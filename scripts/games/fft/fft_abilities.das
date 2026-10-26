options gen2
options indenting = 4

// FFT (PSX) abilities: the tables in RAM (the same layout as War of the
// Lions', research/fftwotl/layouts.md) and the forecast of an ability by
// its formula (research/fftwotl/formulas.md, section 4; research/fft/
// notes.md, "Abilities" - what the game's forecast confirmed).
// - common data 8 B x 512 at 0x8005EBF0: JP, learn %, +3 low nibble the
//   type (1 action, 2 item, 3 throw, 4 jump, 5 charge, 7..9 R/S/M);
// - action data 14 B x 0x170 at +0x1000: range, area, vertical, 4 flag
//   bytes, element, formula, X, Y, inflict status, CT, MP;
// - item abilities' item at +0x2420, charge (CT, power) at +0x2454;
// - skillsets 25 B at 0x80064A94: high bits (3 B), 16 actions, 6 R/S/M;
// - Chemist items 3 B (formula, X, inflict) at 0x80063F98 for 0xF0..;
// - inflict statuses 6 B (flags, 5 status bytes) at 0x80063FC4.
// What a unit knows: its record +0x99, 3 B per job from Squire (2 B the
// actions in skillset order, 1 B R/S/M); Ramza's Guts uses Squire's.
module fft_abilities shared public

require gba_mem
require math
require strings
require daslib/strings_boost
require fft_battle
require fft_attack
require ../fftcore/fft_common.das public

let ABILITY_COMMON = 0x8005EBF0u
let ABILITY_ACTION = 0x8005FBF0u
let ABILITY_ITEM = 0x80061010u          // ABILITY_COMMON + 0x2420
let ABILITY_CHARGE = 0x80061044u        // ABILITY_COMMON + 0x2454
let ABILITY_THROW = 0x80061020u         // + 0x2430: the item type thrown (Shuriken 0x20, Knife 1, Sword 3, ...)
let ABILITY_JUMP = 0x8006102Cu          // + 0x243C: 2 B, horizontal / vertical reach
// the party's items: a count per item id (Potion 5 at 0xF0 in the first
// battle; Throw lists the stocked items of its types)
let INVENTORY = 0x800596E0u
let SKILLSET_TABLE = 0x80064A94u
let CHEMIST_ITEMS = 0x80063F98u
let INFLICT_TABLE = 0x80063FC4u
let LEARNED = 0x99u

let AB_MAGIC_ATTACK_UP = int(0x1D3)
let AB_MAGIC_DEFEND_UP = int(0x1D4)
let ST_SHELL = 27
let ST_UNDEAD = 3
let ST_FAITH = 32
let ST_INNOCENT = 33

struct FftAbility {
    id : int
    name : string
    kind : int                      // 1 action, 2 item, 3 throw, 4 jump, 5 charge
    reach : int                     // horizontal range
    area : int
    vertical : int
    flags : uint8[4]
    element : int
    formula : int
    x : int
    y : int
    inflict : int
    ct : int
    mp : int
    item : int                      // kind 2: the item used; kind 3: the item type thrown
    jump : int2                     // kind 4: horizontal, vertical reach
    charge : int                    // kind 5: the power added to XA
}

def read_ability(id : int) : FftAbility {
    var ab = FftAbility(id = id, name = ability_name(id))
    if (id <= 0 || id >= 0x200) {
        return ab
    }
    ab.kind = int(gba_read8(ABILITY_COMMON + uint(id) * 8u + 3u)) & 15
    if (id < 0x170) {
        let a = ABILITY_ACTION + uint(id) * 14u
        ab.reach = int(gba_read8(a))
        ab.area = int(gba_read8(a + 1u))
        ab.vertical = int(gba_read8(a + 2u))
        for (k in range(4)) {
            ab.flags[k] = uint8(gba_read8(a + 3u + uint(k)))
        }
        ab.element = int(gba_read8(a + 7u))
        ab.formula = int(gba_read8(a + 8u))
        ab.x = int(gba_read8(a + 9u))
        ab.y = int(gba_read8(a + 10u))
        ab.inflict = int(gba_read8(a + 11u))
        ab.ct = int(gba_read8(a + 12u))
        ab.mp = int(gba_read8(a + 13u))
    } elif (id < 0x17E) {
        ab.item = int(gba_read8(ABILITY_ITEM + uint(id - 0x170)))
        let it = CHEMIST_ITEMS + uint(ab.item - 0xF0) * 3u
        ab.formula = int(gba_read8(it))
        ab.x = int(gba_read8(it + 1u))
        ab.inflict = int(gba_read8(it + 2u))
        ab.reach = 1
    } elif (id >= 0x17E && id < 0x18A) {
        ab.item = int(gba_read8(ABILITY_THROW + uint(id - 0x17E)))
        ab.formula = 0x63
    } elif (id >= 0x18A && id < 0x196) {
        let j = ABILITY_JUMP + uint(id - 0x18A) * 2u
        ab.jump = int2(int(gba_read8(j)), int(gba_read8(j + 1u)))
        ab.formula = 0x64
    } elif (id >= 0x196 && id < 0x19E) {
        ab.ct = int(gba_read8(ABILITY_CHARGE + uint(id - 0x196) * 2u))
        ab.charge = int(gba_read8(ABILITY_CHARGE + uint(id - 0x196) * 2u + 1u))
        ab.formula = 1
    }
    return ab
}

// Blade Grasp answers it (action flags 4 bit 4; Charge as Attack)
def grasped(ab : FftAbility) : bool {
    return ab.kind == 5 || (uint(ab.flags[3]) & 0x10u) != 0u
}

def evadable(ab : FftAbility) : bool {
    return (uint(ab.flags[3]) & 0x02u) != 0u
}

// the stocked item of an item type with the best WP (Throw), 0 none
def best_thrown(item_type : int) : int {
    var best = 0
    var best_wp = -1
    for (item in range(1, 254)) {
        if (int(gba_read8(INVENTORY + uint(item))) > 0 && int(gba_read8(ITEM_TABLE_PSX + uint(item) * 12u + 5u)) == item_type) {
            let wp = int(gba_read8(WEAPON_TABLE + item_index(item) * 8u + 4u))
            if (wp > best_wp) {
                best = item
                best_wp = wp
            }
        }
    }
    return best
}

// Throw's and Jump's factor: Speed / PA with the target's Defense UP,
// Protect, Charging / Sleep / Chicken / Frog and the zodiac - not Attack
// UP, Martial Arts nor Berserk (the Guide; Jump's Protect: 28 in the
// game)
def private tj_factor(v0 : int; a, t : FftUnit) : int {
    var v = v0
    if (has_ability(t, AB_DEFENSE_UP)) {
        v = v * 2 / 3
    }
    if (has_status(t, ST_PROTECT)) {
        v = v * 2 / 3
    }
    if (has_status(t, ST_CHARGING) || has_status(t, ST_SLEEP) || has_status(t, ST_CHICKEN) || has_status(t, ST_FROG)) {
        v = v * 3 / 2
    }
    return zodiac_xa(v, a, t)
}

struct UnitAbility {
    id : int
    skillset : int
    learned : bool
}

// a skillset's action abilities (ids) in its order
def skillset_actions(ss : int) : array<int> {
    var res : array<int>
    if (ss <= 0 || ss >= 0xB0) {
        return <- res
    }
    let e = SKILLSET_TABLE + uint(ss) * 25u
    for (i in range(16)) {
        let lo = int(gba_read8(e + 3u + uint(i)))
        let hi = (int(gba_read8(e + uint(i / 8))) & (0x80 >> (i % 8))) != 0 ? 256 : 0
        if (lo != 0) {
            res |> push(lo + hi)
        }
    }
    return <- res
}

// the job slot of a skillset's learned bits: the generic skillsets 5
// (Squire) .. 0x18 (Mime), Ramza's Guts (0x19..0x1B) Squire's; -1 the
// special skillsets (all known)
def private learned_slot(ss : int) : int {
    if (ss >= 5 && ss <= 0x18) {
        return ss - 5
    }
    return ss >= 0x19 && ss <= 0x1B ? 0 : -1
}

// the unit's primary and secondary skillsets' actions, learned or not
// ------------------------------------------------------------ Math Skill

// Math Skill's abilities: 414..417 the conditions CT, Level, Exp, Height;
// 418..421 the numbers Prime Number, 5, 4, 3
let MATH_FIRST = 414
let MATH_END = 422
let MATH_CONDITIONS = fixed_array<string>("CT", "Level", "Exp", "Height")
let MATH_NUMBERS = fixed_array<string>("Prime Number", "5", "4", "3")
// the skillsets whose learned spells Math Skill casts: White, Black,
// Time, Yin Yang Magic (the game listed the learned Black Magic)
let MATH_SKILLSETS = fixed_array<int>(10, 11, 12, 16)

// a unit's value for a condition, -1 none. The game (battle 2): CT at
// most 100 and the unit taking its turn 100 (CT 102 units were hit by
// "5", not by "3"); Height the tile's whole height (2.5 matches no
// number)
def math_value(u : FftUnit; cond : int; m : FftMap) : int {
    if (cond == 0) {
        return u.active ? 100 : min(u.ct, 100)
    } elif (cond == 1) {
        return u.level
    } elif (cond == 2) {
        return u.exp
    }
    if (u.x < 0 || u.y < 0 || u.x >= m.w || u.y >= m.h) {
        return -1
    }
    let i = u.y * m.w + u.x
    let h2 = u.upper && m.upper[i] >= 0 ? m.upper[i] : m.height[i]
    return (h2 & 1) != 0 ? -1 : h2 / 2
}

// the number picks the value: 0 a prime, 1..3 divisible by 5, 4, 3
def math_matches(v, number : int) : bool {
    if (v < 0) {
        return false
    }
    if (number == 0) {
        if (v < 2) {
            return false
        }
        for (d in range(2, v)) {
            if (d * d > v) {
                break
            }
            if (v % d == 0) {
                return false
            }
        }
        return true
    }
    let k = fixed_array<int>(0, 5, 4, 3)
    return v % k[number] == 0
}

// the spells a unit can cast by Math Skill: the learned ones of
// MATH_SKILLSETS, whichever its skillsets are
def math_spells(u : FftUnit) : array<int> {
    var res : array<int>
    for (ss in MATH_SKILLSETS) {
        let slot = learned_slot(ss)
        let ids <- skillset_actions(ss)
        for (i in range(length(ids))) {
            let b = gba_read8(u.record + LEARNED + uint(slot * 3 + i / 8))
            if ((b & (0x80u >> uint(i % 8))) != 0u) {
                res |> push(ids[i])
            }
        }
    }
    return <- res
}

def unit_abilities(u : FftUnit) : array<UnitAbility> {
    var res : array<UnitAbility>
    for (ss in [u.primary, u.secondary]) {
        let slot = learned_slot(ss)
        let ids <- skillset_actions(ss)
        for (i in range(length(ids))) {
            var learned = true
            if (slot >= 0) {
                let b = gba_read8(u.record + LEARNED + uint(slot * 3 + i / 8))
                learned = (b & (0x80u >> uint(i % 8))) != 0u
            }
            res |> push(UnitAbility(id = ids[i], skillset = ss, learned = learned))
        }
    }
    return <- res
}

// the statuses an ability inflicts, as text ("" none)
def inflict_text(n : int) : string {
    if (n <= 0 || n >= 128) {
        return ""
    }
    let e = INFLICT_TABLE + uint(n) * 6u
    let fl = int(gba_read8(e))
    var names : array<string>
    for (k in range(40)) {
        if ((int(gba_read8(e + 1u + uint(k / 8))) & (0x80 >> (k % 8))) != 0) {
            names |> push(STATUS_NAMES[k])
        }
    }
    let how = (fl & 0x10) != 0 ? "cancels " : ((fl & 0x40) != 0 ? "one of " : "")
    return length(names) > 0 ? "{how}{join(names, ", ")}" : ""
}

// an inflict entry adds the status (not "cancels")
def inflicts(n, status : int) : bool {
    if (n <= 0 || n >= 128) {
        return false
    }
    let e = INFLICT_TABLE + uint(n) * 6u
    return (gba_read8(e) & 0x10u) == 0u && (gba_read8(e + 1u + uint(status / 8)) & (0x80u >> uint(status % 8))) != 0u
}

// an immortal unit: record +0x05 bit 0x04 (every unit of the prologue at
// Orbonne, Delita at Gariland) - it can not be KO'd nor turned into a
// frog
def is_immortal(u : FftUnit) : bool {
    return (u.flags & 0x04) != 0
}

struct AbilityForecast {
    known : bool                    // the formula is modelled
    effect : string                 // "damage", "heal", "status", "PA +1", ...
    amount_min : int                // damage (heal: the amount healed)
    amount_max : int
    heal : bool
    hit : int                       // %
    formula : string
    notes : array<string>
}

// Faith of both, / 10000 (Faith status 100, Innocent 0)
def private faith_of(u : FftUnit) : int {
    return has_status(u, ST_INNOCENT) ? 0 : (has_status(u, ST_FAITH) ? 100 : u.faith)
}

def private with_faith(v : int; a, t : FftUnit) : int {
    return v * faith_of(a) * faith_of(t) / 10000
}

// magic's MA: Magic AttackUP, the target's Magic DefendUP and Shell
// (harmful only), the zodiac
def private magic_ma(a, t : FftUnit; harmful : bool) : int {
    return magic_ma_base(a, t, harmful, a.ma)
}

def private magic_ma_base(a, t : FftUnit; harmful : bool; ma0 : int) : int {
    var ma = ma0
    if (has_ability(a, AB_MAGIC_ATTACK_UP)) {
        ma = ma * 4 / 3
    }
    if (harmful && has_ability(t, AB_MAGIC_DEFEND_UP)) {
        ma = ma * 2 / 3
    }
    if (harmful && has_status(t, ST_SHELL)) {
        ma = ma * 2 / 3
    }
    return zodiac_xa(ma, a, t)
}

// the target's magic evade (accessory, shields: their second byte), from
// any side: the pass share from 100 step by step, then base x it / 100
// (Slow 59 x 95 / 100 = 56, Poison 52 -> 49 against a Mythril Shield 5)
def magic_hit(t : FftUnit; base : int) : int {
    var share = 100
    let acc = t.equip[2]
    if ((item_flags(acc) & 0x08) != 0) {
        share = share * (100 - int(gba_read8(ACCESSORY_TABLE + item_index(acc) * 2u + 1u))) / 100
    }
    for (slot in [4, 6]) {
        let item = t.equip[slot]
        if ((item_flags(item) & 0x40) != 0) {
            share = share * (100 - int(gba_read8(SHIELD_TABLE + item_index(item) * 2u + 1u))) / 100
        }
    }
    return clamp(base, 0, 100) * share / 100
}

def ability_forecast(a, t : FftUnit; ab : FftAbility) : AbilityForecast {
    var f = AbilityForecast(known = true, hit = 100)
    var ev = ""
    let fo = ab.formula
    let st = inflict_text(ab.inflict)
    if (fo == 0x63) {
        // Throw: Speed' x the thrown item's WP, evaded as Attack (the
        // game: Speed 6 x Broad Sword 4 = 24, Defender 16 = 96, Shuriken
        // 4 = 24, Magic Shuriken 7 = 42; 66%)
        let item = best_thrown(ab.item)
        if (item == 0) {
            f.effect = "none in stock"
            f.hit = 0
        } else {
            let wi = WEAPON_TABLE + item_index(item) * 8u
            let wp = int(gba_read8(wi + 4u))
            let el = int(gba_read8(wi + 6u))
            var healed = false
            var cancelled = false
            f.effect = "damage ({item_name(item)} x {gba_read8(INVENTORY + uint(item))})"
            f.amount_min = min(element_damage(tj_factor(a.speed, a, t) * wp, el, t, healed, cancelled), 999)
            f.amount_max = f.amount_min
            f.heal = healed
            f.formula = "Speed x WP {wp} ({item_name(item)}, the best in stock)"
            f.hit = cancelled ? 0 : physical_hit(a, t, 100, ev, true)
            f.notes |> push("evades, {ev}")
        }
    } elif (fo == 0x64) {
        // Jump: PA' (a spear x 3 / 2) x WP, bare PA' x (PA x Br / 100);
        // never evaded (the game: sword 42, Spear 9 x 9 = 81, bare 6 x 3
        // = 18, Protect 28; 100%)
        let w = unit_weapon(a)
        var pa = a.pa
        if (w.kind == IT_SPEAR) {
            pa = pa * 3 / 2
        }
        pa = tj_factor(pa, a, t)
        let ya = w.item == 0 ? a.pa * a.brave / 100 : w.wp
        f.effect = "damage"
        f.amount_min = min(pa * ya, 999)
        f.amount_max = f.amount_min
        f.formula = w.item == 0 ? "PA x (PA x Br / 100)" : (w.kind == IT_SPEAR ? "PA x 3 / 2 x WP" : "PA x WP")
    } elif (ab.kind == 5) {
        // Charge: Attack with the power added to XA
        let at = attack_forecast(a, t, ab.charge)
        f.effect = "damage"
        f.amount_min = at.damage_min
        f.amount_max = at.damage_max
        f.hit = at.hit
        f.formula = "Attack, XA + {ab.charge} ({at.formula})"
        f.notes |> push("evades, {at.evades}")
    } elif (fo == 0x08) {
        // Strengthen x 5 / 4 on MA, the elements before Faith (the game:
        // Fire 4 x 14 = 56, weak 112 -> 35, Strengthen 5 x 14 -> 22)
        var ma = magic_ma(a, t, true)
        if (ab.element != 0 && has_element(a, EL_STRENGTHEN, ab.element)) {
            ma = magic_ma_base(a, t, true, a.ma * 5 / 4)
        }
        var healed = false
        var cancelled = false
        let raw = element_damage(ma * ab.y, ab.element, t, healed, cancelled)
        f.effect = healed ? "absorbed (heal)" : "damage"
        f.heal = healed
        f.amount_min = min(with_faith(raw, a, t), 999)
        f.amount_max = f.amount_min
        f.formula = "MA x {ab.y} x Faith x Faith"
        f.hit = cancelled ? 0 : (evadable(ab) ? magic_hit(t, 100) : 100)
        if (ab.element != 0) {
            f.notes |> push("element {element_text(ab.element)}")
        }
    } elif (fo == 0x0A || fo == 0x0B) {
        let harmful = fo == 0x0A
        let ma = magic_ma(a, t, harmful)
        f.effect = st != "" ? st : "status"
        f.hit = min(with_faith(ma + zodiac_xa(ab.x, a, t), a, t), 100)
        if (harmful) {
            f.hit = magic_hit(t, f.hit)
        }
        f.formula = "(MA + {ab.x}) x Faith x Faith"
    } elif (fo == 0x0C) {
        var ma = a.ma
        if (has_ability(a, AB_MAGIC_ATTACK_UP)) {
            ma = ma * 4 / 3
        }
        f.effect = has_status(t, ST_UNDEAD) ? "damage (undead)" : "heal"
        f.heal = !has_status(t, ST_UNDEAD)
        f.amount_min = min(with_faith(zodiac_xa(ma, a, t) * ab.y, a, t), 999)
        f.amount_max = f.amount_min
        f.formula = "MA x {ab.y} x Faith x Faith"
    } elif (fo == 0x0D) {
        f.effect = "revive"
        f.heal = true
        f.amount_min = (t.max_hp * ab.y + 99) / 100
        f.amount_max = f.amount_min
        f.hit = min(with_faith(magic_ma(a, t, false) + zodiac_xa(ab.x, a, t), a, t), 100)
        f.formula = "{ab.y}% of max HP; hit (MA + {ab.x}) x Faith x Faith"
    } elif (fo == 0x0E) {
        f.effect = "Dead"
        f.hit = magic_hit(t, min(with_faith(magic_ma(a, t, true) + zodiac_xa(ab.x, a, t), a, t), 100))
        f.formula = "(MA + {ab.x}) x Faith x Faith"
    } elif (fo == 0x25 || fo == 0x2B || fo == 0x2C) {
        let w = unit_weapon(a)
        let pa = physical_xa(a.pa, a, t, false)
        var base = pa + zodiac_xa(ab.y, a, t)
        if (fo == 0x25) {
            base += zodiac_xa(w.wp, a, t)
            f.effect = "break equipment"
            f.formula = "PA + WP + {ab.y}"
        } elif (fo == 0x2B) {
            f.effect = "{ab.name}: -{ab.x}"
            f.formula = "PA + {ab.y}"
        } else {
            f.effect = "MP -50%"
            f.amount_min = (t.max_mp + 1) / 2
            f.amount_max = f.amount_min
            f.formula = "PA + {ab.y}"
        }
        f.hit = physical_hit(a, t, min(base, 100), ev, grasped(ab))
        f.notes |> push("evades, {ev}")
    } elif (fo == 0x2D) {
        let w = unit_weapon(a)
        let pa = physical_xa(a.pa, a, t, false, w.element)
        var healed = false
        var cancelled = false
        f.effect = "damage"
        f.amount_min = min(element_damage(pa * (w.wp + ab.y), w.element, t, healed, cancelled), 999)
        f.heal = healed
        if (cancelled) {
            f.hit = 0
        }
        f.amount_max = f.amount_min
        f.formula = "PA x (WP + {ab.y})"
        if (st != "") {
            f.notes |> push("may add {st}")
        }
    } elif (fo == 0x2F || fo == 0x30) {
        let w = unit_weapon(a)
        let pa = physical_xa(a.pa, a, t, false)
        f.effect = fo == 0x30 ? "absorb HP" : "absorb MP"
        f.amount_min = min(pa * w.wp, 999)
        f.amount_max = f.amount_min
        f.formula = "PA x WP"
    } elif (fo == 0x31) {
        let pa = physical_xa(a.pa, a, t, true)
        f.effect = "damage"
        f.amount_min = min((a.pa + ab.y) / 2 * pa, 999)
        f.amount_max = f.amount_min
        f.formula = "(PA + {ab.y}) / 2 x PA"
    } elif (fo == 0x34) {
        f.effect = "heal (MP + half)"
        f.heal = true
        f.amount_min = a.pa * ab.y
        f.amount_max = f.amount_min
        f.formula = "PA x {ab.y} HP, PA x {ab.y} / 2 MP"
    } elif (fo == 0x36) {
        f.effect = "PA +{ab.y}"
        f.formula = "PA + {ab.y}"
    } elif (fo == 0x37) {
        // the game's forecast shows one roll: 18 = PA 6 x 3 of Dash
        let pa = physical_xa(a.pa, a, t, true)
        f.effect = "damage"
        f.amount_min = pa
        f.amount_max = min(pa * max(ab.y, 1), 999)
        f.formula = "PA x rand(1..{ab.y})"
        if (evadable(ab)) {
            f.hit = physical_hit(a, t, 100, ev, grasped(ab))
            f.notes |> push("evades, {ev}")
        }
    } elif (fo == 0x38) {
        f.effect = st != "" ? st : "cure"
    } elif (fo == 0x39) {
        f.effect = "Speed +{ab.y}"
    } elif (fo == 0x3A) {
        f.effect = "Brave +{ab.y}"
    } elif (fo == 0x3B) {
        f.effect = "Brave +{ab.x}, PA / MA / Speed +{ab.y}"
    } elif (fo == 0x3C) {
        f.effect = "heal"
        f.heal = true
        // the game: max HP 113 -> 44, 200 -> 80, 100 -> 40 (any target)
        f.amount_min = a.max_hp / 5 * 2
        f.amount_max = f.amount_min
        f.formula = "caster's max HP / 5 x 2 (the caster loses max HP / 5: {a.max_hp / 5})"
    } elif (fo == 0x48) {
        f.effect = has_status(t, ST_UNDEAD) ? "damage (undead)" : "heal"
        f.heal = !has_status(t, ST_UNDEAD)
        f.amount_min = ab.x * 10
        f.amount_max = f.amount_min
        f.formula = "{ab.x} x 10 HP"
    } elif (fo == 0x49) {
        f.effect = "MP heal"
        f.heal = true
        f.amount_min = ab.x * 10
        f.amount_max = f.amount_min
        f.formula = "{ab.x} x 10 MP"
    } elif (fo == 0x4A) {
        f.effect = "full HP and MP"
        f.heal = true
        f.amount_min = t.max_hp - t.hp
        f.amount_max = f.amount_min
    } elif (fo == 0x4B) {
        f.effect = has_status(t, ST_UNDEAD) ? "Dead (undead)" : "revive"
        f.heal = true
        f.amount_min = 1
        f.amount_max = ab.x
        f.formula = "revive with 1..{ab.x} HP"
    } else {
        f.known = false
        f.effect = "formula 0x{fmt(":02x", fo)}"
    }
    if ((fo == 0x0E || inflicts(ab.inflict, ST_DEAD) || inflicts(ab.inflict, ST_FROG)) && is_immortal(t)) {
        // research/fft/notes.md, "Frog and Death": 0% (no status named)
        // on everyone in the prologue, at Gariland 71% / 60% on Candy
        f.hit = 0
        f.notes |> push("the target is immortal (+0x05 bit 0x04): no KO, no Frog")
    }
    if (st != "" && fo != 0x2D && fo != 0x0A && fo != 0x0B && fo != 0x38) {
        f.notes |> push("status: {st}")
    }
    if (f.known && fo != 0x3C && fo < 0x48) {
        f.notes |> push("zodiac: {ZODIAC_TEXT[zodiac_compat(a, t) + 2]}")
    }
    return <- f
}
