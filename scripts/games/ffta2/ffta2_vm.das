options gen2
options indenting = 4

// FFTA2's formula VM (research/ffta2/notes.md, "Script VM"): the game's
// compiled scripts run as they are, read from the ROM (pc.bin entries by
// name hash); the game's native calls go to a host.
//   instruction: i8 opcode, u8 length, operands (34 switch: by its cases)
//   a cell of the expression stack: type (the push opcode: 0 int, 1
//   float, 2 frame variable, 3 global, 4 / 5 through a pointer; 0x36 /
//   0x37 an address) and a 32-bit value (variables: s16 index, s16 type)
//   the frame stack: u32 words; a function's arguments below its frame
//   (a2 = the first), its variables from the frame base
module ffta2_vm shared public

require gba_mem
require math
require strings

let VM_STACK_ADDR = 268435456       // an address: a frame stack word
let VM_GLOBAL_ADDR = 536870912     // an address: a global word
let VM_CODE_ADDR = 805306368        // an address: a byte of the script (strings)

struct VmScript {
    code : array<uint8>
    funcs : table<int; int>         // function id -> code offset
    ok : bool
}

// pc.bin entry `hash` (list character ch, 0 the first) as a script
def load_vm_script(hash, ch : int) : VmScript {
    var s = VmScript()
    let h = nds_arc_entry(hash, ch)
    let n = nds_buf_size(h)
    if (h < 0 || n < 16) {
        return <- s
    }
    let size = min(n, int(nds_buf_read32(h, 8)))
    s.code |> resize(size)
    for (i in range(size)) {
        s.code[i] = uint8(nds_buf_read8(h, i))
    }
    let count = int(nds_buf_read16(h, 0))
    for (k in range(count)) {
        let id = int(nds_buf_read16(h, 0x10 + 8 * k))
        let off = int(nds_buf_read16(h, 0x10 + 8 * k + 2)) * 16
        s.funcs |> insert(id, off)
    }
    s.ok = true
    return <- s
}

struct VmCell {
    t : int
    v : int
}

// the game's natives: VmHost.native returns false for an id it does not
// know (the run is then marked unsupported)
class VmHost {
    def abstract native(var vm : Vm; id : int) : bool
}

class Vm {
    stack : array<int>
    sp : int
    bp : int
    expr : array<VmCell>
    globals : array<int>
    ret_i : int
    ret_f : int                     // float bits
    counter : int
    unsupported : string            // the first native / opcode it could not run
    steps : int

    def Vm {
        stack |> resize(4096)
        globals |> resize(256)
    }

    // native arguments: the i-th (1-based) is the frame word sp - i
    def arg(i : int) : int {
        return stack[sp - i]
    }

    def read_addr(a : int) : int {
        if (a >= VM_GLOBAL_ADDR && a < VM_GLOBAL_ADDR + length(globals)) {
            return globals[a - VM_GLOBAL_ADDR]
        }
        if (a >= VM_STACK_ADDR && a < VM_STACK_ADDR + length(stack)) {
            return stack[a - VM_STACK_ADDR]
        }
        return 0
    }

    def write_addr(a, value : int) : void {
        if (a >= VM_GLOBAL_ADDR && a < VM_GLOBAL_ADDR + length(globals)) {
            globals[a - VM_GLOBAL_ADDR] = value
        } elif (a >= VM_STACK_ADDR && a < VM_STACK_ADDR + length(stack)) {
            stack[a - VM_STACK_ADDR] = value
        }
    }

    def push(t, v : int) : void {
        expr |> push(VmCell(t = t, v = v))
    }

    def pop() : VmCell {
        if (length(expr) == 0) {
            return VmCell()
        }
        let c = expr[length(expr) - 1]
        expr |> pop()
        return c
    }

    // 0x01FF8E70: the value of a cell and its kind (1 int, 2 float, 3 / 4 an address)
    def value(c : VmCell; var kind : int&) : int {
        let idx = int(int16(c.v & 65535))
        let elem = int(int16((c.v >> 16) & 65535))
        if (c.t == 0) {
            kind = 1
            return c.v
        } elif (c.t == 1) {
            kind = 2
            return c.v
        } elif (c.t == 2) {
            kind = elem
            return stack[bp + idx]
        } elif (c.t == 3) {
            kind = elem
            return globals[idx]
        } elif (c.t == 4 || c.t == 5) {
            let p = c.t == 4 ? stack[bp + idx] : globals[idx]
            kind = elem == 3 ? 1 : (elem == 4 ? 2 : elem)
            return self->read_addr(p)
        } elif (c.t == 54) {
            kind = 3
            return c.v
        } elif (c.t == 55) {
            kind = 4
            return c.v
        }
        kind = 0
        return 0
    }

    def int_of(c : VmCell) : int {
        var kind = 0
        let v = self->value(c, kind)
        return kind == 2 ? int(bits_float(v)) : v
    }

    def float_of(c : VmCell) : float {
        var kind = 0
        let v = self->value(c, kind)
        return kind == 2 ? bits_float(v) : float(v)
    }

    // 0x01FF90F4: store into a variable, converted to its type; the value stays on the stack
    def assign(r, l : VmCell) : void {
        var kind = 0
        let v = self->value(r, kind)
        let idx = int(int16(l.v & 65535))
        let elem = int(int16((l.v >> 16) & 65535))
        var where_to = 0
        if (l.t == 2) {
            where_to = VM_STACK_ADDR + bp + idx
        } elif (l.t == 3) {
            where_to = VM_GLOBAL_ADDR + idx
        } elif (l.t == 4) {
            where_to = stack[bp + idx]
        } elif (l.t == 5) {
            where_to = globals[idx]
        } else {
            unsupported = "assignment to a cell of type {l.t}"
            return
        }
        if (elem == 2) {
            let f = kind == 2 ? v : float_bits(float(v))
            self->write_addr(where_to, f)
            self->push(1, f)
        } else {
            let i = kind == 2 ? int(bits_float(v)) : v
            self->write_addr(where_to, i)
            self->push(0, i)
        }
    }

    def binary(op : int) : void {
        let r = self->pop()
        let l = self->pop()
        var kl = 0
        var kr = 0
        let vl = self->value(l, kl)
        let vr = self->value(r, kr)
        if (kl == 2 || kr == 2) {
            let a = kl == 2 ? bits_float(vl) : float(vl)
            let b = kr == 2 ? bits_float(vr) : float(vr)
            if (op == 6) {
                self->push(1, float_bits(a + b))
            } elif (op == 7) {
                self->push(1, float_bits(a - b))
            } elif (op == 8) {
                self->push(1, float_bits(a * b))
            } elif (op == 9) {
                self->push(1, float_bits(b != 0.0 ? a / b : 0.0))
            } elif (op == 15) {
                self->push(1, float_bits(pow(a, b)))
            } elif (op == 17) {
                self->push(0, a == b ? 1 : 0)
            } elif (op == 18) {
                self->push(0, a >= b ? 1 : 0)
            } elif (op == 19) {
                self->push(0, a > b ? 1 : 0)
            } elif (op == 20) {
                self->push(0, a <= b ? 1 : 0)
            } elif (op == 21) {
                self->push(0, a < b ? 1 : 0)
            } elif (op == 22) {
                self->push(0, a != b ? 1 : 0)
            } elif (op == 24) {
                self->push(0, a != 0.0 && b != 0.0 ? 1 : 0)
            } elif (op == 25) {
                self->push(0, a != 0.0 || b != 0.0 ? 1 : 0)
            } else {
                self->push(0, int(a) % max(int(b), 1))      // integer-only operators on floats
            }
            return
        }
        let a = vl
        let b = vr
        var res = 0
        if (op == 6) {
            res = a + b
        } elif (op == 7) {
            res = a - b
        } elif (op == 8) {
            res = a * b
        } elif (op == 9) {
            res = b != 0 ? a / b : 0
        } elif (op == 10) {
            res = a | b
        } elif (op == 11) {
            res = a & b
        } elif (op == 12) {
            res = a ^ b
        } elif (op == 13) {
            res = a << b
        } elif (op == 14) {
            res = a >> b
        } elif (op == 15) {
            res = int(pow(float(a), float(b)))
        } elif (op == 16) {
            res = b != 0 ? a % b : 0
        } elif (op == 17) {
            res = a == b ? 1 : 0
        } elif (op == 18) {
            res = a >= b ? 1 : 0
        } elif (op == 19) {
            res = a > b ? 1 : 0
        } elif (op == 20) {
            res = a <= b ? 1 : 0
        } elif (op == 21) {
            res = a < b ? 1 : 0
        } elif (op == 22) {
            res = a != b ? 1 : 0
        } elif (op == 24) {
            res = a != 0 && b != 0 ? 1 : 0
        } elif (op == 25) {
            res = a != 0 || b != 0 ? 1 : 0
        }
        self->push(0, res)
    }

    // runs function `fid` with int arguments (a2, a3, ...); the int it
    // returns (its last "result ="), unsupported != "" when it could not
    def run(sc : VmScript; fid : int; args : array<int>; var host : VmHost?) : int {
        unsupported = ""
        sp = 0
        bp = 0
        expr |> clear()
        ret_i = 0
        ret_f = 0
        if (!key_exists(sc.funcs, fid)) {
            unsupported = "no function {fid}"
            return 0
        }
        let n = length(args)
        for (i in range(n)) {
            stack[sp + n - 1 - i] = args[i]
        }
        sp += n
        stack[sp] = 0               // the return address: 0 ends the run
        sp++
        var pc = sc.funcs?[fid] ?? 0
        let size = length(sc.code)
        steps = 0
        while (pc >= 0 && pc + 1 < size) {
            steps++
            if (steps > 200000) {
                unsupported = "too many steps"
                return ret_i
            }
            let op = int(int8(sc.code[pc]))
            var len = int(sc.code[pc + 1])
            if (op == 34) {
                len = (rd16s(sc, pc + 2) - 1) * 8 + 12
            }
            var jumped = false
            if (op >= 0 && op <= 5) {
                self->push(op, rd32(sc, pc + 4))
            } elif ((op >= 6 && op <= 22) || op == 24 || op == 25) {
                self->binary(op)
            } elif (op == 23) {
                let c = self->pop()
                self->push(0, self->float_of(c) == 0.0 ? 1 : 0)
            } elif (op == 26) {
                let r = self->pop()
                let l = self->pop()
                self->assign(r, l)
            } elif (op == 27) {
                expr |> clear()
            } elif (op == 28) {
                sp += rd16s(sc, pc + 2)
            } elif (op == 29) {
                bp = sp
            } elif (op == 30) {
                sp = bp
            } elif (op == 31 || op == 32) {
                let c = self->pop()
                expr |> clear()
                let t = self->float_of(c) != 0.0
                if (t == (op == 32)) {
                    pc += rd16s(sc, pc + 2)
                    jumped = true
                }
            } elif (op == 33) {
                expr |> clear()
                pc += rd16s(sc, pc + 2)
                jumped = true
            } elif (op == 34) {
                let v = self->int_of(self->pop())
                let cases = rd16s(sc, pc + 2)
                for (k in range(cases)) {
                    if (!jumped && rd32(sc, pc + 4 + 8 * k) == v) {
                        pc += rd32(sc, pc + 8 + 8 * k)
                        jumped = true
                    }
                }
            } elif (op == 35) {
                counter = self->int_of(self->pop())
            } elif (op == 36) {
                counter--
                expr |> clear()
                if (counter != 0) {
                    pc += rd16s(sc, pc + 2)
                    jumped = true
                }
            } elif (op == 37) {
                stack[sp] = counter
                sp++
            } elif (op == 38) {
                sp--
                counter = stack[sp]
            } elif (op == 39) {
                // save the pending expression cells, the frame base and their count
                for (c in expr) {
                    stack[sp] = c.t
                    stack[sp + 1] = c.v
                    sp += 2
                }
                stack[sp] = bp
                stack[sp + 1] = length(expr)
                sp += 2
                expr |> clear()
            } elif (op == 40) {
                sp--
                let cnt = stack[sp]
                sp--
                bp = stack[sp]
                sp -= cnt * 2
                expr |> clear()
                for (k in range(cnt)) {
                    self->push(stack[sp + 2 * k], stack[sp + 2 * k + 1])
                }
            } elif (op == 41) {
                ret_i = self->int_of(self->pop())
            } elif (op == 42) {
                ret_f = float_bits(self->float_of(self->pop()))
            } elif (op == 43) {
                self->push(0, ret_i)
            } elif (op == 44) {
                self->push(1, ret_f)
            } elif (op == 45) {
                sp--
                let a = stack[sp]
                if (a == 0) {
                    return ret_i
                }
                pc = a
                len = int(sc.code[pc + 1])
                if (int(int8(sc.code[pc])) == 34) {
                    len = (rd16s(sc, pc + 2) - 1) * 8 + 12
                }
            } elif (op == 46) {
                self->push(0, self->int_of(self->pop()))
            } elif (op == 47) {
                self->push(1, float_bits(self->float_of(self->pop())))
            } elif (op == 48) {
                stack[sp] = pc
                sp++
                pc += rd32(sc, pc + 4)
                jumped = true
            } elif (op == 49) {
                let id = rd16s(sc, pc + 2)
                if (host == null || !host->native(self, id)) {
                    if (unsupported == "") {
                        unsupported = "native {id}"
                    }
                    ret_i = 0
                }
            } elif (op == 50) {
                stack[sp + rd16s(sc, pc + 2)] = self->value_word(self->pop())
            } elif (op == 51 || op == 52) {
                let off = rd16s(sc, pc + 4)
                let t = rd16s(sc, pc + 6) == 2 ? 55 : 54
                self->push(t, op == 51 ? VM_STACK_ADDR + bp + off : VM_GLOBAL_ADDR + off)
            } elif (op == 53) {
                self->push(0, VM_CODE_ADDR + pc + 2)
            } elif (op != -1) {
                unsupported = "opcode {op}"
                return ret_i
            }
            if (!jumped) {
                pc += len
            }
        }
        unsupported = "ran off the code"
        return ret_i
    }

    // the raw word of a cell's value (store.local keeps floats as bits)
    def value_word(c : VmCell) : int {
        var kind = 0
        return self->value(c, kind)
    }
}

def private rd32(sc : VmScript; o : int) : int {
    return int(uint(sc.code[o]) | (uint(sc.code[o + 1]) << 8u) | (uint(sc.code[o + 2]) << 16u) |
        (uint(sc.code[o + 3]) << 24u))
}

def private rd16s(sc : VmScript; o : int) : int {
    return int(int16(uint(sc.code[o]) | (uint(sc.code[o + 1]) << 8u)))
}

def float_bits(f : float) : int {
    return unsafe(reinterpret<int>(f))
}

def bits_float(i : int) : float {
    return unsafe(reinterpret<float>(i))
}
