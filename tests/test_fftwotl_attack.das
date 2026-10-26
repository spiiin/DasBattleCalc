options gen2
options indenting = 4

// FFT: The War of the Lions: forecasts of the model on the first battle
// (printed with their steps; checks: hand-computed by formulas.md).
//   battlecalc tests/test_fftwotl_attack.das --state <fftwotl_test_battle1.ppst> [--print 1]
require gba_mem
require gui_common
require ../scripts/games/fftwotl/fftwotl_data.das
require ../scripts/games/fftwotl/fftwotl_battle.das
require ../scripts/games/fftwotl/fftwotl_attack.das
require ./test_check.das


def unit_named(units : array<UnitW>; name : string) : UnitW {
    for (u in units) {
        if (u.name == name) {
            return u
        }
    }
    return UnitW()
}

def show(f : FightW; att, tgt : UnitW) {
    print("{att.name} -> {tgt.name}: {f.name} ({f.weapon}) dmg {f.damage} [{f.dmg_min}..{f.dmg_max}] hit {f.hit}% {f.note}\n")
    for (m in f.mods) {
        print("    {m}\n")
    }
    for (m in f.hit_mods) {
        print("    hit: {m}\n")
    }
}

[export]
def main() : int {
    let err = gba_load_state(gui_arg("--state", ""))
    check("state loads ({err})", err == "")
    var units : array<UnitW>
    check("battle reads", read_battle_w(units) == "")
    let ramza = unit_named(units, "AAAAA")
    let lez = unit_named(units, "Lezalas")
    let wez = unit_named(units, "Wezlef")
    let agrias = unit_named(units, "Agrias")
    let printing = gui_arg("--print", "") != ""
    // Ramza (Capricorn, PA 6, Mythril Sword WP 7) -> Lezalas (Taurus):
    // trine = good: XA 6 -> 7, 7 x 7 = 49
    let f = action_w(ramza, lez, ATTACK_W, side_of_w(ramza, lez))
    if (printing) {
        show(f, ramza, lez)
    }
    check("Ramza -> Lezalas: zodiac good", zodiac_w(ramza, lez) == 1)
    check("Ramza -> Lezalas: 49 damage (got {f.damage})", f.damage == 49)
    for (t in units) {
        if (printing && t.team == TEAM_ENEMY && t.hp > 0) {
            show(action_w(agrias, t, ATTACK_W, side_of_w(agrias, t)), agrias, t)
        }
    }
    let acts <- unit_actions(agrias)
    for (a in acts) {
        let g = action_w(agrias, lez, a, side_of_w(agrias, lez))
        if (printing) {
            show(g, agrias, lez)
        }
    }
    check("Agrias has Holy Sword abilities", length(acts) > 3)
    // a real battle (PPSSPP): Lezalas with Counter (mask bit) and Brave 100,
    // Ramza's class evade 0 - Ramza hits for 49, the counter takes 48 of his HP
    var lc = lez
    lc.rsm_mask[2] = uint8(uint(lc.rsm_mask[2]) | 0x08u)
    lc.brave = 100
    var rc = ramza
    rc.c_ev = 0
    let hitf = action_w(rc, lc, ATTACK_W, side_of_w(rc, lc))
    let re = reaction_w(rc, lc, hitf)
    check("Counter: triggers, chance 100, counter 48 (got {re.name} {re.triggers} {re.chance} {re.counter_fight.damage})",
        re.name == "Counter" && re.triggers && re.chance == 100 && re.counter && re.counter_fight.damage == 48)
    let spell = action_w(rc, lc, 16, side_of_w(rc, lc))
    check("Counter does not answer Fire", !reaction_w(rc, lc, spell).triggers)
    return report()
}
