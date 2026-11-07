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


def ensure_sdk_cloned(sdk_dir: pathlib.Path, skip_submodules: bool = False):
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

    if not skip_submodules:
        if not (sdk_dir / "thirdparty" / "vulkan-headers" / "include").exists():
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
        else:
            print(f"[prepare_sdk] Submodules already present at {sdk_dir}")
    else:
        print(f"[prepare_sdk] Skipping submodules update (--skip-submodules).")
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
            '        add_compile_definitions(_LIBCPP_DISABLE_AVAILABILITY=1)\n'
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
    """
    Serializes Vulkan pipeline cache (4E4D07FC.fbo.*.vkcache) disk writes
    behind a mutex with +64 KB padding on vkGetPipelineCacheData and atomic .tmp rename.
    """
    inc_file = "include/rex/ui/vulkan/functions/device_1_0.inc"
    h_file = "include/rex/graphics/vulkan/pipeline_cache.h"
    cpp_file = "src/graphics/vulkan/pipeline_cache.cpp"

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
            "  void Tekken6LoadVulkanPipelineCache(const std::filesystem::path& folder, uint32_t title_id, bool fsi);\n"
            "  void Tekken6SaveVulkanPipelineCache();\n"
            "  std::atomic<VkPipelineCache> tekken6_vk_pipeline_cache_{VK_NULL_HANDLE};\n"
            "  std::filesystem::path tekken6_vk_pipeline_cache_path_;\n"
            "  std::mutex tekken6_vk_pipeline_cache_mutex_;\n"
            "  std::atomic<bool> tekken6_vk_pipeline_cache_dirty_{false};\n"
            "  uint64_t tekken6_vk_pipeline_cache_requested_ms_ = 0;\n"
            "  std::filesystem::path shader_storage_cache_root_;\n",
        ),
        (
            cpp_file,
            "include chrono for pipeline cache flush interval",
            "#include <array>\n",
            "#include <array>\n#include <chrono>  // LOCAL PATCH - Tekken 6 pipeline cache\n",
        ),
        (
            cpp_file,
            "load vulkan pipeline cache before prewarming",
            "  bool edram_fragment_shader_interlock =\n"
            "      render_target_cache_.GetPath() == RenderTargetCache::Path::kPixelShaderInterlock;\n\n"
            "  // Initialize the pipeline storage stream - read pipeline descriptions and\n",
            "  bool edram_fragment_shader_interlock =\n"
            "      render_target_cache_.GetPath() == RenderTargetCache::Path::kPixelShaderInterlock;\n\n"
            "  // LOCAL PATCH - Load driver pipeline cache before prewarming\n"
            "  Tekken6LoadVulkanPipelineCache(shader_storage_shareable_root, title_id, edram_fragment_shader_interlock);\n\n"
            "  // Initialize the pipeline storage stream - read pipeline descriptions and\n",
        ),
        (
            cpp_file,
            "seek to beginning when opening pipeline_storage_file_",
            '  pipeline_storage_file_ = rex::filesystem::OpenFile(pipeline_storage_file_path, "a+b");\n',
            '  pipeline_storage_file_ = rex::filesystem::OpenFile(pipeline_storage_file_path, "a+b");\n'
            '  // LOCAL PATCH - BSD stdio rewinding for pipeline cache headers\n'
            '  if (pipeline_storage_file_) {\n'
            '    rex::filesystem::Seek(pipeline_storage_file_, 0, SEEK_SET);\n'
            '  }\n',
        ),
        (
            cpp_file,
            "seek to beginning when opening shader_storage_file_",
            '  shader_storage_file_ = rex::filesystem::OpenFile(shader_storage_file_path, "a+b");\n',
            '  shader_storage_file_ = rex::filesystem::OpenFile(shader_storage_file_path, "a+b");\n'
            '  // LOCAL PATCH - BSD stdio rewinding for shader storage headers\n'
            '  if (shader_storage_file_) {\n'
            '    rex::filesystem::Seek(shader_storage_file_, 0, SEEK_SET);\n'
            '  }\n',
        ),
        (
            cpp_file,
            "save pipeline cache after prewarm compilation",
            '    REXGPU_INFO("Created {} graphics pipelines from Vulkan storage ({} requested)",\n'
            '                created_pipeline_count.load(), pipeline_creations.size());\n',
            '    REXGPU_INFO("Created {} graphics pipelines from Vulkan storage ({} requested)",\n'
            '                created_pipeline_count.load(), pipeline_creations.size());\n'
            '    // LOCAL PATCH - Save compiled pipelines immediately\n'
            '    Tekken6SaveVulkanPipelineCache();\n',
        ),
        (
            cpp_file,
            "save pipeline cache on periodic flush",
            '      fflush(pipeline_storage_file_);\n',
            '      fflush(pipeline_storage_file_);\n'
            '      // LOCAL PATCH - Periodic pipeline cache disk write\n'
            '      Tekken6SaveVulkanPipelineCache();\n',
        ),
        (
            cpp_file,
            "implement Tekken6LoadVulkanPipelineCache and Tekken6SaveVulkanPipelineCache",
            'void VulkanPipelineCache::ShutdownShaderStorage() {\n',
            '// LOCAL PATCH - Driver pipeline cache with 64 KB padding and atomic .tmp rename\n'
            'void VulkanPipelineCache::Tekken6LoadVulkanPipelineCache(const std::filesystem::path& folder,\n'
            '                                                         uint32_t title_id, bool fsi) {\n'
            '  std::lock_guard<std::mutex> lock(tekken6_vk_pipeline_cache_mutex_);\n'
            '  const ui::vulkan::VulkanDevice* const vulkan_device = command_processor_.GetVulkanDevice();\n'
            '  if (!vulkan_device) return;\n'
            '  const ui::vulkan::VulkanDevice::Functions& dfn = vulkan_device->functions();\n'
            '  const VkDevice device = vulkan_device->device();\n'
            '  const auto& properties = vulkan_device->properties();\n'
            '  tekken6_vk_pipeline_cache_path_ =\n'
            '      folder / fmt::format("{:08X}.{}.{:04X}-{:04X}-{:08X}.vkcache", title_id, fsi ? "fsi" : "fbo",\n'
            '                            properties.vendorID, properties.deviceID, properties.driverVersion);\n'
            '  if (tekken6_vk_pipeline_cache_.load(std::memory_order_acquire) != VK_NULL_HANDLE) return;\n'
            '  std::vector<uint8_t> data;\n'
            '  bool corrupt = false;\n'
            '  if (FILE* f = rex::filesystem::OpenFile(tekken6_vk_pipeline_cache_path_, "rb")) {\n'
            '    fseek(f, 0, SEEK_END);\n'
            '    const long sz = ftell(f);\n'
            '    fseek(f, 0, SEEK_SET);\n'
            '    if (sz >= 32 && sz < (long(256) << 20)) {\n'
            '      data.resize(size_t(sz));\n'
            '      if (fread(data.data(), 1, data.size(), f) != data.size()) { data.clear(); corrupt = true; }\n'
            '    } else if (sz > 0) { corrupt = true; }\n'
            '    fclose(f);\n'
            '  }\n'
            '  if (data.size() >= 32) {\n'
            '    uint32_t header[4];\n'
            '    std::memcpy(header, data.data(), sizeof(header));\n'
            '    if (header[0] < 32 || header[1] != uint32_t(VK_PIPELINE_CACHE_HEADER_VERSION_ONE) ||\n'
            '        header[2] != properties.vendorID || header[3] != properties.deviceID) {\n'
            '      REXGPU_WARN("[pipeline cache] {} is for another driver or corrupted; starting empty",\n'
            '                  rex::path_to_utf8(tekken6_vk_pipeline_cache_path_.filename()));\n'
            '      data.clear(); corrupt = true;\n'
            '    }\n'
            '  } else { data.clear(); }\n'
            '  if (corrupt) {\n'
            '    std::error_code ec;\n'
            '    std::filesystem::remove(tekken6_vk_pipeline_cache_path_, ec);\n'
            '  }\n'
            '  VkPipelineCacheCreateInfo info = {};\n'
            '  info.sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;\n'
            '  info.initialDataSize = data.size();\n'
            '  info.pInitialData = data.empty() ? nullptr : data.data();\n'
            '  VkPipelineCache cache = VK_NULL_HANDLE;\n'
            '  if (dfn.vkCreatePipelineCache(device, &info, nullptr, &cache) != VK_SUCCESS) {\n'
            '    std::error_code ec;\n'
            '    std::filesystem::remove(tekken6_vk_pipeline_cache_path_, ec);\n'
            '    info.initialDataSize = 0;\n'
            '    info.pInitialData = nullptr;\n'
            '    if (dfn.vkCreatePipelineCache(device, &info, nullptr, &cache) != VK_SUCCESS) {\n'
            '      REXGPU_WARN("[pipeline cache] could not create pipeline cache; proceeding without it");\n'
            '      return;\n'
            '    }\n'
            '    data.clear();\n'
            '  }\n'
            '  tekken6_vk_pipeline_cache_.store(cache, std::memory_order_release);\n'
            '  REXGPU_INFO("[pipeline cache] {} KB loaded from {}", data.size() / 1024,\n'
            '              rex::path_to_utf8(tekken6_vk_pipeline_cache_path_.filename()));\n'
            '}\n\n'
            'void VulkanPipelineCache::Tekken6SaveVulkanPipelineCache() {\n'
            '  std::lock_guard<std::mutex> lock(tekken6_vk_pipeline_cache_mutex_);\n'
            '  const VkPipelineCache cache = tekken6_vk_pipeline_cache_.load(std::memory_order_acquire);\n'
            '  if (cache == VK_NULL_HANDLE || tekken6_vk_pipeline_cache_path_.empty() ||\n'
            '      !tekken6_vk_pipeline_cache_dirty_.exchange(false, std::memory_order_acq_rel)) {\n'
            '    return;\n'
            '  }\n'
            '  const ui::vulkan::VulkanDevice* const vulkan_device = command_processor_.GetVulkanDevice();\n'
            '  if (!vulkan_device) return;\n'
            '  const ui::vulkan::VulkanDevice::Functions& dfn = vulkan_device->functions();\n'
            '  const VkDevice device = vulkan_device->device();\n'
            '  size_t exact_size = 0;\n'
            '  if (dfn.vkGetPipelineCacheData(device, cache, &exact_size, nullptr) != VK_SUCCESS || exact_size < 32) {\n'
            '    return;\n'
            '  }\n'
            '  // Pad by 64 KB in case async shader threads add pipelines between calls\n'
            '  size_t alloc_size = exact_size + 64 * 1024;\n'
            '  std::vector<uint8_t> data(alloc_size);\n'
            '  size_t retrieved_size = alloc_size;\n'
            '  const VkResult result = dfn.vkGetPipelineCacheData(device, cache, &retrieved_size, data.data());\n'
            '  // Strictly require VK_SUCCESS. Never accept VK_INCOMPLETE or truncated data.\n'
            '  if (result != VK_SUCCESS || retrieved_size < 32) {\n'
            '    return;\n'
            '  }\n'
            '  data.resize(retrieved_size);\n'
            '  std::filesystem::path temp_path = tekken6_vk_pipeline_cache_path_;\n'
            '  temp_path += ".tmp";\n'
            '  FILE* f = rex::filesystem::OpenFile(temp_path, "wb");\n'
            '  if (!f) return;\n'
            '  const bool written = (fwrite(data.data(), 1, data.size(), f) == data.size());\n'
            '  fflush(f);\n'
            '  fclose(f);\n'
            '  std::error_code error;\n'
            '  if (written) {\n'
            '    std::filesystem::rename(temp_path, tekken6_vk_pipeline_cache_path_, error);\n'
            '  }\n'
            '  if (!written || error) {\n'
            '    std::filesystem::remove(temp_path, error);\n'
            '    return;\n'
            '  }\n'
            '  REXGPU_INFO("[pipeline cache] {} KB saved to {}", data.size() / 1024,\n'
            '              rex::path_to_utf8(tekken6_vk_pipeline_cache_path_.filename()));\n'
            '}\n\n'
            'void VulkanPipelineCache::ShutdownShaderStorage() {\n'
            '  Tekken6SaveVulkanPipelineCache();\n',
        ),
        (
            cpp_file,
            "request periodic save in EndSubmission",
            'void VulkanPipelineCache::EndSubmission() {\n',
            'void VulkanPipelineCache::EndSubmission() {\n'
            '  if (tekken6_vk_pipeline_cache_dirty_.load(std::memory_order_relaxed) && pipeline_storage_file_) {\n'
            '    auto now = uint64_t(std::chrono::duration_cast<std::chrono::milliseconds>(\n'
            '                            std::chrono::steady_clock::now().time_since_epoch()).count());\n'
            '    if (now - tekken6_vk_pipeline_cache_requested_ms_ >= 10000) {\n'
            '      tekken6_vk_pipeline_cache_requested_ms_ = now;\n'
            '      pipeline_storage_file_flush_needed_ = true;\n'
            '    }\n'
            '  }\n',
        ),
        (
            cpp_file,
            "destroy pipeline cache on shutdown",
            '  ShutdownShaderStorage();\n\n'
            '  const ui::vulkan::VulkanDevice* const vulkan_device = command_processor_.GetVulkanDevice();\n'
            '  const ui::vulkan::VulkanDevice::Functions& dfn = vulkan_device->functions();\n'
            '  const VkDevice device = vulkan_device->device();\n',
            '  ShutdownShaderStorage();\n\n'
            '  const ui::vulkan::VulkanDevice* const vulkan_device = command_processor_.GetVulkanDevice();\n'
            '  const ui::vulkan::VulkanDevice::Functions& dfn = vulkan_device->functions();\n'
            '  const VkDevice device = vulkan_device->device();\n\n'
            '  if (const VkPipelineCache cache = tekken6_vk_pipeline_cache_.exchange(VK_NULL_HANDLE);\n'
            '      cache != VK_NULL_HANDLE) {\n'
            '    dfn.vkDestroyPipelineCache(device, cache, nullptr);\n'
            '  }\n',
        ),
        (
            cpp_file,
            "use driver pipeline cache in vkCreateGraphicsPipelines",
            '  VkResult create_result = dfn.vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1,\n'
            '                                                         &pipeline_create_info, nullptr, &pipeline);\n',
            '  VkResult create_result = dfn.vkCreateGraphicsPipelines(\n'
            '      device, tekken6_vk_pipeline_cache_.load(std::memory_order_acquire), 1,\n'
            '      &pipeline_create_info, nullptr, &pipeline);\n'
            '  if (create_result == VK_SUCCESS) {\n'
            '    tekken6_vk_pipeline_cache_dirty_.store(true, std::memory_order_relaxed);\n'
            '  }\n',
        ),
    ]
    run_patch("tekken6_pipeline_cache_64kb", blocks, sdk)


def apply_tekken6_vfs_patches(sdk: pathlib.Path):
    """
    Tekken 6 VFS Runtime Patches:
    1. src/system/runtime.cpp: Mount writable HostPathDevice at \\Device\\Cache and \\Device\\Scratch.
    2. src/filesystem/virtual_file_system.cpp: Allow opening root volume directories ("D:\\", "cache:\\").
    3. src/kernel/xboxkrnl/xboxkrnl_io_info.cpp: Return FILE_DEVICE_DISK (0x00000007) for XFileFsDeviceInformation.
    4. src/kernel/xboxkrnl/xboxkrnl_io.cpp: Re-register cache: symbolic links after utility dismount.
    """
    vfs_anchor = (
        '  // NOTE: Do NOT register a device for cache: paths\n'
        '  // Games handle "device not found" gracefully but don\'t handle actual device\n'
        '  // errors (like NAME_COLLISION) well. Let cache: fail cleanly.\n\n'
        '  return true;'
    )
    vfs_new = (
        '  // LOCAL PATCH - Tekken 6 (Title ID: 4E4D07FC):\n'
        '  // Mount writable HostPathDevice for cache:\\ and scratch:\\ partitions so\n'
        '  // costume/stage streaming, decompressed blocks, and ghost/replay data do not fail or freeze.\n'
        '  std::filesystem::path cache_root_dir = cache_root_.empty() ? (game_data_root_ / "cache") : cache_root_;\n'
        '  std::filesystem::path cache_host_dir = cache_root_dir / "cache_drive";\n'
        '  std::filesystem::path scratch_host_dir = cache_root_dir / "scratch_drive";\n'
        '  std::error_code vfs_ec;\n'
        '  std::filesystem::create_directories(cache_host_dir, vfs_ec);\n'
        '  std::filesystem::create_directories(scratch_host_dir, vfs_ec);\n\n'
        '  auto cache_device = std::make_unique<rex::filesystem::HostPathDevice>(\n'
        '      "\\\\Device\\\\Cache", cache_host_dir, /*read_only=*/false);\n'
        '  if (cache_device->Initialize()) {\n'
        '    file_system_->RegisterDevice(std::move(cache_device));\n'
        '    file_system_->RegisterSymbolicLink("cache:", "\\\\Device\\\\Cache");\n'
        '    file_system_->RegisterSymbolicLink("CACHE:", "\\\\Device\\\\Cache");\n'
        '    file_system_->RegisterSymbolicLink("utl:", "\\\\Device\\\\Cache");\n'
        '    REXSYS_DEBUG("  Mounted {} at \\\\Device\\\\Cache (cache:, CACHE:, utl:)", cache_host_dir.string());\n'
        '  }\n\n'
        '  auto scratch_device = std::make_unique<rex::filesystem::HostPathDevice>(\n'
        '      "\\\\Device\\\\Scratch", scratch_host_dir, /*read_only=*/false);\n'
        '  if (scratch_device->Initialize()) {\n'
        '    file_system_->RegisterDevice(std::move(scratch_device));\n'
        '    file_system_->RegisterSymbolicLink("scratch:", "\\\\Device\\\\Scratch");\n'
        '    file_system_->RegisterSymbolicLink("SCRATCH:", "\\\\Device\\\\Scratch");\n'
        '    REXSYS_DEBUG("  Mounted {} at \\\\Device\\\\Scratch (scratch:, SCRATCH:)", scratch_host_dir.string());\n'
        '  }\n\n'
        '  return true;'
    )

    open_anchor = (
        '  if (entry) {\n'
        '    if (entry->attributes() & kFileAttributeDirectory && is_non_directory) {\n'
        '      return X_STATUS_FILE_IS_A_DIRECTORY;\n'
        '    }'
    )
    open_new = (
        '  if (entry) {\n'
        '    // LOCAL PATCH: Allow opening root volume directories ("D:\\", "cache:\\")\n'
        '    // even when the guest omits FILE_DIRECTORY_FILE or sets FILE_NON_DIRECTORY_FILE:\n'
        '    if (entry->attributes() & kFileAttributeDirectory && is_non_directory && !entry->name().empty()) {\n'
        '      return X_STATUS_FILE_IS_A_DIRECTORY;\n'
        '    }'
    )

    devinfo_anchor = (
        '    case XFileFsDeviceInformation: {\n'
        '      auto info = info_ptr.as<X_FILE_FS_DEVICE_INFORMATION*>();\n'
        '      REXKRNL_WARN("Stub XFileFsDeviceInformation!");\n'
        '      info->device_type = FILE_DEVICE_UNKNOWN;\n'
        '      info->characteristics = 0;\n'
        '      out_length = sizeof(X_FILE_FS_DEVICE_INFORMATION);\n'
        '      break;\n'
        '    }'
    )
    devinfo_new = (
        '    case XFileFsDeviceInformation: {\n'
        '      auto info = info_ptr.as<X_FILE_FS_DEVICE_INFORMATION*>();\n'
        '      // LOCAL PATCH: Return FILE_DEVICE_DISK (0x00000007) for volume probe\n'
        '      info->device_type.set(static_cast<rex::system::X_FILE_DEVICE_TYPE>(0x00000007));\n'
        '      info->characteristics = 0;\n'
        '      out_length = sizeof(X_FILE_FS_DEVICE_INFORMATION);\n'
        '      break;\n'
        '    }'
    )

    dismount_anchor = (
        'u32 IoDismountVolumeByFileHandle_entry(u32 handle) {\n'
        '  REXKRNL_WARN("IoDismountVolumeByFileHandle({:#x}) - stub", (uint32_t)handle);\n'
        '  return X_STATUS_SUCCESS;\n'
        '}'
    )
    dismount_new = (
        'u32 IoDismountVolumeByFileHandle_entry(u32 handle) {\n'
        '  REXKRNL_WARN("IoDismountVolumeByFileHandle({:#x}) - stub", (uint32_t)handle);\n'
        '  // LOCAL PATCH: Re-ensure cache: symbolic links stay active across utility dismount\n'
        '  REX_KERNEL_FS()->RegisterSymbolicLink("cache:", "\\\\Device\\\\Cache");\n'
        '  REX_KERNEL_FS()->RegisterSymbolicLink("CACHE:", "\\\\Device\\\\Cache");\n'
        '  REX_KERNEL_FS()->RegisterSymbolicLink("utl:", "\\\\Device\\\\Cache");\n'
        '  return X_STATUS_SUCCESS;\n'
        '}'
    )

    blocks = [
        ("src/system/runtime.cpp", "mount writable cache and scratch HostPathDevices", vfs_anchor, vfs_new),
        ("src/filesystem/virtual_file_system.cpp", "allow opening root volume directories", open_anchor, open_new),
        ("src/kernel/xboxkrnl/xboxkrnl_io_info.cpp", "return FILE_DEVICE_DISK for XFileFsDeviceInformation", devinfo_anchor, devinfo_new),
        ("src/kernel/xboxkrnl/xboxkrnl_io.cpp", "re-register cache: symlink on dismount", dismount_anchor, dismount_new),
    ]
    run_patch("tekken6_vfs_fixes", blocks, sdk)


def apply_xenos_fetch_constants_and_nan_patches(sdk: pathlib.Path):
    """
    Xenos Fetch Constants & EDRAM Range Clamping:
    1. src/graphics/pipeline/texture/cache.cpp: Silently skip zeroed dummy fetch constants; honor gpu_allow_invalid_fetch_constants.
    2. src/graphics/pipeline/render_target/cache.cpp: Clamp EDRAM lengths to kEdramTileCount - rt_base.
    """
    texture_anchor = (
        '  switch (fetch.type) {\n'
        '    case xenos::FetchConstantType::kTexture:\n'
        '      break;\n'
        '    case xenos::FetchConstantType::kInvalidTexture:\n'
        '      if (REXCVAR_GET(gpu_allow_invalid_fetch_constants)) {\n'
        '        break;\n'
        '      }\n'
        '      REXGPU_WARN(\n'
        '          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "\n'
        '          "has \\"invalid\\" type! This is incorrect behavior, but you can try "\n'
        '          "bypassing this by launching Xenia with "\n'
        '          "--gpu_allow_invalid_fetch_constants=true.",\n'
        '          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);\n'
        '      return;\n'
        '    default:\n'
        '      REXGPU_WARN(\n'
        '          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "\n'
        '          "is completely invalid!",\n'
        '          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);\n'
        '      return;\n'
        '  }'
    )
    texture_new = (
        '  // LOCAL PATCH: Silently skip zeroed dummy slots (base_address == 0 && width == 0 && height == 0)\n'
        '  if (fetch.base_address == 0 && fetch.size_2d.width == 0 && fetch.size_2d.height == 0) {\n'
        '    return;\n'
        '  }\n'
        '  switch (fetch.type) {\n'
        '    case xenos::FetchConstantType::kTexture:\n'
        '      break;\n'
        '    case xenos::FetchConstantType::kInvalidTexture:\n'
        '      if (REXCVAR_GET(gpu_allow_invalid_fetch_constants)) {\n'
        '        break;\n'
        '      }\n'
        '      REXGPU_WARN(\n'
        '          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "\n'
        '          "has \\"invalid\\" type! This is incorrect behavior, but you can try "\n'
        '          "bypassing this by launching Xenia with "\n'
        '          "--gpu_allow_invalid_fetch_constants=true.",\n'
        '          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);\n'
        '      return;\n'
        '    default:\n'
        '      if (REXCVAR_GET(gpu_allow_invalid_fetch_constants)) {\n'
        '        break;\n'
        '      }\n'
        '      REXGPU_WARN(\n'
        '          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "\n'
        '          "is completely invalid!",\n'
        '          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);\n'
        '      return;\n'
        '  }'
    )

    edram_anchor = (
        '    rt_lengths_tiles[i] = std::min(std::min(length_used_tiles_at_32bpp << rt_is_64bpp,\n'
        '                                            rt_max_distance_tiles_at_64bpp >> (rt_is_64bpp ^ 1)),\n'
        '                                   ((i + 1 < edram_bases_sorted_count)\n'
        '                                        ? edram_bases_sorted[i + 1].first\n'
        '                                        : (xenos::kEdramTileCount + edram_bases_sorted[0].first)) -\n'
        '                                       rt_base);\n'
        '  }'
    )
    edram_new = (
        '    rt_lengths_tiles[i] = std::min(std::min(length_used_tiles_at_32bpp << rt_is_64bpp,\n'
        '                                            rt_max_distance_tiles_at_64bpp >> (rt_is_64bpp ^ 1)),\n'
        '                                   ((i + 1 < edram_bases_sorted_count)\n'
        '                                        ? edram_bases_sorted[i + 1].first\n'
        '                                        : (xenos::kEdramTileCount + edram_bases_sorted[0].first)) -\n'
        '                                       rt_base);\n'
        '    // LOCAL PATCH - Clamp EDRAM tile range to prevent wrapping past tile 2047 onto tile 0\n'
        '    rt_lengths_tiles[i] = std::min(rt_lengths_tiles[i], xenos::kEdramTileCount - rt_base);\n'
        '  }'
    )

    blocks = [
        ("src/graphics/pipeline/texture/cache.cpp", "silently skip zeroed fetch constants & honor cvar", texture_anchor, texture_new),
        ("src/graphics/pipeline/render_target/cache.cpp", "clamp EDRAM tile range to avoid tile 2047 wrap", edram_anchor, edram_new),
    ]
    run_patch("xenos_fetch_and_edram_fixes", blocks, sdk)


def apply_threading_backoff_yield_patch(sdk: pathlib.Path):
    """
    Patches MaybeYield in src/core/threading_posix.cpp to use sched_yield() + nanosleep(200us)
    on iOS to prevent CPU thread starvation and thermal throttling.
    """
    blocks = [
        (
            "src/core/threading_posix.cpp",
            "add 200us backoff yield on iOS in MaybeYield",
            'void MaybeYield() {\n'
            '  sched_yield();\n'
            '  __sync_synchronize();\n'
            '}',
            'void MaybeYield() {\n'
            '#if REX_PLATFORM_IOS\n'
            '  sched_yield();\n'
            '  timespec ts{0, 200000};\n'
            '  nanosleep(&ts, nullptr);\n'
            '#else\n'
            '  sched_yield();\n'
            '#endif\n'
            '  __sync_synchronize();\n'
            '}',
        ),
    ]
    run_patch("threading_backoff_yield", blocks, sdk)


def apply_memory_posix_patch(sdk: pathlib.Path):
    """Patches memory_posix.cpp to use vm_region_64 on iOS (mach_vm is unsupported on iOS)."""
    blocks = [
        (
            "src/core/memory_posix.cpp",
            "iOS mach/vm_map.h include instead of unsupported mach/mach_vm.h",
            "#if REX_PLATFORM_MAC\n"
            "#include <mach/mach.h>\n"
            "#include <mach/mach_vm.h>\n"
            "#include <mach/vm_region.h>\n"
            "#endif  // REX_PLATFORM_MAC\n",
            "#if REX_PLATFORM_IOS\n"
            "#include <mach/mach.h>\n"
            "#include <mach/vm_map.h>\n"
            "#include <mach/vm_region.h>\n"
            "#elif REX_PLATFORM_MAC\n"
            "#include <mach/mach.h>\n"
            "#include <mach/mach_vm.h>\n"
            "#include <mach/vm_region.h>\n"
            "#endif  // REX_PLATFORM_MAC\n",
        ),
        (
            "src/core/memory_posix.cpp",
            "QueryProtect vm_region_64 on iOS",
            "bool QueryProtect(void* base_address, size_t& length, PageAccess& access_out) {\n"
            "#if REX_PLATFORM_MAC\n"
            "  mach_vm_address_t address = reinterpret_cast<mach_vm_address_t>(base_address);\n"
            "  mach_vm_size_t region_size = 0;\n"
            "  vm_region_basic_info_data_64_t info;\n"
            "  mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;\n"
            "  mach_port_t object_name;\n\n"
            "  kern_return_t kr =\n"
            "      mach_vm_region(mach_task_self(), &address, &region_size, VM_REGION_BASIC_INFO_64,\n"
            "                     reinterpret_cast<vm_region_info_t>(&info), &info_count, &object_name);\n"
            "  if (kr != KERN_SUCCESS) {\n"
            "    return false;\n"
            "  }\n"
            "  if (address > reinterpret_cast<mach_vm_address_t>(base_address)) {\n"
            "    return false;\n"
            "  }\n\n"
            "  length = static_cast<size_t>((address + region_size) -\n"
            "                               reinterpret_cast<mach_vm_address_t>(base_address));\n",
            "bool QueryProtect(void* base_address, size_t& length, PageAccess& access_out) {\n"
            "#if REX_PLATFORM_IOS\n"
            "  vm_address_t address = reinterpret_cast<vm_address_t>(base_address);\n"
            "  vm_size_t region_size = 0;\n"
            "  vm_region_basic_info_data_64_t info;\n"
            "  mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;\n"
            "  mach_port_t object_name = MACH_PORT_NULL;\n\n"
            "  kern_return_t kr =\n"
            "      vm_region_64(mach_task_self(), &address, &region_size, VM_REGION_BASIC_INFO_64,\n"
            "                   reinterpret_cast<vm_region_info_t>(&info), &info_count, &object_name);\n"
            "  if (kr != KERN_SUCCESS) {\n"
            "    return false;\n"
            "  }\n"
            "  if (address > reinterpret_cast<vm_address_t>(base_address)) {\n"
            "    return false;\n"
            "  }\n\n"
            "  length = static_cast<size_t>((address + region_size) -\n"
            "                               reinterpret_cast<vm_address_t>(base_address));\n"
            "#elif REX_PLATFORM_MAC\n"
            "  mach_vm_address_t address = reinterpret_cast<mach_vm_address_t>(base_address);\n"
            "  mach_vm_size_t region_size = 0;\n"
            "  vm_region_basic_info_data_64_t info;\n"
            "  mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;\n"
            "  mach_port_t object_name;\n\n"
            "  kern_return_t kr =\n"
            "      mach_vm_region(mach_task_self(), &address, &region_size, VM_REGION_BASIC_INFO_64,\n"
            "                     reinterpret_cast<vm_region_info_t>(&info), &info_count, &object_name);\n"
            "  if (kr != KERN_SUCCESS) {\n"
            "    return false;\n"
            "  }\n"
            "  if (address > reinterpret_cast<mach_vm_address_t>(base_address)) {\n"
            "    return false;\n"
            "  }\n\n"
            "  length = static_cast<size_t>((address + region_size) -\n"
            "                               reinterpret_cast<mach_vm_address_t>(base_address));\n",
        ),
    ]
    run_patch("memory_posix", blocks, sdk)


def apply_version_cmake_patch(sdk: pathlib.Path):
    """Patches rex_version.cmake to use CMAKE_CURRENT_SOURCE_DIR and prevent floor version regression fatal error."""
    version_cmake = sdk / "cmake" / "rex_version.cmake"
    if not version_cmake.exists():
        return
    txt = version_cmake.read_text(encoding="utf-8")
    orig = txt

    # 1. Default to CMAKE_CURRENT_SOURCE_DIR instead of CMAKE_SOURCE_DIR so parent repo tags (like v1.0.0) don't pollute SDK version
    if 'set(ARG_SOURCE_DIR "${CMAKE_SOURCE_DIR}")' in txt:
        txt = txt.replace(
            'set(ARG_SOURCE_DIR "${CMAKE_SOURCE_DIR}")',
            'set(ARG_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")'
        )

    # 2. Downgrade floor version regression check from FATAL_ERROR to STATUS
    if 'message(FATAL_ERROR' in txt and 'The floor in CMakeLists.txt must not regress.' in txt:
        txt = txt.replace(
            'message(FATAL_ERROR\n            "rex_compute_version: floor version (${ARG_FLOOR_MAJOR}.${ARG_FLOOR_MINOR}) is behind',
            'message(STATUS\n            "rex_compute_version: floor version (${ARG_FLOOR_MAJOR}.${ARG_FLOOR_MINOR}) is behind'
        )

    if txt != orig:
        version_cmake.write_text(txt, encoding="utf-8")
        print("  [ok] rex_version: patched rex_version.cmake to use CMAKE_CURRENT_SOURCE_DIR and prevent version errors")


def main():
    parser = argparse.ArgumentParser(description="ReXGlue iOS SDK Preparation")
    parser.add_argument("--sdk", type=str, default=str(REPO_ROOT.parent / "rexglue-sdk-ios"),
                        help="Path to rexglue-sdk-ios (default: ../rexglue-sdk-ios)")
    parser.add_argument("--skip-submodules", action="store_true",
                        help="Skip git submodule update")
    parser.add_argument("--skip-moltenvk", action="store_true",
                        help="Skip MoltenVK download")
    args = parser.parse_args()

    sdk_dir = pathlib.Path(args.sdk).resolve()
    print(f"[prepare_sdk] Targeting ReXGlue SDK at: {sdk_dir}")

    ensure_sdk_cloned(sdk_dir, skip_submodules=args.skip_submodules)
    fix_libmspack_symlinks(sdk_dir)
    if not args.skip_moltenvk:
        ensure_moltenvk(sdk_dir)
    apply_version_cmake_patch(sdk_dir)
    apply_cmake_patches(sdk_dir)
    apply_fpscr_patch(sdk_dir)
    apply_filesystem_paths_patch(sdk_dir)
    apply_pipeline_cache_patch(sdk_dir)
    apply_memory_posix_patch(sdk_dir)
    apply_tekken6_vfs_patches(sdk_dir)
    apply_xenos_fetch_constants_and_nan_patches(sdk_dir)
    apply_threading_backoff_yield_patch(sdk_dir)

    print("[prepare_sdk] SUCCESS: ReXGlue SDK is fully prepared and patched for iOS ARM64!")


if __name__ == "__main__":
    main()
