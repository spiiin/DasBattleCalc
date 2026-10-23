options gen2
options indenting = 4

// What every FFTA test starts with: the ROM (--rom), the state (--state)
// and the battle in it. "" or the first error, with the step as prefix.
module test_common shared public

require gui_common
require gba_mem
require ../scripts/games/ffta/ffta_battle.das
require ../scripts/core/result_try.das

def load_test_units(var units : array<BattleUnit>) : string {
    try_ok(gba_load_rom(gui_arg("--rom", "")), "rom: ")
    try_ok(gba_load_state(gui_arg("--state", "")), "state: ")
    try_ok(read_battle(units), "battle: ")
    return ""
}

def load_test_battle(var units : array<BattleUnit>; var battle : BattleMap) : string {
    try_ok(load_test_units(units))
    read_map(battle)
    return ""
}
