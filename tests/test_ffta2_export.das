options gen2
options indenting = 4

// FFTA2 state export (export_battle2, ffta2_battle.das; the melonDS
// waterbox image, native/nds_mem.cpp): edit units, write a new state,
// load it and read the same units back.
//   battlecalc tests/test_ffta2_export.das --state <ffta2_test_battle1.State> --rom <FFTA2 (USA)>.zip --out <new.State>
require gba_mem
require gui_common
require strings
require math
require daslib/strings_boost
require ../scripts/games/ffta2/ffta2_battle.das
require ../scripts/games/ffta2/ffta2_attack.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

def find_unit(units : array<Unit2>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
}

// what the export writes, as text
def key(u : Unit2) : string {
    return ("{u.job_id} {u.level} {u.base_speed} {u.hp} {u.max_hp} {u.mp} {u.max_mp} {u.raw} {u.items} {u.reaction} " +
        "{u.support} {u.status} {u.learned} {u.speed} {u.ct}")
}

[export]
def main() : int {
    let out = gui_arg("--out", "")
    check("--out given", out != "")
    check("rom loads", gba_load_rom(gui_arg("--rom", "")) == "")
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<Unit2>
    check("battle read", read_battle2(units) == "")
    let luso = find_unit(units, "Luso")
    let cid = find_unit(units, "Cid")
    if (luso < 0 || cid < 0 || out == "") {
        print("FAIL {failed + 1} of {total + 1}\n")
        return 1
    }
    var u & = unsafe(units[luso])
    u.hp = 33
    u.max_hp = 99
    u.mp = 5
    u.raw[0] = gui_arg_int("--attack", 200)
    u.items[0] = 16
    u.equip[0] = read_item2(16)
    u.status[26 >> 3] = uint8(uint(u.status[26 >> 3]) | (1u << uint(26 & 7)))    // Protect
    u.learned[0x98] = 0x80u8                                                       // First Aid mastered
    u.ct = 77
    units[cid].hp = 1
    let err = export_battle2(units, out)
    check("export: {err}", err == "")
    check("the exported state loads", gba_load_state(out) == "")
    var back : array<Unit2>
    check("battle read back", read_battle2(back) == "")
    check("same units", length(back) == length(units))
    for (i in range(min(length(back), length(units)))) {
        check("{units[i].name}: {key(back[i])} = {key(units[i])}", key(back[i]) == key(units[i]))
    }
    // --forecast N: the game's forecast of Luso's Attack on Sasarr in the
    // exported state (vary_probe.lua with PROBE_STATE = --out; the target
    // cursor state, Luso moved to 9, 8)
    let want = gui_arg_int("--forecast", -1)
    let sasarr = find_unit(back, "Sasarr")
    if (want >= 0 && sasarr >= 0) {
        var att = back[luso]
        att.x = 9
        att.y = 8
        let f = action2(att, back[sasarr], read_ability2(ATTACK_ABILITY), side_of2(att, back[sasarr]))
        check("forecast {f.damage} = the game's {want}", f.damage == want)
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
