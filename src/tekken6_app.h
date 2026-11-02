// Tekken 6 Recompiled - Main Application Definition (tekken6_app.h)
// Title ID: 4E4D07FC

#pragma once

#include <rex/ui/windowed_app.h>
#include <rex/runtime.h>
#include <rex/system/interfaces/graphics.h>
#include <rex/system/interfaces/audio.h>

#include "tekken6_hooks.h"

class Tekken6App : public rex::ui::WindowedApp {
 public:
  using WindowedApp::WindowedApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx);

 protected:
  void OnPreSetup(rex::RuntimeConfig& config) override {
    config.title_id = 0x4E4D07FC;
    tekken6::hooks::InstallHooks();
  }

  void OnPostSetup() override {
    rex::ui::WindowedApp::OnPostSetup();
  }
};

