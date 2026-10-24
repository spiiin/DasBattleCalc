"""Find VRAM tiles in the ROM: which VRAM ranges are plain copies of ROM.

python gfx_find.py rom.gba gfx/status_260_vram.bin
Prints runs: VRAM offset, ROM address, tile count (4bpp tiles, 32 bytes).
Tiles that are all one byte are skipped (they match everywhere).
"""
import sys

rom = open(sys.argv[1], 'rb').read()
vram = open(sys.argv[2], 'rb').read()
TILE = 32

def first_match(tile):
    hits = []
    at = rom.find(tile)
    while at >= 0 and len(hits) < 4:
        hits.append(at)
        at = rom.find(tile, at + 1)
    return hits

runs = []           # (vram_off, rom_addr, count)
for off in range(0, len(vram), TILE):
    tile = vram[off:off + TILE]
    if len(set(tile)) <= 2:
        continue
    hits = first_match(tile)
    if not hits:
        continue
    if runs:
        v, a, n = runs[-1]
        if v + n * TILE == off and a + n * TILE in hits:
            runs[-1] = (v, a, n + 1)
            continue
    runs.append((off, hits[0], 1))

for v, a, n in runs:
    if n >= 2:
        print("vram %05X  rom %08X  tiles %3d" % (v, 0x08000000 + a, n))
