options gen2
options indenting = 4

// FFT export (fft_battle.das export_battle): edits of Ramza (HP 77,
// Brave 70, Faith 40, PA 9, Speed 8, CT 50, Move 6) go into a new BizHawk
// state; reading it back gives the edits, the other units unchanged. A
// unit moved on the field (Lezales to (4, 3)) is not written: the game
// would take the tile but keep the sprite where it was. Loaded in BizHawk
// the game shows the edits (HP 077/113, Move 6's range).
//   battlecalc tests/test_fft_export.das --state <fft_test_ramza2.State> --out <new.State>
require gba_mem
require gui_common
require math
require daslib/strings_boost
require ../scripts/games/fft/fft_battle.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

def find_unit(units : array<FftUnit>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
}

[export]
def main() : int {
    let src = gui_arg("--state", "")
    let out = gui_arg("--out", "")
    check("--out given, not the source", out != "" && out != src)
    check("state loads", gba_load_state(src) == "")
    var units : array<FftUnit>
    check("battle read", read_battle(units) == "")
    let ri = find_unit(units, "Ramza")
    let li = find_unit(units, "Lezales")
    if (ri < 0 || li < 0 || out == "") {
        return 1
    }
    var before : array<FftUnit>
    before := units
    units[ri].hp = 77
    units[ri].brave = 70
    units[ri].faith = 40
    units[ri].pa = 9
    units[ri].speed = 8
    units[ri].ct = 50
    units[ri].move = 6
    units[li].x = 4
    units[li].y = 3
    units[li].facing = 0
    check("export", export_battle(units, out) == "")
    check("reload", gba_load_state(out) == "")
    var after : array<FftUnit>
    check("battle read back", read_battle(after) == "")
    check("same units", length(after) == length(before))
    if (length(after) != length(before)) {
        return 1
    }
    let r = after[ri]
    check("Ramza HP {r.hp} Br {r.brave} Fa {r.faith} PA {r.pa} Sp {r.speed} CT {r.ct} Mv {r.move}",
        r.hp == 77 && r.brave == 70 && r.faith == 40 && r.pa == 9 && r.speed == 8 && r.ct == 50 && r.move == 6)
    check("Ramza's original Brave {gba_read8(r.record + 0x23u)}, PA {gba_read8(r.record + 0x30u)}",
        gba_read8(r.record + 0x23u) == 70u && gba_read8(r.record + 0x30u) == 9u)
    let l = after[li]
    check("Lezales not moved: {l.x}, {l.y} facing {l.facing}", l.x == before[li].x && l.y == before[li].y
        && l.facing == before[li].facing)
    var same = true
    for (i in range(length(after))) {
        if (i != ri && i != li) {
            let a = after[i]
            let b = before[i]
            same = same && a.hp == b.hp && a.pa == b.pa && a.ct == b.ct && a.x == b.x && a.y == b.y && a.facing == b.facing
        }
    }
    check("the other units unchanged", same)
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
