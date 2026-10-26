options gen2
options indenting = 4

// Export of edited units (export_battle): edit Marc and Montblanc,
// write a new state, load it back and compare what the reader sees.
//   battlecalc tests/test_ffta_export.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip> --out <new.State>
require daslib/with_boost
require gui_common
require strings
require gba_mem
require ../scripts/games/ffta/ffta_battle.das
require ./test_common.das
require ../scripts/core/result_try.das

def find(units : array<BattleUnit>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return 0
}

// write the edited units to out, then load that file and read it back
def export_and_reload(battle : BattleMap; units, orig : array<BattleUnit>; out : string; var notes : string&;
                      var back : array<BattleUnit>) : string {
    try_ok(export_battle(battle, units, orig, out, notes), "export: ")
    try_ok(gba_load_state(out), "reload: ")
    try_ok(read_battle(back), "reload battle: ")
    return ""
}

[export]
def main() : int {
    let out = gui_arg("--out", "")
    var orig : array<BattleUnit>
    var battle : BattleMap
    var err = load_test_battle(orig, battle)
    if (err != "") {
        print("{err}\n")
        return 1
    }
    var units := orig
    let mi = find(units, "Marc")
    let ni = find(units, "Montblanc")
    units[mi].hp = 7
    units[mi].mp = 3
    units[mi].stat_base[int(Stat.WAtk)] = 150
    units[mi].stat_base[int(Stat.Speed)] = 120
    units[mi].ct = 42
    units[mi].equip[1] = read_item(2u)
    units[mi].status[2] |= 0x20u
    set_ability(units[mi], 3, 13)   // Concentrate (human support)
    set_ability(units[ni], 2, 8)    // Counter (moogle reaction)
    units[mi].learned[6] = true     // Mug (human list entry 6)
    units[mi].learned[58] = true    // Cure (White Mage)
    units[mi].learned[11] = false   // Combat Combo
    units[ni].facing = (units[ni].facing + 1) & 3
    // a free tile next to Montblanc
    for (d in range(4)) {
        let x = units[ni].x + DIR_X[d]
        let y = units[ni].y + DIR_Y[d]
        var free = tile_height(battle, x, y) > 0
        for (u in units) {
            free = free && !(u.x == x && u.y == y)
        }
        if (free) {
            units[ni].x = x
            units[ni].y = y
            break
        }
    }
    for (i in range(length(units))) {
        recompute_unit(units[i])
    }
    units[ni].stat_base[int(Stat.Move)] += 1    // from the job: only a note
    var notes = ""
    var back : array<BattleUnit>
    err = export_and_reload(battle, units, orig, out, notes, back)
    if (err != "") {
        print("{err}\n")
        return 1
    }
    print("notes: {notes}\n")
    var failed = 0
    // the notes reach the caller (they were lost when passed by value)
    if (find(notes, "Montblanc: Move comes from the job") < 0) {
        print("notes: FAIL, no note on Montblanc's Move\n")
        failed++
    }
    for (i in range(length(units))) {
        with_(units[i], back[i]) $(a, b) {
            var same = (a.hp == b.hp && a.mp == b.mp && a.max_hp == b.max_hp && a.ct == b.ct && a.reserve == b.reserve
                && a.x == b.x && a.y == b.y && a.facing == b.facing && a.support == b.support && a.reaction == b.reaction
                && a.job_id == b.job_id && a.speed == b.speed && a.action_count == b.action_count)
            for (s in range(144)) {
                same = same && a.learned[s] == b.learned[s]
            }
            for (s in range(5)) {
                same = same && a.stat_base[s] == b.stat_base[s] && a.items[s] == b.items[s]
            }
            for (s in range(6)) {
                same = same && a.status[s] == b.status[s]
            }
            print("{a.name}: {same ? "ok" : "FAIL"}  hp {b.hp} ct {b.ct} pos {b.position} sup {b.support_name} rea {b.reaction_name}\n")
            if (!same) {
                failed++
            }
        }
    }
    print(failed == 0 ? "PASS {length(units)} units\n" : "FAIL {failed}\n")
    return failed == 0 ? 0 : 1
}
