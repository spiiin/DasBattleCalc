options gen2
options indenting = 4

// FFTA2 abilities (action2 in scripts/games/ffta2/ffta2_attack.das)
// against the game's forecasts: Luso (moved to 9, 8) uses each ability on
// Sasarr (10, 8) - research/ffta2/vary_probe.lua with "ab=<id>" sets the
// ability of the forecast call. A log line: name hit damage; the
// abilities whose amount is function 1 (damage, healing spells).
//   battlecalc tests/test_ffta2_abilities.das --state <ffta2_test_battle1.State> --rom <FFTA2 (USA)>.zip
//     [--data research/ffta2/abil1.txt] [--verbose 1]
require gba_mem
require gui_common
require daslib/fio
require strings
require daslib/strings_boost
require ../scripts/games/ffta2/ffta2_battle.das
require ../scripts/games/ffta2/ffta2_attack.das
require ./test_check.das

[export]
def main() : int {
    gba_load_rom(gui_arg("--rom", ""))
    gba_load_state(gui_arg("--state", ""))
    var units : array<Unit2>
    let err = read_battle2(units)
    if (err != "") {
        print("FAIL {err}\n")
        return 1
    }
    let verbose = gui_arg_int("--verbose", 0) != 0
    var att = units[find_named(units, "Luso")]
    let tgt = units[find_named(units, "Sasarr")]
    att.x = 9
    att.y = 8
    var skipped = 0
    for (line in split(fread(gui_arg("--data", "research/ffta2/abil1.txt")), "\n")) {
        let p <- split(line, " ")
        if (length(p) < 3 || !starts_with(p[0], "ab")) {
            continue
        }
        let ab = read_ability2(to_int(slice(p[0], 2)))
        let f <- action2(att, tgt, ab, side_of2(att, tgt))
        if (f.unsupported || f.hit_unsupported) {
            skipped++
            continue
        }
        total++
        let game_hit = to_int(p[1])
        let game_dmg = to_int(p[2])
        let ok = f.hit == game_hit && (f.damage & 0xFFFF) == game_dmg
        if (!ok) {
            failed++
        }
        if (!ok || verbose) {
            print("{ok ? "ok  " : "FAIL"} {ab.id} {ab.name}: game {game_hit} / {game_dmg}, model {f.hit} / {f.damage}  ({is_magick2(ab) ? "magick" : "physical"}, power {ab.power}, element {ab.element}, effect {f.effect} {ab.fx[f.effect >= 0 ? f.effect : 0]}, flags {ab.flags:x})\n")
        }
    }
    print("{skipped} skipped (not translated)\n")
    return report()
}
