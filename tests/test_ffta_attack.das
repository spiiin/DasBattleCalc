options gen2
options indenting = 4

// The Fight model (ffta_attack.das) against the game's own preview of
// Marc -> Montblanc in the first test save, under the same changes that
// research/attack_probe.lua wrote to RAM (statuses, stats, facing, other
// attackers) - see research/attack.py.
//   battlecalc tests/test_ffta_attack.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
require gui_common
require strings
require gba_mem
require ../scripts/games/ffta/ffta_battle.das
require ./test_common.das
require ../scripts/games/ffta/ffta_attack.das

def find(units : array<BattleUnit>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
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
    let marc = units[find(units, "Marc")]
    let mont = units[find(units, "Montblanc")]
    var failed = 0
    var total = 0
    // one case: attacker and target after the change, damage / hit of the game
    let check = $(name : string; att, tgt : BattleUnit; dmg, hit : int) {
        let r = fight(battle, att, tgt, SideChoice.Auto)
        let ok = r.damage == dmg && r.hit == hit
        print("{name}: model {r.damage} / {r.hit}%  game {dmg} / {hit}%  {ok ? "ok" : "FAIL"}\n")
        total++
        if (!ok) {
            failed++
        }
    }
    check("base", marc, mont, 20, 65)
    for (f in fixed_array(1, 0, 2)) {
        var t = mont
        t.facing = f
        check("target facing {f}", marc, t, 20, f == 1 ? 92 : 83)
    }
    var a = marc
    a.stat_base[int(Stat.WAtk)] = 200
    check("attacker W.Atk 200", a, mont, 41, 65)
    var t = mont
    t.stat_base[int(Stat.WDef)] = 50
    check("target W.Def 50", marc, t, 26, 65)
    // status byte (+0xE8 + i) of the attacker or the target
    let statuses = [("target +E9=04", false, 1, 0x04u, 20, 85), ("attacker +E9=04", true, 1, 0x04u, 20, 15),
        ("target +EB=02", false, 3, 0x02u, 15, 65), ("attacker +E9=40", true, 1, 0x40u, 34, 65),
        ("target +E9=01", false, 1, 0x01u, 33, 65), ("attacker +E8=80", true, 0, 0x80u, 25, 65),
        ("target +EB=10", false, 3, 0x10u, 20, 75)]
    for (s in statuses) {
        var sa = marc
        var st = mont
        if (s._1) {
            sa.status[s._2] = s._3
        } else {
            st.status[s._2] = s._3
        }
        check(s._0, sa, st, s._4, s._5)
    }
    // other attackers on Marc's tile (the whole record copied in the game)
    for (o in [("Euver", 15), ("Lunais", 10), ("Judge", 1), ("Montblanc", 6)]) {
        var oa = units[find(units, o._0)]
        oa.x = marc.x
        oa.y = marc.y
        check("attacker {o._0}", oa, mont, o._1, 65)
    }
    // Flametongue (Fire, item 18) against the target's Fire affinity
    // (record +0x0D): normal, weak, immune, absorb, half
    for (e in [(1, 35), (0, 52), (2, 0), (3, -35), (4, 17)]) {
        var fa = marc
        fa.equip[0] = read_item(18u)
        var ft = mont
        ft.affinity[1] = e._0
        check("Flametongue, affinity {e._0}", fa, ft, e._1, 65)
    }
    let r = fight(battle, marc, mont, SideChoice.Auto)
    print("Marc -> Montblanc: roll {r.hit_roll}% (game rolled 75), crit {r.crit}% (game 5), damage {r.dmg_min}..{r.dmg_max}\n")
    if (r.hit_roll != 75 || r.crit != 5) {
        failed++
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed}\n")
    return failed == 0 ? 0 : 1
}
