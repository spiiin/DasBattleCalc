# Throw and Jump against the game's forecast: Ramza (slot 0) gets the Ninja
# (Throw, skillset 20) or Dragoon (Jump, 18) set as the secondary with every
# ability learned; Lezalas (slot 5) is the target.
#   python fctj.py --throw   one restart per stocked item: the party's stock
#                            (0x092EABA0 + item id) holds only that item, so
#                            the Throw list has one entry
#   python fctj.py --jump    the weapon and the target's statuses varied
#   --items=22,100           Throw: only these items, appended
#   --shot                   only a screenshot after the menu keys (debug)
# Output: forecast7.txt (Throw), forecast8.txt (Jump); lines as fcvary.py.
import sys, struct
import fcprobe as P
from ppdbg import shot

A, T = 0, 5
INV = 0x092EABA0
THROWN = [122, 123, 124, 125, 126, 127, 2, 19, 22, 100]    # Shuriken .. Spear
JOBS = {'throw': (20, 15), 'jump': (18, 13)}                # skillset, learned job index
MODE = 'throw' if '--throw' in sys.argv else 'jump'
ss, job = JOBS[MODE]
BASE = [(P.rec(A) + 0x13, bytes([ss])), (P.rec(A) + 0xA3 + job * 3, bytes([0xFF, 0xFF, 0xFF]))]
# Act, the secondary set, its first entry, the help box, the cursor to Lezalas
P.FRESH = ['Y', 'S', 'H', 'S', 'S', 'H', 'sleep:0.8', 'H', 'sleep:0.8', 'H', 'sleep:0.6', 'W', 'sleep:0.6', 'H',
           'sleep:1.2']
if MODE == 'jump':
    # the Jump command opens the targeting at once (the help box first)
    P.FRESH = ['Y', 'S', 'H', 'S', 'S', 'H', 'sleep:0.8', 'H', 'sleep:0.6', 'W', 'sleep:0.6', 'H', 'sleep:1.2']


def stock_only(item):
    w = []
    for i in range(1, 316):
        if i in THROWN or i == item:
            w.append((INV + i, bytes([3 if i == item else 0])))
    return w


def run(cases, out_name, setup):
    out = open(out_name, 'a')
    P.SETUP = setup
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
            for a, b in reversed(old):
                P.d.write(a, b)
            if r is not None:
                break
            print('  (lost the forecast, restarting)', flush=True)
            P.restart()
        if r is None:
            print('  no forecast:', name, flush=True)
            continue
        dmg, hit, kind = r
        line = '%s | %s | %d %d' % (name, ' '.join('%d:%x=%x%s' % (u, off, v, '/2' if n == 2 else '')
                                                  for u, off, v, n in writes), dmg, hit)
        print(line, flush=True)
        out.write(line + '\n')
        out.flush()
    out.close()


if '--shot' in sys.argv:
    P.SETUP = BASE + (stock_only(122) if MODE == 'throw' else [])
    P.restart()
    import ctypes, time
    u = ctypes.windll.user32
    hs = []
    cb = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(
        lambda h, _: (hs.append(h) if ctypes.wstring_at(ctypes.create_unicode_buffer(256)) is not None and
                      u.GetWindowTextW(h, buf := ctypes.create_unicode_buffer(256), 256) and
                      buf.value.startswith('PPSSPP') else None) or True)
    u.EnumWindows(cb, 0)
    for h in hs:
        u.ShowWindow(h, 4)              # SW_SHOWNOACTIVATE: shown, no focus
    time.sleep(0.8)
    shot(P.d, 'shots/tj_%s.png' % MODE)
    for h in hs:
        u.ShowWindow(h, 7)              # minimized again
    sys.exit(0)

ONLY = [int(x) for a in sys.argv if a.startswith('--items=') for x in a[8:].split(',')]
if MODE == 'throw':
    if not ONLY:
        open('forecast7.txt', 'w').close()       # --items=a,b: append those only
    for item in (ONLY or THROWN):
        tag = 'item%d' % item
        cases = [(tag, [(T, 0x2D, 63, 1)])]          # a no-op write: Lezalas's Faith as it is
        if item == 122:
            cases += [(tag + '_t_protect', [(T, 0x65, 0x20, 1)]), (tag + '_sp10', [(A, 0x40, 10, 1)]),
                      (tag + '_cev50', [(T, 0x4B, 50, 1)]), (tag + '_t_charging', [(T, 0x62, 0x08, 1)])]
        if item == 125:
            cases += [(tag + '_t_weak_fire', [(T, 0x7A, 0x80, 1)]), (tag + '_t_absorb_fire', [(T, 0x77, 0x80, 1)])]
        # the stock is a count per item id: one item, so one list entry
        run(cases, 'forecast7.txt', BASE + stock_only(item))
else:
    cases = [('sword', [(T, 0x2D, 63, 1)]), ('spear', [(A, 0x20, 100, 2)]), ('bare', [(A, 0x20, 0xFF, 2)]),
             ('gungnir', [(A, 0x20, 277, 2)]), ('t_protect', [(T, 0x65, 0x20, 1)]),
             ('t_charging', [(T, 0x62, 0x08, 1)]), ('pa10', [(A, 0x3E, 10, 1)]), ('cev50', [(T, 0x4B, 50, 1)]),
             ('zodiac0', [(A, 0x09, 0x00, 1)]), ('t_weak_lightning', [(A, 0x20, 277, 2), (T, 0x7A, 0x40, 1)])]
    open('forecast8.txt', 'w').close()
    run(cases, 'forecast8.txt', BASE)
