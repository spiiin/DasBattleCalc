"""FFTA2 ROM files (research/ffta2/notes.md, "Game data in the ROM").

The formats follow Rurusachi/ffta2-editor (MIT): NitroFS of the .nds, the
pc.idx / pc.bin archive (files by a hash of the name), idx + pak pairs.

python ffta2_rom.py rom.nds            lists the NitroFS and checks the archive
"""
import struct
import sys


class Nds:
    def __init__(self, path):
        self.rom = open(path, 'rb').read()
        r = self.rom
        self.fnt, self.fnt_size, self.fat, self.fat_size = struct.unpack_from('<IIII', r, 0x40)
        self.paths = {}
        self._walk(0xF000, '')

    def _walk(self, dir_id, prefix):
        r = self.rom
        entry = self.fnt + (dir_id & 0xFFF) * 8
        sub, first, _ = struct.unpack_from('<IHH', r, entry)
        p = self.fnt + sub
        file_id = first
        while True:
            t = r[p]
            p += 1
            if t == 0:
                break
            n = t & 0x7F
            name = r[p:p + n].decode('latin-1')
            p += n
            if t & 0x80:
                sub_id = struct.unpack_from('<H', r, p)[0]
                p += 2
                self._walk(sub_id, prefix + name + '/')
            else:
                self.paths[prefix + name] = file_id
                file_id += 1

    def file(self, path):
        fid = self.paths[path]
        start, end = struct.unpack_from('<II', self.rom, self.fat + fid * 8)
        return self.rom[start:end]


class Archive:
    """master/pc.idx + pc.bin (ndstool: data/master): entries by filename_crc(name)."""

    def __init__(self, idx, binf):
        self.bin = binf
        n = struct.unpack_from('<I', idx, 0)[0]
        self.ids = []
        p = 8
        for _ in range(n):
            a, b = struct.unpack_from('<II', idx, p)
            self.ids.append((a, b))
            p += 9
        self.extra_start = p
        self.extra = idx[p:]
        self.lists = self._bottom()

    def _bottom(self):
        out = {}
        e = self.extra
        p = 0
        while p < len(e):
            start = p
            n = e[p]
            p += 1
            if n == 0:
                break
            lst = []
            for i in range(n):
                off = struct.unpack_from('<I', e, p)[0]
                p += 4
                size = 0
                if i:
                    size = struct.unpack_from('<I', e, p)[0]
                    p += 8
                chr_, pos = e[p], e[p + 1]
                p += 3
                lst.append((off * 4, size * 4, chr_, pos))
            out[start] = lst
        return out

    @staticmethod
    def crc(name):
        b = name.encode('utf-8')
        c = b[0] if b[0] < 128 else b[0] - 256
        for x in b[1:]:
            c = (c * 0x25 + (x if x < 128 else x - 256)) & 0xFFFFFFFF
        return c & 0x3FF

    def file(self, name):
        a, b = self.ids[self.crc(name)]
        if a == 0 and b == 0:
            return None
        off = (a & 0x3FFFFFF) * 2
        size = ((a >> 26) + (b & 0xFFFF) * 64) * 4
        if a & 1:
            index = off // 4 - self.extra_start
            for o, s, chr_, pos in self.lists[index]:
                if pos < len(name) and ord(name[pos]) == chr_:
                    return self.bin[o:o + (s if s else size)]
            return None
        return self.bin[off:off + size]


class IdxPak:
    """name.idx + name.pak: files by index."""

    def __init__(self, idx, pak):
        self.files = []
        n = (len(idx) - 4) // 6
        for i in range(n):
            a1 = struct.unpack_from('<I', idx, 4 + i * 6)[0]
            if a1 & 7:
                if i != n - 1:
                    self.files.append(None)
                continue
            a2 = struct.unpack_from('<I', idx, 4 + (i + 1) * 6)[0] if i + 1 < n else a1
            ab1 = ((a1 << 5) & 0xFFFFFFFF) >> 8
            ab2 = ((a2 << 5) & 0xFFFFFFFF) >> 8
            self.files.append(pak[ab1 << 2:ab2 << 2])


def open_rom(path):
    nds = Nds(path)
    arc = Archive(nds.file('master/pc.idx'), nds.file('master/pc.bin'))
    return nds, arc


def idxpak(arc, idx_name, pak_name):
    return IdxPak(arc.file(idx_name), arc.file(pak_name))


if __name__ == '__main__':
    nds, arc = open_rom(sys.argv[1])
    print('NitroFS files', len(nds.paths))
    for p in sorted(nds.paths)[:40]:
        print('  ', p)
    sysdata = idxpak(arc, 'system/rom/sysdata_rom.idx', 'system/rom/sysdata.pak')
    print('sysdata files', len(sysdata.files), [len(f) if f else None for f in sysdata.files[:12]])
