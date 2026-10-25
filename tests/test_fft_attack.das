options gen2
options indenting = 4

// FFT Attack (scripts/games/fft/fft_attack.das) against the game's
// forecast: Ramza's turn (Mythril Sword, PA 6, Capricorn, male) at (6, 3)
// attacking Lezales at (5, 3) (Knight, Mythril Shield, Iron Sword, Weapon
// Guard). The game showed 42 HP 66% (Lezales facing Ramza); by edits in
// the state (research/fft/plan_probe.lua): facing +y / -y 74%, -x 100%;
// Lezales' zodiac Taurus 49, Aries 35, Cancer 21 (male + male, opposite).
//   battlecalc tests/test_fft_attack.das --state <fft_test_ramza2.State> [--battle2 <fft_test_battle2.State>]
require gba_mem
require gui_common
require math
require daslib/strings_boost
require ../scripts/games/fft/fft_battle.das
require ../scripts/games/fft/fft_attack.das
require ../scripts/games/fft/fft_abilities.das
require ../scripts/games/fft/fft_reactions.das

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

def set_status(var u : FftUnit; n : int) {
    u.status[n >> 3] = uint8(uint(u.status[n >> 3]) | (0x80u >> uint(n & 7)))
}

def set_skill(var u : FftUnit; id : int; on : bool) {
    let i = id - 0x1A6
    let m = 0x80u >> uint(i & 7)
    u.skills[i >> 3] = uint8(on ? (uint(u.skills[i >> 3]) | m) : (uint(u.skills[i >> 3]) & ~m))
}

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<FftUnit>
    check("battle read", read_battle(units) == "")
    let ri = find_unit(units, "Ramza")
    let li = find_unit(units, "Lezales")
    check("units found", ri >= 0 && li >= 0)
    if (ri < 0 || li < 0) {
        return 1
    }
    let ramza = units[ri]
    var lez = units[li]
    let w = unit_weapon(ramza)
    check("Ramza's weapon {w.name} WP {w.wp}", w.name == "Mythril Sword" && w.wp == 7 && w.kind == IT_SWORD)
    check("Lezales: class {class_evade(lez)} shield {shield_evade(lez)} weapon {unit_weapon(lez).w_ev}",
        class_evade(lez) == 10 && shield_evade(lez) == 22 && unit_weapon(lez).w_ev == 5)
    check("Lezales' reaction {ability_name(lez.reaction)}", ability_name(lez.reaction) == "Weapon Guard")
    let f = attack_forecast(ramza, lez)
    check("front: {f.damage_min} {f.hit}%, the game: 42 66%", f.damage_min == 42 && f.damage_max == 42 && f.hit == 66)
    let sides = fixed_array<int>(74, 100, 74, 66)
    for (facing in range(4)) {
        lez.facing = facing
        let g = attack_forecast(ramza, lez)
        check("facing {facing}: {g.hit}%, the game: {sides[facing]}%", g.hit == sides[facing])
    }
    lez.facing = units[li].facing
    let zod = fixed_array<tuple<int; int>>((1, 49), (0, 35), (3, 21), (8, 42))
    for (z in zod) {
        lez.zodiac = z._0
        let g = attack_forecast(ramza, lez)
        check("zodiac {ZODIAC_NAMES[z._0]}: {g.damage_min}, the game: {z._1}", g.damage_min == z._1)
    }
    // other weapons in Ramza's right hand (+0x1D edited), at Lezales:
    // Dagger (WP 3) (PA + Speed) / 2 x WP = 18; Defender (WP 16) PA x Br /
    // 100 x WP = 3 x 16 = 48; Battle Axe (WP 9) rand(1..PA) x WP - the
    // game showed one roll, 36 = 4 x 9
    lez.zodiac = units[li].zodiac
    var armed = ramza
    for (wc in fixed_array<int3>(int3(1, 18, 18), int3(0x21, 48, 48), int3(0x30, 9, 54))) {
        armed.equip[3] = wc.x
        let g = attack_forecast(armed, lez)
        check("{item_name(wc.x)}: {g.damage_min}..{g.damage_max} {g.hit}%, the game: {wc.y}..{wc.z} 66%",
            g.damage_min == wc.y && g.damage_max == wc.z && g.hit == 66)
    }
    // supports and statuses set in RAM (statuses +0x58, ability bits
    // +0x8B), the game's forecast at Lezales (base 42, 66%)
    for (mc in fixed_array<tuple<string; int; int>>(("Attack UP", 56, 66), ("Defense UP", 28, 66), ("Protect", 28, 66),
            ("Berserk", 63, 66), ("Sleep", 63, 100), ("Charging", 63, 100), ("Concentrate", 42, 100), ("Darkness", 42, 40),
            ("Chicken", 63, 66), ("Frog", 63, 66), ("Defending", 42, 40), ("no Weapon Guard", 42, 70), ("bare hands", 18, 66),
            ("Martial Arts", 27, 66))) {
        var a = ramza
        var t = units[li]
        a.equip[3] = ramza.equip[3]
        let what = mc._0
        if (what == "Attack UP") {
            set_skill(a, int(0x1D1), true)
        } elif (what == "Defense UP") {
            set_skill(t, int(0x1D2), true)
        } elif (what == "Protect") {
            set_status(t, 26)
        } elif (what == "Berserk") {
            set_status(a, 20)
        } elif (what == "Sleep") {
            set_status(t, 35)
        } elif (what == "Charging") {
            set_status(t, 4)
        } elif (what == "Concentrate") {
            set_skill(a, int(0x1D5), true)
        } elif (what == "Darkness") {
            set_status(a, 10)
        } elif (what == "Chicken") {
            set_status(t, 21)
        } elif (what == "Frog") {
            set_status(t, 22)
        } elif (what == "Defending") {
            set_status(t, 6)
        } elif (what == "no Weapon Guard") {
            set_skill(t, int(0x1BF), false)
        } elif (what == "bare hands") {
            a.equip[3] = 0xFF
        } elif (what == "Martial Arts") {
            a.equip[3] = 0xFF
            set_skill(a, int(0x1D8), true)
        }
        let g = attack_forecast(a, t)
        check("{what}: {g.damage_min} {g.hit}%, the game: {mc._1} {mc._2}%", g.damage_min == mc._1 && g.hit == mc._2)
    }
    // reactions set in Lezales' bits (+0x8B..): Blade Grasp with Weapon
    // Guard 26%, without 28%, at Brave 90 7%; Abandon (no Weapon Guard) 44%
    for (rc in fixed_array<tuple<string; int>>(("BG + WG", 26), ("BG", 28), ("BG Brave 90", 7), ("Abandon", 44))) {
        var t = units[li]
        let what = rc._0
        if (what != "BG + WG") {
            set_skill(t, int(0x1BF), false)
        }
        set_skill(t, what == "Abandon" ? int(0x1C1) : int(0x1C3), true)
        if (what == "BG Brave 90") {
            t.brave = 90
        }
        let g = attack_forecast(ramza, t)
        check("{what}: {g.hit}%, the game: {rc._1}%", g.hit == rc._1)
    }
    // Counter (the bit, Brave 100): the game struck back - and missed:
    // Ramza had turned to Lezales, so his front (Squire's class evade 10)
    var counter = units[li]
    set_skill(counter, int(0x1BF), false)
    set_skill(counter, int(0x1BA), true)
    counter.brave = 100
    let rc = reaction_to(ramza, counter, FftAbility(), 42)
    check("Counter: {reaction_text(rc)}", rc.triggers && rc.counter && rc.chance == 100 && rc.counter_min == 42
        && rc.counter_hit == 90)
    // A Save (Brave 100): PA +1 after the hit, seen
    var asave = units[li]
    set_skill(asave, int(0x1BF), false)
    set_skill(asave, int(0x1A6), true)
    let ra = reaction_to(ramza, asave, FftAbility(), 42)
    check("A Save: {reaction_text(ra)}", ra.triggers && ra.id == 0x1A6)
    // elements (the record's +0x6D..+0x71 edited): Ice Brand (WP 13, Ice)
    // at Lezales 78; Ice weak 156, half 39; Ramza's Ice Strengthen 91
    for (ec in fixed_array<tuple<string; int>>(("none", 78), ("weak", 156), ("half", 39), ("strengthen", 91))) {
        var a = ramza
        var t = units[li]
        a.equip[3] = 0x1D
        if (ec._0 == "weak") {
            t.elements[3] = uint8(0x20)
        } elif (ec._0 == "half") {
            t.elements[2] = uint8(0x20)
        } elif (ec._0 == "strengthen") {
            a.elements[4] = uint8(0x20)
        }
        let g = attack_forecast(a, t)
        check("Ice Brand, {ec._0}: {g.damage_min} {g.hit}%, the game: {ec._1} 66%", g.damage_min == ec._1 && g.hit == 66)
    }
    // a Long Bow shot from +y: Ramza moved in the game to (5, 6), Lezales
    // at (5, 3) with his facing edited: 0 -> 100% (his back: 0 is -y),
    // 2 -> 66% (his front), 1 / 3 -> 74% (his side)
    let from_y = fixed_array<int>(100, 74, 66, 74)
    for (facing in range(4)) {
        var archer = ramza
        archer.equip[3] = 0x53
        archer.x = 5
        archer.y = 6
        var t = units[li]
        t.facing = facing
        let g = attack_forecast(archer, t)
        check("bow from +y, facing {facing}: {g.hit}%, the game: {from_y[facing]}%", g.hit == from_y[facing])
    }
    // --battle2 (Gariland, Barney's turn): Barney (Dagger, PA 4, Sp 6,
    // Scorpio, male) at Candy (Taurus, female: the best pair, XA 5 -> 7)
    // next to him; the game: front 21 95%, back / side 21 100% (no
    // shield), Broad Sword 24, bare hands 12 = PA 4 -> 6 x (4 x 55 / 100);
    // Dash 18 = one roll of PA 6 x rand(1..4)
    let b2 = gui_arg("--battle2", "")
    if (b2 != "") {
        check("battle 2 loads", gba_load_state(b2) == "")
        var bu : array<FftUnit>
        read_battle(bu)
        let bi = find_unit(bu, "Barney")
        let ci = find_unit(bu, "Candy")
        check("Barney and Candy", bi >= 0 && ci >= 0)
        if (bi >= 0 && ci >= 0) {
            let cases = fixed_array<tuple<string; int; int; int; int>>(("front", 0, 1, 21, 95), ("back", 2, 1, 21, 100),
                ("side", 1, 1, 21, 100), ("Broad Sword", 0, 19, 24, 95), ("bare hands", 0, 255, 12, 95))
            for (c in cases) {
                var a = bu[bi]
                var t = bu[ci]
                t.facing = c._1
                a.equip[3] = c._2
                let g = attack_forecast(a, t)
                check("Barney at Candy, {c._0}: {g.damage_min}-{g.damage_max} {g.hit}%, the game: {c._3} {c._4}%",
                    g.damage_min == c._3 && g.damage_max == c._3 && g.hit == c._4)
            }
            let d = ability_forecast(bu[bi], bu[ci], read_ability(147))
            check("Dash: {d.amount_min}-{d.amount_max} {d.hit}%, the game: 18 (a roll) 100%",
                d.amount_min <= 18 && d.amount_max >= 18 && (18 % 6) == 0 && d.amount_min == 6 && d.hit == 100)
        }
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
