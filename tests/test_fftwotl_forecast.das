options gen2
options indenting = 4

// FFT: The War of the Lions: the model against the game's own forecasts.
// research/fftwotl/forecast1.txt (fcvary.py): Ramza attacks Lezalas in
// the first battle; forecast2.txt (fcvary.py --magic): he casts Fire on
// him (Black Magicks given as the secondary skillset). Each line edits
// bytes of the unit records, then the game's forecast (damage, hit %)
// read from the target's record (+0x1B6, +0x1DC). forecast3.txt
// (fcgroups.py): abilities (Cure, Rend Power, Rend MP, Umbra, Potion, Rush,
// Stone) with their id; the forecast is damage, healing (+0x1B8), MP
// damage (+0x1BA) and hit. forecast4.txt (fcvary.py --supports): Attack
// with support / reaction bits of the record's masks (+0x95..). The same
// edits go into the model's units.
//   battlecalc tests/test_fftwotl_forecast.das --state <fftwotl_test_battle1.ppst> [--print 1]
require gba_mem
require gui_common
require math
require strings
require daslib/strings_boost
require daslib/fio
require ../scripts/games/fftwotl/fftwotl_data.das
require ../scripts/games/fftwotl/fftwotl_battle.das
require ../scripts/games/fftwotl/fftwotl_attack.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

def hex_int(s : string) : int {
    var v = 0
    for (c in s) {
        let d = c >= '0' && c <= '9' ? c - '0' : (c >= 'a' && c <= 'f' ? c - 'a' + 10 : 0)
        v = v * 16 + d
    }
    return v
}

// one edit of the probe (record offset, value) as the model's field
def apply_edit(var u : UnitW; off, v : int) {
    if (off == 0x3E) {
        u.pa = v
    } elif (off == 0x3F) {
        u.ma = v
    } elif (off == 0x09) {
        u.zodiac_id = v >> 4
    } elif (off == 0x06) {
        u.gender = v
    } elif (off == 0x20) {
        u.items[SLOT_RIGHT] = v
        // the game keeps the record's current PA / MA / Speed (the new
        // item's bonus is not added by this edit)
        let pa = u.pa
        let ma = u.ma
        let sp = u.sp
        recompute_unit_w(u)
        u.pa = pa
        u.ma = ma
        u.sp = sp
    } elif (off == 0x2B) {
        u.brave = v
    } elif (off == 0x2D) {
        u.faith = v
    } elif (off >= 0x62 && off < 0x67) {
        u.status[off - 0x62] = uint8(v)
    } elif (off == 0x4B) {
        u.c_ev = v
    } elif (off == 0x51) {
        u.facing = v & 3
    } elif (off == 0x77) {
        u.absorb = v
    } elif (off == 0x78) {
        u.cancel = v
    } elif (off == 0x79) {
        u.half = v
    } elif (off == 0x7A) {
        u.weak = v
    } elif (off >= 0x95 && off < 0xA0) {
        u.rsm_mask[off - 0x95] = uint8(v)
    } elif (off == 0x16) {
        u.support = v               // the id alone: no effect in the game
    }
    // the game ignores the record's shield / accessory evades and
    // strengthen byte (+0x48..0x4A, +0x7B): from the equipment
}

// the forecasts of one file: action (Attack or an ability) by Ramza
// (record 0) on Lezalas (record 5); the number of cases
def check_file(units : array<UnitW>; file : string; action : int) : int {
    let path = "{gui_project_dir()}/research/fftwotl/{file}"
    var text = ""
    fopen(path, "rb") $(f) {
        if (f != null) {
            text = fread(f)
        }
    }
    check("forecasts read: {path}", text != "")
    var cases = 0
    for (line in split(text, "
")) {
        let parts <- split(line, "|")
        if (length(parts) < 3) {
            continue
        }
        cases++
        let name = strip(parts[0])
        var att = units[0]
        var tgt = units[5]
        for (wr in split(strip(parts[1]), " ")) {
            if (wr == "") {
                continue
            }
            let colon = find(wr, ":")
            let eq = find(wr, "=")
            let who = to_int(slice(wr, 0, colon))
            let off = hex_int(slice(wr, colon + 1, eq))
            var vs = slice(wr, eq + 1)
            if (ends_with(vs, "/2")) {
                vs = slice(vs, 0, length(vs) - 2)
            }
            if (who == 0) {
                apply_edit(att, off, hex_int(vs))
            } else {
                apply_edit(tgt, off, hex_int(vs))
            }
        }
        let nums <- split(strip(parts[2]), " ")
        let dmg = to_int(nums[0])
        let hit = to_int(nums[1])
        let f = action_w(att, tgt, action, side_of_w(att, tgt))
        let got = max(f.damage, 0)
        if (gui_arg("--print", "") != "") {
            print("{f.name} {name}: game {dmg} {hit}% model {got} {f.hit}%
")
        }
        check("{f.name} {name}: game {dmg} / {hit}%, model {got} / {f.hit}% ({join(f.mods, "; ")})",
            got == dmg && f.hit == hit)
    }
    return cases
}

def read_text(file : string) : string {
    var text = ""
    fopen("{gui_project_dir()}/research/fftwotl/{file}", "rb") $(f) {
        if (f != null) {
            text = fread(f)
        }
    }
    return text
}

def apply_writes(var att, tgt : UnitW; spec : string) {
    for (wr in split(strip(spec), " ")) {
        if (wr == "") {
            continue
        }
        let colon = find(wr, ":")
        let eq = find(wr, "=")
        let who = to_int(slice(wr, 0, colon))
        let off = hex_int(slice(wr, colon + 1, eq))
        var vs = slice(wr, eq + 1)
        if (ends_with(vs, "/2")) {
            vs = slice(vs, 0, length(vs) - 2)
        }
        if (who == 0) {
            apply_edit(att, off, hex_int(vs))
        } else {
            apply_edit(tgt, off, hex_int(vs))
        }
    }
}

// abilities: "id | case | writes | damage healing mp_damage hit"
def check_abilities(units : array<UnitW>) : int {
    let text = read_text("forecast3.txt")
    check("forecast3.txt read", text != "")
    var cases = 0
    for (line in split(text, "
")) {
        let parts <- split(line, "|")
        if (length(parts) < 4) {
            continue
        }
        cases++
        let aid = to_int(strip(parts[0]))
        let name = strip(parts[1])
        var att = units[0]
        var tgt = units[5]
        apply_writes(att, tgt, parts[2])
        let nums <- split(strip(parts[3]), " ")
        let f = action_w(att, tgt, aid, side_of_w(att, tgt))
        let dmg = !f.mp_effect && f.damage > 0 ? f.damage : 0
        let heal = !f.mp_effect && f.damage < 0 ? -f.damage : 0
        let mpd = f.mp_effect && f.damage > 0 ? f.damage : 0
        let game = "{nums[0]} {nums[1]} {nums[2]} {nums[3]}%"
        let model = "{dmg} {heal} {mpd} {f.hit}%"
        if (gui_arg("--print", "") != "") {
            print("{f.name} {name}: game {game} model {model}
")
        }
        check("{f.name} {name}: game {game}, model {model} ({join(f.mods, "; ")} | {join(f.hit_mods, "; ")})",
            game == model)
    }
    return cases
}

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<UnitW>
    check("battle reads", read_battle_w(units) == "")
    let attacks = check_file(units, "forecast1.txt", ATTACK_W)
    let fires = check_file(units, "forecast2.txt", 16)
    let supports = check_file(units, "forecast4.txt", ATTACK_W)
    check("{supports} support forecasts", supports >= 8)
    check("{attacks} Attack forecasts", attacks >= 80)
    check("{fires} Fire forecasts", fires >= 30)
    let abilities = check_abilities(units)
    check("{abilities} ability forecasts", abilities >= 50)
    print("test_fftwotl_forecast: {total - failed} / {total} passed
")
    return failed == 0 ? 0 : 1
}
