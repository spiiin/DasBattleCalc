options gen2
options indenting = 4

// Fight reach (can_fight in ffta_attack.das) against the game's own
// tile rule: research/range_probe.lua patched Marc's weapon and tile
// heights in the first test save, opened Fight and logged the result of
// 0x0809FEF0 for every tile (research/range_probe_log.txt, reach.py).
//   battlecalc tests/test_ffta_reach.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
require gui_common
require strings
require gba_mem
require ../scripts/games/ffta/ffta_battle.das
require ./test_common.das
require ../scripts/games/ffta/ffta_attack.das

def set_height(var m : BattleMap; x, y, h : int) {
    m.height[(y - m.y0) * m.w + (x - m.x0)] = h
}

[export]
def main() : int {
    var units : array<BattleUnit>
    var base : BattleMap
    var err = load_test_battle(units, base)
    if (err != "") {
        print("{err}\n")
        return 1
    }
    var marc = units[0]
    for (u in units) {
        if (u.name == "Marc") {
            marc = u
        }
    }
    var failed = 0
    // case: weapon, height patches (x, y, h), tiles the game accepted /
    // rejected; for bows and guns the number of accepted tiles
    let check = $(name : string; weapon : int; patches : array<int3>; yes, no : array<int2>; count : int) {
        var m := base
        for (p in patches) {
            set_height(m, p.x, p.y, p.z)
        }
        var a = marc
        a.equip[0] = read_item(uint(weapon))
        var ok = true
        for (t in yes) {
            var why = ""
            if (!can_fight(m, a, t.x, t.y, why)) {
                print("  {name}: {t} the game allows, model: {why}\n")
                ok = false
            }
        }
        for (t in no) {
            var why = ""
            if (can_fight(m, a, t.x, t.y, why)) {
                print("  {name}: {t} the game forbids, model: {why}\n")
                ok = false
            }
        }
        if (count >= 0) {
            var n = 0
            for (y in range(m.h)) {
                for (x in range(m.w)) {
                    var why = ""
                    if (can_fight(m, a, x + m.x0, y + m.y0, why)) {
                        n++
                    }
                }
            }
            ok = ok && n == count
            print("  {name}: {n} tiles in reach (game {count})\n")
        }
        print("{name}: {ok ? "ok" : "FAIL"}\n")
        if (!ok) {
            failed++
        }
    }
    check("sword", 1, [int3(8, 4, 13), int3(7, 5, 12), int3(7, 3, 7)],
        [int2(6, 4), int2(7, 3), int2(7, 5)], [int2(8, 4), int2(9, 4), int2(7, 6)], -1)
    check("sword, -4 / +3", 1, [int3(7, 3, 6), int3(7, 5, 13)], [int2(6, 4), int2(8, 4)], [int2(7, 3), int2(7, 5)], -1)
    check("spear", 189, [int3(8, 4, 11), int3(9, 4, 12), int3(7, 5, 12), int3(7, 6, 10)],
        [int2(6, 4), int2(5, 4), int2(7, 3), int2(7, 5), int2(8, 4), int2(9, 4)], [int2(7, 2), int2(7, 6), int2(8, 5)], -1)
    check("bow", 162, array<int3>(), array<int2>(), array<int2>(), 57)
    check("gun", 241, array<int3>(), array<int2>(), array<int2>(), 115)
    print(failed == 0 ? "PASS 5 cases\n" : "FAIL {failed}\n")
    return failed == 0 ? 0 : 1
}
