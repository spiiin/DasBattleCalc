# FFT: WotL text encoding (single-byte part): 0-9, A-Z, a-z, 0x95 space, 0xFE end
def dec(b):
    o=[]
    for c in b:
        if c<10: o.append(chr(48+c))
        elif c<0x24: o.append(chr(65+c-10))
        elif c<0x3E: o.append(chr(97+c-0x24))
        elif c==0x95 or c==0xFA: o.append(' ')
        else: o.append('{%02x}'%c)
    return ''.join(o)
def strings(ram, addr, n, base=0x08000000):
    o=addr-base; out=[]
    for _ in range(n):
        e=ram.index(b'\xfe',o); out.append(dec(ram[o:e])); o=e+1
    return out
