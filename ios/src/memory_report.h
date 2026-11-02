// Tekken 6 Recompiled - Memory and Resource Reporter (memory_report.h)
// Title ID: 4E4D07FC

#pragma once

namespace tekken6::memory {

void Report(const char* stage);
const char* ThermalState();
void StartPeriodicReports(int seconds);

} // namespace tekken6::memory

