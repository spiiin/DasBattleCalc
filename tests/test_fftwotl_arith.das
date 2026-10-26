options gen2
options indenting = 4

// FFT: WotL: Arithmeticks against the game (research/fftwotl/arith1.txt,
// fcarith.py --sweep): Ramza casts Fire with every algorithm x number;
// the lit tiles (byte 5 bit 0x80) are the targets (the KO'd too) and the
// HP each unit lost when it was performed is the damage.
//   battlecalc tests/test_fftwotl_arith.das --state <fftwotl_test_battle1.ppst>
//   battlecalc tests/test_fftwotl_arith.das --state <fftwotl_test_battle2.ppst> --file arith2.txt --unit 16
// (arith2.txt: Gariland, Ganelon casts; EXP and Height - not used to fit)
require gba_mem
require gui_common
require strings
require daslib/strings_boost
require ../scripts/games/fftwotl/fftwotl_data.das
require ../scripts/games/fftwotl/fftwotl_battle.das
require ../scripts/games/fftwotl/fftwotl_attack.das
require fftwotl_edits
require ./test_check.das


[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<UnitW>
    check("battle reads", read_battle_w(units) == "")
    var m : MapW
    check("map reads", read_map_w(m))
    let file = gui_arg("--file", "arith1.txt")
    let slot = to_int(gui_arg("--unit", "0"))
    var caster = 0
    for (k in range(length(units))) {
        if (units[k].slot == slot) {
            caster = k
        }
    }
    let text = read_text(file)
    check("{file} read", text != "")
    var cases = 0
    for (line in split(text, "\n")) {
        let parts <- split(line, "|")
        if (length(parts) < 5) {
            continue
        }
        cases++
        let alg = find_index(ARITH_ALGS, strip(parts[0]))
        let ns = strip(parts[1])
        let num = ns == "Prime" ? 0 : (ns == "5" ? 1 : (ns == "4" ? 2 : 3))
        let name = "{strip(parts[0])} {ns}"
        // the targets: the units on the lit tiles
        var game : array<string>
        for (t in split(slice(strip(parts[2]), 5), " ")) {
            if (t != "") {
                game |> push(t)
            }
        }
        let ids <- arith_targets_w(units, alg, num, m, true)
        var model : array<string>
        for (i in ids) {
            model |> push("{units[i].x},{units[i].y}")
        }
        sort(game)
        sort(model)
        check("{name}: targets game [{join(game, " ")}], model [{join(model, " ")}]", join(game, " ") == join(model, " "))
        // the damage: "slot:hp lost"
        let hp_part = strip(parts[4])
        var lost : table<int; int>
        for (e in split(slice(hp_part, 2), " ")) {
            let c = find(e, ":")
            if (c > 0) {
                lost[to_int(slice(e, 0, c))] = to_int(slice(e, c + 1))
            }
        }
        for (i in arith_targets_w(units, alg, num, m)) {
            let f <- action_w(units[caster], units[i], 16, side_of_w(units[caster], units[i]))
            let got = lost?[units[i].slot] ?? 0
            check("{name}: {units[i].name} took {got}, model {f.damage}", got == f.damage)
        }
    }
    check("{cases} cases", cases >= (file == "arith1.txt" ? 16 : 8))
    return report()
}
