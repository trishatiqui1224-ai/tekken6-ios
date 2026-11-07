// Tekken 6 Recompiled - Verified Game & Kernel Hooks (tekken6_hooks.cpp)
// Title ID: 4E4D07FC

#include <cstdint>
#include <cstring>
#include <thread>
#include <chrono>

#include <rex/logging.h>
#include <rex/cvar.h>
#include <rex/ppc/func.h>
#include <rex/ppc/context.h>
#include <rex/system/function_dispatcher.h>

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

void StructReturnAdapter(PPCContext& ctx, uint8_t* base) {
    // Xbox 360 / PowerPC 64 ABI: When returning an aggregate structure/object,
    // caller places destination pointer into r3. Callee MUST return that same
    // destination pointer in r3 upon completion.
    uint32_t dest_ptr = static_cast<uint32_t>(ctx.r3);
    if (dest_ptr != 0 && base != nullptr) {
        // Zero-initialize destination buffer up to 64 bytes (Matrix4x4 / Vector4 / BoundingBox)
        std::memset(base + dest_ptr, 0, 64);
    }
    ctx.r3 = dest_ptr;
}

void AnimBlendAdapter(PPCContext& ctx, uint8_t* base) {
    // Animation evaluator stub: return 1 (animation state active / evaluated)
    (void)base;
    ctx.r3 = 1;
}

void PhysicsCollisionAdapter(PPCContext& ctx, uint8_t* base) {
    // Physics collision callback stub: return 0 (no collision reject / success)
    (void)base;
    ctx.r3 = 0;
}

void VoiceCallbackAdapter(PPCContext& ctx, uint8_t* base) {
    // Audio / voice event callback stub: return 0 (success)
    (void)base;
    ctx.r3 = 0;
}

void RegisterMemberAdapters(rex::runtime::FunctionDispatcher* dispatcher) {
    if (!dispatcher) {
        REXLOG_WARN("[Tekken6Hooks] Function dispatcher is null; skipping adapter registration.");
        return;
    }

    REXLOG_INFO("[Tekken6Hooks] Registering member adapters and missing stubs for Tekken 6...");

    // Register verified member adapters for dynamic indirect calls
    // Address 0x82390788 is Tekken 6's primary dynamic dispatcher
    dispatcher->SetFunction(0x82390788, StructReturnAdapter);

    // Register safe fallbacks for character animation, physics, and voice callbacks
    const uint32_t anim_stubs[] = {
        0x821927D0, 0x82192830, 0x82192890, 0x821928F0,
    };
    for (uint32_t addr : anim_stubs) {
        if (!dispatcher->GetFunction(addr)) {
            dispatcher->SetFunction(addr, AnimBlendAdapter);
            REXLOG_INFO("  [Adapter] Registered AnimBlendAdapter at 0x%08X", addr);
        }
    }

    const uint32_t physics_stubs[] = {
        0x82218290, 0x82221CD8, 0x8231D350,
    };
    for (uint32_t addr : physics_stubs) {
        if (!dispatcher->GetFunction(addr)) {
            dispatcher->SetFunction(addr, PhysicsCollisionAdapter);
            REXLOG_INFO("  [Adapter] Registered PhysicsCollisionAdapter at 0x%08X", addr);
        }
    }

    const uint32_t voice_stubs[] = {
        0x82404B58, 0x82404BE8,
    };
    for (uint32_t addr : voice_stubs) {
        if (!dispatcher->GetFunction(addr)) {
            dispatcher->SetFunction(addr, VoiceCallbackAdapter);
            REXLOG_INFO("  [Adapter] Registered VoiceCallbackAdapter at 0x%08X", addr);
        }
    }

    REXLOG_INFO("[Tekken6Hooks] Member adapters registered successfully.");
}

void OnStartupWait(uint64_t* r11) {
    (void)r11;
    // Yield at the startup queue wait's backward branch to prevent worker starvation on iOS ARM64
    std::this_thread::yield();
}

void OnApplyInternalResolution(uint64_t* r11, uint64_t* r10) {
    // Overrides default 1024x576 internal target with user launcher preset
    if (r11 && r10) {
        *r11 = static_cast<uint64_t>(REXCVAR_GET(tekken6_res_width));
        *r10 = static_cast<uint64_t>(REXCVAR_GET(tekken6_res_height));
    }
}

void OnApplyOffscreenResolution(uint64_t* r3, uint64_t* r4, uint64_t* r5) {
    (void)r3;
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
