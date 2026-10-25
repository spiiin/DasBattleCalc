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
// psx_mem.cpp: the 2 MB main RAM of a BizHawk Nymashock (PSX) waterbox
// image, found by the start of the game's code; its offset in the image
const size_t PSX_RAM_SIZE = 0x200000;
bool psx_state_ram(const std::vector<uint8_t> & core, std::vector<uint8_t> & ram, size_t & base);
const std::vector<uint8_t> * psx_buf(int h);
bool nds_state_write_ram(std::vector<uint8_t> & core, const std::vector<uint8_t> & ram,
                         const std::vector<uint8_t> & loaded, std::string & error);

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
bool gba_state_is_psx();
int nds_file(const char * name);
int nds_pak_file(const char * idx_name, const char * pak_name, int index);
// an entry of the pc.bin archive by its name hash (the names of the
// scripts are not known); ch: the distinguishing character of a list, 0 first
int nds_arc_entry(int hash, int ch);
int nds_buf_size(int handle);
uint32_t nds_buf_read8(int handle, int off);
uint32_t nds_buf_read16(int handle, int off);
uint32_t nds_buf_read32(int handle, int off);
// The PSX game's disc (psx_mem.cpp): a .cue or a MODE2/2352 .bin, "" on
// success. Files by ISO9660 path ("BATTLE/TYPE1.SHP") or sectors, read
// whole: a handle >= 0 or -1 (kept until another disc is opened).
const char * psx_open_disc(const char * path);
bool psx_has_disc();
uint32_t psx_disc_serial();
int psx_disc_file(const char * path);
int psx_disc_read(int lba, int size);
int psx_buf_size(int handle);
uint32_t psx_buf_read8(int handle, int off);
uint32_t psx_buf_read16(int handle, int off);
uint32_t psx_buf_read32(int handle, int off);
// the battle's map number (MAPnnn.GNS held in RAM), -1 unknown
int psx_find_map();
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
// FFT (PSX): frame `frame` of battle sprite `sprite` (BATTLE.BIN's
// table: the .SPR sheet, the SHP of its kind), palette 0..15; flip -
// mirrored. The origin: the feet. -1 without the disc.
int psx_unit_sprite(SDL_Renderer * r, int sprite, int palette, int frame, bool flip);
// FFT (PSX): the 16 x 16 icon of item `item` (EVENT/ITEM.BIN; the palette
// and the icon from the item table in RAM)
int psx_item_icon(SDL_Renderer * r, int item);
// FFT (PSX): a 256 x 256 page (0..3) of a map texture (disc buffer
// tex_buf) with palette 0..15 of the mesh (buffer pal_buf at pal_off)
int psx_map_texture(SDL_Renderer * r, int tex_buf, int pal_buf, int pal_off, int page, int palette);
float gba_gfx_width(int handle);
float gba_gfx_height(int handle);
float gba_gfx_origin_x(int handle);
float gba_gfx_origin_y(int handle);
void gba_gfx_draw(int handle, float x, float y, float w, float h, float alpha);
// a textured quad: screen corners, texture coordinates (0..1), shade 0..1
void gba_gfx_draw_quad(int handle, float x0, float y0, float x1, float y1, float x2, float y2, float x3, float y3,
                       float u0, float v0, float u1, float v1, float u2, float v2, float u3, float v3, float shade);
