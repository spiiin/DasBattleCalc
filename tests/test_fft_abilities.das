options gen2
options indenting = 4

// FFT abilities (scripts/games/fft/fft_abilities.das) against the game's
// forecasts: Ramza's turn (PA 6, MA 4, Faith 63, Mythril Sword WP 7,
// Capricorn) at Lezales (Knight, Faith 51, Mythril Shield 22 / 5,
// Weapon Guard, facing Ramza). The other skillsets were given to Ramza in
// RAM (secondary +0x13, all learned at +0x99) by research/fft/plan_probe.
// Dash and Throw Stone: the forecast shows one roll of rand(1..Y) - 3 and
// 2 in this state - so the game's number is PA' x that roll. Also Wish
// (caster's max HP / 5 x 2), Chakra, Potion, Charge with a bow at Viggs.
//   battlecalc tests/test_fft_abilities.das --state <fft_test_ramza2.State> [--throw <fft_test_throw.State>] [--battle2 <fft_test_battle2.State>]
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
    // + Wish (152) 44, Potion (368) 30; Shield / Weapon / Armor Break (140,
    // 141, 139) 44 / 28 / 34
    let cases = fixed_array<tuple<int; int; int>>((147, 18, 100), (148, 12, 66), (138, 0, 38), (144, 0, 36), (142, 9, 36),
        (16, 17, 95), (1, 17, 100), (34, 0, 56), (28, 0, 49), (155, 54, 100), (165, 42, 100), (152, 44, 100), (368, 30, 100),
        (140, 0, 44), (141, 0, 28), (139, 0, 34))
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
    // Chakra on himself: PA x 5
    let fc = ability_forecast(ramza, ramza, read_ability(106))
    check("Chakra: {fc.amount_min}, the game: 30", fc.amount_min == 30)
    // Wish by the caster's max HP: 200 -> 80, 100 -> 40
    for (wc in fixed_array<int2>(int2(200, 80), int2(100, 40))) {
        var r2 = ramza
        r2.max_hp = wc.x
        r2.hp = wc.x
        let fw = ability_forecast(r2, lez, read_ability(152))
        check("Wish, max HP {wc.x}: {fw.amount_min}, the game: {wc.y}", fw.amount_min == wc.y)
    }
    // Charge with a Long Bow at Viggs (side, no shield): (PA + Speed) / 2
    // + K, x WP 4: +1 -> 28, +4 -> 40; Attack 24
    let vi = find_unit(units, "Viggs")
    if (vi >= 0) {
        var archer = ramza
        archer.equip[3] = 0x53
        let fa = attack_forecast(archer, units[vi])
        check("bow at Viggs: {fa.damage_min} {fa.hit}%, the game: 24 100%", fa.damage_min == 24 && fa.hit == 100)
        for (cc in fixed_array<int2>(int2(0x196, 28), int2(0x199, 40))) {
            let fq = ability_forecast(archer, units[vi], read_ability(cc.x))
            check("{ability_name(cc.x)}: {fq.amount_min} {fq.hit}%, the game: {cc.y} 100%", fq.amount_min == cc.y && fq.hit == 100)
        }
    }
    var taurus = lez
    taurus.zodiac = 1
    let fz = ability_forecast(ramza, taurus, read_ability(147))
    check("Dash at Taurus: {fz.amount_min * 3}, the game: 21", fz.amount_min * 3 == 21)
    // Fire at Lezales with his elements edited (+0x6D absorb, cancel,
    // half, weak; Ramza's +0x71 strengthen): +17, 0%, 8, 35, 22
    for (ec in fixed_array<tuple<int; int; int; bool>>((0, 17, 95, true), (1, 0, 0, false), (2, 8, 95, false),
            (3, 35, 95, false), (4, 22, 95, false))) {
        var a = ramza
        var t = lez
        if (ec._0 == 4) {
            a.elements[4] = uint8(0x80)
        } else {
            t.elements[ec._0] = uint8(0x80)
        }
        let f = ability_forecast(a, t, read_ability(16))
        check("Fire, element field {ec._0}: {f.amount_min} {f.hit}% heal {f.heal}, the game: {ec._1} {ec._2}%",
            (ec._2 == 0 || f.amount_min == ec._1) && f.hit == ec._2 && f.heal == ec._3)
    }
    // Jump (Ramza given Jump in RAM; no evade): Mythril Sword 42, Spear
    // (WP 9) 81 = PA 6 x 3 / 2 x 9, bare hands 18 = 6 x (6 x 56 / 100),
    // Lezales with Protect 28
    let jump = read_ability(394)
    for (jc in fixed_array<tuple<string; int>>(("sword", 42), ("spear", 81), ("bare", 18), ("protect", 28))) {
        var a = ramza
        var t = lez
        if (jc._0 == "spear") {
            a.equip[3] = 100
        } elif (jc._0 == "bare") {
            a.equip[3] = 0xFF
        } elif (jc._0 == "protect") {
            t.status[3] = uint8(uint(t.status[3]) | 0x20u)
        }
        let f = ability_forecast(a, t, jump)
        check("Jump, {jc._0}: {f.amount_min} {f.hit}%, the game: {jc._1} 100%", f.amount_min == jc._1 && f.hit == 100)
    }
    // --throw: the stock with Broad Sword, Defender, Shuriken, Magic
    // Shuriken; the game: Speed 6 x WP - 24, 96, 24, 42 at 66%. Throw by
    // type takes the best in stock: Shuriken -> Magic Shuriken 42, Sword
    // -> Broad Sword 24, Knight Sword -> Defender 96
    let throw_state = gui_arg("--throw", "")
    if (throw_state != "") {
        check("throw state loads", gba_load_state(throw_state) == "")
        var tu : array<FftUnit>
        read_battle(tu)
        let tr = tu[find_unit(tu, "Ramza")]
        let tl = tu[find_unit(tu, "Lezales")]
        for (tc in fixed_array<tuple<int; int>>((382, 42), (384, 24), (391, 96))) {
            let ab = read_ability(tc._0)
            let f = ability_forecast(tr, tl, ab)
            check("Throw {ab.name}: {f.effect} {f.amount_min} {f.hit}%, the game: {tc._1} 66%",
                f.amount_min == tc._1 && f.hit == 66)
        }
    }
    // --battle2 (Gariland): Barney given Black Magic and MP 99 at Candy
    // (Scorpio vs Taurus: the best pair, x 3 / 2 on MA + X) - the game:
    // Poison 95%, Frog 71%, Death 60% (the prologue at Orbonne shows 0%
    // for Frog / Death on everyone)
    let b2 = gui_arg("--battle2", "")
    if (b2 != "") {
        check("battle 2 loads", gba_load_state(b2) == "")
        var bu : array<FftUnit>
        read_battle(bu)
        let bi = find_unit(bu, "Barney")
        let ci = find_unit(bu, "Candy")
        if (bi >= 0 && ci >= 0) {
            var barney = bu[bi]
            barney.mp = 99
            for (sc in fixed_array<tuple<int; int>>((28, 95), (29, 71), (30, 60))) {
                let f = ability_forecast(barney, bu[ci], read_ability(sc._0))
                check("{ability_name(sc._0)} at Candy: {f.hit}%, the game: {sc._1}%", f.hit == sc._1)
            }
        }
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
