# PPSSPP save state (.ppst): header, zstd body. Usage: ppst.py state.ppst out.bin
import sys, struct, zstandard
d = open(sys.argv[1], 'rb').read()
rev, comp, csize, usize = struct.unpack_from('<4I', d, 0)
print('rev', rev, 'comp', comp, 'csize', hex(csize), 'usize', hex(usize))
body = d[0xB0:0xB0 + csize]
raw = zstandard.ZstdDecompressor().decompress(body, max_output_size=usize)
print('raw', hex(len(raw)))
open(sys.argv[2], 'wb').write(raw)
