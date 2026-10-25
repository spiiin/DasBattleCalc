options gen2
options indenting = 4

// FFT: The War of the Lions: the forecast of an action, step by step, by
// the formulas of research/fftwotl/formulas.md (the PSX battle code; WotL
// is its port). Checked against the game's own forecasts (Attack with
// every weapon kind, zodiac, statuses, evades, sides, elements; Fire with
// MA, Faith, Shell, elements): tests/test_fftwotl_forecast.das. The rest
// (other formulas, supports) follows the reference unchecked.
module fftwotl_attack shared public

require gba_mem
require math
require strings
require daslib/strings_boost
require fftwotl_data
require fftwotl_battle

enum SideW {
    Front
    Side
    Back
}

let SIDE_W_NAMES = fixed_array<string>("front", "side", "back")

// reaction abilities (0x1A6 + the bit of the record's mask)
let ID_VANISH = 425
let ID_DRAGONHEART = 427
let ID_BRAVERY_BOOST = 429
let ID_FAITH_BOOST = 430
let ID_CRIT_HP = 431
let ID_CRIT_QUICK = 433
let ID_BONECRUSHER = 434
let ID_MAGICK_COUNTER = 435
let ID_COUNTER_TACKLE = 436
let ID_NATURES_WRATH = 437
let ID_ABSORB_MP = 438
let ID_REFLECT_R = 440
let ID_COUNTER = 442
let ID_CUP_OF_LIFE = 444
let ID_PARRY = 447
let ID_EARPLUG = 448
let ID_REFLEXES = 449
let ID_STICKY_FINGERS = 450
let ID_SHIRAHADORI = 451
let ID_ARCHERS_BANE = 452
let ID_FIRST_STRIKE = 453
let ATTACK_W = 0                    // the Attack command (no ability id of its own)
let CRIT_PERCENT = 5                // formulas.md 2.3: 4 or 5 (open)

struct FightW {
    ability : AbilityW              // id 0: Attack
    name : string
    weapon : string
    formula : int
    unsupported : bool              // the formula is not modelled
    physical : bool
    healing : bool                  // the amount restores HP
    mp_effect : bool                // the amount is MP (damage or healing)
    element : int
    xa : int                        // the modified factor (after the modifiers)
    ya : int                        // the multiplier
    damage : int                    // the forecast (minus: absorbed, healed)
    dmg_min : int
    dmg_max : int
    mods : array<string>            // what changed the numbers, in order
    side : SideW
    zodiac : int                    // 0 neutral, 1 good, 2 bad, 3 best, 4 worst
    hit : int                       // the forecast, %
    hit_mods : array<string>
    crit : int                      // critical chance, %
    expected : float                // average damage per use (misses count 0)
    reach : int                     // horizontal range in tiles
    mp_cost : int
    ct : int                        // charge time (0 instant)
    note : string                   // what the action does besides damage
}

// ------------------------------------------------------------ helpers

var private ability_ids : table<string; int>
var private ability_ids_serial : uint = 0xFFFFFFFFu

// an ability by its WotL name (supports and reactions are checked by name:
// "Attack Boost", "Doublehand", ...), 0 when none
def ability_id_named(name : string) : int {
    if (ability_ids_serial != gba_state_serial()) {
        ability_ids_serial = gba_state_serial()
        ability_ids |> clear()
        for (id in range(1, ABILITY_COUNT_W)) {
            let n = ability_name_w(id)
            if (n != "" && !key_exists(ability_ids, n)) {
                ability_ids |> insert(n, id)
            }
        }
    }
    return ability_ids?[name] ?? 0
}

def has_named(u : UnitW; name : string) : bool {
    let id = ability_id_named(name)
    return id != 0 && has_ability_w(u, id)
}

// the side of the target the attacker stands on, by the target's facing:
// the largest of forward / sideways / behind wins, ties to the front
def side_of_w(att, tgt : UnitW) : SideW {
    let dirs = fixed_array<int2>(int2(0, -1), int2(-1, 0), int2(0, 1), int2(1, 0))
    let f = dirs[tgt.facing & 3]
    let dx = att.x - tgt.x
    let dy = att.y - tgt.y
    let fwd = dx * f.x + dy * f.y
    let lat = abs(dx * f.y - dy * f.x)
    if (fwd >= lat) {
        return SideW.Front
    }
    return -fwd > lat ? SideW.Back : SideW.Side
}

// zodiac compatibility (formulas.md 2.4): 0 neutral, 1 good, 2 bad, 3 best, 4 worst
def zodiac_w(att, tgt : UnitW) : int {
    if (att.zodiac_id > 11 || tgt.zodiac_id > 11) {
        return 0
    }
    var d = abs(att.zodiac_id - tgt.zodiac_id)
    if (d > 6) {
        d = 12 - d
    }
    if (d == 4) {
        return 1
    } elif (d == 3) {
        return 2
    } elif (d == 6) {
        let monster = (att.gender & 0x20) != 0 || (tgt.gender & 0x20) != 0
        if (monster) {
            return 2
        }
        return (att.gender & 0xC0) != (tgt.gender & 0xC0) ? 3 : 4
    }
    return 0
}

let ZODIAC_REL_NAMES = fixed_array<string>("neutral", "good", "bad", "best", "worst")

def private zodiac_apply(v, rel : int) : int {
    if (rel == 1) {
        return v + v / 4
    } elif (rel == 2) {
        return v - v / 4
    } elif (rel == 3) {
        return v + v / 2
    } elif (rel == 4) {
        return v - v / 2
    }
    return v
}

// v = v * num / den (truncated), noted when it changes the value
def private scale(var v : int&; num, den : int; why : string; var mods : array<string>) {
    let old = v
    v = v * num / den
    mods |> push("{why}: {old} -> {v}")
}

def private faith_of(u : UnitW) : int {
    if (has_status_w(u, ST_FAITH)) {
        return 100
    }
    return has_status_w(u, ST_INNOCENT) ? 0 : u.faith
}

// the weapon used: the right hand's, else the left's (0xFF none)
def weapon_of(u : UnitW) : ItemW {
    if (is_weapon_w(u.equip[SLOT_RIGHT])) {
        return u.equip[SLOT_RIGHT]
    }
    return is_weapon_w(u.equip[SLOT_LEFT]) ? u.equip[SLOT_LEFT] : ItemW(id = ITEM_NONE, name = "bare hands")
}

def is_undead_w(u : UnitW) : bool {
    return has_status_w(u, ST_UNDEAD)
}

// the target's affinity for an element mask: elements stack as the game
// checks them (cancel > absorb > half > weak); "" when neutral
def private apply_elements(var dmg : int&; elem : int; tgt : UnitW; var miss : bool&; var mods : array<string>) {
    if (elem == 0) {
        return
    }
    if ((tgt.cancel & elem) != 0) {
        miss = true
        mods |> push("{element_text(tgt.cancel & elem)}: nullified")
        return
    }
    let weak = (tgt.weak & elem) != 0 || ((elem & 0x80) != 0 && has_status_w(tgt, ST_OIL))
    if (weak) {
        scale(dmg, 2, 1, "weak to {element_text(elem)}", mods)
    }
    if ((tgt.half & elem) != 0) {
        scale(dmg, 1, 2, "halves {element_text(tgt.half & elem)}", mods)
    }
    if ((tgt.absorb & elem) != 0) {
        dmg = -dmg
        mods |> push("absorbs {element_text(tgt.absorb & elem)}: heals")
    }
}

// ------------------------------------------------------------ hit

// physical evasion (formulas.md 3.1): the target's evades that apply from
// this side, multiplied
def physical_hit(att, tgt : UnitW; side : SideW; base : int; var mods : array<string>; grasp : bool = true) : int {
    let w = weapon_of(att)
    if (w.kind == 10 || has_status_w(att, ST_TRANSPARENT)) {
        mods |> push(w.kind == 10 ? "a gun: not evaded" : "attacker invisible: not evaded")
        return base
    }
    if (has_status_w(tgt, ST_CHARGING) || has_status_w(tgt, ST_SLEEP) || has_status_w(tgt, ST_STOP) ||
            has_status_w(tgt, ST_DONT_ACT) || has_status_w(tgt, ST_CONFUSION)) {
        mods |> push("the target can not evade (status)")
        return base
    }
    var hit = base
    if (has_named(att, "Concentration")) {
        mods |> push("Concentration: evades ignored")
        return hit
    }
    var evs : array<int2>           // (evade %, 0 class / 1 shield / 2 weapon / 3 accessory)
    evs |> push(int2(tgt.a_ev, 3))
    let parry = has_ability_w(tgt, ID_PARRY)
    for (h in range(2)) {
        // slot order: right hand, left hand (weapon parry or shield)
        let ws = tgt.equip[h == 0 ? SLOT_RIGHT : SLOT_LEFT]
        if (parry && is_weapon_w(ws)) {
            evs |> push(int2(ws.w_ev, 2))
        } else {
            evs |> push(int2(tgt.s_ev[h == 0 ? 1 : 0], 1))
        }
    }
    evs |> push(int2(tgt.c_ev, 0))
    // checked in the game: Defending and the attacker's Blindness double
    // every evade (Defending 22% / 10% -> 44% hit, not half of 70%)
    var times = 1
    if (has_status_w(att, ST_DARKNESS)) {
        times *= 2
        mods |> push("attacker blind: evades x2")
    }
    if (has_status_w(tgt, ST_DEFENDING)) {
        times *= 2
        mods |> push("target defending: evades x2")
    }
    if (has_ability_w(tgt, ID_REFLEXES)) {
        times *= 2
        mods |> push("Reflexes: evades x2")
    }
    // checked in the game: the evades combine into one factor, truncated
    // at each step (78 x 90 / 100 = 70), then hit x factor / 100
    var factor = 100
    let names = fixed_array<string>("class", "shield", "weapon", "accessory")
    for (e in evs) {
        if (e.x == 0) {
            continue
        }
        if (side == SideW.Back && e.y != 3) {
            continue
        }
        if (side == SideW.Side && e.y == 0) {
            continue
        }
        let ev = min(e.x * times, 100)
        if (ev >= hit) {
            mods |> push("{names[e.y]} evade {ev}% >= hit: 0%")
            return 0
        }
        factor = factor * (100 - ev) / 100
        mods |> push("{names[e.y]} evade {ev}%")
    }
    // checked: Shirahadori (any physical blow it grasps, bows too) and
    // Archer's Bane (bows, crossbows) block with the target's Brave %, from
    // any side: Brave 58 -> 70% x 42 / 100 = 29
    let shooting = w.kind == 11 || w.kind == 12
    let grasps = has_ability_w(tgt, ID_SHIRAHADORI)
    if (grasp && (grasps || (shooting && has_ability_w(tgt, ID_ARCHERS_BANE)))) {
        factor = factor * (100 - tgt.brave) / 100
        let who = grasps ? "Shirahadori" : "Archer's Bane"
        mods |> push("{who}: x (100 - Brave {tgt.brave}) / 100")
    }
    return hit * factor / 100
}

// magic evasion: shields' and accessory's magic evade, from any side, for
// evadable abilities
def magic_hit(att, tgt : UnitW; ab : AbilityW; base : int; var mods : array<string>) : int {
    if ((ab.f4 & 0x02) == 0 || has_status_w(att, ST_TRANSPARENT)) {
        return base
    }
    // checked in the game (Fire): a charging / sleeping target does not
    // evade, a defending one evades twice as often
    if (has_status_w(tgt, ST_CHARGING) || has_status_w(tgt, ST_SLEEP) || has_status_w(tgt, ST_STOP) ||
            has_status_w(tgt, ST_DONT_ACT)) {
        mods |> push("the target can not evade (status)")
        return base
    }
    let times = has_status_w(tgt, ST_DEFENDING) ? 2 : 1
    var factor = 100
    for (ev in [tgt.sm_ev[0], tgt.sm_ev[1], tgt.am_ev]) {
        if (ev > 0) {
            let e = min(ev * times, 100)
            factor = factor * (100 - e) / 100
            mods |> push("magic evade {e}%")
        }
    }
    return base * factor / 100
}

// ------------------------------------------------------------ physical

// the weapon's XA / YA (formulas.md 2.1); dmg range of random weapons
def private weapon_xa(att : UnitW; w : ItemW; var xa, ya, xa_min, xa_max : int&; var what : string&) {
    let pa = att.pa
    let br = att.brave
    let pabr = max(1, pa * br / 100)
    ya = w.wp
    xa_min = -1
    if (w.id == ITEM_NONE) {
        xa = pa
        ya = pabr
        what = "bare hands: PA x [PA x Brave / 100]"
        return
    }
    let k = w.kind
    if (k == 1 || k == 2 || k == 12) {
        xa = (pa + att.sp) / 2
        what = "[(PA + Speed) / 2] x WP"
    } elif (k == 4 || k == 5) {
        xa = pabr
        what = "[PA x Brave / 100] x WP"
    } elif (k == 8 || k == 16) {
        xa = att.ma
        what = "MA x WP"
    } elif (k == 6 || k == 9 || k == 17) {
        // the forecast shows [(PA + 2) / 2] (checked: PA 6 -> 4)
        xa = (pa + 2) / 2
        xa_min = 1
        xa_max = pa
        what = "random 1..PA x WP (the forecast: [(PA + 2) / 2])"
    } elif (k == 10 || k == 32 || k == 33) {
        xa = w.wp
        what = k == 10 ? "WP x WP (gun)" : "WP x WP (thrown)"
    } elif (k == 13 || k == 14 || k == 18) {
        xa = (pa + att.ma) / 2
        what = "[(PA + MA) / 2] x WP"
    } elif (k == 35) {
        // Fell Sword (unverified exact form): the user's low Faith helps
        xa = pa * (100 - faith_of(att)) / 100
        what = "[PA x (100 - Faith) / 100] x WP (unverified)"
    } else {
        xa = pa
        what = "PA x WP"
    }
}

// elements the attacker strengthens: its equipment's (the game does not
// read the record's +0x7B for this: checked with Chaosbringer)
def strengthen_of(att : UnitW) : int {
    var m = 0
    for (k in range(7)) {
        m = m | att.equip[k].strengthen
    }
    return m
}

// the physical modifiers of XA (formulas.md 2.2), the attack's element
def private physical_mods(att, tgt : UnitW; var xa : int&; elem : int; bare : bool; jump : bool;
                          var mods : array<string>) {
    if (!jump) {
        if (elem != 0 && (strengthen_of(att) & elem) != 0) {
            scale(xa, 5, 4, "strengthens {element_text(elem)}", mods)
        }
        if (has_named(att, "Attack Boost")) {
            scale(xa, 4, 3, "Attack Boost", mods)
        }
        if (has_named(att, "Brawler") && bare) {
            scale(xa, 3, 2, "Brawler, bare hands", mods)
        }
        if (has_status_w(att, ST_BERSERK)) {
            scale(xa, 3, 2, "Berserk", mods)
        }
    }
    if (has_named(tgt, "Defense Boost")) {
        scale(xa, 2, 3, "target's Defense Boost", mods)
    }
    if (has_status_w(tgt, ST_PROTECT)) {
        scale(xa, 2, 3, "target's Protect", mods)
    }
    if (has_status_w(tgt, ST_CHARGING)) {
        scale(xa, 3, 2, "target charging", mods)
    }
    if (has_status_w(tgt, ST_SLEEP)) {
        scale(xa, 3, 2, "target asleep", mods)
    }
    if (has_status_w(tgt, ST_CHICKEN) || has_status_w(tgt, ST_FROG)) {
        scale(xa, 3, 2, "target Chicken / Toad", mods)
    }
    let rel = zodiac_w(att, tgt)
    if (rel != 0) {
        let old = xa
        xa = zodiac_apply(xa, rel)
        mods |> push("zodiac {ZODIAC_REL_NAMES[rel]}: {old} -> {xa}")
    }
}

// a weapon strike (Attack, Aim +k with k > 0)
def private weapon_strike(att, tgt : UnitW; var f : FightW; charge_k : int) {
    let w = weapon_of(att)
    f.weapon = w.name
    f.physical = true
    f.element = w.element
    f.reach = w.id == ITEM_NONE ? 1 : max(w.reach, 1)
    if (has_status_w(att, ST_FROG)) {
        // a Toad attacks bare: [PA x Brave / 100], nothing modifies it (checked: 3)
        f.weapon = "Toad"
        f.xa = att.pa * att.brave / 100
        f.ya = 1
        f.damage = f.xa
        f.dmg_min = f.damage
        f.dmg_max = f.damage
        f.mods |> push("Toad: [PA x Brave / 100] = {f.damage}")
        f.crit = CRIT_PERCENT
        f.hit = physical_hit(att, tgt, f.side, 100, f.hit_mods)
        return
    }
    var xa = 0
    var ya = 0
    var xa_min = 0
    var xa_max = 0
    var what = ""
    weapon_xa(att, w, xa, ya, xa_min, xa_max, what)
    f.mods |> push(what)
    if (has_named(att, "Doublehand") && w.id != ITEM_NONE && (w.wflags & 0x04) != 0 && w.kind != 10 &&
            !is_weapon_w(att.equip[SLOT_LEFT]) && att.items[SLOT_LEFT_SHIELD] == ITEM_NONE &&
            att.items[SLOT_RIGHT_SHIELD] == ITEM_NONE) {
        // checked: the stat, not WP (Mythril Sword: PA 6 -> 12, zodiac 15, x 7 = 105)
        scale(xa, 2, 1, "Doublehand", f.mods)
    }
    if (charge_k > 0) {
        let old = xa
        xa += charge_k
        f.mods |> push("Aim +{charge_k}: {old} -> {xa}")
    }
    if (w.kind != 32 && w.kind != 33) {
        physical_mods(att, tgt, xa, f.element, w.id == ITEM_NONE, false, f.mods)
    } else {
        f.mods |> push("a thrown weapon in hand: no modifiers (checked: Spark Bomb)")
    }
    f.xa = xa
    f.ya = ya
    var dmg = xa * ya
    f.mods |> push("damage = {xa} x {ya} = {dmg}")
    var miss = false
    apply_elements(dmg, f.element, tgt, miss, f.mods)
    f.damage = miss ? 0 : clamp(dmg, -999, 999)
    if (xa_min > 0) {
        // the random factor (axes, flails, bags): 1..PA through the same modifiers
        var lo = xa_min
        var hi = xa_max
        var dummy : array<string>
        physical_mods(att, tgt, lo, f.element, false, false, dummy)
        physical_mods(att, tgt, hi, f.element, false, false, dummy)
        f.dmg_min = min(lo * ya, 999)
        f.dmg_max = min(hi * ya, 999)
    } else {
        f.dmg_min = f.damage
        f.dmg_max = f.damage
    }
    f.crit = CRIT_PERCENT
    f.hit = miss ? 0 : physical_hit(att, tgt, f.side, 100, f.hit_mods)
}

// ------------------------------------------------------------ Throw, Jump

// the party's stock in battle: a count per item id (the first battle:
// Potion 5, Hi-Potion 2, ... Phoenix Down 2)
let INVENTORY_W = 0x092EABA0u

def stock_w(item : int) : int {
    return item > 0 && item < ITEM_COUNT_W ? int(gba_read8(INVENTORY_W + uint(item))) : 0
}

// the stocked item of an item kind with the best WP (Throw), ITEM_NONE
def best_thrown_w(kind : int) : int {
    var best = ITEM_NONE
    var best_wp = -1
    for (item in range(1, ITEM_COUNT_W)) {
        if (item != ITEM_NONE && stock_w(item) > 0) {
            let it = read_item_w(item)
            if (it.kind == kind && it.wp > best_wp) {
                best = item
                best_wp = it.wp
            }
        }
    }
    return best
}

// the unit has learned the ability (the bit of its slot in a job's set)
def knows_w(u : UnitW; ab_id : int) : bool {
    for (j in range(length(LEARN_JOB_NAMES))) {
        let ss = learn_skillset(u, j)
        if (ss <= 0) {
            continue
        }
        let s = read_skillset_w(ss)
        for (k in range(22)) {
            if (s.slots[k] == ab_id && learned_bit(u, j, k)) {
                return true
            }
        }
    }
    return false
}

// Jump's reach: the longest horizontal / vertical Jump learned (0x18A ..
// 0x195; at least the first of each)
def jump_reach_w(u : UnitW) : int2 {
    var r = int2(read_ability_w(394).jump_h, read_ability_w(400).jump_v)
    for (id in range(394, 406)) {
        if (knows_w(u, id)) {
            let a = read_ability_w(id)
            r = int2(max(r.x, a.jump_h), max(r.y, a.jump_v))
        }
    }
    return r
}

// Throw (formula 0x63): Speed' x the thrown item's WP - the target's
// modifiers and the zodiac only, the item's element, evaded as Attack
def private throw_w(att, tgt : UnitW; kind, item : int; var f : FightW) {
    f.formula = 0x63
    f.physical = true
    f.reach = att.move
    if (item == ITEM_NONE) {
        f.note = "none in stock ({KIND_W_NAMES[kind]})"
        f.mods |> push(f.note)
        return
    }
    let it = read_item_w(item)
    f.weapon = it.name
    f.element = it.element
    var xa = att.sp
    f.mods |> push("Speed x WP: {att.sp} x {it.wp} ({it.name}, the best of {stock_w(item)} in stock)")
    physical_mods(att, tgt, xa, it.element, false, true, f.mods)
    f.xa = xa
    f.ya = it.wp
    var dmg = xa * it.wp
    f.mods |> push("damage = {xa} x {it.wp} = {dmg}")
    var miss = false
    apply_elements(dmg, it.element, tgt, miss, f.mods)
    f.damage = miss ? 0 : clamp(dmg, -999, 999)
    f.dmg_min = f.damage
    f.dmg_max = f.damage
    f.hit = miss ? 0 : physical_hit(att, tgt, f.side, 100, f.hit_mods)
    f.note = "throws {it.name} (range = Move, unverified)"
}

// Throw of a given item (the tests: the forecasts were taken with the
// stock edited)
def throw_item_w(att, tgt : UnitW; item : int; side : SideW) : FightW {
    var f = FightW(side = side, zodiac = zodiac_w(att, tgt), name = "Throw")
    throw_w(att, tgt, read_item_w(item).kind, item, f)
    f.expected = expected_damage(f)
    return <- f
}

// Jump (formula 0x64): PA' (a polearm x 3 / 2) x WP, bare hands PA' x
// [PA x Brave / 100]; the target's modifiers and the zodiac only, no
// element, never evaded; charge [50 / Speed]
def private jump_w(att, tgt : UnitW; var f : FightW) {
    f.formula = 0x64
    f.physical = true
    let r = jump_reach_w(att)
    f.reach = r.x
    f.ct = 50 / max(att.raw[2], 1)
    let w = weapon_of(att)
    var xa = att.pa
    if (w.kind == 15) {
        scale(xa, 3, 2, "a polearm", f.mods)
    }
    physical_mods(att, tgt, xa, 0, false, true, f.mods)
    let ya = w.id == ITEM_NONE ? att.pa * att.brave / 100 : w.wp
    f.weapon = w.name
    f.xa = xa
    f.ya = ya
    f.damage = min(xa * ya, 999)
    f.dmg_min = f.damage
    f.dmg_max = f.damage
    f.mods |> push(w.id == ITEM_NONE ? "damage = {xa} x [PA x Brave / 100] {ya} = {f.damage}" :
        "damage = {xa} x WP {ya} = {f.damage}")
    f.hit = 100
    f.hit_mods |> push("Jump is never evaded")
    f.note = "jumps (horizontal {r.x}, vertical {r.y}; charge {f.ct} ticks)"
}

// ------------------------------------------------------------ the action

def action_w(att, tgt : UnitW; ab_id : int; side : SideW) : FightW {
    var f = FightW(side = side, zodiac = zodiac_w(att, tgt))
    f.hit_mods |> push("attacked from the {SIDE_W_NAMES[int(side)]}")
    if (ab_id == ATTACK_W) {
        f.name = "Attack"
        f.formula = 1
        weapon_strike(att, tgt, f, 0)
        f.expected = expected_damage(f)
        return <- f
    }
    let ab = read_ability_w(ab_id)
    f.ability = ab
    f.name = ab.name
    f.formula = ab.formula
    f.mp_cost = ab.mp
    f.ct = ab.ct
    f.reach = ab.reach
    f.element = ab.element
    if (ab.kind == AB_CHARGE) {
        // Aim +k: a bow / crossbow strike with XA + k
        f.ct = ab.ct
        weapon_strike(att, tgt, f, ab.x)
        f.expected = expected_damage(f)
        return <- f
    }
    if (ab.kind == AB_ITEM) {
        item_effect(att, tgt, read_item_w(ab.item), f)
        return <- f
    }
    if (ab.kind == AB_THROW) {
        throw_w(att, tgt, ab.throw_kind, best_thrown_w(ab.throw_kind), f)
        f.expected = expected_damage(f)
        return <- f
    }
    if (ab.kind == AB_JUMP) {
        f.name = "Jump"
        jump_w(att, tgt, f)
        f.expected = expected_damage(f)
        return <- f
    }
    if ((ab.f3 & 0x08) != 0 || (ab.f1 & 0x20) != 0) {
        f.reach = max(weapon_of(att).reach, 1)
    }
    let fa = faith_of(att) * faith_of(tgt)
    let x = ab.x
    let y = ab.y
    let fo = ab.formula
    if (fo == 0x08 || fo == 0x0C) {
        // magick damage / healing: MA x Y x Faith
        f.healing = fo == 0x0C
        var ma = att.ma
        f.mods |> push("MA x Y = {ma} x {y}")
        if (ab.element != 0 && (strengthen_of(att) & ab.element) != 0) {
            scale(ma, 5, 4, "strengthens {element_text(ab.element)}", f.mods)
        }
        if (has_named(att, "Arcane Strength")) {
            scale(ma, 4, 3, "Arcane Strength", f.mods)
        }
        if (!f.healing) {
            if (has_named(tgt, "Arcane Defense")) {
                scale(ma, 2, 3, "target's Arcane Defense", f.mods)
            }
            if (has_status_w(tgt, ST_SHELL)) {
                scale(ma, 2, 3, "target's Shell", f.mods)
            }
        }
        let rel = f.zodiac
        if (rel != 0) {
            let old = ma
            ma = zodiac_apply(ma, rel)
            f.mods |> push("zodiac {ZODIAC_REL_NAMES[rel]}: {old} -> {ma}")
        }
        f.xa = ma
        f.ya = y
        var dmg = ma * y
        var miss = false
        apply_elements(dmg, ab.element, tgt, miss, f.mods)
        let old = dmg
        dmg = dmg * fa / 10000
        f.mods |> push("Faith {faith_of(att)} x {faith_of(tgt)} / 10000: {old} -> {dmg}")
        if (f.healing && is_undead_w(tgt)) {
            f.healing = false
            f.mods |> push("the target is undead: healing hurts")
        }
        f.damage = miss ? 0 : clamp(dmg, -999, 999)
        f.dmg_min = f.damage
        f.dmg_max = f.damage
        f.hit = miss ? 0 : magic_hit(att, tgt, ab, 100, f.hit_mods)
    } elif (fo == 0x0A || fo == 0x0B || fo == 0x0D || fo == 0x0E || fo == 0x10 || fo == 0x0F || fo == 0x12 ||
            fo == 0x09) {
        // a magick's chance: (MA + X) x Faith (harmful ones through Shell / Arcane Defense)
        let harmful = fo == 0x0A || fo == 0x0E || fo == 0x10 || fo == 0x0F || fo == 0x09
        var ma = att.ma
        if (has_named(att, "Arcane Strength")) {
            scale(ma, 4, 3, "Arcane Strength", f.hit_mods)
        }
        if (harmful) {
            if (has_named(tgt, "Arcane Defense")) {
                scale(ma, 2, 3, "target's Arcane Defense", f.hit_mods)
            }
            if (has_status_w(tgt, ST_SHELL)) {
                scale(ma, 2, 3, "target's Shell", f.hit_mods)
            }
        }
        // zodiac scales both addends (checked: Umbra 5 + 250)
        ma = zodiac_apply(ma, f.zodiac)
        let xz = zodiac_apply(x, f.zodiac)
        var h = (ma + xz) * fa / 10000
        f.hit_mods |> push("(MA {ma} + {xz}) x Faith {faith_of(att)} x {faith_of(tgt)} / 10000 = {h}")
        if (fo == 0x0E && is_undead_w(tgt)) {
            // Death heals the undead in full, a healing: no magic evade
            // (checked: 40% = the chance, 134 HP)
            h = min(h, 100)
        } else {
            h = magic_hit(att, tgt, ab, min(h, 100), f.hit_mods)
        }
        f.hit = h
        if (fo == 0x0D) {
            f.healing = true
            f.damage = -((tgt.max_hp * y + 99) / 100)
            f.note = "revives with {y}% HP"
        } elif (fo == 0x09) {
            f.damage = (tgt.max_hp * y + 99) / 100
            f.note = "{y}% of the target's max HP"
        } elif (fo == 0x10) {
            // rounded up as Gravity (checked: 25% of 134 = 34)
            f.damage = (tgt.max_hp * y + 99) / 100
            f.note = "drains {y}% of max HP"
        } elif (fo == 0x0F) {
            f.mp_effect = true
            f.damage = (tgt.max_mp * y + 99) / 100        // checked: 33% of 17 = 6
            f.note = "drains {y}% of max MP"
        } elif (fo == 0x0E) {
            // KO: the forecast shows no damage (and 0% on Lezalas, as Toad -
            // the reason is not known); the undead are healed in full
            f.healing = is_undead_w(tgt)
            f.damage = f.healing ? -tgt.max_hp : 0
            f.note = f.healing ? "heals the undead in full" : "KO"
        } else {
            f.note = inflict_text(ab.inflict)
        }
        f.dmg_min = f.damage
        f.dmg_max = f.damage
    } elif (fo == 0x25 || fo == 0x2B || fo == 0x2C) {
        // Arts of War: a chance PA' (+ WP) + Y; X is the effect (a stat
        // down by X, X% of max MP) - Y is the constant of the chance
        // (Rend Helm 45 .. Rend Power 50: checked)
        var pa = att.pa
        if (has_named(att, "Attack Boost")) {
            scale(pa, 4, 3, "Attack Boost", f.hit_mods)
        }
        if (has_named(tgt, "Defense Boost")) {
            scale(pa, 2, 3, "target's Defense Boost", f.hit_mods)
        }
        if (has_status_w(tgt, ST_PROTECT)) {
            scale(pa, 2, 3, "target's Protect", f.hit_mods)
        }
        // the zodiac: Rend Power .. Rend MP scale PA and Y apart (checked:
        // 7 + 62 = 69); Rend Helm .. Weapon the sum PA + WP + Y (checked:
        // (6 + 7 + 45) x 5 / 4 = 72, x 1 / 2 = 29)
        var base = 0
        if (fo == 0x25) {
            let wp = weapon_of(att).wp
            let sum = pa + wp + y
            base = min(zodiac_apply(sum, f.zodiac), 100)
            f.hit_mods |> push("(PA {pa} + WP {wp} + {y}) = {sum}, zodiac: {base}")
        } else {
            pa = zodiac_apply(pa, f.zodiac)
            let x_z = zodiac_apply(y, f.zodiac)
            base = min(pa + x_z, 100)
            f.hit_mods |> push("PA {pa} + {x_z} = {base}")
        }
        f.hit = physical_hit(att, tgt, side, min(base, 100), f.hit_mods, (ab.f4 & 0x10) != 0)
        f.physical = true
        if (fo == 0x2C) {
            f.mp_effect = true
            f.damage = (tgt.max_mp * x + 99) / 100
            f.note = "MP damage {x}%"
        } elif (fo == 0x2B) {
            f.note = "a stat -{x}"
        } else {
            f.note = "breaks equipment"
        }
        f.dmg_min = f.damage
        f.dmg_max = f.damage
    } elif (fo == 0x2D || fo == 0x2F || fo == 0x30) {
        // Holy Sword (PA x (WP + Y)), Fell Sword drains (PA x WP): not evaded
        let w = weapon_of(att)
        f.weapon = w.name
        f.physical = true
        f.element = w.element
        var xa = att.pa
        let ya = fo == 0x2D ? w.wp + y : w.wp
        f.mods |> push(fo == 0x2D ? "PA x (WP + {y})" : "PA x WP")
        physical_mods(att, tgt, xa, f.element, w.id == ITEM_NONE, false, f.mods)
        f.xa = xa
        f.ya = ya
        var dmg = xa * ya
        f.mods |> push("damage = {xa} x {ya} = {dmg}")
        var miss = false
        apply_elements(dmg, f.element, tgt, miss, f.mods)
        f.damage = clamp(dmg, -999, 999)
        f.dmg_min = f.damage
        f.dmg_max = f.damage
        f.mp_effect = fo == 0x2F
        f.note = fo == 0x2D ? inflict_text(ab.inflict) : (fo == 0x2F ? "drains MP" : "drains HP")
        f.hit = miss ? 0 : 100
        f.hit_mods |> push("not evaded")
    } elif (fo == 0x31) {
        // PA' x [(PA + Y) / 2]: the modifiers and the zodiac on the first
        // PA only (checked: Aurablast 7 x 4 = 28, Protect 5 x 4 = 20)
        var xa = att.pa
        let ya = (att.pa + y) / 2
        f.mods |> push("PA' x [(PA + {y}) / 2]")
        physical_mods(att, tgt, xa, ab.element, true, false, f.mods)
        f.xa = xa
        f.ya = ya
        f.damage = min(xa * ya, 999)
        f.dmg_min = f.damage
        f.dmg_max = f.damage
        f.physical = true
        f.hit = physical_hit(att, tgt, side, 100, f.hit_mods, (ab.f4 & 0x10) != 0)
    } elif (fo == 0x37) {
        // Rush / Stone: PA' x random 1..Y; the forecast shows PA' x [(Y + 2) / 2]
        // (checked: Rush PA 6 -> 7 x 3 = 21, Stone 7 x 2)
        f.physical = true
        var xa = att.pa
        physical_mods(att, tgt, xa, ab.element, false, false, f.mods)
        f.xa = xa
        f.ya = (y + 2) / 2
        f.dmg_min = xa
        f.dmg_max = min(xa * y, 999)
        f.damage = min(xa * f.ya, 999)
        f.mods |> push("PA' x random 1..{y}: the forecast {xa} x {f.ya} = {f.damage}")
        f.hit = (ab.f4 & 0x02) != 0 ? physical_hit(att, tgt, side, 100, f.hit_mods, (ab.f4 & 0x10) != 0) : 100
    } elif (fo == 0x36 || fo == 0x39 || fo == 0x3A || fo == 0x3B) {
        let what = fo == 0x36 ? "PA" : (fo == 0x39 ? "Speed" : "Brave")
        let more = fo == 0x3B ? ", PA / MA / Speed +{y}" : ""
        f.note = "{what} +{fo == 0x3B ? x : y}{more}"
        f.hit = 100
    } elif (fo == 0x3C) {
        // [MaxHP / 5] x 2 to the target, [MaxHP / 5] from the user (checked on
        // the PSX game, same engine: 113 -> 44)
        f.healing = true
        f.damage = -(att.max_hp / 5 * 2)
        f.note = "costs the user {att.max_hp / 5} HP"
        f.dmg_min = f.damage
        f.dmg_max = f.damage
        f.hit = 100
    } elif (fo == 0x38) {
        f.note = inflict_text(ab.inflict)
        f.hit = 100
    } else {
        f.unsupported = true
        f.note = "formula 0x{fmt(":02x", fo)} is not modelled yet"
    }
    if (f.healing && f.damage > 0) {
        f.damage = -f.damage
        f.dmg_min = -f.dmg_min
        f.dmg_max = -f.dmg_max
    }
    f.expected = expected_damage(f)
    return <- f
}

// a Chemist's item (Items: X x 10 HP and so on)
def private item_effect(att, tgt : UnitW; it : ItemW; var f : FightW) {
    f.weapon = it.name
    f.reach = has_named(att, "Throw Items") ? 4 : 1
    f.hit = 100
    if (it.formula == 0x48) {
        f.damage = is_undead_w(tgt) ? it.x * 10 : -it.x * 10
        f.healing = !is_undead_w(tgt)
        f.mods |> push("HP {it.x} x 10")
    } elif (it.formula == 0x49) {
        f.mp_effect = true
        f.healing = true
        f.damage = -it.x * 10
        f.mods |> push("MP {it.x} x 10")
    } elif (it.formula == 0x4A) {
        f.healing = true
        f.damage = -(tgt.max_hp - tgt.hp)
        f.note = "full HP and MP"
    } elif (it.formula == 0x4B) {
        f.note = is_undead_w(tgt) ? "KO (undead)" : "revives"
    } else {
        f.note = inflict_text(it.inflict)
    }
    f.dmg_min = f.damage
    f.dmg_max = f.damage
}

// the average damage of one use: a hit, and the critical's +0..99% of XA
def expected_damage(f : FightW) : float {
    if (f.damage <= 0) {
        return float(f.damage) * float(f.hit) / 100.0
    }
    var d = float(f.dmg_min + f.dmg_max) * 0.5
    if (f.crit > 0 && f.xa > 0) {
        d += float(f.crit) / 100.0 * float(f.xa - 1) * 0.5 * float(f.ya)
    }
    return min(d, 999.0) * float(f.hit) / 100.0
}

// an action's name in the lists: Attack, Jump (the Jumps as one), the
// ability's
def action_name_w(id : int) : string {
    return id == ATTACK_W ? "Attack" : (id == 394 ? "Jump" : ability_name_w(id))
}

// the actions a unit can use from its skillsets (and Attack, id 0), for
// the Attack tab: normal abilities, items, Aim, Throw; the Jumps as one
// action (0x18A: the learned ones only set its reach)
def unit_actions(u : UnitW; all_known : bool) : array<int> {
    var res : array<int>
    res |> push(ATTACK_W)
    for (ss in [u.primary, u.secondary]) {
        if (ss == 0) {
            continue
        }
        let s <- read_skillset_w(ss)
        for (a0 in s.actions) {
            let a = a0 >= 394 && a0 < 406 ? 394 : a0
            if (find_index(res, a) < 0) {
                res |> push(a)
            }
        }
    }
    return <- res
}

// ------------------------------------------------------------ reactions

struct ReactionW {
    id : int                        // the reaction ability in effect (the record's mask), 0 none
    name : string
    triggers : bool                 // the action calls it (before the Brave roll)
    chance : int                    // %, the Brave roll (100: no roll)
    why : string
    effect : string
    counter : bool                  // it strikes back (Counter, First Strike, Bonecrusher)
    counter_fight : FightW
}

// a blow the reactions of grasp answer: Attack, Aim, Jump, Throw and the
// physical abilities flagged for Shirahadori
def private countergrasp(f : FightW) : bool {
    return (f.ability.id == 0 || f.ability.kind == AB_CHARGE || f.ability.kind == AB_JUMP ||
        f.ability.kind == AB_THROW || (f.ability.f4 & 0x10) != 0)
}

// The target's reaction to the action f of att (formulas.md 5). The
// reactions that change the hit chance (Shirahadori, Archer's Bane, Parry,
// Reflexes) are in the forecast already and checked; the others are the
// reference's rules, their Brave rolls are not checked.
def reaction_w(att, tgt : UnitW; f : FightW) : ReactionW {
    var r = ReactionW()
    // the equipped reaction if its bit is on, else the first bit of the mask
    if (tgt.reaction != 0 && has_ability_w(tgt, tgt.reaction)) {
        r.id = tgt.reaction
    } else {
        for (rid in range(422, 454)) {      // 0x1A6 .. 0x1C5
            if (r.id == 0 && has_ability_w(tgt, rid)) {
                r.id = rid
            }
        }
    }
    if (r.id == 0) {
        return <- r
    }
    r.name = ability_name_w(r.id)
    r.chance = tgt.brave
    if (has_status_w(tgt, ST_BERSERK) || has_status_w(tgt, ST_DONT_ACT) || has_status_w(tgt, ST_SLEEP) ||
            has_status_w(tgt, ST_CONFUSION) || has_status_w(tgt, ST_STOP) || has_status_w(tgt, 13) ||
            has_status_w(tgt, ST_DEAD) || has_status_w(tgt, ST_PETRIFY)) {
        r.why = "the target can not react (status)"
        return <- r
    }
    let hp_dmg = f.damage > 0 && !f.mp_effect && !f.healing
    let left = tgt.hp - f.damage
    let critical_after = hp_dmg && left > 0 && left * 5 < tgt.max_hp
    let dist = abs(att.x - tgt.x) + abs(att.y - tgt.y)
    let reach = max(weapon_of(tgt).reach, 1)
    let rid = r.id
    if (rid == ID_PARRY || rid == ID_REFLEXES || rid == ID_SHIRAHADORI || rid == ID_ARCHERS_BANE) {
        r.triggers = f.physical
        r.chance = 100
        r.effect = "in the hit chance"
    } elif (rid == ID_COUNTER || rid == ID_FIRST_STRIKE) {
        let first = rid == ID_FIRST_STRIKE
        r.triggers = first ? f.ability.id == 0 : countergrasp(f)
        if (!r.triggers) {
            r.why = first ? "only the Attack command" : "not a physical blow"
        } elif (dist > reach) {
            r.triggers = false
            r.why = "the attacker is out of its weapon's range ({dist} > {reach})"
        } else {
            r.counter = true
            r.counter_fight <- action_w(tgt, att, ATTACK_W, side_of_w(tgt, att))
            r.effect = first ? "attacks first, the action is cancelled" : "attacks back"
        }
    } elif (rid == ID_COUNTER_TACKLE) {
        r.triggers = f.formula == 0x37
        r.effect = "Rush back"
        r.why = r.triggers ? "" : "only Rush / Stone"
    } elif (rid == ID_DRAGONHEART || rid == ID_BRAVERY_BOOST || rid == ID_VANISH) {
        r.triggers = countergrasp(f)
        r.effect = rid == ID_DRAGONHEART ? "Reraise" : (rid == ID_VANISH ? "Invisible" : "Brave +3")
        r.why = r.triggers ? "" : "not a physical blow"
    } elif (rid >= ID_CRIT_HP && rid <= ID_BONECRUSHER) {
        r.triggers = critical_after
        r.why = r.triggers ? "" : "the target is not left in Critical (HP < 1/5)"
        if (rid == ID_BONECRUSHER && r.triggers && dist <= reach) {
            r.counter = true
            var cf = FightW(name = "Bonecrusher", physical = true, hit = 100)
            cf.damage = min(tgt.max_hp, 999)
            cf.dmg_min = cf.damage
            cf.dmg_max = cf.damage
            cf.mods |> push("damage = the reactor's max HP (unverified)")
            cf.expected = float(cf.damage)
            r.counter_fight <- cf
        }
        r.effect = (rid == ID_CRIT_HP ? "full HP" : (rid == ID_CRIT_QUICK ? "an immediate turn" :
            (rid == ID_BONECRUSHER ? "strikes back for its max HP" : "full MP")))
    } elif (rid == ID_MAGICK_COUNTER || rid == ID_NATURES_WRATH || rid == ID_ABSORB_MP || rid == ID_FAITH_BOOST ||
            rid == ID_REFLECT_R) {
        let magick = f.ability.id != 0 && f.ability.kind == AB_NORMAL && (f.ability.f3 & 0x20) != 0
        r.triggers = (rid == ID_MAGICK_COUNTER ? (f.ability.f4 & 0x40) != 0 : (rid == ID_NATURES_WRATH ?
            (f.ability.f4 & 0x80) != 0 : magick))
        r.effect = (rid == ID_MAGICK_COUNTER ? "casts it back" : (rid == ID_ABSORB_MP ? "gains the MP spent" :
            (rid == ID_FAITH_BOOST ? "Faith +3" : "the reaction's effect")))
        r.why = r.triggers ? "" : "not a magick it answers"
    } elif (rid == ID_STICKY_FINGERS || rid == ID_EARPLUG || rid == ID_CUP_OF_LIFE) {
        r.triggers = false
        r.why = "not modelled (throws, Speechcraft, healing)"
    } else {
        // Fury, Magick Boost, Adrenaline Rush, Vigilance, Regenerate,
        // Auto-Potion, Gil Snapper, Mana Shield, Soulbind: on HP damage
        r.triggers = hp_dmg
        r.effect = "after the damage"
        r.why = r.triggers ? "" : "no HP damage"
    }
    return <- r
}
