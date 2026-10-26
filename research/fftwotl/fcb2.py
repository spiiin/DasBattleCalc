# Forecasts in the second test battle (Gariland, Ganelon - record 16 - at
# its turn). The enemies stand far away (and a record moved next to him is
# not a target: the game keeps its own map of the units), so the target is
# Rosa (record 17, of the party) at 6, 12 - the D key's tile.
#   python fcb2.py --cursor      where the cursor goes for each d-pad key
#   python fcb2.py               the forecasts -> forecast10.txt
# Lines: "<ability id or 0> | <case> | <unit>:<off>=<value> ... | dmg heal mpdmg hit"
import sys, struct
import fcprobe as P

P.STATE = 'C:/rom/psx/PPSSPP/memstick/PSP/PPSSPP_STATE/fftwotl_test_battle2.ppst'
G, T = 16, 17
CX, CY = 0x093E189C, 0x093E18A4


def cursor():
    return P.d.read(CX, 1)[0], P.d.read(CY, 1)[0]


if '--cursor' in sys.argv:
    P.FRESH = ['Y', 'S', 'H', 'H', 'sleep:0.6', 'H', 'sleep:1.0']
    P.restart()
    print('targeting opens at', cursor())
    for k in 'WASD':
        P.keys([k, 'sleep:0.4'])
        print(k, '->', cursor())
    sys.exit(0)

MOVE = []
MP = [(P.rec(G) + 0x34, struct.pack('<H', 99)), (P.rec(G) + 0x36, struct.pack('<H', 99))]
STD = [('base', [])]
GROUPS = [
    # (ability id, setup, keys after Act, cases)
    (0, [], ['H', 'sleep:0.6', 'H', 'sleep:0.8'],
     STD + [('facing%d' % f, [(T, 0x51, f, 1)]) for f in range(4)] +
     [('pa10', [(G, 0x3E, 10, 1)]), ('zodiac0', [(G, 0x09, 0x00, 1)]), ('t_protect', [(T, 0x65, 0x20, 1)]),
      ('cev30', [(T, 0x4B, 30, 1)])]),
]
for aid, idx in ((16, 0), (28, 12), (29, 13), (30, 14)):
    GROUPS.append((aid, [(P.rec(G) + 0x13, bytes([11])), (P.rec(G) + 0xA3 + 18, bytes([0xFF, 0xFF, 0xFF]))],
                   ['S', 'S', 'H', 'sleep:0.6'] + ['S'] * idx + ['H', 'sleep:0.8', 'H', 'sleep:0.6'],
                   STD + [('ma10', [(G, 0x3F, 10, 1)]), ('tfa30', [(T, 0x2D, 30, 1)]),
                          ('t_undead', [(T, 0x62, 0x10, 1)])]))
only = [int(a) for a in sys.argv[1:] if not a.startswith('--')]
out = open('forecast10.txt', 'a' if only else 'w')
for aid, setup, keys, cases in GROUPS:
    if only and aid not in only:
        continue
    P.SETUP = MOVE + MP + setup
    P.FRESH = ['Y', 'S', 'H'] + keys + ['D', 'sleep:0.6', 'H', 'sleep:1.3']
    P.restart()
    for name, writes in cases:
        r = None
        for attempt in range(3):
            old = []
            for u, off, v, n in writes:
                a = P.rec(u) + off
                old.append((a, P.d.read(a, n)))
                (P.w16 if n == 2 else P.w8)(a, v)
            r = P.forecast(T)
            if r is not None:
                b = P.d.read(P.rec(T), P.SZ)
                heal, mpd = struct.unpack_from('<H', b, 0x1B8)[0], struct.unpack_from('<H', b, 0x1BA)[0]
            for a, bb in reversed(old):
                P.d.write(a, bb)
            if r is not None:
                break
            print('  (lost the forecast, restarting)', flush=True)
            P.restart()
        if r is None:
            print('%d %s: no forecast' % (aid, name), flush=True)
            continue
        line = '%d | %s | %s | %d %d %d %d' % (aid, name, ' '.join('%d:%x=%x' % (u, off, v) for u, off, v, n in writes),
                                             r[0], heal, mpd, r[1])
        print(line, flush=True)
        out.write(line + '\n')
        out.flush()
out.close()
