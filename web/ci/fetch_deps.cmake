# CI: the sources a daScript build with dasImgui would fetch itself
# (the web build disables dasImgui in daScript and takes them directly).
# cmake -DDAS=<daScript> -DMD4C_ROOT=<dir> -P fetch_deps.cmake
set(IMGUI_VERSION "1.92.6-docking")
set(DAS_IMGUI_DIR "${DAS}/modules/dasImgui")
set(tmp "${CMAKE_CURRENT_BINARY_DIR}/ci_downloads")

function(fetch url sha dst)
    get_filename_component(name "${url}" NAME)
    file(DOWNLOAD "${url}" "${tmp}/${name}" EXPECTED_HASH SHA256=${sha} TLS_VERIFY ON)
    file(REMOVE_RECURSE "${tmp}/x")
    file(ARCHIVE_EXTRACT INPUT "${tmp}/${name}" DESTINATION "${tmp}/x")
    file(GLOB top "${tmp}/x/*")
    file(REMOVE_RECURSE "${dst}")
    file(RENAME "${top}" "${dst}")
endfunction()

fetch("https://github.com/ocornut/imgui/archive/refs/tags/v${IMGUI_VERSION}.tar.gz"
    5e84cdaa6a6041586a0d11a3071b749734a0439d66fdbdad37ae5b27e37d396c "${DAS_IMGUI_DIR}/imgui")
include("${DAS_IMGUI_DIR}/patches/input_routing.cmake")
# the ImVector data() patch of dasImgui/CMakeLists.txt
file(READ "${DAS_IMGUI_DIR}/imgui/imgui.h" h)
string(REPLACE
    "inline T*           end()                               { return Data + Size; }"
    "inline T*           data()                              { return Data; }\n    inline const T*     data() const                        { return Data; }\n    inline T*           end()                               { return Data + Size; }"
    h "${h}")
file(WRITE "${DAS_IMGUI_DIR}/imgui/imgui.h" "${h}")

fetch("https://github.com/mity/md4c/archive/refs/tags/release-0.5.3.tar.gz"
    353c346f376b87c954a13f3415ede2d51264cc61dc5abcd38ff1d2aa0d059b9e "${MD4C_ROOT}")
