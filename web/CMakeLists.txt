cmake_minimum_required(VERSION 3.24)
project(DasBattleCalcWeb C CXX)

# Web build, standalone AOT (the pattern of dasNES): a wasm32 generator,
# run in Node at build time, compiles scripts/main_web.das and emits C++;
# the page links that C++ with the daScript runtime, ImGui, SDL3 and our
# native code - no compiler, no interpreter, no scripts in the download.
# daScript (the dasSDL3 submodule) is built here for wasm; SDL3 comes from
# an existing dasSDL3 Web build. Nothing in dasSDL3 changes.
if(NOT EMSCRIPTEN OR NOT EMSCRIPTEN_VERSION VERSION_EQUAL "5.0.3")
    message(FATAL_ERROR "Use Emscripten 5.0.3 via web/build.ps1")
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

set(DASSDL3_DIR "C:/src/dasSDL3-localdas" CACHE PATH "dasSDL3 checkout: its daScript is built here")
set(DASSDL3_WEB "C:/src/dasSDL3/build/web" CACHE PATH "a dasSDL3 Web build tree: only its SDL3 wasm is used")
# or SDL3 built on its own (CI): SDL3_SOURCE + SDL3_BUILD
set(SDL3_SOURCE "" CACHE PATH "SDL3 sources (instead of DASSDL3_WEB)")
set(SDL3_BUILD "" CACHE PATH "SDL3 static wasm build tree (instead of DASSDL3_WEB)")
if(SDL3_SOURCE)
    set(SDL_SRC "${SDL3_SOURCE}")
else()
    file(STRINGS "${DASSDL3_WEB}/CMakeCache.txt" sdl_line REGEX "^SDL3_SOURCE_DIR:STATIC=")
    string(REGEX REPLACE "^[^=]*=" "" SDL_SRC "${sdl_line}")
    set(SDL3_BUILD "${DASSDL3_WEB}/_deps/sdl3-build")
endif()
if(NOT EXISTS "${SDL_SRC}/include/SDL3/SDL.h")
    message(FATAL_ERROR "Can not find SDL3 sources: ${SDL_SRC}")
endif()
set(NODE_EXECUTABLE "" CACHE FILEPATH "node.exe of emsdk")
set(DAS "${DASSDL3_DIR}/third_party/daScript")
set(IMGUI "${DAS}/modules/dasImgui")
get_filename_component(ROOT "${CMAKE_SOURCE_DIR}/.." ABSOLUTE)
set(N "${ROOT}/native")

add_compile_options(-msimd128 -mnontrapping-fptoint -fwasm-exceptions -sWASM_LEGACY_EXCEPTIONS=0)
add_link_options(-fwasm-exceptions -sWASM_LEGACY_EXCEPTIONS=0)
add_compile_definitions(DAS_ENABLE_EXCEPTIONS=1 _EMSCRIPTEN_VER)

# daScript for wasm, configured as in dasSDL3/web/CMakeLists.txt
foreach(feature FLEX_BISON CLANG_BIND LLVM SMT HV GLFW IMGUI VULKAN AUDIO STDDLG
        MESHOPTIMIZER STBIMAGE METAL ACCELERATE CLIPBOARD PUGIXML SQLITE TREE_SITTER
        TERMINAL AOT_EXAMPLES TUTORIAL TESTS)
    set(DAS_${feature}_DISABLED ON CACHE BOOL "Minimal Web runtime" FORCE)
endforeach()
# new daScript lanes refer to the daslang target (not built unless needed)
set(DAS_TOOLS_DISABLED OFF CACHE BOOL "daslang target for daScript lanes" FORCE)
add_subdirectory("${DAS}" "${CMAKE_BINARY_DIR}/dascript" EXCLUDE_FROM_ALL)
function(isolate_outputs dir)   # keep daScript outputs out of its source tree
    get_property(targets DIRECTORY "${dir}" PROPERTY BUILDSYSTEM_TARGETS)
    foreach(t IN LISTS targets)
        set_target_properties(${t} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
            LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib" RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools")
    endforeach()
    get_property(children DIRECTORY "${dir}" PROPERTY SUBDIRECTORIES)
    foreach(child IN LISTS children)
        isolate_outputs("${child}")
    endforeach()
endfunction()
isolate_outputs("${DAS}")

# our code: the same defines as libDaScript, no RTTI (libDaScript has none)
add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>)
add_compile_definitions(DAS_ENABLE_DYN_INCLUDES=1 DAS_FUSION=2 DAS_NO_ASSERTIONS
    URIPARSER_BUILD_CHAR URI_STATIC_BUILD IMGUI_DISABLE_OBSOLETE_FUNCTIONS=1 IMGUI_USE_WCHAR32=1)
include_directories(
    ${N} ${N}/third_party ${CMAKE_SOURCE_DIR}
    ${DASSDL3_DIR}/src ${DASSDL3_DIR}/src/libraries ${DASSDL3_DIR}/web
    ${DAS}/include ${DAS}/3rdparty/fmt/include ${CMAKE_BINARY_DIR}/dascript/include ${DAS}/3rdparty/uriparser/include
    ${SDL3_BUILD}/include-revision ${SDL_SRC}/include
    ${IMGUI}/imgui ${IMGUI}/src ${DAS}/modules/dasClipboard/src)
add_compile_definitions(GUI_PROJECT_DIR="")
set(SDL_LIBS ${SDL3_BUILD}/libSDL3.a)
if(EXISTS "${SDL3_BUILD}/libSDL_uclibc.a")   # only with SDL_SHARED; static has it inside
    list(APPEND SDL_LIBS ${SDL3_BUILD}/libSDL_uclibc.a)
endif()

# native code without daScript: used by the generator and by the page
add_library(native_impl STATIC
    ${N}/gui_common.cpp ${N}/imgui_ext.cpp ${N}/gba_mem.cpp ${N}/gba_frame.cpp ${N}/gba_gfx.cpp ${N}/nds_mem.cpp ${N}/psx_mem.cpp ${N}/third_party/zstddeclib.c
    clipboard_web.cpp
    ${IMGUI}/imgui/imgui.cpp ${IMGUI}/imgui/imgui_draw.cpp ${IMGUI}/imgui/imgui_tables.cpp
    ${IMGUI}/imgui/imgui_widgets.cpp ${IMGUI}/imgui/imgui_demo.cpp
    ${IMGUI}/imgui/backends/imgui_impl_sdl3.cpp ${IMGUI}/imgui/backends/imgui_impl_sdlrenderer3.cpp)

# ---------------------------------------------------------------- generator
set(MD4C_DIR "" CACHE PATH "md4c-release-0.5.3/src (dasIMGUI.markdown.cpp needs it)")
file(GLOB IMGUI_BIND "${IMGUI}/src/dasIMGUI*.cpp")
add_executable(generator generator.cpp ${DASSDL3_DIR}/web/module_web.cpp module_imgui_sdl3_web.cpp
    ${N}/module_gui_common.cpp ${N}/module_imgui_ext.cpp ${N}/module_gba_mem.cpp
    ${IMGUI_BIND} ${MD4C_DIR}/md4c.c ${MD4C_DIR}/entity.c)
target_include_directories(generator PRIVATE ${MD4C_DIR})
target_link_libraries(generator PRIVATE libDaScript native_impl ${SDL_LIBS})
target_link_options(generator PRIVATE -lnodefs.js -sENVIRONMENT=node -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=4MB
    -sINITIAL_MEMORY=256MB -sNODERAWFS=0 -O1)
set_target_properties(generator PROPERTIES SUFFIX ".js")

set(AOT "${CMAKE_BINARY_DIR}/aot")
file(MAKE_DIRECTORY "${AOT}")
file(GLOB_RECURSE APP_SCRIPTS CONFIGURE_DEPENDS "${ROOT}/scripts/*.das")
file(GLOB_RECURSE BOOST_SCRIPTS "${DASSDL3_DIR}/dassdl3/*.das" "${IMGUI}/daslib/*.das")
add_custom_command(OUTPUT "${AOT}/battlecalc.das.cpp" "${AOT}/battlecalc.das.h"
    COMMAND "${NODE_EXECUTABLE}" "$<TARGET_FILE:generator>" "${ROOT}" "${AOT}" "${DAS}" "${DASSDL3_DIR}/dassdl3"
        "${IMGUI}/daslib"
    DEPENDS generator standalone.das ${APP_SCRIPTS} ${BOOST_SCRIPTS} VERBATIM)
add_custom_command(OUTPUT "${AOT}/imgui_aot_helpers.cpp"
    COMMAND "${CMAKE_COMMAND}" "-DSRC=${IMGUI}/src/dasIMGUI.main.cpp" "-DDST=${AOT}/imgui_aot_helpers.cpp"
        -P "${CMAKE_SOURCE_DIR}/extract_imgui_helpers.cmake"
    DEPENDS "${IMGUI}/src/dasIMGUI.main.cpp" extract_imgui_helpers.cmake VERBATIM)

# ---------------------------------------------------------------- the page
add_executable(battlecalc_web runner.cpp "${AOT}/battlecalc.das.cpp" "${AOT}/imgui_aot_helpers.cpp")
target_include_directories(battlecalc_web PRIVATE "${AOT}")
target_link_libraries(battlecalc_web PRIVATE native_impl libDaScript_runtime ${SDL_LIBS})
set(A "${ROOT}/assets")
target_link_options(battlecalc_web PRIVATE -O2
    "-Wl,-Map,${CMAKE_BINARY_DIR}/battlecalc_web.map"
    -sSTACK_SIZE=4MB -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB -sMAXIMUM_MEMORY=1GB
    -sFULL_ES3=1 -sMAX_WEBGL_VERSION=2 -sMIN_WEBGL_VERSION=1 -sFORCE_FILESYSTEM=1
    -sMODULARIZE=1 -sEXPORT_NAME=createBattleCalc -sINVOKE_RUN=0 -sEXIT_RUNTIME=0
    "-sEXPORTED_FUNCTIONS=['_main','_web_stop','_web_reload','_web_heap_bytes','_web_paste']"
    "-sEXPORTED_RUNTIME_METHODS=['callMain','FS','UTF8ToString','ccall']"
    "SHELL:--preload-file ${A}/fonts/DejaVuSans.ttf@/assets/fonts/DejaVuSans.ttf"
    "SHELL:--preload-file ${A}/icons/ffta_icons16.png@/assets/icons/ffta_icons16.png")
set_target_properties(battlecalc_web PROPERTIES SUFFIX ".js" RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/site")
add_custom_command(TARGET battlecalc_web POST_BUILD
    COMMAND "${CMAKE_COMMAND}" "-DMAP_FILE=${CMAKE_BINARY_DIR}/battlecalc_web.map" -P "${CMAKE_SOURCE_DIR}/check_standalone.cmake"
    VERBATIM)
if(CMAKE_HOST_WIN32)
    foreach(t generator battlecalc_web)
        add_custom_command(TARGET ${t} POST_BUILD COMMAND icacls "$<TARGET_FILE:${t}>" /reset VERBATIM)
    endforeach()
endif()
foreach(page index.html app.js)
    configure_file("${page}" "${CMAKE_BINARY_DIR}/site/${page}" COPYONLY)
endforeach()
