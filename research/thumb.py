"""Minimal ARM7TDMI Thumb disassembler for reading FFTA routines.

usage: python thumb.py rom.gba 0x0809F800 0x0809FA00 [ram.bin base]
"""
import struct
import sys

R = ['r0', 'r1', 'r2', 'r3', 'r4', 'r5', 'r6', 'r7', 'r8', 'r9', 'r10', 'r11', 'r12', 'sp', 'lr', 'pc']
COND = ['eq', 'ne', 'cs', 'cc', 'mi', 'pl', 'vs', 'vc', 'hi', 'ls', 'ge', 'lt', 'gt', 'le', 'al', 'nv']
ALU = ['and', 'eor', 'lsl', 'lsr', 'asr', 'adc', 'sbc', 'ror', 'tst', 'neg', 'cmp', 'cmn', 'orr', 'mul', 'bic', 'mvn']


def rlist(bits, extra=None):
    regs = [R[i] for i in range(8) if bits >> i & 1]
    if extra:
        regs.append(extra)
    return '{' + ','.join(regs) + '}'


def dis(mem, base, addr):
    """Returns (text, size, literal) for the instruction at addr."""
    off = addr - base
    h = struct.unpack_from('<H', mem, off)[0]
    lit = None
    if h >> 13 == 0 and (h >> 11) & 3 != 3:
        op = ['lsl', 'lsr', 'asr'][(h >> 11) & 3]
        return f'{op} {R[h & 7]}, {R[h >> 3 & 7]}, #{h >> 6 & 31}', 2, lit
    if h >> 11 == 3:
        op = 'sub' if h >> 9 & 1 else 'add'
        v = h >> 6 & 7
        rn = f'#{v}' if h >> 10 & 1 else R[v]
        return f'{op} {R[h & 7]}, {R[h >> 3 & 7]}, {rn}', 2, lit
    if h >> 13 == 1:
        op = ['mov', 'cmp', 'add', 'sub'][h >> 11 & 3]
        return f'{op} {R[h >> 8 & 7]}, #{h & 255}', 2, lit
    if h >> 10 == 0x10:
        return f'{ALU[h >> 6 & 15]} {R[h & 7]}, {R[h >> 3 & 7]}', 2, lit
    if h >> 10 == 0x11:
        op = h >> 8 & 3
        rd = (h & 7) | (h >> 4 & 8)
        rs = h >> 3 & 15
        if op == 3:
            return f'bx {R[rs]}', 2, lit
        return f'{["add", "cmp", "mov"][op]} {R[rd]}, {R[rs]}', 2, lit
    if h >> 11 == 9:
        a = ((addr + 4) & ~3) + (h & 255) * 4
        lit = struct.unpack_from('<I', mem, a - base)[0] if 0 <= a - base < len(mem) - 3 else None
        return f'ldr {R[h >> 8 & 7]}, [pc, #{(h & 255) * 4}]  ; ={lit:#010x}' if lit is not None else 'ldr ?', 2, lit
    if h >> 12 == 5:
        ro, rb, rd = R[h >> 6 & 7], R[h >> 3 & 7], R[h & 7]
        if h >> 9 & 1 == 0:
            op = ['str', 'strb', 'ldr', 'ldrb'][h >> 10 & 3]
        else:
            op = ['strh', 'ldsb', 'ldrh', 'ldsh'][h >> 10 & 3]
        return f'{op} {rd}, [{rb}, {ro}]', 2, lit
    if h >> 13 == 3:
        b, l = h >> 12 & 1, h >> 11 & 1
        imm = (h >> 6 & 31) * (1 if b else 4)
        return f'{"ldr" if l else "str"}{"b" if b else ""} {R[h & 7]}, [{R[h >> 3 & 7]}, #{imm:#x}]', 2, lit
    if h >> 12 == 8:
        return f'{"ldrh" if h >> 11 & 1 else "strh"} {R[h & 7]}, [{R[h >> 3 & 7]}, #{(h >> 6 & 31) * 2:#x}]', 2, lit
    if h >> 12 == 9:
        return f'{"ldr" if h >> 11 & 1 else "str"} {R[h >> 8 & 7]}, [sp, #{(h & 255) * 4:#x}]', 2, lit
    if h >> 12 == 10:
        return f'add {R[h >> 8 & 7]}, {"sp" if h >> 11 & 1 else "pc"}, #{(h & 255) * 4:#x}', 2, lit
    if h >> 8 == 0xB0:
        return f'add sp, #{"-" if h >> 7 & 1 else ""}{(h & 127) * 4:#x}', 2, lit
    if h >> 12 == 11 and h >> 9 & 3 == 2:
        l = h >> 11 & 1
        return f'{"pop" if l else "push"} {rlist(h & 255, ("pc" if l else "lr") if h >> 8 & 1 else None)}', 2, lit
    if h >> 12 == 12:
        return f'{"ldmia" if h >> 11 & 1 else "stmia"} {R[h >> 8 & 7]}!, {rlist(h & 255)}', 2, lit
    if h >> 12 == 13:
        c = h >> 8 & 15
        if c == 15:
            return f'swi #{h & 255:#x}', 2, lit
        o = h & 255
        o = o - 256 if o & 128 else o
        return f'b{COND[c]} {addr + 4 + o * 2:#010x}', 2, lit
    if h >> 11 == 0x1C:
        o = h & 2047
        o = o - 2048 if o & 1024 else o
        return f'b {addr + 4 + o * 2:#010x}', 2, lit
    if h >> 11 == 0x1E:
        h2 = struct.unpack_from('<H', mem, off + 2)[0]
        o = (h & 2047) << 12 | (h2 & 2047) << 1
        o = o - (1 << 23) if o & (1 << 22) else o
        return f'bl {addr + 4 + o:#010x}', 4, lit
    return f'.hword {h:#06x}', 2, lit


def main():
    mem = open(sys.argv[1], 'rb').read()
    base = int(sys.argv[5], 0) if len(sys.argv) > 5 else 0x08000000
    if len(sys.argv) > 4:
        mem = open(sys.argv[4], 'rb').read()
    a, end = int(sys.argv[2], 0), int(sys.argv[3], 0)
    while a < end:
        text, size, _ = dis(mem, base, a)
        raw = mem[a - base:a - base + size].hex()
        print(f'{a:08X}  {raw:<8}  {text}')
        a += size


if __name__ == '__main__':
    main()
