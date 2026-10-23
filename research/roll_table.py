"""The real chance of the roll 0x0812F1DC(p) for p = 0..100.

The roll takes two consecutive outputs of the game's LCG (0x08002804:
x = x * 0x41C64E6D + 0x3039, rand = bits 16..30): success when
rand2 % 10000 + 1 <= 100 p + rand1 % 100. The outputs are correlated, so
the chance is not (100 p + 49.5) / 10000: p 5 -> 6.70 %, 35 -> 40.94 %.
This averages over random seeds (a seed deep in a game is as good as
random) and prints the table for ffta_attack.das.
usage: python roll_table.py [samples]
"""
import sys

import numpy as np

A, C, M = np.uint64(0x41C64E6D), np.uint64(0x3039), np.uint64(0xFFFFFFFF)
n = int(sys.argv[1]) if len(sys.argv) > 1 else 50_000_000
s = np.random.default_rng(1).integers(0, 2 ** 32, size=n, dtype=np.uint64)
s1 = (s * A + C) & M
s2 = (s1 * A + C) & M
r1 = ((s1 << np.uint64(1)) & M) >> np.uint64(17)
r2 = ((s2 << np.uint64(1)) & M) >> np.uint64(17)
lhs = (r2 % 10000 + 1).astype(np.int64)
u = (r1 % 100).astype(np.int64)
table = []
for p in range(101):
    table.append(0.0 if p == 0 else 1.0 if p >= 100 else float(np.mean(lhs <= 100 * p + u)))
rows = [', '.join(f'{v:.4f}' for v in table[i:i + 10]) for i in range(0, 101, 10)]
print('let ROLL_CHANCE = fixed_array<float>(\n    ' + ',\n    '.join(rows) + ')')
