// Tekken 6 Recompiled - Verified Game & Kernel Hooks (tekken6_hooks.h)
// Title ID: 4E4D07FC

#pragma once

#include <cstdint>

namespace tekken6::hooks {

// Installs genuine Tekken 6 entrypoint, privilege check, and kernel hooks
void InstallHooks();

// Mid-ASM hooks called by recompiled PowerPC code
void OnStartupWait(uint64_t* r11);
void OnApplyInternalResolution(uint64_t* r11, uint64_t* r10);
void OnApplyOffscreenResolution(uint64_t* r3, uint64_t* r4, uint64_t* r5);

} // namespace tekken6::hooks

