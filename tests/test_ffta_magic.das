options gen2
options indenting = 4

// Other jobs' abilities read from their effect lists (act in
// ffta_attack.das) against the game in the first test save
// (research/ability_probe.lua): Marc with Montblanc's record copied in
// casts Black Magic (Fire, Thunder) on Montblanc and on Euver moved to
// (7, 5); Marc as a White Mage (job 7, Cure / Life / Protect learned)
// casts Cure on Montblanc and on himself, and Protect.
//   battlecalc tests/test_ffta_magic.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
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
    // Montblanc's record in Marc's place (the record copy in the game)
    var mage = mont
    mage.x = marc.x
    mage.y = marc.y
    mage.facing = marc.facing
    let check = $(name : string; att, tgt : BattleUnit; ability, value, hit : int; kind : TechKind) {
        let r = act(battle, att, tgt, ability, SideChoice.Auto)
        let ok = r.damage == value && r.hit == hit && r.tech == kind
        print("{name}: model {r.damage} / {r.hit}% ({r.tech}, {r.effect})  game {value} / {hit}%  {ok ? "ok" : "FAIL"}\n")
        total++
        if (!ok) {
            failed++
        }
    }
    check("Fire -> Montblanc", mage, mont, 23, 10, 65, TechKind.Damage)
    check("Thunder -> Montblanc", mage, mont, 26, 10, 65, TechKind.Damage)
    check("Fire -> Euver", mage, euver, 23, 22, 50, TechKind.Damage)
    check("Cure -> Montblanc", marc, mont, 1, 3, 100, TechKind.Heal)
    check("Cure -> Marc", marc, marc, 1, 12, 100, TechKind.Heal)
    check("Protect -> Montblanc", marc, mont, 9, 0, 100, TechKind.Status)
    let fire = act(battle, mage, mont, 23, SideChoice.Auto)
    let area_ok = fire.area == 1 && fire.element == 1 && fire.mp_cost == 6
    print("Fire: area {fire.area} (game hit 3 units around the target), element {fire.element}, MP {fire.mp_cost} {area_ok ? "ok" : "FAIL"}\n")
    if (!area_ok) {
        failed++
    }
    return report()
}
