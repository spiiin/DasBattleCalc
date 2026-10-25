# Forecast probe: the unit records of two states (before: the turn, after:
# the target cursor on an enemy with the forecast shown), the bytes that
# differ in each record.  python fcdiff.py before.ppst after.ppst
import sys, struct, zstandard
REC, SZ = 0x092E5CB4, 0x1E8
def ram(path):
    d = open(path, 'rb').read()
    comp, csize, usize = struct.unpack_from('<3I', d, 4)
    raw = zstandard.ZstdDecompressor().decompress(d[0xB0:0xB0 + csize], max_output_size=usize) if comp == 2 else d[0xB0:]
    return raw[0x48:0x48 + 0x2000000]
a, b = ram(sys.argv[1]), ram(sys.argv[2])
open('ram_fc.bin', 'wb').write(b)
from fftext import dec
for k in range(16):
    o = REC - 0x08000000 + k * SZ
    diffs = [(i, a[o + i], b[o + i]) for i in range(SZ) if a[o + i] != b[o + i]]
    if diffs:
        print(k, dec(b[o + 0x14E:o + 0x15A]).split('{fe}')[0], ' '.join('%03x:%d->%d' % t for t in diffs))
