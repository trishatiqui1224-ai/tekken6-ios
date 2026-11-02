// Tekken 6 Recompiled - ProMotion Refresh Rate Manager (display_rate.mm)
// Title ID: 4E4D07FC

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <atomic>
#include <cmath>
#include <mach/mach_time.h>
#include <rex/logging.h>
#include "display_rate.h"

namespace {
CADisplayLink *g_display_link = nil;
std::atomic<uint64_t> g_vblank_time_ns{0};
std::atomic<uint64_t> g_vblank_period_ns{16666666}; // default 60Hz
}

@interface Tekken6DisplayLinkTarget : NSObject
- (void)onTick:(CADisplayLink *)link;
@end

@implementation Tekken6DisplayLinkTarget
- (void)onTick:(CADisplayLink *)link {
    uint64_t now_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    uint64_t period_ns = static_cast<uint64_t>(link.targetTimestamp - link.timestamp) * 1000000000ull;
    g_vblank_time_ns.store(now_ns, std::memory_order_relaxed);
    if (period_ns > 0) {
        g_vblank_period_ns.store(period_ns, std::memory_order_relaxed);
    }
}
@end

namespace tekken6::display {

void RequestRateForCap(int fps_cap) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_display_link) {
            Tekken6DisplayLinkTarget *target = [[Tekken6DisplayLinkTarget alloc] init];
            g_display_link = [CADisplayLink displayLinkWithTarget:target selector:@selector(onTick:)];
            [g_display_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }

        if (@available(iOS 15.0, *)) {
            if (fps_cap > 60) {
                g_display_link.preferredFrameRateRange = CAFrameRateRangeMake(60.0f, 120.0f, 120.0f);
                REXLOG_INFO("[Tekken6Display] ProMotion 120Hz requested.");
            } else {
                g_display_link.preferredFrameRateRange = CAFrameRateRangeMake(30.0f, 60.0f, 60.0f);
                REXLOG_INFO("[Tekken6Display] 60Hz frame pacing requested.");
            }
        }
    });
}

bool MatchesCap() {
    return true;
}

void LatestVblank(uint64_t& time_ns, uint64_t& period_ns) {
    time_ns = g_vblank_time_ns.load(std::memory_order_relaxed);
    period_ns = g_vblank_period_ns.load(std::memory_order_relaxed);
}

} // namespace tekken6::display

