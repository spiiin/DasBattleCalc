// GBA memory images for scripts: the RAM of a BizHawk savestate and a ROM
// (an NDS state / ROM too: nds_mem.cpp).
// BizHawk .State = zip with Core.bin.zst; for the mGBA core Core.bin is a
// 4-byte size + mGBA's GBASerializedState (magic 0x010000xx), where IWRAM
// is at +0x19000 (32 KB) and EWRAM at +0x21000 (256 KB).
#include "gba_mem.h"
#include <cstdio>
#include <algorithm>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif
#include <cstring>
#include <string>
#include <vector>

#define MINIZ_NO_ZLIB_COMPATIBLE_NAMES
#include "miniz.h"
#include "zstd.h"

static std::vector<uint8_t> g_ewram, g_iwram, g_rom, g_frame;
static uint32_t g_rom_serial = 0;
static bool g_state_nds = false;                  // the state is melonDS (NDS)
static bool g_state_psx = false;                  // the state is Nymashock (PSX): 2 MB main RAM
// for gba_save_state: the loaded file, its core image and the RAM to write
static std::vector<uint8_t> g_zip, g_core, g_edit_ewram, g_edit_iwram;
static size_t g_core_base = 0;
static uint32_t g_state_serial = 0;
static std::string g_error;

static bool read_file(const char * path, std::vector<uint8_t> & out) {
    FILE * f = fopen(path, "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    out.resize(n > 0 ? size_t(n) : 0);
    bool ok = n <= 0 || fread(out.data(), 1, out.size(), f) == out.size();
    fclose(f);
    return ok;
}

// Extracts the first entry that ends with suffix ("" - the largest one).
static bool unzip_entry(const std::vector<uint8_t> & zip, const char * suffix, std::vector<uint8_t> & out) {
    mz_zip_archive za;
    memset(&za, 0, sizeof(za));
    if (!mz_zip_reader_init_mem(&za, zip.data(), zip.size(), 0)) return false;
    int pick = -1;
    mz_uint64 best = 0;
    for (mz_uint i = 0; i < mz_zip_reader_get_num_files(&za); ++i) {
        mz_zip_archive_file_stat st;
        if (!mz_zip_reader_file_stat(&za, i, &st) || st.m_is_directory) continue;
        std::string name = st.m_filename;
        size_t n = strlen(suffix);
        if (n ? (name.size() >= n && name.compare(name.size() - n, n, suffix) == 0) : st.m_uncomp_size > best) {
            pick = int(i);
            best = st.m_uncomp_size;
            if (n) break;
        }
    }
    bool ok = false;
    if (pick >= 0) {
        size_t size = 0;
        void * p = mz_zip_reader_extract_to_heap(&za, mz_uint(pick), &size, 0);
        if (p) {
            out.assign((uint8_t *)p, (uint8_t *)p + size);
            mz_free(p);
            ok = true;
        }
    }
    mz_zip_reader_end(&za);
    return ok;
}

static bool unzstd(const std::vector<uint8_t> & in, std::vector<uint8_t> & out) {
    unsigned long long size = ZSTD_getFrameContentSize(in.data(), in.size());
    if (size == ZSTD_CONTENTSIZE_ERROR) return false;
    if (size != ZSTD_CONTENTSIZE_UNKNOWN) {
        out.resize(size_t(size));
        size_t r = ZSTD_decompress(out.data(), out.size(), in.data(), in.size());
        return !ZSTD_isError(r) && r == out.size();
    }
    // streaming: BizHawk writes frames without the content size
    ZSTD_DStream * ds = ZSTD_createDStream();
    ZSTD_initDStream(ds);
    ZSTD_inBuffer ib = { in.data(), in.size(), 0 };
    std::vector<uint8_t> chunk(ZSTD_DStreamOutSize());
    out.clear();
    bool ok = true;
    while (ib.pos < ib.size) {
        ZSTD_outBuffer ob = { chunk.data(), chunk.size(), 0 };
        size_t r = ZSTD_decompressStream(ds, &ob, &ib);
        if (ZSTD_isError(r)) { ok = false; break; }
        out.insert(out.end(), chunk.data(), chunk.data() + ob.pos);
        if (r == 0 && ib.pos == ib.size) break;
    }
    ZSTD_freeDStream(ds);
    return ok;
}

static uint32_t rd32(const std::vector<uint8_t> & v, size_t o) {
    return v[o] | v[o + 1] << 8 | v[o + 2] << 16 | uint32_t(v[o + 3]) << 24;
}

const char * gba_load_state(const char * path) {
    std::vector<uint8_t> zip, zst, core;
    g_error.clear();
    if (!read_file(path, zip)) return (g_error = "can not read file").c_str();
    if (!unzip_entry(zip, "Core.bin.zst", zst)) {
        if (!unzip_entry(zip, "Core.bin", core)) return (g_error = "not a BizHawk state (no Core.bin)").c_str();
    } else if (!unzstd(zst, core)) {
        return (g_error = "zstd: can not decompress Core.bin").c_str();
    }
    // melonDS (NDS) runs in BizHawk's waterbox: the core is the host's state
    static const char wbx[] = "ActivatedWaterboxHost";
    if (core.size() > sizeof(wbx) && memcmp(core.data(), wbx, sizeof(wbx) - 1) == 0) {
        std::vector<uint8_t> ram;
        size_t psx_base = 0;
        // Nymashock (PSX) or melonDS (NDS)
        bool psx = psx_state_ram(core, ram, psx_base);
        if (!psx && !nds_state_ram(core, ram, g_error)) return g_error.c_str();
        g_error.clear();
        g_ewram.swap(ram);
        g_iwram.clear();
        g_zip.swap(zip);
        g_core.swap(core);
        g_core_base = psx_base;
        g_state_nds = !psx;
        g_state_psx = psx;
        if (!unzip_entry(g_zip, "Framebuffer.bmp", g_frame)) g_frame.clear();
        g_state_serial++;
        return "";
    }
    // the mGBA state starts at 0 or after BizHawk's 4-byte size
    size_t base = SIZE_MAX;
    for (size_t o : { size_t(0), size_t(4) })
        if (core.size() >= o + 0x61000 && (rd32(core, o) & 0xffffff00u) == 0x01000000u) base = o;
    if (base == SIZE_MAX) return (g_error = "not an mGBA (GBA) state").c_str();
    g_state_nds = false;
    g_state_psx = false;
    g_iwram.assign(core.begin() + base + 0x19000, core.begin() + base + 0x21000);
    g_ewram.assign(core.begin() + base + 0x21000, core.begin() + base + 0x61000);
    g_zip.swap(zip);
    g_core.swap(core);
    g_core_base = base;
    if (!unzip_entry(g_zip, "Framebuffer.bmp", g_frame)) g_frame.clear();
    g_state_serial++;
    return "";
}

const char * gba_load_rom(const char * path) {
    std::vector<uint8_t> file;
    g_error.clear();
    if (!read_file(path, file)) return (g_error = "can not read file").c_str();
    if (file.size() > 4 && file[0] == 'P' && file[1] == 'K') {
        if (!unzip_entry(file, ".gba", g_rom) && !unzip_entry(file, "", g_rom))
            return (g_error = "zip: no ROM inside").c_str();
    } else {
        g_rom.swap(file);
    }
    if (g_rom.size() < 0xC0) return (g_error = "too small for a GBA ROM").c_str();
    g_rom_serial++;
    return "";
}
uint32_t gba_rom_serial() { return g_rom_serial; }
const std::vector<uint8_t> & gba_rom_bytes() { return g_rom; }
bool gba_state_is_nds() { return g_state_nds; }
bool gba_state_is_psx() { return g_state_psx; }

bool gba_has_state() { return !g_ewram.empty(); }
bool gba_has_rom() { return !g_rom.empty(); }

// Game code at 0x080000AC (4 chars), e.g. "AFXE"; an NDS ROM: at 0x0C ("A6FE").
const char * gba_rom_code() {
    static char code[5] = {};
    if (g_rom.size() < 0xB0) return "";
    memcpy(code, &g_rom[nds_is_rom(g_rom) ? 0x0C : 0xAC], 4);
    return code;
}

static const uint8_t * at(uint32_t addr, uint32_t n) {
    uint32_t region = addr >> 24, off = addr & 0xffffff;
    if (g_state_psx) {
        // 2 MB main RAM at 0x00000000 / 0x80000000 / 0xA0000000, mirrored
        if (region != 0x00 && region != 0x80 && region != 0xA0) return nullptr;
        off = addr & 0x1fffff;
        return size_t(off) + n <= g_ewram.size() ? g_ewram.data() + off : nullptr;
    }
    if (g_state_nds && region == 2) off &= 0x3fffff;  // 4 MB main RAM, mirrored
    const std::vector<uint8_t> * v = region == 2 ? &g_ewram : region == 3 ? &g_iwram : region == 8 ? &g_rom : nullptr;
    if (!v || size_t(off) + n > v->size()) return nullptr;
    return v->data() + off;
}

uint32_t gba_read8(uint32_t addr) {
    const uint8_t * p = at(addr, 1);
    return p ? p[0] : 0;
}
uint32_t gba_read16(uint32_t addr) {
    const uint8_t * p = at(addr, 2);
    return p ? p[0] | p[1] << 8 : 0;
}
uint32_t gba_read32(uint32_t addr) {
    const uint8_t * p = at(addr, 4);
    return p ? p[0] | p[1] << 8 | p[2] << 16 | uint32_t(p[3]) << 24 : 0;
}

const uint8_t * gba_state_frame(size_t & size) {
    size = g_frame.size();
    return g_frame.empty() ? nullptr : g_frame.data();
}
uint32_t gba_state_serial() { return g_state_serial; }

// ------------------------------------------------------------ writing

void gba_edit_begin() {
    g_edit_ewram = g_ewram;
    g_edit_iwram = g_iwram;
}

static uint8_t * edit_at(uint32_t addr, uint32_t n) {
    uint32_t region = addr >> 24, off = addr & 0xffffff;
    if (g_state_psx) {
        if (region != 0x00 && region != 0x80 && region != 0xA0) return nullptr;
        off = addr & 0x1fffff;
        return size_t(off) + n <= g_edit_ewram.size() ? g_edit_ewram.data() + off : nullptr;
    }
    std::vector<uint8_t> * v = region == 2 ? &g_edit_ewram : region == 3 ? &g_edit_iwram : nullptr;
    if (!v || size_t(off) + n > v->size()) return nullptr;
    return v->data() + off;
}

void gba_edit8(uint32_t addr, uint32_t value) {
    if (uint8_t * p = edit_at(addr, 1)) p[0] = uint8_t(value);
}
void gba_edit16(uint32_t addr, uint32_t value) {
    if (uint8_t * p = edit_at(addr, 2)) { p[0] = uint8_t(value); p[1] = uint8_t(value >> 8); }
}
void gba_edit32(uint32_t addr, uint32_t value) {
    if (uint8_t * p = edit_at(addr, 4))
        for (int i = 0; i < 4; ++i) p[i] = uint8_t(value >> (8 * i));
}

// A zstd frame made of raw (stored) blocks: valid for any zstd decoder,
// so no compressor is needed. Header: magic, descriptor 0xE0 (8-byte
// content size, single segment), then blocks of up to 128 KB.
static std::vector<uint8_t> zstd_store(const std::vector<uint8_t> & data) {
    std::vector<uint8_t> out = { 0x28, 0xB5, 0x2F, 0xFD, 0xE0 };
    for (int i = 0; i < 8; ++i) out.push_back(uint8_t(uint64_t(data.size()) >> (8 * i)));
    size_t pos = 0;
    do {
        size_t n = std::min<size_t>(data.size() - pos, 128 * 1024);
        uint32_t last = pos + n == data.size() ? 1 : 0;
        uint32_t header = last | (0u << 1) | uint32_t(n) << 3;    // block type 0: raw
        out.push_back(uint8_t(header));
        out.push_back(uint8_t(header >> 8));
        out.push_back(uint8_t(header >> 16));
        out.insert(out.end(), data.begin() + pos, data.begin() + pos + n);
        pos += n;
    } while (pos < data.size());
    return out;
}

// Writes the loaded state with the edited RAM to path: every entry of the
// original zip is copied, Core.bin(.zst) gets the new core image.
const char * gba_save_state(const char * path) {
    g_error.clear();
    std::vector<uint8_t> core = g_core;
    if (g_state_psx) {
        // Nymashock: the main RAM lies in the image in one piece
        if (g_core.empty() || g_edit_ewram.size() != PSX_RAM_SIZE || g_core_base + PSX_RAM_SIZE > core.size())
            return (g_error = "no state loaded or no edit begun").c_str();
        memcpy(core.data() + g_core_base, g_edit_ewram.data(), PSX_RAM_SIZE);
    } else if (g_state_nds) {
        // melonDS: the main RAM's saved pages of the waterbox image
        if (g_core.empty() || g_edit_ewram.size() != 0x400000)
            return (g_error = "no state loaded or no edit begun").c_str();
        if (!nds_state_write_ram(core, g_edit_ewram, g_ewram, g_error)) return g_error.c_str();
    } else {
        if (g_core.empty() || g_edit_ewram.size() != 0x40000 || g_edit_iwram.size() != 0x8000)
            return (g_error = "no state loaded or no edit begun").c_str();
        memcpy(core.data() + g_core_base + 0x19000, g_edit_iwram.data(), 0x8000);
        memcpy(core.data() + g_core_base + 0x21000, g_edit_ewram.data(), 0x40000);
    }
    mz_zip_archive in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    if (!mz_zip_reader_init_mem(&in, g_zip.data(), g_zip.size(), 0)) return (g_error = "zip: can not read").c_str();
    if (!mz_zip_writer_init_heap(&out, 0, 0)) {
        mz_zip_reader_end(&in);
        return (g_error = "zip: can not write").c_str();
    }
    bool ok = true;
    for (mz_uint i = 0; ok && i < mz_zip_reader_get_num_files(&in); ++i) {
        mz_zip_archive_file_stat st;
        if (!mz_zip_reader_file_stat(&in, i, &st) || st.m_is_directory) continue;
        std::string name = st.m_filename;
        if (name == "Core.bin.zst") {
            std::vector<uint8_t> z = zstd_store(core);
            // the frame is stored, so the zip entry is deflated instead
            ok = mz_zip_writer_add_mem(&out, name.c_str(), z.data(), z.size(), MZ_DEFAULT_LEVEL);
        } else if (name == "Core.bin") {
            ok = mz_zip_writer_add_mem(&out, name.c_str(), core.data(), core.size(), MZ_DEFAULT_LEVEL);
        } else {
            ok = mz_zip_writer_add_from_zip_reader(&out, &in, i);
        }
    }
    void * buf = nullptr;
    size_t size = 0;
    ok = ok && mz_zip_writer_finalize_heap_archive(&out, &buf, &size);
    mz_zip_reader_end(&in);
    if (ok) {
        FILE * f = fopen(path, "wb");
        ok = f && fwrite(buf, 1, size, f) == size;
        if (f) fclose(f);
        if (!ok) g_error = "can not write the file";
#ifdef __EMSCRIPTEN__
        // in the browser the file is in memory: hand it to the user
        if (ok)
            EM_ASM({
                const p = UTF8ToString($0);
                const a = document.createElement('a');
                a.href = URL.createObjectURL(new Blob([FS.readFile(p)]));
                a.download = p.split('/').pop();
                a.click();
            }, path);
#endif
    } else {
        g_error = "zip: can not build the archive";
    }
    mz_zip_writer_end(&out);
    return g_error.c_str();
}
