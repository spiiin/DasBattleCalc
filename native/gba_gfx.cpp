// Graphics from the ROM as SDL textures for ImGui: the game's "A7" archive
// decoder (0x080051C4) and 4bpp tiles laid out as OAM pieces. Formats and
// addresses: research/notes.md, "Graphics".
#include "gba_mem.h"
#include "imgui.h"
#include <SDL3/SDL.h>
#include <map>
#include <tuple>
#include <vector>

namespace {

struct Gfx {
    SDL_Texture * tex = nullptr;
    float w = 0, h = 0, ox = 0, oy = 0;
};

std::vector<Gfx> g_gfx;
std::map<std::tuple<int, uint32_t, uint32_t, uint32_t, int>, int> g_cache;
uint32_t g_serial = 0;

// another ROM: the cached textures show the old one
void check_rom() {
    if (g_serial == gba_rom_serial()) return;
    for (auto & g : g_gfx) if (g.tex) SDL_DestroyTexture(g.tex);
    g_gfx.clear();
    g_cache.clear();
    g_serial = gba_rom_serial();
}

uint32_t be16(uint32_t a) { return gba_read8(a) << 8 | gba_read8(a + 1); }
uint32_t be32(uint32_t a) { return be16(a) << 16 | be16(a + 2); }

// entry `index` of an "A7" archive (0x08005318 / 0x080051C4)
bool a7_entry(uint32_t arc, int index, std::vector<uint8_t> & out) {
    if (gba_read8(arc) != 'A' || gba_read8(arc + 1) != '7') return false;
    if (index < 0 || (uint32_t)index >= be16(arc + 2)) return false;
    uint32_t d = arc + be32(arc + 4);           // the shared dictionary
    uint32_t kind = gba_read8(d), bits = gba_read8(d + 1);
    d += 2;
    uint32_t total = 0;
    if (kind <= 2) { total = be16(d); d += 2; }
    uint32_t e = arc + be32(arc + 8 + index * 4);
    if (kind == 3) { total = be16(e); e += 2; }
    else if (kind != 0) return false;
    uint32_t mask = 0xFFFF >> (bits + 1);
    out.clear();
    while (out.size() < total) {
        uint32_t c = gba_read8(e);
        if (c & 0x80) {
            for (uint32_t i = 0; i < (c & 0x7F) + 1; ++i) out.push_back((uint8_t)gba_read8(e + 1 + i));
            e += (c & 0x7F) + 2;
        } else {
            uint32_t n = ((c << 1) >> (8 - bits)) + 3;
            uint32_t at = ((c << 8) | gba_read8(e + 1)) & mask;
            for (uint32_t i = 0; i < n; ++i) out.push_back((uint8_t)gba_read8(d + at + i));
            e += 2;
        }
        if (out.size() > 0x10000) return false;
    }
    out.resize(total);
    return true;
}

uint32_t rgba(uint32_t pal, int c) {
    uint32_t v = gba_read16(pal + c * 2);
    uint32_t r = v & 31, g = (v >> 5) & 31, b = (v >> 10) & 31;
    r = r << 3 | r >> 2; g = g << 3 | g >> 2; b = b << 3 | b >> 2;
    return 0xFF000000u | b << 16 | g << 8 | r;   // ABGR8888 bytes R, G, B, A
}

int make(SDL_Renderer * r, const std::vector<uint32_t> & px, int w, int h, float ox, float oy) {
    SDL_Texture * t = SDL_CreateTexture(r, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STATIC, w, h);
    if (!t) return -1;
    SDL_UpdateTexture(t, nullptr, px.data(), w * 4);
    SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
    SDL_SetTextureScaleMode(t, SDL_SCALEMODE_NEAREST);
    g_gfx.push_back(Gfx{t, (float)w, (float)h, ox, oy});
    return (int)g_gfx.size() - 1;
}

// a 4bpp pixel of tile `t` in a block of tiles
int pixel4(const uint8_t * tiles, int t, int x, int y) {
    uint8_t b = tiles[t * 32 + y * 4 + x / 2];
    return x & 1 ? b >> 4 : b & 15;
}

const int SIZES[3][4][2] = {
    {{8, 8}, {16, 16}, {32, 32}, {64, 64}},
    {{16, 8}, {32, 8}, {32, 16}, {64, 32}},
    {{8, 16}, {8, 32}, {16, 32}, {32, 64}},
};

}  // namespace

int gba_gfx_icon(SDL_Renderer * r, uint32_t archive, int index, uint32_t palette) {
    check_rom();
    auto key = std::make_tuple(0, archive, (uint32_t)index, palette, 0);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;
    int handle = -1;
    std::vector<uint8_t> data;
    if (r && a7_entry(archive, index, data) && data.size() >= 128) {
        std::vector<uint32_t> px(16 * 16, 0);
        for (int y = 0; y < 16; ++y)
            for (int x = 0; x < 16; ++x) {
                int c = pixel4(data.data(), (y / 8) * 2 + x / 8, x % 8, y % 8);
                if (c) px[y * 16 + x] = rgba(palette, c);
            }
        handle = make(r, px, 16, 16, 0, 0);
    }
    g_cache[key] = handle;
    return handle;
}

int gba_gfx_sprite(SDL_Renderer * r, uint32_t tiles, uint32_t layout, uint32_t palette, bool flip) {
    check_rom();
    auto key = std::make_tuple(1, tiles, layout, palette, flip ? 1 : 0);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;
    int handle = -1;
    struct Piece { int x, y, w, h, tile; };
    std::vector<Piece> pieces;
    int n = (int)(gba_read8(layout) | gba_read8(layout + 1) << 8);
    int x0 = 0, y0 = 0, x1 = 0, y1 = 0, tile_count = 0;
    for (int k = 0; k < n && k < 64; ++k) {
        uint32_t a = layout + 2 + k * 6;
        int y = (int8_t)gba_read8(a);
        int shape = gba_read8(a + 1) >> 6, size = gba_read8(a + 3) >> 6;
        int x = (int)(gba_read8(a + 2) | (gba_read8(a + 3) & 1) << 8);
        if (x >= 256) x -= 512;
        if (shape > 2) continue;
        Piece p{x, y, SIZES[shape][size][0], SIZES[shape][size][1], (int)(gba_read8(a + 4) | gba_read8(a + 5) << 8)};
        if (pieces.empty()) { x0 = p.x; y0 = p.y; x1 = p.x + p.w; y1 = p.y + p.h; }
        x0 = SDL_min(x0, p.x); y0 = SDL_min(y0, p.y);
        x1 = SDL_max(x1, p.x + p.w); y1 = SDL_max(y1, p.y + p.h);
        tile_count = SDL_max(tile_count, p.tile + p.w * p.h / 64);
        pieces.push_back(p);
    }
    if (r && !pieces.empty() && x1 - x0 <= 128 && y1 - y0 <= 128) {
        std::vector<uint8_t> data(tile_count * 32);
        for (size_t i = 0; i < data.size(); ++i) data[i] = (uint8_t)gba_read8(tiles + (uint32_t)i);
        int w = x1 - x0, h = y1 - y0;
        std::vector<uint32_t> px(w * h, 0);
        for (auto & p : pieces)
            for (int y = 0; y < p.h; ++y)
                for (int x = 0; x < p.w; ++x) {
                    int c = pixel4(data.data(), p.tile + (y / 8) * (p.w / 8) + x / 8, x % 8, y % 8);
                    if (!c) continue;
                    int dx = p.x - x0 + x, dy = p.y - y0 + y;
                    if (flip) dx = w - 1 - dx;
                    px[dy * w + dx] = rgba(palette, c);
                }
        handle = make(r, px, w, h, flip ? (float)x1 : (float)-x0, (float)-y0);
    }
    g_cache[key] = handle;
    return handle;
}

namespace {

// NDS LZ77 (type 0x10) at `p` of `b`; the end in `end`
bool lz77(const std::vector<uint8_t> & b, size_t p, std::vector<uint8_t> & out, size_t & end) {
    if (p + 4 > b.size() || b[p] != 0x10) return false;
    size_t size = b[p + 1] | b[p + 2] << 8 | b[p + 3] << 16;
    out.clear();
    p += 4;
    while (out.size() < size) {
        if (p >= b.size()) return false;
        uint8_t flags = b[p++];
        for (int bit = 0; bit < 8 && out.size() < size; ++bit) {
            if (flags & (0x80 >> bit)) {
                if (p + 2 > b.size()) return false;
                int v = b[p] << 8 | b[p + 1];
                p += 2;
                size_t n = (v >> 12) + 3, d = (v & 0xFFF) + 1;
                if (d > out.size()) return false;
                for (size_t i = 0; i < n; ++i) out.push_back(out[out.size() - d]);
            } else {
                if (p >= b.size()) return false;
                out.push_back(b[p++]);
            }
        }
    }
    out.resize(size);
    end = p;
    return true;
}

std::vector<uint8_t> buf_bytes(int h) {
    std::vector<uint8_t> v(h >= 0 ? nds_buf_size(h) : 0);
    for (size_t i = 0; i < v.size(); ++i) v[i] = (uint8_t)nds_buf_read8(h, (int)i);
    return v;
}

}  // namespace

int nds_unit_sprite(SDL_Renderer * r, int set, int palette, int frame, bool flip) {
    check_rom();
    auto key = std::make_tuple(2, (uint32_t)set, (uint32_t)palette, (uint32_t)frame, flip ? 1 : 0);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;
    int handle = -1;
    auto cg = buf_bytes(nds_pak_file("char/rom/rom_idx/UnitCg.rom_idx", "char/rom/pak/UnitCg.pak", set));
    auto sst = buf_bytes(nds_pak_file("char/rom/rom_idx/UnitSst.rom_idx", "char/rom/pak/UnitSst.pak", set));
    // the frame: the chain of 4-aligned LZ77 blocks
    std::vector<uint8_t> tex;
    size_t p = 0, end = 0;
    bool found = false;
    for (int k = 0; k <= frame && p < cg.size(); ++k) {
        if (!lz77(cg, p, tex, end)) break;
        p = (end + 3) & ~size_t(3);
        found = k == frame;
    }
    // the palettes: u16 size, u16 2, LZ77 of 32-colour BGR555 palettes
    std::vector<uint8_t> pals;
    for (size_t q = 0; q + 8 <= sst.size() && pals.empty(); q += 2) {
        size_t s = sst[q] | sst[q + 1] << 8;
        if (s && s % 64 == 0 && sst[q + 2] == 2 && sst[q + 3] == 0 && sst[q + 4] == 0x10 &&
            (size_t)(sst[q + 5] | sst[q + 6] << 8 | sst[q + 7] << 16) == s) {
            if (!lz77(sst, q + 4, pals, end)) pals.clear();
        }
    }
    int w = tex.size() == 1536 ? 32 : (tex.size() == 3072 ? 64 : 0);
    size_t plain = 0;
    for (uint8_t v : tex) plain += (v >> 5) == 0 || (v >> 5) == 7;
    if (r && found && w && plain * 20 >= tex.size() * 19 && pals.size() >= size_t(palette + 1) * 64) {
        int h = (int)tex.size() / w;
        const uint8_t * pal = &pals[palette * 64];
        std::vector<uint32_t> px(w * h, 0);
        int bottom = 0;
        for (int y = 0; y < h; ++y)
            for (int x = 0; x < w; ++x) {
                uint8_t v = tex[y * w + x];
                if ((v >> 5) == 0) continue;
                uint32_t c = pal[(v & 31) * 2] | pal[(v & 31) * 2 + 1] << 8;
                uint32_t cr = c & 31, cg5 = (c >> 5) & 31, cb = (c >> 10) & 31;
                cr = cr << 3 | cr >> 2; cg5 = cg5 << 3 | cg5 >> 2; cb = cb << 3 | cb >> 2;
                uint32_t a = (v >> 5) * 255 / 7;
                px[y * w + (flip ? w - 1 - x : x)] = a << 24 | cb << 16 | cg5 << 8 | cr;
                bottom = SDL_max(bottom, y + 1);
            }
        handle = make(r, px, w, h, w * 0.5f, (float)bottom);
    }
    g_cache[key] = handle;
    return handle;
}

static const Gfx * gfx(int handle) {
    check_rom();
    return handle >= 0 && handle < (int)g_gfx.size() ? &g_gfx[handle] : nullptr;
}
float gba_gfx_width(int handle) { auto g = gfx(handle); return g ? g->w : 0; }
float gba_gfx_height(int handle) { auto g = gfx(handle); return g ? g->h : 0; }
float gba_gfx_origin_x(int handle) { auto g = gfx(handle); return g ? g->ox : 0; }
float gba_gfx_origin_y(int handle) { auto g = gfx(handle); return g ? g->oy : 0; }
void gba_gfx_draw(int handle, float x, float y, float w, float h, float alpha) {
    auto g = gfx(handle);
    if (!g || !g->tex) return;
    ImGui::GetWindowDrawList()->AddImage(ImTextureRef((ImTextureID)(intptr_t)g->tex), ImVec2(x, y),
                                         ImVec2(x + w, y + h), ImVec2(0, 0), ImVec2(1, 1),
                                         IM_COL32(255, 255, 255, (int)(alpha * 255)));
}
