// PSX (BizHawk's Nymashock core) support for gba_mem: the 2 MB main RAM of
// the waterbox image (it lies there in one piece; found by Final Fantasy
// Tactics (USA)'s code at 0x8001E000 = SCUS_942.21 + 0xE000, which no
// other page of the image holds), and the game's disc for the graphics.
// research/fft/notes.md.
#include "gba_mem.h"
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>

namespace {

const uint8_t FFT_CODE[32] = {
    0xD8, 0xFF, 0xBD, 0x27, 0x14, 0x00, 0xB1, 0xAF, 0x03, 0x80, 0x11, 0x3C, 0xFC, 0x06, 0x31, 0x26,
    0x24, 0x00, 0xBF, 0xAF, 0x20, 0x00, 0xB4, 0xAF, 0x1C, 0x00, 0xB3, 0xAF, 0x18, 0x00, 0xB2, 0xAF,
};
const size_t FFT_CODE_RAM = 0x1E000;

}  // namespace

bool psx_state_ram(const std::vector<uint8_t> & core, std::vector<uint8_t> & ram, size_t & base) {
    if (core.size() < PSX_RAM_SIZE) return false;
    for (size_t p = FFT_CODE_RAM; p + sizeof(FFT_CODE) <= core.size(); ++p) {
        if (core[p] != FFT_CODE[0] || memcmp(core.data() + p, FFT_CODE, sizeof(FFT_CODE)) != 0) continue;
        base = p - FFT_CODE_RAM;
        if (base + PSX_RAM_SIZE > core.size()) return false;
        ram.assign(core.begin() + base, core.begin() + base + PSX_RAM_SIZE);
        return true;
    }
    return false;
}

// ------------------------------------------------------------------ the disc
// The disc image (MODE2/2352, one data track, ISO9660): a .cue (its FILE)
// or the .bin itself. Files are read whole into buffers kept until another
// disc is opened; handles as nds_file's.

namespace {

const int SECTOR = 2352;

struct DiscState {
    std::string bin;
    uint32_t serial = 0;
    std::vector<std::vector<uint8_t>> bufs;
    std::map<std::string, int> by_key;
    std::string error;
};
DiscState g_disc;

bool read_sectors(uint32_t lba, uint32_t size, std::vector<uint8_t> & out) {
    out.clear();
    FILE * f = fopen(g_disc.bin.c_str(), "rb");
    if (!f) return false;
    std::vector<uint8_t> raw(SECTOR);
    bool ok = true;
    while (out.size() < size) {
#ifdef _WIN32
        if (_fseeki64(f, (long long)lba * SECTOR, SEEK_SET) != 0) { ok = false; break; }
#else
        if (fseeko(f, (off_t)lba * SECTOR, SEEK_SET) != 0) { ok = false; break; }
#endif
        if (fread(raw.data(), 1, SECTOR, f) != SECTOR) { ok = false; break; }
        size_t n = std::min<size_t>(2048, size - out.size());
        out.insert(out.end(), raw.begin() + 24, raw.begin() + 24 + n);   // mode 2 form 1
        ++lba;
    }
    fclose(f);
    return ok;
}

uint32_t le32(const uint8_t * p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

// an ISO9660 path ("BATTLE/TYPE1.SHP") -> its sector and size
bool iso_find(const std::string & path, uint32_t & lba, uint32_t & size) {
    std::vector<uint8_t> pvd;
    if (!read_sectors(16, 2048, pvd) || memcmp(&pvd[1], "CD001", 5) != 0) return false;
    lba = le32(&pvd[156 + 2]);
    size = le32(&pvd[156 + 10]);
    size_t pos = 0;
    while (pos <= path.size()) {
        size_t slash = path.find('/', pos);
        std::string part = path.substr(pos, slash == std::string::npos ? std::string::npos : slash - pos);
        std::vector<uint8_t> dir;
        if (!read_sectors(lba, size, dir)) return false;
        bool found = false;
        for (size_t p = 0; p < dir.size();) {
            uint8_t n = dir[p];
            if (n == 0) { p = (p / 2048 + 1) * 2048; continue; }
            std::string name((const char *)&dir[p + 33], dir[p + 32]);
            name = name.substr(0, name.find(';'));
            if (name == part) {
                lba = le32(&dir[p + 2]);
                size = le32(&dir[p + 10]);
                found = true;
                break;
            }
            p += n;
        }
        if (!found) return false;
        if (slash == std::string::npos) break;
        pos = slash + 1;
    }
    return true;
}

int keep(const std::string & key, bool ok, std::vector<uint8_t> & data) {
    int h = ok ? int(g_disc.bufs.size()) : -1;
    if (ok) g_disc.bufs.push_back(std::move(data));
    g_disc.by_key[key] = h;
    return h;
}

const std::vector<uint8_t> * disc_buf(int h) {
    return h >= 0 && h < int(g_disc.bufs.size()) ? &g_disc.bufs[h] : nullptr;
}

}  // namespace

const char * psx_open_disc(const char * path) {
    std::string p = path ? path : "";
    std::string bin = p;
    g_disc.error.clear();
    if (p.size() > 4 && (p.substr(p.size() - 4) == ".cue" || p.substr(p.size() - 4) == ".CUE")) {
        FILE * f = fopen(p.c_str(), "rb");
        if (!f) return (g_disc.error = "can not read the .cue").c_str();
        std::string text;
        char chunk[4096];
        size_t n;
        while ((n = fread(chunk, 1, sizeof chunk, f)) > 0) text.append(chunk, n);
        fclose(f);
        size_t a = text.find("FILE \"");
        size_t b = a == std::string::npos ? a : text.find('"', a + 6);
        if (b == std::string::npos) return (g_disc.error = ".cue: no FILE").c_str();
        size_t slash = p.find_last_of("/\\");
        bin = (slash == std::string::npos ? "" : p.substr(0, slash + 1)) + text.substr(a + 6, b - a - 6);
    }
    DiscState next;
    next.bin = bin;
    next.serial = g_disc.serial + 1;
    std::swap(g_disc, next);
    std::vector<uint8_t> pvd;
    if (!read_sectors(16, 2048, pvd) || memcmp(&pvd[1], "CD001", 5) != 0) {
        g_disc.bin.clear();
        return (g_disc.error = "not a MODE2/2352 disc image").c_str();
    }
    return "";
}
bool psx_has_disc() { return !g_disc.bin.empty(); }
uint32_t psx_disc_serial() { return g_disc.serial; }

int psx_disc_file(const char * path) {
    std::string key = std::string("f:") + path;
    auto it = g_disc.by_key.find(key);
    if (it != g_disc.by_key.end()) return it->second;
    std::vector<uint8_t> data;
    uint32_t lba = 0, size = 0;
    bool ok = psx_has_disc() && iso_find(path, lba, size) && read_sectors(lba, size, data);
    return keep(key, ok, data);
}

int psx_disc_read(int lba, int size) {
    std::string key = "s:" + std::to_string(lba) + ":" + std::to_string(size);
    auto it = g_disc.by_key.find(key);
    if (it != g_disc.by_key.end()) return it->second;
    std::vector<uint8_t> data;
    bool ok = psx_has_disc() && lba > 0 && size > 0 && size < 0x1000000 && read_sectors(lba, size, data);
    return keep(key, ok, data);
}

int psx_buf_size(int h) {
    auto b = disc_buf(h);
    return b ? int(b->size()) : 0;
}
uint32_t psx_buf_read8(int h, int off) {
    auto b = disc_buf(h);
    return b && off >= 0 && size_t(off) < b->size() ? (*b)[off] : 0;
}
uint32_t psx_buf_read16(int h, int off) {
    return psx_buf_read8(h, off) | psx_buf_read8(h, off + 1) << 8;
}
uint32_t psx_buf_read32(int h, int off) {
    return psx_buf_read16(h, off) | psx_buf_read16(h, off + 2) << 16;
}
const std::vector<uint8_t> * psx_buf(int h) { return disc_buf(h); }

// the battle's map: the MAPnnn.GNS the game holds in RAM (its first 64
// bytes), -1 none
int psx_find_map() {
    if (!gba_state_is_psx() || !psx_has_disc()) return -1;
    std::vector<uint8_t> ram(PSX_RAM_SIZE);
    for (uint32_t a = 0; a < PSX_RAM_SIZE; a += 4) {
        uint32_t v = gba_read32(0x80000000u + a);
        memcpy(&ram[a], &v, 4);
    }
    for (int m = 0; m < 128; ++m) {
        char name[32];
        snprintf(name, sizeof name, "MAP/MAP%03d.GNS", m);
        auto g = disc_buf(psx_disc_file(name));
        if (!g || g->size() < 64) continue;
        for (size_t p = 0; p + 64 <= ram.size(); p += 4)
            if (memcmp(&ram[p], g->data(), 64) == 0) return m;
    }
    return -1;
}
