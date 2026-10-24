options gen2
options indenting = 4

// The FFTA2 model (scripts/games/ffta2/ffta2_battle.das) on the first
// battle: the units, their names and jobs, and the stats of the Unit Info
// screens (research/ffta2/notes.md).
//   battlecalc tests/test_ffta2_battle.das --state <ffta2_test_battle1.State> --rom <FFTA2 (USA)>.zip
require gba_mem
require gui_common
require daslib/strings_boost
require ../scripts/games/ffta2/ffta2_battle.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

def find_unit(units : array<Unit2>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
}

// Attack, Defense, Magick, Resistance, Speed, Evasion, Move, Jump
def check_stats(units : array<Unit2>; name : string; want : int[8]) {
    let i = find_unit(units, name)
    check("{name} is in the battle", i >= 0)
    if (i < 0) {
        return
    }
    for (s in range(STAT2_COUNT)) {
        let got = units[i].stat_total[s]
        check("{name} {STAT2_LABELS[s]} {want[s]} (got {got})", got == want[s])
    }
}

[export]
def main() : int {
    check("rom loads", gba_load_rom(gui_arg("--rom", "")) == "")
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<Unit2>
    let err = read_battle2(units)
    check("battle read ({err})", err == "")
    check("7 units (got {length(units)})", length(units) == 7)
    let names = join([for (un in units); un.name], ", ")
    check("names: {names}", names == "Klesta, Sasarr, Kaveisl, Cid, Belissana, Moricad, Luso")
    let luso = find_unit(units, "Luso")
    if (luso >= 0) {
        let un = units[luso]
        check("Luso: Hume Soldier ({un.race} {un.job})", un.race == "Hume" && un.job == "Soldier")
        check("Luso HP 90 / 90, MP 14 / 14", un.hp == 90 && un.max_hp == 90 && un.mp == 14 && un.max_mp == 14)
        check("Luso at 8, 7 (got {un.x}, {un.y})", un.x == 8 && un.y == 7)
        check("Luso: player", un.team == TEAM_PLAYER)
        check("Luso's weapon Shortsword ({un.equip[0].name})", un.equip[0].name == "Shortsword")
    }
    let cid = find_unit(units, "Cid")
    check("Cid: guest Bangaa Warrior", cid >= 0 && units[cid].team == TEAM_GUEST && units[cid].race == "Bangaa" &&
        units[cid].job == "Warrior")
    let klesta = find_unit(units, "Klesta")
    check("Klesta: enemy Crushatrice", klesta >= 0 && units[klesta].team == TEAM_ENEMY &&
        units[klesta].job == "Crushatrice")
    check_stats(units, "Luso", fixed_array<int>(44, 51, 15, 27, 57, 5, 4, 2))
    check_stats(units, "Moricad", fixed_array<int>(34, 35, 28, 58, 56, 0, 3, 2))
    for (un in units) {
        print("{un.name} ({un.race} {un.job}) Lv{un.level} HP {un.hp}/{un.max_hp} MP {un.mp}/{un.max_mp} {un.position} CT {un.ct} team {fmt(":02X", un.team_byte)} stats {un.stat_total}\n")
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
