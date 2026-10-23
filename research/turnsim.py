"""FFTA turn-order model (read from the ROM, see notes.md) and its check
against a BizHawk log (long.lua).

usage: python turnsim.py rom.gba long_log.txt
"""
import struct
import sys

ITEM_TABLE = 0x0851D180      # 32 bytes per item, +0x14: signed speed bonus


class Unit:
    def __init__(self, rec, ct, rs, base_speed, status, items, b104, name_ptr):
        self.rec, self.ct, self.rs = rec, ct, rs
        self.base_speed, self.status, self.items = base_speed, status, items
        self.b104, self.name_ptr = b104, name_ptr

    def copy(self):
        return Unit(self.rec, self.ct, self.rs, self.base_speed, self.status, self.items, self.b104, self.name_ptr)


def item_speed(rom, item):
    return struct.unpack_from('<b', rom, ITEM_TABLE - 0x08000000 + item * 32 + 0x14)[0]


def speed(rom, u):
    """0x0812E368: base + equipment, then status halving / doubling."""
    s = u.base_speed + sum(item_speed(rom, i) for i in u.items if i)
    s = max(s, 0)
    st = u.status     # bytes +0xE8..+0xED
    if st[4] & 0x04 or st[2] & 0x02:
        s >>= 1
    if st[2] & 0x20:
        s <<= 1
    if st[2] & 0x40:
        s >>= 1
    return s


def eligible(rom, u):
    return not (u.status[0] & 0x40) and speed(rom, u) > 0 and not (u.status[5] & 0x40)


def tick(rom, units):
    """0x0809DF7C: every unit gains reserve + speed, then the excess over
    1000 (at most 500) is moved from CT into the reserve of everyone."""
    top = -8000
    for u in units:
        if eligible(rom, u):
            u.ct = u.ct + u.rs + speed(rom, u)
        else:
            u.ct = 0
        u.rs = 0
        top = max(top, u.ct)
    if top > 1000:
        e = min(top - 1000, 500)
        for u in units:
            d = u.ct - e
            if d < 0:
                u.rs, u.ct = u.ct, 0
            else:
                u.rs, u.ct = e, d


def next_actor(rom, units, guard=10000):
    """0x0809E05C: Quick first, else tick until someone eligible has
    CT > 999 and take the largest (CT + reserve) << 8 | byte +0x104."""
    for i, u in enumerate(units):
        if u.status[0] & 0x02 and eligible(rom, u):
            u.rs = 0x1000
            return i
    for _ in range(guard):
        if any(eligible(rom, u) and u.ct > 999 for u in units):
            break
        tick(rom, units)
    best, idx = -(1 << 31), -1
    for i, u in enumerate(units):
        key = ((u.ct + u.rs) if eligible(rom, u) else -100) << 8 | u.b104
        if key > best:
            best, idx = key, i
    return idx


def end_turn(u, moved, acted):
    """0x0809F8EC"""
    ct = u.ct - 500 - (200 if moved else 0) - (300 if acted else 0)
    u.ct, u.rs = max(ct, 0), 0


def parse_log(path):
    states = []
    cur = None
    for line in open(path):
        p = line.split()
        if p[0] == 'F':
            cur = (int(p[1]), [])
            states.append(cur)
        elif p[0] == 'U':
            st = bytes.fromhex(p[6])
            items = [int(x) for x in p[7].split(',')]
            cur[1].append(Unit(int(p[2], 16), int(p[3]), int(p[4]), int(p[5]), st, items, int(p[8]), int(p[9], 16)))
    return states


def same(a, b):
    return all(x.ct == y.ct and x.rs == y.rs for x, y in zip(a, b))


def main():
    rom = open(sys.argv[1], 'rb').read()
    states = parse_log(sys.argv[2])
    ticks_ok = ticks_bad = ends = other = hidden = 0
    for (fa, a), (fb, b) in zip(states, states[1:]):
        if len(a) != len(b):
            other += 1
            continue
        changed = [i for i in range(len(a)) if (a[i].ct, a[i].rs) != (b[i].ct, b[i].rs)]
        # a turn end touches one unit: CT drops by 500/700/800/1000, reserve -> 0
        if len(changed) == 1 and b[changed[0]].rs == 0:
            ends += 1
            continue
        sim = [u.copy() for u in a]
        actor = next_actor(rom, sim)
        game_actor = [i for i, u in enumerate(b) if u.ct >= 1000]
        if same(sim, b) and game_actor == [actor]:
            ticks_ok += 1
            continue
        # one turn may be missing from the log (it ended within the
        # sampling gap): try every way that turn could have ended
        found = None
        for moved, acted in [(1, 1), (0, 1), (1, 0), (0, 0)]:
            s2 = [u.copy() for u in sim]
            end_turn(s2[actor], moved, acted)
            a2 = next_actor(rom, s2)
            if same(s2, b):
                found = (moved, acted, a2)
                break
        if found:
            hidden += 1
            print(f'frames {fa}->{fb}: unlogged turn of unit {actor} (moved={found[0]} acted={found[1]}),'
                  f' then unit {found[2]}')
        else:
            ticks_bad += 1
            print(f'MISMATCH frames {fa}->{fb}')
            for x, y, s in zip(a, b, sim):
                print(f'  {x.rec:08x} spd {speed(rom, x):3}  {x.ct:5},{x.rs:4} -> game {y.ct:5},{y.rs:4}'
                      f'  model {s.ct:5},{s.rs:4}  st {x.status.hex()}')
    print(f'ticks ok {ticks_ok}, with an unlogged turn {hidden}, mismatched {ticks_bad}, turn ends {ends}, other {other}')


if __name__ == '__main__':
    main()
