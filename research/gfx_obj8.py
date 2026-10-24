"""Draw the visible OBJ sprites of a frame from its VRAM / palette / OAM dumps.

python gfx_obj8.py <prefix> out.png   (prefix: gfx/status_260)
1D mapping; 4bpp and 8bpp; flips. Shows what the sprites hold.
"""
import sys, struct
from PIL import Image
p = sys.argv[1]
vram = open(p + '_vram.bin', 'rb').read()
pal = open(p + '_pal.bin', 'rb').read()
oam = open(p + '_oam.bin', 'rb').read()
SIZES = {(0, 0): (8, 8), (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
         (1, 0): (16, 8), (1, 1): (32, 8), (1, 2): (32, 16), (1, 3): (64, 32),
         (2, 0): (8, 16), (2, 1): (8, 32), (2, 2): (16, 32), (2, 3): (32, 64)}
def rgb(i):
    v = struct.unpack_from('<H', pal, 0x200 + i * 2)[0]
    return ((v & 31) << 3, ((v >> 5) & 31) << 3, ((v >> 10) & 31) << 3, 255)
img = Image.new('RGBA', (240, 160), (40, 40, 40, 255))
px = img.load()
for i in range(127, -1, -1):
    a0, a1, a2 = struct.unpack_from('<HHH', oam, i * 8)
    if (a0 >> 8) & 3 == 2 or a0 >> 14 == 3:
        continue
    w, h = SIZES[(a0 >> 14, a1 >> 14)]
    y0, x0 = a0 & 0xFF, a1 & 0x1FF
    if y0 >= 160: y0 -= 256
    if x0 >= 256: x0 -= 512
    bpp8 = (a0 >> 13) & 1
    tile, palno = a2 & 0x3FF, a2 >> 12
    hf, vf = (a1 >> 12) & 1, (a1 >> 13) & 1
    tw = w // 8
    for y in range(h):
        for x in range(w):
            sx = w - 1 - x if hf else x
            sy = h - 1 - y if vf else y
            t = (sy // 8) * tw + sx // 8
            if bpp8:
                addr = 0x10000 + tile * 32 + t * 64 + (sy % 8) * 8 + sx % 8
                c = vram[addr]
                col = rgb(c) if c else None
            else:
                addr = 0x10000 + tile * 32 + t * 32 + (sy % 8) * 4 + (sx % 8) // 2
                b = vram[addr]
                c = (b >> 4) if sx & 1 else b & 15
                col = rgb(palno * 16 + c) if c else None
            X, Y = x0 + x, y0 + y
            if col and 0 <= X < 240 and 0 <= Y < 160:
                px[X, Y] = col
img.resize((480, 320), Image.NEAREST).save(sys.argv[2])
