options gen2
options indenting = 4

// FFT (PSX) reactions of the target (research/fftwotl/formulas.md 5, as
// War of the Lions' reaction_w; research/fft/notes.md, "Reactions"). The
// reaction in effect: the record's reaction bits (+0x8B), the equipped id
// (+0x14) if its bit is on, else the first bit. Most fire with the
// target's Brave %, none while it is Berserk, Sleeping, Confused, Stopped,
// under Don't Act or Blood Suck. Seen in the game: Blade Grasp and Abandon
// in the hit chance (fft_attack), A Save (PA +1 at Brave 100) and Counter
// (Brave 100: Lezales struck back at Ramza - and missed, Ramza having
// turned to face him) set by the bits.
module fft_reactions shared public

require math
require fft_battle
require fft_attack
require fft_abilities

let RE_A_SAVE = int(0x1A6)
let RE_SUNKEN_STATE = int(0x1A9)
let RE_DRAGON_SPIRIT = int(0x1AB)
let RE_BRAVE_UP = int(0x1AD)
let RE_FACE_UP = int(0x1AE)
let RE_HP_RESTORE = int(0x1AF)
let RE_MP_RESTORE = int(0x1B0)
let RE_CRITICAL_QUICK = int(0x1B1)
let RE_MEATBONE_SLASH = int(0x1B2)
let RE_COUNTER_MAGIC = int(0x1B3)
let RE_COUNTER_TACKLE = int(0x1B4)
let RE_COUNTER_FLOOD = int(0x1B5)
let RE_ABSORB_MP = int(0x1B6)
let RE_COUNTER = int(0x1BA)
let RE_FINGER_GUARD = int(0x1C0)
let RE_CATCH = int(0x1C2)
let RE_HAMEDO = int(0x1C5)

let private ST_CONFUSION = 11
let private ST_BLOOD_SUCK = 13
let private ST_BERSERK_R = 20

struct FftReaction {
    id : int                        // the reaction in effect, 0 none
    name : string
    triggers : bool                 // the action calls it (before the Brave roll)
    chance : int                    // %, the Brave roll (100: no roll)
    why : string
    effect : string
    counter : bool                  // it strikes back: counter_* is that Attack
    counter_min : int
    counter_max : int
    counter_hit : int
}

def unit_reaction(t : FftUnit) : int {
    if (t.reaction != 0 && has_ability(t, t.reaction)) {
        return t.reaction
    }
    for (id in range(0x1A6, 0x1C6)) {
        if (has_ability(t, id)) {
            return id
        }
    }
    return 0
}

// the facing from a toward t (0 -y, 1 -x, 2 +y, 3 +x): a unit turns to
// its target when it acts
def facing_toward(a, t : FftUnit) : int {
    let dx = t.x - a.x
    let dy = t.y - a.y
    if (abs(dx) >= abs(dy)) {
        return dx > 0 ? 3 : 1
    }
    return dy > 0 ? 2 : 0
}

// The target t's reaction to a's action: ab (ab.id 0: Attack) dealing
// damage (its most) to t.
def reaction_to(a, t : FftUnit; ab : FftAbility; damage : int) : FftReaction {
    var r = FftReaction(id = unit_reaction(t))
    if (r.id == 0) {
        return r
    }
    r.name = ability_name(r.id)
    r.chance = clamp(t.brave, 0, 100)
    if (has_status(t, ST_BERSERK_R) || has_status(t, ST_DONT_ACT) || has_status(t, ST_SLEEP)
            || has_status(t, ST_CONFUSION) || has_status(t, ST_STOP) || has_status(t, ST_BLOOD_SUCK)
            || has_status(t, ST_DEAD) || has_status(t, ST_PETRIFY)) {
        r.why = "the target can not react (status)"
        return r
    }
    let attack = ab.id == 0
    let grasp = attack || grasped(ab)
    let hp_dmg = damage > 0
    let left = t.hp - damage
    let critical_after = hp_dmg && left > 0 && left * 5 < t.max_hp
    let dist = abs(a.x - t.x) + abs(a.y - t.y)
    let reach = max(unit_weapon(t).reach, 1)
    let rid = r.id
    if (rid == AB_WEAPON_GUARD || rid == AB_ABANDON || rid == AB_BLADE_GRASP || rid == AB_ARROW_GUARD) {
        r.triggers = grasp || rid == AB_ABANDON
        r.chance = 100
        r.effect = "in the hit chance"
        r.why = r.triggers ? "" : "not a physical blow"
    } elif (rid == RE_COUNTER || rid == RE_HAMEDO) {
        let first = rid == RE_HAMEDO
        r.triggers = first ? (attack || ab.kind == 5) : grasp
        if (!r.triggers) {
            r.why = first ? "only Attack / Charge" : "not a physical blow"
        } elif (dist > reach) {
            r.triggers = false
            r.why = "the attacker is out of its weapon's range ({dist} > {reach})"
        } else {
            // a has turned to t: the counter meets its front
            var turned = a
            turned.facing = facing_toward(a, t)
            let cf = attack_forecast(t, turned)
            r.counter = true
            r.counter_min = cf.damage_min
            r.counter_max = cf.damage_max
            r.counter_hit = cf.hit
            r.effect = first ? "attacks first, the action is cancelled" : "attacks back"
        }
    } elif (rid == RE_COUNTER_TACKLE) {
        r.triggers = ab.formula == 0x37
        r.effect = "Dash back"
        r.why = r.triggers ? "" : "only Dash / Throw Stone"
    } elif (rid == RE_DRAGON_SPIRIT || rid == RE_BRAVE_UP || rid == RE_SUNKEN_STATE) {
        r.triggers = grasp
        r.effect = rid == RE_DRAGON_SPIRIT ? "Reraise" : (rid == RE_SUNKEN_STATE ? "Transparent" : "Brave +3")
        r.why = r.triggers ? "" : "not a physical blow"
    } elif (rid >= RE_HP_RESTORE && rid <= RE_MEATBONE_SLASH) {
        r.triggers = critical_after
        r.why = r.triggers ? "" : "the target is not left in Critical (HP < 1/5)"
        if (rid == RE_MEATBONE_SLASH && r.triggers && dist <= reach) {
            r.counter = true
            r.counter_min = min(t.max_hp, 999)
            r.counter_max = r.counter_min
            r.counter_hit = 100
        }
        r.effect = (rid == RE_HP_RESTORE ? "full HP" : (rid == RE_CRITICAL_QUICK ? "a turn at once"
            : (rid == RE_MEATBONE_SLASH ? "strikes back for its max HP" : "full MP")))
    } elif (rid == RE_COUNTER_MAGIC || rid == RE_COUNTER_FLOOD || rid == RE_ABSORB_MP || rid == RE_FACE_UP) {
        let magic = !attack && ab.kind == 1 && (uint(ab.flags[2]) & 0x20u) != 0u
        r.triggers = (rid == RE_COUNTER_MAGIC ? (uint(ab.flags[3]) & 0x40u) != 0u
            : (rid == RE_COUNTER_FLOOD ? (uint(ab.flags[3]) & 0x80u) != 0u : magic))
        r.effect = (rid == RE_COUNTER_MAGIC ? "casts it back" : (rid == RE_ABSORB_MP ? "gains the MP spent"
            : (rid == RE_FACE_UP ? "Faith +3" : "Geomancy back")))
        r.why = r.triggers ? "" : "not a magic it answers"
    } elif (rid == RE_CATCH || rid == RE_FINGER_GUARD) {
        r.why = "not modelled (throws, Talk Skill)"
    } else {
        // A / MA / Speed Save, Caution, Regenerator, Auto Potion, Gilgame
        // Heart, MP Switch, Damage Split, Distribute: on HP damage
        r.triggers = hp_dmg
        r.effect = "after the damage"
        r.why = r.triggers ? "" : "no HP damage"
    }
    return r
}

// one line for the UI
def reaction_text(r : FftReaction) : string {
    if (r.id == 0) {
        return "no reaction"
    }
    if (!r.triggers) {
        let why = r.why != "" ? r.why : "-"
        return "{r.name}: not called - {why}"
    }
    let roll = r.chance < 100 ? "{r.chance}% (Brave)" : "always"
    if (r.counter) {
        let span = "{r.counter_min}..{r.counter_max}"
        let dmg = r.counter_min == r.counter_max ? "{r.counter_min}" : span
        return "{r.name}: {roll}, {r.effect}: {dmg} at {r.counter_hit}%"
    }
    return "{r.name}: {roll}, {r.effect}"
}
