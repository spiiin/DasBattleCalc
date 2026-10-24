"""FFTA2 text: the charset (from Rurusachi/ffta2-editor, MIT) and string tables.

python ffta2_text.py rom.nds        prints a few names from JD_message
charset.json is built from the editor's FFTA2Charset.java by
python ffta2_text.py --charset FFTA2Charset.java
"""
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BS = chr(92)


def build_charset(java_path):
    src = open(java_path, encoding='utf-8').read()
    pat = r'decodingMap\.put\((0x[0-9A-Fa-f]+),\s*"((?:[^"' + BS + BS + r']|' + BS + BS + r'.)*)"\)'
    m = {}
    for k, v in re.findall(pat, src):
        s = v
        s = s.replace(BS + BS, '\x00BS\x00').replace(BS + '"', '"').replace(BS + 'n', '\n').replace(BS + 'r', '\r')
        s = re.sub(BS + BS + 'u([0-9a-fA-F]{4})', lambda mm: chr(int(mm.group(1), 16)), s)
        s = s.replace('\x00BS\x00', BS)
        m[int(k, 16)] = s
    json.dump({str(k): v for k, v in m.items()}, open(os.path.join(HERE, 'charset.json'), 'w', encoding='utf-8'),
              ensure_ascii=False, indent=0)
    return m


def load_charset():
    return {int(k): v for k, v in json.load(open(os.path.join(HERE, 'charset.json'), encoding='utf-8')).items()}


CS = None


def decode(b):
    global CS
    if CS is None:
        CS = load_charset()
    out = []
    i = 0
    while i < len(b):
        v = 0
        s = None
        for j in range(4):
            if i + j >= len(b):
                break
            v = (v << 8) | b[i + j]
            s = CS.get(v)
            if s is not None:
                i += j + 1
                break
        if s is None:
            out.append('<%02X>' % b[i])
            i += 1
            continue
        if s.startswith(BS) and s.endswith('%02X' + BS):
            s = s % b[i]
            i += 1
        if s != '\r':
            out.append(s)
    return ''.join(out)


def table(data):
    """A JD_message string table: i16 count, then (i32 length, u32 offset, u16 lines)."""
    n = struct.unpack_from('<h', data, 0)[0]
    res = []
    for k in range(n):
        ln, off = struct.unpack_from('<iI', data, 2 + k * 10)
        res.append(decode(data[off:off + ln]))
    return res


def messages(arc, idxpak):
    """JD_message tables: 0 characters, 1 jobs, 3 abilities, 11 items, ..."""
    msg = idxpak(arc, 'system/rom/JD_message_rom_0.idx', 'system/rom/JD_message_0.pak')
    return {i: table(f) for i, f in enumerate(msg.files) if f}


if __name__ == '__main__':
    if sys.argv[1] == '--charset':
        print(len(build_charset(sys.argv[2])), 'characters')
        sys.exit(0)
    sys.path.insert(0, HERE)
    import ffta2_rom as fr
    nds, arc = fr.open_rom(sys.argv[1])
    names = messages(arc, fr.idxpak)
    print('jobs', names[1][:16])
    print('jobs 25 35 45 89 135:', [names[1][i] for i in (25, 35, 45, 89, 135) if i < len(names[1])])
    print('characters', names[0][:12])
    print('items', names[11][:12])
    print('abilities', names[3][:8])
    print('Luso / Gully:', decode(bytes([0x0d, 0x30, 0x2e, 0x2a])), decode(bytes([0x08, 0x30, 0x27, 0x27, 0x34])))
