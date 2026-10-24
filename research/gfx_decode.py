"""FFTA graphics formats, as the game decodes them (research/notes.md, "Graphics").

- lzss(rom, addr): 0x0800543C - 4-byte big-endian length, then the FFTA
  LZSS opcodes (Data Crystal "Compression Formats").
- a7(rom, addr, i): 0x08005318 - entry i of an "A7" archive: magic "A7",
  BE16 count, BE32 offset of the shared dictionary, BE32 entry offsets;
  an entry copies runs of literals and runs from the dictionary
  (0x080051C4).
- tiles4 / tiles8: GBA tiles to RGBA with BGR555 palettes.
"""
import struct

def be16(b, o):
    return (b[o] << 8) | b[o + 1]

def be32(b, o):
    return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]

def off(addr):
    return addr - 0x08000000 if addr >= 0x08000000 else addr

def lzss(rom, addr):
    s = off(addr)
    n = be32(rom, s)
    out = bytearray()
    i = s + 4
    while len(out) < n:
        b = rom[i]
        if b & 0x80:
            back = ((b & 0x07) << 8) | rom[i + 1]
            for _ in range(((b >> 3) & 0x0F) + 3):
                out.append(out[len(out) - back - 1])
            i += 2
        elif b & 0x40:
            cnt = (b & 0x3F) + 1
            out += rom[i + 1:i + 1 + cnt]
            i += 1 + cnt
        elif b & 0x20:
            out += bytes((b & 0x1F) + 2)
            i += 1
        elif b & 0x10:
            back = ((rom[i + 1] & 0x3F) << 8) | rom[i + 2]
            cnt = (((rom[i + 1] >> 2) & 0x30) | (b & 0x0F)) + 4
            p = max(0, len(out) - back - 1)
            for k in range(cnt):
                out.append(out[p + k])
            i += 3
        elif b == 0x01:
            out += b'\xff' * (rom[i + 1] + 3)
            i += 2
        elif b == 0x02:
            out += bytes(rom[i + 1] + 3)
            i += 2
        elif b == 0x00:
            back = be16(rom, i + 2)
            p = max(0, len(out) - back - 1)
            for k in range(rom[i + 1] + 5):
                out.append(out[p + k])
            i += 4
        else:
            raise ValueError("lzss: opcode %02X at %08X" % (b, i))
    return bytes(out[:n])

def a7_count(rom, addr):
    s = off(addr)
    assert rom[s:s + 2] == b'A7', "not an A7 archive at %08X" % addr
    return be16(rom, s + 2)

def a7(rom, addr, index):
    s = off(addr)
    assert rom[s:s + 2] == b'A7', "not an A7 archive at %08X" % addr
    if index >= be16(rom, s + 2):
        raise IndexError(index)
    d = s + be32(rom, s + 4)            # the shared dictionary
    kind, bits = rom[d], rom[d + 1]
    d += 2
    total = None
    if kind <= 2:
        total = be16(rom, d)
        d += 2
    e = s + be32(rom, s + 8 + index * 4)
    if kind == 3:
        total = be16(rom, e)
        e += 2
    elif kind != 0:
        raise ValueError("a7: dictionary kind %d" % kind)
    mask = 0xFFFF >> (bits + 1)
    out = bytearray()
    while len(out) < total:
        c = rom[e]
        if c & 0x80:
            cnt = (c & 0x7F) + 1
            out += rom[e + 1:e + 1 + cnt]
            e += 1 + cnt
        else:
            cnt = ((c << 1) >> (8 - bits)) + 3
            at = ((c << 8) | rom[e + 1]) & mask
            out += rom[d + at:d + at + cnt]
            e += 2
    return bytes(out[:total])

def bgr555(v):
    r, g, b = v & 31, (v >> 5) & 31, (v >> 10) & 31
    return ((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2))

def palette(data, offset, n):
    return [bgr555(struct.unpack_from('<H', data, offset + i * 2)[0]) for i in range(n)]

def tiles(data, pal, w_tiles, h_tiles, bpp=4):
    """RGBA rows (list of list of tuples); colour 0 transparent."""
    size = 32 if bpp == 4 else 64
    img = [[(0, 0, 0, 0)] * (w_tiles * 8) for _ in range(h_tiles * 8)]
    for t in range(w_tiles * h_tiles):
        tx, ty = (t % w_tiles) * 8, (t // w_tiles) * 8
        for y in range(8):
            for x in range(8):
                if bpp == 4:
                    b = data[t * size + y * 4 + x // 2]
                    c = (b >> 4) if x & 1 else b & 15
                else:
                    c = data[t * size + y * 8 + x]
                if c:
                    img[ty + y][tx + x] = pal[c] + (255,)
    return img
