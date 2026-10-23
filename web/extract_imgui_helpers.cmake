# The helper functions of dasImgui's dasIMGUI.main.cpp (Text, InputText,
# AddText, DockBuilder*_das, ...) without the module class: AOT code calls
# them, and the module registration would pull the compiler into the page.
file(READ "${SRC}" text)
string(FIND "${text}" "    void Module_dasIMGUI::initAotAlias" cut)
if(cut LESS 0)
    message(FATAL_ERROR "dasIMGUI.main.cpp layout changed: review web/extract_imgui_helpers.cmake")
endif()
string(SUBSTRING "${text}" 0 ${cut} head)
file(WRITE "${DST}" "// generated from ${SRC}\n${head}}\n")
