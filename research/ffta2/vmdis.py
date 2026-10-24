"""FFTA2 script VM (research/ffta2/notes.md, "Script VM"): a disassembler
for the compiled scripts (whole files of pc.bin; loaded at a heap address,
e.g. the Fight damage script at 0x0223C040 in plan_<frame>.bin).

Script: u16 function count, ..., functions from +0x10, 8 bytes each:
u16 id, u16 code offset / 16, u16 / u16 links of a binary search tree by
id. An instruction: i8 opcode, u8 length, operands (0x22 switch: length
from its case count). The interpreter: 0x0203AAB4.

python vmdis.py dump.bin 0x0223C040 [function id ...]
"""
import struct
import sys

# opcode -> (name, operand format); names from the handlers (0x0203AAE4 table)
OPS = {
    -1: 'nop',
    0: 'push.i', 1: 'push.f', 2: 'push.2', 3: 'push.3', 4: 'push.4', 5: 'push.5',
    6: 'bin6', 7: 'bin7', 8: 'bin8', 9: 'bin9', 10: 'bin10', 11: 'bin11', 12: 'bin12',
    13: 'bin13', 14: 'bin14', 15: 'bin15', 16: 'bin16', 17: 'bin17', 18: 'bin18', 19: 'bin19',
    20: 'bin20', 21: 'bin21', 22: 'bin22', 23: 'un23', 24: 'bin24', 25: 'bin25', 26: 'op26',
    27: 'clear', 28: 'frame.add', 29: 'frame.save', 30: 'frame.restore',
    31: 'jz', 32: 'jnz', 33: 'jmp', 34: 'switch', 35: 'loop.set', 36: 'loop.next',
    37: 'loop.push', 38: 'loop.pop', 39: 'enter', 40: 'leave', 41: 'ret.i', 42: 'ret.f',
    43: 'push.ret.i', 44: 'push.ret.f', 45: 'return', 46: 'to.i', 47: 'to.f',
    48: 'call', 49: 'native', 50: 'store.local', 51: 'ref.local', 52: 'ref.global',
    53: 'push.str',
}


def s16(b, o):
    return struct.unpack_from('<h', b, o)[0]


def i32(b, o):
    return struct.unpack_from('<i', b, o)[0]


class Script:
    def __init__(self, b):
        self.b = b
        self.count = struct.unpack_from('<H', b, 0)[0]
        self.funcs = {}
        for k in range(self.count):
            fid, off, l, r = struct.unpack_from('<HHHH', b, 0x10 + 8 * k)
            self.funcs[fid] = off * 16

    def insn(self, pc):
        b = self.b
        op = struct.unpack_from('<b', b, pc)[0]
        ln = b[pc + 1]
        if op == 34:
            ln = (s16(b, pc + 2) - 1) * 8 + 12
        name = OPS.get(op, 'op%d' % op)
        ops = ''
        if 0 <= op <= 5:
            ops = '%d' % i32(b, pc + 4) if op == 0 else '0x%08X' % struct.unpack_from('<I', b, pc + 4)[0]
            if op == 1:
                ops = '%g' % struct.unpack_from('<f', b, pc + 4)[0]
        elif op in (31, 32, 33):
            ops = '-> %04X' % (pc + s16(b, pc + 2))
        elif op == 48:
            ops = '-> %04X' % (pc + i32(b, pc + 4))
        elif op == 49:
            ops = '#%d' % s16(b, pc + 2)
        elif op in (28, 50):
            ops = '%d' % s16(b, pc + 2)
        elif op in (51, 52):
            ops = '%d type %d' % (s16(b, pc + 4), s16(b, pc + 6))
        elif op == 34:
            n = s16(b, pc + 2)
            cases = []
            for k in range(n):
                v, d = i32(b, pc + 4 + 8 * k), i32(b, pc + 8 + 8 * k)
                cases.append('%d:%04X' % (v, pc + d))
            ops = ' '.join(cases)
        elif op == 53:
            end = b.index(0, pc + 2)
            ops = repr(b[pc + 2:end].decode('latin-1'))
        elif ln > 2:
            ops = b[pc + 2:pc + ln].hex(' ')
        return op, ln, name, ops

    def listing(self, start, stop_at_return=True, limit=4000):
        out = []
        pc = start
        for _ in range(limit):
            op, ln, name, ops = self.insn(pc)
            out.append('%04X: %-11s %s' % (pc, name, ops))
            if ln == 0:
                break
            pc += ln
            if stop_at_return and op == 45:
                # a function may return in a branch: stop at the next function start
                if pc in self.funcs.values():
                    break
        return out


if __name__ == '__main__':
    dump = open(sys.argv[1], 'rb').read()
    base = int(sys.argv[2], 16)
    o = base - 0x02000000
    size = struct.unpack_from('<I', dump, o + 8)[0]
    sc = Script(dump[o:o + size])
    print('functions:', sc.count, 'ids', sorted(sc.funcs)[:40])
    for fid in [int(x) for x in sys.argv[3:]]:
        print('--- function %d at %04X' % (fid, sc.funcs[fid]))
        for line in sc.listing(sc.funcs[fid]):
            print(line)
