// Tekken 6 Recompiled - Low-Latency iOS Audio Output (CoreAudio RemoteIO)
// Title ID: 4E4D07FC

#pragma once

#include <rex/audio/audio_driver.h>
#include <rex/audio/audio_system.h>
#include <rex/thread.h>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>

typedef struct OpaqueAudioComponentInstance* AudioComponentInstance;

namespace rex::audio::ios {

void PrepareAudioSession();

class CoreAudioDriver final : public AudioDriver {
 public:
  CoreAudioDriver(memory::Memory* memory, rex::thread::Semaphore* semaphore);
  ~CoreAudioDriver() override;

  bool Initialize();
  void Shutdown();

  void Pause();
  void Resume();

  void SubmitFrame(uint32_t samples_ptr) override;
  void Render(float* out, uint32_t frames);

 private:
  bool OpenUnit();
  void CloseUnit();

  static constexpr size_t kSamplesPerChannel = 256;
  static constexpr size_t kOutputChannels = 2;
  static constexpr size_t kFloatsPerBlock = kSamplesPerChannel * kOutputChannels;

  static constexpr size_t kRingBlocks = 64;
  static constexpr size_t kCapacity = kRingBlocks * kFloatsPerBlock;
  static_assert((kCapacity & (kCapacity - 1)) == 0, "capacity must be a power of 2");
  static constexpr size_t kMask = kCapacity - 1;

  rex::thread::Semaphore* semaphore_ = nullptr;
  AudioComponentInstance unit_ = nullptr;
  std::atomic<bool> is_running_{false};
  bool started_ = false;

  std::unique_ptr<float[]> ring_;
  alignas(64) std::atomic<size_t> write_{0};
  alignas(64) std::atomic<size_t> read_{0};

  size_t consumed_ = 0;

  std::atomic<uint32_t> underruns_{0}, silent_frames_{0}, refused_permits_{0};
  uint32_t dropped_full_ = 0, trimmed_ = 0;
  std::atomic<uint32_t> lowest_floats_{UINT32_MAX};
  uint64_t last_submit_ns_ = 0, worst_submit_gap_ns_ = 0, stats_since_ns_ = 0;
  uint32_t submitted_ = 0;

  float limiter_gain_ = 1.0f, deepest_gain_ = 1.0f;
  uint32_t silent_blocks_ = 0, silent_run_ = 0, longest_silent_run_ = 0, sudden_drops_ = 0;
  float last_block_peak_ = 0.0f;
  uint64_t limited_samples_ = 0;

  void* interruption_observer_ = nullptr;
  std::mutex control_;
};

class CoreAudioSystem final : public AudioSystem {
 public:
  explicit CoreAudioSystem(runtime::FunctionDispatcher* function_dispatcher);
  ~CoreAudioSystem() override;

  static bool IsAvailable() { return true; }
  static std::unique_ptr<AudioSystem> Create(runtime::FunctionDispatcher* function_dispatcher) {
    return std::make_unique<CoreAudioSystem>(function_dispatcher);
  }

  X_STATUS CreateDriver(size_t index, rex::thread::Semaphore* semaphore,
                        AudioDriver** out_driver) override;
  void DestroyDriver(AudioDriver* driver) override;
};

}  // namespace rex::audio::ios
