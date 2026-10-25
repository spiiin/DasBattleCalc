# Watch the units' bytes +0x2E, +0x41 (CT?) while turns pass.
import sys, time
from ppdbg import *
REC, SIZE = 0x092E5CB4, 0x1E8
d = Dbg()
def snap():
    b = d.read(REC, SIZE * 16)
    return [(b[k*SIZE+0x2E], b[k*SIZE+0x41], b[k*SIZE+0x40], int.from_bytes(b[k*SIZE+0x30:k*SIZE+0x32],'little')) for k in range(16)]
def press(btn, n=1, wait=0.4):
    for _ in range(n):
        d.call('input.buttons.press', button=btn, duration=3); time.sleep(wait)
if __name__ == '__main__':
    for a in sys.argv[1:]:
        if a.startswith('shot:'): shot(d, 'shots/' + a[5:] + '.png')
        elif a == 'ct': print(snap())
        elif a.startswith('sleep:'): time.sleep(float(a[6:]))
        else:
            btn, _, n = a.partition('*'); press(btn, int(n or 1))
