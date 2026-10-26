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
// with support / reaction bits of the record's masks (+0x95..);
// forecast5.txt (--reactions): Shirahadori, Archer's Bane, Counter, First
// Strike, Parry from the back; forecast6.txt (fcyside.py): the side
// along y - Ramza moved to (7, 4) / (7, 2), Lezalas in each facing;
// forecast7.txt / forecast8.txt (fctj.py): Throw (the stock edited to one
// item: "item<id>") and Jump (the Dragoon set, weapons, statuses). The same
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
require fftwotl_edits

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}



// the forecasts of one file: action (Attack or an ability) by Ramza
// (record 0) on Lezalas (record 5); the number of cases
def check_file(units : array<UnitW>; file : string; action : int; throws : bool = false) : int {
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
        // Throw (forecast7.txt): "item<id>..." - the stock held that item only
        var item = 0
        if (throws && starts_with(name, "item")) {
            var k = 4
            while (k < length(name) && character_at(name, k) >= '0' && character_at(name, k) <= '9') {
                item = item * 10 + character_at(name, k) - '0'
                k++
            }
        }
        var f : FightW
        if (item > 0) {
            f <- throw_item_w(att, tgt, item, side_of_w(att, tgt))
        } else {
            f <- action_w(att, tgt, action, side_of_w(att, tgt))
        }
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



// abilities: "id | case | writes | damage healing mp_damage hit"
def check_abilities(units : array<UnitW>; file : string) : int {
    let text = read_text(file)
    check("{file} read", text != "")
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
        // Death / Toad on the living Lezalas: the game shows 0% - his own
        // (no immunity in his record, job, equipment; on Rosa in Gariland
        // they work: test_fftwotl_battle2)
        if ((aid == 29 || aid == 30) && name != "t_undead") {
            continue
        }
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
    let reactions = check_file(units, "forecast5.txt", ATTACK_W)
    let sides = check_file(units, "forecast6.txt", ATTACK_W)
    let throws = check_file(units, "forecast7.txt", ATTACK_W, true)
    let jumps = check_file(units, "forecast8.txt", 394)
    check("{throws} Throw forecasts", throws >= 15)
    check("{jumps} Jump forecasts", jumps >= 10)
    check("{reactions} reaction forecasts", reactions >= 10)
    check("{sides} side forecasts", sides >= 12)
    check("{supports} support forecasts", supports >= 8)
    check("{attacks} Attack forecasts", attacks >= 80)
    check("{fires} Fire forecasts", fires >= 30)
    let abilities = check_abilities(units, "forecast3.txt")
    let statuses = check_abilities(units, "forecast9.txt")
    check("{statuses} status / drain / Gravity forecasts", statuses >= 50)
    check("{abilities} ability forecasts", abilities >= 50)
    print("test_fftwotl_forecast: {total - failed} / {total} passed
")
    return failed == 0 ? 0 : 1
}
