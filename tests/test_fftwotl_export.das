options gen2
options indenting = 4

// FFT: The War of the Lions: export a PPSSPP state with edited units and
// read it back (job, skillset, equipment, Brave, HP, statuses, learned).
//   battlecalc tests/test_fftwotl_export.das --state <fftwotl_test_battle1.ppst> [--out <new.ppst>]
require gba_mem
require gui_common
require ../scripts/games/fftwotl/fftwotl_data.das
require ../scripts/games/fftwotl/fftwotl_battle.das
require ./test_check.das


[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<UnitW>
    check("battle reads", read_battle_w(units) == "")
    // Ramza: Brave 97, HP 50, a Broadsword (19) in the right hand, Protect,
    // Items as secondary, Chemist's Hi-Potion learned
    units[0].brave = 97
    units[0].hp = 50
    units[0].items[SLOT_RIGHT] = 19
    units[0].secondary = 6
    set_status_bit(units[0].status, ST_PROTECT, true)
    set_learned_bit(units[0], 1, 1, true)
    recompute_unit_w(units[0])
    let out = gui_arg("--out", "{gui_project_dir()}/build/test_fftwotl_export.ppst")
    let err = export_battle_w(units, out)
    check("exported ({err})", err == "")
    check("loads back", gba_load_state(out) == "")
    var back : array<UnitW>
    check("battle reads back", read_battle_w(back) == "")
    if (length(back) > 0) {
        let r = back[0]
        check("Brave 97 (got {r.brave})", r.brave == 97)
        check("HP 50", r.hp == 50)
        check("Broadsword, WP 4 (got {r.equip[SLOT_RIGHT].name}, {r.wp[0]})", r.items[SLOT_RIGHT] == 19 && r.wp[0] == 4)
        check("secondary Items", skillset_name_w(r.secondary) == "Items")
        check("Protect", has_status_w(r, ST_PROTECT))
        check("Hi-Potion learned", learned_bit(r, 1, 1))
        check("others unchanged", back[1].name == "Agrias" && back[1].hp == units[1].hp)
    }
    return report()
}
