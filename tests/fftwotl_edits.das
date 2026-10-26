options gen2
options indenting = 4

// FFT: WotL tests: the edits of a forecast line ("<unit>:<offset>=<hex>
// ...", the probes' format) applied to the model's units.
module fftwotl_edits shared public

require strings
require daslib/strings_boost
require daslib/fio
require gui_common
require ../scripts/games/fftwotl/fftwotl_data.das
require ../scripts/games/fftwotl/fftwotl_battle.das

def hex_int(s : string) : int {
    var v = 0
    for (c in s) {
        let d = c >= '0' && c <= '9' ? c - '0' : (c >= 'a' && c <= 'f' ? c - 'a' + 10 : 0)
        v = v * 16 + d
    }
    return v
}

// one edit of the probe (record offset, value) as the model's field
def apply_edit(var u : UnitW; off, v : int) {
    if (off == 0x3E) {
        u.pa = v
    } elif (off == 0x3F) {
        u.ma = v
    } elif (off == 0x40) {
        u.sp = v
    } elif (off == 0x09) {
        u.zodiac_id = v >> 4
    } elif (off == 0x06) {
        u.gender = v
    } elif (off == 0x20) {
        u.items[SLOT_RIGHT] = v
        // the game keeps the record's current PA / MA / Speed (the new
        // item's bonus is not added by this edit)
        let pa = u.pa
        let ma = u.ma
        let sp = u.sp
        recompute_unit_w(u)
        u.pa = pa
        u.ma = ma
        u.sp = sp
    } elif (off == 0x2B) {
        u.brave = v
    } elif (off == 0x2D) {
        u.faith = v
    } elif (off >= 0x62 && off < 0x67) {
        u.status[off - 0x62] = uint8(v)
    } elif (off == 0x4B) {
        u.c_ev = v
    } elif (off == 0x51) {
        u.facing = v & 3
    } elif (off == 0x4F) {
        u.x = v
    } elif (off == 0x50) {
        u.y = v
    } elif (off == 0x77) {
        u.absorb = v
    } elif (off == 0x78) {
        u.cancel = v
    } elif (off == 0x79) {
        u.half = v
    } elif (off == 0x7A) {
        u.weak = v
    } elif (off >= 0x95 && off < 0xA0) {
        u.rsm_mask[off - 0x95] = uint8(v)
    } elif (off >= 0xA3 && off < 0xA3 + LEARNED_W_SIZE) {
        u.learned[off - 0xA3] = uint8(v)
    } elif (off == 0x05) {
        u.team_byte = v
        u.team = team_of_w(v)
    } elif (off == 0x16) {
        u.support = v               // the id alone: no effect in the game
    }
    // the game ignores the record's shield / accessory evades and
    // strengthen byte (+0x48..0x4A, +0x7B): from the equipment
}

def read_text(file : string) : string {
    var text = ""
    fopen("{gui_project_dir()}/research/fftwotl/{file}", "rb") $(f) {
        if (f != null) {
            text = fread(f)
        }
    }
    return text
}

// who == att_slot: the attacker, else the target
def apply_writes(var att, tgt : UnitW; spec : string; att_slot : int = 0) {
    for (wr in split(strip(spec), " ")) {
        if (wr == "") {
            continue
        }
        let colon = find(wr, ":")
        let eq = find(wr, "=")
        let who = to_int(slice(wr, 0, colon))
        let off = hex_int(slice(wr, colon + 1, eq))
        var vs = slice(wr, eq + 1)
        if (ends_with(vs, "/2")) {
            vs = slice(vs, 0, length(vs) - 2)
        }
        if (who == att_slot) {
            apply_edit(att, off, hex_int(vs))
        } else {
            apply_edit(tgt, off, hex_int(vs))
        }
    }
}
