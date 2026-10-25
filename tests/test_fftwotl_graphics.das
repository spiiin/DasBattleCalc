options gen2
options indenting = 4

// FFT: WotL graphics from the ISO (native/psx_mem.cpp: the .iso and
// fftpack.bin; native/gba_gfx.cpp; scripts/games/fftwotl/fftwotl_map.das)
// without a renderer: fftpack.bin's files, the battle's map by the GNS in
// RAM (the first battle: MAP056 = fftpack 2995), its mesh (63 + 372
// textured, 27 + 45 untextured polygons; x 0..10, z 0..14 tiles), the
// units' sprite sheets and their SHP types.
//   battlecalc tests/test_fftwotl_graphics.das --state <fftwotl_test_battle1.ppst> --rom <WotL .iso>
require gba_mem
require gui_common
require sdl3
require math
require daslib/strings_boost
require ../scripts/games/fftwotl/fftwotl_battle.das
require ../scripts/games/fftwotl/fftwotl_map.das
require ../scripts/ui/battle_field.das

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
    check("ISO opens: {err}", err == "")
    if (err != "") {
        return 1
    }
    check("fftpack.bin: {psp_pack_count()} files", psp_pack_count() == 3968)
    check("ITEM.BIN {psp_pack_size(33)} B", psp_pack_size(33) == 34816 && psx_buf_size(psp_pack_file(33)) == 34816)
    check("TYPE1.SHP", psx_buf_size(psp_pack_file(51)) > 0x410)
    check("no file 0", psp_pack_file(0) == -1 && psp_pack_file(5000) == -1)
    check("map {psp_find_map()}", psp_find_map() == 2995)
    var polys : array<FieldPoly>
    var r : SDL_Renderer?
    let merr = load_map_mesh_w(r, polys)
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
    var units : array<UnitW>
    check("battle read", read_battle_w(units) == "")
    // graphics.md: Ramza 0x02, Agrias 0x34, Lezalas 0x64 (KNIGHT_M), the
    // Chemist 0x62 (TYPE2), Ladd 0x60; enemies palette 2
    let want = fixed_array<tuple<string; int; int; int>>(("Agrias", 52, 0, 0), ("Lezalas", 100, 2, 0),
        ("Fuchs", 98, 2, 1), ("Ladd", 96, 0, 0))
    for (w in want) {
        var seen = false
        for (un in units) {
            if (un.name == w._0) {
                seen = true
                check("{un.name}: sheet {un.sheet} palette {un.palette} type {psp_sprite_type(un.sheet)}",
                    un.sheet == w._1 && un.palette == w._2 && psp_sprite_type(un.sheet) == w._3)
            }
        }
        check("{w._0} in battle", seen)
    }
    check("stand frames", stand_frame_w(96, false) == 11 && stand_frame_w(96, true) == 16)
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
