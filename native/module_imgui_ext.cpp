// daScript bindings of imgui_ext.cpp ("imgui_ext" module).
#include "gui_das.h"
#include "imgui.h"
#include "imgui_ext.h"

namespace das {
class Module_imgui_ext : public Module {
    bool initialized = false;
public:
    Module_imgui_ext() : Module("imgui_ext") {}
    bool initDependencies() override {
        if (initialized) return true;
        ModuleLibrary lib(this);
        if (!gui_das::start(this, lib, {"sdl3", "gui_common"})) return false;
        initialized = true;
#define C(N) addConstant<int32_t>(*this, #N, int32_t(N))
        C(ImDrawFlags_RoundCornersAll); C(ImDrawFlags_RoundCornersNone); C(ImDrawFlags_RoundCornersLeft);
        C(ImDrawFlags_RoundCornersRight); C(ImDrawFlags_RoundCornersTop); C(ImDrawFlags_RoundCornersBottom);
#undef C
        GUI_BIND(imx_bnd_box);
        GUI_BIND(imx_style_blendish);
        GUI_BIND(imx_hide_tab_bar);
        GUI_BIND(imx_begin_status_bar);
        GUI_BIND(imx_vtx_count);
        GUI_BIND(imx_shade_vertical);
        GUI_BIND(imx_gradient_box);
        GUI_BIND(imx_load_icons);
        GUI_BIND(imx_icon_at);
        GUI_BIND(imx_icon);
        GUI_BIND(imx_style_color);
        GUI_BIND(imx_style_metrics);
        GUI_BIND(imx_capture_style);
        GUI_BIND(imx_ui_scale);
        return true;
    }
    ModuleAotType aotRequire(TextWriter & tw) const override {
        tw << "#include \"imgui_ext.h\"\n";
        tw << "#include \"dasimgui_aot_extra.h\"\n";
        return ModuleAotType::cpp;
    }
};
}
REGISTER_MODULE_IN_NAMESPACE(Module_imgui_ext, das);
