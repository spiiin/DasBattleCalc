"""FFTA2 script VM natives: the handler of a native id. The game's native
dispatcher 0x020CCEB0 (called from 0x02070224) is a compiled switch on r1:
a tree of cmp / sub / conditional branches and jump tables. This runs that
tree for an id (a tiny ARM subset) and stops at the first other
instruction - the case's code - then disassembles the case.

python natives.py dump.bin 1561 1562 ...
"""
import struct
import sys

import arm

DISPATCH = 0x020CCEB8      # after the prologue (push, sub sp)


def cond_ok(c, f):
    n, z, cf, v = f
    return [z, not z, cf, not cf, n, not n, v, not v, cf and not z, not cf or z, n == v, n != v,
            not z and n == v, z or n != v, True, False][c]


def imm(w):
    return arm.ror(w & 0xFF, ((w >> 8) & 15) * 2)


def case_address(ram, nid, start=DISPATCH, depth=0):
    """The case of a native id; a case that only delegates (bl X; add sp)
    continues in X - the next level of the switch (0x020CBC98 and on)."""
    pc = switch_case(ram, nid, start)
    if pc is None or depth > 4:
        return pc
    t = arm.dis(ram.u32(pc), pc)
    nxt = arm.dis(ram.u32(pc + 4), pc + 4)
    if t.startswith('bl 0x') and (nxt.startswith('add sp') or nxt.startswith('pop')):
        x = int(t.split('0x')[1], 16)
        while True:                         # skip the callee's prologue
            u = arm.dis(ram.u32(x), x)
            if u.startswith('push') or u.startswith('sub sp'):
                x += 4
            else:
                break
        return case_address(ram, nid, x, depth + 1)
    return pc


def switch_case(ram, nid, start, limit=200):
    regs = [0] * 16
    regs[1] = nid
    f = (False, False, False, False)
    pc = start
    for _ in range(limit):
        w = ram.u32(pc)
        c = w >> 28
        if (w & 0x0E000000) == 0x0A000000 and not (w & 0x01000000):        # B
            off = (w & 0xFFFFFF) << 2
            if off & 0x2000000:
                off -= 0x4000000
            pc = pc + 8 + off if cond_ok(c, f) else pc + 4
            continue
        if (w & 0x0F7F0000) == 0x051F0000:                                   # LDR rd, [pc, #]
            rd = (w >> 12) & 15
            o = w & 0xFFF
            if cond_ok(c, f):
                regs[rd] = ram.u32(pc + 8 + (o if w & 0x800000 else -o))
            pc += 4
            continue
        if (w & 0x0C000000) == 0 and ((w & 0x02000000) or (w & 0x90) != 0x90):  # data processing
            op = (w >> 21) & 15
            rn, rd = (w >> 16) & 15, (w >> 12) & 15
            if w & 0x02000000:
                b = imm(w)
            else:
                rm = w & 15
                if w & 0xFF0:                                                # shifted register
                    if (w & 0xFF0) == 0x100 and op == 4 and rd == 15:       # addls pc, pc, rX, lsl #2
                        if cond_ok(c, f):
                            pc = pc + 8 + (regs[rm] << 2)
                        else:
                            pc += 4
                        continue
                    return pc
                b = regs[rm]
            a = regs[rn]
            if op == 10:                                                     # CMP
                r = (a - b) & 0xFFFFFFFF
                n = bool(r >> 31)
                z = r == 0
                cf = a >= b
                v = bool(((a ^ b) & (a ^ r)) >> 31)
                f = (n, z, cf, v)
            elif op == 2:                                                    # SUB
                if cond_ok(c, f):
                    regs[rd] = (a - b) & 0xFFFFFFFF
            elif op == 4:                                                    # ADD
                if cond_ok(c, f):
                    regs[rd] = (a + b) & 0xFFFFFFFF
            elif op == 13:                                                   # MOV
                if cond_ok(c, f):
                    regs[rd] = b
            else:
                return pc
            pc += 4
            continue
        return pc
    return None


if __name__ == '__main__':
    ram = arm.Ram(sys.argv[1])
    for a in sys.argv[2:]:
        nid = int(a)
        pc = case_address(ram, nid)
        print('native %d (0x%X): case at %08X' % (nid, nid, pc or 0))
        if pc:
            for line in arm.listing(ram, pc, pc + 0x30):
                print('   ', line)
