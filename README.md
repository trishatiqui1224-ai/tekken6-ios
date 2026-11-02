# Tekken 6 Recompiled for iOS & iPadOS

<div align="center">

**The Xbox 360 retail release of *Tekken 6* (Title ID: 4E4D07FC, World Multi-Language: En, Ja, Fr, De, Es, It, Ko, Ru), statically recompiled and running natively on Apple Silicon ARM64 with ProMotion 120Hz / 60Hz support.**

![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20iPadOS%2016%2B-black?logo=apple&logoColor=white)
![Architecture](https://img.shields.io/badge/Arch-ARM64%20(Apple%20Silicon)-orange)
![Graphics](https://img.shields.io/badge/Graphics-Metal%203%20%2F%20MoltenVK-blue?logo=vulkan)
![Refresh Rate](https://img.shields.io/badge/Display-ProMotion%20120Hz%20%7C%2060Hz-brightgreen)
![Sideloading](https://img.shields.io/badge/Sideloading-SideStore%20%7C%20LiveContainer%20%7C%20AltStore-purple)

</div>

---

## ⚡ Architecture Overview

This project is **not an emulator**. Tekken 6's Xbox 360 PowerPC bytecode is statically translated ahead-of-time (AOT) into native C++23 machine code using the **ReXGlue SDK** and compiled directly into Apple Silicon ARM64 binaries.

- **Title ID:** `4E4D07FC` (Tekken 6 World retail release).
- **Renderer Backend:** Vulkan translated to Metal via **MoltenVK v1.4.1** using Metal 3 argument buffers, `VK_EXT_fragment_shader_interlock`, and FBO render paths.
- **ProMotion 120Hz / 60Hz:** Dynamic refresh pacing via `CADisableMinimumFrameDurationOnPhone` and `CAFrameRateRange`.
- **Zero Stall Performance:** Occlusion queries disabled (`--occlusion_query_enable=false`), memexport disabled (`--readback_memexport=false`), and resolve readbacks turned off (`--readback_resolve=none`) to guarantee locked 60.0 FPS fighting responsiveness.
- **Audio Output:** Low-latency Apple CoreAudio RemoteIO interleaved stereo driver with 5.1 fold-down and `--ios_xma_starve_reset=false` to prevent context starvation during stage BGM and character themes.
- **Filesystem Sandbox Safety:** Sandbox `$HOME` is read-only on iOS. All directories are pre-created using `std::error_code` into `Documents/rex_data`, `Documents/config`, `Library/Caches`, and `Documents/saves`.

---

## 🎮 Arcade Fighting Touch Control System

### Namco Noir / Vewlix 6-Button Matrix (18° Ergonomic Thumb Arc)
Constructed for high-execution fighting games (EWGF, Korean backdash, quarter-circle, dragon punch motions):

```
       [ L1 (Throw) ]   [ L2 (1+2/3+4) ]               [ START / PAUSE ]

     [ 8-WAY D-PAD ]                        [ LP (1) ]    [ RP (2) ]    [ R1 (Rage) ]
       ▲ / 8-Way                              (X/Cyan)     (Y/Gold)      (RB/Red)
   ◀   ●   ▶                                [ LK (3) ]    [ RK (4) ]    [ R2 (Special) ]
       ▼                                     (A/Green)     (B/Crimson)   (RT/Violet)
```

| Button | Tekken Notation | Xbox 360 | Color Theme | Description |
|:---|:---|:---|:---|:---|
| **LP (1)** | Left Punch | **X** | Cyan (`#00E5FF`) | Quick jabs, 10-frame strings, high punch |
| **RP (2)** | Right Punch | **Y** | Gold (`#FFD600`) | Launchers, power punches |
| **LK (3)** | Left Kick | **A** | Emerald (`#00E676`) | Low/mid kicks |
| **RK (4)** | Right Kick | **B** | Crimson (`#FF1744`) | Launching kicks, roundhouses |
| **R1** | Rage / Grab | **RB** | Hot Red | Rage Drive / Rage Arts / Grab |
| **R2** | Item / Special | **RT** | Violet | Custom item move / Special attack |
| **L1** | Throw (1+3) | **LB** | Silver | Instant throw macro |
| **L2** | 1+2 / 3+4 | **LT** | Silver | Power crush / stance macro |
| **8-Way D-Pad** | Directional | **D-Pad** | Illuminated | 8-way precision gate for `236`, `214`, `623` motions |

- **Passthrough Overlay (`zPosition = 9999`):** Built with `TouchOverlayContainerView` with non-button touch forwarding, `delaysTouchesBegan = NO`, and `multipleTouchEnabled = YES`.
- **CoreHaptics:** Crisp tactile click pulses on button strikes via `UIImpactFeedbackGenerator`.
- **Physical Gamepad Support:** Native `GameController.framework` automatically hides touch controls when an MFi / Xbox / DualSense controller connects.

---

## 🎨 Studio-Grade AppIcon Generator (`tools/generate_appicon.py`)

Generates a 4096x4096 procedural master downsampled via Lanczos to 1024x1024 + all iOS `AppIcon.appiconset` sizes (strict 24-bit zero-alpha RGB, validated `Contents.json`):

```bash
# Generate default "King of Iron Fist" Fist Clash icon
python3 tools/generate_appicon.py --style fist

# Generate Mishima electric lightning icon
python3 tools/generate_appicon.py --style lightning

# Generate pure championship brushed-gold emblem icon
python3 tools/generate_appicon.py --style gold

# Use custom box-art image
python3 tools/generate_appicon.py --input /path/to/boxart.png
```

Preview sheet output: `tools/icon_preview_sheet.png`.

---

## 🛠️ Step-by-Step Recompilation Pipeline

### 1. Stage Retail Game Binary
Place your dumped retail Tekken 6 `default.xex` (Title ID: `4E4D07FC`) into `xex/tekken6_default.xex`.

### 2. Prepare ReXGlue SDK
```bash
python3 tools/ios/prepare_sdk.py
```
Applies all mandatory iOS cross-compilation fixes:
- Skips submodule MoltenVK and desktop `vulkan-loader`.
- Embeds MoltenVK v1.4.1 XCFramework for iOS ARM64.
- Eliminates `-Wasm-operand-widths` via ARM64 `fpscr.h` 64-bit cast.
- Patches POSIX path resolver for iOS sandbox and LiveContainer.
- Serializes Vulkan pipeline cache (`4E4D07FC.fbo.*.vkcache`) behind an atomic mutex.

### 3. Translate PowerPC to ARM64 C++
```bash
python3 tools/build_tekken6_codegen.py
```
- Parses 14,983 ground-truth PE `.pdata` function bounds.
- Discovers 238 PowerPC switch tables and 2,373 `.rdata`/`.data` function pointers.
- Heals unresolved branch targets until strictly **0 unresolved branches** remain.
- Registers genuine Tekken 6 hooks: entry point `0x824BEA50`, privilege check `0x824BE868`, engine `main()` `0x82170000`, `XamLoaderTerminateTitle` `0x826CCBE4`, and `DbgPrint` `0x826CCD34`.

### 4. Build Unsigned IPA Package
```bash
cd ios
cmake --preset ios
cmake --build --preset ios --target ipa
# Output: ios/build-ios/Tekken6-iOS-unsigned.ipa
```

---

## 📦 Sideloading & Game Asset Setup

### Sideloading
1. Transfer `Tekken6-iOS-unsigned.ipa` to your iPhone or iPad.
2. Install via **SideStore**, **LiveContainer**, **AltStore**, or **TrollStore**.
   - Note: The app includes `com.apple.developer.kernel.increased-memory-limit` and `extended-virtual-addressing` entitlements.

### Where to Place Game Data
1. Open the **Files** app on iOS.
2. Navigate to: **On My iPhone/iPad > Tekken 6 > game**
3. Copy your extracted game assets:
   - `default.xex`
   - `DATA301.BIN` through `DATA320.BIN`
   - `DATA301.IDX` through `DATA320.IDX`
   - `DINF_300.BIN`
4. Launch Tekken 6! The combat dashboard will detect the assets and start in 60 FPS / 120 FPS native gameplay mode!

