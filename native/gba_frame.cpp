// The state's screenshot (Framebuffer.bmp) as an SDL texture for ImGui.
#include "gba_mem.h"
#include "imgui.h"
#include <SDL3/SDL.h>

static SDL_Texture * g_frame_tex = nullptr;
static uint32_t g_frame_serial = 0;
static float g_frame_w = 0, g_frame_h = 0;

bool gba_frame_update(SDL_Renderer * r) {
    if (g_frame_tex && g_frame_serial == gba_state_serial()) return true;
    if (g_frame_tex) { SDL_DestroyTexture(g_frame_tex); g_frame_tex = nullptr; }
    g_frame_serial = gba_state_serial();
    size_t n = 0;
    const uint8_t * bmp = gba_state_frame(n);
    if (!bmp) return false;
    SDL_Surface * s = SDL_LoadBMP_IO(SDL_IOFromConstMem(bmp, n), true);
    if (!s) return false;
    g_frame_tex = SDL_CreateTextureFromSurface(r, s);
    if (g_frame_tex) SDL_SetTextureScaleMode(g_frame_tex, SDL_SCALEMODE_NEAREST);
    g_frame_w = float(s->w); g_frame_h = float(s->h);
    SDL_DestroySurface(s);
    return g_frame_tex != nullptr;
}
float gba_frame_width() { return g_frame_tex ? g_frame_w : 0.0f; }
float gba_frame_height() { return g_frame_tex ? g_frame_h : 0.0f; }
void gba_frame_draw(float x, float y, float w, float h) {
    if (!g_frame_tex) return;
    ImGui::GetWindowDrawList()->AddImage(ImTextureRef((ImTextureID)(intptr_t)g_frame_tex), ImVec2(x, y), ImVec2(x + w, y + h));
}

