options gen2
options indenting = 4

// FFT Attack (scripts/games/fft/fft_attack.das) against the game's
// forecast: Ramza's turn (Mythril Sword, PA 6, Capricorn, male) at (6, 3)
// attacking Lezales at (5, 3) (Knight, Mythril Shield, Iron Sword, Weapon
// Guard). The game showed 42 HP 66% (Lezales facing Ramza); by edits in
// the state (research/fft/plan_probe.lua): facing +y / -y 74%, -x 100%;
// Lezales' zodiac Taurus 49, Aries 35, Cancer 21 (male + male, opposite).
//   battlecalc tests/test_fft_attack.das --state <fft_test_ramza2.State>
require gba_mem
require gui_common
require math
require daslib/strings_boost
require ../scripts/games/fft/fft_battle.das
require ../scripts/games/fft/fft_attack.das

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
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
