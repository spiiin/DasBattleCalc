options gen2
options indenting = 4

// FFT abilities (scripts/games/fft/fft_abilities.das) against the game's
// forecasts: Ramza's turn (PA 6, MA 4, Faith 63, Mythril Sword WP 7,
// Capricorn) at Lezales (Knight, Faith 51, Mythril Shield 22 / 5,
// Weapon Guard, facing Ramza). The other skillsets were given to Ramza in
// RAM (secondary +0x13, all learned at +0x99) by research/fft/plan_probe.
// Dash and Throw Stone: the forecast shows one roll of rand(1..Y) - 3 and
// 2 in this state - so the game's number is PA' x that roll.
//   battlecalc tests/test_fft_abilities.das --state <fft_test_ramza2.State>
require gba_mem
require gui_common
require math
require daslib/strings_boost
require ../scripts/games/fft/fft_battle.das
require ../scripts/games/fft/fft_attack.das
require ../scripts/games/fft/fft_abilities.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

def find_unit(units : array<FftUnit>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
}

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<FftUnit>
    check("battle read", read_battle(units) == "")
    let ri = find_unit(units, "Ramza")
    let li = find_unit(units, "Lezales")
    if (ri < 0 || li < 0) {
        check("units found", false)
        return 1
    }
    var ramza = units[ri]
    let lez = units[li]
    // what Ramza knows: Guts (0x1A) with Accumulate, Dash, Wish learned
    let known <- unit_abilities(ramza)
    var learned = ""
    for (k in known) {
        if (k.learned) {
            learned += " {ability_name(k.id)}"
        }
    }
    check("Ramza knows:{learned}", learned == " Accumulate Dash Wish")
    // (ability id, the game's amount, the game's hit %)
    let cases = fixed_array<tuple<int; int; int>>((147, 18, 100), (148, 12, 66), (138, 0, 38), (144, 0, 36), (142, 9, 36),
        (16, 17, 95), (1, 17, 100), (34, 0, 56), (28, 0, 49), (155, 54, 100), (165, 42, 100))
    for (c in cases) {
        let ab = read_ability(c._0)
        let f = ability_forecast(ramza, lez, ab)
        // Dash / Throw Stone: PA' x the roll (3 / 2)
        let roll = c._0 == 147 ? 3 : (c._0 == 148 ? 2 : 1)
        let amount = f.amount_min * roll
        check("{ab.name}: {amount} {f.hit}%, the game: {c._1} {c._2}%", amount == c._1 && f.hit == c._2)
    }
    // Dash with Ramza's PA edited: 7 -> 21, 10 -> 30; PA 6 at a Taurus
    // Lezales (good: 6 + 6 / 4 = 7) -> 21
    for (pc in fixed_array<int2>(int2(7, 21), int2(10, 30))) {
        ramza.pa = pc.x
        let f = ability_forecast(ramza, lez, read_ability(147))
        check("Dash PA {pc.x}: {f.amount_min * 3}, the game: {pc.y}", f.amount_min * 3 == pc.y)
    }
    ramza.pa = 6
    var taurus = lez
    taurus.zodiac = 1
    let fz = ability_forecast(ramza, taurus, read_ability(147))
    check("Dash at Taurus: {fz.amount_min * 3}, the game: 21", fz.amount_min * 3 == 21)
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
