options gen2
options indenting = 4

// FFTA2 turn order (scripts/games/ffta2/ffta2_turns.das) against 17
// turns recorded in the game from the first battle's state
// (research/ffta2/ct_probe.lua, ct1.txt): the clan waits each turn, Cid
// and the cockatrices move and act, Klesta acts without moving.
//   battlecalc tests/test_ffta2_turns.das --state <ffta2_test_battle1.State> --rom <FFTA2 (USA)>.zip
require gba_mem
require gui_common
require ../scripts/games/ffta2/ffta2_battle.das
require ../scripts/games/ffta2/ffta2_turns.das

// name, CT when the turn starts, ticks before it
let EXPECTED = fixed_array<tuple<string; int; int>>(
    ("Luso", 144, 0), ("Moricad", 142, 0), ("Cid", 136, 0), ("Belissana", 132, 0), ("Klesta", 118, 0),
    ("Sasarr", 114, 0), ("Kaveisl", 114, 0), ("Luso", 151, 1), ("Moricad", 148, 1), ("Belissana", 143, 1),
    ("Klesta", 107, 1), ("Luso", 101, 1), ("Moricad", 154, 2), ("Belissana", 154, 2), ("Cid", 152, 2),
    ("Sasarr", 128, 2), ("Kaveisl", 128, 2))

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
    for (u in units) {
        u.assumed = u.team == TEAM_PLAYER ? TurnEnd2.Wait : (u.name == "Klesta" ? TurnEnd2.ActOnly : TurnEnd2.MoveAndAct)
    }
    let turns <- predict_turns2(units, length(EXPECTED))
    var failed = 0
    for (k in range(length(EXPECTED))) {
        let e = EXPECTED[k]
        let t = turns[k]
        let ok = units[t.unit].name == e._0 && t.ct == e._1 && t.tick == e._2
        if (!ok) {
            failed++
            print("FAIL turn {k + 1}: game {e._0} CT {e._1} tick {e._2}, model {units[t.unit].name} CT {t.ct} tick {t.tick}\n")
        }
    }
    print(failed == 0 ? "PASS {length(EXPECTED)} turns\n" : "FAIL {failed} of {length(EXPECTED)}\n")
    return failed == 0 ? 0 : 1
}
