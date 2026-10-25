# Vary probe: Ramza attacks Lezalas (the forecast on screen); each case
# writes bytes of the unit records, re-triggers the forecast, restores.
# Output: research/fftwotl/fc1.txt, one case per line:
#   <name> | <unit>:<off>=<value>[/2 for u16] ... | dmg hit
import struct, sys
import fcprobe as P
A, T = 0, 5           # Ramza, Lezalas
cases = []
for pa in (1, 3, 9, 15, 20, 40):
    cases.append(('pa%d' % pa, [(A, 0x3E, pa, 1)]))
for z in range(13):
    cases.append(('zodiac%d' % z, [(A, 0x09, z << 4, 1)]))
cases.append(('female', [(A, 0x06, 0x40, 1)]))
for z in (3, 9):                        # opposite of Capricorn: Cancer; same sex / other sex
    cases.append(('opp%d_male' % z, [(T, 0x09, z << 4, 1)]))
    cases.append(('opp%d_female' % z, [(T, 0x09, z << 4, 1), (T, 0x06, 0x40, 1)]))
# weapons in the right hand (item id, u16): dagger, ninja blade, knight sword, katana, axe, rod, staff, flail,
# gun, crossbow, bow, instrument, book, polearm, pole, bag, cloth, fell sword, Excalibur, bare hands
for it in (1, 0x0A, 0x24, 0x2A, 0x38, 0x3F, 0x46, 0x4D, 0x4F, 0x5A, 0x60, 0x6C, 0x6F, 0x74, 0x78, 0x7B, 0x7F, 0x11E,
           0x22, 0xFF):
    cases.append(('item%x' % it, [(A, 0x20, it, 2)]))
for br in (10, 50, 97):
    cases.append(('ksword_br%d' % br, [(A, 0x20, 0x24, 2), (A, 0x2B, br, 1)]))
    cases.append(('bare_br%d' % br, [(A, 0x20, 0xFF, 2), (A, 0x2B, br, 1)]))
cases.append(('fell_fa20', [(A, 0x20, 0x11E, 2), (A, 0x2D, 20, 1)]))
# statuses: target byte 0x62 + k
for k, bit, name in ((3, 0x20, 'protect'), (2, 0x04, 'chicken'), (2, 0x02, 'frog'), (4, 0x10, 'sleep'),
                     (0, 0x08, 'charging'), (0, 0x02, 'defending'), (2, 0x80, 'oil'), (4, 0x20, 'charm'),
                     (1, 0x20, 'blind_t'), (4, 0x04, 'dontact'), (3, 0x02, 'stop')):
    cases.append(('t_' + name, [(T, 0x62 + k, bit, 1)]))
for k, bit, name in ((2, 0x08, 'berserk'), (1, 0x20, 'blind'), (2, 0x10, 'invisible'), (2, 0x02, 'frog')):
    cases.append(('a_' + name, [(A, 0x62 + k, bit, 1)]))
# target evades in the record: C-EV, shields, accessory; facing
for cev in (0, 5, 30, 69, 70):
    cases.append(('cev%d' % cev, [(T, 0x4B, cev, 1)]))
cases.append(('sev0', [(T, 0x49, 0, 1), (T, 0x4A, 0, 1)]))
cases.append(('aev25', [(T, 0x48, 25, 1)]))
for f in range(4):
    cases.append(('facing%d' % f, [(T, 0x51, f, 1)]))
cases.append(('t_elem_weak_dark', [(A, 0x20, 0x100, 2), (T, 0x7A, 0x01, 1)]))
cases.append(('t_elem_half_dark', [(A, 0x20, 0x100, 2), (T, 0x79, 0x01, 1)]))
cases.append(('t_elem_absorb_dark', [(A, 0x20, 0x100, 2), (T, 0x77, 0x01, 1)]))
cases.append(('a_strengthen_dark', [(A, 0x20, 0x100, 2), (A, 0x7B, 0x01, 1)]))
MAGIC = '--magic' in sys.argv
if '--supports' in sys.argv:
    # the record's ability bit masks (+0x95..): Attack Boost, Defense Boost,
    # Concentration, Brawler (bare hands), Doublehand, Parry, Reflexes
    cases = [('a_attackboost', [(A, 0x9A, 0x10, 1)]), ('t_defenseboost', [(T, 0x9A, 0x08, 1)]),
             ('a_concentration', [(A, 0x9A, 0x01, 1)]), ('a_brawler_bare', [(A, 0x9B, 0x20, 1), (A, 0x20, 0xFF, 2)]),
             ('a_doublehand', [(A, 0x9B, 0x02, 1)]), ('t_parry', [(T, 0x98, 0x40, 1)]),
             ('t_reflexes', [(T, 0x98, 0x10, 1)]), ('a_attackboost_id_only', [(A, 0x16, 0x1D1, 2)])]
only = [a for a in sys.argv[1:] if not a.startswith('--')]
if MAGIC:
    # Ramza casts Fire on Lezalas: Black Magicks as the secondary skillset, every spell learned
    P.SETUP = [(P.rec(A) + 0x13, bytes([11])), (P.rec(A) + 0xA3 + 18, bytes([0xFF, 0xFF, 0xFF]))]
    P.FRESH = ['Y', 'S', 'H', 'S', 'S', 'H', 'sleep:0.8', 'H', 'sleep:0.8', 'H', 'sleep:0.6', 'W', 'sleep:0.6', 'H',
               'sleep:1.2']
    cases = []
    for ma in (1, 4, 10, 25):
        cases.append(('ma%d' % ma, [(A, 0x3F, ma, 1)]))
    for fa in (0, 30, 70, 100):
        cases.append(('afa%d' % fa, [(A, 0x2D, fa, 1)]))
        cases.append(('tfa%d' % fa, [(T, 0x2D, fa, 1)]))
    for z in (0, 4, 5, 7, 9):
        cases.append(('zodiac%d' % z, [(A, 0x09, z << 4, 1)]))
    for k, bit, name in ((3, 0x10, 'shell'), (4, 0x80, 'faith'), (4, 0x40, 'atheist'), (3, 0x20, 'protect'),
                         (2, 0x80, 'oil'), (4, 0x10, 'sleep'), (0, 0x08, 'charging'), (0, 0x02, 'defending')):
        cases.append(('t_' + name, [(T, 0x62 + k, bit, 1)]))
    cases.append(('a_faith', [(A, 0x66, 0x80, 1)]))
    cases.append(('t_weak_fire', [(T, 0x7A, 0x80, 1)]))
    cases.append(('t_half_fire', [(T, 0x79, 0x80, 1)]))
    cases.append(('t_absorb_fire', [(T, 0x77, 0x80, 1)]))
    cases.append(('t_cancel_fire', [(T, 0x78, 0x80, 1)]))
    cases.append(('cev50', [(T, 0x4B, 50, 1)]))
out = open('fc2.txt' if MAGIC else ('fc4.txt' if '--supports' in sys.argv else 'fc1.txt'), 'a' if only else 'w')
P.restart()
for name, writes in cases:
    if only and name not in only:
        continue
    for attempt in range(3):
        old = []
        for u, off, v, n in writes:
            a = P.rec(u) + off
            old.append((a, P.d.read(a, n)))
            (P.w16 if n == 2 else P.w8)(a, v)
        r = P.forecast(T)
        for a, b in reversed(old):
            P.d.write(a, b)
        if r is not None:
            break
        print('  (lost the forecast, restarting)', flush=True)
        P.restart()
    if r is None:
        continue
    dmg, hit, kind = r
    line = '%s | %s | %d %d' % (name, ' '.join('%d:%x=%x%s' % (u, off, v, '/2' if n == 2 else '') for u, off, v, n in writes), dmg, hit)
    print(line, flush=True)
    out.write(line + '\n')
out.close()
