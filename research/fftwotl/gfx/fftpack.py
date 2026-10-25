"""Read files of FFT: WotL (PSP, ULUS10297) straight from the ISO (read only).

fftpack.bin: u32 count, u32 ?, then u32 start offset of file i (1-based) at 8 + 4*(i-1);
file i ends where file i+1 starts. No compression at the pack level.
"""
import os, struct, xml.etree.ElementTree as ET

ISO = r'C:\rom\psx\rom\Final_Fantasy_Tactics_The_War_Of_The_Lions_USA_PSP-pSyPSP.iso'
FFTPACK_LBA, FFTPACK_SIZE = 0x5840, 220930048
BOOT_LBA = 0x1FDB0
BOOT_RAM = 0x08803FAC          # RAM address = BOOT.BIN offset + this
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
NAMES_XML = os.path.join(HERE, '..', 'ext', 'FFTPatcher', 'PatcherLib', 'Resources', 'FFTPackFiles.xml')

_iso = None
def iso():
    global _iso
    if _iso is None: _iso = open(ISO, 'rb')
    return _iso

def read_iso(off, n):
    f = iso(); f.seek(off); return f.read(n)

_hdr = None
def header():
    global _hdr
    if _hdr is None:
        b = read_iso(FFTPACK_LBA * 2048, 8)
        count, unk = struct.unpack('<II', b)
        tab = read_iso(FFTPACK_LBA * 2048 + 8, 4 * count)
        _hdr = (count, unk, struct.unpack('<%dI' % count, tab))
    return _hdr

def file_range(i):
    """(offset in fftpack.bin, size) of file i (1-based)."""
    count, _, tab = header()
    start = tab[i - 1]
    end = tab[i] if i < count else FFTPACK_SIZE
    return start, end - start

def get(i):
    start, size = file_range(i)
    return read_iso(FFTPACK_LBA * 2048 + start, size)

_names = None
def names():
    global _names
    if _names is None:
        _names = {int(e.get('entry')): e.get('name') for e in ET.parse(NAMES_XML).getroot().iter('file')}
    return _names

def find(name):
    for k, v in names().items():
        if v.upper() == name.upper(): return k
    raise KeyError(name)

_boot = None
def boot():
    global _boot
    if _boot is None:
        # BOOT.BIN size from the ISO directory is not needed: read 16 MB, enough for all tables
        _boot = read_iso(BOOT_LBA * 2048, 0x400000)
    return _boot

def save(name, data):
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name); open(p, 'wb').write(data); return p

if __name__ == '__main__':
    count, unk, tab = header()
    print('count', count, 'unk', hex(unk), 'first offsets', [hex(x) for x in tab[:4]])
    nonempty = sum(1 for i in range(1, count + 1) if file_range(i)[1] > 0)
    print('non-empty files', nonempty)
    for i in (1, 2, 3, 33, 51, 58, 76, 77, 78, 2143, 2184):
        s, n = file_range(i); d = get(i)
        print(i, names().get(i), hex(s), n, d[:16].hex())
