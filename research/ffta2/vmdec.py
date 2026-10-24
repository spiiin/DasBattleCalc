"""FFTA2 script VM: a decompiler to C-like text (statements with gotos),
on top of vmdis.py. Enough to read the formulas: expressions are rebuilt
from the stack code, calls and native calls get their arguments.

python vmdec.py dump.bin 0x0223C040 [function id | @offset ...]   (no ids: all)
python vmdec.py rom.nds '#598/c' 1 @67E0      (a script of the ROM: pc.bin hash / the list's character)
"""
import struct
import sys

from vmdis import Script, s16, i32

BIN = {6: '+', 7: '-', 8: '*', 9: '/', 10: '|', 11: '&', 12: '^', 13: '<<', 14: '>>', 15: '**', 16: '%',
       17: '==', 18: '>=', 19: '>', 20: '<=', 21: '<', 22: '!=', 24: '&&', 25: '||'}


def var_name(op, v):
    idx = struct.unpack('<h', struct.pack('<H', v & 0xFFFF))[0]
    hi = v >> 16
    if op == 2 and hi == 1:
        return 'a%d' % -idx if idx < 0 else 'v%d' % idx
    return 'ref%d_%X' % (op, v & 0xFFFFFFFF)


def decompile(sc, fid, names=None, start=None):
    names = names or {}
    if start is None:
        start = sc.funcs[fid]
    by_off = {off: f for f, off in sc.funcs.items()}
    out = []
    stack = []
    calls = []          # argument lists of calls being built (enter .. leave)
    pending = None      # the last call's expression, for push.ret
    labels = set()
    pc = start
    insns = []
    # first pass: the instructions up to the next function start
    ends = sorted(o for o in sc.funcs.values() if o > start)
    end = ends[0] if ends else len(sc.b)
    while pc < end:
        op, ln, name, ops = sc.insn(pc)
        insns.append((pc, op, ln))
        if op in (31, 32, 33):
            labels.add(pc + s16(sc.b, pc + 2))
        if op == 34:
            for k in range(s16(sc.b, pc + 2)):
                labels.add(pc + i32(sc.b, pc + 8 + 8 * k))
        if ln == 0:
            break
        pc += ln
        # an internal function (no id) ends at a return past every label
        if op == 45 and all(t < pc for t in labels):
            break
    b = sc.b
    for pc, op, ln in insns:
        if pc in labels:
            out.append('L%04X:' % pc)
        if 0 <= op <= 5:
            v = struct.unpack_from('<I', b, pc + 4)[0]
            if op == 0:
                stack.append(str(i32(b, pc + 4)))
            elif op == 1:
                stack.append('%gf' % struct.unpack_from('<f', b, pc + 4)[0])
            else:
                stack.append(var_name(op, v))
        elif op in BIN:
            r = stack.pop() if stack else '?'
            l = stack.pop() if stack else '?'
            stack.append('(%s %s %s)' % (l, BIN[op], r))
        elif op == 23:
            stack.append('!%s' % (stack.pop() if stack else '?'))
        elif op == 26:
            r = stack.pop() if stack else '?'
            l = stack.pop() if stack else '?'
            out.append('    %s = %s;' % (l, r))
        elif op == 27:
            if stack:
                for e in stack:
                    out.append('    %s;' % e)
            stack = []
        elif op in (28, 29, 30, -1):
            pass
        elif op == 31:
            out.append('    if (!%s) goto L%04X;' % (stack.pop() if stack else '?', pc + s16(b, pc + 2)))
            stack = []
        elif op == 32:
            out.append('    if (%s) goto L%04X;' % (stack.pop() if stack else '?', pc + s16(b, pc + 2)))
            stack = []
        elif op == 33:
            out.append('    goto L%04X;' % (pc + s16(b, pc + 2)))
        elif op == 34:
            n = s16(b, pc + 2)
            cases = ', '.join('%d: L%04X' % (i32(b, pc + 4 + 8 * k), pc + i32(b, pc + 8 + 8 * k)) for k in range(n))
            out.append('    switch (%s) { %s }' % (stack.pop() if stack else '?', cases))
            stack = []
        elif op == 39:
            calls.append({})
        elif op == 50:
            k = -s16(b, pc + 2)
            if calls:
                calls[-1][k] = stack.pop() if stack else '?'
        elif op in (48, 49):
            args = calls[-1] if calls else {}
            a = ', '.join(args[k] for k in sorted(args))
            if op == 48:
                t = pc + i32(b, pc + 4)
                fname = names.get(by_off.get(t), 'F%d' % by_off[t] if t in by_off else 'sub_%04X' % t)
            else:
                nid = s16(b, pc + 2)
                fname = names.get(('n', nid), 'native_%d' % nid)
            pending = '%s(%s)' % (fname, a)
        elif op == 40:
            if calls:
                calls.pop()
            if pending is not None:
                stack.append(pending)
                pending = None
        elif op in (43, 44):
            pass                # the call's value is already on the stack (leave)
        elif op == 41 or op == 42:
            out.append('    result = %s;' % (stack.pop() if stack else '?'))
        elif op == 45:
            out.append('    return;')
        elif op == 46:
            stack.append('int(%s)' % (stack.pop() if stack else '?'))
        elif op == 47:
            stack.append('float(%s)' % (stack.pop() if stack else '?'))
        else:
            _, _, name, ops = sc.insn(pc)
            out.append('    /* %s %s */' % (name, ops))
    # a call whose value was not used (statement): stack leftovers are
    # emitted at 'clear'; leave pushes them
    return out


def load_script(where, what):
    """A script from a RAM dump (where = dump.bin, what = its hex address)
    or from the ROM (where = rom.nds, what = #hash of its pc.bin entry:
    598/c Fight damage, 784 hit, 897 applying damage)."""
    if what.startswith('#'):
        import ffta2_rom
        nds, arc = ffta2_rom.open_rom(where)
        h, _, ch = what[1:].partition('/')
        return Script(arc_entry(arc, int(h), ch))
    dump = open(where, 'rb').read()
    o = int(what, 16) - 0x02000000
    size = struct.unpack_from('<I', dump, o + 8)[0]
    return Script(dump[o:o + size])


def arc_entry(arc, h, ch=''):
    a, b = arc.ids[h]
    off = (a & 0x3FFFFFF) * 2
    size = ((a >> 26) + (b & 0xFFFF) * 64) * 4
    if a & 1:                               # a list: the file whose name has ch (#598/c)
        index = off // 4 - arc.extra_start
        for o, s, chr_, pos in arc.lists[index]:
            if not ch or chr(chr_) == ch:
                data = arc.bin[o:o + (s if s else size)]
                break
    else:
        data = arc.bin[off:off + size]
    return data[:struct.unpack_from('<I', data, 8)[0]]


if __name__ == '__main__':
    sc = load_script(sys.argv[1], sys.argv[2])
    ids = sys.argv[3:] or [str(f) for f in sorted(sc.funcs)]
    if ids and ids[0].startswith('+'):
        # +id: the function and every function it reaches, once each
        import re
        todo = [ids[0][1:]]
        ids = []
        while todo:
            a = todo.pop(0)
            if a in ids:
                continue
            ids.append(a)
            if a.startswith('@'):
                text = '\n'.join(decompile(sc, None, start=int(a[1:], 16)))
            else:
                text = '\n'.join(decompile(sc, int(a)))
            todo += ['@' + m for m in re.findall(r'sub_([0-9A-F]{4})\(', text)]
            todo += [m for m in re.findall(r'F(\d+)\(', text)]
    for a in ids:
        if a.startswith('@'):
            off = int(a[1:], 16)
            print('sub_%04X() {' % off)
            lines = decompile(sc, None, start=off)
        else:
            fid = int(a)
            print('F%d() {   // %04X' % (fid, sc.funcs[fid]))
            lines = decompile(sc, fid)
        for line in lines:
            print(line)
        print('}')
