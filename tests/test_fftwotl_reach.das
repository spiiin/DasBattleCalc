options gen2
options indenting = 4

// FFT: WotL: Attack's reach with the heights (reach_w) against the tiles
// the game highlights (research/fftwotl/reach1.txt from fcreach.py: Ramza
// with each weapon in the right hand, the targeting open; byte 5 bit 0x40
// of a tile). Lines: "at X,Y | weapon ID | x,y x,y ... | upper ...".
//   battlecalc tests/test_fftwotl_reach.das --state <fftwotl_test_battle1.ppst> [--print 1]
//   battlecalc tests/test_fftwotl_reach.das --state <fftwotl_test_battle2.ppst> --reach reach2.txt --unit 16
// (reach2.txt: the Gariland battle, Ganelon - record 16 - at its turn;
// not used to fit the rules)
require gba_mem
require gui_common
require strings
require daslib/fio
require daslib/strings_boost
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

def tiles_of(s : string) : array<int2> {
    var res : array<int2>
    for (p in split(strip(s), " ")) {
        let c = find(p, ",")
        if (c > 0) {
            res |> push(int2(to_int(slice(p, 0, c)), to_int(slice(p, c + 1))))
        }
    }
    return <- res
}

def has_tile(a : array<int2>; t : int2) : bool {
    for (v in a) {
        if (v.x == t.x && v.y == t.y) {
            return true
        }
    }
    return false
}

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<UnitW>
    check("battle reads", read_battle_w(units) == "")
    var m : MapW
    check("map reads", read_map_w(m))
    var text = ""
    let file = gui_arg("--reach", "reach1.txt")
    let slot = to_int(gui_arg("--unit", "0"))
    var who = 0
    for (k in range(length(units))) {
        if (units[k].slot == slot) {
            who = k
        }
    }
    fopen("{gui_project_dir()}/research/fftwotl/{file}", "rb") $(f) {
        if (f != null) {
            text = fread(f)
        }
    }
    check("{file} read", text != "")
    var cases = 0
    for (line in split(text, "\n")) {
        let parts <- split(line, "|")
        if (length(parts) < 4) {
            continue
        }
        cases++
        let at <- tiles_of(slice(strip(parts[0]), 3))
        let wid = to_int(slice(strip(parts[1]), 7))
        let game <- tiles_of(parts[2])
        var att = units[who]
        att.x = at[0].x
        att.y = at[0].y
        att.items[SLOT_RIGHT] = wid
        recompute_unit_w(att)
        let f <- action_w(att, att, ATTACK_W, SideW.Front)
        var model : array<int2>
        for (ty in range(m.h)) {
            for (tx in range(m.w)) {
                if (reach_w(att, f, m, tx, ty, false).ok) {
                    model |> push(int2(tx, ty))
                }
            }
        }
        var missing : array<string>
        var extra : array<string>
        for (t in game) {
            if (!has_tile(model, t)) {
                missing |> push("{t.x},{t.y} ({reach_w(att, f, m, t.x, t.y, false).why})")
            }
        }
        for (t in model) {
            if (!has_tile(game, t)) {
                extra |> push("{t.x},{t.y} ({reach_w(att, f, m, t.x, t.y, false).why})")
            }
        }
        let name = "{strip(parts[0])}, {read_item_w(wid).name}"
        if (gui_arg("--print", "") != "") {
            print("{name}: game {length(game)} tiles, model {length(model)}\n")
        }
        check("{name}: the game lights but the model does not: {join(missing, "; ")}", length(missing) == 0)
        check("{name}: the model reaches but the game does not light: {join(extra, "; ")}", length(extra) == 0)
    }
    check("{cases} reach cases", cases >= 9 || (file != "reach1.txt" && cases >= 4))
    print("test_fftwotl_reach: {total - failed} / {total} passed\n")
    return failed == 0 ? 0 : 1
}
