"""FFTA (USA) basic attack ("Fight") model, read from the ROM.

Checked against the game's own preview (attack_probe.lua: RAM patches
before the preview of Marc -> Montblanc, the game's damage and hit chance
read at 0x0813023C / 0x0812C8C6). See notes.md, "Attack".

usage: python attack.py   (runs the recorded cases from the test save)
"""
import struct

ROM = open('rom.gba', 'rb').read()
ITEMS, JOBS = 0x51D180, 0x521A14

SIDE_DIV = {'front': 1, 'side': 2, 'back': 4}      # table 0x083A8444
DIR_VEC = [(0, 1), (-1, 0), (0, -1), (1, 0)]       # table 0x083A842C


def s8(b):
    return b - 256 if b >= 128 else b


def item(i):
    return ROM[ITEMS + 32 * i: ITEMS + 32 * i + 32]


def job_field(job, job2, field):
    for _ in range(16):
        e = ROM[JOBS + 52 * job: JOBS + 52 * job + 52]
        if e[5] == 255:
            job = job2
        elif e[5]:
            job = e[5]
        else:
            return e[field]
    return 0


class Unit:
    """The fields of a unit record (0x108 bytes) the attack uses."""

    def __init__(self, rec, x, y, facing):
        self.r = rec
        self.x, self.y, self.facing = x, y, facing    # wrapper +0x08>>5, +0x0C>>5, +0x1F

    def u16(self, o):
        return struct.unpack_from('<H', self.r, o)[0]

    def status(self, byte, bit):
        return self.r[byte] & bit != 0

    def items(self):
        return [i for i in struct.unpack_from('<5H', self.r, 0x2A) if i]

    def enemy(self):
        return self.u16(0x28) & 0x8000 != 0


def side_of(att, tgt):
    """0x0812C700: the first 90-degree quadrant around the target's
    facing (front, its left / right, back) that holds the attacker."""
    dx, dy = att.x - tgt.x, att.y - tgt.y
    for k, off in enumerate((0, -1, 1, 2)):
        vx, vy = DIR_VEC[(tgt.facing + off) % 4]
        if dx * vx >= 0 and dy * vy >= 0 and (abs(dy) <= abs(dx) if vx else abs(dx) <= abs(dy)):
            return ('front', 'side', 'side', 'back')[k]
    return 'front'


def evade(u):
    """0x0812C7B8: job +0x2A + items (none when Frog), 0..100."""
    e = job_field(u.r[5], u.r[7], 0x2A)
    if not u.status(0xE9, 0x01):
        e += sum(s8(item(i)[0x15]) for i in u.items())
    return max(0, min(100, e))


def can_evade(t):
    """0x0812C56C: KO (HP 0) and some statuses cannot evade."""
    return t.u16(0x18) != 0 and not any(t.status(b, m) for b, m in
                                        ((0xE8, 0x40), (0xE9, 0x80), (0xEA, 0x80), (0xEB, 0x04), (0xEC, 0x02)))


def hit_chance(att, tgt, support=0):
    """0x0812C7F4 / 0x0812EF94: the chance the preview shows."""
    if not can_evade(tgt):
        return 100
    e = evade(tgt) // SIDE_DIV[side_of(att, tgt)]
    e += -20 * tgt.status(0xE9, 0x04) - 10 * tgt.status(0xEB, 0x10) + 50 * att.status(0xE9, 0x04)
    e += {13: -50, 4: -15}.get(support, 0)                          # 0x0812C610
    hit = 100 - max(5, min(95, e))
    return 100 if tgt.status(0xEA, 0x02) else hit


def rolled_hit(att, tgt, support=0):
    """0x080A2846: the roll uses +10 for non-enemy attackers."""
    h = hit_chance(att, tgt, support)
    if tgt.u16(0x18) == 0:
        return 100
    return min(100, h + 10) if h > 0 and not att.enemy() else h


def power(att, weapon):
    """0x0812F5E0: weapon W.Atk (job +0x33 bare-handed) + W.Atk of the
    other non-weapon equipment; 0 when Frog."""
    if att.status(0xE9, 0x01):
        return 0
    p = s8(item(weapon)[0x10]) if weapon else ROM[JOBS + 52 * att.r[5] + 0x33]
    return p + sum(s8(item(i)[0x10]) for i in att.items() if not 1 <= item(i)[8] <= 19)


def scale(v, k):
    return v * k >> 8


def attack_value(att, weapon):
    """0x0812FD44: record W.Atk x statuses + power (mission % and support
    abilities: not modelled)."""
    a = att.u16(0x20)
    for byte, bit, k in ((0xE8, 0x80, 0x133), (0xE9, 0x01, 25), (0xE9, 0x40, 384), (0xEC, 0x08, 0x119), (0xEC, 0x10, 230)):
        if att.status(byte, bit):
            a = scale(a, k)
    return min(999, a + power(att, weapon))


def defense_value(tgt):
    """0x0812FDDC: record W.Def x statuses + equipment W.Def."""
    d = tgt.u16(0x22)
    for byte, bit, k in ((0xEB, 0x02, 358), (0xE8, 0x40, 460), (0xE9, 0x01, 25), (0xE9, 0x20, 358), (0xEC, 0x80, 358), (0xED, 0x01, 179)):
        if tgt.status(byte, bit):
            d = scale(d, k)
    if not tgt.status(0xE9, 0x01):
        d += sum(s8(item(i)[0x11]) for i in tgt.items())
    return min(999, d)


def damage(att, tgt, weapon, crit=False):
    """0x0812FE38 without the random part: (A - D/2) x power / 100,
    element affinity, x1.5 on a critical hit."""
    base = max(1, attack_value(att, weapon) - (defense_value(tgt) >> 1))
    d = max(1, base * power(att, weapon) // 100)
    element = item(weapon)[9] if weapon else 0
    aff = tgt.r[0x0C + element] if element < 9 else 1
    d = {0: d * 384 >> 8, 2: 0, 3: -d, 4: d >> 1}.get(aff, d)
    if crit:
        d = d * 384 >> 8
    if tgt.status(0xEC, 0x02):
        d = 0
    return d


def damage_range(d):
    """The real attack adds a whole number in [-d/10, d/10]."""
    k = abs(d) // 10
    return d - k, d + k


def crit_chance(att):
    """0x0812E0FC: job Evade (no items) / 10, +30 with +0xEA & 1."""
    c = job_field(att.r[5], att.r[7], 0x2A) // 10 + 30 * att.status(0xEA, 0x01)
    return max(0, min(100, c))


def roll_probability(p):
    """0x0812F1DC: success when rand%10000+1 <= 100p + rand%100. This is
    the naive chance; the two rands are consecutive LCG outputs and the
    real chance differs (roll_table.py: p 5 -> 6.70 %, 35 -> 40.94 %)."""
    return 0.0 if p <= 0 else 1.0 if p >= 100 else (100 * p + 49.5) / 10000


# ------------------------------------------------------------ checks

if __name__ == '__main__':
    ew = open('ewram.bin', 'rb').read()
    MARC, MONT = 0x80, 0x31D4
    recs = {'Marc': 0x80, 'Lunais': 0x2FC4, 'Euver': 0x30CC, 'Montblanc': 0x31D4, 'Judge': 0x32DC}

    def run(att_rec, tgt_patch=None, att_patch=None, facing=3, weapon=None):
        a = bytearray(ew[att_rec:att_rec + 0x108])
        t = bytearray(ew[MONT:MONT + 0x108])
        for o, v in (att_patch or {}).items():
            a[o] = v
        for o, v in (tgt_patch or {}).items():
            t[o] = v
        att, tgt = Unit(bytes(a), 7, 4, 1), Unit(bytes(t), 6, 4, facing)
        w = weapon if weapon is not None else next((i for i in att.items() if 1 <= item(i)[8] <= 19), 0)
        return damage(att, tgt, w), hit_chance(att, tgt)

    cases = [  # name, result of the model, (damage, hit) shown by the game
        ('base', run(MARC), (20, 65)),
        ('back', run(MARC, facing=1), (20, 92)),
        ('side0', run(MARC, facing=0), (20, 83)),
        ('side2', run(MARC, facing=2), (20, 83)),
        ('atk200', run(MARC, att_patch={0x20: 200}), (41, 65)),
        ('def50', run(MARC, tgt_patch={0x22: 50}), (26, 65)),
        ('tblind', run(MARC, tgt_patch={0xE9: 4}), (20, 85)),
        ('ablind', run(MARC, att_patch={0xE9: 4}), (20, 15)),
        ('protect', run(MARC, tgt_patch={0xEB: 2}), (15, 65)),
        ('e9_40', run(MARC, att_patch={0xE9: 0x40}), (34, 65)),
        ('tfrog', run(MARC, tgt_patch={0xE9: 1}), (33, 65)),
        ('e8_80', run(MARC, att_patch={0xE8: 0x80}), (25, 65)),
        ('eb_10', run(MARC, tgt_patch={0xEB: 0x10}), (20, 75)),
        ('euver', run(recs['Euver']), (15, 65)),
        ('lunais', run(recs['Lunais']), (10, 65)),
        ('lunais+sword', run(recs['Lunais'], weapon=1), (14, 65)),
        ('judge', run(recs['Judge']), (1, 65)),
        ('montblanc', run(recs['Montblanc']), (6, 65)),
    ]
    bad = 0
    for name, got, want in cases:
        ok = got == want
        bad += not ok
        print(f'{name:14} model {got}  game {want}  {"ok" if ok else "FAIL"}')
    m = Unit(ew[MARC:MARC + 0x108], 7, 4, 1)
    print('Marc crit chance', crit_chance(m), '% , rolled hit vs Montblanc', rolled_hit(m, Unit(ew[MONT:MONT + 0x108], 6, 4, 3)))
    print('FAIL', bad if bad else 'none')
