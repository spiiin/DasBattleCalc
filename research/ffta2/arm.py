"""A small ARMv5 (ARM state) disassembler for reading FFTA2 code from a Main
RAM dump (plan_<frame>.bin, 4 MB at 0x02000000). Covers what game code
mostly uses: data processing, multiplies, LDR / STR (word, byte, halfword,
signed), LDM / STM, B / BL / BX / BLX, CLZ, SWI. Others print as .word.

python arm.py dump.bin 0x02073000 0x02073300
"""
import struct
import sys

COND = ['eq', 'ne', 'cs', 'cc', 'mi', 'pl', 'vs', 'vc', 'hi', 'ls', 'ge', 'lt', 'gt', 'le', '', 'nv']
OPS = ['and', 'eor', 'sub', 'rsb', 'add', 'adc', 'sbc', 'rsc', 'tst', 'teq', 'cmp', 'cmn', 'orr', 'mov', 'bic', 'mvn']
SHIFT = ['lsl', 'lsr', 'asr', 'ror']


def reg(n):
    return {13: 'sp', 14: 'lr', 15: 'pc'}.get(n, 'r%d' % n)


def ror(v, n):
    n &= 31
    return ((v >> n) | (v << (32 - n))) & 0xFFFFFFFF


def shifter(w):
    rm = w & 15
    st = (w >> 5) & 3
    if w & 0x10:
        return '%s, %s %s' % (reg(rm), SHIFT[st], reg((w >> 8) & 15))
    amt = (w >> 7) & 31
    if amt == 0 and st == 0:
        return reg(rm)
    if amt == 0 and st == 3:
        return '%s, rrx' % reg(rm)
    if amt == 0:
        amt = 32
    return '%s, %s #%d' % (reg(rm), SHIFT[st], amt)


def regs_list(mask):
    return '{' + ', '.join(reg(i) for i in range(16) if mask & (1 << i)) + '}'


def dis(w, pc):
    c = COND[w >> 28]
    if w >> 28 == 15:
        if (w & 0x0E000000) == 0x0A000000:          # BLX imm
            off = (w & 0xFFFFFF) << 2
            if off & 0x2000000:
                off -= 0x4000000
            return 'blx 0x%08X' % (pc + 8 + off + ((w >> 23) & 2))
        return '.word 0x%08X' % w
    if (w & 0x0FFFFFF0) == 0x012FFF10:
        return 'bx%s %s' % (c, reg(w & 15))
    if (w & 0x0FFFFFF0) == 0x012FFF30:
        return 'blx%s %s' % (c, reg(w & 15))
    if (w & 0x0FFF0FF0) == 0x016F0F10:
        return 'clz%s %s, %s' % (c, reg((w >> 12) & 15), reg(w & 15))
    if (w & 0x0E000000) == 0x0A000000:
        off = (w & 0xFFFFFF) << 2
        if off & 0x2000000:
            off -= 0x4000000
        return '%s%s 0x%08X' % ('bl' if w & 0x01000000 else 'b', c, pc + 8 + off)
    if (w & 0x0F000000) == 0x0F000000:
        return 'swi%s 0x%X' % (c, w & 0xFFFFFF)
    if (w & 0x0FC000F0) == 0x00000090:             # MUL / MLA
        rd, rn, rs, rm = (w >> 16) & 15, (w >> 12) & 15, (w >> 8) & 15, w & 15
        s = 's' if w & 0x100000 else ''
        if w & 0x200000:
            return 'mla%s%s %s, %s, %s, %s' % (c, s, reg(rd), reg(rm), reg(rs), reg(rn))
        return 'mul%s%s %s, %s, %s' % (c, s, reg(rd), reg(rm), reg(rs))
    if (w & 0x0F8000F0) == 0x00800090:             # UMULL / SMULL / ...
        name = ['umull', 'umlal', 'smull', 'smlal'][(w >> 21) & 3]
        return '%s%s %s, %s, %s, %s' % (name, c, reg((w >> 12) & 15), reg((w >> 16) & 15), reg(w & 15),
                                        reg((w >> 8) & 15))
    if (w & 0x0FF000F0) == 0x01000080 or (w & 0x0F9000F0) == 0x01000080:  # SMLAxy etc (v5TE)
        return '.word 0x%08X ; dsp' % w
    if (w & 0x0E000090) == 0x00000090 and (w & 0x60):  # halfword / signed transfers
        p, u, i, wb, l = (w >> 24) & 1, (w >> 23) & 1, (w >> 22) & 1, (w >> 21) & 1, (w >> 20) & 1
        rn, rd = (w >> 16) & 15, (w >> 12) & 15
        sh = (w >> 5) & 3
        name = {(1, 1): 'ldrh', (1, 2): 'ldrsb', (1, 3): 'ldrsh', (0, 1): 'strh', (0, 2): 'ldrd', (0, 3): 'strd'}[(l, sh)]
        if i:
            off = ((w >> 4) & 0xF0) | (w & 15)
            o = '#%s0x%X' % ('' if u else '-', off)
        else:
            o = '%s%s' % ('' if u else '-', reg(w & 15))
        if p:
            return '%s%s %s, [%s, %s]%s' % (name, c, reg(rd), reg(rn), o, '!' if wb else '')
        return '%s%s %s, [%s], %s' % (name, c, reg(rd), reg(rn), o)
    if (w & 0x0C000000) == 0x00000000:             # data processing
        op = (w >> 21) & 15
        s = 's' if (w & 0x100000) and op not in (8, 9, 10, 11) else ''
        rn, rd = (w >> 16) & 15, (w >> 12) & 15
        if (w & 0x0FB00000) == 0x01000000 or (w & 0x0FB00000) == 0x01400000:
            return 'mrs%s %s, %s' % (c, reg(rd), 'spsr' if w & 0x400000 else 'cpsr')
        if (w & 0x0DB0F000) == 0x0120F000:
            return 'msr%s ...' % c
        if w & 0x02000000:
            v = ror(w & 0xFF, ((w >> 8) & 15) * 2)
            o2 = '#0x%X' % v
        else:
            o2 = shifter(w)
        name = OPS[op]
        if op in (13, 15):
            return '%s%s%s %s, %s' % (name, c, s, reg(rd), o2)
        if op in (8, 9, 10, 11):
            return '%s%s %s, %s' % (name, c, reg(rn), o2)
        return '%s%s%s %s, %s, %s' % (name, c, s, reg(rd), reg(rn), o2)
    if (w & 0x0C000000) == 0x04000000:             # LDR / STR
        i, p, u, b, wb, l = [(w >> k) & 1 for k in (25, 24, 23, 22, 21, 20)]
        rn, rd = (w >> 16) & 15, (w >> 12) & 15
        name = ('ldr' if l else 'str') + ('b' if b else '')
        if i:
            o = '%s%s' % ('' if u else '-', shifter(w & ~0x10))
        else:
            o = '#%s0x%X' % ('' if u else '-', w & 0xFFF)
        if rn == 15 and not i and p:
            return '%s%s %s, =0x%08X' % (name, c, reg(rd), pc + 8 + ((w & 0xFFF) if u else -(w & 0xFFF)))
        if p:
            return '%s%s %s, [%s, %s]%s' % (name, c, reg(rd), reg(rn), o, '!' if wb else '')
        return '%s%s %s, [%s], %s' % (name, c, reg(rd), reg(rn), o)
    if (w & 0x0E000000) == 0x08000000:             # LDM / STM
        p, u, wb, l = (w >> 24) & 1, (w >> 23) & 1, (w >> 21) & 1, (w >> 20) & 1
        mode = ('i' if u else 'd') + ('b' if p else 'a')
        rn = (w >> 16) & 15
        if rn == 13 and l and mode == 'ia' and wb:
            return 'pop%s %s' % (c, regs_list(w & 0xFFFF))
        if rn == 13 and not l and mode == 'db' and wb:
            return 'push%s %s' % (c, regs_list(w & 0xFFFF))
        return '%s%s%s %s%s, %s' % ('ldm' if l else 'stm', mode, c, reg(rn), '!' if wb else '', regs_list(w & 0xFFFF))
    return '.word 0x%08X' % w


class Ram:
    """Main RAM (0x02000000); the ITCM (0x01FF8000, 32 KB) from
    <dump>_itcm.bin next to it when present."""

    def __init__(self, path):
        self.b = open(path, 'rb').read()
        try:
            self.itcm = open(path[:-4] + '_itcm.bin', 'rb').read()
        except OSError:
            self.itcm = b''

    def u32(self, a):
        if 0x01FF8000 <= a < 0x02000000 and self.itcm:
            return struct.unpack_from('<I', self.itcm, (a - 0x01FF8000) & 0x7FFF)[0]
        return struct.unpack_from('<I', self.b, a - 0x02000000)[0]


def listing(ram, start, end):
    out = []
    for pc in range(start, end, 4):
        w = ram.u32(pc)
        text = dis(w, pc)
        if '=0x' in text:                           # a literal: show its value
            lit = int(text.split('=0x')[1], 16)
            if 0x02000000 <= lit < 0x02400000:
                text += '  ; 0x%08X' % ram.u32(lit)
        out.append('%08X: %08X  %s' % (pc, w, text))
    return out


if __name__ == '__main__':
    r = Ram(sys.argv[1])
    for line in listing(r, int(sys.argv[2], 16), int(sys.argv[3], 16)):
        print(line)
