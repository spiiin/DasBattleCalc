options gen2
options indenting = 4
options stack = 1000000     // the dasPEG parser of the Explore language recurses

// FFT Explore (fft_explore.das): experiments on Ramza's Attack at Lezales
// in fft_test_ramza2 give the game's forecasts (research/fft/notes.md):
// the sides 66 / 74 / 100% (Lezales' facing edited), the zodiac 35 / 49
// / 21 (his zodiac edited), weapons Dagger 18 and Defender 48 (Ramza's
// right hand edited), Attack UP 56 (its bit), Protect 28. The sides are
// forced by turning the target; the weapon and the support follow
// recompute_unit, as the editor. Fire (MA 4) 17 at 95%.
//   battlecalc tests/test_fft_explore.das --state <fft_test_ramza2.State>
require gba_mem
require gui_common
require math
require daslib/strings_boost
require ../scripts/core/explore.das
require ../scripts/games/fft/fft_battle.das
require ../scripts/games/fft/fft_explore.das
require ./test_check.das


// the experiment's table; "" or the error
def run(sc : SceneF; m : FftMap; src : string; var t : ETable) : string {
    var s = Script()
    let err = parse_script(src, s)
    return err != "" ? err : run_experiment_f(sc, m, s, t)
}

// a column of the table as text, the rows joined by spaces
def column(t : ETable; name : string) : string {
    let c = find_index(t.names, name)
    if (c < 0) {
        return "(no {name})"
    }
    return join([for (r in t.rows); value_text(r[c])], " ")
}

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<FftUnit>
    check("battle read", read_battle(units) == "")
    var m : FftMap
    read_map(m)
    let ri = find_named(units, "Ramza")
    let li = find_named(units, "Lezales")
    if (ri < 0 || li < 0) {
        return 1
    }
    let sc = SceneF(att = units[ri], tgt = units[li])
    var t : ETable
    var err = run(sc, m, "vary side sides\n", t)
    check("sides: {err} {column(t, "damage")} / {column(t, "hit")}, the game: 42, 66 74 100",
        err == "" && column(t, "damage") == "42 42 42" && column(t, "hit") == "66 74 100")
    err = run(sc, m, "vary tgt.zodiac 0, 1, 3\n", t)
    check("zodiac Aries, Taurus, Cancer: {err} {column(t, "damage")}, the game: 35 49 21",
        err == "" && column(t, "damage") == "35 49 21")
    err = run(sc, m, "vary atk.weapon 1, 33\n", t)
    check("Dagger, Defender: {err} {column(t, "damage")} {column(t, "atk.weapon")}, the game: 18 48",
        err == "" && column(t, "damage") == "18 48")
    err = run(sc, m, "vary atk.support 0, 465\n", t)
    check("support none, Attack UP: {err} {column(t, "damage")}, the game: 42 56",
        err == "" && column(t, "damage") == "42 56")
    err = run(sc, m, "vary tgt.status.protect 0, 1\n", t)
    check("Protect: {err} {column(t, "damage")}, the game: 42 28", err == "" && column(t, "damage") == "42 28")
    err = run(sc, m, "vary action actions\nwhere damage > 0\n", t)
    check("Ramza's actions: {err} {column(t, "action")}", err == "" && starts_with(column(t, "action"), "Attack"))
    err = run(sc, m, "vary atk.pa 3..20\nvary atk.brave 40, 60, 80, 97\navg = expected\nplot avg by atk.pa per atk.brave\n", t)
    check("PA x Brave: {err} {length(t.rows)} rows", err == "" && length(t.rows) == 72)
    err = run(sc, m, "vary atk.weapon weapons\nwhere damage > 0\n", t)
    check("every weapon: {err} {length(t.rows)} rows", err == "" && length(t.rows) > 50)
    err = run(sc, m, "vary atk.nothing 1, 2\n", t)
    check("an unknown parameter: '{err}'", starts_with(err, "line 1: no parameter"))
    // a job (the raw stats x its multipliers): Ramza (Squire) as a Knight,
    // a Monk; the generic jobs first
    err = run(sc, m, "vary atk.job 76, 78
", t)
    let kpa = job_stat(units[ri], 76, 3)
    let mpa = job_stat(units[ri], 78, 3)
    check("Ramza as Knight / Monk: {err} PA {kpa} / {mpa}, {column(t, "damage")}",
        err == "" && column(t, "damage") == "{kpa * 7} {mpa * 7}" && kpa != mpa)
    err = run(sc, m, "vary atk.job jobs
", t)
    check("jobs: {err} {length(t.rows)}, first {length(t.rows) > 0 ? value_text(t.rows[0][0]) : ""}",
        err == "" && length(t.rows) > 60 && value_text(t.rows[0][0]) == "Squire")
    // the ready experiments run (the scene line is the UI's: here Attack)
    for (k in range(length(EXPLORE_F_EXAMPLES))) {
        err = run(sc, m, EXPLORE_F_EXAMPLES[k], t)
        check("example {FFT_EXPLORE_NAMES[k]}: '{err}', {length(t.rows)} rows", err == "" && length(t.rows) > 0)
    }
    // Fire (the scene's action) at Lezales: MA 4 x 14 x Faith 63 x his Faith
    let fire = SceneF(att = units[ri], tgt = units[li], ability = 16)
    err = run(fire, m, "vary atk.ma 4, 8
", t)
    check("Fire, MA 4 and 8: {err} {column(t, "damage")} {column(t, "hit")}, the game: 17 95% (MA 4)",
        err == "" && column(t, "damage") == "17 35" && column(t, "hit") == "95 95")
    return report()
}
