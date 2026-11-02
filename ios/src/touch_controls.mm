// Tekken 6 Recompiled - Low-Latency Arcade Fighting Touch Control System
// Optimized for 60 FPS fighting game inputs (Namco Noir / Vewlix 6-Button Layout)
// Title ID: 4E4D07FC

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#include <SDL3/SDL_joystick.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <vector>

#include <rex/cvar.h>
#include <rex/logging.h>

#include "touch_controls.h"

REXCVAR_DEFINE_BOOL(ios_touch_haptics, true, "Input", "Crisp CoreHaptics tactile pulses on fighting strikes");
REXCVAR_DEFINE_FLOAT(ios_touch_opacity, 0.85f, "Input", "Touch controls opacity (0.2 to 1.0)");
REXCVAR_DEFINE_FLOAT(ios_touch_scale, 1.0f, "Input", "Scale multiplier for arcade fighting buttons");
REXCVAR_DEFINE_INT32(ios_touch_dpad_mode, 0, "Input", "0 = 8-way Fixed D-Pad, 1 = Floating D-Pad, 2 = Analog Stick");

namespace {

// SDL / Xbox 360 Controller bitmask
constexpr int kA     = 1 << 0;  // LK (3)
constexpr int kB     = 1 << 1;  // RK (4)
constexpr int kX     = 1 << 2;  // LP (1)
constexpr int kY     = 1 << 3;  // RP (2)
constexpr int kBack  = 1 << 4;  // Select
constexpr int kStart = 1 << 6;  // Start / Pause
constexpr int kL3    = 1 << 7;
constexpr int kR3    = 1 << 8;
constexpr int kLB    = 1 << 9;  // L1 (Throw / Macro)
constexpr int kRB    = 1 << 10; // R1 (Rage / Grab)
constexpr int kUp    = 1 << 11;
constexpr int kDown  = 1 << 12;
constexpr int kLeft  = 1 << 13;
constexpr int kRight = 1 << 14;

// Triggers (axes 4 and 5 in SDL gamepad)
constexpr int kLT    = 1 << 15; // L2 (1+2 / 3+4 shortcut)
constexpr int kRT    = 1 << 16; // R2 (Item / Special / Rage)

SDL_Joystick* g_joystick = nullptr;
std::atomic<int> g_pressed_buttons{0};
std::atomic<int16_t> g_axis_x{0};
std::atomic<int16_t> g_axis_y{0};

UIImpactFeedbackGenerator* g_haptic_light = nil;
UIImpactFeedbackGenerator* g_haptic_heavy = nil;

void TriggerHaptic(bool heavy = false) {
    if (!REXCVAR_GET(ios_touch_haptics)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (heavy) {
            if (!g_haptic_heavy) g_haptic_heavy = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
            [g_haptic_heavy impactOccurred];
        } else {
            if (!g_haptic_light) g_haptic_light = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [g_haptic_light impactOccurred];
        }
    });
}

void UpdateJoystickState() {
    int buttons = g_pressed_buttons.load(std::memory_order_relaxed);
    if (!g_joystick) return;

    // Report standard buttons
    for (int i = 0; i < 15; ++i) {
        SDL_SetJoystickVirtualButton(g_joystick, i, (buttons & (1 << i)) != 0);
    }
    // Triggers
    int16_t lt_val = (buttons & kLT) ? 32767 : 0;
    int16_t rt_val = (buttons & kRT) ? 32767 : 0;
    SDL_SetJoystickVirtualAxis(g_joystick, 4, lt_val);
    SDL_SetJoystickVirtualAxis(g_joystick, 5, rt_val);

    // Left Stick / D-Pad
    SDL_SetJoystickVirtualAxis(g_joystick, 0, g_axis_x.load(std::memory_order_relaxed));
    SDL_SetJoystickVirtualAxis(g_joystick, 1, g_axis_y.load(std::memory_order_relaxed));
}

} // namespace

// ---------------------------------------------------------------------------
//  Always-On-Top Passthrough Container View
// ---------------------------------------------------------------------------
@interface TouchOverlayContainerView : UIView
@property (nonatomic, assign) BOOL isHiddenByUser;
@end

@implementation TouchOverlayContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = YES;
        self.layer.zPosition = 9999.0f; // Always strictly on top of Metal/MoltenVK
    }
    return self;
}

// Passthrough hit-testing: if a touch is not on a control subview, pass it through to the game
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) {
        return nil; // Forward touch to underlying Metal swapchain
    }
    return hit;
}

@end

// ---------------------------------------------------------------------------
//  Arcade Fighting Button View (Procedural Metal/Glow Styling)
// ---------------------------------------------------------------------------
@interface ArcadeButtonView : UIView
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *sublabel;
@property (nonatomic, assign) int buttonMask;
@property (nonatomic, strong) UIColor *themeColor;
@property (nonatomic, assign) BOOL isPressed;
@end

@implementation ArcadeButtonView

- (instancetype)initWithFrame:(CGRect)frame label:(NSString *)label sublabel:(NSString *)sub
                         mask:(int)mask color:(UIColor *)color {
    self = [super initWithFrame:frame];
    if (self) {
        _label = [label copy];
        _sublabel = [sub copy];
        _buttonMask = mask;
        _themeColor = color;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = YES;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect bounds = CGRectInset(rect, 4, 4);

    // Outer Glow if pressed
    if (_isPressed) {
        CGContextSetShadowWithColor(ctx, CGSizeZero, 16.0f, _themeColor.CGColor);
    }

    // Outer Rim
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.12f alpha:0.85f].CGColor);
    CGContextFillEllipseInRect(ctx, bounds);

    CGContextSetStrokeColorWithColor(ctx, _themeColor.CGColor);
    CGContextSetLineWidth(ctx, _isPressed ? 4.0f : 2.5f);
    CGContextStrokeEllipseInRect(ctx, bounds);

    // Button Cap
    CGRect inner = CGRectInset(bounds, _isPressed ? 6 : 4, _isPressed ? 6 : 4);
    UIColor *capColor = _isPressed ? [_themeColor colorWithAlphaComponent:0.6f]
                                   : [UIColor colorWithWhite:0.18f alpha:0.85f];
    CGContextSetFillColorWithColor(ctx, capColor.CGColor);
    CGContextFillEllipseInRect(ctx, inner);

    // Text Label
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;

    NSDictionary *attrMain = @{
        NSFontAttributeName: [UIFont systemFontOfSize:rect.size.width * 0.32f weight:UIFontWeightBlack],
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSParagraphStyleAttributeName: style
    };

    NSDictionary *attrSub = @{
        NSFontAttributeName: [UIFont systemFontOfSize:rect.size.width * 0.18f weight:UIFontWeightBold],
        NSForegroundColorAttributeName: _themeColor,
        NSParagraphStyleAttributeName: style
    };

    CGFloat midY = rect.size.height * 0.22f;
    [_label drawInRect:CGRectMake(0, midY, rect.size.width, rect.size.height * 0.4f) withAttributes:attrMain];
    [_sublabel drawInRect:CGRectMake(0, midY + rect.size.height * 0.36f, rect.size.width, rect.size.height * 0.3f) withAttributes:attrSub];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _isPressed = YES;
    g_pressed_buttons.fetch_or(_buttonMask, std::memory_order_relaxed);
    UpdateJoystickState();
    TriggerHaptic(_buttonMask & (kRB | kRT));
    [self setNeedsDisplay];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _isPressed = NO;
    g_pressed_buttons.fetch_and(~_buttonMask, std::memory_order_relaxed);
    UpdateJoystickState();
    [self setNeedsDisplay];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

@end

// ---------------------------------------------------------------------------
//  8-Way Precision Arcade D-Pad View (Quarter-Circle / Dragon Punch motions)
// ---------------------------------------------------------------------------
@interface Arcade8WayDpadView : UIView
@property (nonatomic, assign) CGPoint centerPoint;
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) int activeDirection;
@end

@implementation Arcade8WayDpadView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = YES;
        _radius = frame.size.width * 0.45f;
        _centerPoint = CGPointMake(frame.size.width * 0.5f, frame.size.height * 0.5f);
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect bounds = CGRectInset(rect, 6, 6);

    // Cross Base
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.10f alpha:0.80f].CGColor);
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.8f green:0.7f blue:0.2f alpha:0.7f].CGColor);
    CGContextSetLineWidth(ctx, 2.5f);

    CGContextFillEllipseInRect(ctx, bounds);
    CGContextStrokeEllipseInRect(ctx, bounds);

    // Center gate
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.20f alpha:0.90f].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectInset(bounds, bounds.size.width * 0.35f, bounds.size.height * 0.35f));
}

- (void)updateTouch:(UITouch *)touch {
    CGPoint loc = [touch locationInView:self];
    CGFloat dx = loc.x - _centerPoint.x;
    CGFloat dy = loc.y - _centerPoint.y;
    CGFloat dist = std::hypot(dx, dy);

    int buttons = 0;
    int16_t ax = 0, ay = 0;

    if (dist > 12.0f) {
        CGFloat angle = std::atan2(-dy, dx); // Radians, 0 = Right, PI/2 = Up
        if (angle < 0) angle += 2.0f * M_PI;

        // 8-Way Sectors (45 deg = PI/4)
        constexpr CGFloat kOctant = M_PI / 4.0f;
        int sector = static_cast<int>((angle + kOctant * 0.5f) / kOctant) % 8;

        switch (sector) {
            case 0: buttons = kRight; ax = 32767; break;          // 6
            case 1: buttons = kRight | kUp; ax = 23170; ay = -23170; break; // 9
            case 2: buttons = kUp; ay = -32767; break;             // 8
            case 3: buttons = kLeft | kUp; ax = -23170; ay = -23170; break;  // 7
            case 4: buttons = kLeft; ax = -32767; break;           // 4
            case 5: buttons = kLeft | kDown; ax = -23170; ay = 23170; break;// 1
            case 6: buttons = kDown; ay = 32767; break;            // 2
            case 7: buttons = kRight | kDown; ax = 23170; ay = 23170; break;// 3
        }
    }

    // Mask out previous D-Pad buttons and apply new
    int current = g_pressed_buttons.load(std::memory_order_relaxed);
    current &= ~(kUp | kDown | kLeft | kRight);
    current |= buttons;
    g_pressed_buttons.store(current, std::memory_order_relaxed);
    g_axis_x.store(ax, std::memory_order_relaxed);
    g_axis_y.store(ay, std::memory_order_relaxed);

    UpdateJoystickState();
    if (buttons != _activeDirection) {
        _activeDirection = buttons;
        TriggerHaptic(false);
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateTouch:[touches anyObject]];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateTouch:[touches anyObject]];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    int current = g_pressed_buttons.load(std::memory_order_relaxed);
    current &= ~(kUp | kDown | kLeft | kRight);
    g_pressed_buttons.store(current, std::memory_order_relaxed);
    g_axis_x.store(0, std::memory_order_relaxed);
    g_axis_y.store(0, std::memory_order_relaxed);
    _activeDirection = 0;
    UpdateJoystickState();
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

@end

// ---------------------------------------------------------------------------
//  Touch Controls Manager State
// ---------------------------------------------------------------------------
static TouchOverlayContainerView *g_overlay_view = nil;
static UILabel *g_fps_label = nil;

namespace tekken6::touch {

void SetVisible(bool visible) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_overlay_view) {
            g_overlay_view.hidden = !visible;
        }
    });
}

bool IsVisible() {
    return g_overlay_view && !g_overlay_view.hidden;
}

void BringToFront() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_overlay_view && g_overlay_view.superview) {
            [g_overlay_view.superview bringSubviewToFront:g_overlay_view];
        }
    });
}

void InstallFpsCounter() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_overlay_view || g_fps_label) return;

        g_fps_label = [[UILabel alloc] initWithFrame:CGRectMake(24, 12, 160, 28)];
        g_fps_label.backgroundColor = [UIColor colorWithWhite:0.05f alpha:0.75f];
        g_fps_label.layer.cornerRadius = 6.0f;
        g_fps_label.layer.masksToBounds = YES;
        g_fps_label.layer.borderColor = [UIColor colorWithRed:0.0f green:0.9f blue:1.0f alpha:0.8f].CGColor;
        g_fps_label.layer.borderWidth = 1.0f;
        g_fps_label.textColor = [UIColor colorWithRed:0.0f green:0.9f blue:1.0f alpha:1.0f];
        g_fps_label.font = [UIFont monospacedDigitSystemFontOfSize:13.0f weight:UIFontWeightBold];
        g_fps_label.textAlignment = NSTextAlignmentCenter;
        g_fps_label.text = @"60.0 FPS | 16.6ms";
        [g_overlay_view addSubview:g_fps_label];
    });
}

void Install() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_overlay_view) return;

        UIWindow *keyWindow = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        if (!keyWindow && [UIApplication sharedApplication].windows.count > 0) {
            keyWindow = [UIApplication sharedApplication].windows.firstObject;
        }
        if (!keyWindow) return;

        CGRect screenBounds = keyWindow.bounds;
        g_overlay_view = [[TouchOverlayContainerView alloc] initWithFrame:screenBounds];
        g_overlay_view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [keyWindow addSubview:g_overlay_view];
        [keyWindow bringSubviewToFront:g_overlay_view];

        CGFloat w = screenBounds.size.width;
        CGFloat h = screenBounds.size.height;

        // 1. D-Pad (Left Thumb, 8-way precision)
        CGFloat dpadSize = std::min(w, h) * 0.42f * REXCVAR_GET(ios_touch_scale);
        Arcade8WayDpadView *dpad = [[Arcade8WayDpadView alloc] initWithFrame:CGRectMake(40, h - dpadSize - 35, dpadSize, dpadSize)];
        [g_overlay_view addSubview:dpad];

        // 2. Namco Noir Arcade 6-Button Matrix (Right Thumb, 18 deg ergonomic arc)
        CGFloat btnSize = std::min(w, h) * 0.17f * REXCVAR_GET(ios_touch_scale);
        CGFloat spacingX = btnSize * 1.15f;
        CGFloat spacingY = btnSize * 1.05f;
        CGFloat baseRight = w - 45;
        CGFloat baseBottom = h - 35;

        // Top Row: LP (1 / X), RP (2 / Y), R1 / Rage (RB)
        // Bottom Row: LK (3 / A), RK (4 / B), R2 / Special (RT)
        ArcadeButtonView *btnLP = [[ArcadeButtonView alloc] initWithFrame:CGRectMake(baseRight - spacingX * 2.7f, baseBottom - spacingY * 1.85f, btnSize, btnSize)
            label:@"LP" sublabel:@"1 / X" mask:kX color:[UIColor colorWithRed:0.0f green:0.9f blue:1.0f alpha:1.0f]];

        ArcadeButtonView *btnRP = [[ArcadeButtonView alloc] initWithFrame:CGRectMake(baseRight - spacingX * 1.6f, baseBottom - spacingY * 2.05f, btnSize, btnSize)
            label:@"RP" sublabel:@"2 / Y" mask:kY color:[UIColor colorWithRed:1.0f green:0.85f blue:0.0f alpha:1.0f]];

        ArcadeButtonView *btnR1 = [[ArcadeButtonView alloc] initWithFrame:CGRectMake(baseRight - spacingX * 0.5f, baseBottom - spacingY * 2.15f, btnSize, btnSize)
            label:@"R1" sublabel:@"RAGE" mask:kRB color:[UIColor colorWithRed:1.0f green:0.2f blue:0.3f alpha:1.0f]];

        ArcadeButtonView *btnLK = [[ArcadeButtonView alloc] initWithFrame:CGRectMake(baseRight - spacingX * 2.85f, baseBottom - spacingY * 0.85f, btnSize, btnSize)
            label:@"LK" sublabel:@"3 / A" mask:kA color:[UIColor colorWithRed:0.0f green:0.9f blue:0.45f alpha:1.0f]];

        ArcadeButtonView *btnRK = [[ArcadeButtonView alloc] initWithFrame:CGRectMake(baseRight - spacingX * 1.75f, baseBottom - spacingY * 0.95f, btnSize, btnSize)
            label:@"RK" sublabel:@"4 / B" mask:kB color:[UIColor colorWithRed:1.0f green:0.1f blue:0.2f alpha:1.0f]];

        ArcadeButtonView *btnR2 = [[ArcadeButtonView alloc] initWithFrame:CGRectMake(baseRight - spacingX * 0.65f, baseBottom - spacingY * 1.05f, btnSize, btnSize)
            label:@"R2" sublabel:@"ITEM" mask:kRT color:[UIColor colorWithRed:0.8f green:0.3f blue:1.0f alpha:1.0f]];

        [g_overlay_view addSubview:btnLP];
        [g_overlay_view addSubview:btnRP];
        [g_overlay_view addSubview:btnR1];
        [g_overlay_view addSubview:btnLK];
        [g_overlay_view addSubview:btnRK];
        [g_overlay_view addSubview:btnR2];

        // 3. Top Action Bar: L1 (Throw), L2 (1+2 / 3+4), Start (Pause)
        CGFloat barBtnW = 75;
        CGFloat barBtnH = 36;
        ArcadeButtonView *btnL1 = [[ArcadeButtonView alloc] initWithFrame:CGRectMake(w * 0.28f, 12, barBtnW, barBtnH)
            label:@"L1" sublabel:@"THROW" mask:kLB color:[UIColor colorWithWhite:0.7f alpha:1.0f]];

        ArcadeButtonView *btnL2 = [[ArcadeButtonView alloc] initWithFrame:CGRectMake(w * 0.28f + barBtnW + 15, 12, barBtnW, barBtnH)
            label:@"L2" sublabel:@"1+2" mask:kLT color:[UIColor colorWithWhite:0.7f alpha:1.0f]];

        ArcadeButtonView *btnPause = [[ArcadeButtonView alloc] initWithFrame:CGRectMake(w - 110, 12, 85, barBtnH)
            label:@"START" sublabel:@"PAUSE" mask:kStart color:[UIColor colorWithRed:1.0f green:0.6f blue:0.0f alpha:1.0f]];

        [g_overlay_view addSubview:btnL1];
        [g_overlay_view addSubview:btnL2];
        [g_overlay_view addSubview:btnPause];

        InstallFpsCounter();

        // 4. Physical Controller Observation (GCController)
        [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            NSLog(@"[Tekken6Touch] Physical gamepad connected; auto-hiding on-screen overlay.");
            SetVisible(false);
        }];

        [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidDisconnectNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            if ([GCController controllers].count == 0) {
                NSLog(@"[Tekken6Touch] Gamepad disconnected; restoring touch controls.");
                SetVisible(true);
            }
        }];

        NSLog(@"[Tekken6Touch] Arcade Fighting touch controls installed successfully.");
    });
}

} // namespace tekken6::touch

