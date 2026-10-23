"""Finds Thumb BL calls to given targets: python blrefs.py rom.gba 0x0812F410 ..."""
import struct, sys
rom = open(sys.argv[1], 'rb').read()
targets = {int(a, 16) for a in sys.argv[2:]}
for off in range(0, len(rom) - 4, 2):
    h1, h2 = struct.unpack_from('<HH', rom, off)
    if h1 >> 11 == 0x1E and h2 >> 11 == 0x1F:
        d = ((h1 & 0x7FF) << 12) | ((h2 & 0x7FF) << 1)
        if d & 0x400000:
            d -= 0x800000
        t = 0x08000000 + off + 4 + d
        if t in targets:
            print(f'{0x08000000 + off:08X} -> {t:08X}')
