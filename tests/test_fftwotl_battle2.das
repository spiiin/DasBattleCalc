options gen2
options indenting = 4

// FFT: WotL, the second test battle: Gariland (the user's save, Ganelon's
// turn). What the first battle could not show: the party in the last
// records (16..20) with +0x2E set only for the unit at its turn, a guest
// (Delita), a 15 x 10 map. And the game's forecasts there
// (research/fftwotl/forecast10.txt, fcb2.py): Ganelon (record 16) on Rosa
// (record 17) - Attack, Fire, Poison, Toad, Death.
//   battlecalc tests/test_fftwotl_battle2.das --state <fftwotl_test_battle2.ppst>
require gba_mem
require gui_common
require ../scripts/games/fftwotl/fftwotl_data.das
require ../scripts/games/fftwotl/fftwotl_battle.das
require ../scripts/games/fftwotl/fftwotl_turns.das
require ../scripts/games/fftwotl/fftwotl_attack.das
require strings
require daslib/strings_boost
require fftwotl_edits
require ./test_check.das


[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<UnitW>
    check("battle reads", read_battle_w(units) == "")
    check("11 units (got {length(units)})", length(units) == 11)
    var party = 0
    var enemies = 0
    var guests = 0
    for (u in units) {
        party += u.team == TEAM_PLAYER ? 1 : 0
        enemies += u.team == TEAM_ENEMY ? 1 : 0
        guests += u.team == TEAM_GUEST ? 1 : 0
    }
    check("5 of the party, 5 enemies, 1 guest (got {party} / {enemies} / {guests})", party == 5 && enemies == 5 &&
        guests == 1)
    let g = find_named(units, "Ganelon")
    check("Ganelon is here", g >= 0)
    if (g >= 0) {
        let u = units[g]
        check("Ganelon: record 16, Chemist Lv 1, HP 37, MP 11, at 7, 12, Leo, at its turn",
            u.slot == 16 && u.job == "Chemist" && u.level == 1 && u.max_hp == 37 && u.max_mp == 11 && u.x == 7 &&
            u.y == 12 && u.zodiac == "Leo" && u.active)
    }
    let r = find_named(units, "AAAAA")
    check("Ramza (AAAAA): record 20, Squire, on the field though +0x2E is 0", r >= 0 && units[r].slot == 20 &&
        units[r].job == "Squire" && !units[r].on_field)
    let d = find_named(units, "Delita")
    check("Delita: the guest, record 0", d >= 0 && units[d].team == TEAM_GUEST && units[d].slot == 0)
    var m : MapW
    check("map reads", read_map_w(m))
    check("map 10 x 15 (got {m.w} x {m.h})", m.w == 10 && m.h == 15)
    let turns <- predict_turns_w(units, 4)
    check("Ganelon acts first", length(turns) > 0 && units[turns[0].unit].name == "Ganelon")
    // the forecasts: "<ability, 0 Attack> | case | edits | dmg heal mpdmg hit"
    let r16 = find_named(units, "Ganelon")
    let r17 = find_named(units, "Rosa")
    let text = read_text("forecast10.txt")
    check("forecast10.txt read", text != "" && r16 >= 0 && r17 >= 0)
    var cases = 0
    for (line in split(text, "
")) {
        let parts <- split(line, "|")
        if (length(parts) < 4 || r16 < 0 || r17 < 0) {
            continue
        }
        cases++
        let aid = to_int(strip(parts[0]))
        var att = units[r16]
        var tgt = units[r17]
        apply_writes(att, tgt, parts[2], 16)
        let nums <- split(strip(parts[3]), " ")
        let f <- action_w(att, tgt, aid == 0 ? ATTACK_W : aid, side_of_w(att, tgt))
        let dmg = !f.mp_effect && f.damage > 0 ? f.damage : 0
        let heal = !f.mp_effect && f.damage < 0 ? -f.damage : 0
        let mpd = f.mp_effect && f.damage > 0 ? f.damage : 0
        let game = "{nums[0]} {nums[1]} {nums[2]} {nums[3]}%"
        let model = "{dmg} {heal} {mpd} {f.hit}%"
        check("{f.name} {strip(parts[1])}: game {game}, model {model} ({join(f.mods, "; ")} | {join(f.hit_mods, "; ")})",
            game == model)
    }
    check("{cases} forecasts", cases >= 20)
    return report()
}
