options gen2
options indenting = 4

// FFTA2's formula scripts run by our VM (scripts/games/ffta2/ffta2_vm.das,
// ffta2_forecast.das) against the game's forecasts: Luso (moved to 9, 8)
// on Sasarr (10, 8), every ability of research/ffta2/abil1.txt.
//   battlecalc tests/test_ffta2_vm.das --state <ffta2_test_battle1.State> --rom <FFTA2 (USA)>.zip
//     [--data research/ffta2/abil1.txt] [--verbose 1]
require gba_mem
require gui_common
require daslib/fio
require strings
require daslib/strings_boost
require ../scripts/games/ffta2/ffta2_battle.das
require ../scripts/games/ffta2/ffta2_forecast.das

def find_unit(units : array<Unit2>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
}

[export]
def main() : int {
    gba_load_rom(gui_arg("--rom", ""))
    gba_load_state(gui_arg("--state", ""))
    var units : array<Unit2>
    let err = read_battle2(units)
    if (err != "") {
        print("FAIL {err}\n")
        return 1
    }
    let verbose = gui_arg_int("--verbose", 0) != 0
    var att = units[find_unit(units, "Luso")]
    let tgt = units[find_unit(units, "Sasarr")]
    att.x = 9
    att.y = 8
    var failed = 0
    var total = 0
    var problems : table<string; int>
    for (line in split(fread(gui_arg("--data", "research/ffta2/abil1.txt")), "\n")) {
        let p <- split(line, " ")
        if (length(p) < 3 || !starts_with(p[0], "ab")) {
            continue
        }
        let ab = read_ability2(to_int(slice(p[0], 2)))
        let f = vm_forecast(att, tgt, ab)
        total++
        let game_hit = to_int(p[1])
        let game_dmg = to_int(p[2])
        // 10001: the game found no effect for this target
        let ok = f.ok && (f.no_effect ? game_dmg == 10001 : f.hit == game_hit && (f.amount & 0xFFFF) == game_dmg)
        if (!ok) {
            failed++
            if (f.problem != "") {
                problems[f.problem] = (problems?[f.problem] ?? 0) + 1
            }
        }
        if ((!ok && f.problem == "") || verbose) {
            print("{ok ? "ok  " : "FAIL"} {ab.id} {ab.name}: game {game_hit} / {game_dmg}, vm {f.hit} / {f.amount} {f.problem}\n")
        }
    }
    for (k, v in keys(problems), values(problems)) {
        print("  {v} x {k}\n")
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
