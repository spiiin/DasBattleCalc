"""FFT (PSX, USA) research helpers: the disc image (MODE2/2352, ISO9660)
and the BizHawk Nymashock state (a waterbox image: main RAM pages).

python psx.py ls <disc.bin> [dir]          list a directory of the disc
python psx.py get <disc.bin> <path> <out>  extract a file
python psx.py ram <state> <disc.bin> <out> the 2 MB main RAM of the state
"""
import struct
import sys
import zipfile

SECTOR = 2352


class Disc:
    def __init__(self, path):
        self.f = open(path, 'rb')

    def sector(self, lba):
        self.f.seek(lba * SECTOR)
        raw = self.f.read(SECTOR)
        return raw[24:24 + 2048]          # mode 2 form 1: header 16, subheader 8

    def read(self, lba, size):
        out = bytearray()
        while len(out) < size:
            out += self.sector(lba)
            lba += 1
        return bytes(out[:size])

    def entries(self, lba, size):
        data = self.read(lba, size)
        p = 0
        res = []
        while p < len(data):
            n = data[p]
            if n == 0:
                p = (p // 2048 + 1) * 2048
                continue
            ext = struct.unpack_from('<I', data, p + 2)[0]
            ln = struct.unpack_from('<I', data, p + 10)[0]
            flags = data[p + 25]
            nl = data[p + 32]
            name = data[p + 33:p + 33 + nl].decode('latin1')
            res.append((name, ext, ln, flags & 2 != 0))
            p += n
        return res

    def root(self):
        pvd = self.sector(16)
        assert pvd[1:6] == b'CD001', pvd[:8]
        ext = struct.unpack_from('<I', pvd, 156 + 2)[0]
        ln = struct.unpack_from('<I', pvd, 156 + 10)[0]
        return ext, ln

    def find(self, path):
        ext, ln = self.root()
        parts = [p for p in path.upper().split('/') if p]
        for i, part in enumerate(parts):
            for name, e, l, d in self.entries(ext, ln):
                if name.split(';')[0] == part.split(';')[0]:
                    ext, ln = e, l
                    break
            else:
                raise KeyError(path)
        return ext, ln

    def file(self, path):
        ext, ln = self.find(path)
        return self.read(ext, ln)


PAGE = 4096


def core_of(state_path):
    import zstandard
    z = zipfile.ZipFile(state_path)
    d = z.read('Core.bin.zst')
    return zstandard.ZstdDecompressor().decompressobj().decompress(d)


def waterbox_pages(core):
    """(dirty flags per page, offset of the saved data, number of pages)"""
    m = core.find(b'ActivatedMemoryBlock')
    p = m + len(b'ActivatedMemoryBlock') + 32
    size = struct.unpack_from('<Q', core, p + 8)[0]
    n = size // PAGE
    dirty = core[p + 16 + n:p + 16 + 2 * n]
    data = p + 16 + 2 * n + 32
    return dirty, data, n


def saved_index(dirty):
    """page index -> index among the saved pages"""
    res = {}
    k = 0
    for j, d in enumerate(dirty):
        if d:
            res[j] = k
            k += 1
    return res


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'ls':
        disc = Disc(sys.argv[2])
        ext, ln = disc.find(sys.argv[3]) if len(sys.argv) > 3 else disc.root()
        for name, e, l, d in disc.entries(ext, ln):
            print(('d ' if d else '  ') + name, e, l)
    elif cmd == 'get':
        open(sys.argv[4], 'wb').write(Disc(sys.argv[2]).file(sys.argv[3]))
