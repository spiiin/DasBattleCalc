"""Item icons of FFT: WotL (PSP): EVENT/ITEM.BIN (fftpack file 33).

ITEM.BIN = 256x256 4bpp image (0x8000 B, low nibble = left pixel), then palettes of 16 BGR555 colours
(32 B each) at 0x8000: 33 used (0..32; the 0x800-byte area has room for 64).
Icon of graphic g (item byte 1): 16x16 at x = 16*(g % 15), y = 16*(g // 15) + ICON_Y0 (15 icons
per 16-px row, the last 16 px column is empty; g = 0 is the blank slot);
palette = item byte 0. Item tables: RAM 0x08B29288 (items 0..255), 0x08A5ADAC (256..315), 12 B.
"""
import os, sys
from PIL import Image, ImageDraw
import fftpack as fp
import sprites as S

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
from fftext import strings  # noqa: E402

ITEM_BIN = 33
ICON_Y0 = 32       # icon 0 starts at row 2 of 16-px rows (rows 0..1: small glyphs)
N_PAL = 33


def item_sheet():
    d = fp.get(ITEM_BIN)
    return S.Sheet(d[0x8000:0x8000 + 32 * 16] + d[:0x8000], lower=False), d


def palettes(d):
    return [[S.bgr555(int.from_bytes(d[0x8000 + 32 * p + 2 * c:0x8002 + 32 * p + 2 * c], 'little'), c)
             for c in range(16)] for p in range(N_PAL)]


def icon(d, pals, g, pal):
    pix = []
    y0, x0 = 16 * (g // 15) + ICON_Y0, 16 * (g % 15)
    for y in range(y0, y0 + 16):
        row = d[(y * 256 + x0) // 2:(y * 256 + x0 + 16) // 2]
        for b in row:
            pix += [b & 15, b >> 4]
    im = Image.new('RGBA', (16, 16))
    im.putdata([pals[pal][v] for v in pix])
    return im


def item_record(ram, i):
    a = (0x08B29288 + 12 * i if i < 256 else 0x08A5ADAC + 12 * (i - 256)) - 0x08000000
    return ram[a:a + 12]


def main():
    ram = open(os.path.join(HERE, '..', 'ram0.bin'), 'rb').read()
    names = strings(ram, 0x08A935FD, 316)
    _, d = item_sheet()
    pals = palettes(d)
    items = [i for i in range(1, 316) if item_record(ram, i)[1] or i == 1]
    cols, cw, chh, sc = 6, 130, 20, 2
    rows = (len(items) + cols - 1) // cols
    can = Image.new('RGBA', (cols * cw, rows * chh), (40, 40, 60, 255))
    dr = ImageDraw.Draw(can)
    for n, i in enumerate(items):
        r = item_record(ram, i)
        x, y = (n % cols) * cw, (n // cols) * chh
        can.alpha_composite(icon(d, pals, r[1], r[0]), (x + 2, y + 2))
        dr.text((x + 20, y + 4), '%d %s' % (i, names[i][:16]), fill=(255, 255, 255, 255))
    p = os.path.join(fp.OUT, 'item_icons.png')
    can.resize((can.width * sc, can.height * sc), Image.NEAREST).save(p)
    print(len(items), 'items ->', p)


if __name__ == '__main__':
    main()
