options gen2
options indenting = 4

// FFT turn order (scripts/games/fft/fft_turns.das) against the game: from
// the second state of the first battle (Lavian's turn, Viggs stopped for
// 7 more ticks) the AI played on (research/fft/ct_probe.lua, ct2.txt):
// Lavian, then after 4 ticks Agrias, Lezales, Wezaleff (dead), Dish,
// Fukes, Rad; Viggs when Stop ends (7 ticks), Ramza after 10 ticks.
//   battlecalc tests/test_fft_turns.das --state <fft_test_battle1b.State>
//     [--charge <fft_test_charge.State>] [--haste <fft_test_haste.State>]
require gba_mem
require gui_common
require math
require daslib/strings_boost
require ../scripts/games/fft/fft_battle.das
require ../scripts/games/fft/fft_turns.das
require ./test_check.das


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
    // --charge: Ramza has set Fire (CT 4) on Lezales and acts no more
    // (assumed: Act only); the game (research/fft/ct_probe.lua): Gafgarion
    // +3 CT 101, Fire off at +4, Alicia and Lavian (dead) +7 CT 102, then
    // at +10 Agrias, Lezales, Wezaleff, Dish, Fukes, Rad with 100
    let charge_state = gui_arg("--charge", "")
    if (charge_state != "") {
        check("charge state loads", gba_load_state(charge_state) == "")
        var cu : array<FftUnit>
        check("charge battle read", read_battle(cu) == "")
        for (k in range(length(cu))) {
            if (cu[k].active) {
                cu[k].assumed = TurnEnd.ActOnly
            }
        }
        let cw = fixed_array<tuple<string; int; int>>(("Ramza", 0, 100), ("Gafgarion", 3, 101), ("Fire", 4, -1),
            ("Alicia", 7, 102), ("Lavian", 7, 102), ("Agrias", 10, 100), ("Lezales", 10, 100), ("Wezaleff", 10, 100),
            ("Dish", 10, 100), ("Fukes", 10, 100), ("Rad", 10, 100))
        let ct <- predict_turns(cu, length(cw))
        for (k in range(min(length(ct), length(cw)))) {
            let t = ct[k]
            let w = cw[k]
            let name = t.charge != 0 ? ability_name(t.charge) : cu[t.unit].name
            check("charge turn {k + 1}: {name} +{t.tick} CT {t.ct}, the game: {w._0} +{w._1} CT {w._2}",
                name == w._0 && t.tick == w._1 && (w._2 < 0 || t.ct == w._2))
        }
    }
    // --haste: Lezales with Haste (+0x5B 0x08, timer +0x61), Agrias with
    // Slow (0x04, +0x62); the game: Lezales 40 -> 67 in 3 ticks (9 a
    // tick), Agrias 40 -> 49 -> 61 -> 67 -> 70 (3 a tick). Gafgarion's
    // action then took Lezales' Haste away, so only the rates are checked.
    let haste_state = gui_arg("--haste", "")
    if (haste_state != "") {
        check("haste state loads", gba_load_state(haste_state) == "")
        var hu : array<FftUnit>
        check("haste battle read", read_battle(hu) == "")
        for (u in hu) {
            if (u.name == "Lezales") {
                check("Lezales with Haste: {tick_amount(u)} a tick, the game: 9", tick_amount(u) == 9)
            } elif (u.name == "Agrias") {
                check("Agrias with Slow: {tick_amount(u)} a tick, the game: 3", tick_amount(u) == 3)
            }
        }
    }
    return report()
}
