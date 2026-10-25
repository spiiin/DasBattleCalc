options gen2
options indenting = 4

// The FFT (PSX) model (scripts/games/fft/fft_battle.das) on the first
// battle (Orbonne Monastery): the units, their names and jobs, the
// numbers of the bottom panel, the map (MAP056: heights the cursor shows).
//   battlecalc tests/test_fft_battle.das --state <fft_test_battle1.State>
require gba_mem
require gui_common
require daslib/strings_boost
require ../scripts/games/fft/fft_battle.das

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
    let err = read_battle(units)
    check("battle read ({err})", err == "")
    let names = join([for (un in units); un.name], ", ")
    check("names: {names}", names == "Ramza, Agrias, Gafgarion, Alicia, Lavian, Lezales, Wezaleff, Viggs, Dish, Fukes, Rad")
    let r = find_unit(units, "Ramza")
    if (r >= 0) {
        let un = units[r]
        check("Ramza: Squire Lv 9 Exp 8", un.job == "Squire" && un.level == 9 && un.exp == 8)
        check("HP 113 / 113, MP 24 / 24", un.hp == 113 && un.max_hp == 113 && un.mp == 24 && un.max_mp == 24)
        check("Brave 56, Faith 63", un.brave == 56 && un.faith == 63)
        check("at 6, 3", un.x == 6 && un.y == 3)
        check("a player unit", un.team == TEAM_PLAYER)
    }
    let lez = find_unit(units, "Lezales")
    check("Lezales: enemy Knight, HP 135, MP 17, CT 80", lez >= 0 && units[lez].team == TEAM_ENEMY &&
        units[lez].job == "Knight" && units[lez].hp == 135 && units[lez].mp == 17 && units[lez].ct == 80)
    var m : FftMap
    check("the map 10 x 14", read_map(m) && m.w == 10 && m.h == 14)
    // the cursor from Ramza to +x: 11h, 10h, 9.5h, 8h
    check("heights 11 10 9.5 8", map_height(m, 6, 3) == 11.0 && map_height(m, 7, 3) == 10.0 &&
        map_height(m, 8, 3) == 9.5 && map_height(m, 9, 3) == 8.0)
    for (un in units) {
        print("{un.slot} {un.name} ({un.job}) Lv{un.level} HP {un.hp}/{un.max_hp} MP {un.mp}/{un.max_mp} Br {un.brave} Fa {un.faith} PA {un.pa} MA {un.ma} Sp {un.speed} CT {un.ct} Mv {un.move} Jp {un.jump} {un.position} team {un.team} eq {un.equip}\n")
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
