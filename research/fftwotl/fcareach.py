# The tiles the game lights for abilities (their reach), against the model
# (the first battle; Ramza moved to a tile, as fcreach.py). Ramza gets the
# set as the secondary with every ability learned; the menu goes up to the
# targeting and the lit tiles (byte 5 bit 0x40) are read.
# Output reach3.txt: "at X,Y | ability ID | edits | x,y ... | upper ..."
# (edits as the forecasts': what the model's unit needs - the learned
# bytes for Jump).
import sys, struct
import fcprobe as P

A = 0
for a in sys.argv:
    if a.startswith('--state='):
        P.STATE = a[8:]                 # another battle's state
    if a.startswith('--unit='):
        A = int(a[7:])                  # the record of the unit at its turn
OUT = ([a[6:] for a in sys.argv if a.startswith('--out=')] or ['reach3.txt'])[0]
TILES, SIZE = 0x092E8530, 0x093EBB6C
INV = 0x092EABA0
HELP = ['sleep:0.8', 'H', 'sleep:1.0']


def act(sub, idx, extra=()):
    # Act; the submenu: Attack, Mettle, the secondary; the ability; the help box
    return ['Y', 'S', 'H', 'sleep:0.4'] + ['S'] * sub + ['H', 'sleep:0.6'] + ['S'] * idx + ['H'] + list(extra) + HELP


def learn(ss, job):
    return [(P.rec(A) + 0x13, bytes([ss])), (P.rec(A) + 0xA3 + job * 3, bytes([0xFF, 0xFF, 0xFF]))]


BASE = [(P.rec(A) + 0xA3, bytes([0xFF, 0xFF, 0xFF]))]      # every Mettle ability learned (the menu's order)
STOCK = [(INV + 122, bytes([3]))]                       # a Shuriken to throw
CASES = [
    # (ability id, setup, keys, edits for the model)
    (16, learn(11, 6), act(2, 0), ''),                  # Fire
    (28, learn(11, 6), act(2, 12), ''),                 # Poison (area 1, vertical 2)
    (102, learn(9, 4), act(2, 2), ''),                  # Aurablast (vertical 3, tolerance)
    (138, learn(7, 2), act(2, 0), ''),                  # Rend Helm (the weapon's range)
    (147, BASE, act(1, 1), ''),                           # Rush (Mettle)
    (148, BASE, act(1, 2), ''),                           # Stone
    (150, BASE, act(1, 4), ''),                           # Tailwind
    (152, BASE, act(1, 5), ''),                           # Chant (reach 1, vertical 3, tolerance)
    (382, learn(20, 15) + STOCK, act(2, 0, ['sleep:0.6', 'H']), ''),       # Throw: Shuriken, the list's entry
    (394, learn(18, 13), ['Y', 'S', 'H', 'sleep:0.4', 'S', 'S', 'H'] + HELP, '0:ca=ff 0:cb=ff 0:cc=ff'),  # Jump
]
POS = [tuple(int(v) for v in a[6:].split(',')) for a in sys.argv if a.startswith('--pos=')] or [(6, 3), (0, 3), (2, 9)]
only = [int(a) for a in sys.argv[1:] if not a.startswith('--')]
out = open(OUT, 'a' if '--append' in sys.argv else 'w')
for x, y in POS:
    for aid, setup, keys, edits in CASES:
        if only and aid not in only:
            continue
        P.SETUP = setup + [(P.rec(A) + 0x4F, bytes([x, y]))]
        P.FRESH = keys
        P.restart()
        h, w = P.d.read(SIZE, 2)
        lo = P.d.read(TILES, w * h * 8)
        up = P.d.read(TILES + 0x800, w * h * 8)
        lit = ['%d,%d' % (t % w, t // w) for t in range(w * h) if lo[t * 8 + 5] & 0x40]
        lit_up = ['%d,%d' % (t % w, t // w) for t in range(w * h) if up[t * 8 + 5] & 0x40]
        line = 'at %d,%d | ability %d | %s | %s | upper %s' % (x, y, aid, edits.replace('0:', '%d:' % A), ' '.join(lit),
                                                             ' '.join(lit_up))
        print(line[:150], flush=True)
        out.write(line + '\n')
        out.flush()
out.close()
