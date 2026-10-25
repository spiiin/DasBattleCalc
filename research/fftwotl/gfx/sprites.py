"""Unit sprites of FFT: WotL (PSP): sheet lookup, SPR decoding, SHP frames, SEQ animations.

Sheet id s (unit record +0x181) ->
  BOOT.BIN 0x32481C + 8*s : u32 'sector' (a fake PSX-style sector number), u32 size
  BOOT.BIN 0x252F34 + 4*(i-3): fake sector of fftpack file i  -> fftpack file of the sheet
  BOOT.BIN 0x324284 + 4*s : u8 SHP type, u8 SEQ type, u8 flying, u8 height
"""
import struct
from PIL import Image
import fftpack as fp

SPR_LOC, SECTOR_MAP, SPR_ATTR, NUM_SPR = 0x32481C, 0x252F34, 0x324284, 170
TYPES = ['TYPE1', 'TYPE2', 'CYOKO', 'MON', 'OTHER', 'RUKA', 'ARUTE', 'KANZEN']
# SHP / SEQ file per type (fftpack names); RUKA uses MON.SHP
SHP_FILE = {'TYPE1': 'BATTLE/TYPE1.SHP', 'TYPE2': 'BATTLE/TYPE2.SHP', 'CYOKO': 'BATTLE/CYOKO.SHP',
            'MON': 'BATTLE/MON.SHP', 'OTHER': 'BATTLE/OTHER.SHP', 'RUKA': 'BATTLE/MON.SHP',
            'ARUTE': 'BATTLE/ARUTE.SHP', 'KANZEN': 'BATTLE/KANZEN.SHP'}
SEQ_FILE = {t: 'BATTLE/%s.SEQ' % t for t in TYPES}


def u32(b, o):
    return struct.unpack_from('<I', b, o)[0]


_sec2file = None


def sector_to_file():
    global _sec2file
    if _sec2file is None:
        boot = fp.boot()
        count = fp.header()[0]
        _sec2file = {}
        for i in range(3, count):
            _sec2file[u32(boot, SECTOR_MAP + 4 * (i - 3))] = i
    return _sec2file


def sheet_info(s):
    boot = fp.boot()
    sec, size = struct.unpack_from('<II', boot, SPR_LOC + 8 * s)
    shp, seq, fly, h = boot[SPR_ATTR + 4 * s: SPR_ATTR + 4 * s + 4]
    f = sector_to_file().get(sec) if sec else None
    return dict(id=s, sector=sec, size=size, file=f, name=fp.names().get(f),
                shp=TYPES[shp] if shp < 8 else shp, seq=TYPES[seq] if seq < 8 else seq,
                flying=fly, height=h)


def bgr555(v, idx):
    if idx == 0:
        return (0, 0, 0, 0)            # colour 0 of every palette is transparent
    r, g, b = (v & 31) << 3, ((v >> 5) & 31) << 3, ((v >> 10) & 31) << 3
    return (r | r >> 5, g | g >> 5, b | b >> 5, 255)


def decompress_lower(data):
    """Lower part of a sheet (after 0x200 + 36864 bytes): nibble RLE of zero runs."""
    nib = []
    for b in data:
        nib += [b >> 4, b & 15]
    out, j = [], 0
    while j < len(nib):
        if nib[j]:
            out.append(nib[j])
        elif j + 1 < len(nib):
            s = nib[j + 1]
            if s == 7 and j + 3 < len(nib):
                n = nib[j + 2] | nib[j + 3] << 4
                j += 2
            elif s == 8 and j + 4 < len(nib):
                n = nib[j + 2] | nib[j + 3] << 4 | nib[j + 4] << 8
                j += 3
            elif s == 0 and j + 2 < len(nib):
                n = nib[j + 2]
                j += 1
            else:
                n = s
            j += 1
            out += [0] * n
        j += 1
    for k in range(0, len(out) - 1, 2):
        out[k], out[k + 1] = out[k + 1], out[k]
    return out


class Sheet:
    """16 palettes (BGR555, 32 B each) + 4bpp pixels, 256 px wide (low nibble = left pixel)."""

    def __init__(self, data, lower=True):
        self.pal = [[bgr555(struct.unpack_from('<H', data, p * 32 + c * 2)[0], c) for c in range(16)]
                    for p in range(16)]
        pix = []
        top = data[0x200:0x200 + 36864]   # rows 0..287: 256 sprite rows + 32 portrait rows
        for b in top:
            pix += [b & 15, b >> 4]
        if lower and len(data) > 0x200 + 36864:
            pix += decompress_lower(data[0x200 + 36864:])
        self.h = len(pix) // 256
        self.pix = pix[:self.h * 256]

    def image(self, palette=0):
        im = Image.new('RGBA', (256, self.h))
        p = self.pal[palette]
        im.putdata([p[v] for v in self.pix])
        return im


# frames from 'second half' on read the decompressed lower area; in the raw layout used here
# (256 sprite rows, 32 portrait rows, then the lower area) it starts at row 288
LOWER_Y = 288

TILE_SIZES = [(8, 8), (16, 8), (16, 16), (16, 24), (24, 8), (24, 16), (24, 24), (32, 8), (32, 16),
              (32, 24), (32, 32), (32, 40), (48, 16), (40, 32), (48, 48), (56, 56)]


def _ptrs(data, at):
    offs, i = [0], 0
    while True:
        a = u32(data, at + 4 * i)
        i += 1
        if not a:
            return offs
        offs.append(a)


class Shp:
    """SHP: u32 offset of a second table (<= 8: none), u16 'second half' frame index; frame pointer
    table at 0x0C (u32, 0-terminated, frame 0 implied at 0); frame data at pointer + 0x40A."""

    def __init__(self, data):
        jump = u32(data, 0)
        self.second_half = data[4] | data[5] << 8
        offs = _ptrs(data, 0x0C)
        self.frames = [self._frame(data, o + 0x40A, LOWER_Y if k >= self.second_half else 0)
                       for k, o in enumerate(offs)]
        if jump > 8:            # second block (attack frames etc.)
            offs = _ptrs(data, jump + 4)
            self.frames += [self._frame(data, o + jump + 0x402, LOWER_Y if k >= self.second_half else 0)
                            for k, o in enumerate(offs)]

    @staticmethod
    def _frame(d, o, yoff):
        n = d[o] | d[o + 1] << 8
        pieces = []
        for i in range(n + 1):
            x, y = struct.unpack_from('<bb', d, o + 2 + 4 * i)
            fl = d[o + 4 + 4 * i] | d[o + 5 + 4 * i] << 8
            w, h = TILE_SIZES[(fl >> 10) & 15]
            pieces.append(dict(x=x, y=y, sx=(fl & 31) * 8, sy=((fl >> 5) & 31) * 8 + yoff, w=w, h=h,
                               fx=bool(fl & 0x4000), fy=bool(fl & 0x8000)))
        return pieces[::-1]     # listed front to back: draw in reverse


SEQ_JUMPS = {192: 1, 198: 1, 211: 1, 212: 1, 214: 1, 215: 1, 216: 1, 226: 1, 238: 1, 239: 1, 240: 1,
             246: 1, 193: 2, 217: 2, 242: 2, 252: 2, 250: 3}


def parse_seq(data):
    """SEQ: 4-byte header, up to 0x100 u32 offsets at 4 (0xFFFFFFFF ends), animation bytes at
    0x406 + offset. Animation = pairs (frame, delay); 0xFF xx = opcode with SEQ_JUMPS[xx] more bytes."""
    offs = []
    for i in range(0x100):
        a = u32(data, 4 + 4 * i)
        if a == 0xFFFFFFFF:
            break
        offs.append(a)
    anims = []
    for i, a in enumerate(offs):
        end = offs[i + 1] if i + 1 < len(offs) else len(data) - 0x406
        b = data[0x406 + a: 0x406 + end]
        fr, j = [], 0
        while j < len(b) - 1:
            if b[j] != 0xFF:
                fr.append((b[j], b[j + 1]))
            else:
                j += SEQ_JUMPS.get(b[j + 1], 0)
            j += 2
        anims.append(fr)
    return anims


def render_frame(sheet, frame, palette=0, mirror=False, size=(96, 128), origin=(48, 112)):
    """Compose a frame onto a canvas; origin = canvas point of the frame's (0, 0)."""
    src = sheet.image(palette)
    can = Image.new('RGBA', size, (0, 0, 0, 0))
    for p in frame:
        t = src.crop((p['sx'], p['sy'], p['sx'] + p['w'], p['sy'] + p['h']))
        if p['fx']:
            t = t.transpose(Image.FLIP_LEFT_RIGHT)
        if p['fy']:
            t = t.transpose(Image.FLIP_TOP_BOTTOM)
        x, y = origin[0] + p['x'], origin[1] + p['y']
        if 0 <= x and 0 <= y and x + p['w'] <= size[0] and y + p['h'] <= size[1]:
            can.alpha_composite(t, (x, y))
        else:
            tmp = Image.new('RGBA', size, (0, 0, 0, 0))
            tmp.paste(t, (x, y))
            can = Image.alpha_composite(can, tmp)
    if mirror:
        can = can.transpose(Image.FLIP_LEFT_RIGHT)
    return can


_cache = {}


def load_shp(t):
    if ('shp', t) not in _cache:
        _cache[('shp', t)] = Shp(fp.get(fp.find(SHP_FILE[t])))
    return _cache[('shp', t)]


def load_seq(t):
    if ('seq', t) not in _cache:
        _cache[('seq', t)] = parse_seq(fp.get(fp.find(SEQ_FILE[t])))
    return _cache[('seq', t)]


def load_sheet(s):
    inf = sheet_info(s)
    return inf, Sheet(fp.get(inf['file'])[:inf['size']])


if __name__ == '__main__':
    for s in range(NUM_SPR):
        inf = sheet_info(s)
        print('%02X %-5s %-6s %-6s fly%d h%-3d %s %s size %d' % (
            s, inf['file'], inf['shp'], inf['seq'], inf['flying'], inf['height'], inf['name'],
            hex(inf['sector']), inf['size']))
