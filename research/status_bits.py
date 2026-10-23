"""Which status bit (+0xE8..+0xED) each status effect kind sets.

Setters 0x080CDxxx..0x080CExxx: one per bit, `(unit, on)` clears the bit and
sets it when on != 0. Kind handlers (EFFECT_KINDS +0, 0x083A87B0) call them
with `mov r1, #1` (set) or `#0` (clear). The abilities using a kind name it.
usage: python status_bits.py  -> status_kinds.txt
"""
import re
import struct
import subprocess

ROM = open('rom.gba', 'rb').read()
KT, EF, AB = 0x3A87B0, 0x553E70, 0x55187C
names = [l.split(' ', 1)[1] if ' ' in l else '' for l in open('ability_names.txt').read().split('\n')]


def dis(a, b):
    out = subprocess.run(['python', 'thumb.py', 'rom.gba', hex(a), hex(b)], capture_output=True, text=True).stdout
    return [l.split(None, 2) for l in out.splitlines() if len(l.split(None, 2)) == 3]


# setters: address -> (byte, bit)
setters = {}
cur = None
for a, _, t in dis(0x080CDCA4, 0x080CE400):
    if t.startswith('push {lr}'):
        cur = [int(a, 16), None, []]
    if cur is None:
        continue
    m = re.match(r'add r\d, #(\d+)', t)
    if m and cur[1] is None:
        cur[1] = int(m.group(1))
    m = re.match(r'mov r\d, #(\d+)', t)
    if m:
        cur[2].append(int(m.group(1)))
    if t.startswith('orr') and cur[1] and 0xE8 <= cur[1] <= 0xED and len(cur[2]) >= 2:
        setters[cur[0]] = (cur[1], cur[2][1])

# kinds used by status-only effects, and the abilities using them
kind_abilities = {}
for i in range(1, 420):
    e = ROM[AB + 28 * i: AB + 28 * i + 28]
    nid = struct.unpack_from('<H', e, 0)[0]
    if nid == 0 or nid >= len(names):
        continue
    for k in e[0x0C:0x10]:
        if k > 1:
            x = ROM[EF + 4 * k: EF + 4 * k + 4]
            kind = ROM[KT + 12 * x[1]: KT + 12 * x[1] + 12]
            if kind[4] == 0:
                kind_abilities.setdefault(x[1], []).append(names[nid])

rows = []
for kid, abilities in sorted(kind_abilities.items()):
    kind = ROM[KT + 12 * kid: KT + 12 * kid + 12]
    handler = struct.unpack_from('<I', kind, 0)[0] & ~1
    sets, clears = [], []
    last_r1 = None
    for a, _, t in dis(handler, handler + 0x100):
        m = re.match(r'mov r1, #(\d+)', t)
        if m:
            last_r1 = int(m.group(1))
        m = re.match(r'bl 0x([0-9a-f]+)', t)
        if m:
            target = int(m.group(1), 16)
            if target in setters:
                byte, bit = setters[target]
                (sets if last_r1 else clears).append(f'{byte:02X}&{bit:02X}')
        if t.startswith('bx') or t.startswith('pop {r4}') and False:
            break
    sign = '+' if kind[8] == 1 else '-'
    rows.append(f'{kid:02x} {sign} sets {",".join(sets) or "-"} clears {",".join(clears) or "-"} | {", ".join(sorted(set(abilities))[:6])}')
open('status_kinds.txt', 'w').write('\n'.join(rows))
print('\n'.join(rows))
