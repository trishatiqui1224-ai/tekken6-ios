// Tekken 6 iOS - Startup Trace & Crash Breadcrumbs (boot_trace.h)
// Title ID: 4E4D07FC

#pragma once

#include <string>
#include <cstdint>

namespace tekken6::boot {

void Open(const std::string& path);
void SetLogFilePath(const std::string& path);
void Trace(const std::string& line);
void SetEnabled(bool enabled);
void SetupAltStack();
void SetLastPPCBreadcrumb(uint32_t fn_addr, uint32_t lr, uint32_t r3);
size_t FormatLastPPCBreadcrumbs(char* buf, size_t buf_size);

}  // namespace tekken6::boot

namespace fnc::boot {
using namespace tekken6::boot;
}
