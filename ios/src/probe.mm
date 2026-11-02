// Tekken 6 Recompiled - Metal / Hardware Probe (probe.mm)
// Title ID: 4E4D07FC

#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#include <fstream>
#include <rex/logging.h>
#include "probe.h"

namespace tekken6::probe {

int RunHardwareProbe(const std::string& report_path) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        REXLOG_ERROR("[Tekken6Probe] Metal is not supported on this device!");
        return -1;
    }

    std::ofstream out(report_path);
    out << "=== Tekken 6 iOS Hardware Probe Report ===" << std::endl;
    out << "Device Name: " << [device.name UTF8String] << std::endl;
    out << "Max Buffer Length: " << (device.maxBufferLength / (1024 * 1024)) << " MB" << std::endl;

    if (@available(iOS 16.0, *)) {
        out << "Metal 3 Support: " << ([device supportsFamily:MTLGPUFamilyMetal3] ? "YES" : "NO") << std::endl;
        out << "Apple 8 (A15/A16/M2): " << ([device supportsFamily:MTLGPUFamilyApple8] ? "YES" : "NO") << std::endl;
        out << "Apple 9 (A17 Pro/M3): " << ([device supportsFamily:MTLGPUFamilyApple9] ? "YES" : "NO") << std::endl;
    }

    out << "Argument Buffers Tier: " << (int)device.argumentBuffersSupport << std::endl;
    REXLOG_INFO("[Tekken6Probe] Hardware probe written to {}", report_path);
    return 0;
}

} // namespace tekken6::probe

