// Tekken 6 Recompiled - Verified Game & Kernel Hooks (tekken6_hooks.h)
// Title ID: 4E4D07FC

#pragma once

#include <cstdint>

namespace rex::runtime {
class FunctionDispatcher;
}

struct PPCContext;

namespace tekken6::hooks {

// Installs genuine Tekken 6 entrypoint, privilege check, and kernel hooks
void InstallHooks();

// Registers member adapters, dynamic function pointer fallbacks, and structure-return stubs
void RegisterMemberAdapters(rex::runtime::FunctionDispatcher* dispatcher);

// Mid-ASM hooks called by recompiled PowerPC code
void OnStartupWait(uint64_t* r11);
void OnApplyInternalResolution(uint64_t* r11, uint64_t* r10);
void OnApplyOffscreenResolution(uint64_t* r3, uint64_t* r4, uint64_t* r5);

// Structure-return adapter: preserves and returns hidden destination pointer in r3
void StructReturnAdapter(PPCContext& ctx, uint8_t* base);

// Animation blend evaluator adapter
void AnimBlendAdapter(PPCContext& ctx, uint8_t* base);

// Physics collision callback adapter
void PhysicsCollisionAdapter(PPCContext& ctx, uint8_t* base);

// Sound / voice event callback adapter
void VoiceCallbackAdapter(PPCContext& ctx, uint8_t* base);

} // namespace tekken6::hooks
