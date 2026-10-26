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
    // the editor's names and its recompute: unchanged, it gives the record's
    // derived fields back (the ability bits, the elements, the stats)
    check("job names: {job_name(74)}, {job_name(76)}, {job_name(78)}",
        job_name(74) == "Squire" && job_name(76) == "Knight" && job_name(78) == "Monk")
    check("skillset names: {skillset_name(5)}, {skillset_name(7)}, {skillset_name(20)}",
        skillset_name(5) == "Basic Skill" && skillset_name(7) == "Battle Skill" && skillset_name(20) == "Throw")
    for (un in units) {
        var c = un
        recompute_unit(c, un)
        var same = c.pa == un.pa && c.ma == un.ma && c.speed == un.speed && c.move == un.move && c.jump == un.jump
        for (k in range(11)) {
            same = same && c.skills[k] == un.skills[k]
        }
        for (k in range(5)) {
            same = same && c.elements[k] == un.elements[k]
        }
        check("{un.name}: the recompute gives the record back", same)
    }
    // the raw stats (+0x72): raw x the job's multiplier / 1638400 gives
    // the record's max HP / MP (without the equipment), Speed, PA, MA
    for (un in units) {
        var hpb = 0
        var mpb = 0
        for (s in range(EQUIP_SLOTS)) {
            let b = item_bonus(un.equip[s])
            hpb += b.hp
            mpb += b.mp
        }
        let rec = fixed_array<int>(un.max_hp - hpb, un.max_mp - mpb, int(gba_read8(un.record + 0x32u)),
            int(gba_read8(un.record + 0x30u)), int(gba_read8(un.record + 0x31u)))
        var same = true
        for (k in range(5)) {
            same = same && job_stat(un, un.job_id, k) == rec[k]
        }
        check("{un.name}: the raw stats x the job give the record's", same)
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
