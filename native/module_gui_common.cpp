#include "gui_das.h"

namespace das {
class Module_gui_common : public Module {
    bool initialized = false;
public:
    Module_gui_common() : Module("gui_common") {}
    bool initDependencies() override {
        if (initialized) return true;
        ModuleLibrary lib(this);
        if (!gui_das::start(this, lib, {"sdl3"})) return false;
        initialized = true;
        GUI_OPAQUE(GuiFont);
        GUI_BIND(gui_font_load);
        GUI_BIND(gui_font_height);
        GUI_BIND(gui_font_ascent);
        GUI_BIND(gui_text_width);
        GUI_BIND(gui_text);
        GUI_BIND(gui_fill_rect);
        GUI_BIND(gui_rect);
        GUI_BIND(gui_fill_round_rect);
        GUI_BIND(gui_fill_round_rect4);
        GUI_BIND(gui_line);
        GUI_BIND(gui_fill_triangle);
        GUI_BIND(gui_fill_circle);
        GUI_BIND(gui_circle);
        GUI_BIND(gui_clip);
        GUI_BIND(gui_no_clip);
        GUI_BIND(gui_save_renderer_png);
        GUI_BIND(gui_save_text);
        GUI_BIND(gui_arg);
        GUI_BIND(gui_arg_int);
        GUI_BIND(gui_project_dir);
        GUI_BIND(gui_script_step);
        GUI_BIND(gui_script_shot);
        GUI_BIND(gui_script_end);
        return true;
    }
    ModuleAotType aotRequire(TextWriter & tw) const override {
        tw << "#include \"gui_common.h\"\n";
        return ModuleAotType::cpp;
    }
};
}
REGISTER_MODULE_IN_NAMESPACE(Module_gui_common, das);
