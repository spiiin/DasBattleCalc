"""FFTA (USA) Fight targeting: which tiles a unit can attack.

Read from the ROM (notes.md, "Fight range") and checked against the
game's own tile rule (range_probe.lua): python reach.py
"""
import struct

EW = open('ewram.bin', 'rb').read()
MAP = EW[0x7F10:0x7F20]
TILES, STRIDE = struct.unpack_from('<I', MAP, 4)[0] - 0x02000000, MAP[8]
W, H = MAP[0xD], MAP[0xF]


def height(hmap, x, y):
    return hmap.get((x, y), EW[TILES + (y * STRIDE + x) * 2]) if 0 <= x < W and 0 <= y < H else 0


def flags(x, y):
    return EW[TILES + (y * STRIDE + x) * 2 + 1]


def can_fight(kind, rng, cx, cy, tx, ty, hmap):
    """0x0809FEF0: the tile exists, has no flag 0x01 / 0x08 and is not
    the attacker's; bows (13, 14) and guns (19): |dx| + |dy| <= range;
    other weapons 0x0812E1A8: dh = target - attacker height."""
    if height(hmap, tx, ty) == 0 or flags(tx, ty) & 0x09 or (tx, ty) == (cx, cy):
        return False
    d = abs(tx - cx) + abs(ty - cy)
    if kind in (13, 14, 19):
        return d <= rng
    h0 = height(hmap, cx, cy)
    dh = height(hmap, tx, ty) - h0
    if kind == 15:                       # spears
        if d <= 1:
            return -4 <= dh <= 3
        if d != 2 or (tx != cx and ty != cy):
            return False
        m = height(hmap, (cx + tx) // 2, (cy + ty) // 2) - h0   # the tile between
        lo = {0: -2, 1: -1, 2: 1, 3: 2}.get(m, -3 if m < 0 else 99)
        return lo <= dh <= 2
    return d <= 1 and -3 <= dh <= 2


if __name__ == '__main__':
    cases = {
        'sword': (1, 1, {(8, 4): 13, (7, 5): 12, (7, 3): 7}),
        'sword4': (1, 1, {(7, 3): 6, (7, 5): 13}),
        'spear': (15, 2, {(8, 4): 11, (9, 4): 12, (7, 5): 12, (7, 6): 10}),
        'bow': (13, 5, {}),
        'gun': (19, 8, {}),
    }
    bad = total = 0
    seen = {}
    for line in open('range_probe_log.txt'):
        name, tx, ty, _, _, res = line.split()
        tx, ty, res = int(tx), int(ty), int(res)
        kind, rng, hmap = cases[name]
        got = can_fight(kind, rng, 7, 4, tx, ty, hmap)
        seen.setdefault(name, set()).add((tx, ty))
        total += 1
        if got != bool(res):
            bad += 1
            print('FAIL', name, (tx, ty), 'game', res, 'model', got)
    # tiles the game did not check must be out of reach in the model too
    for name, (kind, rng, hmap) in cases.items():
        extra = [(x, y) for x in range(W) for y in range(H)
                 if (x, y) not in seen.get(name, ()) and can_fight(kind, rng, 7, 4, x, y, hmap)]
        if extra:
            bad += 1
            print('FAIL', name, 'model allows unchecked tiles', extra)
    print(f'{total} tiles checked by the game, mismatches: {bad}')
