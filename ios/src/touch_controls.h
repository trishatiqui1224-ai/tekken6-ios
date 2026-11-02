// Tekken 6 Recompiled - iOS Arcade Fighting Touch Controls
// Title ID: 4E4D07FC

#pragma once

#ifdef __OBJC__
#import <UIKit/UIKit.h>
@class UIViewController;
@class UIView;
#endif

namespace tekken6::touch {

// Installs the always-on-top passthrough arcade fighting touch overlay
// (TouchOverlayContainerView, zPosition = 9999). Idempotent.
void Install();

// Brings the overlay to front if swapchain or Metal views recreate
void BringToFront();

// Installs the 60/120 FPS and frame-time HUD in the top bar
void InstallFpsCounter();

// Toggles visibility of touch controls (e.g. on gamepad connection)
void SetVisible(bool visible);
bool IsVisible();

// Switch between Arcade Fight Pad layout and Menu navigation layout
void SetLayoutMode(int mode); // 0 = FightPad, 1 = Menu

#ifdef __OBJC__
// In-game configuration & drag-to-edit layout controller
UIViewController* MakeLayoutEditor();
#endif

} // namespace tekken6::touch

