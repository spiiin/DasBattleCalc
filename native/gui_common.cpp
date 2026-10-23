#include "gui_common.h"
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>

#define STBTT_STATIC
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

SDL_FColor gui_color(uint32_t c) {
    return SDL_FColor{ ((c >> 24) & 255) / 255.0f, ((c >> 16) & 255) / 255.0f,
                       ((c >> 8) & 255) / 255.0f, (c & 255) / 255.0f };
}

// ---------------------------------------------------------------- font

struct GuiFontRange { int first; int count; std::vector<stbtt_packedchar> chars; };

struct GuiFont {
    SDL_Texture * texture = nullptr;
    float pixel_height = 0, ascent = 0, descent = 0, line_gap = 0;
    int tex_w = 0, tex_h = 0;
    std::vector<GuiFontRange> ranges;
};

static std::vector<std::unique_ptr<GuiFont>> g_fonts;

static int utf8_next(const char *& s, const char * end) {
    unsigned char c = (unsigned char)*s++;
    if (c < 0x80) return c;
    int n = (c >= 0xF0) ? 3 : (c >= 0xE0) ? 2 : (c >= 0xC0) ? 1 : 0;
    int cp = c & (0x3F >> n);
    for (int i = 0; i < n && s < end; ++i) cp = (cp << 6) | ((unsigned char)*s++ & 0x3F);
    return cp;
}

static const stbtt_packedchar * find_glyph(GuiFont * f, int cp) {
    for (auto & r : f->ranges)
        if (cp >= r.first && cp < r.first + r.count) return &r.chars[cp - r.first];
    return cp != '?' ? find_glyph(f, '?') : nullptr;
}

GuiFont * gui_font_load(SDL_Renderer * renderer, const char * path, float px) {
    size_t size = 0;
    auto data = (unsigned char *)SDL_LoadFile(path, &size);
    if (!data) { SDL_Log("font: can not read %s", path); return nullptr; }
    auto font = std::make_unique<GuiFont>();
    font->pixel_height = px;
    font->tex_w = 1024; font->tex_h = 512;
    std::vector<unsigned char> alpha(font->tex_w * font->tex_h);
    stbtt_pack_context pc;
    stbtt_PackBegin(&pc, alpha.data(), font->tex_w, font->tex_h, 0, 1, nullptr);
    stbtt_PackSetOversampling(&pc, 2, 1);
    const int ranges[][2] = { {32, 95}, {0xA0, 0x60}, {0x400, 0x60}, {0x2013, 0x14},
                              {0x2190, 0x10}, {0x25A0, 0x60}, {0x2713, 0x02} };
    for (auto & r : ranges) {
        GuiFontRange fr; fr.first = r[0]; fr.count = r[1]; fr.chars.resize(r[1]);
        stbtt_PackFontRange(&pc, data, 0, px, r[0], r[1], fr.chars.data());
        font->ranges.push_back(std::move(fr));
    }
    stbtt_PackEnd(&pc);
    stbtt_fontinfo info;
    stbtt_InitFont(&info, data, stbtt_GetFontOffsetForIndex(data, 0));
    int asc, desc, gap;
    stbtt_GetFontVMetrics(&info, &asc, &desc, &gap);
    float scale = stbtt_ScaleForPixelHeight(&info, px);
    font->ascent = asc * scale; font->descent = desc * scale; font->line_gap = gap * scale;
    SDL_free(data);
    std::vector<uint32_t> rgba(alpha.size());
    for (size_t i = 0; i < alpha.size(); ++i) rgba[i] = 0x00FFFFFFu | (uint32_t(alpha[i]) << 24);
    font->texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STATIC,
                                      font->tex_w, font->tex_h);
    SDL_UpdateTexture(font->texture, nullptr, rgba.data(), font->tex_w * 4);
    SDL_SetTextureBlendMode(font->texture, SDL_BLENDMODE_BLEND);
    SDL_SetTextureScaleMode(font->texture, SDL_SCALEMODE_LINEAR);
    g_fonts.push_back(std::move(font));
    return g_fonts.back().get();
}

float gui_font_height(GuiFont * f) { return f ? std::ceil(f->ascent - f->descent + f->line_gap) : 0; }
float gui_font_ascent(GuiFont * f) { return f ? f->ascent : 0; }

float gui_text_width_n(GuiFont * f, const char * text, int len) {
    if (!f || !text) return 0;
    float w = 0;
    const char * end = text + len;
    for (const char * s = text; s < end;) {
        int cp = utf8_next(s, end);
        if (auto g = find_glyph(f, cp)) w += g->xadvance;
    }
    return w;
}
float gui_text_width(GuiFont * f, const char * text) {
    return text ? gui_text_width_n(f, text, (int)strlen(text)) : 0;
}

void gui_text_n(SDL_Renderer * r, GuiFont * f, const char * text, int len, float x, float y, uint32_t rgba) {
    if (!f || !text || !len) return;
    std::vector<SDL_Vertex> v;
    std::vector<int> idx;
    SDL_FColor col = gui_color(rgba);
    float px = std::floor(x), py = std::floor(y + f->ascent + 0.5f);
    const char * end = text + len;
    for (const char * s = text; s < end;) {
        int cp = utf8_next(s, end);
        const stbtt_packedchar * g = find_glyph(f, cp);
        if (!g) continue;
        stbtt_aligned_quad q;
        float gx = px, gy = py;
        for (auto & rg : f->ranges) {
            if (g >= rg.chars.data() && g < rg.chars.data() + rg.chars.size()) {
                stbtt_GetPackedQuad(rg.chars.data(), f->tex_w, f->tex_h, int(g - rg.chars.data()), &gx, &gy, &q, 0);
                break;
            }
        }
        px = gx;
        int base = (int)v.size();
        v.push_back({ {q.x0, q.y0}, col, {q.s0, q.t0} });
        v.push_back({ {q.x1, q.y0}, col, {q.s1, q.t0} });
        v.push_back({ {q.x1, q.y1}, col, {q.s1, q.t1} });
        v.push_back({ {q.x0, q.y1}, col, {q.s0, q.t1} });
        int quad[6] = { base, base + 1, base + 2, base, base + 2, base + 3 };
        idx.insert(idx.end(), quad, quad + 6);
    }
    if (!v.empty()) SDL_RenderGeometry(r, f->texture, v.data(), (int)v.size(), idx.data(), (int)idx.size());
}
void gui_text(SDL_Renderer * r, GuiFont * f, const char * text, float x, float y, uint32_t rgba) {
    if (text) gui_text_n(r, f, text, (int)strlen(text), x, y, rgba);
}

// ---------------------------------------------------------- primitives

// Convex polygon with a 1 px anti-aliasing fringe (ImGui's approach).
void gui_fill_convex(SDL_Renderer * r, const float * xy, int n, uint32_t rgba) {
    if (n < 3) return;
    SDL_FColor col = gui_color(rgba), tr = col;
    tr.a = 0;
    float area = 0;
    for (int i = 0; i < n; ++i) {
        int j = (i + 1) % n;
        area += xy[i * 2] * xy[j * 2 + 1] - xy[j * 2] * xy[i * 2 + 1];
    }
    float sign = area > 0 ? 1.0f : -1.0f;
    std::vector<float> nx(n), ny(n);
    for (int i = 0; i < n; ++i) {   // edge normals, pointing outside
        int j = (i + 1) % n;
        float dx = xy[j * 2] - xy[i * 2], dy = xy[j * 2 + 1] - xy[i * 2 + 1];
        float l = std::sqrt(dx * dx + dy * dy);
        if (l > 0) { dx /= l; dy /= l; }
        nx[i] = dy * sign; ny[i] = -dx * sign;
    }
    std::vector<SDL_Vertex> v(n * 2);
    std::vector<int> idx;
    idx.reserve((n - 2) * 3 + n * 6);
    for (int i = 0; i < n; ++i) {
        int p = (i + n - 1) % n;
        float mx = (nx[p] + nx[i]) * 0.5f, my = (ny[p] + ny[i]) * 0.5f;
        float d2 = mx * mx + my * my;
        if (d2 > 0.000001f) { float inv = 1.0f / d2; if (inv > 100) inv = 100; mx *= inv; my *= inv; }
        float x = xy[i * 2], y = xy[i * 2 + 1];
        v[i * 2] = { {x - mx * 0.5f, y - my * 0.5f}, col, {0, 0} };
        v[i * 2 + 1] = { {x + mx * 0.5f, y + my * 0.5f}, tr, {0, 0} };
    }
    for (int i = 2; i < n; ++i) { idx.push_back(0); idx.push_back((i - 1) * 2); idx.push_back(i * 2); }
    for (int i = 0; i < n; ++i) {
        int j = (i + 1) % n;
        int a = i * 2, b = j * 2;
        int q[6] = { a, b, b + 1, a, b + 1, a + 1 };
        idx.insert(idx.end(), q, q + 6);
    }
    SDL_RenderGeometry(r, nullptr, v.data(), (int)v.size(), idx.data(), (int)idx.size());
}

void gui_fill_rect(SDL_Renderer * r, float x, float y, float w, float h, uint32_t rgba) {
    if (w <= 0 || h <= 0) return;
    SDL_FColor c = gui_color(rgba);
    SDL_SetRenderDrawColorFloat(r, c.r, c.g, c.b, c.a);
    SDL_SetRenderDrawBlendMode(r, SDL_BLENDMODE_BLEND);
    SDL_FRect rc{ x, y, w, h };
    SDL_RenderFillRect(r, &rc);
}

void gui_rect(SDL_Renderer * r, float x, float y, float w, float h, float t, uint32_t rgba) {
    gui_fill_rect(r, x, y, w, t, rgba);
    gui_fill_rect(r, x, y + h - t, w, t, rgba);
    gui_fill_rect(r, x, y + t, t, h - 2 * t, rgba);
    gui_fill_rect(r, x + w - t, y + t, t, h - 2 * t, rgba);
}

static void arc(std::vector<float> & pts, float cx, float cy, float rad, float a0, float a1) {
    if (rad <= 0.5f) { pts.push_back(cx); pts.push_back(cy); return; }
    int seg = (int)std::ceil(rad * 0.6f) + 2;
    if (seg > 16) seg = 16;
    for (int i = 0; i <= seg; ++i) {
        float a = a0 + (a1 - a0) * i / seg;
        pts.push_back(cx + std::cos(a) * rad);
        pts.push_back(cy + std::sin(a) * rad);
    }
}

void gui_fill_round_rect4(SDL_Renderer * r, float x, float y, float w, float h,
                          float tl, float tr, float br, float bl, uint32_t rgba) {
    if (w <= 0 || h <= 0) return;
    float m = std::fmin(w, h) * 0.5f;
    tl = std::fmin(tl, m); tr = std::fmin(tr, m); br = std::fmin(br, m); bl = std::fmin(bl, m);
    if (tl <= 0 && tr <= 0 && br <= 0 && bl <= 0) { gui_fill_rect(r, x, y, w, h, rgba); return; }
    const float pi = 3.14159265f;
    std::vector<float> pts;
    arc(pts, x + tl, y + tl, tl, pi, pi * 1.5f);
    arc(pts, x + w - tr, y + tr, tr, pi * 1.5f, pi * 2.0f);
    arc(pts, x + w - br, y + h - br, br, 0, pi * 0.5f);
    arc(pts, x + bl, y + h - bl, bl, pi * 0.5f, pi);
    gui_fill_convex(r, pts.data(), (int)pts.size() / 2, rgba);
}
void gui_fill_round_rect(SDL_Renderer * r, float x, float y, float w, float h, float rad, uint32_t rgba) {
    gui_fill_round_rect4(r, x, y, w, h, rad, rad, rad, rad, rgba);
}

void gui_line(SDL_Renderer * r, float x0, float y0, float x1, float y1, float t, uint32_t rgba) {
    float dx = x1 - x0, dy = y1 - y0, l = std::sqrt(dx * dx + dy * dy);
    if (l <= 0.0001f) return;
    if (t < 1.0f) { // thin lines keep 1 px of geometry and fade instead
        uint32_t a = uint32_t((rgba & 255) * t);
        rgba = (rgba & 0xFFFFFF00u) | a; t = 1.0f;
    }
    float h = (t - 1.0f) * 0.5f + 0.5f;
    float nx = -dy / l * h, ny = dx / l * h;
    float q[8] = { x0 + nx, y0 + ny, x1 + nx, y1 + ny, x1 - nx, y1 - ny, x0 - nx, y0 - ny };
    gui_fill_convex(r, q, 4, rgba);
}

void gui_fill_triangle(SDL_Renderer * r, float x0, float y0, float x1, float y1, float x2, float y2, uint32_t rgba) {
    float p[6] = { x0, y0, x1, y1, x2, y2 };
    gui_fill_convex(r, p, 3, rgba);
}

void gui_fill_circle(SDL_Renderer * r, float cx, float cy, float rad, uint32_t rgba) {
    int seg = (int)std::fmax(12.0f, std::fmin(64.0f, rad * 1.5f));
    std::vector<float> p(seg * 2);
    for (int i = 0; i < seg; ++i) {
        float a = 6.2831853f * i / seg;
        p[i * 2] = cx + std::cos(a) * rad; p[i * 2 + 1] = cy + std::sin(a) * rad;
    }
    gui_fill_convex(r, p.data(), seg, rgba);
}

void gui_circle(SDL_Renderer * r, float cx, float cy, float rad, float t, uint32_t rgba) {
    int seg = (int)std::fmax(12.0f, std::fmin(64.0f, rad * 1.5f));
    for (int i = 0; i < seg; ++i) {
        float a0 = 6.2831853f * i / seg, a1 = 6.2831853f * (i + 1) / seg;
        gui_line(r, cx + std::cos(a0) * rad, cy + std::sin(a0) * rad,
                 cx + std::cos(a1) * rad, cy + std::sin(a1) * rad, t, rgba);
    }
}

void gui_clip(SDL_Renderer * r, float x, float y, float w, float h) {
    SDL_Rect rc{ (int)std::floor(x), (int)std::floor(y), (int)std::ceil(w), (int)std::ceil(h) };
    SDL_SetRenderClipRect(r, &rc);
}
void gui_no_clip(SDL_Renderer * r) { SDL_SetRenderClipRect(r, nullptr); }

// ---------------------------------------------------------- screenshots

bool gui_save_renderer_png(SDL_Renderer * r, const char * path) {
    SDL_Surface * s = SDL_RenderReadPixels(r, nullptr);
    if (!s) return false;
    bool ok = SDL_SavePNG(s, path);
    SDL_DestroySurface(s);
    if (ok) SDL_Log("screenshot: %s", path);
    return ok;
}

// ---------------------------------------------------------- arguments

static std::vector<std::string> g_args;

void gui_set_args(int argc, char ** argv) {
    g_args.assign(argv, argv + argc);
}
// "--name value" or "--name=value"
const char * gui_arg(const char * name, const char * fallback) {
    size_t n = strlen(name);
    for (size_t i = 0; i < g_args.size(); ++i) {
        if (g_args[i] == name && i + 1 < g_args.size()) return g_args[i + 1].c_str();
        if (g_args[i].size() > n && g_args[i].compare(0, n, name) == 0 && g_args[i][n] == '=')
            return g_args[i].c_str() + n + 1;
    }
    return fallback;
}
int gui_arg_int(const char * name, int fallback) {
    const char * v = gui_arg(name, nullptr);
    return v ? atoi(v) : fallback;
}
const char * gui_project_dir() { return GUI_PROJECT_DIR; }

// ---------------------------------------------------------- scripted input
// --script "F move X Y; F click X Y; F rclick X Y; F down X Y; F up X Y; F drag X0 Y0 X1 Y1;
//           F text STR; F key SCANCODE; F wheel DY; F shot PATH"
// Events are pushed through SDL's queue, so every library sees real input.

struct ScriptAction { int frame; std::string op; std::vector<std::string> args; };
static std::vector<ScriptAction> g_script;
static bool g_script_parsed = false;

static void parse_script() {
    g_script_parsed = true;
    const char * s = gui_arg("--script", nullptr);
    if (!s) return;
    std::string all(s), item;
    size_t pos = 0;
    while (pos <= all.size()) {
        size_t end = all.find(';', pos);
        if (end == std::string::npos) end = all.size();
        item = all.substr(pos, end - pos);
        pos = end + 1;
        std::vector<std::string> words;
        size_t i = 0;
        while (i < item.size()) {
            while (i < item.size() && item[i] == ' ') ++i;
            size_t j = i;
            while (j < item.size() && item[j] != ' ') ++j;
            if (j > i) words.push_back(item.substr(i, j - i));
            i = j;
        }
        if (words.size() < 2) continue;
        ScriptAction a{ atoi(words[0].c_str()), words[1], {} };
        a.args.assign(words.begin() + 2, words.end());
        g_script.push_back(a);
    }
}

static SDL_WindowID g_win_id = 0;
static void push_motion(float x, float y) {
    SDL_Event e{}; e.type = SDL_EVENT_MOUSE_MOTION; e.motion.windowID = g_win_id;
    e.motion.x = x; e.motion.y = y; SDL_PushEvent(&e);
}
static void push_button(float x, float y, bool down, Uint8 button = SDL_BUTTON_LEFT) {
    SDL_Event e{}; e.type = down ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
    e.button.windowID = g_win_id; e.button.button = button; e.button.down = down;
    e.button.clicks = 1; e.button.x = x; e.button.y = y; SDL_PushEvent(&e);
}

// Call once per frame before polling events.
void gui_script_step(SDL_Window * window, int frame) {
    if (!g_script_parsed) parse_script();
    g_win_id = SDL_GetWindowID(window);
    auto f = [](const ScriptAction & a, size_t i) { return i < a.args.size() ? (float)atof(a.args[i].c_str()) : 0.0f; };
    for (auto & a : g_script) {
        if (a.op == "click" && a.frame + 2 == frame) push_button(f(a, 0), f(a, 1), false);
        if (a.op == "rclick" && a.frame + 2 == frame) push_button(f(a, 0), f(a, 1), false, SDL_BUTTON_RIGHT);
        if (a.op == "drag") {
            int k = frame - a.frame;
            float x0 = f(a, 0), y0 = f(a, 1), x1 = f(a, 2), y1 = f(a, 3);
            if (k == 0) { push_motion(x0, y0); push_button(x0, y0, true); }
            else if (k >= 1 && k <= 8) push_motion(x0 + (x1 - x0) * k / 8, y0 + (y1 - y0) * k / 8);
            else if (k == 9) push_button(x1, y1, false);
        }
        if (a.frame != frame) continue;
        if (a.op == "move") push_motion(f(a, 0), f(a, 1));
        else if (a.op == "click" || a.op == "down") { push_motion(f(a, 0), f(a, 1)); push_button(f(a, 0), f(a, 1), true); }
        else if (a.op == "rclick") { push_motion(f(a, 0), f(a, 1)); push_button(f(a, 0), f(a, 1), true, SDL_BUTTON_RIGHT); }
        else if (a.op == "up") push_button(f(a, 0), f(a, 1), false);
        else if (a.op == "text" && !a.args.empty()) {
            SDL_Event e{}; e.type = SDL_EVENT_TEXT_INPUT; e.text.windowID = g_win_id;
            e.text.text = SDL_strdup(a.args[0].c_str());   // SDL frees event text it allocated; this leaks a few bytes
            SDL_PushEvent(&e);
        } else if (a.op == "key" && !a.args.empty()) {
            for (int down = 1; down >= 0; --down) {
                SDL_Event e{}; e.type = down ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP; e.key.windowID = g_win_id;
                e.key.scancode = (SDL_Scancode)atoi(a.args[0].c_str());
                e.key.key = SDL_GetKeyFromScancode(e.key.scancode, SDL_KMOD_NONE, false);
                e.key.down = down != 0; SDL_PushEvent(&e);
            }
        } else if (a.op == "wheel") {
            SDL_Event e{}; e.type = SDL_EVENT_MOUSE_WHEEL; e.wheel.windowID = g_win_id; e.wheel.y = f(a, 0);
            float mx, my; SDL_GetMouseState(&mx, &my); e.wheel.mouse_x = mx; e.wheel.mouse_y = my; SDL_PushEvent(&e);
        }
    }
}
// Screenshot path requested for this frame ("" if none); the last frame of the script is returned by gui_script_end.
const char * gui_script_shot(int frame) {
    if (!g_script_parsed) parse_script();
    for (auto & a : g_script)
        if (a.op == "shot" && a.frame == frame && !a.args.empty()) return a.args[0].c_str();
    return "";
}
int gui_script_end() {
    if (!g_script_parsed) parse_script();
    int last = -1;
    for (auto & a : g_script) last = a.frame + (a.op == "drag" ? 10 : 2) > last ? a.frame + (a.op == "drag" ? 10 : 2) : last;
    return last;
}
