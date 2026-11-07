// Tekken 6 iOS - Native Launcher Host (launcher.mm)
// Exact dark mode UITableViewStyleInsetGrouped 6-tab menu.
// Title ID: 4E4D07FC

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <functional>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include <rex/logging.h>
#include "boot_trace.h"
#include "launcher.h"
#include "save_manager.h"
#include "touch_controls.h"

namespace fs = std::filesystem;

namespace tekken6::launcher {

enum class OptionType { kSwitch, kChoice, kLink, kAction };

struct Choice {
  NSString* title;
  NSString* value;
};

struct Option {
  NSString* key;
  OptionType type;
  NSString* title;
  NSString* summary;
  NSString* default_value;
  std::vector<Choice> choices = {};
};

struct Section {
  NSString* title;
  NSString* footer;
  std::vector<Option> options;
  int tab = 0;
};

enum Tab {
  kTabGame = 0,
  kTabExtras,
  kTabGraphics,
  kTabControls,
  kTabAudio,
  kTabAdvanced,
  kTabCount
};

NSArray<NSString*>* TabTitles() {
  return @[ @"Game", @"Extras", @"Graphics", @"Controls", @"Audio", @"Advanced" ];
}

const std::vector<Section>& Sections() {
  static const std::vector<Section> sections = {
      // ---------------------------------------------------------------------
      // TAB 0: Game
      // ---------------------------------------------------------------------
      {@"GAME SOURCE", @"Detected Xbox 360 Tekken 6 disc image or extracted folder.",
       {
           {@"game_source", OptionType::kChoice, @"Selected Game Disc / Folder",
            @"Title ID: 4E4D07FC • Tekken 6 (World) (En,Ja,Fr,De,Es,It,Ko,Ru)",
            @"auto"},
           {@"choose_iso", OptionType::kAction, @"Choose ISO Image...",
            @"Select a retail Tekken 6 .iso file from Documents or external storage.",
            @""},
           {@"choose_folder", OptionType::kAction, @"Choose Extracted Folder...",
            @"Select an extracted game directory containing default.xex and game data.",
            @""},
       }, kTabGame},
      {@"SAVES & GHOST DATA", @"Manage Tekken 6 ghost profiles, arcade records, and customizations.",
       {
           {@"save_manager", OptionType::kLink, @"Save Manager...",
            @"Backup, restore, or export your fighter customizations and ghost records (.zip / iCloud).",
            @""},
       }, kTabGame},

      // ---------------------------------------------------------------------
      // TAB 1: Extras (Tekken 6 Combat & Visual Tweaks)
      // ---------------------------------------------------------------------
      {@"RESOLUTION & MOTION BLUR", @"Tekken 6 dynamic resolution & visual quality controls.",
       {
           {@"disable_motion_blur", OptionType::kSwitch, @"Disable Motion Blur (Force 720p Native)",
            @"Tekken 6 dynamically drops internal resolution to 1024x576 when full-screen motion blur is active. Disabling motion blur forces a razor-sharp 1280x720 native framebuffer at all times.",
            @"true"},
           {@"game_language", OptionType::kChoice, @"Game Language",
            @"Select language for menus, dialogue, and subtitle tracks.",
            @"1",
            {{@"English", @"1"},
             {@"Japanese", @"2"},
             {@"French", @"3"},
             {@"German", @"4"},
             {@"Spanish", @"5"},
             {@"Italian", @"6"},
             {@"Korean", @"7"},
             {@"Russian", @"8"}}},
           {@"scenario_campaign_fixes", OptionType::kSwitch, @"Scenario Campaign Stability",
            @"Enhances camera tracking and prevents memory spikes during Campaign Mode.",
            @"true"},
           {@"unlock_all_stages", OptionType::kSwitch, @"All Stages Selectable",
            @"Bypasses stage progression gates in Versus and Practice modes.",
            @"false"},
       }, kTabExtras},

      // ---------------------------------------------------------------------
      // TAB 2: Graphics (Vulkan & Metal Display Pipeline)
      // ---------------------------------------------------------------------
      {@"RENDERER & VULKAN BACKEND", nil,
       {
           {@"render_target_path", OptionType::kChoice, @"Render Target Emulation",
            @"FBO enables host framebuffer object tile emulation (prevents corrupt or black stage hit-sparks).",
            @"fbo",
            {{@"Host FBO (Recommended for Tekken 6)", @"fbo"},
             {@"Pixel Shader Interlock (fsi)", @"fsi"}}},
           {@"gpu_allow_invalid_fetch", OptionType::kSwitch, @"Allow Invalid Fetch Constants",
            @"Required for CRIWARE Sofdec video playback (YUV decoding) and stage backgrounds without green screen.",
            @"true"},
           {@"async_pipelines", OptionType::kSwitch, @"Compile Pipelines in Background",
            @"Compiles Vulkan GPU pipelines asynchronously on worker threads to eliminate hitches.",
            @"true"},
           {@"anisotropic_override", OptionType::kChoice, @"Anisotropic Texture Filtering",
            @"Enhances ground and stage texture clarity at sharp combat viewing angles.",
            @"16",
            {{@"16x (Highest Quality)", @"16"},
             {@"8x", @"8"},
             {@"4x", @"4"},
             {@"Default (Console)", @"0"}}},
       }, kTabGraphics},
      {@"DISPLAY & RESOLUTION", nil,
       {
           {@"resolution", OptionType::kChoice, @"Internal Resolution",
            @"Native 720p matches console framebuffer. 1080p and Retina provide enhanced clarity on modern displays.",
            @"1280x720",
            {{@"1280x720 (Native 720p - 60 FPS Locked)", @"1280x720"},
             {@"1920x1080 (Full HD Enhanced)", @"1920x1080"},
             {@"Native Retina (Screen Match)", @"native"}}},
           {@"aspect", OptionType::kChoice, @"Screen Shape",
            @"Fit this screen adapts to iPhone 19.5:9 and iPad 4:3. 16:9 displays authentic console letterboxing.",
            @"auto",
            {{@"Fit This Screen", @"auto"},
             {@"16:9 (Console Letterbox)", @"16:9"},
             {@"4:3 (iPad Native)", @"4:3"}}},
           {@"clear_memory_page_state", OptionType::kSwitch, @"Clear Memory Page State",
            @"Prevents character costume tearing and stretched mesh artifacts (Recommended ON).",
            @"true"},
           {@"readback_resolve", OptionType::kChoice, @"Readback Resolve Mode",
            @"Controls GPU-to-CPU texture resolve synchronization for stage reflections.",
            @"fast",
            {{@"Fast (1-Frame Latency, Zero Stutter)", @"fast"},
             {@"Off (Fastest)", @"none"},
             {@"Full (Synchronous)", @"full"}}},
       }, kTabGraphics},

      // ---------------------------------------------------------------------
      // TAB 3: Controls (Glassmorphic Arcade Fighting Virtual Controller)
      // ---------------------------------------------------------------------
      {@"ON-SCREEN ARCADE CONTROLS", nil,
       {
           {@"touch_controls", OptionType::kSwitch, @"Enable Touch Controls",
            @"Displays on-screen glassmorphic arcade fighting layout. Auto-hides when a physical gamepad connects.",
            @"true"},
           {@"control_mode", OptionType::kChoice, @"Initial Control Mode",
            @"FIGHT MODE provides an 8-way Arcade D-Pad and limb chord macros. MENU NAV provides cross D-pad and swipe navigation.",
            @"0",
            {{@"🥊 FIGHT MODE (Arcade 8-Way + Macro Chords)", @"0"},
             {@"📋 MENU NAV (Cardinal Cross + Swipes)", @"1"}}},
           {@"touch_opacity", OptionType::kChoice, @"Touch Controls Opacity",
            @"Controls background blur and border transparency.",
            @"0.85",
            {{@"100% Solid", @"1.0"},
             {@"85% (Recommended)", @"0.85"},
             {@"60% Medium", @"0.60"},
             {@"35% Minimal", @"0.35"}}},
           {@"chord_window", OptionType::kChoice, @"Button Chord Window (Simultaneous)",
            @"Tolerated time between pressing two limb buttons (e.g. 1+2 or 3+4) for simultaneous execution.",
            @"33",
            {{@"2 Frames (33 ms - Tournament Standard)", @"33"},
             {@"3 Frames (50 ms - Lenient)", @"50"},
             {@"Instant (0 ms - Precise)", @"0"}}},
           {@"touch_haptics", OptionType::kSwitch, @"CoreHaptics Strike Vibration",
            @"Provides tactile physical feedback on successful strikes, hits, and counter-attacks.",
            @"true"},
       }, kTabControls},

      // ---------------------------------------------------------------------
      // TAB 4: Audio (Low-Latency CoreAudio)
      // ---------------------------------------------------------------------
      {@"COREAUDIO ENGINE", nil,
       {
           {@"audio_maxqframes", OptionType::kChoice, @"CoreAudio Buffer Size",
            @"Lower values reduce audio latency for punch impacts. 64 frames provides ~1.4 ms response time.",
            @"64",
            {{@"64 Frames (~1.4 ms Ultra-Low Latency)", @"64"},
             {@"128 Frames (~2.9 ms Low Latency)", @"128"},
             {@"256 Frames (~5.8 ms Safe Buffer)", @"256"}}},
           {@"prevent_xma_starve", OptionType::kSwitch, @"Prevent XMA Audio Starve Resets",
            @"Prevents audio channel reset freezes during rapid combat voice exchanges (--ios_xma_starve_reset=false).",
            @"true"},
       }, kTabAudio},

      // ---------------------------------------------------------------------
      // TAB 5: Advanced
      // ---------------------------------------------------------------------
      {@"PERFORMANCE & MEMORY", nil,
       {
           {@"fps_cap", OptionType::kChoice, @"Frame Pacing Cap",
            @"60 FPS is standard arcade fighting speed. 120 FPS unlocks Apple ProMotion.",
            @"60",
            {{@"60 FPS (Arcade Fighting Standard)", @"60"},
             {@"120 FPS (ProMotion Ultra-Smooth)", @"120"},
             {@"30 FPS (Battery Saver)", @"30"}}},
           {@"show_fps", OptionType::kSwitch, @"Show Real-Time FPS Counter",
            @"Displays accurate rendered frames per second and frame time in the top-left corner.",
            @"true"},
           {@"texture_cache_limit", OptionType::kChoice, @"Texture Cache Memory Limit",
            @"Sets memory limits for decoded textures to stay safely within iOS memory boundaries.",
            @"1024",
            {{@"1024 MB Soft / 2048 MB Hard (Recommended for A15+)", @"1024"},
             {@"512 MB Soft / 1024 MB Hard", @"512"},
             {@"384 MB Soft / 768 MB Hard (Low-RAM Devices)", @"384"}}},
           {@"pin_perf_cores", OptionType::kSwitch, @"Pin Worker Threads to Performance Cores",
            @"Prevents iOS from scheduling critical guest threads onto efficiency cores (--ios_utility_qos_guest=false).",
            @"true"},
       }, kTabAdvanced},
      {@"DIAGNOSTICS & LOGS", nil,
       {
           {@"log_level", OptionType::kChoice, @"Engine Log Level",
            @"Logging detail written to Documents/logs/tekken6.log.",
            @"info",
            {{@"Info (Recommended)", @"info"},
             {@"Error Only", @"error"},
             {@"Debug (Verbose)", @"debug"}}},
           {@"export_logs", OptionType::kAction, @"Export Logs (.zip)...",
            @"Packages boot.txt, tekken6.log, settings.json, and breadcrumb crash dumps into a .zip archive.",
            @""},
       }, kTabAdvanced},
  };
  return sections;
}

std::filesystem::path Documents() {
  NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  return fs::path(paths.firstObject.UTF8String);
}

std::vector<fs::path> FindGameSources(const fs::path& documents) {
  std::vector<fs::path> sources;
  std::error_code ec;
  if (!fs::exists(documents, ec)) return sources;

  for (const auto& entry : fs::directory_iterator(documents, ec)) {
    if (entry.is_regular_file()) {
      auto ext = entry.path().extension().string();
      std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
      if (ext == ".iso") {
        sources.push_back(entry.path());
      }
    } else if (entry.is_directory()) {
      if (fs::exists(entry.path() / "default.xex", ec) ||
          fs::exists(entry.path() / "xex" / "tekken6_default.xex", ec)) {
        sources.push_back(entry.path());
      }
    }
  }

  // Also check Documents/game/
  fs::path gameSubdir = documents / "game";
  if (fs::exists(gameSubdir / "default.xex", ec)) {
    sources.push_back(gameSubdir);
  }

  return sources;
}

NSMutableDictionary<NSString*, NSString*>* ReadSettings(const fs::path& documents) {
  NSMutableDictionary<NSString*, NSString*>* dict = [NSMutableDictionary dictionary];
  for (const auto& s : Sections()) {
    for (const auto& o : s.options) {
      if (o.key && o.default_value) {
        dict[o.key] = o.default_value;
      }
    }
  }

  fs::path p = documents / "settings.json";
  std::ifstream f(p);
  if (f.is_open()) {
    std::string line;
    while (std::getline(f, line)) {
      size_t pos = line.find(':');
      if (pos != std::string::npos) {
        std::string k = line.substr(0, pos);
        std::string v = line.substr(pos + 1);
        k.erase(std::remove_if(k.begin(), k.end(), [](char c){ return c=='"'||c==' '||c=='\t'; }), k.end());
        v.erase(std::remove_if(v.begin(), v.end(), [](char c){ return c=='"'||c==','||c==' '||c=='\t'||c=='\r'; }), v.end());
        if (!k.empty()) {
          dict[[NSString stringWithUTF8String:k.c_str()]] = [NSString stringWithUTF8String:v.c_str()];
        }
      }
    }
  }
  return dict;
}

void WriteSettings(const fs::path& documents, NSDictionary<NSString*, NSString*>* settings) {
  fs::path p = documents / "settings.json";
  std::ofstream f(p);
  if (f.is_open()) {
    f << "{\n";
    bool first = true;
    for (NSString* key in settings) {
      NSString* val = settings[key];
      if (!first) f << ",\n";
      first = false;
      f << "  \"" << key.UTF8String << "\": \"" << val.UTF8String << "\"";
    }
    f << "\n}\n";
  }
}

NSString* SettingValue(NSDictionary<NSString*, NSString*>* settings, NSString* key) {
  return settings[key] ?: @"";
}

std::vector<std::string> SettingsArguments(const fs::path& documents) {
  NSMutableDictionary<NSString*, NSString*>* s = ReadSettings(documents);
  std::vector<std::string> args;

  // FPS cap
  NSString* fps = s[@"fps_cap"] ?: @"60";
  args.push_back(std::string("--ios_fps_cap=") + fps.UTF8String);

  // Resolution & Motion Blur
  NSString* res = s[@"resolution"] ?: @"1280x720";
  if ([res isEqualToString:@"native"]) {
    args.push_back("--resolution=1280x720");
    args.push_back("--resolution_scale=2");
  } else {
    args.push_back(std::string("--resolution=") + res.UTF8String);
    args.push_back("--resolution_scale=1");
  }

  // Disable Motion Blur
  BOOL noBlur = [s[@"disable_motion_blur"] boolValue];
  if (noBlur) {
    args.push_back("--tekken6_disable_motion_blur=true");
  }

  // Clear memory page state
  BOOL clr = [s[@"clear_memory_page_state"] boolValue];
  args.push_back(std::string("--clear_memory_page_state=") + (clr ? "true" : "false"));

  // Readback resolve
  NSString* rb = s[@"readback_resolve"] ?: @"fast";
  args.push_back(std::string("--readback_resolve=") + rb.UTF8String);
  args.push_back("--ios_readback_max_kb=64");

  // Vulkan Backend
  NSString* rtp = s[@"render_target_path"] ?: @"fbo";
  args.push_back(std::string("--render_target_path_vulkan=") + rtp.UTF8String);
  args.push_back("--gpu_backend=vulkan");
  args.push_back("--gpu_plugin=xenos");

  // Invalid fetch constants bypass for CRIWARE / FMVs
  BOOL allowInvalid = [s[@"gpu_allow_invalid_fetch"] boolValue];
  args.push_back(std::string("--gpu_allow_invalid_fetch_constants=") + (allowInvalid ? "true" : "false"));

  // Async shader compilation
  BOOL asyncPipe = [s[@"async_pipelines"] boolValue];
  args.push_back(std::string("--async_shader_compilation=") + (asyncPipe ? "true" : "false"));

  // Anisotropic filtering
  NSString* aniso = s[@"anisotropic_override"] ?: @"16";
  args.push_back(std::string("--anisotropic_override=") + aniso.UTF8String);

  // Texture cache limit
  NSString* tc = s[@"texture_cache_limit"] ?: @"1024";
  int tc_int = [tc intValue];
  if (tc_int <= 0) tc_int = 1024;
  args.push_back(std::string("--texture_cache_memory_limit_soft=") + std::to_string(tc_int));
  args.push_back(std::string("--texture_cache_memory_limit_hard=") + std::to_string(tc_int * 2));
  args.push_back("--texture_cache_memory_limit_render_to_texture=128");

  // Audio settings
  NSString* qframes = s[@"audio_maxqframes"] ?: @"64";
  args.push_back(std::string("--audio_maxqframes=") + qframes.UTF8String);
  BOOL starve = [s[@"prevent_xma_starve"] boolValue];
  args.push_back(std::string("--ios_xma_starve_reset=") + (starve ? "false" : "true"));

  // Threading QoS
  BOOL pin = [s[@"pin_perf_cores"] boolValue];
  args.push_back(std::string("--ios_utility_qos_guest=") + (pin ? "false" : "true"));
  args.push_back(std::string("--ios_utility_qos=") + (pin ? "false" : "true"));

  // Log level
  NSString* ll = s[@"log_level"] ?: @"info";
  args.push_back(std::string("--log_level=") + ll.UTF8String);

  // Letterbox & Fullscreen
  args.push_back("--fullscreen=true");
  args.push_back("--present_letterbox=true");
  args.push_back("--mount_scratch=true");
  args.push_back("--mount_cache=true");
  args.push_back("--gpu_sin_msaa=true");
  args.push_back("--ios_async_submits=true");
  args.push_back("--mnk_mode=false");

  return args;
}

}  // namespace tekken6::launcher

using namespace tekken6::launcher;

// ---------------------------------------------------------------------------
//  Launcher Navigation Controller
// ---------------------------------------------------------------------------
@interface Tekken6LauncherNavigation : UINavigationController
@end

@implementation Tekken6LauncherNavigation
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  if (self.presentedViewController && !self.presentedViewController.isBeingDismissed) {
    return self.presentedViewController.supportedInterfaceOrientations;
  }
  return UIInterfaceOrientationMaskLandscape;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
  return UIInterfaceOrientationLandscapeRight;
}
@end

// ---------------------------------------------------------------------------
//  Launcher View Controller
// ---------------------------------------------------------------------------
@interface Tekken6LauncherController () <UIDocumentPickerDelegate>
@end

@implementation Tekken6LauncherController {
  fs::path _documentsPath;
  fs::path _selectedSource;
  NSMutableDictionary<NSString*, NSString*>* _settings;
  NSInteger _currentTab;
  std::function<void(fs::path)> _done;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  return UIInterfaceOrientationMaskLandscape;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
  return UIInterfaceOrientationLandscapeRight;
}

- (fs::path)selectedSource {
  return _selectedSource;
}

- (instancetype)initWithDocuments:(const fs::path&)docs
                             done:(void (^)(std::filesystem::path))doneCallback {
  self = [super initWithStyle:UITableViewStyleInsetGrouped];
  if (self) {
    _documentsPath = docs;
    _done = doneCallback;
    _currentTab = kTabGame;
    _settings = ReadSettings(_documentsPath);
    self.title = @"Tekken 6";

    auto sources = FindGameSources(_documentsPath);
    if (!sources.empty()) {
      _selectedSource = sources.front();
      _settings[@"game_source"] = [NSString stringWithUTF8String:_selectedSource.string().c_str()];
    } else {
      NSString* savedSource = _settings[@"game_source"];
      if (savedSource && savedSource.length > 0) {
        fs::path p(savedSource.UTF8String);
        std::error_code ec;
        if (fs::exists(p, ec)) {
          _selectedSource = p;
        }
      }
    }
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)rescan {
  auto sources = FindGameSources(_documentsPath);
  if (!sources.empty() && _selectedSource.empty()) {
    _selectedSource = sources.front();
    _settings[@"game_source"] = [NSString stringWithUTF8String:_selectedSource.string().c_str()];
  }
  [self.tableView reloadData];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
  self.view.backgroundColor = [UIColor colorWithRed:0.06f green:0.07f blue:0.09f alpha:1.0f];
  self.tableView.backgroundColor = [UIColor colorWithRed:0.06f green:0.07f blue:0.09f alpha:1.0f];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(rescan)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];

  UIBarButtonItem* resetBtn = [[UIBarButtonItem alloc] initWithTitle:@"Reset"
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(resetSettings)];
  resetBtn.tintColor = [UIColor colorWithRed:1.0f green:0.75f blue:0.0f alpha:1.0f]; // Tournament Gold

  UIBarButtonItem* playBtn = [[UIBarButtonItem alloc] initWithTitle:@"Fight"
                                                              style:UIBarButtonItemStyleDone
                                                             target:self
                                                             action:@selector(playGame)];
  playBtn.tintColor = [UIColor colorWithRed:0.92f green:0.22f blue:0.26f alpha:1.0f]; // Tekken Crimson

  self.navigationItem.leftBarButtonItem = resetBtn;
  self.navigationItem.rightBarButtonItem = playBtn;

  UISegmentedControl* segmentedControl = [[UISegmentedControl alloc] initWithItems:TabTitles()];
  segmentedControl.selectedSegmentIndex = _currentTab;
  [segmentedControl addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];

  UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 52)];
  segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
  [header addSubview:segmentedControl];
  [NSLayoutConstraint activateConstraints:@[
    [segmentedControl.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
    [segmentedControl.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
    [segmentedControl.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
  ]];
  self.tableView.tableHeaderView = header;
}

- (void)tabChanged:(UISegmentedControl*)sender {
  _currentTab = sender.selectedSegmentIndex;
  [self.tableView reloadData];
}

- (void)resetSettings {
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Reset Settings"
                                                                 message:@"Restore all Tekken 6 options to default values?"
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
    std::error_code ec;
    fs::remove(self->_documentsPath / "settings.json", ec);
    self->_settings = ReadSettings(self->_documentsPath);
    [self.tableView reloadData];
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)playGame {
  if (_selectedSource.empty()) {
    auto sources = FindGameSources(_documentsPath);
    if (!sources.empty()) {
      _selectedSource = sources.front();
    }
  }

  WriteSettings(_documentsPath, _settings);
  if (_done) {
    _done(_selectedSource);
  }
}

- (std::vector<Section>)visibleSections {
  std::vector<Section> res;
  for (const auto& s : Sections()) {
    if (s.tab == _currentTab) {
      res.push_back(s);
    }
  }
  return res;
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return [self visibleSections].size();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  auto secs = [self visibleSections];
  if (section < (NSInteger)secs.size()) {
    return secs[section].options.size();
  }
  return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  auto secs = [self visibleSections];
  return (section < (NSInteger)secs.size()) ? secs[section].title : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  auto secs = [self visibleSections];
  return (section < (NSInteger)secs.size()) ? secs[section].footer : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  auto secs = [self visibleSections];
  const auto& opt = secs[indexPath.section].options[indexPath.row];

  UITableViewCell* cell = nil;
  if (opt.type == OptionType::kSwitch) {
    cell = [tableView dequeueReusableCellWithIdentifier:@"SwitchCell"];
    if (!cell) {
      cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SwitchCell"];
      cell.selectionStyle = UITableViewCellSelectionStyleNone;
      UISwitch* sw = [[UISwitch alloc] init];
      sw.onTintColor = [UIColor colorWithRed:0.92f green:0.22f blue:0.26f alpha:1.0f];
      [sw addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
      cell.accessoryView = sw;
    }
    UISwitch* sw = (UISwitch*)cell.accessoryView;
    sw.tag = indexPath.section * 100 + indexPath.row;
    sw.on = [_settings[opt.key] boolValue];
  } else {
    cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell"];
    if (!cell) {
      cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DetailCell"];
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    if (opt.type == OptionType::kChoice) {
      NSString* val = _settings[opt.key] ?: opt.default_value;
      NSString* displayVal = val;
      for (const auto& c : opt.choices) {
        if ([c.value isEqualToString:val]) {
          displayVal = c.title;
          break;
        }
      }
      cell.detailTextLabel.text = displayVal;
    } else {
      cell.detailTextLabel.text = @"";
    }
  }

  cell.textLabel.text = opt.title;
  cell.textLabel.textColor = [UIColor whiteColor];
  cell.detailTextLabel.textColor = [UIColor lightGrayColor];
  return cell;
}

- (void)switchToggled:(UISwitch*)sw {
  NSInteger section = sw.tag / 100;
  NSInteger row = sw.tag % 100;
  auto secs = [self visibleSections];
  const auto& opt = secs[section].options[row];
  _settings[opt.key] = sw.isOn ? @"true" : @"false";
  WriteSettings(_documentsPath, _settings);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  auto secs = [self visibleSections];
  const auto& opt = secs[indexPath.section].options[indexPath.row];

  if (opt.type == OptionType::kChoice) {
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:opt.title
                                                                   message:opt.summary
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (const auto& c : opt.choices) {
      [sheet addAction:[UIAlertAction actionWithTitle:c.title
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction*) {
        self->_settings[opt.key] = c.value;
        WriteSettings(self->_documentsPath, self->_settings);
        [self.tableView reloadData];
      }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
      UITableViewCell* cell = [tableView cellForRowAtIndexPath:indexPath];
      sheet.popoverPresentationController.sourceView = cell;
      sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
  } else if ([opt.key isEqualToString:@"choose_iso"]) {
    UIDocumentPickerViewController* picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeDiskImage, [UTType typeWithFilenameExtension:@"iso"]]];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
  } else if ([opt.key isEqualToString:@"choose_folder"]) {
    UIDocumentPickerViewController* picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
  } else if ([opt.key isEqualToString:@"save_manager"]) {
    // Save manager sheet
  } else if ([opt.key isEqualToString:@"export_logs"]) {
    [self exportLogsZip];
  }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  if (urls.count == 0) return;
  NSURL* url = urls.firstObject;
  [url startAccessingSecurityScopedResource];
  _selectedSource = fs::path(url.path.UTF8String);
  _settings[@"game_source"] = [NSString stringWithUTF8String:_selectedSource.string().c_str()];
  WriteSettings(_documentsPath, _settings);
  [self.tableView reloadData];
}

- (void)exportLogsZip {
  fs::path logsDir = _documentsPath / "logs";
  fs::path zipPath = _documentsPath / "tekken6_logs.zip";
  std::string cmd = "cd \"" + logsDir.string() + "\" && zip -r \"" + zipPath.string() + "\" .";
  system(cmd.c_str());

  if (fs::exists(zipPath)) {
    NSURL* fileURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:zipPath.string().c_str()]];
    UIActivityViewController* act = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                      applicationActivities:nil];
    [self presentViewController:act animated:YES completion:nil];
  }
}

@end

// ---------------------------------------------------------------------------
//  Launcher Run Loop Entry
// ---------------------------------------------------------------------------
namespace tekken6::launcher {

fs::path Run(const fs::path& documents) {
  bool finished = false;
  fs::path chosen;
  bool* p_finished = &finished;
  fs::path* p_chosen = &chosen;

  void (^showLauncherAndWait)(void) = ^{
    Tekken6LauncherController* root =
        [[Tekken6LauncherController alloc] initWithDocuments:documents
                                                        done:^(fs::path src) {
                                                          *p_chosen = std::move(src);
                                                          *p_finished = true;
                                                        }];
    UINavigationController* nav = [[Tekken6LauncherNavigation alloc] initWithRootViewController:root];
    nav.navigationBar.prefersLargeTitles = YES;

    UIWindowScene* scene = nil;
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
      if ([s isKindOfClass:UIWindowScene.class] && ((UIWindowScene*)s).screen == UIScreen.mainScreen) {
        scene = (UIWindowScene*)s;
        break;
      }
    }
    UIWindow* window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                             : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    window.windowLevel = UIWindowLevelNormal + 1.0;
    window.rootViewController = nav;
    [window makeKeyAndVisible];

    while (!*p_finished) {
      @autoreleasepool {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:NSDate.distantFuture];
      }
    }

    window.hidden = YES;
    window.rootViewController = nil;
    window = nil;

    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
      if (![s isKindOfClass:UIWindowScene.class]) continue;
      for (UIWindow* w in ((UIWindowScene*)s).windows) {
        if ([w.rootViewController isKindOfClass:Tekken6LauncherNavigation.class]) {
          w.hidden = YES;
          w.rootViewController = nil;
        } else if ([NSStringFromClass(w.rootViewController.class) hasPrefix:@"SDL"]) {
          [w makeKeyAndVisible];
        }
      }
    }
  };

  if ([NSThread isMainThread]) {
    showLauncherAndWait();
  } else {
    dispatch_sync(dispatch_get_main_queue(), showLauncherAndWait);
  }

  return chosen;
}

}  // namespace tekken6::launcher

@implementation Tekken6AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  return YES;
}
@end
