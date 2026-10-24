// NDS (melonDS core) support for gba_mem: the main RAM of a BizHawk
// waterbox state, and files of an NDS ROM (NitroFS, the pc.idx / pc.bin
// archive of FFTA2, idx + pak pairs). Formats: research/ffta2/notes.md.
#include "gba_mem.h"
#include <cstring>
#include <map>
#include <string>
#include <vector>

namespace {

uint64_t rd64(const std::vector<uint8_t> & v, size_t o) {
    uint64_t r = 0;
    for (int i = 7; i >= 0; --i) r = r << 8 | v[o + i];
    return r;
}
uint32_t rd32(const uint8_t * p) { return p[0] | p[1] << 8 | p[2] << 16 | uint32_t(p[3]) << 24; }
uint16_t rd16(const uint8_t * p) { return uint16_t(p[0] | p[1] << 8); }

uint16_t crc16(const uint8_t * p, size_t n) {
    uint16_t c = 0xFFFF;
    for (size_t i = 0; i < n; ++i) {
        c ^= p[i];
        for (int b = 0; b < 8; ++b) c = (c & 1) ? (c >> 1) ^ 0xA001 : c >> 1;
    }
    return c;
}

// a cartridge header with a valid CRC (the copy at main RAM 0x027FFE00)
bool is_nds_header(const uint8_t * p) { return crc16(p, 0x15E) == rd16(p + 0x15E); }

const size_t PAGE = 4096;
// the guest page of NDS main RAM in BizHawk 2.11's melonDS core (a static
// array: fixed for a core build)
const size_t MAIN_RAM_PAGE = 143532;

}  // namespace

bool nds_state_ram(const std::vector<uint8_t> & core, std::vector<uint8_t> & ram, std::string & error) {
    static const char magic[] = "ActivatedMemoryBlock";
    const size_t mlen = sizeof(magic) - 1;
    size_t m = 0;
    for (; m + mlen < core.size() && m < 0x10000; ++m)
        if (memcmp(core.data() + m, magic, mlen) == 0) break;
    if (m + mlen >= core.size() || m >= 0x10000) { error = "no waterbox memory block"; return false; }
    size_t p = m + mlen + 32;                         // magic, 32-byte hash
    uint64_t size = rd64(core, p + 8);                // start, size
    size_t n = size_t(size / PAGE);
    const uint8_t * dirty = core.data() + p + 16 + n; // after one status byte per page
    size_t data = p + 16 + 2 * n + 32;
    if (data > core.size() || MAIN_RAM_PAGE + 1024 > n) { error = "unexpected waterbox layout"; return false; }
    size_t pages = (core.size() - data) / PAGE;
    // anchor: the saved page that holds the header copy at +0xE00 is main RAM page 1023
    size_t anchor = SIZE_MAX;
    for (size_t k = 0; k < pages; ++k)
        if (is_nds_header(core.data() + data + k * PAGE + 0xE00)) anchor = k;
    if (anchor == SIZE_MAX || !dirty[MAIN_RAM_PAGE + 1023]) { error = "NDS main RAM not found in the state"; return false; }
    ram.assign(0x400000, 0);
    size_t k = anchor;
    for (size_t j = 1024; j-- > 0;) {
        if (!dirty[MAIN_RAM_PAGE + j]) continue;      // not saved: never written since the core started
        memcpy(ram.data() + j * PAGE, core.data() + data + k * PAGE, PAGE);
        if (k == 0) break;
        --k;
    }
    return true;
}

bool nds_is_rom(const std::vector<uint8_t> & rom) { return rom.size() >= 0x200 && is_nds_header(rom.data()); }

// ------------------------------------------------------------------ ROM files

namespace {

struct Files {
    uint32_t serial = 0xFFFFFFFF;
    std::vector<std::vector<uint8_t>> bufs;
    std::map<std::string, int> by_key;
};
Files g_files;

const std::vector<uint8_t> & rom() { return gba_rom_bytes(); }

// NitroFS: the file id of a path ("master/pc.idx"), -1 if absent
int nitro_find(const std::string & path) {
    const auto & r = rom();
    if (r.size() < 0x200) return -1;
    uint32_t fnt = rd32(&r[0x40]);
    uint16_t dir = 0xF000;
    size_t pos = 0;
    while (true) {
        size_t slash = path.find('/', pos);
        std::string part = path.substr(pos, slash == std::string::npos ? std::string::npos : slash - pos);
        size_t e = fnt + (dir & 0xFFF) * 8;
        if (e + 8 > r.size()) return -1;
        uint32_t sub = rd32(&r[e]);
        uint16_t file = rd16(&r[e + 4]);
        size_t q = fnt + sub;
        bool found = false;
        while (q < r.size() && r[q]) {
            uint8_t t = r[q++];
            size_t len = t & 0x7F;
            std::string name(reinterpret_cast<const char *>(&r[q]), len);
            q += len;
            if (t & 0x80) {
                uint16_t sub_dir = rd16(&r[q]);
                q += 2;
                if (name == part && slash != std::string::npos) { dir = sub_dir; found = true; break; }
            } else {
                if (name == part && slash == std::string::npos) return file;
                ++file;
            }
        }
        if (!found) return -1;
        pos = slash + 1;
    }
}

// a file's place in the ROM (offset, size); false if absent
bool nitro_range(const std::string & path, size_t & off, size_t & size) {
    int id = nitro_find(path);
    if (id < 0) return false;
    const auto & r = rom();
    size_t fat = rd32(&r[0x48]) + size_t(id) * 8;
    uint32_t a = rd32(&r[fat]), b = rd32(&r[fat + 4]);
    if (b < a || b > r.size()) return false;
    off = a;
    size = b - a;
    return true;
}

bool nitro_file(const std::string & path, std::vector<uint8_t> & out) {
    size_t off = 0, size = 0;
    if (!nitro_range(path, off, size)) return false;
    out.assign(rom().begin() + off, rom().begin() + off + size);
    return true;
}

// pc.idx / pc.bin (Rurusachi/ffta2-editor, Archive.java): a file by the
// hash of its name; a hash shared by several names lists them with the
// character at a position that tells them apart
struct Archive {
    std::vector<uint8_t> idx;
    size_t bin_off = 0, bin_size = 0;     // pc.bin stays in the ROM (86 MB)
    bool ok = false;
};
Archive g_archive;

int name_hash(const std::string & s) {
    int32_t c = int8_t(s[0]);
    for (size_t i = 1; i < s.size(); ++i) c = int32_t(uint32_t(c) * 0x25u + uint32_t(int8_t(s[i])));
    return c & 0x3FF;
}

bool archive_file(const std::string & name, std::vector<uint8_t> & out) {
    if (!g_archive.ok) {
        g_archive.ok = nitro_file("master/pc.idx", g_archive.idx) &&
            nitro_range("master/pc.bin", g_archive.bin_off, g_archive.bin_size);
        if (!g_archive.ok) return false;
    }
    const auto & idx = g_archive.idx;
    const uint8_t * bin = rom().data() + g_archive.bin_off;
    const size_t bin_size = g_archive.bin_size;
    uint32_t count = rd32(&idx[0]);
    int h = name_hash(name);
    if (uint32_t(h) >= count) return false;
    uint32_t a = rd32(&idx[8 + h * 9]), b = rd32(&idx[8 + h * 9 + 4]);
    if (a == 0 && b == 0) return false;
    size_t off = size_t(a & 0x3FFFFFF) * 2;
    size_t size = size_t((a >> 26) + (b & 0xFFFF) * 64) * 4;
    if (!(a & 1)) {
        if (off + size > bin_size) return false;
        out.assign(bin + off, bin + off + size);
        return true;
    }
    // a list in the table after the ids: its position in pc.idx is off / 4
    size_t q = off / 4;
    if (q >= idx.size()) return false;
    uint8_t n = idx[q++];
    for (int i = 0; i < n; ++i) {
        uint32_t o = rd32(&idx[q]) * 4;
        q += 4;
        uint32_t s = 0;
        if (i) { s = rd32(&idx[q]) * 4; q += 8; }
        uint8_t chr = idx[q], pos = idx[q + 1];
        q += 3;
        if (pos < name.size() && uint8_t(name[pos]) == chr) {
            size_t len = s ? s : size;
            if (o + len > bin_size) return false;
            out.assign(bin + o, bin + o + len);
            return true;
        }
    }
    return false;
}

// name.idx + name.pak (IdxAndPak.java): file `index` of the pak
bool pak_file(const std::string & idx_name, const std::string & pak_name, int index, std::vector<uint8_t> & out) {
    std::vector<uint8_t> idx, pak;
    if (!archive_file(idx_name, idx) || !archive_file(pak_name, pak)) return false;
    size_t n = (idx.size() - 4) / 6;
    int file = 0;
    for (size_t i = 0; i < n; ++i) {
        uint32_t a1 = rd32(&idx[4 + i * 6]);
        if (a1 & 7) {
            if (i != n - 1) {
                if (file == index) return false;      // an empty slot
                ++file;
            }
            continue;
        }
        if (file == index) {
            uint32_t a2 = i + 1 < n ? rd32(&idx[4 + (i + 1) * 6]) : a1;
            uint32_t ab1 = (a1 << 5) >> 8, ab2 = (a2 << 5) >> 8;
            size_t o = size_t(ab1) << 2, e = size_t(ab2) << 2;
            if (e < o || e > pak.size()) return false;
            out.assign(pak.begin() + o, pak.begin() + e);
            return true;
        }
        ++file;
    }
    return false;
}

void check_rom() {
    if (g_files.serial == gba_rom_serial()) return;
    g_files = Files();
    g_files.serial = gba_rom_serial();
    g_archive = Archive();
}

int keep(const std::string & key, bool ok, std::vector<uint8_t> & data) {
    int h = ok ? int(g_files.bufs.size()) : -1;
    if (ok) g_files.bufs.push_back(std::move(data));
    g_files.by_key[key] = h;
    return h;
}

const std::vector<uint8_t> * buf(int h) {
    check_rom();
    return h >= 0 && h < int(g_files.bufs.size()) ? &g_files.bufs[h] : nullptr;
}

}  // namespace

int nds_file(const char * name) {
    check_rom();
    std::string key = std::string("a:") + name;
    auto it = g_files.by_key.find(key);
    if (it != g_files.by_key.end()) return it->second;
    std::vector<uint8_t> data;
    return keep(key, archive_file(name, data), data);
}

int nds_pak_file(const char * idx_name, const char * pak_name, int index) {
    check_rom();
    std::string key = std::string("p:") + idx_name + "|" + pak_name + "|" + std::to_string(index);
    auto it = g_files.by_key.find(key);
    if (it != g_files.by_key.end()) return it->second;
    std::vector<uint8_t> data;
    return keep(key, pak_file(idx_name, pak_name, index, data), data);
}

int nds_buf_size(int h) {
    auto b = buf(h);
    return b ? int(b->size()) : 0;
}
uint32_t nds_buf_read8(int h, int off) {
    auto b = buf(h);
    return b && off >= 0 && size_t(off) < b->size() ? (*b)[off] : 0;
}
uint32_t nds_buf_read16(int h, int off) {
    auto b = buf(h);
    return b && off >= 0 && size_t(off) + 2 <= b->size() ? rd16(&(*b)[off]) : 0;
}
uint32_t nds_buf_read32(int h, int off) {
    auto b = buf(h);
    return b && off >= 0 && size_t(off) + 4 <= b->size() ? rd32(&(*b)[off]) : 0;
}
