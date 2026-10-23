#pragma once
// GBA memory images (savestate RAM, ROM) read by the game scripts.
#include <cstddef>
#include <cstdint>

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
// changes on every successful gba_load_state
uint32_t gba_state_serial();
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
