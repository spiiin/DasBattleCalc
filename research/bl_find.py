"""Thumb BL call sites of a function: python bl_find.py rom.gba 0x080CB8D4"""
import sys, struct
rom = open(sys.argv[1], 'rb').read()
target = int(sys.argv[2], 0)
for o in range(0, 0x200000, 2):
    h1, h2 = struct.unpack_from('<HH', rom, o)
    if h1 & 0xF800 == 0xF000 and h2 & 0xF800 == 0xF800:
        off = ((h1 & 0x7FF) << 12) | ((h2 & 0x7FF) << 1)
        if off & 0x400000:
            off -= 0x800000
        if 0x08000000 + o + 4 + off == target:
            print(hex(0x08000000 + o))
