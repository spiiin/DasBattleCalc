options gen2
options indenting = 4

// FFT: The War of the Lions: the units and tables of the first battle
// (Orbonne Monastery, Ramza's turn), from the PPSSPP state's RAM.
//   battlecalc tests/test_fftwotl_battle.das --state <fftwotl_test_battle1.ppst> [--print 1]
require gba_mem
require gui_common
require ../scripts/games/fftwotl/fftwotl_data.das
require ../scripts/games/fftwotl/fftwotl_battle.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

def find_unit(units : array<UnitW>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
}

[export]
def main() : int {
    let err = gba_load_state(gui_arg("--state", ""))
    check("state loads ({err})", err == "")
    check("the game is WotL", is_wotl_state())
    var units : array<UnitW>
    let berr = read_battle_w(units)
    check("battle reads ({berr})", berr == "")
    if (gui_arg("--print", "") != "") {
        for (u in units) {
            print("{u.slot} {u.name} [{u.job}] Lv{u.level} Br{u.brave} Fa{u.faith} HP {u.hp}/{u.max_hp} MP {u.mp}/{u.max_mp} PA {u.pa} MA {u.ma} SP {u.sp} CT {u.ct} Mv {u.move} Jp {u.jump} @{u.x},{u.y} team {u.team} {u.zodiac}\n")
            for (k in range(7)) {
                if (u.items[k] != ITEM_NONE) {
                    print("    {SLOT_W_NAMES[k]}: {u.equip[k].name} (kind {KIND_W_NAMES[u.equip[k].kind]}, WP {u.equip[k].wp})\n")
                }
            }
            print("    {skillset_name_w(u.primary)} / {skillset_name_w(u.secondary)}; R {ability_name_w(u.reaction)} S {ability_name_w(u.support)} M {ability_name_w(u.movement)}; status {status_text(u.status)}\n")
        }
    }
    check("11 units on the field (got {length(units)})", length(units) == 11)
    let r = find_unit(units, "AAAAA")
    check("Ramza: first record", r == 0)
    if (r >= 0) {
        let u = units[r]
        check("Ramza Lv 9, HP 111, MP 24, Br 53, Fa 47", u.level == 9 && u.max_hp == 111 && u.max_mp == 24 &&
            u.brave == 53 && u.faith == 47)
        check("Ramza at 6, 3; Capricorn; player", u.x == 6 && u.y == 3 && u.zodiac == "Capricorn" && u.team == TEAM_PLAYER)
        check("Ramza's job Squire (got {u.job})", u.job == "Squire")
    }
    let a = find_unit(units, "Agrias")
    check("Agrias: Holy Knight, HP 204, guest", a >= 0 && units[a].job == "Holy Knight" && units[a].max_hp == 204 &&
        units[a].team == TEAM_GUEST)
    check("tables: Dagger WP 3, Broadsword WP 4", read_item_w(1).wp == 3 && read_item_w(19).wp == 4)
    check("Potion: formula 0x48, X 3", read_item_w(240).formula == 0x48 && read_item_w(240).x == 3)
    let fire = read_ability_w(16)
    check("Fire: formula 8, Y 14, CT 4, MP 6, fire", fire.name == "Fire" && fire.formula == 8 && fire.y == 14 &&
        fire.ct == 4 && fire.mp == 6 && fire.element == 0x80)
    let sq = read_job_w(74)
    check("Squire: move 4, jump 3, C-EV 5, HP 11/100", sq.move == 4 && sq.jump == 3 && sq.c_ev == 5 && sq.hp_c == 11 &&
        sq.hp_m == 100)
    check("status 26 Protect, 38 Reflect", status_name_w(26) == "Protect" && status_name_w(38) == "Reflect")
    print("test_fftwotl_battle: {total - failed} / {total} passed\n")
    return failed == 0 ? 0 : 1
}
