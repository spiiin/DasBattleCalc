options gen2
options indenting = 4

// The second battle (research/notes.md, "Second battle"): the model
// against the game on saves it did not come from.
// 1. Turn order: from the start of the battle (every CT 0) the tick model
//    must reach Loki's turn with the CT of every unit the game has then.
// 2. Stats: the Status screen of all 12 units (status_copy.lua).
// 3. Attacks: 66 forecasts of the game (attack_probe.lua): one record
//    copied over Loki's (with Loki's flags), the target's record put into
//    Marc's place (and turned: /f), Fight to the right.
//   battlecalc tests/test_ffta_battle2.das --state <ffta_test_battle2.State>
//       --start <ffta_test_battle2_start.State> --rom <FFTA (USA).zip>
require gui_common
require gba_mem
require ../scripts/games/ffta/ffta_battle.das
require ../scripts/games/ffta/ffta_attack.das
require ./test_common.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

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
    // 1. ticks from the start
    var start : array<BattleUnit>
    var err = gba_load_rom(gui_arg("--rom", ""))
    if (err == "") {
        err = gba_load_state(gui_arg("--start", ""))
    }
    if (err == "") {
        err = read_battle(start)
    }
    var units : array<BattleUnit>
    var m : BattleMap
    if (err == "") {
        err = load_test_battle(units, m)
    }
    if (err != "") {
        print("{err}\n")
        return 1
    }
    var sim := start
    var ticks = 0
    let first = next_actor(sim, ticks)
    check("first actor {sim[first].name} after {ticks} ticks", sim[first].name == "Loki" && ticks == 9)
    for (u in sim) {
        let k = find(units, u.name)
        check("{u.name}: CT {u.ct}, game {k >= 0 ? units[k].ct : -1}", k >= 0 && units[k].ct == u.ct)
    }
    // 2. the Status screens: W.Atk W.Def M.Pow M.Res Speed Evade Move Jump
    let want = [("Marc", [138, 140, 75, 94, 106, 54, 4, 2]), ("Montblanc", [93, 120, 117, 153, 104, 35, 3, 2]),
        ("Hardy", [137, 137, 73, 94, 109, 54, 4, 2]), ("Loki", [126, 112, 102, 88, 118, 61, 4, 3]),
        ("Nusratt", [81, 98, 101, 124, 112, 40, 3, 2]), ("Cristine", [115, 96, 83, 88, 116, 50, 4, 2]),
        ("Sinagelus", [119, 117, 92, 93, 111, 55, 3, 2]), ("Batazes", [103, 101, 71, 68, 110, 50, 3, 2]),
        ("Romuel", [100, 104, 71, 66, 104, 50, 3, 2]), ("Herbatius", [107, 106, 73, 67, 107, 50, 3, 2]),
        ("Hjalavar", [107, 85, 116, 130, 115, 60, 4, 3]), ("Judge", [0, 0, 0, 0, 50, 0, 8, 4])]
    for (w in want) {
        let k = find(units, w._0)
        var ok = k >= 0
        for (s in range(8)) {
            ok = ok && units[k].stat_total[s] == w._1[s]
        }
        check("{w._0} stats, game {w._1}", ok)
    }
    // 3. the forecasts: attacker, target, its facing (-1: Marc's), damage, hit
    let loki = units[find(units, "Loki")]
    let marc = units[find(units, "Marc")]
    let cases = [
        ("Loki", "Marc", -1, 16, 87), ("Loki", "Batazes", -1, 22, 88), ("Loki", "Sinagelus", -1, 19, 87),
        ("Loki", "Hjalavar", -1, 24, 85), ("Loki", "Cristine", -1, 22, 88), ("Loki", "Nusratt", -1, 22, 90),
        ("Hardy", "Marc", -1, 16, 87), ("Hardy", "Batazes", -1, 21, 88), ("Hardy", "Sinagelus", -1, 19, 87),
        ("Hardy", "Hjalavar", -1, 23, 85), ("Hardy", "Cristine", -1, 22, 88), ("Hardy", "Nusratt", -1, 22, 90),
        ("Cristine", "Marc", -1, 8, 87), ("Cristine", "Batazes", -1, 12, 88), ("Cristine", "Sinagelus", -1, 10, 87),
        ("Cristine", "Hjalavar", -1, 13, 85), ("Cristine", "Cristine", -1, 12, 88), ("Cristine", "Nusratt", -1, 12, 90),
        ("Sinagelus", "Marc", -1, 21, 87), ("Sinagelus", "Batazes", -1, 27, 88), ("Sinagelus", "Sinagelus", -1, 24, 87),
        ("Sinagelus", "Hjalavar", -1, 29, 85), ("Sinagelus", "Cristine", -1, 27, 88), ("Sinagelus", "Nusratt", -1, 27, 90),
        ("Hjalavar", "Marc", -1, 5, 87), ("Hjalavar", "Batazes", -1, 8, 88), ("Hjalavar", "Sinagelus", -1, 7, 87),
        ("Hjalavar", "Hjalavar", -1, 9, 85), ("Hjalavar", "Cristine", -1, 8, 88), ("Hjalavar", "Nusratt", -1, 8, 90),
        ("Batazes", "Marc", -1, 11, 87), ("Batazes", "Batazes", -1, 15, 88), ("Batazes", "Sinagelus", -1, 13, 87),
        ("Batazes", "Hjalavar", -1, 17, 85), ("Batazes", "Cristine", -1, 15, 88), ("Batazes", "Nusratt", -1, 15, 90),
        ("Nusratt", "Marc", -1, 2, 87), ("Nusratt", "Batazes", -1, 5, 88), ("Nusratt", "Sinagelus", -1, 4, 87),
        ("Nusratt", "Hjalavar", -1, 7, 85), ("Nusratt", "Cristine", -1, 6, 88), ("Nusratt", "Nusratt", -1, 6, 90),
        ("Montblanc", "Marc", -1, 4, 87), ("Montblanc", "Batazes", -1, 7, 88), ("Montblanc", "Sinagelus", -1, 6, 87),
        ("Montblanc", "Hjalavar", -1, 9, 85), ("Montblanc", "Cristine", -1, 8, 88), ("Montblanc", "Nusratt", -1, 7, 90),
        ("Loki", "Batazes", 1, 22, 50), ("Loki", "Batazes", 0, 22, 75), ("Loki", "Batazes", 2, 22, 75),
        ("Loki", "Hjalavar", 1, 24, 40), ("Loki", "Hjalavar", 0, 24, 70), ("Loki", "Hjalavar", 2, 24, 70),
        ("Cristine", "Batazes", 1, 12, 50), ("Cristine", "Batazes", 0, 12, 75), ("Cristine", "Batazes", 2, 12, 75),
        ("Cristine", "Hjalavar", 1, 13, 40), ("Cristine", "Hjalavar", 0, 13, 70), ("Cristine", "Hjalavar", 2, 13, 70),
        ("Sinagelus", "Batazes", 1, 27, 50), ("Sinagelus", "Batazes", 0, 27, 75), ("Sinagelus", "Batazes", 2, 27, 75),
        ("Sinagelus", "Hjalavar", 1, 29, 40), ("Sinagelus", "Hjalavar", 0, 29, 70), ("Sinagelus", "Hjalavar", 2, 29, 70)]
    for (c in cases) {
        var att = units[find(units, c._0)]
        att.x = loki.x
        att.y = loki.y
        att.facing = loki.facing
        att.flags = loki.flags
        var tgt = units[find(units, c._1)]
        tgt.x = marc.x
        tgt.y = marc.y
        tgt.facing = c._2 >= 0 ? c._2 : marc.facing
        let r = fight(m, att, tgt, SideChoice.Auto)
        check("{c._0} -> {c._1} ({r.side}): {r.damage} / {r.hit}%, game {c._3} / {c._4}%", r.damage == c._3 && r.hit == c._4)
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
