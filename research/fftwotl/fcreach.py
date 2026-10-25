# The tiles the game highlights for Attack (its reach), against the model.
#   python fcreach.py --find     the tile bytes that change when the targeting
#                                opens (to learn which flag marks the reach)
#   python fcreach.py            per weapon in Ramza's right hand: the
#                                highlighted tiles -> reach1.txt
# The state: the first battle (Ramza at 6, 3 on the bridge; heights 9..11
# around, lower ground below). Keys through the debugger: menu, Act,
# Attack, the help box -> the targeting with the reach shown.
import sys, struct, time
import fcprobe as P

A = 0
for a in sys.argv:
    if a.startswith('--state='):
        P.STATE = a[8:]                 # another battle's state
    if a.startswith('--unit='):
        A = int(a[7:])                  # the record of the unit at its turn
OUT = ([a[6:] for a in sys.argv if a.startswith('--out=')] or ['reach1.txt'])[0]
TILES = 0x092E8530
SIZE = 0x093EBB6C
OPEN = ['Y', 'S', 'H', 'H', 'sleep:0.6', 'H', 'sleep:1.0']      # up to the targeting (the help box closed)
P.FRESH = []


def tiles():
    h, w = P.d.read(SIZE, 2)
    return w, h, P.d.read(TILES, w * h * 8), P.d.read(TILES + 0x800, w * h * 8)


if '--find' in sys.argv:
    P.restart()
    w, h, lo0, up0 = tiles()
    P.keys(OPEN)
    w, h, lo1, up1 = tiles()
    for name, a, b in (('lower', lo0, lo1), ('upper', up0, up1)):
        for i in range(len(a)):
            if a[i] != b[i]:
                t = i // 8
                print(name, 'tile', t % w, t // w, 'byte', i % 8, hex(a[i]), '->', hex(b[i]))
    sys.exit(0)



WEAPONS = [22, 0xFF, 99, 119, 83, 77, 71, 92, 95]   # sword, bare, javelin, cloth, longbow, bowgun, pistol, harp, book
FLAG_BYTE, FLAG_MASK = 5, 0x40                      # --find: byte 5 bit 0x40 = highlighted
POS = [tuple(int(v) for v in a[6:].split(',')) for a in sys.argv if a.startswith('--pos=')] or [(6, 3)]
WSEL = [int(v, 0) for a in sys.argv if a.startswith('--weapons=') for v in a[10:].split(',')]
WEAPONS = WSEL or WEAPONS
out = open(OUT, 'a' if '--append' in sys.argv else 'w')
for x, y in POS:
    for wid in WEAPONS:
        P.SETUP = [(P.rec(A) + 0x20, struct.pack('<H', wid)), (P.rec(A) + 0x4F, bytes([x, y]))]
        P.restart()
        P.keys(OPEN)
        w, h, lo, up = tiles()
        lit = [(t % w, t // w) for t in range(w * h) if lo[t * 8 + FLAG_BYTE] & FLAG_MASK]
        lit_up = [(t % w, t // w) for t in range(w * h) if up[t * 8 + FLAG_BYTE] & FLAG_MASK]
        line = 'at %d,%d | weapon %d | %s | upper %s' % (x, y, wid, ' '.join('%d,%d' % p for p in lit),
                                                       ' '.join('%d,%d' % p for p in lit_up))
        print(line, flush=True)
        out.write(line + '\n')
out.close()
