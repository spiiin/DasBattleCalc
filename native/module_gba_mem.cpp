// daScript bindings of gba_mem.cpp / gba_frame.cpp ("gba_mem" module).
#include "gui_das.h"
#include "gba_mem.h"

namespace das {
class Module_gba_mem : public Module {
    bool initialized = false;
public:
    Module_gba_mem() : Module("gba_mem") {}
    bool initDependencies() override {
        if (initialized) return true;
        ModuleLibrary lib(this);
        if (!gui_das::start(this, lib, {"sdl3"})) return false;
        initialized = true;
        GUI_BIND(gba_load_state);
        GUI_BIND(gba_load_rom);
        GUI_BIND(gba_has_state);
        GUI_BIND(gba_has_rom);
        GUI_BIND(gba_rom_code);
        GUI_BIND(gba_read8);
        GUI_BIND(gba_read16);
        GUI_BIND(gba_read32);
        GUI_BIND(gba_state_serial);
        GUI_BIND(gba_edit_begin);
        GUI_BIND(gba_edit8);
        GUI_BIND(gba_edit16);
        GUI_BIND(gba_edit32);
        GUI_BIND(gba_save_state);
        GUI_BIND(gba_frame_update);
        GUI_BIND(gba_frame_width);
        GUI_BIND(gba_frame_height);
        GUI_BIND(gba_frame_draw);
        GUI_BIND(gba_rom_serial);
        GUI_BIND(gba_gfx_icon);
        GUI_BIND(gba_gfx_sprite);
        GUI_BIND(nds_unit_sprite);
        GUI_BIND(nds_item_icon);
        GUI_BIND(gba_gfx_width);
        GUI_BIND(gba_gfx_height);
        GUI_BIND(gba_gfx_origin_x);
        GUI_BIND(gba_gfx_origin_y);
        GUI_BIND(gba_gfx_draw);
        GUI_BIND(gba_gfx_draw_quad);
        GUI_BIND(psx_unit_sprite);
        GUI_BIND(psx_item_icon);
        GUI_BIND(psx_map_texture);
        GUI_BIND(psx_open_disc);
        GUI_BIND(psx_has_disc);
        GUI_BIND(psx_disc_serial);
        GUI_BIND(psx_disc_file);
        GUI_BIND(psx_disc_read);
        GUI_BIND(psx_buf_size);
        GUI_BIND(psx_buf_read8);
        GUI_BIND(psx_buf_read16);
        GUI_BIND(psx_buf_read32);
        GUI_BIND(psx_find_map);
        GUI_BIND(gba_state_is_nds);
        GUI_BIND(gba_state_is_psx);
        GUI_BIND(gba_state_is_psp);
        GUI_BIND(nds_file);
        GUI_BIND(nds_pak_file);
        GUI_BIND(nds_arc_entry);
        GUI_BIND(nds_buf_size);
        GUI_BIND(nds_buf_read8);
        GUI_BIND(nds_buf_read16);
        GUI_BIND(nds_buf_read32);
        return true;
    }
    ModuleAotType aotRequire(TextWriter & tw) const override {
        tw << "#include \"gba_mem.h\"\n";
        return ModuleAotType::cpp;
    }
};
}
REGISTER_MODULE_IN_NAMESPACE(Module_gba_mem, das);
