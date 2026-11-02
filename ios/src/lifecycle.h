// Tekken 6 Recompiled - iOS Lifecycle (lifecycle.h)
// Title ID: 4E4D07FC

#pragma once

#include <functional>

namespace tekken6::lifecycle {

void Install(std::function<void()> pause, std::function<void()> resume);
void OnDisplayTick();

} // namespace tekken6::lifecycle

