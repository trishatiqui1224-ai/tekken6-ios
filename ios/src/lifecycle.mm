// Tekken 6 Recompiled - iOS Lifecycle (lifecycle.mm)
// Title ID: 4E4D07FC

#import <UIKit/UIKit.h>
#include <atomic>
#include <functional>
#include <rex/logging.h>
#include "lifecycle.h"

namespace {
std::function<void()> g_pause_fn;
std::function<void()> g_resume_fn;
std::atomic<bool> g_is_paused{false};
}

namespace tekken6::lifecycle {

void Install(std::function<void()> pause, std::function<void()> resume) {
    g_pause_fn = pause;
    g_resume_fn = resume;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        REXLOG_INFO("[Tekken6Lifecycle] App entered background; pausing GPU emulation.");
        g_is_paused.store(true, std::memory_order_relaxed);
        if (g_pause_fn) g_pause_fn();
    }];

    [nc addObserverForName:UIApplicationWillEnterForegroundNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        REXLOG_INFO("[Tekken6Lifecycle] App returned to foreground; resuming GPU emulation.");
        g_is_paused.store(false, std::memory_order_relaxed);
        if (g_resume_fn) g_resume_fn();
    }];
}

void OnDisplayTick() {
    if (g_is_paused.load(std::memory_order_relaxed)) {
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            g_is_paused.store(false, std::memory_order_relaxed);
            if (g_resume_fn) g_resume_fn();
        }
    }
}

} // namespace tekken6::lifecycle

