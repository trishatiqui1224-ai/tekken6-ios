// Tekken 6 Recompiled - iOS Entrypoint (ios_main.mm)
// Title ID: 4E4D07FC

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <AVFoundation/AVFoundation.h>

#include <filesystem>
#include <string>
#include <vector>
#include <cstdlib>

#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/platform.h>

#include "launcher.h"
#include "touch_controls.h"

// Set up iOS sandbox environment before ANY library (SDL, MoltenVK, ReXGlue) initializes
static void SetupIosSandboxEnvironment() {
    @autoreleasepool {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docDir = paths.firstObject;
        NSArray *cachePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDir = cachePaths.firstObject;
        NSString *tmpDir = NSTemporaryDirectory();

        NSString *rexDataDir = [docDir stringByAppendingPathComponent:@"rex_data"];
        NSString *configDir = [docDir stringByAppendingPathComponent:@"config"];

        std::error_code ec;
        std::filesystem::create_directories([rexDataDir UTF8String], ec);
        std::filesystem::create_directories([configDir UTF8String], ec);
        std::filesystem::create_directories([cacheDir UTF8String], ec);
        std::filesystem::create_directories([[docDir stringByAppendingPathComponent:@"game"] UTF8String], ec);
        std::filesystem::create_directories([[docDir stringByAppendingPathComponent:@"saves"] UTF8String], ec);

        setenv("XDG_DATA_HOME", [rexDataDir UTF8String], 1);
        setenv("XDG_CACHE_HOME", [cacheDir UTF8String], 1);
        setenv("XDG_CONFIG_HOME", [configDir UTF8String], 1);
        setenv("TMPDIR", [tmpDir UTF8String], 1);

        // MoltenVK configuration overrides for Metal3 argument buffers and low-latency rendering
        setenv("MVK_CONFIG_RESUME_LOST_DEVICE", "1", 1);
        setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "1", 1);
        setenv("MVK_CONFIG_PREFILL_METAL_ARGUMENT_BUFFERS", "1", 1);
        setenv("MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING", "0", 1);

        NSLog(@"[Tekken6] iOS Sandbox environment initialized cleanly.");
        NSLog(@"[Tekken6] Documents: %@", docDir);
        NSLog(@"[Tekken6] Cache:     %@", cacheDir);
    }
}

int main(int argc, char *argv[]) {
    // 1. Mandatory Rule: Initialize Sandbox Environment First
    SetupIosSandboxEnvironment();

    // 2. Build default launch arguments for 60 FPS fighting game performance
    std::vector<std::string> args;
    for (int i = 0; i < argc; ++i) {
        args.emplace_back(argv[i]);
    }

    auto append_if_missing = [&](const std::string& key, const std::string& val) {
        for (const auto& a : args) {
            if (a.rfind(key, 0) == 0) return;
        }
        args.push_back(key + "=" + val);
    };

    append_if_missing("--gpu_backend", "vulkan");
    append_if_missing("--render_target_path_vulkan", "fbo");
    append_if_missing("--occlusion_query_enable", "false");
    append_if_missing("--readback_memexport", "false");
    append_if_missing("--readback_resolve", "none");
    append_if_missing("--resolution_scale", "1");
    append_if_missing("--anisotropic_override", "16");
    append_if_missing("--ios_xma_starve_reset", "false");

    // Convert back to argv
    std::vector<char*> c_argv;
    for (auto& s : args) {
        c_argv.push_back(s.data());
    }
    int c_argc = static_cast<int>(c_argv.size());

    // 3. Launch through UIKit
    @autoreleasepool {
        return UIApplicationMain(c_argc, c_argv.data(), nil, NSStringFromClass([Tekken6AppDelegate class]));
    }
}

