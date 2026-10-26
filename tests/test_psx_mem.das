options gen2
options indenting = 4

// Reading a BizHawk Nymashock (PSX) state (native/psx_mem.cpp): the main
// RAM of the first battle of Final Fantasy Tactics (USA) - Ramza's battle
// record (research/fft/notes.md) as the bottom screen shows it, and a
// write: an exported state reads back with the edit.
//   battlecalc tests/test_psx_mem.das --state <fft_test_battle1.State> [--out <new.State>]
require gba_mem
require gui_common
require ./test_check.das


let RAMZA = 0x801908CCu                 // the first battle record

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    check("a PSX state", gba_state_is_psx() && !gba_state_is_nds())
    check("Ramza's level 9", gba_read8(RAMZA + 0x22u) == 9u)
    check("HP 113 / 113", gba_read16(RAMZA + 0x28u) == 113u && gba_read16(RAMZA + 0x2Au) == 113u)
    check("MP 24 / 24", gba_read16(RAMZA + 0x2Cu) == 24u && gba_read16(RAMZA + 0x2Eu) == 24u)
    check("the 0x80 / 0x00 mirrors", gba_read16(RAMZA & 0x1FFFFFu) == gba_read16(RAMZA))
    // "Ramza" in FFT's encoding (a-z 0x24..0x3D, A-Z 0x0A..0x23), 0xFE ends
    check("the name", gba_read8(RAMZA + 0x12Cu) == 0x1Bu && gba_read8(RAMZA + 0x12Du) == 0x24u)
    check("a frame", gba_frame_width() >= 0.0)
    let out = gui_arg("--out", "")
    if (out != "") {
        gba_edit_begin()
        gba_edit16(RAMZA + 0x28u, 77u)
        check("export", gba_save_state(out) == "")
        check("the export loads", gba_load_state(out) == "")
        check("HP 77 in it", gba_read16(RAMZA + 0x28u) == 77u && gba_read16(RAMZA + 0x2Au) == 113u)
    }
    return report()
}
