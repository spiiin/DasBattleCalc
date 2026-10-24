"""Render a VRAM dump as 4bpp tiles, 32 per row, to look for graphics.

python gfx_sheet.py vram.bin pal.bin out.png [palette] [start] [end]
palette: 0..15 BG palette, 16..31 OBJ palette, -1 grey (default);
start / end: VRAM byte offsets (default the whole dump).
"""
import sys
import struct
from PIL import Image

vram = open(sys.argv[1], 'rb').read()
pal = open(sys.argv[2], 'rb').read()
which = int(sys.argv[4]) if len(sys.argv) > 4 else -1
start = int(sys.argv[5], 0) if len(sys.argv) > 5 else 0
end = int(sys.argv[6], 0) if len(sys.argv) > 6 else len(vram)

def color(i):
    if which < 0:
        return (i * 17, i * 17, i * 17)
    v = struct.unpack_from('<H', pal, (which * 16 + i) * 2)[0]
    return ((v & 31) << 3, ((v >> 5) & 31) << 3, ((v >> 10) & 31) << 3)

colors = [color(i) for i in range(16)]
data = vram[start:end]
n = len(data) // 32
per_row = 32
img = Image.new('RGB', (per_row * 8, ((n + per_row - 1) // per_row) * 8))
px = img.load()
for t in range(n):
    tx, ty = (t % per_row) * 8, (t // per_row) * 8
    for y in range(8):
        for x in range(8):
            b = data[t * 32 + y * 4 + x // 2]
            px[tx + x, ty + y] = colors[(b >> 4) if x & 1 else (b & 15)]
img.save(sys.argv[3])
