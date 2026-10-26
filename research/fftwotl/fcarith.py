# Arithmeticks in the game (the first battle): Ramza gets the set (skillset
# 21, job 16) as the secondary and the Black Magicks learned (job 6).
#   python fcarith.py --shots    screenshots after each step of the menu
import sys, time, ctypes
import fcprobe as P
from ppdbg import shot

A = 0
for a in sys.argv:
    if a.startswith('--state='):
        P.STATE = a[8:]                 # another battle's state
    if a.startswith('--unit='):
        A = int(a[7:])                  # the record of the unit at its turn
OUT = ([a[6:] for a in sys.argv if a.startswith('--out=')] or ['arith1.txt'])[0]
SETUP = [(P.rec(A) + 0x13, bytes([21])), (P.rec(A) + 0xA3 + 16 * 3, bytes([0xFF, 0xFF, 0xFF])),
         (P.rec(A) + 0xA3 + 6 * 3, bytes([0xFF, 0xFF, 0xFF]))]


def windows():
    u = ctypes.windll.user32
    hs = []

    def cb(h, _):
        buf = ctypes.create_unicode_buffer(256)
        u.GetWindowTextW(h, buf, 256)
        if buf.value.startswith('PPSSPP') and u.IsWindowVisible(h):
            hs.append(h)
        return True
    u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(cb), 0)
    return hs


def snap(name):
    u = ctypes.windll.user32
    hs = windows()
    for h in hs:
        u.ShowWindow(h, 4)              # shown, no focus
    time.sleep(0.8)
    shot(P.d, 'shots/%s.png' % name)
    for h in hs:
        u.ShowWindow(h, 7)              # minimized again


if '--shots' in sys.argv:
    P.SETUP = SETUP
    P.FRESH = ['Y', 'S', 'H', 'sleep:0.4', 'S', 'S', 'H', 'sleep:0.8']
    P.restart()
    snap('ar1')
    for i, k in enumerate(['H', 'H', 'H', 'H']):
        P.keys([k, 'sleep:1.0'])
        snap('ar%d' % (i + 2))
    sys.exit(0)

TILES, SIZE = 0x092E8530, 0x093EBB6C


def lit():
    h, w = P.d.read(SIZE, 2)
    lo = P.d.read(TILES, w * h * 8)
    return [(t % w, t // w) for t in range(w * h) if lo[t * 8 + 5] & 0x40]


if '--shots2' in sys.argv:
    P.SETUP = SETUP
    # Act, Arithmeticks, (help) CT, (help) Prime, (help) Fire
    P.FRESH = ['Y', 'S', 'H', 'sleep:0.4', 'S', 'S', 'H', 'sleep:0.8', 'H', 'sleep:0.8', 'H', 'sleep:0.8',
               'H', 'sleep:0.8', 'H', 'sleep:0.8', 'H', 'sleep:0.8']
    P.restart()
    print('before Fire', lit())
    P.keys(['H', 'sleep:1.2'])
    snap('ar6')
    print('after Fire', lit())
    P.keys(['H', 'sleep:1.2'])
    snap('ar7')
    print('after one more', lit())
    sys.exit(0)

ALG = ['CT', 'Level', 'EXP', 'Height']
NUM = ['Prime', '5', '4', '3']


def menu(alg, num):
    # Act, Arithmeticks, (help) the algorithm, (help) the number, (help) -> the magick list
    return (['Y', 'S', 'H', 'sleep:0.4', 'S', 'S', 'H', 'sleep:0.8', 'H', 'sleep:0.8'] + ['S'] * alg +
            ['H', 'sleep:0.8', 'H', 'sleep:0.8'] + ['S'] * num + ['H', 'sleep:0.8', 'H', 'sleep:0.8'])


def targets(spell_idx):
    """mark every record, pick the magick, read which records the game filled"""
    for i in range(21):
        P.d.write(P.rec(i) + 0x1DC, bytes([0xEE]))
    P.keys(['S'] * spell_idx + ['H', 'sleep:1.5'])
    res = []
    for i in range(21):
        b = P.d.read(P.rec(i), P.SZ)
        if b[0x1DC] != 0xEE:
            res.append((i, struct.unpack_from('<H', b, 0x1B6)[0], struct.unpack_from('<H', b, 0x1B8)[0], b[0x1DC]))
    return res


if '--try' in sys.argv:
    import struct
    a, n = int(sys.argv[2]), int(sys.argv[3])
    P.SETUP = SETUP
    P.FRESH = menu(a, n)
    P.restart()
    h, w = P.d.read(SIZE, 2)
    before = P.d.read(TILES, w * h * 8)
    print(ALG[a], NUM[n], targets(0))
    after = P.d.read(TILES, w * h * 8)
    for i in range(len(before)):
        if before[i] != after[i]:
            print('tile', (i // 8) % w, (i // 8) // w, 'byte', i % 8, hex(before[i]), '->', hex(after[i]))
    snap('ar_try')
    sys.exit(0)

if '--sweep' in sys.argv:
    import struct
    # every algorithm x number with Fire: the targeted tiles (byte 5 bit
    # 0x80), the forecast the game fills (its first target), then Perform
    # and every unit's HP before / after -> arith1.txt
    start = int(([x[8:] for x in sys.argv if x.startswith('--start=')] or ['0'])[0])     # resume: alg * 4 + num
    out = open(OUT, 'a' if start or OUT != 'arith1.txt' else 'w')
    for a in range(4):
        for n in range(4):
            stop = int(([x[7:] for x in sys.argv if x.startswith('--stop=')] or ['16'])[0])
            if a * 4 + n < start or a * 4 + n >= stop:
                continue
            P.SETUP = SETUP
            P.FRESH = menu(a, n)
            P.restart()
            hp0 = [struct.unpack_from('<H', P.d.read(P.rec(i) + 0x30, 2))[0] for i in range(21)]
            fc = targets(0)
            h, w = P.d.read(SIZE, 2)
            lo = P.d.read(TILES, w * h * 8)
            tiles = ['%d,%d' % (t % w, t // w) for t in range(w * h) if lo[t * 8 + 5] & 0x80]
            P.keys(['H', 'sleep:1.0', 'H', 'sleep:%d' % (8 + 2 * len(tiles))])
            hp1 = [struct.unpack_from('<H', P.d.read(P.rec(i) + 0x30, 2))[0] for i in range(21)]
            dmg = ['%d:%d' % (i, hp0[i] - hp1[i]) for i in range(21) if hp0[i] != hp1[i]]
            line = '%s | %s | tiles %s | forecast %s | hp %s' % (ALG[a], NUM[n], ' '.join(tiles),
                                                                 ' '.join('%d:%d/%d' % (r[0], r[1], r[3]) for r in fc),
                                                                 ' '.join(dmg))
            print(line, flush=True)
            out.write(line + '\n')
            out.flush()
    out.close()
    sys.exit(0)
