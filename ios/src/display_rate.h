// Tekken 6 Recompiled - ProMotion Refresh Rate Manager (display_rate.h)
// Title ID: 4E4D07FC

#pragma once

#include <cstdint>

namespace tekken6::display {

void RequestRateForCap(int fps_cap);
bool MatchesCap();
void LatestVblank(uint64_t& time_ns, uint64_t& period_ns);

} // namespace tekken6::display

