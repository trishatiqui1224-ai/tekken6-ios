// Tekken 6 Recompiled - Low-Latency Arcade Fighting Touch Control System (touch_controls.mm)
// Optimized for 60 FPS fighting game inputs (Namco Noir / Vewlix 4-Limb Matrix + 4 Macro Pills)
// Title ID: 4E4D07FC

#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include <SDL3/SDL.h>
#include <SDL3/SDL_joystick.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <vector>

#include <rex/cvar.h>
#include <rex/logging.h>

#include "touch_controls.h"

REXCVAR_DEFINE_BOOL(ios_touch_haptics, true, "Input", "CoreHaptics tactile pulses on fighting strikes");
REXCVAR_DEFINE_DOUBLE(ios_touch_opacity, 0.85, "Input", "Touch controls opacity (0.2 to 1.0)");
REXCVAR_DEFINE_INT32(ios_touch_chord_window_ms, 33, "Input", "Chord window in ms (33 ms = 2 frames at 60 FPS)");

namespace {

// SDL Button indices matching Xbox 360 controller
enum T6ButtonIndex : int {
  kBtnA          = 0,  // LK (3)
  kBtnB          = 1,  // RK (4)
  kBtnX          = 2,  // LP (1)
  kBtnY          = 3,  // RP (2)
  kBtnBack       = 4,  // Select
  kBtnGuide      = 5,
  kBtnStart      = 6,  // Start / Pause
  kBtnLStick     = 7,
  kBtnRStick     = 8,
  kBtnLB         = 9,  // Throw (1+3 / 2+4)
  kBtnRB         = 10, // Rage / Grab
  kBtnDPadUp     = 11,
  kBtnDPadDown   = 12,
  kBtnDPadLeft   = 13,
  kBtnDPadRight  = 14,
};

static SDL_Joystick* g_virtual_pad = nullptr;
static UIImpactFeedbackGenerator* g_haptic_light = nil;
static UIImpactFeedbackGenerator* g_haptic_medium = nil;
static UIImpactFeedbackGenerator* g_haptic_heavy = nil;

void EnsureVirtualPad() {
  if (g_virtual_pad) return;
  SDL_VirtualJoystickDesc desc;
  SDL_INIT_INTERFACE(&desc);
  desc.type = SDL_JOYSTICK_TYPE_GAMEPAD;
  desc.naxes = 6;
  desc.nbuttons = 16;
  desc.button_mask = 0xFFFF;
  desc.axis_mask = 0x3F;

  const SDL_JoystickID jid = SDL_AttachVirtualJoystick(&desc);
  if (jid) {
    g_virtual_pad = SDL_OpenJoystick(jid);
    REXLOG_INFO("[T6-Touch] Virtual arcade gamepad attached (id={})", jid);
  } else {
    REXLOG_ERROR("[T6-Touch] Failed to attach virtual joystick: {}", SDL_GetError());
  }
}

void TriggerHaptic(int level) {
  if (!REXCVAR_GET(ios_touch_haptics)) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (level == 2) {
      if (!g_haptic_heavy) g_haptic_heavy = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
      [g_haptic_heavy impactOccurred];
    } else if (level == 1) {
      if (!g_haptic_medium) g_haptic_medium = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
      [g_haptic_medium impactOccurred];
    } else {
      if (!g_haptic_light) g_haptic_light = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
      [g_haptic_light impactOccurred];
    }
  });
}

static inline void SendButton(int button, bool pressed) {
  EnsureVirtualPad();
  if (g_virtual_pad && button >= 0) {
    SDL_SetJoystickVirtualButton(g_virtual_pad, button, pressed);
  }
}

static inline void SendAxis(int axis, Sint16 value) {
  EnsureVirtualPad();
  if (g_virtual_pad && axis >= 0 && axis < 6) {
    SDL_SetJoystickVirtualAxis(g_virtual_pad, axis, value);
  }
}

}  // namespace

// ---------------------------------------------------------------------------
//  Glassmorphic Visual Effect Button
// ---------------------------------------------------------------------------
@interface T6GlassButton : UIControl
@property(nonatomic, copy) NSString* mainLabel;
@property(nonatomic, copy) NSString* subLabel;
@property(nonatomic, strong) UIColor* accentColor;
@property(nonatomic, assign) int primaryButton;
@property(nonatomic, assign) int secondaryButton; // For chords/macros
@property(nonatomic, assign) BOOL isPill;
@property(nonatomic, assign) BOOL isMacro;
@end

@implementation T6GlassButton {
  UIVisualEffectView* _blurView;
  UILabel* _mainText;
  UILabel* _subText;
  CAShapeLayer* _glowBorder;
}

- (instancetype)initWithFrame:(CGRect)frame
                    mainLabel:(NSString*)main
                     subLabel:(NSString*)sub
                        color:(UIColor*)color
                       isPill:(BOOL)isPill {
  self = [super initWithFrame:frame];
  if (self) {
    _mainLabel = [main copy];
    _subLabel = [sub copy];
    _accentColor = color;
    _isPill = isPill;
    _primaryButton = -1;
    _secondaryButton = -1;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    self.multipleTouchEnabled = YES;

    UIBlurEffect* blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.frame = self.bounds;
    _blurView.userInteractionEnabled = NO;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _blurView.layer.cornerRadius = isPill ? frame.size.height * 0.5f : frame.size.width * 0.5f;
    _blurView.layer.masksToBounds = YES;
    [self addSubview:_blurView];

    _glowBorder = [CAShapeLayer layer];
    _glowBorder.frame = self.bounds;
    _glowBorder.fillColor = [UIColor clearColor].CGColor;
    _glowBorder.strokeColor = _accentColor.CGColor;
    _glowBorder.lineWidth = 1.8f;
    UIBezierPath* path = isPill
        ? [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:frame.size.height * 0.5f]
        : [UIBezierPath bezierPathWithOvalInRect:self.bounds];
    _glowBorder.path = path.CGPath;
    [self.layer addSublayer:_glowBorder];

    _mainText = [[UILabel alloc] initWithFrame:CGRectMake(0, frame.size.height * (sub ? 0.14f : 0.22f),
                                                          frame.size.width, frame.size.height * (sub ? 0.44f : 0.56f))];
    _mainText.text = _mainLabel;
    _mainText.textAlignment = NSTextAlignmentCenter;
    _mainText.textColor = [UIColor whiteColor];
    _mainText.font = [UIFont systemFontOfSize:frame.size.height * (isPill ? 0.36f : 0.34f) weight:UIFontWeightBlack];
    [self addSubview:_mainText];

    if (sub) {
      _subText = [[UILabel alloc] initWithFrame:CGRectMake(0, frame.size.height * 0.56f,
                                                           frame.size.width, frame.size.height * 0.32f)];
      _subText.text = _subLabel;
      _subText.textAlignment = NSTextAlignmentCenter;
      _subText.textColor = _accentColor;
      _subText.font = [UIFont systemFontOfSize:frame.size.height * 0.20f weight:UIFontWeightBold];
      [self addSubview:_subText];
    }
  }
  return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [super touchesBegan:touches withEvent:event];
  self.transform = CGAffineTransformMakeScale(0.92f, 0.92f);
  _glowBorder.lineWidth = 3.2f;
  _glowBorder.strokeColor = [UIColor whiteColor].CGColor;

  if (_isMacro) {
    TriggerHaptic(2);
    if (_primaryButton >= 0) SendButton(_primaryButton, true);
    if (_secondaryButton >= 0) SendButton(_secondaryButton, true);
  } else {
    TriggerHaptic(1);
    if (_primaryButton >= 0) SendButton(_primaryButton, true);
  }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [super touchesEnded:touches withEvent:event];
  self.transform = CGAffineTransformIdentity;
  _glowBorder.lineWidth = 1.8f;
  _glowBorder.strokeColor = _accentColor.CGColor;

  if (_isMacro) {
    // Hold macro for 2 frames before release
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(33 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
      if (self->_primaryButton >= 0) SendButton(self->_primaryButton, false);
      if (self->_secondaryButton >= 0) SendButton(self->_secondaryButton, false);
    });
  } else {
    if (_primaryButton >= 0) SendButton(_primaryButton, false);
  }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self touchesEnded:touches withEvent:event];
}

@end

// ---------------------------------------------------------------------------
//  8-Way Arcade Fighting D-Pad View (Namco Noir / Vewlix Standard)
// ---------------------------------------------------------------------------
@interface T6Arcade8WayDpad : UIView
@property(nonatomic, assign) int activeMask;
@end

@implementation T6Arcade8WayDpad {
  UIVisualEffectView* _blurView;
  CAShapeLayer* _outerRim;
  CAShapeLayer* _activeSectorLayer;
  CGPoint _center;
  CGFloat _radius;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    self.multipleTouchEnabled = YES;
    _center = CGPointMake(frame.size.width * 0.5f, frame.size.height * 0.5f);
    _radius = frame.size.width * 0.46f;
    _activeMask = 0;

    UIBlurEffect* blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.frame = self.bounds;
    _blurView.userInteractionEnabled = NO;
    _blurView.layer.cornerRadius = frame.size.width * 0.5f;
    _blurView.layer.masksToBounds = YES;
    [self addSubview:_blurView];

    _outerRim = [CAShapeLayer layer];
    _outerRim.frame = self.bounds;
    _outerRim.strokeColor = [UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:0.85f].CGColor; // Tournament Gold
    _outerRim.fillColor = [UIColor colorWithWhite:0.08f alpha:0.40f].CGColor;
    _outerRim.lineWidth = 2.0f;
    _outerRim.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 4, 4)].CGPath;
    [self.layer addSublayer:_outerRim];

    _activeSectorLayer = [CAShapeLayer layer];
    _activeSectorLayer.frame = self.bounds;
    _activeSectorLayer.fillColor = [UIColor colorWithRed:0.92f green:0.22f blue:0.26f alpha:0.60f].CGColor; // Crimson Glow
    _activeSectorLayer.strokeColor = [UIColor colorWithRed:0.92f green:0.22f blue:0.26f alpha:0.95f].CGColor;
    _activeSectorLayer.lineWidth = 2.0f;
    [self.layer addSublayer:_activeSectorLayer];

    // Center pivot cap
    UIView* cap = [[UIView alloc] initWithFrame:CGRectMake(_center.x - 22, _center.y - 22, 44, 44)];
    cap.backgroundColor = [UIColor colorWithWhite:0.18f alpha:0.90f];
    cap.layer.cornerRadius = 22;
    cap.layer.borderColor = [UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:0.70f].CGColor;
    cap.layer.borderWidth = 1.5f;
    cap.userInteractionEnabled = NO;
    [self addSubview:cap];
  }
  return self;
}

- (void)updateDirectionFromPoint:(CGPoint)p {
  CGFloat dx = p.x - _center.x;
  CGFloat dy = p.y - _center.y;
  CGFloat dist = std::hypot(dx, dy);

  int mask = 0;
  Sint16 ax = 0, ay = 0;

  if (dist > 14.0f) {
    CGFloat angle = std::atan2(-dy, dx);
    if (angle < 0) angle += 2.0f * M_PI;

    constexpr CGFloat kOctant = M_PI / 4.0f;
    int sector = static_cast<int>((angle + kOctant * 0.5f) / kOctant) % 8;

    switch (sector) {
      case 0: // 6 - Forward / Right
        mask = (1 << kBtnDPadRight);
        ax = 32767; break;
      case 1: // 9 - Up-Forward (d/f EWGF motion)
        mask = (1 << kBtnDPadRight) | (1 << kBtnDPadUp);
        ax = 23170; ay = -23170; break;
      case 2: // 8 - Up
        mask = (1 << kBtnDPadUp);
        ay = -32767; break;
      case 3: // 7 - Up-Back
        mask = (1 << kBtnDPadLeft) | (1 << kBtnDPadUp);
        ax = -23170; ay = -23170; break;
      case 4: // 4 - Back
        mask = (1 << kBtnDPadLeft);
        ax = -32767; break;
      case 5: // 1 - Down-Back (Korean Backdash)
        mask = (1 << kBtnDPadLeft) | (1 << kBtnDPadDown);
        ax = -23170; ay = 23170; break;
      case 6: // 2 - Down
        mask = (1 << kBtnDPadDown);
        ay = 32767; break;
      case 7: // 3 - Down-Forward
        mask = (1 << kBtnDPadRight) | (1 << kBtnDPadDown);
        ax = 23170; ay = 23170; break;
    }
  }

  if (mask != _activeMask) {
    SendButton(kBtnDPadUp, (mask & (1 << kBtnDPadUp)) != 0);
    SendButton(kBtnDPadDown, (mask & (1 << kBtnDPadDown)) != 0);
    SendButton(kBtnDPadLeft, (mask & (1 << kBtnDPadLeft)) != 0);
    SendButton(kBtnDPadRight, (mask & (1 << kBtnDPadRight)) != 0);
    SendAxis(0, ax);
    SendAxis(1, ay);
    _activeMask = mask;
    if (mask != 0) TriggerHaptic(0);
  }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self updateDirectionFromPoint:[[touches anyObject] locationInView:self]];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self updateDirectionFromPoint:[[touches anyObject] locationInView:self]];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  SendButton(kBtnDPadUp, false);
  SendButton(kBtnDPadDown, false);
  SendButton(kBtnDPadLeft, false);
  SendButton(kBtnDPadRight, false);
  SendAxis(0, 0);
  SendAxis(1, 0);
  _activeMask = 0;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self touchesEnded:touches withEvent:event];
}

@end

// ---------------------------------------------------------------------------
//  Master Touch Container View & Menu Gestures
// ---------------------------------------------------------------------------
@interface T6TouchMasterView : UIView
@property(nonatomic, assign) BOOL isFightMode;
@property(nonatomic, strong) UIView* fightControlsContainer;
@property(nonatomic, strong) UIView* menuControlsContainer;
@property(nonatomic, strong) UIButton* modeToggleButton;
@property(nonatomic, strong) UIButton* opacityButton;
@end

@implementation T6TouchMasterView {
  NSArray<NSNumber*>* _opacityLevels;
  NSInteger _opacityIndex;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    self.multipleTouchEnabled = YES;
    self.layer.zPosition = 9999.0f;

    _isFightMode = YES;
    _opacityLevels = @[@1.0f, @0.85f, @0.60f, @0.35f];
    _opacityIndex = 1; // 0.85

    [self setupTopBar];
    [self setupFightControls];
    [self setupMenuControls];
    [self setupCenterGestures];
    [self updateModeVisibility];
  }
  return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView* hit = [super hitTest:point withEvent:event];
  if (hit == self || hit == _fightControlsContainer || hit == _menuControlsContainer) {
    return nil; // Pass touches through to underlying 3D Metal swapchain
  }
  return hit;
}

- (void)setupTopBar {
  CGFloat w = self.bounds.size.width;

  // 1. BACK / Select Pill
  T6GlassButton* btnBack = [[T6GlassButton alloc] initWithFrame:CGRectMake(24, 12, 70, 32)
                                                      mainLabel:@"BACK" subLabel:nil
                                                          color:[UIColor colorWithWhite:0.75f alpha:1.0f]
                                                         isPill:YES];
  btnBack.primaryButton = kBtnBack;
  [self addSubview:btnBack];

  // 2. Mode Toggle Pill: 🥊 FIGHT MODE vs 📋 MENU NAV
  _modeToggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _modeToggleButton.frame = CGRectMake((w - 180) * 0.5f, 12, 180, 32);
  _modeToggleButton.backgroundColor = [UIColor colorWithRed:0.08f green:0.09f blue:0.11f alpha:0.85f];
  _modeToggleButton.layer.cornerRadius = 16.0f;
  _modeToggleButton.layer.borderColor = [UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:0.85f].CGColor;
  _modeToggleButton.layer.borderWidth = 1.5f;
  [_modeToggleButton setTitle:@"🥊 FIGHT MODE" forState:UIControlStateNormal];
  [_modeToggleButton setTitleColor:[UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:1.0f] forState:UIControlStateNormal];
  _modeToggleButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBlack];
  [_modeToggleButton addTarget:self action:@selector(toggleMode) forControlEvents:UIControlEventTouchUpInside];
  [self addSubview:_modeToggleButton];

  // 3. START / Pause Pill
  T6GlassButton* btnStart = [[T6GlassButton alloc] initWithFrame:CGRectMake(w - 170, 12, 75, 32)
                                                       mainLabel:@"START" subLabel:nil
                                                           color:[UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:1.0f]
                                                          isPill:YES];
  btnStart.primaryButton = kBtnStart;
  [self addSubview:btnStart];

  // 4. Opacity Pill
  _opacityButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _opacityButton.frame = CGRectMake(w - 85, 12, 60, 32);
  _opacityButton.backgroundColor = [UIColor colorWithWhite:0.10f alpha:0.75f];
  _opacityButton.layer.cornerRadius = 16.0f;
  _opacityButton.layer.borderColor = [UIColor colorWithWhite:0.40f alpha:0.8f].CGColor;
  _opacityButton.layer.borderWidth = 1.0f;
  [_opacityButton setTitle:@"👁 85%" forState:UIControlStateNormal];
  [_opacityButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  _opacityButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
  [_opacityButton addTarget:self action:@selector(cycleOpacity) forControlEvents:UIControlEventTouchUpInside];
  [self addSubview:_opacityButton];
}

- (void)setupFightControls {
  CGFloat w = self.bounds.size.width;
  CGFloat h = self.bounds.size.height;

  _fightControlsContainer = [[UIView alloc] initWithFrame:self.bounds];
  _fightControlsContainer.backgroundColor = [UIColor clearColor];
  [self addSubview:_fightControlsContainer];

  // 1. Arcade 8-Way D-Pad
  CGFloat dpadSize = std::min(w, h) * 0.44f;
  T6Arcade8WayDpad* dpad = [[T6Arcade8WayDpad alloc] initWithFrame:CGRectMake(36, h - dpadSize - 30, dpadSize, dpadSize)];
  [_fightControlsContainer addSubview:dpad];

  // 2. 4-Limb Face Buttons (1/LP, 2/RP, 3/LK, 4/RK)
  CGFloat btnSize = std::min(w, h) * 0.17f;
  CGFloat rightBase = w - 48;
  CGFloat bottomBase = h - 32;

  // 1 (LP / X) - Blue/Cyan
  T6GlassButton* btn1 = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 2.5f, bottomBase - btnSize * 2.1f, btnSize, btnSize)
                                                   mainLabel:@"1" subLabel:@"LP / X"
                                                       color:[UIColor colorWithRed:0.22f green:0.71f blue:1.0f alpha:1.0f]
                                                      isPill:NO];
  btn1.primaryButton = kBtnX;
  [_fightControlsContainer addSubview:btn1];

  // 2 (RP / Y) - Tournament Gold
  T6GlassButton* btn2 = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 1.35f, bottomBase - btnSize * 2.3f, btnSize, btnSize)
                                                   mainLabel:@"2" subLabel:@"RP / Y"
                                                       color:[UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:1.0f]
                                                      isPill:NO];
  btn2.primaryButton = kBtnY;
  [_fightControlsContainer addSubview:btn2];

  // 3 (LK / A) - Emerald Green
  T6GlassButton* btn3 = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 2.65f, bottomBase - btnSize * 0.95f, btnSize, btnSize)
                                                   mainLabel:@"3" subLabel:@"LK / A"
                                                       color:[UIColor colorWithRed:0.22f green:0.90f blue:0.30f alpha:1.0f]
                                                      isPill:NO];
  btn3.primaryButton = kBtnA;
  [_fightControlsContainer addSubview:btn3];

  // 4 (RK / B) - Crimson Red
  T6GlassButton* btn4 = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 1.5f, bottomBase - btnSize * 1.15f, btnSize, btnSize)
                                                   mainLabel:@"4" subLabel:@"RK / B"
                                                       color:[UIColor colorWithRed:0.92f green:0.22f blue:0.26f alpha:1.0f]
                                                      isPill:NO];
  btn4.primaryButton = kBtnB;
  [_fightControlsContainer addSubview:btn4];

  // 3. 4 Macro Pills: [1+2], [3+4], [1+4], [2+3]
  CGFloat pillW = btnSize * 0.95f;
  CGFloat pillH = btnSize * 0.44f;

  // Macro 1+2 (X+Y)
  T6GlassButton* m12 = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 2.2f, bottomBase - btnSize * 2.95f, pillW, pillH)
                                                  mainLabel:@"1+2" subLabel:nil
                                                      color:[UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:1.0f]
                                                     isPill:YES];
  m12.isMacro = YES;
  m12.primaryButton = kBtnX;
  m12.secondaryButton = kBtnY;
  [_fightControlsContainer addSubview:m12];

  // Macro 3+4 (A+B)
  T6GlassButton* m34 = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 1.05f, bottomBase - btnSize * 2.95f, pillW, pillH)
                                                  mainLabel:@"3+4" subLabel:nil
                                                      color:[UIColor colorWithRed:0.92f green:0.22f blue:0.26f alpha:1.0f]
                                                     isPill:YES];
  m34.isMacro = YES;
  m34.primaryButton = kBtnA;
  m34.secondaryButton = kBtnB;
  [_fightControlsContainer addSubview:m34];

  // Macro 1+4 (X+B)
  T6GlassButton* m14 = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 0.35f, bottomBase - btnSize * 2.1f, pillW, pillH)
                                                  mainLabel:@"1+4" subLabel:nil
                                                      color:[UIColor colorWithRed:0.80f green:0.30f blue:1.0f alpha:1.0f]
                                                     isPill:YES];
  m14.isMacro = YES;
  m14.primaryButton = kBtnX;
  m14.secondaryButton = kBtnB;
  [_fightControlsContainer addSubview:m14];

  // Macro 2+3 (Y+A)
  T6GlassButton* m23 = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 0.35f, bottomBase - btnSize * 1.15f, pillW, pillH)
                                                  mainLabel:@"2+3" subLabel:nil
                                                      color:[UIColor colorWithRed:0.30f green:0.85f blue:0.80f alpha:1.0f]
                                                     isPill:YES];
  m23.isMacro = YES;
  m23.primaryButton = kBtnY;
  m23.secondaryButton = kBtnA;
  [_fightControlsContainer addSubview:m23];

  // Shoulder buttons: L1 (Throw), R1 (Rage)
  T6GlassButton* btnL1 = [[T6GlassButton alloc] initWithFrame:CGRectMake(36, 56, 85, 34)
                                                    mainLabel:@"L1" subLabel:@"THROW"
                                                        color:[UIColor colorWithWhite:0.80f alpha:1.0f]
                                                       isPill:YES];
  btnL1.primaryButton = kBtnLB;
  [_fightControlsContainer addSubview:btnL1];

  T6GlassButton* btnR1 = [[T6GlassButton alloc] initWithFrame:CGRectMake(w - 121, 56, 85, 34)
                                                    mainLabel:@"R1" subLabel:@"RAGE"
                                                        color:[UIColor colorWithRed:0.92f green:0.22f blue:0.26f alpha:1.0f]
                                                       isPill:YES];
  btnR1.primaryButton = kBtnRB;
  [_fightControlsContainer addSubview:btnR1];
}

- (void)setupMenuControls {
  CGFloat w = self.bounds.size.width;
  CGFloat h = self.bounds.size.height;

  _menuControlsContainer = [[UIView alloc] initWithFrame:self.bounds];
  _menuControlsContainer.backgroundColor = [UIColor clearColor];
  [self addSubview:_menuControlsContainer];

  // Cardinal Cross D-Pad on Left
  CGFloat crossSize = std::min(w, h) * 0.40f;
  T6Arcade8WayDpad* cross = [[T6Arcade8WayDpad alloc] initWithFrame:CGRectMake(40, h - crossSize - 35, crossSize, crossSize)];
  [_menuControlsContainer addSubview:cross];

  // Classic Xbox A/B/X/Y on Right
  CGFloat btnSize = std::min(w, h) * 0.16f;
  CGFloat rightBase = w - 55;
  CGFloat bottomBase = h - 35;

  // A: Confirm (Green)
  T6GlassButton* btnA = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 1.8f, bottomBase - btnSize * 0.9f, btnSize, btnSize)
                                                   mainLabel:@"A" subLabel:@"CONFIRM"
                                                       color:[UIColor colorWithRed:0.22f green:0.90f blue:0.30f alpha:1.0f]
                                                      isPill:NO];
  btnA.primaryButton = kBtnA;
  [_menuControlsContainer addSubview:btnA];

  // B: Cancel (Red)
  T6GlassButton* btnB = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 0.8f, bottomBase - btnSize * 1.6f, btnSize, btnSize)
                                                   mainLabel:@"B" subLabel:@"BACK"
                                                       color:[UIColor colorWithRed:0.92f green:0.22f blue:0.26f alpha:1.0f]
                                                      isPill:NO];
  btnB.primaryButton = kBtnB;
  [_menuControlsContainer addSubview:btnB];

  // X: Option (Blue)
  T6GlassButton* btnX = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 2.8f, bottomBase - btnSize * 1.6f, btnSize, btnSize)
                                                   mainLabel:@"X" subLabel:@"OPTION"
                                                       color:[UIColor colorWithRed:0.22f green:0.71f blue:1.0f alpha:1.0f]
                                                      isPill:NO];
  btnX.primaryButton = kBtnX;
  [_menuControlsContainer addSubview:btnX];

  // Y: Menu (Yellow)
  T6GlassButton* btnY = [[T6GlassButton alloc] initWithFrame:CGRectMake(rightBase - btnSize * 1.8f, bottomBase - btnSize * 2.3f, btnSize, btnSize)
                                                   mainLabel:@"Y" subLabel:@"INFO"
                                                       color:[UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:1.0f]
                                                      isPill:NO];
  btnY.primaryButton = kBtnY;
  [_menuControlsContainer addSubview:btnY];
}

- (void)setupCenterGestures {
  // Swipe Gestures for Menu Navigation
  UISwipeGestureRecognizer* swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
  swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
  [self addGestureRecognizer:swipeUp];

  UISwipeGestureRecognizer* swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
  swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
  [self addGestureRecognizer:swipeDown];

  UISwipeGestureRecognizer* swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
  swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
  [self addGestureRecognizer:swipeLeft];

  UISwipeGestureRecognizer* swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
  swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
  [self addGestureRecognizer:swipeRight];

  // Double-tap for A (Confirm)
  UITapGestureRecognizer* doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
  doubleTap.numberOfTapsRequired = 2;
  [self addGestureRecognizer:doubleTap];
}

- (void)handleSwipe:(UISwipeGestureRecognizer*)swipe {
  if (_isFightMode) return;
  int btn = -1;
  switch (swipe.direction) {
    case UISwipeGestureRecognizerDirectionUp:    btn = kBtnDPadUp; break;
    case UISwipeGestureRecognizerDirectionDown:  btn = kBtnDPadDown; break;
    case UISwipeGestureRecognizerDirectionLeft:  btn = kBtnDPadLeft; break;
    case UISwipeGestureRecognizerDirectionRight: btn = kBtnDPadRight; break;
  }
  if (btn >= 0) {
    TriggerHaptic(0);
    SendButton(btn, true);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
      SendButton(btn, false);
    });
  }
}

- (void)handleDoubleTap:(UITapGestureRecognizer*)tap {
  if (_isFightMode) return;
  TriggerHaptic(1);
  SendButton(kBtnA, true);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
    SendButton(kBtnA, false);
  });
}

- (void)toggleMode {
  _isFightMode = !_isFightMode;
  TriggerHaptic(1);
  [self updateModeVisibility];
}

- (void)updateModeVisibility {
  [UIView animateWithDuration:0.2 animations:^{
    if (self->_isFightMode) {
      [self->_modeToggleButton setTitle:@"🥊 FIGHT MODE" forState:UIControlStateNormal];
      [self->_modeToggleButton setTitleColor:[UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:1.0f] forState:UIControlStateNormal];
      self->_modeToggleButton.layer.borderColor = [UIColor colorWithRed:0.96f green:0.78f blue:0.26f alpha:0.85f].CGColor;
      self->_fightControlsContainer.alpha = 1.0f;
      self->_menuControlsContainer.alpha = 0.0f;
    } else {
      [self->_modeToggleButton setTitle:@"📋 MENU NAV" forState:UIControlStateNormal];
      [self->_modeToggleButton setTitleColor:[UIColor colorWithRed:0.22f green:0.71f blue:1.0f alpha:1.0f] forState:UIControlStateNormal];
      self->_modeToggleButton.layer.borderColor = [UIColor colorWithRed:0.22f green:0.71f blue:1.0f alpha:0.85f].CGColor;
      self->_fightControlsContainer.alpha = 0.0f;
      self->_menuControlsContainer.alpha = 1.0f;
    }
  }];
}

- (void)cycleOpacity {
  _opacityIndex = (_opacityIndex + 1) % _opacityLevels.count;
  float val = [_opacityLevels[_opacityIndex] floatValue];
  [self setOpacity:val];
}

- (void)setOpacity:(float)opacity {
  self.alpha = opacity;
  int pct = static_cast<int>(opacity * 100);
  [_opacityButton setTitle:[NSString stringWithFormat:@"👁 %d%%", pct] forState:UIControlStateNormal];
}

@end

// ---------------------------------------------------------------------------
//  Public Touch API
// ---------------------------------------------------------------------------
static T6TouchMasterView* g_touch_view = nil;
static UILabel* g_fps_hud = nil;

namespace tekken6::touch {

void Install() {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_touch_view) return;

    UIWindow* window = nil;
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
      if (w.isKeyWindow) { window = w; break; }
    }
    if (!window && UIApplication.sharedApplication.windows.count > 0) {
      window = UIApplication.sharedApplication.windows.firstObject;
    }
    if (!window) return;

    EnsureVirtualPad();
    g_touch_view = [[T6TouchMasterView alloc] initWithFrame:window.bounds];
    g_touch_view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:g_touch_view];
    [window bringSubviewToFront:g_touch_view];

    // Physical gamepad notifications
    [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification*) {
      REXLOG_INFO("[T6-Touch] Physical gamepad connected; auto-hiding touch overlay.");
      SetVisible(false);
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidDisconnectNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification*) {
      if (GCController.controllers.count == 0) {
        REXLOG_INFO("[T6-Touch] Gamepad disconnected; restoring touch overlay.");
        SetVisible(true);
      }
    }];

    REXLOG_INFO("[T6-Touch] Glassmorphic Arcade Fighting touch controls installed successfully.");
  });
}

void InstallFpsCounter() {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!g_touch_view || g_fps_hud) return;
    g_fps_hud = [[UILabel alloc] initWithFrame:CGRectMake(110, 14, 150, 28)];
    g_fps_hud.backgroundColor = [UIColor colorWithRed:0.04f green:0.05f blue:0.07f alpha:0.80f];
    g_fps_hud.layer.cornerRadius = 6.0f;
    g_fps_hud.layer.masksToBounds = YES;
    g_fps_hud.layer.borderColor = [UIColor colorWithRed:0.22f green:0.71f blue:1.0f alpha:0.8f].CGColor;
    g_fps_hud.layer.borderWidth = 1.0f;
    g_fps_hud.textColor = [UIColor colorWithRed:0.22f green:0.71f blue:1.0f alpha:1.0f];
    g_fps_hud.font = [UIFont monospacedDigitSystemFontOfSize:12.0f weight:UIFontWeightBold];
    g_fps_hud.textAlignment = NSTextAlignmentCenter;
    g_fps_hud.text = @"60.0 FPS | 16.6ms";
    [g_touch_view addSubview:g_fps_hud];
  });
}

void SetVisible(bool visible) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_touch_view) g_touch_view.hidden = !visible;
  });
}

bool IsVisible() {
  return g_touch_view && !g_touch_view.hidden;
}

void BringToFront() {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_touch_view && g_touch_view.superview) {
      [g_touch_view.superview bringSubviewToFront:g_touch_view];
    }
  });
}

void SetFightMode(bool fight_mode) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_touch_view && g_touch_view.isFightMode != fight_mode) {
      [g_touch_view toggleMode];
    }
  });
}

bool IsFightMode() {
  return g_touch_view && g_touch_view.isFightMode;
}

void SetOpacity(float opacity) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_touch_view) [g_touch_view setOpacity:opacity];
  });
}

void CycleOpacity() {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_touch_view) [g_touch_view cycleOpacity];
  });
}

}  // namespace tekken6::touch
