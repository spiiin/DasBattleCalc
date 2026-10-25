options gen2
options indenting = 4

// FFT (PSX) Attack: damage and hit chance (research/fft/notes.md,
// "Attack"). The damage is XA x YA by the weapon's type (Battle
// Mechanics Guide); XA's modifiers in order: critical, Attack UP / Martial
// Arts, Berserk, the target's Defense UP / Protect, the target's Charging
// / Sleep / Chicken / Frog, the zodiac. The hit chance multiplies the
// target's evades by the side it is hit from: front - class, shields,
// accessory, weapon (Weapon Guard); side - no class; back - the
// accessory. Seen in the game's forecast: sword PA x WP, the zodiac's
// integer steps on PA, the evades by side. The rest - the Guide.
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
let AB_ATTACK_UP = int(0x1D1)
let AB_DEFENSE_UP = int(0x1D2)
let AB_CONCENTRATE = int(0x1D5)
let AB_MARTIAL_ARTS = int(0x1D8)

let ST_CHARGING = 4
let ST_PERFORMING = 7
let ST_BERSERK = 20
let ST_CHICKEN = 21
let ST_FROG = 22
let ST_PROTECT = 26
let ST_SLEEP = 35
let ST_DONT_ACT = 37

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

def private item_index(item : int) : uint {
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
    evades : string
    notes : array<string>
}

// XA's modifiers after the critical (in the Guide's order)
def private modify_xa(xa0 : int; a, t : FftUnit; bare : bool) : int {
    var xa = xa0
    if (a.support == AB_ATTACK_UP) {
        xa = xa * 4 / 3
    }
    if (bare && a.support == AB_MARTIAL_ARTS) {
        xa = xa * 3 / 2
    }
    if (has_status(a, ST_BERSERK)) {
        xa = xa * 3 / 2
    }
    if (t.support == AB_DEFENSE_UP) {
        xa = xa * 2 / 3
    }
    if (has_status(t, ST_PROTECT)) {
        xa = xa * 2 / 3
    }
    if (has_status(t, ST_CHARGING) || has_status(t, ST_SLEEP) || has_status(t, ST_CHICKEN) || has_status(t, ST_FROG)) {
        xa = xa * 3 / 2
    }
    let z = zodiac_compat(a, t)
    if (z == 1) {
        xa = xa + xa / 4
    } elif (z == -1) {
        xa = xa - xa / 4
    } elif (z == 2) {
        xa = xa + xa / 2
    } elif (z == -2) {
        xa = xa / 2
    }
    return xa
}

def attack_forecast(a, t : FftUnit) : AttackForecast {
    var f = AttackForecast(weapon = unit_weapon(a))
    let w = f.weapon
    let bare = w.item == 0
    let br = a.pa * a.brave / 100
    var ya = w.wp
    if (bare) {
        f.formula = "PA x Br / 100 x PA"
        f.xa_min = br
        f.xa_max = br
        ya = a.pa
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
    f.damage_min = modify_xa(f.xa_min, a, t, bare) * ya
    f.damage_max = modify_xa(f.xa_max, a, t, bare) * ya
    f.crit_max = modify_xa(f.xa_max * 2 - 1, a, t, bare) * ya
    // the hit chance
    f.side = attack_side(a, t)
    let cev = class_evade(t)
    let sev = shield_evade(t)
    let aev = accessory_evade(t)
    let wev = t.reaction == AB_WEAPON_GUARD ? unit_weapon(t).w_ev : 0
    var evs : array<int>
    if (f.side == 0) {
        evs <- [cev, sev, aev, wev]
        f.evades = "front: class {cev}%, shield {sev}%, accessory {aev}%, weapon {wev}%"
    } elif (f.side == 1) {
        evs <- [sev, aev, wev]
        f.evades = "side: shield {sev}%, accessory {aev}%, weapon {wev}%"
    } else {
        evs <- [aev]
        f.evades = "back: accessory {aev}%"
    }
    let no_evade = (a.support == AB_CONCENTRATE || has_status(t, ST_CHARGING) || has_status(t, ST_PERFORMING)
        || has_status(t, ST_SLEEP) || has_status(t, ST_STOP) || has_status(t, ST_DONT_ACT) || has_status(t, ST_PETRIFY))
    // the product of the fractions, floored: 100 x 0.90 x 0.78 x 0.95 = 66
    var p = 1.0
    if (!no_evade) {
        for (ev in evs) {
            p *= float(100 - min(ev, 100)) / 100.0
        }
    } else {
        f.notes |> push("evades ignored (Concentrate or the target's status)")
    }
    f.hit = int(floor(p * 100.0 + 0.0001))
    f.notes |> push("zodiac: {ZODIAC_TEXT[zodiac_compat(a, t) + 2]}")
    if (a.support == AB_ATTACK_UP) {
        f.notes |> push("Attack UP: XA x 4 / 3")
    }
    if (bare && a.support == AB_MARTIAL_ARTS) {
        f.notes |> push("Martial Arts: XA x 3 / 2")
    }
    if (has_status(a, ST_BERSERK)) {
        f.notes |> push("Berserk: XA x 3 / 2")
    }
    if (t.support == AB_DEFENSE_UP) {
        f.notes |> push("target's Defense UP: XA x 2 / 3")
    }
    if (has_status(t, ST_PROTECT)) {
        f.notes |> push("target's Protect: XA x 2 / 3")
    }
    return <- f
}
