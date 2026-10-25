# The side of an attack along y: Ramza (slot 0) attacks Lezalas (slot 5,
# at 7, 3) with the cursor already on him; Ramza's record is moved to
# (7, 4) / (7, 2) (and back to 6, 3 as the control) and Lezalas turned to
# each facing; the game's hit % shows the side (front: class evade too,
# side: no class evade, back: only the accessory). Output: forecast6.txt.
import fcprobe as P

A, T = 0, 5
cases = []
for x, y in ((6, 3), (7, 4), (7, 2)):
    for f in range(4):
        cases.append(('at%d_%d_facing%d' % (x, y, f), [(A, 0x4F, x), (A, 0x50, y), (T, 0x51, f)]))
out = open('forecast6.txt', 'w')
P.restart()
for name, writes in cases:
    r = None
    for attempt in range(3):
        old = []
        for u, off, v in writes:
            a = P.rec(u) + off
            old.append((a, P.d.read(a, 1)))
            P.w8(a, v)
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
    line = '%s | %s | %d %d' % (name, ' '.join('%d:%x=%x' % w for w in writes), dmg, hit)
    print(line, flush=True)
    out.write(line + '\n')
out.close()
