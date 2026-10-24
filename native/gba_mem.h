#pragma once
// GBA memory images (savestate RAM, ROM) read by the game scripts.
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

// between gba_mem.cpp and nds_mem.cpp (not bound to scripts)
const std::vector<uint8_t> & gba_rom_bytes();
bool nds_state_ram(const std::vector<uint8_t> & core, std::vector<uint8_t> & ram, std::string & error);
bool nds_is_rom(const std::vector<uint8_t> & rom);

// "" on success, else the error text
const char * gba_load_state(const char * path);
const char * gba_load_rom(const char * path);
bool gba_has_state();
bool gba_has_rom();
const char * gba_rom_code();
// 0x02xxxxxx EWRAM, 0x03xxxxxx IWRAM, 0x08xxxxxx ROM; 0 outside
uint32_t gba_read8(uint32_t addr);
uint32_t gba_read16(uint32_t addr);
uint32_t gba_read32(uint32_t addr);
// BMP screenshot stored in the state (BizHawk Framebuffer.bmp), or null
const uint8_t * gba_state_frame(size_t & size);
// The loaded state is an NDS one (melonDS): 0x02000000.. is the 4 MB main
// RAM (pages the state does not hold read as 0). NDS ROM files
// (nds_mem.cpp, FFTA2's archive): a handle >= 0 or -1, read by offset.
bool gba_state_is_nds();
int nds_file(const char * name);
int nds_pak_file(const char * idx_name, const char * pak_name, int index);
// an entry of the pc.bin archive by its name hash (the names of the
// scripts are not known); ch: the distinguishing character of a list, 0 first
int nds_arc_entry(int hash, int ch);
int nds_buf_size(int handle);
uint32_t nds_buf_read8(int handle, int off);
uint32_t nds_buf_read16(int handle, int off);
uint32_t nds_buf_read32(int handle, int off);
// changes on every successful gba_load_state / gba_load_rom
uint32_t gba_state_serial();
uint32_t gba_rom_serial();
// Writing a state: copy the loaded RAM, change it, save as a new file
// ("" on success). Reads (gba_read*) still see the loaded RAM.
void gba_edit_begin();
void gba_edit8(uint32_t addr, uint32_t value);
void gba_edit16(uint32_t addr, uint32_t value);
void gba_edit32(uint32_t addr, uint32_t value);
const char * gba_save_state(const char * path);

// gba_frame.cpp: the state's screenshot as a texture, drawn by ImGui
struct SDL_Renderer;
bool gba_frame_update(SDL_Renderer * r);
float gba_frame_width();
float gba_frame_height();
void gba_frame_draw(float x, float y, float w, float h);

// gba_gfx.cpp: graphics decoded from the ROM into SDL textures (cached
// until another ROM is loaded). Formats: research/notes.md, "Graphics".
// A handle >= 0 or -1; imx_icon_at draws icon ids >= GBA_GFX_ICON_BASE.
const int GBA_GFX_ICON_BASE = 0x10000;
// 16 x 16 icon: entry `index` of an "A7" archive, 2 x 2 4bpp tiles, a
// 16-colour palette (BGR555) at `palette`
int gba_gfx_icon(SDL_Renderer * r, uint32_t archive, int index, uint32_t palette);
// a sprite frame: 4bpp tiles at `tiles`, pieces of the layout at `layout`
// (u16 count, 6 bytes per piece as in OAM), 16-colour palette; flip -
// mirrored. The origin (the layout's 0, 0) is gba_gfx_origin_x / _y.
int gba_gfx_sprite(SDL_Renderer * r, uint32_t tiles, uint32_t layout, uint32_t palette, bool flip);
float gba_gfx_width(int handle);
float gba_gfx_height(int handle);
float gba_gfx_origin_x(int handle);
float gba_gfx_origin_y(int handle);
void gba_gfx_draw(int handle, float x, float y, float w, float h, float alpha);
