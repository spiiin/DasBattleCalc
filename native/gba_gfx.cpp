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
uint32_t g_disc_serial = 0;

// another ROM or disc: the cached textures show the old one
void check_rom() {
    if (g_serial == gba_rom_serial() && g_disc_serial == psx_disc_serial()) return;
    for (auto & g : g_gfx) if (g.tex) SDL_DestroyTexture(g.tex);
    g_gfx.clear();
    g_cache.clear();
    g_serial = gba_rom_serial();
    g_disc_serial = psx_disc_serial();
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

int nds_item_icon(SDL_Renderer * r, int icon) {
    check_rom();
    auto key = std::make_tuple(3, (uint32_t)icon, 0u, 0u, 0);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;
    int handle = -1;
    char name[64];
    SDL_snprintf(name, sizeof name, "menu/icon_rom/itemicon%02d.pak", icon / 256);
    int pak = nds_file(name);
    SDL_snprintf(name, sizeof name, "menu/icon_rom/itemicon%02d.bhd", icon / 256);
    int bhd = nds_file(name);
    int plt = nds_file("menu/icon_rom/itemicon.plt");
    int i = icon % 256;
    if (r && icon >= 0 && nds_buf_size(pak) >= (i + 1) * 128 && nds_buf_size(bhd) >= 4 + i / 2 + 1 &&
        nds_buf_size(plt) >= 96) {
        int k = SDL_min((int)(nds_buf_read8(bhd, 4 + i / 2) >> (4 * (i & 1))) & 15, 2);
        std::vector<uint32_t> px(16 * 16, 0);
        for (int y = 0; y < 16; ++y)
            for (int x = 0; x < 16; ++x) {
                int c = (nds_buf_read8(pak, i * 128 + y * 8 + x / 2) >> (4 * (x & 1))) & 15;
                if (!c) continue;
                uint32_t v = nds_buf_read16(plt, k * 32 + c * 2);
                uint32_t cr = v & 31, cg = (v >> 5) & 31, cb = (v >> 10) & 31;
                cr = cr << 3 | cr >> 2; cg = cg << 3 | cg >> 2; cb = cb << 3 | cb >> 2;
                px[y * 16 + x] = 0xFF000000u | cb << 16 | cg << 8 | cr;
            }
        handle = make(r, px, 16, 16, 0, 0);
    }
    g_cache[key] = handle;
    return handle;
}

// ------------------------------------------------------------------ FFT (PSX)
// research/fft/notes.md, "Graphics": the formats as FFTPatcher's sprite
// editor and GaneshaDx read them.

namespace {

uint32_t bgr555(uint32_t v) {
    uint32_t r = v & 31, g = (v >> 5) & 31, b = (v >> 10) & 31;
    r = r << 3 | r >> 2; g = g << 3 | g >> 2; b = b << 3 | b >> 2;
    return 0xFF000000u | b << 16 | g << 8 | r;
}

// a battle sprite sheet (.SPR): 16 palettes, 256 x 288 4bpp (low nibble
// first), then 200 rows packed: nibbles high first, 0 + n a run of n
// zeros (n 0: the next nibble, 7: two, 8: three nibbles, low first)
bool spr_pixels(const std::vector<uint8_t> & b, std::vector<uint8_t> & px) {
    const size_t RAW = 36864;
    if (b.size() < 512 + RAW) return false;
    px.assign(256 * 488, 0);
    for (size_t i = 0; i < RAW; ++i) {
        px[i * 2] = b[512 + i] & 15;
        px[i * 2 + 1] = b[512 + i] >> 4;
    }
    std::vector<uint8_t> nib;
    for (size_t i = 512 + RAW; i < b.size(); ++i) {
        nib.push_back(b[i] >> 4);
        nib.push_back(b[i] & 15);
    }
    std::vector<uint8_t> out;
    size_t j = 0;
    auto at = [&](size_t k) -> uint32_t { return k < nib.size() ? nib[k] : 0; };
    while (j < nib.size() && out.size() < 200 * 256) {
        if (nib[j]) { out.push_back(nib[j]); ++j; continue; }
        uint32_t s = at(j + 1), l = s;
        if (s == 7) { l = at(j + 2) | at(j + 3) << 4; j += 2; }
        else if (s == 8) { l = at(j + 2) | at(j + 3) << 4 | at(j + 4) << 8; j += 3; }
        else if (s == 0) { l = at(j + 2); j += 1; }
        out.insert(out.end(), l, 0);
        j += 2;
    }
    for (size_t k = 0; k + 1 < out.size(); k += 2) std::swap(out[k], out[k + 1]);
    for (size_t k = 0; k < out.size() && RAW * 2 + k < px.size(); ++k) px[RAW * 2 + k] = out[k];
    return true;
}

const int SPR_SIZES[16][2] = {{8, 8}, {16, 8}, {16, 16}, {16, 24}, {24, 8}, {24, 16}, {24, 24}, {32, 8},
    {32, 16}, {32, 24}, {32, 32}, {32, 40}, {48, 16}, {40, 32}, {48, 48}, {56, 56}};
const char * SHP_NAMES[8] = {"TYPE1", "TYPE2", "CYOKO", "MON", "OTHER", "RUKA", "ARUTE", "KANZEN"};

uint32_t le32v(const std::vector<uint8_t> & s, size_t o) {
    return o + 4 <= s.size() ? s[o] | s[o + 1] << 8 | s[o + 2] << 16 | (uint32_t)s[o + 3] << 24 : 0;
}

// a frame of a SHP over a decoded SPR sheet (frames from the second half
// read from row lower_y: PSX 256, WotL 288); -1
int shp_frame(SDL_Renderer * r, const std::vector<uint8_t> & sprb, const std::vector<uint8_t> & s, int palette,
              int frame, bool flip, int lower_y) {
    std::vector<uint8_t> px;
    if (s.size() <= 0x410 || !spr_pixels(sprb, px)) return -1;
    int handle = -1;
    // the SHP: u32 the second table, u16 the first frame of the
    // sheet's lower half; frames from 0x40A by u32 offsets at 8
    uint32_t half = s[4] | s[5] << 8;
    std::vector<uint32_t> offs{0};
    for (size_t o = 0x0C; o + 4 <= 0x40A; o += 4) {
        uint32_t v = le32v(s, o);
        if (!v) break;
        offs.push_back(v);
    }
    if (frame >= 0 && frame < (int)offs.size()) {
        size_t at = offs[frame] + 0x40A;
        int yoff = frame >= (int)half ? lower_y : 0;
        int n = at + 2 <= s.size() ? s[at] + 1 : 0;
        struct Piece { int x, y, tx, ty, w, h; bool rx, ry; };
        std::vector<Piece> pieces;
        int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
        for (int k = 0; k < n && at + 6 + k * 4 <= s.size(); ++k) {
            const uint8_t * b = &s[at + 2 + k * 4];
            uint32_t f = b[2] | b[3] << 8;
            Piece p{(int8_t)b[0], (int8_t)b[1], int(f & 31) * 8, int((f >> 5) & 31) * 8 + yoff,
                    SPR_SIZES[(f >> 10) & 15][0], SPR_SIZES[(f >> 10) & 15][1], (f & 0x4000) != 0,
                    (f & 0x8000) != 0};
            if (pieces.empty()) { x0 = p.x; y0 = p.y; x1 = p.x + p.w; y1 = p.y + p.h; }
            x0 = SDL_min(x0, p.x); y0 = SDL_min(y0, p.y);
            x1 = SDL_max(x1, p.x + p.w); y1 = SDL_max(y1, p.y + p.h);
            pieces.push_back(p);
        }
        int w = x1 - x0, h = y1 - y0;
        if (!pieces.empty() && w <= 256 && h <= 256) {
            const uint8_t * pal = &sprb[(palette & 15) * 32];
            std::vector<uint32_t> img(w * h, 0);
            // the first piece is in front
            for (auto p = pieces.rbegin(); p != pieces.rend(); ++p)
                for (int y = 0; y < p->h; ++y)
                    for (int x = 0; x < p->w; ++x) {
                        int sx = p->tx + (p->rx ? p->w - 1 - x : x), sy = p->ty + (p->ry ? p->h - 1 - y : y);
                        if (sx >= 256 || sy >= 488) continue;
                        int c = px[sy * 256 + sx];
                        if (!c) continue;
                        int dx = p->x - x0 + x, dy = p->y - y0 + y;
                        if (flip) dx = w - 1 - dx;
                        img[dy * w + dx] = bgr555(pal[c * 2] | pal[c * 2 + 1] << 8);
                    }
            handle = make(r, img, w, h, flip ? (float)x1 : (float)-x0, (float)-y0);
        }
    }
    return handle;
}

}  // namespace

int psx_unit_sprite(SDL_Renderer * r, int sprite, int palette, int frame, bool flip) {
    check_rom();
    auto key = std::make_tuple(4, (uint32_t)sprite, (uint32_t)palette, (uint32_t)frame, flip ? 1 : 0);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;
    int handle = -1;
    // BATTLE.BIN: the sprites' sectors and sizes (8 B), their kinds (4 B:
    // the SHP, the SEQ, flying, height)
    auto battle = psx_buf(psx_disc_file("BATTLE.BIN"));
    if (r && battle && battle->size() > 0x2E1CC && sprite > 0 && sprite < 159) {
        int lba = (int)le32v(*battle, 0x2DCD4 + sprite * 8), size = (int)le32v(*battle, 0x2DCD8 + sprite * 8);
        int kind = (*battle)[0x2D748 + sprite * 4];
        auto spr = psx_buf(psx_disc_read(lba, size));
        std::string shp_name = std::string("BATTLE/") + SHP_NAMES[kind & 7] + ".SHP";
        auto shp = psx_buf(psx_disc_file(shp_name.c_str()));
        if (spr && shp && kind < 8) handle = shp_frame(r, *spr, *shp, palette, frame, flip, 256);
    }
    g_cache[key] = handle;
    return handle;
}

int psx_item_icon(SDL_Renderer * r, int item) {
    check_rom();
    auto key = std::make_tuple(5, (uint32_t)item, 0u, 0u, 0);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;
    int handle = -1;
    // EVENT/ITEM.BIN: 256 x 256 4bpp, 16 palettes after; 15 icons a row
    // from the third; the item table (12 B at 0x80062EB8): +0 the palette,
    // +1 the icon
    auto icons = psx_buf(psx_disc_file("EVENT/ITEM.BIN"));
    if (r && icons && icons->size() >= 33280 && item > 0 && item < 0xFE && gba_state_is_psx()) {
        uint32_t e = 0x80062EB8u + item * 12;
        int pal = gba_read8(e) & 15, g = gba_read8(e + 1);
        int ox = (g % 15) * 16, oy = 32 + (g / 15) * 16;
        if (g > 0 && oy + 16 <= 208) {
            const auto & b = *icons;
            const uint8_t * pp = &b[32768 + pal * 32];
            std::vector<uint32_t> img(16 * 16, 0);
            for (int y = 0; y < 16; ++y)
                for (int x = 0; x < 16; ++x) {
                    int X = ox + x;
                    int c = (b[(oy + y) * 128 + X / 2] >> (4 * (X & 1))) & 15;
                    if (c) img[y * 16 + x] = bgr555(pp[c * 2] | pp[c * 2 + 1] << 8);
                }
            handle = make(r, img, 16, 16, 0, 0);
        }
    }
    g_cache[key] = handle;
    return handle;
}

int psx_map_texture(SDL_Renderer * r, int tex_buf, int pal_buf, int pal_off, int page, int palette) {
    check_rom();
    auto key = std::make_tuple(6, (uint32_t)tex_buf, (uint32_t)pal_off, (uint32_t)(pal_buf << 8 | page), palette);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;
    int handle = -1;
    // the map's texture: 256 x 1024 4bpp (low nibble first), page = 256
    // rows; the mesh's 16 palettes (BGR555, 0: transparent)
    auto tex = psx_buf(tex_buf);
    auto pal = psx_buf(pal_buf);
    if (r && tex && pal && tex->size() >= 131072 && page >= 0 && page < 4 && palette >= 0 && palette < 16 &&
        pal_off >= 0 && (size_t)pal_off + 512 <= pal->size()) {
        const uint8_t * pp = &(*pal)[pal_off + palette * 32];
        std::vector<uint32_t> img(256 * 256, 0);
        for (int y = 0; y < 256; ++y)
            for (int x = 0; x < 256; ++x) {
                int c = ((*tex)[(page * 256 + y) * 128 + x / 2] >> (4 * (x & 1))) & 15;
                uint32_t v = pp[c * 2] | pp[c * 2 + 1] << 8;
                if (v) img[y * 256 + x] = bgr555(v);
            }
        handle = make(r, img, 256, 256, 0, 0);
    }
    g_cache[key] = handle;
    return handle;
}

// ------------------------------------------------------------------ FFT: WotL (PSP)
// research/fftwotl/graphics.md: BOOT.BIN's tables are in RAM (offset +
// 0x08803FAC), the files in the ISO's fftpack.bin.

namespace {

const uint32_t BOOT_RAM = 0x08803FACu;

// the sheet's fftpack file and size: BOOT.BIN 0x32481C + 8 s (u32 a PSX
// "sector", u32 size); file i's sector at 0x252F34 + 4 (i - 3)
bool psp_sheet_file(int sheet, int & file, int & size) {
    if (!gba_state_is_psp() || sheet <= 0 || sheet >= 170) return false;
    uint32_t sector = gba_read32(BOOT_RAM + 0x32481C + sheet * 8);
    size = (int)gba_read32(BOOT_RAM + 0x324820 + sheet * 8);
    int n = psp_pack_count();
    for (int i = 3; i <= n; ++i)
        if (gba_read32(BOOT_RAM + 0x252F34 + (i - 3) * 4) == sector) {
            file = i;
            return size > 0;
        }
    return false;
}

}  // namespace

int psp_sprite_type(int sheet) {
    if (!gba_state_is_psp() || sheet <= 0 || sheet >= 170) return -1;
    return (int)gba_read8(BOOT_RAM + 0x324284 + sheet * 4);
}

int psp_unit_sprite(SDL_Renderer * r, int sheet, int palette, int frame, bool flip) {
    check_rom();
    auto key = std::make_tuple(7, (uint32_t)sheet, (uint32_t)palette, (uint32_t)frame, flip ? 1 : 0);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;
    int handle = -1, file = 0, size = 0, kind = psp_sprite_type(sheet);
    // the SHP files: fftpack 51.. (TYPE1, TYPE2, CYOKO, MON, OTHER, ARUTE,
    // KANZEN); RUKA uses MON's
    static const int SHP_FILE[8] = {51, 52, 53, 54, 55, 54, 56, 57};
    if (r && kind >= 0 && kind < 8 && psp_sheet_file(sheet, file, size)) {
        auto spr = psx_buf(psp_pack_file(file));
        auto shp = psx_buf(psp_pack_file(SHP_FILE[kind]));
        if (spr && shp) {
            std::vector<uint8_t> sheet_bytes(spr->begin(), spr->begin() + SDL_min((size_t)size, spr->size()));
            handle = shp_frame(r, sheet_bytes, *shp, palette, frame, flip, 288);
        }
    }
    g_cache[key] = handle;
    return handle;
}

int psp_item_icon(SDL_Renderer * r, int item) {
    check_rom();
    auto key = std::make_tuple(8, (uint32_t)item, 0u, 0u, 0);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;
    int handle = -1;
    // 256 x 256 4bpp, then 33 palettes at 0x8000; 15 icons a row from y 32;
    // the item tables (12 B): 0..255 at 0x08B29288, 256..315 at 0x08A5ADAC
    auto icons = psx_buf(psp_pack_file(33));
    if (r && icons && icons->size() >= 0x8000 + 64 * 32 && item >= 0 && item < 316 && item != 255 &&
        gba_state_is_psp()) {
        uint32_t e = item < 256 ? 0x08B29288u + item * 12 : 0x08A5ADACu + (item - 256) * 12;
        int pal = gba_read8(e) & 63, g = gba_read8(e + 1);
        int ox = (g % 15) * 16, oy = 32 + (g / 15) * 16;
        if (g > 0 && oy + 16 <= 256) {
            const auto & b = *icons;
            const uint8_t * pp = &b[0x8000 + pal * 32];
            std::vector<uint32_t> img(16 * 16, 0);
            for (int y = 0; y < 16; ++y)
                for (int x = 0; x < 16; ++x) {
                    int X = ox + x;
                    int c = (b[(oy + y) * 128 + X / 2] >> (4 * (X & 1))) & 15;
                    if (c) img[y * 16 + x] = bgr555(pp[c * 2] | pp[c * 2 + 1] << 8);
                }
            handle = make(r, img, 16, 16, 0, 0);
        }
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
void gba_gfx_draw_quad(int handle, float x0, float y0, float x1, float y1, float x2, float y2, float x3, float y3,
                       float u0, float v0, float u1, float v1, float u2, float v2, float u3, float v3, float shade) {
    auto g = gfx(handle);
    if (!g || !g->tex) return;
    int k = (int)(SDL_clamp(shade, 0.0f, 1.0f) * 255);
    ImGui::GetWindowDrawList()->AddImageQuad(ImTextureRef((ImTextureID)(intptr_t)g->tex), ImVec2(x0, y0),
                                             ImVec2(x1, y1), ImVec2(x2, y2), ImVec2(x3, y3), ImVec2(u0, v0),
                                             ImVec2(u1, v1), ImVec2(u2, v2), ImVec2(u3, v3), IM_COL32(k, k, k, 255));
}
void gba_gfx_draw(int handle, float x, float y, float w, float h, float alpha) {
    auto g = gfx(handle);
    if (!g || !g->tex) return;
    ImGui::GetWindowDrawList()->AddImage(ImTextureRef((ImTextureID)(intptr_t)g->tex), ImVec2(x, y),
                                         ImVec2(x + w, y + h), ImVec2(0, 0), ImVec2(1, 1),
                                         IM_COL32(255, 255, 255, (int)(alpha * 255)));
}
