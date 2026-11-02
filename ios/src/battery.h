// Tekken 6 Recompiled - Battery and Thermal Management (battery.h)
// Title ID: 4E4D07FC

#pragma once

namespace tekken6::battery {

void Start();
void SetInMenu(bool in_menu);
int InMenu();
void ChooseCap(int fps);
float HeatScale();

} // namespace tekken6::battery

