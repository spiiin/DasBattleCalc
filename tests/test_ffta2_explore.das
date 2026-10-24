options gen2
options indenting = 4
options stack = 1000000     // the dasPEG parser of the Explore language recurses

// Explore over the FFTA2 model (ffta2_explore.das): every point of an
// experiment must be the action the calculator computes for the same
// units after the same edit.
//   battlecalc tests/test_ffta2_explore.das --state <ffta2_test_attack.State> --rom <FFTA2 (USA)>.zip
require gui_common
require math
require strings
require gba_mem
require ../scripts/core/explore.das
require ../scripts/games/ffta2/ffta2_battle.das
require ../scripts/games/ffta2/ffta2_attack.das
require ../scripts/games/ffta2/ffta2_explore.das

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
    return 0
}

def run(sc : Scene2; src : string; var t : ETable) : string {
    var s = Script()
    var err = parse_script(src, s)
    if (err == "") {
        err = run_experiment2(sc, s, t)
    }
    return err
}

[export]
def main() : int {
    check("rom loads", gba_load_rom(gui_arg("--rom", "")) == "")
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<Unit2>
    let err0 = read_battle2(units)
    if (err0 != "") {
        print("{err0}\n")
        return 1
    }
    let luso = units[find_unit(units, "Luso")]
    let sasarr = units[find_unit(units, "Sasarr")]
    let sc = Scene2(att = luso, tgt = sasarr)
    // Attack by the attacker's Attack: every row = action2 after the edit
    var t : ETable
    var err = run(sc, "vary atk.attack 20..80 step 20\nx = damage * 2\n", t)
    check("attack axis: {err}", err == "" && length(t.rows) == 4)
    let di = column_index(t, "damage")
    let hi = column_index(t, "hit")
    let xi = column_index(t, "x")
    let attack = read_ability2(ATTACK_ABILITY)
    for (row in t.rows) {
        var a = luso
        a.raw[0] = int(row[0].num) * 4
        recompute_unit(a)
        let f = action2(a, sasarr, attack, side_of2(a, sasarr))
        check("attack {row[0].num}: damage {row[di].num} = {f.damage}, hit {row[hi].num} = {f.hit}",
            int(row[di].num) == f.damage && int(row[hi].num) == f.hit && row[xi].num == double(f.damage * 2))
    }
    if (length(t.rows) == 4) {
        check("damage grows with attack", t.rows[3][di].num > t.rows[0][di].num)
    }
    // two axes, a filter, an order
    err = run(sc, "vary atk.weapon weapons\nvary side sides\ne = expected\nwhere hit_real > 0\nsort e desc\n", t)
    check("weapons x sides: {err}, {length(t.rows)} rows", err == "" && length(t.rows) > 30)
    let ei = column_index(t, "e")
    for (i in range(1, length(t.rows))) {
        check("ordered", t.rows[i - 1][ei].num >= t.rows[i][ei].num)
    }
    // the side axis: back hits hardest
    err = run(sc, "vary side sides\n", t)
    check("sides: {err}", err == "" && length(t.rows) == 3)
    if (err == "") {
        let d = column_index(t, "damage")
        check("back >= side >= front", t.rows[2][d].num >= t.rows[1][d].num && t.rows[1][d].num >= t.rows[0][d].num)
    }
    // a status of the target; a parameter read but not varied is a column
    err = run(sc, "vary tgt.status.protect 0, 1\nleft = target.hp - damage\n", t)
    check("status axis + tgt.hp: {err}", err == "" && length(t.rows) == 2 && column_index(t, "tgt.hp") >= 0)
    if (err == "") {
        let d = column_index(t, "damage")
        check("protect lowers damage ({t.rows[0][d].num} -> {t.rows[1][d].num})", t.rows[1][d].num < t.rows[0][d].num)
    }
    // every action: Attack first, abilities by name, numbers where computed
    err = run(sc, "vary action actions\n", t)
    check("actions: {err}, {length(t.rows)} rows", err == "" && length(t.rows) > 100 && t.rows[0][0].text == "Attack")
    var numbers = 0
    for (row in t.rows) {
        if (!is_nan(row[di].num)) {
            numbers++
        }
    }
    check("actions computed: {numbers} of {length(t.rows)}", numbers * 10 >= length(t.rows) * 9)
    // jobs and supports
    err = run(sc, "vary atk.job jobs\n", t)
    check("jobs: {err}, {length(t.rows)} rows", err == "" && length(t.rows) > 50)
    err = run(sc, "vary atk.support supports\nvary privilege 0, 2\n", t)
    check("supports x privilege: {err}, {length(t.rows)} rows", err == "" && length(t.rows) == 64)
    // the ready examples of the Explore tab run and make a chart
    for (k in range(length(EXPLORE2_EXAMPLES))) {
        var s = Script()
        var e = parse_script(EXPLORE2_EXAMPLES[k], s)
        var esc = sc
        for (a in s.scene) {
            let v = eval_const(a.exprs[0], a.exprs[0].root)
            for (aid in explore_actions2()) {
                if (a.name == "action" && read_ability2(aid).name == v.text) {
                    esc.ability = aid
                }
            }
        }
        if (e == "") {
            e = run_experiment2(esc, s, t)
        }
        var ch = Chart()
        if (e == "") {
            e = build_chart(s, t, t.names[0], "damage", ch)
        }
        check("example '{EXPLORE2_NAMES[k]}': {e}, {length(t.rows)} rows", e == "" && length(t.rows) > 1 &&
            length(ch.series) > 0)
    }
    // errors name the line and the problem
    for (c in [("vary atk.attak 1..5\n", "line 1: no parameter 'atk.attak'"),
            ("vary atk.attack 1..100000\nvary tgt.defense 1..100\n", "too many points"),
            ("vary atk.attack foo\n", "values are from..to"), ("vary hp 1\n", "vary atk."),
            ("vary tgt.status.nonsense 0, 1\n", "no parameter")]) {
        let e = run(sc, c._0, t)
        check("{c._0}-> {e}", find(e, c._1) >= 0)
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
