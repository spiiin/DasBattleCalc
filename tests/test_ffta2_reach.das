options gen2
options indenting = 4

// FFTA2 reach (in_reach_on, ffta2_attack.das) against the tiles the game
// highlights: Luso at (9, 8) next to Sasarr, the reach builder's list
// (research/ffta2/reach_probe.lua -> reach1.txt, "keys | count x,y ...")
// with edited tile heights, Luso's weapon and the ability.
//   h=x,y,height  a tile's height; w Luso's weapon (slot 1); ab the ability
//   battlecalc tests/test_ffta2_reach.das --state <ffta2_test_attack.State> --rom <FFTA2 (USA)>.zip
require gba_mem
require gui_common
require strings
require daslib/strings_boost
require daslib/fio
require ../scripts/games/ffta2/ffta2_battle.das
require ../scripts/games/ffta2/ffta2_attack.das
require ./test_check.das

[export]
def main() : int {
    gba_load_rom(gui_arg("--rom", ""))
    gba_load_state(gui_arg("--state", ""))
    var units : array<Unit2>
    let err = read_battle2(units)
    var map0 : Map2
    if (err != "" || !read_map2(map0)) {
        print("FAIL battle / map {err}\n")
        return 1
    }
    var luso = -1
    for (i in range(length(units))) {
        if (units[i].name == "Luso") {
            luso = i
        }
    }
    for (line in split(fread("research/ffta2/reach1.txt"), "\n")) {
        let parts <- split(line, " | ")
        if (length(parts) != 2) {
            continue
        }
        // the state is at the target cursor after the move: the object
        // still has the old position (as in test_ffta2_attack.das)
        var att = units[luso]
        att.x = 9
        att.y = 8
        var m := map0
        var ability = ATTACK_ABILITY
        for (e in split(parts[0], " ")) {
            let kv <- split(e, "=")
            if (length(kv) != 2) {
                continue
            }
            if (kv[0] == "ab") {
                ability = to_int(kv[1])
            } elif (kv[0] == "w") {
                att.equip[0] = read_item2(to_int(kv[1]))
                att.items[0] = att.equip[0].id
            } elif (kv[0] == "h") {
                let p <- split(kv[1], ",")
                m.height[to_int(p[1]) * m.w + to_int(p[0])] = to_int(p[2])
            }
        }
        recompute_unit(att)
        let ab = read_ability2(ability)
        var want : array<string>
        let got <- split(parts[1], " ")
        for (i in range(1, length(got))) {
            want |> push(got[i])
        }
        var model : array<string>
        for (y in range(m.h)) {
            for (x in range(m.w)) {
                if (in_reach_on(att, ab, m, x, y)) {
                    model |> push("{x},{y}")
                }
            }
        }
        sort(want)
        sort(model)
        total++
        let ok = join(want, " ") == join(model, " ")
        if (!ok) {
            failed++
            var missing : array<string>
            var extra : array<string>
            for (t in want) {
                if (find_index(model, t) < 0) {
                    missing |> push(t)
                }
            }
            for (t in model) {
                if (find_index(want, t) < 0) {
                    extra |> push(t)
                }
            }
            print("FAIL {parts[0]} ({ab.name}, {att.equip[0].name}): missing {missing}, extra {extra}\n")
        }
    }
    return report()
}
