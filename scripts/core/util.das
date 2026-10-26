options gen2
options indenting = 4

// Small helpers every game uses: bits of byte arrays, item and ability
// names, lists as text.
module util shared public

require strings
require daslib/strings_boost

// bit n of a byte array, the first bit the highest of byte 0 (the PSX
// and PSP tables: statuses, abilities, equipment kinds)
def msb_bit(bytes; n : int) : bool {
    return (uint(bytes[n >> 3]) & (0x80u >> uint(n & 7))) != 0u
}

def set_msb_bit(var bytes; n : int; on : bool) {
    let m = 0x80u >> uint(n & 7)
    bytes[n >> 3] = uint8(on ? (uint(bytes[n >> 3]) | m) : (uint(bytes[n >> 3]) & ~m))
}

// bit n of a byte array, the first bit the lowest of byte 0 (GBA, NDS)
def lsb_bit(bytes; n : int) : bool {
    return (uint(bytes[n >> 3]) & (1u << uint(n & 7))) != 0u
}

def set_lsb_bit(var bytes; n : int; on : bool) {
    let m = 1u << uint(n & 7)
    bytes[n >> 3] = uint8(on ? (uint(bytes[n >> 3]) | m) : (uint(bytes[n >> 3]) & ~m))
}

// a name the game uses ("" and "-" mark unused entries of its tables)
def named(s : string) : bool {
    return s != "" && s != "-"
}

// the parts joined, or none when there are no parts
def join_or(parts : array<string>; sep, none : string) : string {
    return length(parts) > 0 ? join(parts, sep) : none
}
