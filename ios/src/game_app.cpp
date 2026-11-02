// Tekken 6 Recompiled - iOS Game Application Host (game_app.cpp)
// Title ID: 4E4D07FC

#include "tekken6_init.h"
#include "tekken6_app.h"

#include <rex/logging.h>
#include <rex/runtime.h>
#include <rex/cvar.h>
#include <rex/system/interfaces/graphics.h>

#include "audio/coreaudio_driver.h"
#include "display_rate.h"
#include "launcher.h"
#include "lifecycle.h"
#include "touch_controls.h"
#include "battery.h"

class IosTekken6App : public Tekken6App {
 public:
  using Tekken6App::Tekken6App;

  static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<IosTekken6App>(new IosTekken6App(ctx, "tekken6", PPCImageConfig));
  }

 protected:
  void OnPreSetup(rex::RuntimeConfig& config) override {
    Tekken6App::OnPreSetup(config);
    config.audio_factory = REX_AUDIO_BACKEND(rex::audio::ios::CoreAudioSystem);
    tekken6::display::RequestRateForCap(60);
    tekken6::battery::Start();
  }

  void OnPostSetup() override {
    Tekken6App::OnPostSetup();
    tekken6::touch::Install();
    tekken6::touch::InstallFpsCounter();
    tekken6::lifecycle::Install(
        [this]() {
            REXLOG_INFO("[Tekken6App] Emulation paused (background).");
        },
        [this]() {
            REXLOG_INFO("[Tekken6App] Emulation resumed (foreground).");
            tekken6::touch::BringToFront();
        }
    );
  }
};

std::unique_ptr<rex::ui::WindowedApp> Tekken6App::Create(rex::ui::WindowedAppContext& ctx) {
    return IosTekken6App::Create(ctx);
}

