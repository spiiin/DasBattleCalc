"""Summary of live_probe.lua logs: hit rate, damage spread, crits, pushes.

usage: python live_stats.py live_fight.txt live_advice.txt ...
"""
import collections
import math
import sys


def load(path):
    rows = []
    for line in open(path):
        if line[:1].isdigit():
            p = line.split()
            rows.append(dict(zip(p[1::2], p[2::2])))
    return rows


for path in sys.argv[1:]:
    rows = load(path)
    n = len(rows)
    hits = [r for r in rows if int(r['hp']) != 0 or int(r['mp']) != 0 or r.get('status', '-') != '-']
    crits = [r for r in hits if r['crit'] == '1']
    p = len(hits) / n
    print(f'{path}: {n} trials, rolled {dict(collections.Counter(r["roll"] for r in rows))}, '
          f'hit {p:.3f} +- {math.sqrt(p * (1 - p) / n):.3f}')
    print('  normal', sorted(collections.Counter(int(r['hp']) for r in hits if r['crit'] == '0').items()))
    if hits:
        q = len(crits) / len(hits)
        print(f'  crits {len(crits)}/{len(hits)} = {q:.3f} +- {math.sqrt(q * (1 - q) / len(hits)):.3f}',
              sorted(collections.Counter(int(r['hp']) for r in crits).items()),
              'pushed', dict(collections.Counter(r['pushed'] for r in crits)))
    print('  status', dict(collections.Counter(r.get('status', '-') for r in rows)))
