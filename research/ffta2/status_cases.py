"""Cases of status abilities for vary_probe.lua: Luso uses the ability
on Sasarr (ffta2_test_attack.State) with edits of the target's job,
statuses of both, Luso's support. Writes cases.txt (probe) and prints
nothing; join.py-style: python status_cases.py join vary_log.txt
prints the test lines "keys | hit damage" (tests/test_ffta2_attack.das
keys: ab, tj, st, sa, sup).
"""
import sys

LUSO = 0x0212B120
SASARR = 0x0212A0D0
STATUS = 0x28
JOB = 0x06
SUPPORT = 0x50

SPELLS = [304, 227, 197, 219, 221, 303, 228, 134, 213, 191, 211, 339, 45, 79, 584, 462]
JOBS = [1, 5, 12, 20, 33, 47, 62, 80, 101, 130]
T_STATUS = [47, 48, 57, 17, 34, 27, 24, 9, 13, 12]
A_STATUS = [13, 54, 36, 10]
SUPPORTS = [865, 855, 851]


def status_edit(rec, n):
    return '%X:1:%d' % (rec + STATUS + (n >> 3), 1 << (n & 7))


def cases():
    out = []
    for ab in SPELLS:
        out.append(('ab%d' % ab, 'ab=%d' % ab, ''))
    for j in JOBS:
        for ab in (304, 134, 213):
            out.append(('ab%d_tj%d' % (ab, j), 'ab=%d tj=%d' % (ab, j), '%X:1:%d' % (SASARR + JOB, j)))
    for s in T_STATUS:
        for ab in (304, 227):
            out.append(('ab%d_st%d' % (ab, s), 'ab=%d st=%d' % (ab, s), status_edit(SASARR, s)))
    for s in A_STATUS:
        out.append(('ab304_sa%d' % s, 'ab=304 sa=%d' % s, status_edit(LUSO, s)))
    for sup in SUPPORTS:
        for ab in (304, 197):
            out.append(('ab%d_sup%d' % (ab, sup), 'ab=%d sup=%d' % (ab, sup), '%X:2:%d' % (LUSO + SUPPORT, sup)))
    return out


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == 'join':
        keys = {name: k for name, k, _ in cases()}
        for line in open(sys.argv[2]):
            p = line.split()
            if len(p) >= 3 and p[0] in keys:
                print('    "%s | %s %s",' % (keys[p[0]], p[1], p[2]))
    else:
        with open('cases.txt', 'w', newline='\n') as f:
            for name, _, edits in cases():
                f.write('%s ab=%s %s\n' % (name, name[2:].split('_')[0], edits))
