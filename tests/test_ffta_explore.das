options gen2
options indenting = 4
options stack = 1000000     // the dasPEG parser of the Explore language recurses

// Explore over the FFTA model (ffta_explore.das): every point of an
// experiment must be the attack the calculator computes for the same
// units (fight / act after the same edit).
//   battlecalc tests/test_ffta_explore.das --state <QuickSave1.State> --rom <FFTA (USA).zip>
require gui_common
require math
require strings
require gba_mem
require ../scripts/core/explore.das
require ../scripts/games/ffta/ffta_battle.das
require ../scripts/games/ffta/ffta_attack.das
require ../scripts/games/ffta/ffta_explore.das
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
    return 0
}

def run(m : BattleMap; sc : Scene; src : string; var t : ETable) : string {
    var s = Script()
    var err = parse_script(src, s)
    if (err == "") {
        err = run_experiment(m, sc, s, t)
    }
    return err
}

[export]
def main() : int {
    var units : array<BattleUnit>
    var battle : BattleMap
    let err0 = load_test_battle(units, battle)
    if (err0 != "") {
        print("{err0}\n")
        return 1
    }
    let marc = units[find(units, "Marc")]
    let mont = units[find(units, "Montblanc")]
    let sc = Scene(att = marc, tgt = mont, ability = 0, side = 0)
    // W.Atk axis: every row = fight() with that base W.Atk
    var t : ETable
    var err = run(battle, sc, "vary atk.watk 50..300 step 50\nx = damage * 2\n", t)
    check("watk axis: {err}", err == "" && length(t.rows) == 6)
    let di = column_index(t, "damage")
    let xi = column_index(t, "x")
    for (row in t.rows) {
        var a = marc
        a.stat_base[int(Stat.WAtk)] = int(row[0].num)
        recompute_unit(a)
        let r = fight(battle, a, mont, SideChoice.Auto)
        check("watk {row[0].num}: damage {row[di].num} = fight {r.damage}", int(row[di].num) == r.damage
            && row[xi].num == double(r.damage * 2))
    }
    // two axes, a filter, an order; jobs of a human
    err = run(battle, sc, "vary atk.job jobs\nvary side sides\ne = expected\nwhere hit_real > 0\nsort e desc\n", t)
    let jobs = length(race_jobs(marc.race))
    check("jobs x sides: {err}, {length(t.rows)} rows of {jobs * 3}", err == "" && length(t.rows) > 0
        && length(t.rows) <= jobs * 3)
    let ei = column_index(t, "e")
    for (i in range(1, length(t.rows))) {
        check("ordered", t.rows[i - 1][ei].num >= t.rows[i][ei].num)
    }
    for (row in t.rows) {
        var a = marc
        set_job(a, int(row[0].num))
        recompute_unit(a)
        let side = int(row[1].num)
        let choice = side == 1 ? SideChoice.Front : (side == 2 ? SideChoice.Side : SideChoice.Back)
        let r = fight(battle, a, mont, choice)
        check("{row[0].text} {row[1].text}: {row[ei].num} = {r.expected}", abs(row[ei].num - double(r.expected)) < 1e-6lf)
    }
    // a parameter read by a formula but not an axis becomes a column
    // (target.hp: the long name means tgt.hp)
    err = run(battle, sc, "vary tgt.status.protect 0, 1\nleft = target.hp - damage\n", t)
    check("status axis + tgt.hp: {err}", err == "" && length(t.rows) == 2 && column_index(t, "tgt.hp") >= 0)
    if (err == "") {
        check("protect lowers damage", t.rows[1][column_index(t, "damage")].num < t.rows[0][column_index(t, "damage")].num)
    }
    // from..to includes both ends, also downwards
    err = run(battle, sc, "vary atk.watk 300..100 step 100\n", t)
    check("300..100 step 100: {err}", err == "" && length(t.rows) == 3 && t.rows[0][0].num == 300.0lf
        && t.rows[2][0].num == 100.0lf)
    // errors name the line and the problem
    for (c in [("vary atk.wat 1..5\n", "line 1: no parameter 'atk.wat'"),
            ("vary atk.watk 1..100000\nvary atk.wdef 1..100\n", "too many points"),
            ("vary atk.watk foo\n", "values are from..to"), ("vary hp 1\n", "vary atk.")]) {
        let e = run(battle, sc, c._0, t)
        check("{c._0}-> {e}", find(e, c._1) >= 0)
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
