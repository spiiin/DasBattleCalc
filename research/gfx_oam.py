"""List visible OAM sprites: python gfx_oam.py oam.bin"""
import sys, struct
oam = open(sys.argv[1], 'rb').read()
SIZES = {(0, 0): (8, 8), (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
         (1, 0): (16, 8), (1, 1): (32, 8), (1, 2): (32, 16), (1, 3): (64, 32),
         (2, 0): (8, 16), (2, 1): (8, 32), (2, 2): (16, 32), (2, 3): (32, 64)}
for i in range(128):
    a0, a1, a2 = struct.unpack_from('<HHH', oam, i * 8)
    if (a0 >> 8) & 3 == 2:      # hidden
        continue
    shape, size = a0 >> 14, a1 >> 14
    if shape == 3:
        continue
    w, h = SIZES[(shape, size)]
    y, x = a0 & 0xFF, a1 & 0x1FF
    print("%3d x=%3d y=%3d %2dx%-2d tile=%3d pal=%2d prio=%d 8bpp=%d hflip=%d" % (
        i, x if x < 256 else x - 512, y if y < 160 else y - 256, w, h, a2 & 0x3FF, a2 >> 12, (a2 >> 10) & 3,
        (a0 >> 13) & 1, (a1 >> 12) & 1))
