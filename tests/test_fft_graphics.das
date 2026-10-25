options gen2
options indenting = 4

// FFT graphics from the disc (native/psx_mem.cpp, native/gba_gfx.cpp,
// scripts/games/fft/fft_map.das) without a renderer: the disc's files,
// the battle's map by the GNS in RAM (the first battle: MAP056), its mesh
// (63 + 372 textured, 27 + 45 untextured polygons; x 0..10, z 0..14
// tiles), the units' battle sprites (BATTLE.BIN's table).
//   battlecalc tests/test_fft_graphics.das --state <fft_test_battle1.State> --rom <FFT (USA).cue>
require gba_mem
require gui_common
require sdl3
require math
require daslib/strings_boost
require ../scripts/games/fft/fft_battle.das
require ../scripts/ui/battle_field.das
require ../scripts/games/fft/fft_map.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    let err = psx_open_disc(gui_arg("--rom", ""))
    check("disc opens: {err}", err == "")
    if (err != "") {
        return 1
    }
    check("BATTLE.BIN {psx_buf_size(psx_disc_file("BATTLE.BIN"))} B", psx_buf_size(psx_disc_file("BATTLE.BIN")) == 1397096)
    check("ITEM.BIN", psx_buf_size(psx_disc_file("EVENT/ITEM.BIN")) == 33280)
    check("no such file", psx_disc_file("BATTLE/NONE.BIN") == -1)
    check("map {psx_find_map()}", psx_find_map() == 56)
    var polys : array<FieldPoly>
    var r : SDL_Renderer?
    let merr = load_map_mesh(r, polys)
    check("mesh: {merr}, {length(polys)} polygons", merr == "" && length(polys) == 63 + 372 + 27 + 45)
    var lo = float3(1000.0)
    var hi = float3(-1000.0)
    for (pl in polys) {
        for (c in range(4)) {
            lo = min(lo, pl.p[c])
            hi = max(hi, pl.p[c])
        }
    }
    check("mesh x {lo.x}..{hi.x}, y {lo.y}..{hi.y}", lo.x == -0.5 && hi.x == 9.5 && lo.y == -0.5 && hi.y == 13.5)
    var units : array<FftUnit>
    check("battle read", read_battle(units) == "")
    // Ramza 0x02 (RAMUZA2), the generics by the job: Knight 0x64, Archer
    // 0x66, Chemist 0x62, Squire 0x60
    let want = fixed_array<tuple<string; int>>(("Ramza", 2), ("Lezales", 100), ("Viggs", 102), ("Fukes", 98),
        ("Rad", 96), ("Alicia", 101))
    for (w in want) {
        for (un in units) {
            if (un.name == w._0) {
                check("{un.name}'s sprite {unit_sprite(un)}, want {w._1}", unit_sprite(un) == w._1)
            }
        }
    }
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
