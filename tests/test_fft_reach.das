options gen2
options indenting = 4

// FFT reach (scripts/games/fft/fft_reach.das) against the game's marks:
// states saved by research/fft/plan_probe.lua with Ramza's Move or Attack
// range shown (the terrain's +5: 0x20 Move, 0x40 the range). From
// fft_test_ramza2 with edits in RAM: Move / Jump, the weapon (Long Bow,
// Spear, Cross Bow, Romanda Gun), a tile's height (bow_up16: (6, 6) at 16,
// sword_up14 / dn8: (7, 3) at 14 / 8).
//   battlecalc tests/test_fft_reach.das --dir <BizHawk PSX/State>
require gba_mem
require gui_common
require math
require daslib/strings_boost
require ../scripts/games/fft/fft_battle.das
require ../scripts/games/fft/fft_attack.das
require ../scripts/games/fft/fft_reach.das

let TERRAIN = 0x8018F8CCu

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

def tiles_text(m : FftMap; set : array<bool>; other : array<bool>) : string {
    var res = ""
    for (i in range(length(set))) {
        if (set[i] && !other[i]) {
            res += " ({i % m.w}, {i / m.w})"
        }
    }
    return res
}

[export]
def main() : int {
    let dir = gui_arg("--dir", "")
    let cases = fixed_array<tuple<string; int>>(("move", 32), ("move_m7j3", 32), ("move_m3j8", 32),
        ("move_m6j1", 32), ("sword", 64), ("sword_up14", 64), ("sword_dn8", 64), ("spear", 64), ("bow", 64),
        ("bow_up16", 64), ("xbow", 64), ("gun", 64))
    for (c in cases) {
        let name = c._0
        if (gba_load_state("{dir}/fft_reach_{name}.State") != "") {
            check("{name}: the state loads", false)
            continue
        }
        var units : array<FftUnit>
        read_battle(units)
        var m : FftMap
        read_map(m)
        var me = -1
        for (i in range(length(units))) {
            if (units[i].active) {
                me = i
            }
        }
        check("{name}: the active unit", me >= 0)
        if (me < 0) {
            continue
        }
        var game : array<bool>
        for (i in range(m.w * m.h)) {
            game |> push((int(gba_read8(TERRAIN + uint(i) * 8u + 5u)) & c._1) != 0)
        }
        let model <- c._1 == 32 ? move_reach(units, m, me) : attack_reach(units[me], m)
        var n = 0
        var same = length(model) == length(game)
        for (i in range(length(game))) {
            n += game[i] ? 1 : 0
            same = same && model[i] == game[i]
        }
        check("{name} ({n} tiles): only the model{tiles_text(m, model, game)}; only the game{tiles_text(m, game, model)}",
            same)
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
