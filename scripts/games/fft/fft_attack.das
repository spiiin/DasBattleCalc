options gen2
options indenting = 4

// FFT (PSX) Attack: damage and hit chance (research/fft/notes.md,
// "Attack", "Modifiers and evades"). The damage is XA x YA by the
// weapon's type; XA's modifiers: Attack UP / Martial Arts, Berserk, the
// target's Defense UP / Protect, Charging / Sleep / Chicken / Frog, the
// zodiac (each step floored). The hit: base x the share past the
// target's evades (physical_pass). Seen in the game's forecasts: sword PA
// x WP, knife and bow (PA + Speed) / 2 x WP, knight sword PA x Br / 100 x
// WP, axe rand(1..PA) x WP, bare hands PA x (PA x Br / 100) with the
// modifiers on PA, Charge's K added to XA, the zodiac, the supports and
// statuses above, the evades by side. Not seen: the critical, elements.
module fft_attack shared public

require gba_mem
require math
require strings
require fft_battle

// the battle data in RAM (the executable's tables)
let ITEM_TABLE = 0x80062EB8u        // 12 B: +3 flags (0x80 weapon, 0x40 shield, 0x08 accessory), +4 index, +5 type
let WEAPON_TABLE = 0x80063AB8u      // 8 B: range, flags, formula, -, WP, W-Ev, element, status
let SHIELD_TABLE = 0x80063EB8u      // 2 B: physical, magic evade
let ACCESSORY_TABLE = 0x80063F58u   // 2 B: physical, magic evade
let JOB_CLASS_EV = 0x800610D1u      // the job table, 48 B a job: Move, Jump, C-Ev
let JOB_SIZE = 48u

let AB_WEAPON_GUARD = int(0x1BF)
let AB_ABANDON = int(0x1C1)
let AB_BLADE_GRASP = int(0x1C3)
let AB_ARROW_GUARD = int(0x1C4)
let AB_ATTACK_UP = int(0x1D1)
let AB_DEFENSE_UP = int(0x1D2)
let AB_CONCENTRATE = int(0x1D5)
let AB_MARTIAL_ARTS = int(0x1D8)

let ST_PERFORMING = 7
let ST_BERSERK = 20
let ST_CHICKEN = 21
let ST_FROG = 22
let ST_PROTECT = 26
let ST_SLEEP = 35
let ST_DONT_ACT = 37
let ST_DARKNESS = 10
let ST_DEFENDING = 6

// item types (+5)
let IT_KNIFE = 1
let IT_NINJA = 2
let IT_SWORD = 3
let IT_KNIGHT_SWORD = 4
let IT_KATANA = 5
let IT_AXE = 6
let IT_ROD = 7
let IT_STAFF = 8
let IT_FLAIL = 9
let IT_GUN = 10
let IT_CROSSBOW = 11
let IT_BOW = 12
let IT_INSTRUMENT = 13
let IT_BOOK = 14
let IT_SPEAR = 15
let IT_POLE = 16
let IT_BAG = 17
let IT_CLOTH = 18

struct FftWeapon {
    item : int                      // 0: bare hands
    name : string
    kind : int                      // the item type
    wp : int
    w_ev : int
    reach : int
    flags : int                     // 0x80 striking, 0x40 lunging, 0x20 direct, 0x10 arc
    element : int
}

def item_flags(item : int) : int {
    return item > 0 && item < 0xFF ? int(gba_read8(ITEM_TABLE + uint(item) * 12u + 3u)) : 0
}

def item_index(item : int) : uint {
    return gba_read8(ITEM_TABLE + uint(item) * 12u + 4u)
}

// the weapon in the right hand, else the left; bare hands: item 0
def unit_weapon(u : FftUnit) : FftWeapon {
    for (slot in [3, 5]) {
        let item = u.equip[slot]
        if ((item_flags(item) & 0x80) != 0) {
            let w = WEAPON_TABLE + item_index(item) * 8u
            return FftWeapon(item = item, name = item_name(item), kind = int(gba_read8(ITEM_TABLE + uint(item) * 12u + 5u)),
                wp = int(gba_read8(w + 4u)), w_ev = int(gba_read8(w + 5u)), reach = int(gba_read8(w)),
                flags = int(gba_read8(w + 1u)),
                element = int(gba_read8(w + 6u)))
        }
    }
    return FftWeapon(name = "bare hands", reach = 1, flags = 0x80)
}

def class_evade(u : FftUnit) : int {
    return int(gba_read8(JOB_CLASS_EV + uint(u.job_id) * JOB_SIZE))
}

// the physical evade of the shields (both shield slots)
def shield_evade(u : FftUnit) : int {
    var ev = 0
    for (slot in [4, 6]) {
        let item = u.equip[slot]
        if ((item_flags(item) & 0x40) != 0) {
            ev += int(gba_read8(SHIELD_TABLE + item_index(item) * 2u))
        }
    }
    return ev
}

def accessory_evade(u : FftUnit) : int {
    let item = u.equip[2]
    return (item_flags(item) & 0x08) != 0 ? int(gba_read8(ACCESSORY_TABLE + item_index(item) * 2u)) : 0
}

// the side of the target the attacker stands at: 0 front, 1 side, 2 back
// (the dominant axis; a diagonal counts as the side)
def attack_side(a, t : FftUnit) : int {
    let dx = a.x - t.x
    let dy = a.y - t.y
    if (abs(dx) == abs(dy)) {
        return dx == 0 ? 0 : 1
    }
    // facing: 0 +y, 1 -x, 2 -y, 3 +x
    let dir = abs(dx) > abs(dy) ? (dx > 0 ? 3 : 1) : (dy > 0 ? 0 : 2)
    let rel = (dir - t.facing) & 3
    return rel == 0 ? 0 : (rel == 2 ? 2 : 1)
}

// the zodiac: 0 neutral, 1 good, -1 bad, 2 best, -2 worst
def zodiac_compat(a, t : FftUnit) : int {
    if (a.zodiac >= 12 || t.zodiac >= 12) {
        return 0
    }
    let d = (t.zodiac - a.zodiac + 12) % 12
    if (d == 4 || d == 8) {
        return 1
    } elif (d == 3 || d == 9) {
        return -1
    } elif (d == 6) {
        let opposite = ((a.gender & 0x80) != 0 && (t.gender & 0x40) != 0) || ((a.gender & 0x40) != 0 && (t.gender & 0x80) != 0)
        return opposite ? 2 : -2
    }
    return 0
}

let ZODIAC_TEXT = fixed_array<string>("worst (XA / 2)", "bad (XA - XA / 4)", "neutral", "good (XA + XA / 4)",
    "best (XA + XA / 2)")

struct AttackForecast {
    weapon : FftWeapon
    formula : string
    xa_min : int                    // XA before the modifiers
    xa_max : int
    ya : int
    damage_min : int
    damage_max : int
    crit_max : int                  // the critical's best (XA + XA - 1)
    hit : int                       // %
    side : int
    healed : bool                   // the target absorbs the weapon's element
    evades : string
    notes : array<string>
}

// the zodiac on a factor (XA, MA): good + / 4, bad - / 4, best + / 2,
// worst / 2 (seen in the game's forecasts)
def zodiac_xa(xa : int; a, t : FftUnit) : int {
    let z = zodiac_compat(a, t)
    if (z == 1) {
        return xa + xa / 4
    } elif (z == -1) {
        return xa - xa / 4
    } elif (z == 2) {
        return xa + xa / 2
    } elif (z == -2) {
        return xa / 2
    }
    return xa
}

// XA's physical modifiers (in the Guide's order); bare: Martial Arts
// applies (bare hands, or not weapon-elemental); element: the attack's -
// a's Strengthen on it x 5 / 4 (Ice Brand: 6 -> 7, 91 in the game)
def physical_xa(xa0 : int; a, t : FftUnit; bare : bool; element : int = 0) : int {
    var xa = xa0
    if (element != 0 && has_element(a, EL_STRENGTHEN, element)) {
        xa = xa * 5 / 4
    }
    if (has_ability(a, AB_ATTACK_UP)) {
        xa = xa * 4 / 3
    }
    if (bare && has_ability(a, AB_MARTIAL_ARTS)) {
        xa = xa * 3 / 2
    }
    if (has_status(a, ST_BERSERK)) {
        xa = xa * 3 / 2
    }
    if (has_ability(t, AB_DEFENSE_UP)) {
        xa = xa * 2 / 3
    }
    if (has_status(t, ST_PROTECT)) {
        xa = xa * 2 / 3
    }
    if (has_status(t, ST_CHARGING) || has_status(t, ST_SLEEP) || has_status(t, ST_CHICKEN) || has_status(t, ST_FROG)) {
        xa = xa * 3 / 2
    }
    return zodiac_xa(xa, a, t)
}

// a hand's evade: its weapon's with Weapon Guard, else its shield's
// (weapon: slot 3 / 5, shield: slot 4 / 6)
def private hand_evade(t : FftUnit; weapon_slot, shield_slot : int; guard : bool) : int {
    let wi = t.equip[weapon_slot]
    if (guard && (item_flags(wi) & 0x80) != 0) {
        return int(gba_read8(WEAPON_TABLE + item_index(wi) * 8u + 5u))
    }
    let si = t.equip[shield_slot]
    return (item_flags(si) & 0x40) != 0 ? int(gba_read8(SHIELD_TABLE + item_index(si) * 2u)) : 0
}

// The share of hits past the target's evades (%), as the game takes it:
// the slots accessory, right hand, left hand, class in turn from 100,
// each step floored; by the side a stands at (side: no class; back: the
// accessory only); Darkness on a / Defending on t / t's Abandon double
// each evade (Abandon: 100 -> 56 -> 44 in the game).
// The game's forecasts against a Knight (Iron Sword with Weapon Guard 5,
// Mythril Shield 22, class 10): 100 -> 95 -> 74 -> 66; with Darkness or
// Defending 100 -> 90 -> 50 -> 40.
def physical_pass(a, t : FftUnit; var evades : string&) : int {
    let side = attack_side(a, t)
    let guard = has_ability(t, AB_WEAPON_GUARD)
    let aev = accessory_evade(t)
    let rev = hand_evade(t, 3, 4, guard)
    let lev = hand_evade(t, 5, 6, guard)
    let cev = class_evade(t)
    var evs : array<int>
    if (side == 0) {
        evs <- [aev, rev, lev, cev]
        evades = "front: accessory {aev}%, right hand {rev}%, left hand {lev}%, class {cev}%"
    } elif (side == 1) {
        evs <- [aev, rev, lev]
        evades = "side: accessory {aev}%, right hand {rev}%, left hand {lev}%"
    } else {
        evs <- [aev]
        evades = "back: accessory {aev}%"
    }
    let k = ((has_status(a, ST_DARKNESS) ? 2 : 1) * (has_status(t, ST_DEFENDING) ? 2 : 1)
        * (has_ability(t, AB_ABANDON) ? 2 : 1))
    if (k > 1) {
        evades += " (x {k})"
    }
    var share = 100
    for (ev in evs) {
        share = share * (100 - min(ev * k, 100)) / 100
    }
    return share
}

// the hit chance of a physical action with the base hit base (%): base x
// the pass share / 100 - Power Break 56 x 66 / 100 = 36, Head Break 58 ->
// 38, Shield Break 68 -> 44, Weapon Break 43 -> 28, Armor Break 53 -> 34;
// grasp: a blow the target's Blade Grasp answers (Attack, Charge, the
// abilities flagged so), its Arrow Guard too with a bow or crossbow - x
// (100 - its Brave) / 100 after the evades (the game: 66 -> 26 at Brave
// 60, 70 -> 28 without Weapon Guard, 70 -> 7 at Brave 90); evades: the
// text
// the target's affinity to an element on damage dmg (after XA x YA, before
// Faith): weak x 2, half / 2, absorb heals; cancel - the attack misses
// (cancelled = true). The game: Ice Brand 78 -> weak 156, half 39; Fire
// 56 -> weak 112 -> Faith 35, half 8, absorb +17, cancel 0%.
def element_damage(dmg : int; element : int; t : FftUnit; var healed : bool&; var cancelled : bool&) : int {
    healed = false
    cancelled = false
    if (element == 0) {
        return dmg
    }
    if (has_element(t, EL_CANCEL, element)) {
        cancelled = true
        return 0
    }
    var d = dmg
    if (has_element(t, EL_WEAK, element)) {
        d *= 2
    }
    if (has_element(t, EL_HALF, element)) {
        d /= 2
    }
    healed = has_element(t, EL_ABSORB, element)
    return d
}

def physical_hit(a, t : FftUnit; base : int; var evades : string&; grasp : bool = false) : int {
    let no_evade = (has_ability(a, AB_CONCENTRATE) || has_status(t, ST_CHARGING) || has_status(t, ST_PERFORMING)
        || has_status(t, ST_SLEEP) || has_status(t, ST_STOP) || has_status(t, ST_DONT_ACT) || has_status(t, ST_PETRIFY))
    if (no_evade) {
        evades = "evades ignored (Concentrate or the target's status)"
        return clamp(base, 0, 100)
    }
    var hit = clamp(base, 0, 100) * physical_pass(a, t, evades) / 100
    let w = unit_weapon(a)
    let arrow = w.kind == IT_BOW || w.kind == IT_CROSSBOW
    if (grasp && (has_ability(t, AB_BLADE_GRASP) || (arrow && has_ability(t, AB_ARROW_GUARD)))) {
        hit = hit * (100 - clamp(t.brave, 0, 100)) / 100
        evades += ", Blade Grasp / Arrow Guard x (100 - Brave {t.brave}) / 100"
    }
    return hit
}

// k: Charge's power, added to XA
def attack_forecast(a, t : FftUnit; k : int = 0) : AttackForecast {
    var f = AttackForecast(weapon = unit_weapon(a))
    let w = f.weapon
    let bare = w.item == 0
    let br = a.pa * a.brave / 100
    var ya = w.wp
    if (bare) {
        // the modifiers change the PA factor: Martial Arts 6 -> 9, x (6 x
        // 56 / 100 = 3) = 27 in the game (not 3 -> 4, x 6 = 24)
        f.formula = "PA x (PA x Br / 100)"
        f.xa_min = a.pa
        f.xa_max = a.pa
        ya = br
    } elif (w.kind == IT_KNIFE || w.kind == IT_NINJA || w.kind == IT_BOW) {
        f.formula = "(PA + Speed) / 2 x WP"
        f.xa_min = (a.pa + a.speed) / 2
        f.xa_max = f.xa_min
    } elif (w.kind == IT_KNIGHT_SWORD || w.kind == IT_KATANA) {
        f.formula = "PA x Br / 100 x WP"
        f.xa_min = br
        f.xa_max = br
    } elif (w.kind == IT_AXE || w.kind == IT_FLAIL || w.kind == IT_BAG) {
        f.formula = "rand(1..PA) x WP"
        f.xa_min = 1
        f.xa_max = a.pa
    } elif (w.kind == IT_STAFF || w.kind == IT_POLE) {
        f.formula = "MA x WP"
        f.xa_min = a.ma
        f.xa_max = a.ma
    } elif (w.kind == IT_GUN) {
        f.formula = "WP x WP"
        f.xa_min = w.wp
        f.xa_max = w.wp
    } elif (w.kind == IT_INSTRUMENT || w.kind == IT_BOOK || w.kind == IT_CLOTH) {
        f.formula = "(PA + MA) / 2 x WP"
        f.xa_min = (a.pa + a.ma) / 2
        f.xa_max = f.xa_min
    } else {
        // sword, rod, crossbow, spear
        f.formula = "PA x WP"
        f.xa_min = a.pa
        f.xa_max = a.pa
    }
    f.ya = ya
    f.xa_min += k
    f.xa_max += k
    let el = w.element
    let xmin = physical_xa(f.xa_min, a, t, bare, el)
    let xmax = physical_xa(f.xa_max, a, t, bare, el)
    var healed = false
    var cancelled = false
    f.damage_min = min(element_damage(xmin * ya, el, t, healed, cancelled), 999)
    f.damage_max = min(element_damage(xmax * ya, el, t, healed, cancelled), 999)
    // the critical: XA + rand(0..XA - 1) on the modified XA (the code's
    // order: the modifiers, then the critical; ~4-5%, not seen)
    f.crit_max = min(element_damage((xmax * 2 - 1) * ya, el, t, healed, cancelled), 999)
    f.healed = healed
    f.side = attack_side(a, t)
    f.hit = cancelled ? 0 : physical_hit(a, t, 100, f.evades, true)
    if (el != 0) {
        let how = healed ? ": absorbed" : (cancelled ? ": cancelled" : "")
        f.notes |> push("element {element_text(el)}{how}")
    }
    f.notes |> push("zodiac: {ZODIAC_TEXT[zodiac_compat(a, t) + 2]}")
    if (has_ability(a, AB_ATTACK_UP)) {
        f.notes |> push("Attack UP: XA x 4 / 3")
    }
    if (bare && has_ability(a, AB_MARTIAL_ARTS)) {
        f.notes |> push("Martial Arts: XA x 3 / 2")
    }
    if (has_status(a, ST_BERSERK)) {
        f.notes |> push("Berserk: XA x 3 / 2")
    }
    if (has_ability(t, AB_DEFENSE_UP)) {
        f.notes |> push("target's Defense UP: XA x 2 / 3")
    }
    if (has_status(t, ST_PROTECT)) {
        f.notes |> push("target's Protect: XA x 2 / 3")
    }
    return <- f
}
