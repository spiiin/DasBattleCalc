options gen2
options indenting = 4

// FFTA2 reactions (reaction2, ffta2_attack.das; the game's 0x020636DC)
// against real attacks: Luso attacks Sasarr with a reaction given to
// Sasarr (research/ffta2/reaction1.txt from exec_probe.lua): whether the
// attack lands, whether Sasarr counter-attacks and the counter's damage
// is within the model's spread (critical x2 included).
//   battlecalc tests/test_ffta2_reaction.das --state <ffta2_test_attack.State> --rom <FFTA2 (USA)>.zip
require gba_mem
require gui_common
require strings
require daslib/strings_boost
require daslib/fio
require ../scripts/games/ffta2/ffta2_battle.das
require ../scripts/games/ffta2/ffta2_attack.das

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

def find_unit(units : array<Unit2>; name : string) : int {
    for (i in range(length(units))) {
        if (units[i].name == name) {
            return i
        }
    }
    return -1
}

[export]
def main() : int {
    check("rom loads", gba_load_rom(gui_arg("--rom", "")) == "")
    check("state loads", gba_load_state(gui_arg("--state", "")) == "")
    var units : array<Unit2>
    check("battle read", read_battle2(units) == "")
    var m : Map2
    check("map read", read_map2(m))
    var att = units[find_unit(units, "Luso")]
    att.x = 9
    att.y = 8
    let atk = read_ability2(ATTACK_ABILITY)
    for (line in split(fread("research/ffta2/reaction1.txt"), "\n")) {
        let p <- split(line, " ")
        if (length(p) != 3 || starts_with(line, "#")) {
            continue
        }
        var tgt = units[find_unit(units, "Sasarr")]
        tgt.reaction = to_int(p[0])
        let sasarr = to_int(p[1])
        let luso = to_int(p[2])
        let r <- reaction2(att, tgt, atk, m)
        check("{r.name} triggers", r.triggers)
        check("{r.name}: the attack {sasarr == 77 ? "missed" : "landed"}, model evades = {r.evades}",
            r.evades == (sasarr == 77))
        check("{r.name}: counter {luso != 90}, model {r.counter}", r.counter == (luso != 90))
        if (r.counter) {
            let d = 90 - luso
            let lo = r.counter_fight.dmg_min
            let hi = r.counter_fight.dmg_max
            check("{r.name}: counter damage {d} in {lo}..{hi}", d >= lo && d <= hi)
        }
    }
    // no counter from out of reach: Sasarr two tiles away
    var far = units[find_unit(units, "Sasarr")]
    far.reaction = 829
    far.x = 11
    let r <- reaction2(att, far, atk, m)
    check("Counter out of reach: {r.why}", !r.triggers && !r.counter)
    // Fire has the counter flag too (+0x20 bit 29: 0x21085DAA), so by
    // the code Counter answers it next to the caster (not seen in the
    // game: Luso has no Fire); Evade Magick evades it
    let fire = read_ability2(63)
    var t2 = units[find_unit(units, "Sasarr")]
    t2.reaction = 829
    check("Counter answers Fire next to the caster", reaction2(att, t2, fire, m).counter)
    t2.reaction = 839
    let em <- reaction2(att, t2, fire, m)
    check("Evade Magick evades Fire", em.triggers && em.evades)
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}
