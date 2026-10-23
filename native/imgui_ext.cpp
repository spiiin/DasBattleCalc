// Small ImGui extras for a Blender-like look: vertical gradients on draw
// list vertices (ImGui's internal ShadeVertsLinearColorGradientKeepAlpha),
// a Blendish-style gradient box, the Blender icon sheet, style colors.
#include "imgui_ext.h"
#include "imgui.h"
#include "imgui_internal.h"

static SDL_Texture * g_icons = nullptr;
static float g_icons_w = 1, g_icons_h = 1;

static ImU32 abgr(uint32_t c) { return IM_COL32(c >> 24, (c >> 16) & 255, (c >> 8) & 255, c & 255); }

int imx_vtx_count() { return ImGui::GetWindowDrawList()->VtxBuffer.Size; }

// Recolors vertices [start, now) with a vertical gradient, keeping their alpha.
void imx_shade_vertical(int start, float y0, float y1, uint32_t top, uint32_t bottom) {
    ImDrawList * dl = ImGui::GetWindowDrawList();
    ImGui::ShadeVertsLinearColorGradientKeepAlpha(dl, start, dl->VtxBuffer.Size, ImVec2(0, y0), ImVec2(0, y1),
                                                  abgr(top), abgr(bottom));
}

// Blendish "inner box + outline": rounded rect with a vertical gradient.
// corners - ImDrawFlags_RoundCorners* bits (0 - all corners).
void imx_gradient_box(float x, float y, float w, float h, float rounding, int corners,
                             uint32_t top, uint32_t bottom, uint32_t outline) {
    ImDrawList * dl = ImGui::GetWindowDrawList();
    ImDrawFlags flags = corners ? (ImDrawFlags)corners : ImDrawFlags_RoundCornersAll;
    int start = dl->VtxBuffer.Size;
    dl->AddRectFilled(ImVec2(x, y), ImVec2(x + w, y + h), IM_COL32_WHITE, rounding, flags);
    ImGui::ShadeVertsLinearColorGradientKeepAlpha(dl, start, dl->VtxBuffer.Size, ImVec2(0, y), ImVec2(0, y + h),
                                                  abgr(top), abgr(bottom));
    if (outline & 255)
        dl->AddRect(ImVec2(x + 0.5f, y + 0.5f), ImVec2(x + w - 0.5f, y + h - 0.5f), abgr(outline), rounding, flags, 1.0f);
}

// Blendish widget frame, same geometry as bndInnerBox + bndOutlineBox:
// inner (x+1, y+1, w-2, h-3, r-1) with a vertical gradient, outline
// (x+.5, y+.5, w-1, h-2, r). sharp - Blendish BND_CORNER_* bits (corners
// that are NOT rounded); s - UI scale (Blendish units -> pixels).
static ImDrawFlags corners_of(int sharp) {
    ImDrawFlags f = 0;
    if (!(sharp & 1)) f |= ImDrawFlags_RoundCornersTopLeft;
    if (!(sharp & 2)) f |= ImDrawFlags_RoundCornersTopRight;
    if (!(sharp & 4)) f |= ImDrawFlags_RoundCornersBottomRight;
    if (!(sharp & 8)) f |= ImDrawFlags_RoundCornersBottomLeft;
    return f ? f : ImDrawFlags_RoundCornersNone;
}
void imx_bnd_box(float x, float y, float w, float h, float r, int sharp,
                        uint32_t top, uint32_t bottom, uint32_t outline, float s) {
    ImDrawList * dl = ImGui::GetWindowDrawList();
    ImDrawFlags f = corners_of(sharp);
    float d = ImMin(w, h) * 0.5f;
    float ri = ImMin(ImMax(0.0f, (r - 1) * s), d), ro = ImMin(r * s, d);
    if ((top | bottom) & 255) {   // both transparent: outline only
        int start = dl->VtxBuffer.Size;
        dl->AddRectFilled(ImVec2(x + s, y + s), ImVec2(x + w - s, y + h - 2 * s), IM_COL32(255, 255, 255, 255), ri, f);
        ImGui::ShadeVertsLinearColorGradientKeepAlpha(dl, start, dl->VtxBuffer.Size, ImVec2(0, y), ImVec2(0, y + h),
                                                      abgr(top), abgr(bottom));
        // KeepAlpha keeps the white's alpha: apply the colors' own alpha
        float a0 = (top & 255) / 255.0f, a1 = (bottom & 255) / 255.0f;
        for (int i = start; i < dl->VtxBuffer.Size; ++i) {
            ImDrawVert & v = dl->VtxBuffer[i];
            float t = ImClamp((v.pos.y - y) / ImMax(h, 1.0f), 0.0f, 1.0f);
            int a = (int)((a0 + (a1 - a0) * t) * ((v.col >> IM_COL32_A_SHIFT) & 255));
            v.col = (v.col & ~IM_COL32_A_MASK) | ((ImU32)a << IM_COL32_A_SHIFT);
        }
    }
    if (outline & 255)
        dl->AddRect(ImVec2(x + 0.5f * s, y + 0.5f * s), ImVec2(x + w - 0.5f * s, y + h - 1.5f * s), abgr(outline), ro, f, s);
}
// Blendish metrics (scale 1): 21 px widgets with a 15 px font, flat panels.
void imx_style_blendish() {
    ImGuiStyle & s = ImGui::GetStyle();
    s.WindowPadding = ImVec2(0, 0); s.WindowRounding = 0; s.WindowBorderSize = 0;
    s.ChildRounding = 0; s.ChildBorderSize = 0;
    s.PopupRounding = 3; s.PopupBorderSize = 1;
    s.FramePadding = ImVec2(8, 3); s.FrameRounding = 4; s.FrameBorderSize = 0;
    s.ItemSpacing = ImVec2(8, 2); s.ItemInnerSpacing = ImVec2(4, 2);
    s.IndentSpacing = 16; s.ScrollbarSize = 13; s.ScrollbarRounding = 7;
    s.GrabRounding = 4; s.TabRounding = 4; s.DockingSeparatorSize = 1;
    s.WindowMenuButtonPosition = ImGuiDir_None;
}
// The current docked window shows no tab bar (Blender panels have none).
void imx_hide_tab_bar() {
    if (ImGuiDockNode * n = ImGui::GetWindowDockNode()) n->LocalFlags |= ImGuiDockNodeFlags_NoTabBar;
}
// A bar along the bottom of the main viewport, outside the dock space.
// Call before DockSpaceOverViewport; when true, End() it.
bool imx_begin_status_bar(float height) {
    return ImGui::BeginViewportSideBar("##statusbar", ImGui::GetMainViewport(), ImGuiDir_Down, height,
        ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoDecoration);
}

bool imx_load_icons(SDL_Renderer * r, const char * path) {
    SDL_Surface * s = SDL_LoadPNG(path);
    if (!s) { SDL_Log("icons: %s", SDL_GetError()); return false; }
    g_icons = SDL_CreateTextureFromSurface(r, s);
    g_icons_w = (float)s->w; g_icons_h = (float)s->h;
    SDL_DestroySurface(s);
    return g_icons != nullptr;
}

// Icon ids are Blendish's BND_ICONID(x, y): 16 px cells on a 21 px grid.
static void icon_uv(int icon, ImVec2 & uv0, ImVec2 & uv1) {
    int ix = icon & 0xff, iy = (icon >> 8) & 0xff;
    float u = 5.0f + ix * 21.0f, v = 10.0f + iy * 21.0f;
    uv0 = ImVec2(u / g_icons_w, v / g_icons_h);
    uv1 = ImVec2((u + 16) / g_icons_w, (v + 16) / g_icons_h);
}
void imx_icon_at(float x, float y, int icon, float size, float alpha) {
    if (!g_icons || icon < 0) return;
    ImVec2 uv0, uv1; icon_uv(icon, uv0, uv1);
    ImGui::GetWindowDrawList()->AddImage(ImTextureRef((ImTextureID)(intptr_t)g_icons), ImVec2(x, y),
                                         ImVec2(x + size, y + size), uv0, uv1, IM_COL32(255, 255, 255, (int)(alpha * 255)));
}
void imx_icon(int icon, float size) {
    if (!g_icons) return;
    ImVec2 uv0, uv1; icon_uv(icon, uv0, uv1);
    ImGui::Image(ImTextureRef((ImTextureID)(intptr_t)g_icons), ImVec2(size, size), uv0, uv1);
}

void imx_style_color(int index, uint32_t c) {
    if (index >= 0 && index < ImGuiCol_COUNT)
        ImGui::GetStyle().Colors[index] = ImGui::ColorConvertU32ToFloat4(abgr(c));
}
void imx_style_metrics(float window_rounding, float frame_rounding, float frame_border,
                              float item_spacing_x, float item_spacing_y, float frame_pad_x, float frame_pad_y) {
    ImGuiStyle & s = ImGui::GetStyle();
    s.WindowRounding = window_rounding; s.ChildRounding = window_rounding; s.PopupRounding = frame_rounding;
    s.FrameRounding = frame_rounding; s.GrabRounding = frame_rounding; s.TabRounding = frame_rounding;
    s.FrameBorderSize = frame_border; s.PopupBorderSize = 1; s.WindowBorderSize = 1;
    s.ItemSpacing = ImVec2(item_spacing_x, item_spacing_y);
    s.FramePadding = ImVec2(frame_pad_x, frame_pad_y);
    s.ScrollbarRounding = frame_rounding; s.WindowMenuButtonPosition = ImGuiDir_None;
}
// UI scale in ImGui 1.92: sizes via ScaleAllSizes on the unscaled style
// (captured once after the theme is set), fonts via FontScaleMain - the
// dynamic font atlas renders glyphs at the new size, so text stays sharp.
static ImGuiStyle g_base_style;
static bool g_base_captured = false;
void imx_capture_style() { g_base_style = ImGui::GetStyle(); g_base_captured = true; }
void imx_ui_scale(float scale) {
    if (!g_base_captured) imx_capture_style();
    ImGuiStyle s = g_base_style;
    s.ScaleAllSizes(scale);
    s.FontScaleMain = scale;
    ImGui::GetStyle() = s;
}

