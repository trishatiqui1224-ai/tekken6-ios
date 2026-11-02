// Tekken 6 Recompiled - Memory and Resource Reporter (memory_report.mm)
// Title ID: 4E4D07FC

#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <rex/logging.h>
#include "memory_report.h"

namespace tekken6::memory {

void Report(const char* stage) {
    task_vm_info_data_t vm_info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm_info, &count) == KERN_SUCCESS) {
        double footprint_mb = (double)vm_info.phys_footprint / (1024.0 * 1024.0);
        REXLOG_INFO("[Tekken6Mem] Stage '{}': physical footprint {:.1f} MB", stage, footprint_mb);
    }
}

const char* ThermalState() {
    switch ([NSProcessInfo processInfo].thermalState) {
        case NSProcessInfoThermalStateNominal: return "nominal";
        case NSProcessInfoThermalStateFair: return "fair";
        case NSProcessInfoThermalStateSerious: return "serious";
        case NSProcessInfoThermalStateCritical: return "critical";
        default: return "unknown";
    }
}

void StartPeriodicReports(int seconds) {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0));
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, seconds * NSEC_PER_SEC), seconds * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        Report("periodic");
    });
    dispatch_resume(timer);
}

} // namespace tekken6::memory

