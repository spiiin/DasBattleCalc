options gen2
options indenting = 4

// Reads a struct from GBA memory (gba_mem): each field says where it is,
//   @offset = 0xD0 ct : uint16
// (hex in annotations needs daScript with fix-annotation-hex: it arrives
// as uint64). uint8 / uint16 / uint read 1 / 2 / 4 bytes; fixed arrays
// read consecutive elements.
module gba_struct shared public

require gba_mem
require daslib/apply
require daslib/rtti

def read_value(a : uint; var v : uint8&) {
    v = uint8(gba_read8(a))
}

def read_value(a : uint; var v : uint16&) {
    v = uint16(gba_read16(a))
}

def read_value(a : uint; var v : uint&) {
    v = gba_read32(a)
}

def read_value(a : uint; var v : auto(TT)&) {
    static_if (typeinfo is_dim(v)) {
        let stride = uint(typeinfo sizeof(v[0]))
        for (i in range(typeinfo dim(v))) {
            read_value(a + uint(i) * stride, v[i])
        }
    } else {
        concept_assert(false, "gba_struct: a field must be uint8, uint16, uint or a fixed array of them")
    }
}

def read_struct(base : uint; var value : auto(T)&) {
    apply(value) $(name : string; var field; annotations) {
        for (a in annotations) {
            if (a.name == "offset" && a.data is tUInt64) {
                read_value(base + uint(a.data as tUInt64), field)
            } elif (a.name == "offset" && a.data is tInt) {
                read_value(base + uint(a.data as tInt), field)
            }
        }
    }
}
