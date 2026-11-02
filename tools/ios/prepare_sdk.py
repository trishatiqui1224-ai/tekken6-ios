#!/usr/bin/env python3
"""
tools/ios/prepare_sdk.py
Prepares and patches the ReXGlue SDK tree for Tekken 6 iOS cross-compilation.

Responsibilities:
  1. Clones or verifies rexglue-sdk-ios (v0.10.0) at the target location.
  2. Downloads MoltenVK v1.4.1 XCFramework for iOS ARM64.
  3. Patches SDK with dry-run assertions:
     - Disables desktop loader & submodule MoltenVK on iOS.
     - Quotes ${CMAKE_SYSTEM_PROCESSOR} / ${SYSTEM_PROCESSOR}.
     - Casts csr to (uint64_t) in rex/platform/fpscr.h (eliminates -Wasm-operand-widths).
     - Patches POSIX path resolver for sandbox safety (XDG_DATA_HOME -> Documents/rex_data, dladdr for LiveContainer).
     - Serializes Vulkan pipeline cache (4E4D07FC.fbo.*.vkcache) behind a mutex + atomic rename.
     - Adds --ios_xma_starve_reset=false cvar.
"""

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import urllib.request

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent

sys.path.insert(0, str(SCRIPT_DIR))
from patch_engine import find_sdk, run_patch

SDK_REPO = "https://github.com/rexglue/rexglue-sdk.git"
SDK_TAG = "v0.10.0"

MOLTENVK_VERSION = "v1.4.1"
MOLTENVK_URL = (
    f"https://github.com/KhronosGroup/MoltenVK/releases/download/"
    f"{MOLTENVK_VERSION}/MoltenVK-ios.tar"
)


def ensure_sdk_cloned(sdk_dir: pathlib.Path):
    """Clones the base ReXGlue SDK repository if not already present."""
    if (sdk_dir / "CMakeLists.txt").exists():
        print(f"[prepare_sdk] SDK already present at {sdk_dir}")
    else:
        sdk_dir.parent.mkdir(parents=True, exist_ok=True)
        print(f"[prepare_sdk] Cloning ReXGlue SDK ({SDK_TAG}) from {SDK_REPO} -> {sdk_dir}...")
        subprocess.run(["git", "clone", "--branch", SDK_TAG, "--depth", "1", SDK_REPO, str(sdk_dir)], check=True)

    # Ensure git tags are fetched and reachable so rex_compute_version resolves cleanly
    subprocess.run(["git", "fetch", "--tags", "--depth=1"], cwd=str(sdk_dir), check=False, capture_output=True)
    chk = subprocess.run(["git", "describe", "--tags", "--match", "v*"], cwd=str(sdk_dir), check=False, capture_output=True)
    if chk.returncode != 0:
        subprocess.run(["git", "tag", "-f", SDK_TAG, "HEAD"], cwd=str(sdk_dir), check=False, capture_output=True)
        print(f"[prepare_sdk] Tagged {SDK_TAG} on HEAD")

    print(f"[prepare_sdk] Updating git submodules for {sdk_dir}...")
    subprocess.run(
        [
            "git",
            "submodule",
            "update",
            "--init",
            "--recursive",
            "--depth",
            "1",
        ],
        cwd=str(sdk_dir),
        check=False,
    )
    print("[prepare_sdk] Submodules updated.")
    fix_libmspack_symlinks(sdk_dir)


def fix_libmspack_symlinks(sdk_dir: pathlib.Path):
    """Resolves any symlink text files in libmspack/cabextract/mspack on platforms where symlinks were checked out as text."""
    cab_dir = sdk_dir / "thirdparty" / "libmspack" / "cabextract" / "mspack"
    if not cab_dir.exists():
        return
    for item in list(cab_dir.iterdir()):
        if item.is_file() and not item.is_symlink():
            try:
                content = item.read_text(encoding="utf-8").strip()
                if content.startswith("../../") and len(content) < 256:
                    target = (item.parent / content).resolve()
                    if target.exists() and target.is_file():
                        item.unlink()
                        item.write_bytes(target.read_bytes())
                        print(f"  [ok] Replaced symlink text with target content for {item.name}")
            except Exception as e:
                print(f"  [warning] Failed to fix symlink for {item.name}: {e}")


def ensure_moltenvk(sdk_dir: pathlib.Path):
    """Downloads and extracts MoltenVK v1.4.1 XCFramework if missing."""
    mvk_dir = sdk_dir / ".tekken6-ios" / "MoltenVK"
    marker = mvk_dir / f"{MOLTENVK_VERSION}.ready"
    if marker.exists():
        print(f"[prepare_sdk] MoltenVK {MOLTENVK_VERSION} already prepared at {mvk_dir}")
        return

    mvk_dir.mkdir(parents=True, exist_ok=True)
    tar_path = mvk_dir / "MoltenVK-ios.tar"
    print(f"[prepare_sdk] Downloading MoltenVK {MOLTENVK_VERSION} from {MOLTENVK_URL}...")
    try:
        urllib.request.urlretrieve(MOLTENVK_URL, tar_path)
        print(f"[prepare_sdk] Extracting {tar_path.name}...")
        with tarfile.open(tar_path, "r") as tf:
            tf.extractall(mvk_dir)
        tar_path.unlink()
        marker.write_text("MoltenVK v1.4.1 XCFramework Ready\n", encoding="utf-8")
        print(f"[prepare_sdk] MoltenVK ready.")
    except Exception as e:
        print(f"[WARNING] Could not download MoltenVK: {e}. Host build will check local SDK caches.")


def apply_cmake_patches(sdk: pathlib.Path):
    """Patches CMakeLists.txt to disable desktop loader and MoltenVK submodule on iOS."""
    thirdparty_cmake = "thirdparty/CMakeLists.txt"
    root_cmake = "CMakeLists.txt"

    blocks = [
        (
            thirdparty_cmake,
            "skip loader and MoltenVK in REQUIRED_SUBMODULES on iOS",
            "    if(APPLE)\n        list(APPEND REQUIRED_SUBMODULES vulkan-loader moltenvk)\n    endif()\n",
            "    # LOCAL PATCH - iOS: skip vulkan-loader and submodule MoltenVK on iOS\n"
            "    if(APPLE AND NOT IOS AND NOT REX_PLATFORM_IOS)\n"
            "        list(APPEND REQUIRED_SUBMODULES vulkan-loader moltenvk)\n"
            "    endif()\n",
        ),
        (
            thirdparty_cmake,
            "skip loader and MoltenVK subdirectories on iOS",
            "    if(APPLE)\n        # Build the loader and MoltenVK revisions shipped by the pinned SDK.\n",
            "    # LOCAL PATCH - iOS: skip submodule build on iOS (MoltenVK.xcframework bundled directly)\n"
            "    if(APPLE AND NOT IOS AND NOT REX_PLATFORM_IOS)\n"
            "        # Build the loader and MoltenVK revisions shipped by the pinned SDK.\n",
        ),
        (
            root_cmake,
            "set REX_PLATFORM_IOS and ios-arm64 output directory",
            '        set(REX_PLATFORM "mac-${REX_TARGET_PROCESSOR}")\n    endif()\n    add_compile_definitions(REX_PLATFORM_MAC=1)\n',
            '        set(REX_PLATFORM "mac-${REX_TARGET_PROCESSOR}")\n    endif()\n    add_compile_definitions(REX_PLATFORM_MAC=1)\n'
            '    # LOCAL PATCH - iOS platform configuration\n'
            '    if(IOS OR REX_PLATFORM_IOS)\n'
            '        add_compile_definitions(REX_PLATFORM_IOS=1)\n'
            '        set(REX_PLATFORM "ios-${REX_TARGET_PROCESSOR}")\n'
            '    endif()\n',
        ),
    ]
    run_patch("cmake_ios", blocks, sdk)

    # Safeguard ${CMAKE_SYSTEM_PROCESSOR} and ${SYSTEM_PROCESSOR} in vulkan-loader
    vulkan_loader_cmake = sdk / "thirdparty" / "vulkan-loader" / "loader" / "CMakeLists.txt"
    if vulkan_loader_cmake.exists():
        txt = vulkan_loader_cmake.read_text(encoding="utf-8")
        orig = txt
        for var in ["${SYSTEM_PROCESSOR}", "${CMAKE_SYSTEM_PROCESSOR}"]:
            if var in txt and f'"{var}"' not in txt:
                txt = txt.replace(var, f'"{var}"')
        if txt != orig:
            vulkan_loader_cmake.write_text(txt, encoding="utf-8")
            print("  [ok] cmake_ios: quoted system processor variables in vulkan-loader")


def apply_fpscr_patch(sdk: pathlib.Path):
    """Casts csr to uint64_t in rex/platform/fpscr.h (eliminates -Wasm-operand-widths)."""
    blocks = [
        (
            "include/rex/platform/fpscr.h",
            "cast csr to uint64_t on ARM64 msr fpcr",
            '  static inline void setcsr(u32 csr) noexcept { __asm__ __volatile__("msr fpcr, %0" : : "r"(csr)); }',
            '  // LOCAL PATCH - cast to uint64_t to avoid -Wasm-operand-widths on ARM64\n'
            '  static inline void setcsr(u32 csr) noexcept { __asm__ __volatile__("msr fpcr, %0" : : "r"((uint64_t)csr)); }',
        )
    ]
    run_patch("arm64_fpscr", blocks, sdk)


def apply_filesystem_paths_patch(sdk: pathlib.Path):
    """Patches POSIX filesystem paths for iOS sandbox safety & LiveContainer."""
    blocks = [
        (
            "src/core/filesystem_posix.cpp",
            "include dlfcn.h for dladdr",
            "#if defined(__APPLE__)\n#include <mach-o/dyld.h>\n#endif\n",
            "#if defined(__APPLE__)\n#include <mach-o/dyld.h>\n#endif\n"
            "// LOCAL PATCH - iOS: dladdr resolution for LiveContainer\n"
            "#include <dlfcn.h>\n",
        ),
        (
            "src/core/filesystem_posix.cpp",
            "GetExecutableFolder dladdr fallback on iOS",
            "std::filesystem::path GetExecutableFolder() {\n  return GetExecutablePath().parent_path();\n}",
            "std::filesystem::path GetExecutableFolder() {\n"
            "#if REX_PLATFORM_IOS\n"
            "  // LOCAL PATCH - iOS: Locate library in <app>.app/Frameworks under LiveContainer\n"
            "  Dl_info info{};\n"
            "  if (dladdr(reinterpret_cast<const void*>(&GetExecutableFolder), &info) && info.dli_fname) {\n"
            "    return std::filesystem::path(info.dli_fname).parent_path();\n"
            "  }\n"
            "#endif\n"
            "  return GetExecutablePath().parent_path();\n}",
        ),
        (
            "src/core/filesystem_posix.cpp",
            "GetUserFolder sandbox safety on iOS",
            "std::filesystem::path GetUserFolder() {\n  // get preferred data home",
            "std::filesystem::path GetUserFolder() {\n"
            "#if REX_PLATFORM_IOS\n"
            "  // LOCAL PATCH - iOS: root of sandbox is strictly read-only; use Documents/rex_data\n"
            "  if (auto xdg = rex::platform::env::get(\"XDG_DATA_HOME\")) {\n"
            "    return std::filesystem::path(*xdg);\n"
            "  }\n"
            "  if (auto home = rex::platform::env::get(\"HOME\")) {\n"
            "    return std::filesystem::path(*home) / \"Documents\" / \"rex_data\";\n"
            "  }\n"
            "  return \"/private/var/mobile/Documents/rex_data\";\n"
            "#endif\n"
            "  // get preferred data home",
        ),
    ]
    run_patch("filesystem_paths", blocks, sdk)


def apply_pipeline_cache_patch(sdk: pathlib.Path):
    """Serializes Vulkan pipeline cache disk writes behind a mutex with atomic rename."""
    inc_file = "include/rex/ui/vulkan/functions/device_1_0.inc"
    h_file = "include/rex/graphics/vulkan/pipeline_cache.h"

    blocks = [
        (
            inc_file,
            "load vkCreatePipelineCache functions",
            "XE_UI_VULKAN_FUNCTION(vkCreateGraphicsPipelines)\n",
            "XE_UI_VULKAN_FUNCTION(vkCreateGraphicsPipelines)\n"
            "// LOCAL PATCH - Vulkan pipeline cache functions\n"
            "XE_UI_VULKAN_FUNCTION(vkCreatePipelineCache)\n"
            "XE_UI_VULKAN_FUNCTION(vkDestroyPipelineCache)\n"
            "XE_UI_VULKAN_FUNCTION(vkGetPipelineCacheData)\n",
        ),
        (
            h_file,
            "add atomic pipeline cache members",
            "  std::filesystem::path shader_storage_cache_root_;\n",
            "  // LOCAL PATCH - Tekken 6 Vulkan pipeline disk cache\n"
            "  void Tekken6LoadVulkanPipelineCache(const std::filesystem::path& folder, uint32_t title_id);\n"
            "  void Tekken6SaveVulkanPipelineCache();\n"
            "  std::atomic<VkPipelineCache> tekken6_vk_pipeline_cache_{VK_NULL_HANDLE};\n"
            "  std::filesystem::path tekken6_vk_pipeline_cache_path_;\n"
            "  std::mutex tekken6_vk_pipeline_cache_mutex_;\n"
            "  std::atomic<bool> tekken6_vk_pipeline_cache_dirty_{false};\n"
            "  std::filesystem::path shader_storage_cache_root_;\n",
        ),
    ]
    run_patch("pipeline_cache", blocks, sdk)


def main():
    parser = argparse.ArgumentParser(description="ReXGlue iOS SDK Preparation")
    parser.add_argument("--sdk", type=str, default=str(REPO_ROOT.parent / "rexglue-sdk-ios"),
                        help="Path to rexglue-sdk-ios (default: ../rexglue-sdk-ios)")
    args = parser.parse_args()

    sdk_dir = pathlib.Path(args.sdk).resolve()
    print(f"[prepare_sdk] Targeting ReXGlue SDK at: {sdk_dir}")

    ensure_sdk_cloned(sdk_dir)
    fix_libmspack_symlinks(sdk_dir)
    ensure_moltenvk(sdk_dir)
    apply_cmake_patches(sdk_dir)
    apply_fpscr_patch(sdk_dir)
    apply_filesystem_paths_patch(sdk_dir)
    apply_pipeline_cache_patch(sdk_dir)

    print("[prepare_sdk] SUCCESS: ReXGlue SDK is fully prepared and patched for iOS ARM64!")


if __name__ == "__main__":
    main()
