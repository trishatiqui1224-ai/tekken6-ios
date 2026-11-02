// Tekken 6 Recompiled - Battery and Thermal Management (battery.mm)
// Title ID: 4E4D07FC

#import <UIKit/UIKit.h>
#include <atomic>
#include <rex/logging.h>
#include "battery.h"

namespace {
std::atomic<int> g_in_menu{-1};
std::atomic<float> g_heat_scale{1.0f};
}

namespace tekken6::battery {

void Start() {
    [[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        NSProcessInfoThermalState state = [NSProcessInfo processInfo].thermalState;
        if (state >= NSProcessInfoThermalStateSerious) {
            g_heat_scale.store(0.85f, std::memory_order_relaxed);
            REXLOG_WARN("[Tekken6Battery] Thermal state serious/critical; lowering resolution scale to 0.85x.");
        } else {
            g_heat_scale.store(1.0f, std::memory_order_relaxed);
        }
    }];
}

void SetInMenu(bool in_menu) {
    g_in_menu.store(in_menu ? 1 : 0, std::memory_order_relaxed);
}

int InMenu() {
    return g_in_menu.load(std::memory_order_relaxed);
}

void ChooseCap(int fps) {
    REXLOG_INFO("[Tekken6Battery] Target FPS cap: {}", fps);
}

float HeatScale() {
    return g_heat_scale.load(std::memory_order_relaxed);
}

} // namespace tekken6::battery

