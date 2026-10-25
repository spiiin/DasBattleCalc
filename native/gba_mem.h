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
bool nds_state_write_ram(std::vector<uint8_t> & core, const std::vector<uint8_t> & ram,
                         const std::vector<uint8_t> & loaded, std::string & error);
// between gba_mem.cpp and psp_mem.cpp: a PPSSPP save state (.ppst)
bool psp_is_state(const std::vector<uint8_t> & file);
bool psp_state_ram(const std::vector<uint8_t> & file, std::vector<uint8_t> & raw, size_t & ram_off,
                   size_t & ram_size, std::string & error);
bool psp_state_write(const std::vector<uint8_t> & file, std::vector<uint8_t> raw, size_t ram_off,
                     const std::vector<uint8_t> & ram, std::vector<uint8_t> & out, std::string & error);
// a zstd frame of raw (stored) blocks: no compressor needed
std::vector<uint8_t> zstd_store(const std::vector<uint8_t> & data);

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
// The loaded state is a PPSSPP one (PSP): 0x08000000.. is the user RAM
// (32 MB; 0x08000000 + size reads as 0 beyond it). Reads of 0x08xxxxxx
// and 0x09xxxxxx then go to this RAM, not to a ROM.
bool gba_state_is_psp();
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
// FFTA2 (NDS): frame `frame` of unit graphics set `set` (char/rom/pak/
// UnitCg.pak: LZ77 blocks of A3I5 texels; palette `palette` of the
// set's palette block in UnitSst.pak); flip - mirrored. The origin is
// the frame's bottom centre (the feet). -1: no such frame, or a frame
// not in plain A3I5 (the big monsters' are assembled from parts).
int nds_unit_sprite(SDL_Renderer * r, int set, int palette, int frame, bool flip);
// FFTA2 (NDS): 16 x 16 item icon `icon` (equipment +2): menu/icon_rom/
// itemicon00..02.pak (256 icons each, 4bpp, rows of 8 bytes), the
// palette (0..2 of itemicon.plt) by 4 bits per icon of itemicon0N.bhd +4
int nds_item_icon(SDL_Renderer * r, int icon);
float gba_gfx_width(int handle);
float gba_gfx_height(int handle);
float gba_gfx_origin_x(int handle);
float gba_gfx_origin_y(int handle);
void gba_gfx_draw(int handle, float x, float y, float w, float h, float alpha);
