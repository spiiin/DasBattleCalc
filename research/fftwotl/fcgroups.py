# Forecasts of abilities: Ramza (record 0) on Lezalas (record 5). Per
# group: write his secondary skillset and learned bits, go through Act >
# skillset > ability, close the help box, cursor to Lezalas, confirm;
# then the cases of the group (edits, circle + cross, read).
# Output research/fftwotl/forecast3.txt:
#   <ability id> | <case> | <unit>:<off>=<value> ... | dmg heal mpdmg hit
import struct, sys
import fcprobe as P
A, T = 0, 5
REC = P.rec
def fresh(sub, idx):
    # Act; the submenu: Attack, the primary skillset, the secondary one
    return (['Y', 'S', 'H', 'sleep:0.4'] + ['S'] * sub + ['H', 'sleep:0.6'] + ['S'] * idx +
            ['H', 'sleep:0.8', 'H', 'sleep:0.6', 'W', 'sleep:0.6', 'H', 'sleep:1.3'])
STD = [('base', [])]
def stats(key, off, vals): return [('%s%d' % (key, v), [(A, off, v, 1)]) for v in vals]
GROUPS = [
    # (ability id, secondary skillset, learned job index, submenu, index, cases)
    (1, 10, 5, 2, 0, STD + stats('ma', 0x3F, (1, 10, 25)) + stats('afa', 0x2D, (20, 90)) +
        [('tfa30', [(T, 0x2D, 30, 1)]), ('t_shell', [(T, 0x65, 0x10, 1)]), ('zodiac7', [(A, 0x09, 0x70, 1)]),
         ('t_undead', [(T, 0x62, 0x10, 1)])]),
    (15, 10, 5, 2, 14, STD + stats('ma', 0x3F, (10, 30)) + [('t_shell', [(T, 0x65, 0x10, 1)]),
         ('t_undead', [(T, 0x62, 0x10, 1)]), ('t_weak_holy', [(T, 0x7A, 0x02, 1)])]),
    (144, 7, 2, 2, 6, STD + stats('pa', 0x3E, (1, 20, 60)) + [('zodiac7', [(A, 0x09, 0x70, 1)]),
         ('zodiac5', [(A, 0x09, 0x50, 1)]), ('cev0', [(T, 0x4B, 0, 1)]), ('back', [(T, 0x51, 3, 1)]),
         ('t_protect', [(T, 0x65, 0x20, 1)]), ('t_defending', [(T, 0x62, 0x02, 1)])]),
    (142, 7, 2, 2, 4, STD + stats('pa', 0x3E, (20,))),
    (46, 16, 11, 2, 0, STD + stats('ma', 0x3F, (1, 20)) + [('tfa30', [(T, 0x2D, 30, 1)]),
         ('t_shell', [(T, 0x65, 0x10, 1)]), ('zodiac7', [(A, 0x09, 0x70, 1)]), ('zodiac5', [(A, 0x09, 0x50, 1)]),
         ('t_innocent', [(T, 0x66, 0x40, 1)])]),
    (368, 6, 1, 2, 0, STD + [('t_undead', [(T, 0x62, 0x10, 1)])]),
    (147, 0, 0, 1, 1, STD + stats('pa', 0x3E, (1, 20)) + [('zodiac7', [(A, 0x09, 0x70, 1)]),
         ('t_protect', [(T, 0x65, 0x20, 1)])]),
    (148, 0, 0, 1, 2, STD + stats('pa', 0x3E, (20,)) + [('cev0', [(T, 0x4B, 0, 1)])]),
]
only = [int(a) for a in sys.argv[1:]]
out = open('fc3.txt', 'a' if only else 'w')
for aid, sec, job, sub, idx, cases in GROUPS:
    if only and aid not in only:
        continue
    P.SETUP = [(REC(A) + 0xA3 + 3 * job, bytes([0xFF, 0xFF, 0xFF]))]
    if sec:
        P.SETUP.append((REC(A) + 0x13, bytes([sec])))
    P.FRESH = fresh(sub, idx)
    P.restart()
    for name, writes in cases:
        r = None
        for attempt in range(3):
            old = []
            for u, off, v, n in writes:
                a = REC(u) + off
                old.append((a, P.d.read(a, n)))
                (P.w16 if n == 2 else P.w8)(a, v)
            r = P.forecast(T)
            if r is not None:
                b = P.d.read(REC(T), P.SZ)
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
out.close()
