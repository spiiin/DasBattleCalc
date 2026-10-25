# MIPS (Allegrex) disassembly of the WotL RAM image: mips.py ADDR [N]
import sys, capstone
B = 0x08000000
md = capstone.Cs(capstone.CS_ARCH_MIPS, capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
def ram(): return open(__file__.replace('mips.py', 'ram0.bin'), 'rb').read()
def dis(r, addr, n=40):
    out = []
    for ins in md.disasm(r[addr - B: addr - B + 4 * n], addr):
        out.append('%08x: %s %s' % (ins.address, ins.mnemonic, ins.op_str))
    return out
def refs(r, target, lo=0x08804000, hi=0x08BB0000):
    """addresses of lui/addiu|ori|lw pairs that build `target` (within 8 instructions)"""
    import struct
    hi16 = (target + 0x8000) >> 16 & 0xFFFF; lo16 = target & 0xFFFF
    res = []
    for a in range(lo, hi, 4):
        w = struct.unpack_from('<I', r, a - B)[0]
        if w >> 26 == 0x0F and w & 0xFFFF == hi16:
            rt = w >> 16 & 31
            for k in range(1, 9):
                w2 = struct.unpack_from('<I', r, a - B + 4 * k)[0]
                if w2 & 0xFFFF == lo16 and (w2 >> 21 & 31) == rt: res.append(a); break
    return res
if __name__ == '__main__':
    r = ram()
    a = int(sys.argv[1], 16); n = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    print('\n'.join(dis(r, a, n)))
