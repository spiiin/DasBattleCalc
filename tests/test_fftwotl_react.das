options gen2
options indenting = 4

// FFT: WotL: does the target's reaction trigger (reaction_w) - against the
// game, the action performed (research/fftwotl/react1.txt, fcreact.py):
// Ramza attacks / Rushes / casts Arithmeticks Fire on Lezalas, who has one
// reaction, Brave 100, no shield, C-EV 0. A reaction triggered when the
// result differs from the control (the same action without a reaction):
// Ramza's HP, Lezalas's HP (for his starting HP), MP, CT, Brave, PA, MA or
// statuses (the Critical status itself aside); controls: "none" (Attack),
// "rush", "arith". Lines with Ramza still
// charging (a magick not landed) are skipped.
//   battlecalc tests/test_fftwotl_react.das --state <fftwotl_test_battle1.ppst>
require gba_mem
require gui_common
require strings
require math
require daslib/strings_boost
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

// "hp mp ct brave faith pa ma statuses" -> 7 numbers and the statuses' hex
struct Snap {
    v : int[7]
    st : string
}

def snap_of(s : string) : Snap {
    var r : Snap
    let ps <- split(strip(s), " ")
    for (k in range(7)) {
        r.v[k] = to_int(ps[k + 1])
    }
    r.st = ps[8]
    return r
}

// the statuses without the Critical bit (the third byte's 0x01)
def st_core(s : string) : string {
    if (length(s) < 6) {
        return s
    }
    let b = to_int(slice(s, 4, 6), true) & 0xFE
    return "{slice(s, 0, 4)}{fmt(":02x", b)}{slice(s, 6)}"
}

[export]
def main() : int {
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<UnitW>
    check("battle reads", read_battle_w(units) == "")
    let text = read_text("react1.txt")
    check("react1.txt read", text != "")
    // the controls (reaction 0) by action: "attack" for Attack / Rush cases,
    // "arith" for the Arithmeticks
    var ctrl : table<string; tuple<Snap; Snap; Snap>>
    var lines : array<array<string>>
    for (line in split(text, "\n")) {
        var parts <- split(line, "|")
        if (length(parts) < 6) {
            continue
        }
        let rid = to_int(strip(parts[0]))
        let case = strip(parts[1])
        if (rid == 0) {
            ctrl[case == "arith" || case == "rush" ? case : "attack"] = (snap_of(parts[3]), snap_of(parts[4]),
                snap_of(parts[5]))
        } else {
            lines |> emplace(parts)
        }
    }
    check("the controls", key_exists(ctrl, "attack"))
    var cases = 0
    for (parts in lines) {
        let rid = to_int(strip(parts[0]))
        let case = strip(parts[1])
        let a = snap_of(parts[3])
        let t = snap_of(parts[4])
        let t0 = snap_of(parts[5])
        if ((to_int(slice(a.st, 0, 2), true) & 0x08) != 0) {
            continue                    // still charging: the magick did not land
        }
        let kind = case == "arith" || case == "rush" ? case : "attack"
        if (rid == 0x1B0 && t0.v[1] >= units[5].max_mp) {
            continue                    // Critical: Recover MP with the MP full shows nothing
        }
        if (!key_exists(ctrl, kind)) {
            continue
        }
        cases++
        let c = ctrl?[kind] ?? (Snap(), Snap(), Snap())
        // what the control did to Lezalas, applied to this case's start
        let hit = c._2.v[0] - c._1.v[0]
        let want_hp = max(t0.v[0] - hit, 0)
        // (Rush's damage is random: its target's HP tells nothing)
        let differs = (a.v[0] != c._0.v[0] || (t.v[0] != want_hp && case != "rush") || t.v[1] - t0.v[1] != c._1.v[1] - c._2.v[1] ||
            t.v[2] != c._1.v[2] || t.v[3] - t0.v[3] != c._1.v[3] - c._2.v[3] || t.v[5] != c._1.v[5] ||
            t.v[6] != c._1.v[6] || st_core(t.st) != st_core(c._1.st))
        // the model: the same Lezalas, the same action
        var att = units[0]
        var tgt = units[5]
        tgt.brave = t0.v[3]
        tgt.hp = t0.v[0]
        tgt.mp = t0.v[1]
        tgt.items[SLOT_LEFT_SHIELD] = ITEM_NONE
        recompute_unit_w(tgt)
        tgt.c_ev = 0
        let n = rid - 0x1A6
        tgt.rsm_mask[n / 8] = uint8(0x80 >> (n % 8))
        tgt.reaction = rid
        let aid = case == "rush" ? 147 : (case == "arith" ? 16 : ATTACK_W)
        let f <- action_w(att, tgt, aid, side_of_w(att, tgt))
        let re <- reaction_w(att, tgt, f, case == "arith")
        let name = "{ability_name_w(rid)} ({case})"
        check("{name}: the game {differs ? "reacts" : "does not"}, the model {re.triggers ? "triggers" : "does not"} ({re.why})",
            differs == re.triggers)
    }
    check("{cases} reaction cases", cases >= 20)
    print("test_fftwotl_react: {total - failed} / {total} passed\n")
    return failed == 0 ? 0 : 1
}
