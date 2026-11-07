// Tekken 6 Recompiled - Main Application Definition (tekken6_app.h)
// Title ID: 4E4D07FC

#pragma once

#include <rex/rex_app.h>
#include <rex/runtime.h>
#include <rex/system/interfaces/graphics.h>
#include <rex/system/interfaces/audio.h>

#include "tekken6_hooks.h"

class Tekken6App : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx);

 protected:
  void OnPreSetup(rex::RuntimeConfig& config) override {
    tekken6::hooks::InstallHooks();
  }

  void OnPostSetup() override {
    rex::ReXApp::OnPostSetup();
    if (runtime()) {
      tekken6::hooks::RegisterMemberAdapters(runtime()->function_dispatcher());
    }
  }
};

