options gen2
options indenting = 4

// The FFTA2 model (scripts/games/ffta2/ffta2_battle.das) on the first
// battle: the units, their names and jobs, and the stats of the Unit Info
// screens (research/ffta2/notes.md).
//   battlecalc tests/test_ffta2_battle.das --state <ffta2_test_battle1.State> --rom <FFTA2 (USA)>.zip
require gba_mem
require gui_common
require daslib/strings_boost
require daslib/fio
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

def find_item(name : string) : int {
    for (i in range(1, item_count())) {
        if (read_item2(i).name == name) {
            return i
        }
    }
    return 0
}

def find_ability(name : string) : int {
    for (i in range(1, ability_count())) {
        if (read_ability2(i).name == name) {
            return i
        }
    }
    return 0
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
    // the map: the height the game shows under the cursor on every tile
    // (research/ffta2/height_probe.lua, heights1.txt)
    var m : Map2
    check("the battle map", read_map2(m) && m.w == 12 && m.h == 12)
    var tiles = 0
    var wrong = 0
    for (line in split(fread("research/ffta2/heights1.txt"), "\n")) {
        let p <- split(line, " ")
        if (length(p) == 3) {
            tiles++
            if (map_height(m, to_int(p[0]), to_int(p[1])) * 16 != to_int(p[2])) {
                wrong++
            }
        }
    }
    check("map heights: {tiles} tiles, {wrong} differ", tiles == 144 && wrong == 0)
    // graphics sets: the palettes in RAM in the first battle are those of
    // these sets (research/ffta2/notes.md, "Unit graphics")
    var sets : array<string>
    for (un in units) {
        sets |> push("{un.name} {unit_gfx_set(un)}")
    }
    check("graphics sets: {sets}", join(sets, ", ") ==
        "Klesta 154, Sasarr 119, Kaveisl 119, Cid 62, Belissana 34, Moricad 24, Luso 61")
    // what a job can wear (job +67 bits by item kind)
    check("Soldier wears Broadsword", can_equip(1, read_item2(15)))
    check("Soldier wears Bronze Shield", can_equip(1, read_item2(find_item("Bronze Shield"))))
    check("Soldier does not wear White Staff", !can_equip(1, read_item2(142)))
    check("White Mage wears White Staff", can_equip(3, read_item2(142)))
    // the abilities of a job (taught by the equipment) and the learned
    // bytes (the Soldier's menu reads +0x52 + 0x98 for First Aid)
    let soldier <- [for (a in job_abilities(1)); read_ability2(a).name]
    check("Soldier: {soldier}", join(soldier, ", ") ==
        "First Aid, Rend Power, Rend Magick, Rend MP, Rend Speed, Mug Gil, Provoke, Gauge")
    check("Spellblade is job number 35 in the items", job_number(40) == 35)
    let blades <- [for (a in job_abilities(40)); read_ability2(a).name]
    check("Spellblade: {blades}", length(blades) == 8 && blades[1] == "Oil Blade")
    check("First Aid: Hume byte 0x98", learn_slot(read_ability2(39), 1) == 0x98)
    if (cid >= 0) {
        let sl = learn_slot(read_ability2(find_ability("Body Slam")), job_class(units[cid].job_id))
        check("Cid mastered Body Slam ({sl})", sl >= 0 && (uint(units[cid].learned[sl]) & 0x80u) != 0u)
    }
    for (un in units) {
        print("{un.name} ({un.race} {un.job}) Lv{un.level} HP {un.hp}/{un.max_hp} MP {un.mp}/{un.max_mp} {un.position} CT {un.ct} team {fmt(":02X", un.team_byte)} stats {un.stat_total}\n")
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
