cmake_minimum_required(VERSION 3.24)
project(DasBattleCalc C CXX)

# Desktop host: daScript + dasSDL3 + Dear ImGui (dasImgui) + our helper
# modules. Links the static libraries of an existing dasSDL3 build tree
# (Release, Ninja, MSVC /MD, DASSDL3_WITH_IMGUI=ON) as is.
if(NOT MSVC)
    message(FATAL_ERROR "Only MSVC /MD Release is supported (it must match the dasSDL3 build)")
endif()
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
set(CMAKE_CXX_STANDARD 17)

set(DASSDL3_DIR "C:/src/dasSDL3-localdas" CACHE PATH "dasSDL3 checkout (build.bat passes it)")
set(DASSDL3_BUILD "${DASSDL3_DIR}/build/ninja")   # Release build with DASSDL3_WITH_IMGUI
load_cache(${DASSDL3_BUILD} READ_WITH_PREFIX DS_ FETCHCONTENT_SOURCE_DIR_SDL3)
if(NOT DS_FETCHCONTENT_SOURCE_DIR_SDL3)
    message(FATAL_ERROR "Can not read SDL3 source dir from ${DASSDL3_BUILD}/CMakeCache.txt")
endif()
set(DAS "${DASSDL3_DIR}/third_party/daScript")

add_executable(battlecalc
    native/runner.cpp
    native/gui_common.cpp
    native/module_gui_common.cpp
    native/module_imgui_ext.cpp
    native/gba_mem.cpp
    native/module_gba_mem.cpp
    native/gba_frame.cpp
    native/gba_gfx.cpp
    native/nds_mem.cpp
    native/psx_mem.cpp
    native/psp_mem.cpp
    native/imgui_ext.cpp
    native/third_party/zstddeclib.c)
set_source_files_properties(native/third_party/zstddeclib.c PROPERTIES COMPILE_OPTIONS /W0)
target_include_directories(battlecalc PRIVATE
    native
    native/third_party
    ${DASSDL3_DIR}/src
    ${DAS}/include
    ${DAS}/3rdparty/fmt/include
    ${DASSDL3_BUILD}/third_party/daScript/include
    ${DAS}/3rdparty/uriparser/include
    ${DASSDL3_BUILD}/_deps/sdl3-build/include-revision
    ${DS_FETCHCONTENT_SOURCE_DIR_SDL3}/include
    ${DAS}/modules/dasImgui/imgui
    ${DAS}/modules/dasImgui/src)
# the same as the dasSDL3 / dasImgui libraries we link
target_compile_definitions(battlecalc PRIVATE
    DAS_ENABLE_DYN_INCLUDES=1 DAS_ENABLE_EXCEPTIONS=1 DAS_FUSION=2 DAS_NO_ASSERTIONS
    URIPARSER_BUILD_CHAR URI_STATIC_BUILD
    IMGUI_DISABLE_OBSOLETE_FUNCTIONS=1 IMGUI_ENABLE_FREETYPE=1 IMGUI_USE_WCHAR32=1
    DAS_ROOT_DIR="${DAS}"
    DASSDL3_MODULE_ROOT_DIR="${DASSDL3_DIR}/dassdl3"
    GUI_PROJECT_DIR="${CMAKE_SOURCE_DIR}")
target_compile_options(battlecalc PRIVATE /bigobj /utf-8)

set(B ${DASSDL3_BUILD})
target_link_libraries(battlecalc PRIVATE
    ${B}/src/libraries/dasSDL3_imgui.lib
    ${DAS}/lib/libDasModuleImgui.lib
    ${DAS}/lib/freetype.lib
    ${DAS}/lib/libDasModuleClipboard.lib
    ${B}/src/dasSDL3.lib
    ${DAS}/lib/libDaScript.lib
    ${DAS}/lib/libDaScript_runtime.lib
    ${DAS}/lib/libUriParser.lib
    ${B}/_deps/sdl3-build/SDL3-static.lib
    dbghelp ws2_32 mswsock rpcrt4 iphlpapi
    kernel32 user32 gdi32 winmm imm32 ole32 oleaut32 version uuid advapi32 setupapi shell32 dinput8
    winspool comdlg32)
set_target_properties(battlecalc PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
target_link_options(battlecalc PRIVATE /SUBSYSTEM:CONSOLE)
