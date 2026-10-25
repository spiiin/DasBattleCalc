// PSP (PPSSPP) support for gba_mem: the RAM of a PPSSPP save state
// (.ppst). Format: research/fftwotl/notes.md, "Save state".
// Header (0xB0 bytes): u32 revision, u32 compression (0 none, 1 snappy,
// 2 zstd), u32 stored size, u32 raw size, char version[32], char
// title[128]; then the body. The raw body is PPSSPP's ChunkFile: sections
// with a 16-byte title; "Memory" holds the 32 MB user RAM (0x08000000)
// right after its u32 size.
#include "gba_mem.h"
#include <cstring>
#include <string>
#include <vector>

#include "zstd.h"

namespace {

uint32_t rd32(const std::vector<uint8_t> & v, size_t o) {
    return v[o] | v[o + 1] << 8 | v[o + 2] << 16 | uint32_t(v[o + 3]) << 24;
}
void wr32(std::vector<uint8_t> & v, size_t o, uint32_t x) {
    for (int i = 0; i < 4; ++i) v[o + i] = uint8_t(x >> (8 * i));
}

const size_t HEADER = 0xB0;

}  // namespace

bool psp_is_state(const std::vector<uint8_t> & file) {
    if (file.size() < HEADER + 16) return false;
    uint32_t comp = rd32(file, 4), stored = rd32(file, 8);
    return comp <= 2 && size_t(stored) == file.size() - HEADER && memcmp(file.data() + 0x10, "v1.", 3) == 0;
}

// raw: the decompressed body; ram_off: where the RAM starts in it
bool psp_state_ram(const std::vector<uint8_t> & file, std::vector<uint8_t> & raw, size_t & ram_off,
                   size_t & ram_size, std::string & error) {
    uint32_t comp = rd32(file, 4), raw_size = rd32(file, 12);
    if (comp == 2) {
        raw.resize(raw_size);
        size_t r = ZSTD_decompress(raw.data(), raw.size(), file.data() + HEADER, file.size() - HEADER);
        if (ZSTD_isError(r) || r != raw.size()) { error = "zstd: can not decompress the PPSSPP state"; return false; }
    } else if (comp == 0) {
        raw.assign(file.begin() + HEADER, file.end());
    } else {
        error = "PPSSPP state compressed with snappy (old PPSSPP): not supported";
        return false;
    }
    // the "Memory" section, then (version, model, marker...) the u32 RAM size
    for (size_t t = 0; t + 64 < raw.size() && t < 0x400; ++t) {
        if (memcmp(raw.data() + t, "Memory\0", 7) != 0) continue;
        for (size_t o = t + 16; o < t + 48; o += 4) {
            uint32_t n = rd32(raw, o);
            if ((n == 0x2000000 || n == 0x4000000) && o + 4 + n <= raw.size()) {
                ram_off = o + 4;
                ram_size = n;
                return true;
            }
        }
    }
    error = "no RAM (Memory section) in the PPSSPP state";
    return false;
}

// The state file with the RAM replaced: the body as one zstd frame of raw
// blocks (zstd_store in gba_mem.cpp), the header's sizes updated.
bool psp_state_write(const std::vector<uint8_t> & file, std::vector<uint8_t> raw, size_t ram_off,
                     const std::vector<uint8_t> & ram, std::vector<uint8_t> & out, std::string & error) {
    if (ram_off + ram.size() > raw.size()) { error = "PPSSPP state: RAM out of the body"; return false; }
    memcpy(raw.data() + ram_off, ram.data(), ram.size());
    std::vector<uint8_t> body = zstd_store(raw);
    out.assign(file.begin(), file.begin() + HEADER);
    wr32(out, 4, 2);
    wr32(out, 8, uint32_t(body.size()));
    wr32(out, 12, uint32_t(raw.size()));
    out.insert(out.end(), body.begin(), body.end());
    return true;
}
