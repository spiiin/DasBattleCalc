options gen2
options indenting = 4
options stack = 1000000     // the dasPEG parser of the Explore language recurses

// Explore over the WotL model (fftwotl_explore.das): every point of an
// experiment must be the action the calculator computes for the same
// units after the same edit; the ready examples run; turn order.
//   battlecalc tests/test_fftwotl_explore.das --state <fftwotl_test_battle1.ppst>
require gui_common
require math
require strings
require gba_mem
require ../scripts/core/explore.das
require ../scripts/games/fftwotl/fftwotl_data.das
require ../scripts/games/fftwotl/fftwotl_battle.das
require ../scripts/games/fftwotl/fftwotl_attack.das
require ../scripts/games/fftwotl/fftwotl_turns.das
require ../scripts/games/fftwotl/fftwotl_explore.das
require ./test_check.das


def run(sc : SceneW; src : string; var t : ETable) : string {
    var s = Script()
    var err = parse_script(src, s)
    if (err == "") {
        err = run_experiment_w(sc, s, t)
    }
    return err
}

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<UnitW>
    let err0 = read_battle_w(units)
    if (err0 != "") {
        print("{err0}\n")
        return 1
    }
    let ramza = units[find_named(units, "AAAAA")]
    let lez = units[find_named(units, "Lezalas")]
    let sc = SceneW(att = ramza, tgt = lez)
    // Attack by the attacker's PA: every row = action_w after the edit
    var t : ETable
    var err = run(sc, "vary atk.pa 4..10 step 2\nx = damage * 2\n", t)
    check("pa axis: {err}", err == "" && length(t.rows) == 4)
    let di = column_index(t, "damage")
    let hi = column_index(t, "hit")
    let xi = column_index(t, "x")
    for (row in t.rows) {
        var a = ramza
        set_unit_param_w(a, "pa", row[0])
        let f = action_w(a, lez, ATTACK_W, side_of_w(a, lez))
        check("pa {row[0].num}: damage {row[di].num} = {f.damage}, hit {row[hi].num} = {f.hit}",
            int(row[di].num) == f.damage && int(row[hi].num) == f.hit && row[xi].num == double(f.damage * 2))
    }
    if (length(t.rows) == 4) {
        check("damage grows with PA", t.rows[3][di].num > t.rows[0][di].num)
    }
    err = run(sc, "vary side sides\n", t)
    check("sides: {err}", err == "" && length(t.rows) == 3)
    if (err == "") {
        check("back hits more often than front", t.rows[2][hi].num >= t.rows[0][hi].num)
    }
    err = run(sc, "vary tgt.status.protect 0, 1\nleft = target.hp - damage\n", t)
    check("status axis + tgt.hp: {err}", err == "" && length(t.rows) == 2 && column_index(t, "tgt.hp") >= 0)
    if (err == "") {
        let d = column_index(t, "damage")
        check("Protect lowers damage ({t.rows[0][d].num} -> {t.rows[1][d].num})", t.rows[1][d].num < t.rows[0][d].num)
    }
    err = run(sc, "vary atk.weapon weapons\ne = expected\nwhere damage > 0\nsort e desc\n", t)
    check("weapons: {err}, {length(t.rows)} rows", err == "" && length(t.rows) > 50)
    err = run(sc, "vary atk.job jobs\nvary atk.support supports\n", t)
    check("jobs x supports: {err}, {length(t.rows)} rows", err == "" && length(t.rows) > 1000)
    for (k in range(length(EXPLORE_W_EXAMPLES))) {
        var s = Script()
        var e = parse_script(EXPLORE_W_EXAMPLES[k], s)
        var esc := sc
        for (a in s.scene) {
            let v = eval_const(a.exprs[0], a.exprs[0].root)
            if (a.name == "action") {
                esc.ability = ability_id_named(v.text)
            }
        }
        if (e == "") {
            e = run_experiment_w(esc, s, t)
        }
        var ch = Chart()
        if (e == "") {
            e = build_chart(s, t, t.names[0], "damage", ch)
        }
        check("example '{FFT_EXPLORE_NAMES[k]}': {e}, {length(t.rows)} rows", e == "" && length(t.rows) > 1 &&
            length(ch.series) > 0)
    }
    for (c in [("vary atk.pq 1..5\n", "line 1: no parameter 'atk.pq'"), ("vary atk.pa foo\n", "values are from..to"),
            ("vary hp 1\n", "vary atk."), ("vary tgt.status.nonsense 0, 1\n", "no parameter")]) {
        let e = run(sc, c._0, t)
        check("{c._0}-> {e}", find(e, c._1) >= 0)
    }
    // turn order: Ramza's turn now; the units at CT 104 next, by record
    let turns <- predict_turns_w(units, 12)
    check("12 turns", length(turns) == 12)
    if (length(turns) > 2) {
        check("Ramza first", units[turns[0].unit].name == "AAAAA" && turns[0].tick == 0)
        check("then Agrias (104, tick 0)", units[turns[1].unit].name == "Agrias" && turns[1].tick == 0)
    }
    if (gui_arg("--print", "") != "") {
        for (tr in turns) {
            print("tick {tr.tick}: {units[tr.unit].name} (CT {tr.ct})\n")
        }
    }
    return report()
}
