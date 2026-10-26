options gen2
options indenting = 4

// PSP support of gba_mem (native/psp_mem.cpp) on the first battle of FFT:
// The War of the Lions: the PPSSPP state's RAM, and a written state.
//   battlecalc tests/test_psp_mem.das --state <fftwotl_test_battle1.ppst> [--out <new.ppst>]
require gba_mem
require gui_common
require ./test_check.das


// Ramza's battle record (research/fftwotl/notes.md)
let RAMZA = 0x092E5CB4u

[export]
def main() : int {
    let path = gui_arg("--state", "")
    let err = gba_load_state(path)
    check("state loads ({err})", err == "")
    check("the state is PSP", gba_state_is_psp() && !gba_state_is_nds())
    check("BOOT.BIN at 0x08804000: the game id ULUS10297 at 0x08B18354",
        gba_read32(0x08B18354u) == 0x53554C55u && gba_read32(0x08B18358u) == 0x39323031u)
    check("Ramza HP 111 / 111 (got {gba_read16(RAMZA + 0x30u)})",
        gba_read16(RAMZA + 0x30u) == 111u && gba_read16(RAMZA + 0x32u) == 111u)
    check("Ramza MP 24 / 24", gba_read16(RAMZA + 0x34u) == 24u && gba_read16(RAMZA + 0x36u) == 24u)
    check("Ramza level 9, Brave 53, Faith 47", gba_read8(RAMZA + 0x29u) == 9u && gba_read8(RAMZA + 0x2Bu) == 53u
        && gba_read8(RAMZA + 0x2Du) == 47u)
    check("kseg mirror 0x48.. reads the same", gba_read16(0x492E5CE4u) == 111u)
    check("beyond the 32 MB RAM reads 0", gba_read32(0x0A000000u) == 0u)
    // write: HP 99, then load the new file and read it back
    let out = gui_arg("--out", "{gui_project_dir()}/build/test_psp_mem.ppst")
    gba_edit_begin()
    gba_edit16(RAMZA + 0x30u, 99u)
    let werr = gba_save_state(out)
    check("state written ({werr})", werr == "")
    check("reads still see the loaded RAM", gba_read16(RAMZA + 0x30u) == 111u)
    let rerr = gba_load_state(out)
    check("written state loads ({rerr})", rerr == "")
    check("written HP 99 (got {gba_read16(RAMZA + 0x30u)})", gba_read16(RAMZA + 0x30u) == 99u)
    check("the rest unchanged", gba_read16(RAMZA + 0x32u) == 111u && gba_read8(RAMZA + 0x2Bu) == 53u)
    return report()
}
