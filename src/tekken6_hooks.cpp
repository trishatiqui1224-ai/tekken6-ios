// Tekken 6 Recompiled - Verified Game & Kernel Hooks (tekken6_hooks.cpp)
// Title ID: 4E4D07FC

#include <cstdint>
#include <thread>
#include <chrono>

#include <rex/logging.h>
#include <rex/cvar.h>

#include "tekken6_hooks.h"

REXCVAR_DEFINE_INT32(tekken6_res_width, 1920, "Graphics", "Tekken 6 Internal Render Width");
REXCVAR_DEFINE_INT32(tekken6_res_height, 1080, "Graphics", "Tekken 6 Internal Render Height");

namespace tekken6::hooks {

void InstallHooks() {
    REXLOG_INFO("[Tekken6Hooks] Installing verified hooks for Title ID 4E4D07FC...");
    REXLOG_INFO("  [Hook] 0x824BEA50: Genuine XEX Entry Point");
    REXLOG_INFO("  [Hook] 0x824BE868: Display & Privilege Check (forced Success = 0)");
    REXLOG_INFO("  [Hook] 0x82170000: Engine main() entrypoint");
    REXLOG_INFO("  [Hook] 0x826CCBE4: XamLoaderTerminateTitle interlock");
    REXLOG_INFO("  [Hook] 0x826CCD34: DbgPrint kernel trace");
}

void OnStartupWait(uint64_t* r11) {
    // Yield at the startup queue wait's backward branch to prevent worker starvation on iOS
    std::this_thread::sleep_for(std::chrono::microseconds(200));
}

void OnApplyInternalResolution(uint64_t* r11, uint64_t* r10) {
    // Overrides default 1024x576 internal target with user launcher preset
    if (r11 && r10) {
        *r11 = static_cast<uint64_t>(REXCVAR_GET(tekken6_res_width));
        *r10 = static_cast<uint64_t>(REXCVAR_GET(tekken6_res_height));
    }
}

void OnApplyOffscreenResolution(uint64_t* r3, uint64_t* r4, uint64_t* r5) {
    // Scales offscreen render targets
    if (r4 && r5) {
        *r4 = static_cast<uint64_t>(REXCVAR_GET(tekken6_res_width));
        *r5 = static_cast<uint64_t>(REXCVAR_GET(tekken6_res_height));
    }
}

} // namespace tekken6::hooks

// ReXGlue Mid-ASM Hook Symbols defined in tekken6_config.toml
extern "C" {

void Tekken6StartupWait(uint64_t* r11) {
    tekken6::hooks::OnStartupWait(r11);
}

void ApplyTekkenInternalResolution(uint64_t* r11, uint64_t* r10) {
    tekken6::hooks::OnApplyInternalResolution(r11, r10);
}

void ApplyTekkenOffscreenResolution(uint64_t* r3, uint64_t* r4, uint64_t* r5) {
    tekken6::hooks::OnApplyOffscreenResolution(r3, r4, r5);
}

}

