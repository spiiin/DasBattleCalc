options gen2
options indenting = 4

// Support abilities and Soldier's Battle Tech (act in ffta_attack.das)
// against the game's own preview in the first test save:
// research/attack_probe.lua with record +0x3B patched (support), and
// research/ability_probe.lua with the techs learned (+0x40 + index),
// Euver moved next to Marc to (7, 5) for the enemy-only techs.
//   battlecalc tests/test_ffta_abilities.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
require gui_common
require strings
require gba_mem
require ../scripts/games/ffta/ffta_battle.das
require ./test_common.das
require ../scripts/games/ffta/ffta_attack.das
require ./test_check.das

def find(units : array<BattleUnit>; name : string) : BattleUnit {
    for (u in units) {
        if (u.name == name) {
            return u
        }
    }
    return units[0]
}

[export]
def main() : int {
    var units : array<BattleUnit>
    var battle : BattleMap
    var err = load_test_battle(units, battle)
    if (err != "") {
        print("{err}\n")
        return 1
    }
    let marc = find(units, "Marc")
    let mont = find(units, "Montblanc")
    var euver = find(units, "Euver")
    euver.x = 7
    euver.y = 5
    let check = $(name : string; att, tgt : BattleUnit; ability, value, hit : int) {
        let r = act(battle, att, tgt, ability, SideChoice.Auto)
        let ok = r.damage == value && r.hit == hit
        print("{name}: model {r.damage} / {r.hit}%  game {value} / {hit}%  {ok ? "ok" : "FAIL"}\n")
        total++
        if (!ok) {
            failed++
        }
    }
    // support abilities (record +0x3B), Marc -> Montblanc, Fight
    for (s in [("Concentrate", 13, 20, 95), ("Turbo MP", 4, 20, 80), ("Weapon Atk+", 1, 25, 65),
            ("Doublehand", 7, 25, 65)]) {
        var a = marc
        a.support = s._1
        check("attacker {s._0}", a, mont, 0, s._2, s._3)
    }
    var t = mont
    t.support = 2
    check("target Weapon Def+", marc, t, 0, 15, 65)
    // Battle Tech: Powerbreak 77, Magicbreak 79 (MP), Speedbreak 80,
    // Mug 81, Provoke 82, First Aid 76 (heals the user)
    check("Powerbreak", marc, mont, 77, 0, 65)
    check("Magicbreak", marc, mont, 79, 20, 65)
    check("Speedbreak -> Euver", marc, euver, 80, 0, 50)
    check("Mug -> Euver", marc, euver, 81, 20, 50)
    check("Provoke -> Euver", marc, euver, 82, 0, 50)
    check("First Aid", marc, mont, 76, 7, 100)
    var strong = marc
    strong.stat_base[int(Stat.MPow)] = 200
    check("First Aid, M.Pow 200", strong, mont, 76, 38, 100)
    return report()
}
