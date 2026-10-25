#pragma once
// Native helpers shared by the hosts: font + primitives on SDL_Renderer,
// command line options, scripted input (--script) and screenshots.
#include <SDL3/SDL.h>
#include <string>
#include <vector>

struct GuiFont;

// Colors are packed 0xRRGGBBAA everywhere in this project.
SDL_FColor gui_color(uint32_t rgba);

// Font: TTF baked with stb_truetype into an SDL texture (ASCII + Cyrillic).
GuiFont * gui_font_load(SDL_Renderer * renderer, const char * path, float pixel_height);
float gui_font_height(GuiFont * font);   // line height in pixels
float gui_font_ascent(GuiFont * font);
float gui_text_width_n(GuiFont * font, const char * text, int len);
float gui_text_width(GuiFont * font, const char * text);
// y is the top of the line.
void gui_text_n(SDL_Renderer * r, GuiFont * font, const char * text, int len, float x, float y, uint32_t rgba);
void gui_text(SDL_Renderer * r, GuiFont * font, const char * text, float x, float y, uint32_t rgba);

// Anti-aliased primitives (1 px fringe, as ImGui does) via SDL_RenderGeometry.
void gui_fill_rect(SDL_Renderer * r, float x, float y, float w, float h, uint32_t rgba);
void gui_rect(SDL_Renderer * r, float x, float y, float w, float h, float thickness, uint32_t rgba);
void gui_fill_round_rect(SDL_Renderer * r, float x, float y, float w, float h, float radius, uint32_t rgba);
void gui_fill_round_rect4(SDL_Renderer * r, float x, float y, float w, float h,
                          float tl, float tr, float br, float bl, uint32_t rgba);
void gui_line(SDL_Renderer * r, float x0, float y0, float x1, float y1, float thickness, uint32_t rgba);
void gui_fill_triangle(SDL_Renderer * r, float x0, float y0, float x1, float y1, float x2, float y2, uint32_t rgba);
void gui_fill_circle(SDL_Renderer * r, float cx, float cy, float radius, uint32_t rgba);
void gui_circle(SDL_Renderer * r, float cx, float cy, float radius, float thickness, uint32_t rgba);
void gui_fill_convex(SDL_Renderer * r, const float * xy, int count, uint32_t rgba);
void gui_clip(SDL_Renderer * r, float x, float y, float w, float h);
void gui_no_clip(SDL_Renderer * r);

// Screenshots.
bool gui_save_renderer_png(SDL_Renderer * r, const char * path);
// Writes text to path ("" or the error); in the browser the file is also
// handed to the user as a download (its name: the last part of path).
const char * gui_save_text(const char * path, const char * text);

// File dialogs (SDL3's, desktop only: false in the browser) and files
// dropped on the window. gui_file_dialog asks; the chosen path comes later
// from gui_file_dialog_result(id) once ("" until then, or if cancelled).
// patterns: "State;ppst" (extensions without dots, ';' between).
bool gui_has_file_dialog();
void gui_file_dialog(int id, bool save, const char * filter_name, const char * patterns, const char * default_path);
const char * gui_file_dialog_result(int id);
// the next file dropped on the window, "" none
const char * gui_take_dropped();

// Command line after the script name: --name value.
void gui_set_args(int argc, char ** argv);
const char * gui_arg(const char * name, const char * fallback);
int gui_arg_int(const char * name, int fallback);
const char * gui_project_dir();

// Scripted input (--script), see gui_common.cpp.
void gui_script_step(SDL_Window * window, int frame);
const char * gui_script_shot(int frame);
int gui_script_end();
