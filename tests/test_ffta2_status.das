options gen2
options indenting = 4

// FFTA2 status abilities (Sleep, Poison, Doom, Charm, ...) against the
// game's forecasts: Luso uses the ability on Sasarr with an edited target
// job or statuses of both (research/ffta2/status_cases.py ->
// vary_probe.lua -> status4.txt, "keys | hit damage"; the game shows
// 10001: no damage). The VM forecast (ffta2_forecast.das) runs every
// effect; the status effect's hit is the game's.
//   ab  the ability; tj Sasarr's job; st / sa a status of Sasarr / Luso
//   battlecalc tests/test_ffta2_status.das --state <ffta2_test_attack.State> --rom <FFTA2 (USA)>.zip
require gba_mem
require gui_common
require strings
require daslib/strings_boost
require daslib/fio
require ../scripts/games/ffta2/ffta2_battle.das
require ../scripts/games/ffta2/ffta2_forecast.das

var failed = 0
var total = 0

def find_unit(units : array<Unit2>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
}

def add_status(var u : Unit2; n : int) {
    u.status[n >> 3] = uint8(uint(u.status[n >> 3]) | (1u << uint(n & 7)))
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
    let luso = find_unit(units, "Luso")
    let sasarr = find_unit(units, "Sasarr")
    for (line in split(fread("research/ffta2/status4.txt"), "\n")) {
        let parts <- split(line, " | ")
        if (length(parts) != 2) {
            continue
        }
        var att = units[luso]
        var tgt = units[sasarr]
        var ability = 0
        for (e in split(parts[0], " ")) {
            let kv <- split(e, "=")
            let v = to_int(kv[1])
            if (kv[0] == "ab") {
                ability = v
            } elif (kv[0] == "tj") {
                set_job2(tgt, v)
            } elif (kv[0] == "st") {
                add_status(tgt, v)
            } elif (kv[0] == "sa") {
                add_status(att, v)
            }
        }
        recompute_unit(att)
        recompute_unit(tgt)
        let want <- split(parts[1], " ")
        let game_hit = to_int(want[0])
        let ab = read_ability2(ability)
        let f = vm_forecast(att, tgt, ab)
        // the first effect that applies: its hit (none: the game shows 0)
        var hit = 0
        var why = f.problem
        if (length(f.effects) > 0) {
            hit = f.effects[0].hit
            why = f.effects[0].problem
        }
        total++
        let ok = f.ok && why == "" && hit == game_hit && f.effect < 0
        if (!ok) {
            failed++
        }
        print("{ok ? "ok  " : "FAIL"} {parts[0]} ({ab.name}): game {game_hit}, vm {hit} {why}\n")
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
