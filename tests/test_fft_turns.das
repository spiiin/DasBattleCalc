options gen2
options indenting = 4

// FFT turn order (scripts/games/fft/fft_turns.das) against the game: from
// the second state of the first battle (Lavian's turn, Viggs stopped for
// 7 more ticks) the AI played on (research/fft/ct_probe.lua, ct2.txt):
// Lavian, then after 4 ticks Agrias, Lezales, Wezaleff (dead), Dish,
// Fukes, Rad; Viggs when Stop ends (7 ticks), Ramza after 10 ticks.
//   battlecalc tests/test_fft_turns.das --state <fft_test_battle1b.State>
require gba_mem
require gui_common
require math
require daslib/strings_boost
require ../scripts/games/fft/fft_battle.das
require ../scripts/games/fft/fft_turns.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<FftUnit>
    check("battle read", read_battle(units) == "")
    // the game's turns: unit, ticks since the state, CT at the turn
    let want = fixed_array<tuple<string; int; int>>(("Lavian", 0, 100), ("Agrias", 4, 104), ("Lezales", 4, 104),
        ("Wezaleff", 4, 104), ("Dish", 4, 104), ("Fukes", 4, 104), ("Rad", 4, 104), ("Viggs", 7, 108),
        ("Ramza", 10, 100))
    let turns <- predict_turns(units, length(want))
    check("{length(turns)} turns", length(turns) == length(want))
    for (k in range(min(length(turns), length(want)))) {
        let t = turns[k]
        let w = want[k]
        check("turn {k + 1}: {units[t.unit].name} +{t.tick} CT {t.ct}, the game: {w._0} +{w._1} CT {w._2}",
            units[t.unit].name == w._0 && t.tick == w._1 && t.ct == w._2)
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
