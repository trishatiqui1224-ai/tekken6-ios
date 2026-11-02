// Tekken 6 Recompiled - Low-Latency iOS Audio Output (CoreAudio RemoteIO)
// Title ID: 4E4D07FC

#include "coreaudio_driver.h"

#import <AVFoundation/AVFoundation.h>
#include <AudioToolbox/AudioToolbox.h>
#include <SDL3/SDL_events.h>

#include <rex/logging.h>
#include <rex/system/xmemory.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <mutex>
#include <pthread.h>
#include <time.h>

namespace rex::audio::ios {

namespace {

constexpr double kSampleRate = 48000.0;

constexpr float kCenterGain = 0.7071f;
constexpr float kSurroundGain = 0.7071f;
constexpr float kLfeGain = 0.5f;

inline float LoadBEFloat(uint32_t raw_be) {
  const uint32_t le = __builtin_bswap32(raw_be);
  float f;
  std::memcpy(&f, &le, sizeof(float));
  return f;
}

OSStatus RenderCallback(void* ref, AudioUnitRenderActionFlags* /*flags*/,
                        const AudioTimeStamp* /*time*/, UInt32 /*bus*/, UInt32 frames,
                        AudioBufferList* data) {
  auto* self = static_cast<CoreAudioDriver*>(ref);
  self->Render(static_cast<float*>(data->mBuffers[0].mData), frames);
  return noErr;
}

bool SDLCALL EventWatch(void* userdata, SDL_Event* event) {
  auto* driver = static_cast<CoreAudioDriver*>(userdata);
  if (event->type == SDL_EVENT_WILL_ENTER_BACKGROUND) {
    driver->Pause();
  } else if (event->type == SDL_EVENT_DID_ENTER_FOREGROUND) {
    driver->Resume();
  }
  return true;
}

dispatch_semaphore_t session_ready = dispatch_semaphore_create(0);
std::atomic<bool> session_activated{false};

void ActivateSessionOnce() {
  static std::once_flag once;
  std::call_once(once, [] {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      AVAudioSession* session = AVAudioSession.sharedInstance;
      NSError* error = nil;
      [session setCategory:AVAudioSessionCategorySoloAmbient error:&error];
      [session setPreferredSampleRate:kSampleRate error:nil];
      [session setPreferredIOBufferDuration:256.0 / kSampleRate error:nil];
      const bool active = [session setActive:YES error:&error];
      if (!active) {
        REXLOG_WARN("[coreaudio] AVAudioSession setActive failed: {}", error.localizedDescription.UTF8String);
      }
      session_activated = true;
      dispatch_semaphore_signal(session_ready);
    });
  });
}

void ConfigureSession() {
  ActivateSessionOnce();
  if (!session_activated &&
      dispatch_semaphore_wait(session_ready, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) != 0) {
    REXLOG_WARN("[coreaudio] Audio session activating timeout: continuing");
    return;
  }
}

}  // namespace

void PrepareAudioSession() { ActivateSessionOnce(); }

CoreAudioDriver::CoreAudioDriver(memory::Memory* memory, rex::thread::Semaphore* semaphore)
    : AudioDriver(memory), semaphore_(semaphore), ring_(new float[kCapacity]()) {}

CoreAudioDriver::~CoreAudioDriver() { Shutdown(); }

bool CoreAudioDriver::OpenUnit() {
  AudioComponentDescription desc{};
  desc.componentType = kAudioUnitType_Output;
  desc.componentSubType = kAudioUnitSubType_RemoteIO;
  desc.componentManufacturer = kAudioUnitManufacturer_Apple;
  AudioComponent component = AudioComponentFindNext(nullptr, &desc);
  if (!component || AudioComponentInstanceNew(component, &unit_) != noErr || !unit_) {
    REXLOG_ERROR("[coreaudio] cannot create RemoteIO unit");
    unit_ = nullptr;
    return false;
  }

  AudioStreamBasicDescription format{};
  format.mSampleRate = kSampleRate;
  format.mFormatID = kAudioFormatLinearPCM;
  format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  format.mChannelsPerFrame = kOutputChannels;
  format.mBitsPerChannel = 32;
  format.mFramesPerPacket = 1;
  format.mBytesPerFrame = sizeof(float) * kOutputChannels;
  format.mBytesPerPacket = format.mBytesPerFrame;
  OSStatus s = AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input, 0, &format, sizeof(format));
  if (s == noErr) {
    AURenderCallbackStruct callback{RenderCallback, this};
    s = AudioUnitSetProperty(unit_, kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0, &callback, sizeof(callback));
  }
  if (s == noErr) {
    s = AudioUnitInitialize(unit_);
  }
  if (s == noErr) {
    s = AudioOutputUnitStart(unit_);
  }
  if (s != noErr) {
    REXLOG_ERROR("[coreaudio] RemoteIO start failed: OSStatus {}", static_cast<int>(s));
    AudioComponentInstanceDispose(unit_);
    unit_ = nullptr;
    return false;
  }
  started_ = true;
  REXLOG_INFO("[coreaudio] RemoteIO started: 48 kHz stereo float");
  return true;
}

void CoreAudioDriver::CloseUnit() {
  if (unit_) {
    AudioOutputUnitStop(unit_);
    AudioUnitUninitialize(unit_);
    AudioComponentInstanceDispose(unit_);
    unit_ = nullptr;
  }
  started_ = false;
}

bool CoreAudioDriver::Initialize() {
  ConfigureSession();
  {
    std::lock_guard<std::mutex> lock(control_);
    if (!OpenUnit()) {
      return false;
    }
  }
  is_running_.store(true, std::memory_order_release);
  SDL_AddEventWatch(EventWatch, this);

  id token = [NSNotificationCenter.defaultCenter
      addObserverForName:AVAudioSessionInterruptionNotification
                  object:AVAudioSession.sharedInstance
                   queue:nil
              usingBlock:^(NSNotification* note) {
                const auto type = static_cast<AVAudioSessionInterruptionType>(
                    [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue]);
                if (type == AVAudioSessionInterruptionTypeBegan) {
                  Pause();
                } else {
                  [AVAudioSession.sharedInstance setActive:YES error:nil];
                  Resume();
                }
              }];
  interruption_observer_ = (__bridge_retained void*)token;
  return true;
}

void CoreAudioDriver::Pause() {
  std::lock_guard<std::mutex> lock(control_);
  if (unit_ && started_) {
    AudioOutputUnitStop(unit_);
    started_ = false;
  }
}

void CoreAudioDriver::Resume() {
  std::lock_guard<std::mutex> lock(control_);
  if (unit_ && !started_ && is_running_.load(std::memory_order_acquire)) {
    const OSStatus s = AudioOutputUnitStart(unit_);
    started_ = (s == noErr);
  }
}

void CoreAudioDriver::Shutdown() {
  if (!is_running_.exchange(false, std::memory_order_acq_rel)) {
    return;
  }
  SDL_RemoveEventWatch(EventWatch, this);
  if (interruption_observer_) {
    id token = (__bridge_transfer id)interruption_observer_;
    interruption_observer_ = nullptr;
    [NSNotificationCenter.defaultCenter removeObserver:token];
  }
  if (semaphore_) {
    semaphore_->Release(16, nullptr);
  }
  std::lock_guard<std::mutex> lock(control_);
  CloseUnit();
}

void CoreAudioDriver::SubmitFrame(uint32_t samples_ptr) {
  if (!is_running_.load(std::memory_order_relaxed)) {
    return;
  }
  uint8_t* frame_data = nullptr;
  if (memory_) {
    frame_data = memory_->TranslateVirtual<uint8_t*>(samples_ptr);
    if (!frame_data) {
      frame_data = TranslatePhysical(samples_ptr);
    }
  }
  if (!frame_data) {
    return;
  }

  const size_t w = write_.load(std::memory_order_relaxed);
  const size_t r = read_.load(std::memory_order_acquire);
  if (kCapacity - (w - r) < kFloatsPerBlock) {
    ++dropped_full_;
    return;
  }
  constexpr size_t kTargetBlocks = 12;
  if (w - r >= kTargetBlocks * kFloatsPerBlock) {
    ++trimmed_;
    return;
  }

  const uint32_t* src = reinterpret_cast<const uint32_t*>(frame_data);
  const uint32_t* ch_fl = src + 0 * kSamplesPerChannel;
  const uint32_t* ch_fr = src + 1 * kSamplesPerChannel;
  const uint32_t* ch_c = src + 2 * kSamplesPerChannel;
  const uint32_t* ch_lfe = src + 3 * kSamplesPerChannel;
  const uint32_t* ch_bl = src + 4 * kSamplesPerChannel;
  const uint32_t* ch_br = src + 5 * kSamplesPerChannel;

  constexpr float kCeiling = 0.98f;
  const float release = 1.0f - std::exp(-1.0f / (0.1f * float(kSampleRate)));
  float* dst = ring_.get() + (w & kMask);

  for (size_t i = 0; i < kSamplesPerChannel; ++i) {
    const float c = LoadBEFloat(ch_c[i]) * kCenterGain;
    const float lfe = LoadBEFloat(ch_lfe[i]) * kLfeGain;
    const float mid = c + lfe;
    const float left = LoadBEFloat(ch_fl[i]) + mid + LoadBEFloat(ch_bl[i]) * kSurroundGain;
    const float right = LoadBEFloat(ch_fr[i]) + mid + LoadBEFloat(ch_br[i]) * kSurroundGain;
    const float peak = std::max(std::fabs(left), std::fabs(right));
    if (peak * limiter_gain_ > kCeiling) {
      limiter_gain_ = kCeiling / peak;
    } else {
      limiter_gain_ += (1.0f - limiter_gain_) * release;
    }
    dst[i * 2 + 0] = std::clamp(left * limiter_gain_, -1.0f, 1.0f);
    dst[i * 2 + 1] = std::clamp(right * limiter_gain_, -1.0f, 1.0f);
  }

  write_.store(w + kFloatsPerBlock, std::memory_order_release);
}

void CoreAudioDriver::Render(float* out, uint32_t frames) {
  if (frames == 0) {
    return;
  }
  const size_t wanted = size_t(frames) * kOutputChannels;
  const size_t r = read_.load(std::memory_order_relaxed);
  const size_t w = write_.load(std::memory_order_acquire);
  const size_t n = std::min(w - r, wanted);

  const size_t pos = r & kMask;
  const size_t first = std::min(n, kCapacity - pos);
  std::memcpy(out, ring_.get() + pos, first * sizeof(float));
  if (n > first) {
    std::memcpy(out + first, ring_.get(), (n - first) * sizeof(float));
  }
  if (n < wanted) {
    std::memset(out + n, 0, (wanted - n) * sizeof(float));
    underruns_.fetch_add(1, std::memory_order_relaxed);
    silent_frames_.fetch_add(uint32_t((wanted - n) / kOutputChannels), std::memory_order_relaxed);
  }
  read_.store(r + n, std::memory_order_release);

  if (semaphore_) {
    consumed_ += frames;
    const size_t rel = consumed_ / kSamplesPerChannel;
    if (rel > 0) {
      consumed_ -= rel * kSamplesPerChannel;
      semaphore_->Release(int32_t(rel), nullptr);
    }
  }
}

// ---------------------------------------------------------------------------
//  CoreAudioSystem
// ---------------------------------------------------------------------------
CoreAudioSystem::CoreAudioSystem(runtime::FunctionDispatcher* function_dispatcher)
    : AudioSystem(function_dispatcher) {}

CoreAudioSystem::~CoreAudioSystem() = default;

X_STATUS CoreAudioSystem::CreateDriver(size_t index, rex::thread::Semaphore* semaphore,
                                       AudioDriver** out_driver) {
  auto driver = std::make_unique<CoreAudioDriver>(memory_, semaphore);
  if (!driver->Initialize()) {
    REXLOG_ERROR("[coreaudio] cannot initialize driver for index {}", index);
    return X_STATUS_UNSUCCESSFUL;
  }
  *out_driver = driver.release();
  return X_STATUS_SUCCESS;
}

void CoreAudioSystem::DestroyDriver(AudioDriver* driver) { delete driver; }

}  // namespace rex::audio::ios

