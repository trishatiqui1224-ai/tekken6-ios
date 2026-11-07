# =============================================================================
#  Tekken 6 - iOS App (arm64, iOS 16.0+)
#  Xbox 360 Title ID: 4E4D07FC
#
#  Configure with the preset in ios/CMakePresets.json:
#      cmake --preset ios
#      cmake --build --preset ios
#      cmake --build --preset ios --target ipa
# =============================================================================

cmake_minimum_required(VERSION 3.25)

# 1. Mandatory Toolchain Flags for iOS ARM64 Native Target
if(NOT CMAKE_SYSTEM_NAME)
    set(CMAKE_SYSTEM_NAME "iOS")
endif()
if(NOT CMAKE_SYSTEM_PROCESSOR)
    set(CMAKE_SYSTEM_PROCESSOR "arm64")
endif()
if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64")
endif()
if(NOT CMAKE_OSX_SYSROOT)
    set(CMAKE_OSX_SYSROOT "iphoneos")
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "16.4")
endif()
set(REX_PLATFORM_IOS 1 CACHE BOOL "Build for iOS platform" FORCE)
add_compile_definitions(REX_PLATFORM_IOS=1)
add_compile_definitions(_LIBCPP_DISABLE_AVAILABILITY=1)

# Preferred Compiler Resolution via xcrun
if(APPLE AND NOT CMAKE_C_COMPILER)
    execute_process(
        COMMAND xcrun --sdk iphoneos --find clang
        OUTPUT_VARIABLE _IOS_CLANG
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_IOS_CLANG AND EXISTS "${_IOS_CLANG}")
        set(CMAKE_C_COMPILER "${_IOS_CLANG}" CACHE FILEPATH "C compiler" FORCE)
    endif()
endif()
if(APPLE AND NOT CMAKE_CXX_COMPILER)
    execute_process(
        COMMAND xcrun --sdk iphoneos --find clang++
        OUTPUT_VARIABLE _IOS_CLANGXX
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_IOS_CLANGXX AND EXISTS "${_IOS_CLANGXX}")
        set(CMAKE_CXX_COMPILER "${_IOS_CLANGXX}" CACHE FILEPATH "CXX compiler" FORCE)
    endif()
endif()

project(tekken6_ios LANGUAGES C CXX OBJC OBJCXX ASM)

if(NOT IOS)
    message(FATAL_ERROR "This CMakeLists.txt is for iOS: configure with cmake --preset ios")
endif()

set(TEKKEN6_REPO "${CMAKE_CURRENT_SOURCE_DIR}/.." CACHE PATH "Tekken 6 Recompiled repository root")
set(TEKKEN6_SDK "${TEKKEN6_REPO}/../rexglue-sdk-ios" CACHE PATH "ReXGlue SDK prepared for iOS")
set(TEKKEN6_BUNDLE_ID "com.recomp.tekken6.ios" CACHE STRING "App bundle identifier")
set(TEKKEN6_GEN_DIR "${TEKKEN6_REPO}/generated/default" CACHE PATH "Generated code for Tekken 6")
set(TEKKEN6_JOBS_RECOMP "2" CACHE STRING "Generated files compiled at once")
get_filename_component(TEKKEN6_REPO "${TEKKEN6_REPO}" ABSOLUTE)
get_filename_component(TEKKEN6_SDK "${TEKKEN6_SDK}" ABSOLUTE)

# Locate MoltenVK.framework
set(_mvk_marker "${TEKKEN6_SDK}/.tekken6-ios/MoltenVK/v1.4.1.ready")
if(EXISTS "${_mvk_marker}")
    set(TEKKEN6_MOLTENVK_FW "${TEKKEN6_SDK}/.tekken6-ios/MoltenVK/MoltenVK/MoltenVK.xcframework/ios-arm64/MoltenVK.framework")
endif()

if(NOT EXISTS "${TEKKEN6_MOLTENVK_FW}/MoltenVK")
    file(GLOB_RECURSE _found_mvk
        "${TEKKEN6_SDK}/.tekken6-ios/*/ios-arm64/MoltenVK.framework"
        "${TEKKEN6_SDK}/*/ios-arm64/MoltenVK.framework"
        "${TEKKEN6_REPO}/thirdparty/*/ios-arm64/MoltenVK.framework"
    )
    if(_found_mvk)
        list(GET _found_mvk 0 TEKKEN6_MOLTENVK_FW)
    endif()
endif()

if(EXISTS "${TEKKEN6_MOLTENVK_FW}")
    message(STATUS "Tekken 6: Found MoltenVK.framework at ${TEKKEN6_MOLTENVK_FW}")
else()
    message(STATUS "Tekken 6: MoltenVK.framework will be linked from framework search paths")
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)

set(REXGLUE_ENABLE_TRACY OFF CACHE BOOL "" FORCE)
set(REXGLUE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(REXGLUE_USE_VULKAN ON CACHE BOOL "" FORCE)
set(REXGLUE_USE_D3D12 OFF CACHE BOOL "" FORCE)
set(REXGLUE_ENABLE_DESKTOP_SDL_BACKENDS OFF CACHE BOOL "" FORCE)

if(EXISTS "${TEKKEN6_SDK}/CMakeLists.txt")
    add_subdirectory("${TEKKEN6_SDK}" rexglue-sdk)
endif()

# Header-only interface library for SDK dependencies
add_library(tekken6_headers INTERFACE)
if(TARGET imgui)
    target_include_directories(tekken6_headers INTERFACE
        $<TARGET_PROPERTY:imgui,INTERFACE_INCLUDE_DIRECTORIES>)
endif()
if(TARGET Vulkan::Headers)
    target_link_libraries(tekken6_headers INTERFACE Vulkan::Headers)
endif()
if(TARGET GPUOpen::VulkanMemoryAllocator)
    target_link_libraries(tekken6_headers INTERFACE GPUOpen::VulkanMemoryAllocator)
endif()
if(TARGET spirv-tools-headers)
    target_link_libraries(tekken6_headers INTERFACE spirv-tools-headers)
endif()

# -----------------------------------------------------------------------------
#  Generated Game Code (PowerPC to ARM64 C++)
# -----------------------------------------------------------------------------
set(TEKKEN6_WITH_GAME OFF)
if(EXISTS "${TEKKEN6_GEN_DIR}/sources.cmake")
    include("${TEKKEN6_GEN_DIR}/sources.cmake")
    if(GENERATED_SOURCES)
        set(TEKKEN6_WITH_GAME ON)

        add_library(tekken6_recomp STATIC ${GENERATED_SOURCES})
        target_include_directories(tekken6_recomp PRIVATE
            "${TEKKEN6_REPO}"
            "${TEKKEN6_REPO}/src"
            "${TEKKEN6_GEN_DIR}")
        if(TARGET rex::runtime)
            target_link_libraries(tekken6_recomp PUBLIC rex::runtime tekken6_headers)
            rexglue_apply_target_settings(tekken6_recomp)
        endif()

        if(EXISTS "${TEKKEN6_GEN_DIR}/tekken6_pch.h")
            target_precompile_headers(tekken6_recomp PRIVATE "${TEKKEN6_GEN_DIR}/tekken6_pch.h")
        endif()
        target_compile_options(tekken6_recomp PRIVATE -gline-tables-only -Wno-unused-variable)
        if(EXISTS "${TEKKEN6_GEN_DIR}/tekken6_register.cpp")
            set_source_files_properties("${TEKKEN6_GEN_DIR}/tekken6_register.cpp"
                PROPERTIES COMPILE_OPTIONS "-O1")
        endif()
        set_property(GLOBAL APPEND PROPERTY JOB_POOLS recomp=${TEKKEN6_JOBS_RECOMP})
        set_target_properties(tekken6_recomp PROPERTIES JOB_POOL_COMPILE recomp)
        message(STATUS "Tekken 6: Compiling with generated game code (${TEKKEN6_GEN_DIR})")
    endif()
endif()

# -----------------------------------------------------------------------------
#  Application Target (Tekken6.app)
# -----------------------------------------------------------------------------
set(TEKKEN6_VERSION "1.0.0")
set(TEKKEN6_VERSION_CODE "1")
set(TEKKEN6_DISPLAY_NAME "Tekken 6")
set(TEKKEN6_IOS_MIN "${CMAKE_OSX_DEPLOYMENT_TARGET}")
set(TEKKEN6_EXECUTABLE "Tekken6")

configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
               "${CMAKE_CURRENT_BINARY_DIR}/Info.plist" @ONLY)

set(TEKKEN6_APP_SOURCES
    src/ios_main.mm
    src/boot_trace.cpp
    src/launcher.mm
    src/touch_controls.mm
    src/save_manager.mm
    src/lifecycle.mm
    src/display_rate.mm
    src/battery.mm
    src/memory_report.mm
    src/probe.mm
    src/audio/coreaudio_driver.mm
    ${TEKKEN6_REPO}/src/tekken6_hooks.cpp
)

if(TEKKEN6_WITH_GAME)
    list(APPEND TEKKEN6_APP_SOURCES
        src/game_app.cpp
    )
    if(EXISTS "${TEKKEN6_SDK}/src/ui/rex_app.cpp")
        list(APPEND TEKKEN6_APP_SOURCES "${TEKKEN6_SDK}/src/ui/rex_app.cpp")
    endif()
endif()

add_executable(tekken6 MACOSX_BUNDLE ${TEKKEN6_APP_SOURCES})
set_target_properties(tekken6 PROPERTIES
    OUTPUT_NAME "${TEKKEN6_EXECUTABLE}"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist"
    INSTALL_RPATH "@loader_path/Frameworks")

target_compile_options(tekken6 PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)

target_include_directories(tekken6 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${TEKKEN6_REPO}"
    "${TEKKEN6_REPO}/src"
    "${TEKKEN6_SDK}"
    "${TEKKEN6_SDK}/include"
    "${TEKKEN6_SDK}/src"
    "${TEKKEN6_GEN_DIR}"
)

set(TEKKEN6_GAME_LANGUAGE "1" CACHE STRING "Game language ID (1=English)")

target_compile_definitions(tekken6 PRIVATE
    REXGLUE_BUILD_CONFIG="$<CONFIG>"
    TEKKEN6_WITH_GAME=$<BOOL:${TEKKEN6_WITH_GAME}>
    TEKKEN6_GAME_LANGUAGE="${TEKKEN6_GAME_LANGUAGE}"
    TITLE_ID="4E4D07FC"
    REX_PLATFORM_IOS=1
)

target_link_libraries(tekken6 PRIVATE
    tekken6_headers
    "-framework Foundation"
    "-framework UIKit"
    "-framework Metal"
    "-framework MetalFX"
    "-framework QuartzCore"
    "-framework CoreImage"
    "-framework UniformTypeIdentifiers"
    "-framework AudioToolbox"
    "-framework AVFoundation"
    "-framework GameController"
    z
)

if(TARGET rex::runtime)
    target_link_libraries(tekken6 PRIVATE rex::runtime)
endif()

if(TEKKEN6_WITH_GAME)
    target_link_libraries(tekken6 PRIVATE tekken6_recomp)
endif()

if(TARGET rexgpu-xenos)
    add_dependencies(tekken6 rexgpu-xenos)
endif()

# -----------------------------------------------------------------------------
#  Packaging & Ad-Hoc Code Signing Target
# -----------------------------------------------------------------------------
set(_app "$<TARGET_BUNDLE_DIR:tekken6>")
set(_fw "${_app}/Frameworks")

if(TARGET rexruntime)
    set(_copy_rexruntime COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:rexruntime>" "${_fw}/")
    set(_sign_rexruntime COMMAND codesign --force --sign - --timestamp=none "${_fw}/$<TARGET_FILE_NAME:rexruntime>" 2>/dev/null || true)
    set(_dep_rexruntime rexruntime)
else()
    set(_copy_rexruntime COMMAND ${CMAKE_COMMAND} -E true)
    set(_sign_rexruntime COMMAND ${CMAKE_COMMAND} -E true)
    set(_dep_rexruntime "")
endif()

if(TARGET rexgpu-xenos)
    set(_copy_rexgpu COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:rexgpu-xenos>" "${_fw}/")
    set(_sign_rexgpu COMMAND codesign --force --sign - --timestamp=none "${_fw}/$<TARGET_FILE_NAME:rexgpu-xenos>" 2>/dev/null || true)
    set(_dep_rexgpu rexgpu-xenos)
else()
    set(_copy_rexgpu COMMAND ${CMAKE_COMMAND} -E true)
    set(_sign_rexgpu COMMAND ${CMAKE_COMMAND} -E true)
    set(_dep_rexgpu "")
endif()

if(EXISTS "${TEKKEN6_MOLTENVK_FW}")
    set(_copy_mvk_cmd COMMAND ${CMAKE_COMMAND} -E copy_directory "${TEKKEN6_MOLTENVK_FW}" "${_fw}/MoltenVK.framework")
    set(_sign_mvk_cmd COMMAND codesign --force --sign - --timestamp=none "${_fw}/MoltenVK.framework" 2>/dev/null || true)
else()
    set(_copy_mvk_cmd COMMAND ${CMAKE_COMMAND} -E true)
    set(_sign_mvk_cmd COMMAND ${CMAKE_COMMAND} -E true)
endif()

add_custom_target(tekken6_package ALL
    COMMAND ${CMAKE_COMMAND} -E make_directory "${_fw}"
    ${_copy_rexruntime}
    ${_copy_rexgpu}
    ${_copy_mvk_cmd}
    COMMAND xcrun actool "${CMAKE_CURRENT_SOURCE_DIR}/resources/Assets.xcassets"
            --compile "${_app}" --platform iphoneos
            --minimum-deployment-target "${CMAKE_OSX_DEPLOYMENT_TARGET}"
            --target-device iphone --target-device ipad --app-icon AppIcon
            --output-partial-info-plist "${CMAKE_CURRENT_BINARY_DIR}/actool-partial.plist"
            --output-format human-readable-text --errors --warnings || true
    COMMAND xattr -cr "${_app}" || true
    ${_sign_mvk_cmd}
    ${_sign_rexruntime}
    ${_sign_rexgpu}
    COMMAND codesign --force --sign - --timestamp=none
            --entitlements "${CMAKE_CURRENT_SOURCE_DIR}/tekken6.entitlements" "${_app}" || true
    COMMENT "Tekken 6: Packaging and signing Tekken6.app"
    VERBATIM
)
add_dependencies(tekken6_package tekken6 ${_dep_rexruntime} ${_dep_rexgpu})

# -----------------------------------------------------------------------------
#  IPA Generation Target
# -----------------------------------------------------------------------------
add_custom_target(ipa
    COMMAND ${CMAKE_COMMAND} -E rm -rf "${CMAKE_CURRENT_BINARY_DIR}/ipa"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/ipa/Payload"
    COMMAND ditto "${_app}" "${CMAKE_CURRENT_BINARY_DIR}/ipa/Payload/Tekken6.app"
    COMMAND ${CMAKE_COMMAND} -E rm -f "${CMAKE_CURRENT_BINARY_DIR}/Tekken6.ipa"
    COMMAND ${CMAKE_COMMAND} -E rm -f "${CMAKE_CURRENT_BINARY_DIR}/Tekken6-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E chdir "${CMAKE_CURRENT_BINARY_DIR}/ipa"
            ditto -c -k --sequesterRsrc --keepParent Payload "${CMAKE_CURRENT_BINARY_DIR}/Tekken6-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/Tekken6-iOS-unsigned.ipa"
            "${CMAKE_CURRENT_BINARY_DIR}/Tekken6.ipa"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_SOURCE_DIR}/build"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/Tekken6-iOS-unsigned.ipa"
            "${CMAKE_CURRENT_SOURCE_DIR}/build/Tekken6-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/Tekken6.ipa"
            "${CMAKE_CURRENT_SOURCE_DIR}/build/Tekken6.ipa"
    COMMENT "Tekken 6: Generated unsigned IPA package at build/Tekken6-iOS-unsigned.ipa"
    VERBATIM
)
add_dependencies(ipa tekken6_package)

