options gen2
options indenting = 4

// NDS support of gba_mem (native/nds_mem.cpp) on the first FFTA2 battle:
// the melonDS state's main RAM and the ROM's files.
//   battlecalc tests/test_nds_mem.das --state <ffta2_test_battle1.State> --rom <FFTA2 (USA)>.zip
require gba_mem
require gui_common

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
    let rom_err = gba_load_rom(gui_arg("--rom", ""))
    let state_err = gba_load_state(gui_arg("--state", ""))
    check("rom loads ({rom_err})", rom_err == "")
    check("state loads ({state_err})", state_err == "")
    check("game code A6FE (got {gba_rom_code()})", gba_rom_code() == "A6FE")
    check("the state is NDS", gba_state_is_nds())
    // Luso, the acting unit: HP 90 / 90, MP 14 / 14 (research/ffta2/notes.md)
    check("Luso HP 90 (got {gba_read16(0x0212B154u)})", gba_read16(0x0212B154u) == 90u)
    check("Luso MP 14 / 14", gba_read16(0x0212B158u) == 14u && gba_read16(0x0212B15Au) == 14u)
    check("the cartridge header copy at 0x027FFE0C", gba_read32(0x027FFE0Cu) == 0x45463641u)
    let jobs = nds_pak_file("system/rom/sysdata_rom.idx", "system/rom/sysdata.pak", 1)
    check("jobs: 163 x 72 bytes (got {nds_buf_size(jobs)})", nds_buf_size(jobs) == 163 * 72)
    check("Soldier: Move 4, Jump 2, HP 90", nds_buf_read8(jobs, 72 + 17) == 4u && nds_buf_read8(jobs, 72 + 18) == 2u
        && nds_buf_read8(jobs, 72 + 19) == 90u)
    let items = nds_pak_file("system/rom/sysdata_rom.idx", "system/rom/sysdata.pak", 16)
    check("equipment: 412 x 40 bytes (got {nds_buf_size(items)})", nds_buf_size(items) == 412 * 40)
    check("Shortsword Attack 22", nds_buf_read8(items, 25 * 40 + 19) == 22u)
    let names = nds_pak_file("system/rom/JD_message_rom_0.idx", "system/rom/JD_message_0.pak", 0)
    check("name table: 779 strings (got {nds_buf_read16(names, 0)})", nds_buf_read16(names, 0) == 779u)
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
