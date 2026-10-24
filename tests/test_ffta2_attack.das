options gen2
options indenting = 4

// FFTA2 Fight (scripts/games/ffta2/ffta2_attack.das) against the game's
// forecasts: Luso (moved to 9, 8) attacks Sasarr (10, 8) in the first
// battle, with edited stats, equipment, facing and affinity
// (research/ffta2/vary_probe.lua; logs grid1, weapons1, hit1, hit2,
// elem1, elem2, min1, status1..3). A case: edits | hit damage.
//   a / d        Luso raw Attack / Sasarr raw Defense
//   w / s2 / s4  Luso's item in slot 1 / 3 / 5 (0: none); t Sasarr's slot 1
//   e            Evasion of Sasarr's item in slot 1; f Sasarr's facing (game's)
//   b            Luso's bare-hand power; af Sasarr's Fire affinity
//   sa / st      a status of Luso / Sasarr (record +0x28 bits, status1..3.txt)
//   sup / tsup   Luso's / Sasarr's support ability; tj Sasarr's job
//   battlecalc tests/test_ffta2_attack.das --state <ffta2_test_battle1.State> --rom <FFTA2 (USA)>.zip
require gba_mem
require gui_common
require strings
require daslib/strings_boost
require ../scripts/games/ffta2/ffta2_battle.das
require ../scripts/games/ffta2/ffta2_attack.das

let CASES = fixed_array<string>(
    "sa=10 | 99 20",
    "sa=36 | 99 20",
    "sa=37 | 99 15",
    "sa=16 | 99 26",
    "sa=13 | 70 17",
    "sa=54 | 99 17",
    "st=26 | 99 16",
    "st=15 | 99 17",
    "st=40 | 99 17",
    "st=41 | 99 18",
    "st=57 | 80 17",
    "st=27 | 100 17",
    "st=34 | 100 0",
    "st=46 w=30 | 99 40",
    "sup=851 | 99 20",
    "sup=869 | 99 23",
    "sup=865 | 99 17",
    "sup=856 w=30 | 99 40",
    "sup=856 | 99 17",
    "tsup=852 | 99 17",
    "tsup=876 f=2 | 99 17",
    "tsup=881 | 99 17",
    "t=293 w=30 | 90 65509",
    "t=333 w=30 | 99 8",
    "t=363 w=30 | 99 65514",
    "tj=135 | 99 25",
    "tj=135 f=2 | 99 25",
    "a=0 d=0 | 99 11",
    "a=0 d=32 | 99 9",
    "a=0 d=66 | 99 6",
    "a=0 d=100 | 99 4",
    "a=0 d=160 | 99 1",
    "a=0 d=240 | 99 1",
    "a=0 d=400 | 99 1",
    "a=0 d=800 | 99 1",
    "a=40 d=0 | 99 16",
    "a=40 d=32 | 99 14",
    "a=40 d=66 | 99 11",
    "a=40 d=100 | 99 9",
    "a=40 d=160 | 99 6",
    "a=40 d=240 | 99 1",
    "a=40 d=400 | 99 1",
    "a=40 d=800 | 99 1",
    "a=88 d=0 | 99 22",
    "a=88 d=32 | 99 20",
    "a=88 d=66 | 99 17",
    "a=88 d=100 | 99 15",
    "a=88 d=160 | 99 12",
    "a=88 d=240 | 99 7",
    "a=88 d=400 | 99 1",
    "a=88 d=800 | 99 1",
    "a=160 d=0 | 99 31",
    "a=160 d=32 | 99 29",
    "a=160 d=66 | 99 26",
    "a=160 d=100 | 99 24",
    "a=160 d=160 | 99 21",
    "a=160 d=240 | 99 16",
    "a=160 d=400 | 99 6",
    "a=160 d=800 | 99 1",
    "a=280 d=0 | 99 46",
    "a=280 d=32 | 99 44",
    "a=280 d=66 | 99 41",
    "a=280 d=100 | 99 39",
    "a=280 d=160 | 99 36",
    "a=280 d=240 | 99 31",
    "a=280 d=400 | 99 21",
    "a=280 d=800 | 99 1",
    "a=400 d=0 | 99 61",
    "a=400 d=32 | 99 59",
    "a=400 d=66 | 99 56",
    "a=400 d=100 | 99 54",
    "a=400 d=160 | 99 51",
    "a=400 d=240 | 99 46",
    "a=400 d=400 | 99 36",
    "a=400 d=800 | 99 11",
    "a=800 d=0 | 99 111",
    "a=800 d=32 | 99 109",
    "a=800 d=66 | 99 106",
    "a=800 d=100 | 99 104",
    "a=800 d=160 | 99 101",
    "a=800 d=240 | 99 96",
    "a=800 d=400 | 99 86",
    "a=800 d=800 | 99 61",
    "w=0 | 99 15",
    "w=25 | 99 17",
    "w=1 | 99 17",
    "w=15 | 99 19",
    "w=128 | 99 15",
    "w=180 | 99 16",
    "w=207 | 99 18",
    "w=166 | 99 21",
    "w=105 | 99 22",
    "w=281 | 99 18",
    "w=217 | 99 17",
    "w=231 | 99 17",
    "w=258 | 99 20",
    "w=272 | 99 21",
    "w=119 | 99 22",
    "w=142 | 99 16",
    "w=154 | 99 22",
    "w=262 | 99 18",
    "w=252 | 99 22",
    "w=52 | 99 24",
    "w=82 | 99 25",
    "t=324 | 99 10",
    "t=301 | 99 16",
    "t=359 | 99 13",
    "t=289 | 95 17",
    "t=289 e=0 | 99 17",
    "t=289 e=5 | 95 17",
    "t=289 e=10 | 90 17",
    "t=289 e=20 | 80 17",
    "t=289 e=30 | 70 17",
    "t=289 e=50 | 50 17",
    "t=289 e=80 | 20 17",
    "t=289 e=100 | 1 17",
    "t=289 e=127 | 1 17",
    "f=0 | 99 25",
    "f=1 | 99 17",
    "f=2 | 99 34",
    "f=3 | 99 25",
    "w=0 a=0 | 99 4",
    "w=0 a=88 | 99 15",
    "w=0 a=200 | 99 29",
    "w=0 a=400 | 99 54",
    "w=0 b=10 | 99 11",
    "w=0 b=40 | 99 26",
    "t=289 e=30 f=0 | 70 25",
    "t=289 e=30 f=1 | 70 17",
    "t=289 e=30 f=2 | 70 34",
    "t=289 e=30 f=3 | 70 25",
    "a=400 f=0 | 99 84",
    "a=400 f=1 | 99 56",
    "a=400 f=2 | 99 112",
    "a=400 f=3 | 99 84",
    "a=120 f=0 | 99 31",
    "a=120 f=1 | 99 21",
    "a=120 f=2 | 99 42",
    "a=120 f=3 | 99 31",
    "w=30 | 99 27",
    "w=46 | 99 37",
    "w=106 | 99 33",
    "w=19 | 99 24",
    "w=32 | 99 27",
    "w=30 af=0 | 99 40",
    "w=30 af=1 | 99 27",
    "w=30 af=2 | 99 13",
    "w=30 af=3 | 99 0",
    "w=30 af=4 | 99 65509",
    "w=30 af=5 | 99 27",
    "w=30 af=6 | 99 27",
    "w=46 f=0 | 99 55",
    "w=46 f=1 | 99 37",
    "w=46 f=2 | 99 75",
    "w=46 f=3 | 99 55",
    "w=95 | 99 23",
    "s4=391 | 99 17",
    "s2=301 | 99 17",
    "d=60 | 99 18",
    "d=61 | 99 18",
    "d=62 | 99 18",
    "d=63 | 99 18",
    "d=64 | 99 18",
    "d=65 | 99 17",
    "d=66 | 99 17",
    "d=67 | 99 17",
    "d=400 f=1 | 99 1",
    "d=400 f=2 | 99 1",
    "d=400 f=0 | 99 1",
    "d=400 w=46 | 99 7",
    "d=400 w=30 af=2 | 99 3",
    "d=340 f=2 | 99 1",
    "d=336 f=2 | 99 2",
    "d=330 f=2 | 99 2",
    "d=330 w=30 af=2 | 99 5")

var failed = 0
var total = 0

def find_unit(units : array<Unit2>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
}

def apply_edit(var att, tgt : Unit2; var game_facing : int&; key : string; v : int) {
    if (key == "a") {
        att.raw[0] = v
    } elif (key == "d") {
        tgt.raw[1] = v
    } elif (key == "w") {
        att.equip[0] = read_item2(v)
    } elif (key == "s2") {
        att.equip[2] = read_item2(v)
    } elif (key == "s4") {
        att.equip[4] = read_item2(v)
    } elif (key == "t") {
        tgt.equip[0] = read_item2(v)
    } elif (key == "e") {
        tgt.equip[0].bonus[5] = v
    } elif (key == "f") {
        game_facing = v
    } elif (key == "b") {
        att.bare_power = v
    } elif (key == "af") {
        tgt.affinity[0] = v
    } elif (key == "sa") {
        att.status[v >> 3] = uint8(uint(att.status[v >> 3]) | (1u << uint(v & 7)))
    } elif (key == "st") {
        tgt.status[v >> 3] = uint8(uint(tgt.status[v >> 3]) | (1u << uint(v & 7)))
    } elif (key == "sup") {
        att.support = v
    } elif (key == "tsup") {
        tgt.support = v
    } elif (key == "tj") {
        set_job2(tgt, v)
    }
}

[export]
def main() : int {
    gba_load_rom(gui_arg("--rom", ""))
    gba_load_state(gui_arg("--state", ""))
    var units : array<Unit2>
    let err = read_battle2(units)
    if (err != "") {
        print("FAIL {err}\n")
        return 1
    }
    let luso = find_unit(units, "Luso")
    let sasarr = find_unit(units, "Sasarr")
    for (c in CASES) {
        let parts <- split(c, " | ")
        var att = units[luso]
        var tgt = units[sasarr]
        att.x = 9
        att.y = 8
        var game_facing = 1
        for (e in split(parts[0], " ")) {
            let kv <- split(e, "=")
            apply_edit(att, tgt, game_facing, kv[0], to_int(kv[1]))
        }
        tgt.facing = FACING_FROM_GAME[game_facing]
        recompute_unit(att)
        recompute_unit(tgt)
        let want <- split(parts[1], " ")
        let f <- fight2(att, tgt, side_of2(att, tgt))
        total++
        if (f.hit != to_int(want[0]) || (f.damage & 0xFFFF) != to_int(want[1])) {
            failed++
            print("FAIL {parts[0]}: game {want[0]} / {want[1]}, model {f.hit} / {f.damage} ({SIDE2_NAMES[int(f.side)]}, base {f.base})\n")
        }
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
