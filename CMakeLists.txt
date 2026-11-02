cmake_minimum_required(VERSION 3.25)

if(APPLE)
    project(tekken6 LANGUAGES C CXX OBJC OBJCXX ASM)
else()
    project(tekken6 LANGUAGES C CXX ASM)
endif()

if(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    add_subdirectory(ios)
else()
    set(CMAKE_CXX_STANDARD 23)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)

    include(generated/rexglue.cmake OPTIONAL)

    set(TEKKEN6_SOURCES
        src/main.cpp
        src/tekken6_hooks.cpp
    )

    if(WIN32)
        add_executable(tekken6 WIN32 ${TEKKEN6_SOURCES})
        target_link_libraries(tekken6 PRIVATE dbghelp)
    else()
        add_executable(tekken6 ${TEKKEN6_SOURCES})
    endif()

    if(COMMAND rexglue_setup_target)
        rexglue_setup_target(tekken6 GPU_PLUGINS xenos)
    endif()

    target_include_directories(tekken6 PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/generated/default"
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}"
    )

    target_compile_definitions(tekken6 PRIVATE
        TEKKEN6_WITH_GAME=1
        TEKKEN6_GAME_LANGUAGE="1"
        TITLE_ID="4E4D07FC"
    )
endif()

