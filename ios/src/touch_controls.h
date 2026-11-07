// Tekken 6 iOS - Low-Latency Arcade Fighting Touch Controls (touch_controls.h)
// Title ID: 4E4D07FC

#pragma once

#ifdef __OBJC__
#import <UIKit/UIKit.h>
#endif

namespace tekken6::touch {

// Installs the glassmorphic touch overlay on the key window
void Install();

// Installs the real-time FPS and frame time HUD
void InstallFpsCounter();

// Visibility and z-order controls
void SetVisible(bool visible);
bool IsVisible();
void BringToFront();

// Mode controls: Fight Mode vs Menu Nav Mode
void SetFightMode(bool fight_mode);
bool IsFightMode();

// Opacity controls
void SetOpacity(float opacity);
void CycleOpacity();

}  // namespace tekken6::touch

namespace fnc::touch {
using namespace tekken6::touch;
}
