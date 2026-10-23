options gen2
options indenting = 4

// Reactions (reaction in ffta_attack.das) against real uses in the first
// test save (research/live_probe.lua): Montblanc made a human Soldier
// (+0x05 / +0x06 / +0x07) with a reaction at +0x3A, Marc attacks him
// with Fight. In the game: Reflex - Marc's roll was 0 % (25 of 25 missed);
// Strikeback - Marc always missed, Montblanc struck back for 4; Counter -
// struck back for 4 with the roll 56 % (82 of 144 hit); Bonecrusher - 6.
//   battlecalc tests/test_ffta_reactions.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
require gui_common
require strings
require gba_mem
require ../scripts/games/ffta/ffta_battle.das
require ./test_common.das
require ../scripts/games/ffta/ffta_attack.das

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
    var failed = 0
    // reaction id, dodges, strikes back, damage back, roll of the strike back
    for (c in [("Reflex", 5, true, false, 0, 0), ("Strikeback", 7, true, true, 4, 56),
            ("Counter", 8, false, true, 4, 56), ("Bonecrusher", 10, false, true, 6, 56)]) {
        var t = mont
        t.reaction = c._1
        t.reaction_name = c._0
        let r = fight(battle, marc, t, SideChoice.Auto)
        let rr = reaction(battle, marc, t, 0, r)
        var ok = rr.triggers && rr.dodge == c._2 && rr.counter == c._3
        if (c._3) {
            ok = ok && rr.back.damage == c._4 && rr.back.hit_roll == c._5
        }
        print("{c._0}: dodge {rr.dodge}, back {rr.counter} {rr.back.damage} / {rr.back.hit_roll}%  {ok ? "ok" : "FAIL"}\n")
        if (!ok) {
            failed++
        }
    }
    // no reaction against a spell for Counter (not physical)
    var t = mont
    t.reaction = 8
    var mage = mont
    mage.x = marc.x
    mage.y = marc.y
    let fire = act(battle, mage, t, 23, SideChoice.Auto)
    if (reaction(battle, mage, t, 23, fire).triggers) {
        print("Counter against Fire: triggers  FAIL\n")
        failed++
    }
    print(failed == 0 ? "PASS 5 cases\n" : "FAIL {failed}\n")
    return failed == 0 ? 0 : 1
}
