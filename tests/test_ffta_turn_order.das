options gen2
options indenting = 4

// Replays the turn order recorded in the game (BizHawk, research/long.lua)
// from the first test save: the model must pick the same unit every turn
// when each turn ends the way it ended in the game.
//   battlecalc tests/test_ffta_turn_order.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
require gui_common
require strings
require gba_mem
require ../scripts/games/ffta/ffta_battle.das
require ./test_common.das

struct Expected {
    name : string
    how : TurnEnd
}

[export]
def main() : int {
    var units : array<BattleUnit>
    var err = load_test_units(units)
    if (err != "") {
        print("{err}\n")
        return 1
    }
    for (u in units) {
        print("{u.name}: lv {u.level} hp {u.hp}/{u.max_hp} speed {u.speed} (base {u.base_speed} items {u.item_speed}) ct {u.ct} reserve {u.reserve} side {u.side} order {u.order} status {u.status_text}\n")
    }
    let M = TurnEnd.MoveAndAct
    let A = TurnEnd.ActOnly
    let W = TurnEnd.WaitOnly
    var expected <- [
        Expected(name = "Marc", how = W), Expected(name = "Euver", how = M), Expected(name = "Montblanc", how = M),
        Expected(name = "Marc", how = W), Expected(name = "Lunais", how = M), Expected(name = "Judge", how = A),
        Expected(name = "Marc", how = W), Expected(name = "Euver", how = M), Expected(name = "Montblanc", how = M),
        Expected(name = "Marc", how = W), Expected(name = "Lunais", how = M), Expected(name = "Marc", how = W),
        Expected(name = "Euver", how = M), Expected(name = "Montblanc", how = M), Expected(name = "Marc", how = W),
        Expected(name = "Judge", how = A), Expected(name = "Lunais", how = M), Expected(name = "Marc", how = W),
        Expected(name = "Euver", how = M), Expected(name = "Montblanc", how = M), Expected(name = "Marc", how = W),
        Expected(name = "Lunais", how = M)]
    var failed = 0
    for (k in range(length(expected))) {
        var actor = -1
        var ticks = 0
        if (k == 0) {
            for (i in range(length(units))) {   // mid-turn in the save
                if (units[i].ct >= 1000) {
                    actor = i
                }
            }
        } else {
            actor = next_actor(units, ticks)
        }
        let got = actor >= 0 ? units[actor].name : "-"
        let ok = got == expected[k].name
        print("{k + 1}: {got} (ticks {ticks}) expected {expected[k].name} {ok ? "ok" : "FAIL"}\n")
        if (!ok) {
            failed++
        }
        if (actor >= 0) {
            end_turn(units[actor], expected[k].how)
        }
    }
    print(failed == 0 ? "PASS {length(expected)} turns\n" : "FAIL {failed} of {length(expected)}\n")
    return failed == 0 ? 0 : 1
}
