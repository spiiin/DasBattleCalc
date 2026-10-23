#pragma once
// ImGui extras for the Blendish look (imgui_ext.cpp). Plain C++: called by
// the daScript bindings and directly by AOT-generated code.
#include <SDL3/SDL.h>
#include <cstdint>

void imx_bnd_box(float x, float y, float w, float h, float r, int sharp, uint32_t top, uint32_t bottom, uint32_t outline, float s);
void imx_style_blendish();
void imx_hide_tab_bar();
bool imx_begin_status_bar(float height);
int imx_vtx_count();
void imx_shade_vertical(int start, float y0, float y1, uint32_t top, uint32_t bottom);
void imx_gradient_box(float x, float y, float w, float h, float rounding, int corners, uint32_t top, uint32_t bottom, uint32_t outline);
bool imx_load_icons(SDL_Renderer * r, const char * path);
void imx_icon_at(float x, float y, int icon, float size, float alpha);
void imx_icon(int icon, float size);
void imx_style_color(int index, uint32_t c);
void imx_style_metrics(float window_rounding, float frame_rounding, float frame_border, float item_spacing_x, float item_spacing_y, float frame_pad_x, float frame_pad_y);
void imx_capture_style();
void imx_ui_scale(float scale);
