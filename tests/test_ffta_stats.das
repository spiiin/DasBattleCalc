options gen2
options indenting = 4

// Stats and equipment of every unit of the first test save against the
// Status screens of the game (BizHawk, research/status_copy.lua: each
// record copied over Marc's, then Status opened).
//   battlecalc tests/test_ffta_stats.das --state <QuickSave1.State> --rom <FFTA (USA).zip>
require gui_common
require strings
require daslib/strings_boost
require gba_mem
require ../scripts/games/ffta/ffta_battle.das
require ./test_common.das

struct Expected {
    name : string
    job : string
    stats : int[8]                  // by Stat: W.Atk W.Def M.Pow M.Res Speed Evade Move Jump
    equip : string
}

[export]
def main() : int {
    var units : array<BattleUnit>
    var err = load_test_units(units)
    if (err != "") {
        print("{err}\n")
        return 1
    }
    var expected <- [
        Expected(name = "Marc", job = "Soldier", stats = fixed_array(138, 140, 75, 94, 106, 54, 4, 2),
            equip = "Shortsword, Cuirass, Bronze Shield"),
        Expected(name = "Lunais", job = "White Monk", stats = fixed_array(89, 95, 93, 78, 107, 60, 4, 3),
            equip = "Leather Garb"),
        Expected(name = "Euver", job = "Warrior", stats = fixed_array(121, 111, 68, 75, 101, 50, 4, 2),
            equip = "Shortsword, Leather Garb"),
        Expected(name = "Montblanc", job = "Black Mage", stats = fixed_array(96, 116, 111, 155, 99, 35, 3, 2),
            equip = "Rod, Hempen Robe"),
        Expected(name = "Judge", job = "Judge", stats = fixed_array(0, 0, 0, 0, 50, 0, 8, 4), equip = "")
    ]
    var failed = 0
    for (e in expected) {
        var found = false
        for (u in units) {
            if (u.name != e.name) {
                continue
            }
            found = true
            let names <- [for (it in u.equip); it.name; where it.id != 0]
            let equip = join(names, ", ")
            var ok = u.job == e.job && equip == e.equip
            for (i in range(STAT_COUNT)) {
                ok = ok && u.stat_total[i] == e.stats[i]
            }
            let verdict = ok ? "ok" : "FAIL, expected {e.job} {e.stats} [{e.equip}]"
            print("{u.name} ({u.job}): {u.stat_total} [{equip}] {verdict}\n")
            if (!ok) {
                failed++
            }
        }
        if (!found) {
            print("{e.name}: not in the battle\n")
            failed++
        }
    }
    print(failed == 0 ? "PASS {length(expected)} units\n" : "FAIL {failed}\n")
    return failed == 0 ? 0 : 1
}
