"""FFTA2 unit graphics (char/rom/pak/UnitCg.pak + UnitSst.pak, indexes
char/rom/rom_idx/Unit*.rom_idx; 324 sets): research helpers.

python unit_gfx.py rom.nds cg <set> out.png [width_tiles]   chunks as 4bpp tiles, grey
"""
import struct
import sys

from ffta2_rom import open_rom, IdxPak


def lz77(b, p=0):
    """NDS LZ77 (type 0x10) at p: (data, end offset)."""
    assert b[p] == 0x10, hex(b[p])
    size = b[p + 1] | b[p + 2] << 8 | b[p + 3] << 16
    out = bytearray()
    p += 4
    while len(out) < size:
        flags = b[p]
        p += 1
        for bit in range(8):
            if len(out) >= size:
                break
            if flags & (0x80 >> bit):
                v = b[p] << 8 | b[p + 1]
                p += 2
                n = (v >> 12) + 3
                d = (v & 0xFFF) + 1
                for _ in range(n):
                    out.append(out[-d])
            else:
                out.append(b[p])
                p += 1
    return bytes(out[:size]), p


def chunks(b):
    """The LZ77 blocks of a UnitCg entry, one after another (4-aligned)."""
    res = []
    p = 0
    while p < len(b) and b[p] == 0x10:
        d, p = lz77(b, p)
        res.append(d)
        p = (p + 3) & ~3
    return res, p


def sets(path):
    nds, arc = open_rom(path)
    cg = IdxPak(arc.file('char/rom/rom_idx/UnitCg.rom_idx'), arc.file('char/rom/pak/UnitCg.pak')).files
    sst = IdxPak(arc.file('char/rom/rom_idx/UnitSst.rom_idx'), arc.file('char/rom/pak/UnitSst.pak')).files
    return cg, sst


def tiles_image(data, wt, pal=None):
    from PIL import Image
    n = len(data) // 32
    ht = (n + wt - 1) // wt
    im = Image.new('RGB', (wt * 8, ht * 8))
    px = im.load()
    for t in range(n):
        tx, ty = t % wt * 8, t // wt * 8
        for i in range(64):
            v = data[t * 32 + i // 2] >> (4 * (i & 1)) & 15
            c = pal[v] if pal else (v * 17, v * 17, v * 17)
            px[tx + i % 8, ty + i // 8] = c
    return im


if __name__ == '__main__':
    cg, sst = sets(sys.argv[1])
    if sys.argv[2] == 'cg':
        s = int(sys.argv[3])
        cs, end = chunks(cg[s])
        print('set', s, 'chunks', len(cs), [len(c) for c in cs[:8]], 'end', end, 'of', len(cg[s]))
        print('tail', cg[s][end:end + 64].hex())
        wt = int(sys.argv[5]) if len(sys.argv) > 5 else 8
        from PIL import Image
        ims = [tiles_image(c, wt) for c in cs]
        w = sum(i.width + 4 for i in ims)
        out = Image.new('RGB', (min(w, 2000), (ims[0].height + 4) * ((w + 1999) // 2000)), (60, 0, 60))
        x = y = 0
        for im in ims:
            if x + im.width > out.width:
                x, y = 0, y + im.height + 4
            out.paste(im, (x, y))
            x += im.width + 4
        out = out.resize((out.width * 2, out.height * 2))
        out.save(sys.argv[4])
