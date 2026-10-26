options gen2
options indenting = 4

// FFTA basic attack ("Fight") and Soldier's Battle Tech: damage, hit
// chance, critical hits and reach as the ROM computes them, with support
// abilities (research/notes.md, "Attack", "Fight reach", "Abilities";
// checked against the game's own preview). Not modelled: other
// abilities' effects, reactions, mission bonuses.
module ffta_attack shared public

require math
require strings
require daslib/strings_boost
require gba_mem
require ffta_battle
require daslib/match

// where the attacker stands relative to the target's facing
enum AttackSide {
    Front
    Side
    Back
}

// how the calculator picks the side: from the positions or by hand
enum SideChoice {
    Auto
    Front
    Side
    Back
}

let SIDE_DIVISOR = fixed_array<int>(1, 2, 4)    // table 0x083A8444

struct AttackResult {
    ability : int                 // 0: Fight, else ABILITY_TABLE id
    action_name : string
    tech : TechKind
    effect : string               // what it does to the target
    physical : bool               // W.Atk / W.Def, else M.Pow / M.Res
    multiplier : int              // weapon power or the ability's power
    uses_weapon : bool            // Fight power from the weapon
    area : int                    // area radius around the target, 0: one target
    mp_cost : int
    note : string                 // the effect's other parts
    weapon : string               // item name or "Bare hands"
    element : int                 // ELEMENTS
    distance : int                // tiles, |dx| + |dy|
    weapon_range : int            // weapon +0x0A, bare hands 1
    reach : bool                  // can_fight: the target's tile is in reach
    reach_text : string           // the rule that decided it
    power : int                   // P: weapon W.Atk + other equipment
    attack_base : int             // record W.Atk
    attack : int                  // A = base x statuses + P
    attack_mods : string
    defense_base : int            // record W.Def
    defense_items : int
    defense : int                 // D = base x statuses + items
    defense_mods : string
    base : int                    // max(1, A - D / 2)
    affinity : int                // target's, for the element
    damage : int                  // the preview: no random part
    dmg_min : int
    dmg_max : int
    crit_damage : int
    crit_min : int
    crit_max : int
    side : AttackSide
    evade : int                   // target Evade
    evade_mods : string
    evade_final : int             // after side and statuses, 5..95
    cannot_evade : bool
    hit : int                     // shown by the game
    hit_roll : int                // what the roll uses
    hit_prob : float
    crit : int
    crit_prob : float
    expected : float              // average damage per attack
}

// byte: 0xE8..0xED, as in research/notes.md
def has_status(u : BattleUnit; byte, bit : uint) : bool {
    return (u.status[int(byte - 0xE8u)] & bit) != 0u
}

def is_enemy(u : BattleUnit) : bool {
    return (u.flags & 0x8000u) != 0u
}

// the equipment slot of the weapon, -1: bare hands
def weapon_slot(u : BattleUnit) : int {
    for (i in range(5)) {
        if (u.equip[i].id != 0 && is_weapon(u.equip[i])) {
            return i
        }
    }
    return -1
}

// Fight reach (0x0809FEF0): the tile exists, has no flag 0x01 / 0x08,
// is not the attacker's. Bows, greatbows, guns: |dx| + |dy| <= weapon
// range, height and obstacles do not matter. Other weapons (0x0812E1A8,
// dh = target - attacker height): the next tile with -3 <= dh <= 2;
// spears: the next tile with -4 <= dh <= 3, or 2 tiles in a line with
// dh <= 2 and dh >= a bound set by the tile between (m = its height -
// attacker's): m < 0: -3, 0: -2, 1: -1, 2: 1, 3: 2, higher: blocked.
// how a weapon kind (ITEM_KINDS) reaches its target
enum FightReach {
    Ranged          // Bow, Greatbow, Gun: distance only
    Spear           // next tile or 2 in a line, over the tile between
    Melee           // everything else, bare hands too: the next tile
}

def fight_reach(kind : int) : FightReach {
    return match (kind) {
        13 | 14 | 19 => FightReach.Ranged
        15 => FightReach.Spear
        _ => FightReach.Melee
    }
}

// spear, 2 tiles in a line: the lowest dh for the height of the tile
// between (relative to the attacker); 99: blocked
def spear_low_bound(mid : int) : int {
    return match (mid) {
        h && h < 0 => -3
        0 => -2
        1 => -1
        2 => 1
        3 => 2
        _ => 99
    }
}

def can_fight(m : BattleMap; att : BattleUnit; tx, ty : int; var why : string&) : bool {
    let slot = weapon_slot(att)
    let reach = fight_reach(slot >= 0 ? att.equip[slot].kind : 17)
    let tiles = slot >= 0 ? max(1, att.equip[slot].weapon_range) : 1
    let d = abs(tx - att.x) + abs(ty - att.y)
    let h1 = tile_height(m, tx, ty)
    let dh = h1 - tile_height(m, att.x, att.y)
    let line = tx == att.x || ty == att.y
    let r = match (reach, d) {
        (_, _) && (h1 == 0 || (tile_flags(m, tx, ty) & 0x09) != 0) => (false, "no tile to target")
        (_, 0) => (false, "own tile")
        (FightReach.Ranged, _) => (d <= tiles, "{d} <= {tiles} tiles, any height")
        (FightReach.Spear, 1) => (dh >= -4 && dh <= 3, "next tile, height {dh} in -4..3")
        (FightReach.Spear, 2) && line => spear_two(m, att, tx, ty, dh)
        (FightReach.Spear, _) => (false, "spear: next tile or 2 in a line")
        (FightReach.Melee, 1) => (dh >= -3 && dh <= 2, "next tile, height {dh} in -3..2")
        _ => (false, "melee: next tile only")
    }
    why = r._1
    return r._0
}

// spear, 2 tiles in a line: the tile between sets the lowest dh
def spear_two(m : BattleMap; att : BattleUnit; tx, ty, dh : int) : tuple<bool; string> {
    let lo = spear_low_bound(tile_height(m, (att.x + tx) / 2, (att.y + ty) / 2) - tile_height(m, att.x, att.y))
    return lo > 2 ? (false, "blocked by the tile between") : (dh >= lo && dh <= 2, "2 in a line, height {dh} in {lo}..2")
}

// 0x0812C700: the first 90-degree quadrant around the target's facing
// (front, its sides, back) that holds the attacker
def side_of(att, tgt : BattleUnit) : AttackSide {
    let dx = att.x - tgt.x
    let dy = att.y - tgt.y
    let offsets = fixed_array<int>(0, 3, 1, 2)
    for (k in range(4)) {
        let d = (tgt.facing + offsets[k]) & 3
        let vx = DIR_X[d]
        let vy = DIR_Y[d]
        let along = vx != 0 ? abs(dy) <= abs(dx) : abs(dx) <= abs(dy)
        if (dx * vx >= 0 && dy * vy >= 0 && along) {
            return k == 0 ? AttackSide.Front : (k == 3 ? AttackSide.Back : AttackSide.Side)
        }
    }
    return AttackSide.Front
}

def private scale_by(var v : int&; k : int; why : string; var mods : array<string>) {
    v = (v * k) >> 8
    mods |> push("{why} x{fmt(":.2f", float(k) / 256.0)}")
}

// 0x0812F5E0: weapon W.Atk (job +0x33 bare-handed) + W.Atk of the other
// non-weapon equipment; nothing when Frog
def attack_power(att : BattleUnit; weapon : int) : int {
    if (has_status(att, 0xE9, 0x01u)) {
        return 0
    }
    var p = weapon >= 0 ? att.equip[weapon].bonus[int(Stat.WAtk)] : att.bare_power
    for (it in att.equip) {
        if (it.id != 0 && !is_weapon(it)) {
            p += it.bonus[int(Stat.WAtk)]
        }
    }
    return p
}

// 0x0812C56C: KO (HP 0) and some statuses cannot evade
def can_evade(t : BattleUnit) : bool {
    return (t.hp != 0 && !has_status(t, 0xE8, 0x40u) && !has_status(t, 0xE9, 0x80u) && !has_status(t, 0xEA, 0x80u)
        && !has_status(t, 0xEB, 0x04u) && !has_status(t, 0xEC, 0x02u))
}

// 0x0812F1DC: success when rand2 % 10000 + 1 <= 100 p + rand1 % 100,
// two consecutive outputs of the game's LCG. They are correlated, so the
// chance is not (100 p + 49.5) / 10000: research/roll_table.py averages
// over seeds (p 5 -> 6.70 %, 35 -> 40.94 %, 75 -> 77.56 %); real hits
// agree (research/notes.md, "Real hits").
let ROLL_CHANCE = fixed_array<float>(
    0.0000, 0.0182, 0.0304, 0.0426, 0.0548, 0.0670, 0.0792, 0.0914, 0.1036, 0.1158,
    0.1281, 0.1403, 0.1525, 0.1647, 0.1769, 0.1891, 0.2013, 0.2135, 0.2257, 0.2379,
    0.2501, 0.2623, 0.2745, 0.2867, 0.2990, 0.3112, 0.3234, 0.3354, 0.3453, 0.3544,
    0.3636, 0.3727, 0.3818, 0.3910, 0.4002, 0.4093, 0.4185, 0.4277, 0.4368, 0.4460,
    0.4551, 0.4643, 0.4734, 0.4826, 0.4917, 0.5009, 0.5100, 0.5192, 0.5283, 0.5375,
    0.5467, 0.5559, 0.5650, 0.5742, 0.5833, 0.5924, 0.6016, 0.6107, 0.6199, 0.6291,
    0.6382, 0.6474, 0.6566, 0.6658, 0.6749, 0.6841, 0.6933, 0.7024, 0.7116, 0.7207,
    0.7298, 0.7390, 0.7481, 0.7573, 0.7664, 0.7756, 0.7847, 0.7939, 0.8031, 0.8122,
    0.8214, 0.8306, 0.8397, 0.8489, 0.8580, 0.8672, 0.8764, 0.8855, 0.8946, 0.9038,
    0.9130, 0.9221, 0.9313, 0.9404, 0.9496, 0.9588, 0.9679, 0.9770, 0.9862, 0.9953,
    1.0000)

def roll_probability(p : int) : float {
    return ROLL_CHANCE[clamp(p, 0, 100)]
}

// d after the element: weak x1.5, immune 0, absorb -d, half d / 2
def element_damage(d, affinity : int) : int {
    return match (affinity) {
        0 => (d * 384) >> 8             // weak
        2 => 0                          // nullifies
        3 => -d                         // absorbs
        4 => d >> 1                     // halves
        _ => d
    }
}
def private finish_damage(var r : AttackResult; tgt : BattleUnit) {
    var d = element_damage(r.damage, r.affinity)
    var c = (d * 384) >> 8
    if (has_status(tgt, 0xEC, 0x02u)) {
        d = 0
        c = 0
    }
    r.damage = clamp(d, -999, 999)
    r.crit_damage = clamp(c, -999, 999)
    // the real attack adds a whole number in [-d / 10, d / 10]
    r.dmg_min = clamp(d - abs(d) / 10, -999, 999)
    r.dmg_max = clamp(d + abs(d) / 10, -999, 999)
    r.crit_min = clamp(c - abs(c) / 10, -999, 999)
    r.crit_max = clamp(c + abs(c) / 10, -999, 999)
}

// What an action does. Soldier's Battle Tech is checked in the game
// one by one; other abilities are read from their effect list
// (research/notes.md "Ability effects").
enum TechKind {
    Fight           // the basic attack
    Damage          // HP damage, the damage formula (0x0812FE38)
    MpDamage        // MP damage, the same formula, at most the target's MP
    Status          // a status only, chance = hit chance if harmful
    Heal            // HP up, the heal formula (0x08130150)
    Revive          // KO -> HP (Life: max / 2, Full-Life: max)
    Info            // no effect on the target (Sensor)
    Unknown         // not modelled
}

struct TechInfo {
    kind : TechKind
    effect : string
    self_only : bool
    factor : int = 1              // x2 Holy Blade, x3 Ultima ...
    cap_hp : bool                 // at most the target's HP (Drain)
    revive_full : bool
    beneficial : bool             // the kind's sign (EFFECT_KINDS +8) is -1
    note : string                 // what else it does
}

// ABILITY_TABLE (28 bytes, getter 0x080CCD50) and the effect list:
// +0x0C..+0x0F effect numbers (0 / 1: none) -> EFFECT_TABLE, 4 bytes:
// +1 kind (EFFECT_KINDS, 12 bytes: +4 category 0 status / 1 HP / 2 MP,
// +8 sign 1 harmful / 0xFF helpful), +3 function (EFFECT_FUNCS)
let EFFECT_TABLE = 0x08553E70u
let EFFECT_KINDS = 0x083A87B0u
let EFFECT_FUNCS = 0x083A86F8u

struct AbilityData {
    power : int                   // +0x0B (field 33)
    weapon_power : bool           // +0x05 != 0 (field 3): power = weapon
    physical : bool               // +0x10 bit 18 (field 29): W.Atk / W.Def
    weapon_reach : bool           // +0x06 & 0x80 (field 4): Fight reach
    reach_tiles : int             // +0x06: tiles (0: the user)
    element : int                 // +0x02: ELEMENTS
    area : int                    // +0x09 == 5: area radius +0x0A, else 0
    mp_cost : int                 // +0x04 (field 2)
    funcs : uint[4]               // effect functions
    kinds : int[4]
    signs : int[4]
    effect_count : int
}

def ability_data(ability : int) : AbilityData {
    if (ability == 0 || !gba_has_rom()) {
        return AbilityData(weapon_power = true, physical = true, weapon_reach = true, reach_tiles = 1)
    }
    let a = ABILITY_TABLE + uint(ability) * 28u
    var d = AbilityData(power = int(gba_read8(a + 0x0Bu)), weapon_power = gba_read8(a + 0x05u) != 0u,
        physical = (gba_read32(a + 0x10u) & 0x40000u) != 0u, weapon_reach = (gba_read8(a + 0x06u) & 0x80u) != 0u,
        reach_tiles = int(gba_read8(a + 0x06u) & 0x3Fu), element = int(gba_read8(a + 0x02u)),
        area = gba_read8(a + 0x09u) == 5u ? int(gba_read8(a + 0x0Au)) : 0, mp_cost = int(gba_read8(a + 0x04u)))
    for (k in range(4)) {
        let e = gba_read8(a + 0x0Cu + uint(k))
        if (e > 1u && d.effect_count < 4) {
            let ef = EFFECT_TABLE + e * 4u
            let kind = gba_read8(ef + 1u)
            d.funcs[d.effect_count] = gba_read32(EFFECT_FUNCS + gba_read8(ef + 3u) * 4u)
            d.kinds[d.effect_count] = int(kind)
            d.signs[d.effect_count] = gba_read8(EFFECT_KINDS + kind * 12u + 8u) == 1u ? 1 : -1
            d.effect_count++
        }
    }
    return d
}

def tech_info(ability : int) : TechInfo {
    return match (ability) {
        0 => TechInfo(kind = TechKind.Fight, effect = "HP damage")
        76 => TechInfo(kind = TechKind.Heal, effect = "HP up (the user only)", self_only = true, beneficial = true)
        77 => TechInfo(kind = TechKind.Status, effect = "+0xEC & 0x10: W.Atk x0.9")
        78 => TechInfo(kind = TechKind.Status, effect = "+0xEC & 0x40: M.Pow x0.9")
        79 => TechInfo(kind = TechKind.MpDamage, effect = "MP damage")
        80 => TechInfo(kind = TechKind.Status, effect = "+0xEC & 0x04: Speed / 2")
        81 => TechInfo(kind = TechKind.Damage, effect = "HP damage, steals gil")
        82 => TechInfo(kind = TechKind.Status, effect = "Berserk (+0xE8 & 0x80): W.Atk x1.2")
        83 => TechInfo(kind = TechKind.Info, effect = "shows the target's info")
        _ => effect_info(ability, ability_data(ability))
    }
}
def private is_formula(f : uint) : bool {
    return f == 0x0813189Du || f == 0x081318D5u || f == 0x08131A99u || f == 0x081319FDu || f == 0x08131931u
}

// The effect list: the first effect that changes HP / MP decides; a
// formula damage effect after a heal or revive one hits undead only.
// Functions: 0x08131481 status only (value 0); 0x0813189D the damage
// formula, 0x081318D5 x2, 0x08131A99 x3, 0x081319FD at most the
// target's HP (Drain; 0x08131751 gives it to the user), 0x08131931 at
// most the target's MP; 0x08131961 the heal formula; 0x08131A61 /
// 0x08131A51 revive with max HP / 2 / max HP.
def effect_info(ability : int; ab : AbilityData) : TechInfo {
    var t = TechInfo(kind = TechKind.Unknown, effect = "no effect data")
    t.self_only = ab.reach_tiles == 0 && !ab.weapon_reach
    var statuses = 0
    var others : array<string>
    for (k in range(ab.effect_count)) {
        let f = ab.funcs[k]
        let harmful = ab.signs[k] > 0
        let first = t.kind == TechKind.Unknown
        if (f == 0x08131481u) {
            statuses++
            if (first) {
                t.kind = TechKind.Status
                t.beneficial = !harmful
                t.effect = harmful ? "inflicts {ability_name(ability)}" : "grants {ability_name(ability)}"
            }
        } elif (is_formula(f)) {
            if (first || t.kind == TechKind.Status) {
                let mp = f == 0x08131931u
                t.kind = mp ? TechKind.MpDamage : (harmful ? TechKind.Damage : TechKind.Heal)
                t.factor = f == 0x081318D5u ? 2 : (f == 0x08131A99u ? 3 : 1)
                t.cap_hp = f == 0x081319FDu
                t.beneficial = !harmful
                t.effect = mp ? "MP damage" : (harmful ? "HP damage" : "HP up (damage formula)")
                if (t.factor > 1) {
                    t.effect += " x{t.factor}"
                }
                if (t.cap_hp) {
                    t.effect += ", the user gets it back"
                }
            } else {
                others |> push("damages undead")
            }
        } elif (f == 0x08131961u) {
            t.kind = TechKind.Heal
            t.beneficial = true
            t.effect = "HP up"
        } elif (f == 0x08131A61u || f == 0x08131A51u) {
            t.kind = TechKind.Revive
            t.revive_full = f == 0x08131A51u
            t.beneficial = true
            t.effect = t.revive_full ? "revives with full HP" : "revives with max HP / 2"
        } elif (f != 0x08131751u) {
            others |> push("special 0x{fmt(":08x", f)}")
            if (first) {
                t.effect = "special effect, not modelled"
            }
        }
    }
    if (statuses > 0 && t.kind != TechKind.Status) {
        others |> push("and a status")
    }
    t.note = join(others, ", ")
    return t
}

// 0x08130150 (Cure, First Aid, ...): (record stat x support x statuses
// - the target's record M.Res (W.Def) / 2, no equipment, no statuses)
// x power / 100; the random part (+-1/10) is on the base
def private heal_value(var r : AttackResult; tgt : BattleUnit; power : int; phys : bool) {
    let a = r.attack - r.power                 // the attack value without P
    let d = tgt.stat_base[phys ? int(Stat.WDef) : int(Stat.MRes)]
    let base = a - (d >> 1)
    let k = abs(base) / 10
    r.attack = a
    r.power = 0
    r.defense = d
    r.defense_items = 0
    r.defense_mods = "record only"
    r.base = base
    r.damage = clamp(base * power / 100, 1, 999)
    r.dmg_min = clamp((base - k) * power / 100, 1, 999)
    r.dmg_max = clamp((base + k) * power / 100, 1, 999)
}

// Fight or an action ability. 0x0812FE38 (damage: 0x0812FD44 attack,
// 0x0812FDDC defense), 0x0812C7F4 (hit), 0x0812E0FC (critical hit).
// Support abilities (0x080CD50C, record +0x3B): attacker Weapon Atk+ (1)
// x1.2 physical, Magic Pow+ (3) x1.2 magic, Turbo MP (4) x1.3 for
// abilities with an MP cost and Evade -15, Doublehand (7) x1.2 in Fight
// with a one-handed weapon (item +0x0B == 1), Concentrate (13) Evade
// -50; target Weapon Def+ (2) physical defense x1.4.
def act(m : BattleMap; att, tgt0 : BattleUnit; ability : int; choice : SideChoice) : AttackResult {
    var r : AttackResult
    r.ability = ability
    r.action_name = ability_name(ability)
    let info = tech_info(ability)
    r.tech = info.kind
    r.effect = info.effect
    let tgt = info.self_only ? att : tgt0
    let ab = ability_data(ability)
    r.physical = ab.physical
    let slot = weapon_slot(att)
    r.weapon = slot >= 0 ? att.equip[slot].name : "Bare hands"
    r.element = ab.element != 0 ? ab.element : (slot >= 0 && ab.weapon_power ? att.equip[slot].element : 0)
    r.area = ab.area
    r.uses_weapon = ab.weapon_power
    r.mp_cost = ab.mp_cost
    r.note = info.note
    r.weapon_range = slot >= 0 ? max(1, att.equip[slot].weapon_range) : 1
    r.distance = abs(att.x - tgt.x) + abs(att.y - tgt.y)
    if (info.self_only) {
        r.reach = true
        r.reach_text = "the user only"
    } elif (ab.weapon_reach) {
        r.reach = can_fight(m, att, tgt.x, tgt.y, r.reach_text)
    } else {
        r.reach = r.distance <= ab.reach_tiles
        r.reach_text = "{r.distance} <= {ab.reach_tiles} tiles"  // height: not checked
    }
    let phys = ab.physical
    let atk_stat = phys ? int(Stat.WAtk) : int(Stat.MPow)
    let def_stat = phys ? int(Stat.WDef) : int(Stat.MRes)
    let frog_att = has_status(att, 0xE9, 0x01u)
    // P: Fight power (weapon) for the attack value, all equipment M.Pow
    // for magic; the multiplier is the weapon power or the ability's
    let weapon_p = attack_power(att, slot)
    r.power = phys ? weapon_p : (frog_att ? 0 : att.stat_items[int(Stat.MPow)])
    let mult = ab.weapon_power ? weapon_p : ab.power
    r.multiplier = mult
    // attack: record stat x support x attacker statuses + P
    var amods : array<string>
    var a = att.stat_base[atk_stat]
    r.attack_base = a
    if (phys && att.support == 1) {
        scale_by(a, 307, "Weapon Atk+", amods)
    }
    if (!phys && att.support == 3) {
        scale_by(a, 307, "Magic Pow+", amods)
    }
    if (ability != 0 && att.support == 4 && ab.mp_cost != 0) {
        scale_by(a, 332, "Turbo MP", amods)
    }
    if (ability == 0 && att.support == 7 && slot >= 0 && att.equip[slot].hands == 1) {
        scale_by(a, 307, "Doublehand", amods)
    }
    if (phys && has_status(att, 0xE8, 0x80u)) {
        scale_by(a, 307, "Berserk", amods)
    }
    if (frog_att) {
        scale_by(a, 25, "Frog", amods)
    }
    if (phys && has_status(att, 0xE9, 0x40u)) {
        scale_by(a, 384, "+E9&40", amods)
    }
    if (phys && has_status(att, 0xEC, 0x08u)) {
        scale_by(a, 281, "+EC&08", amods)
    }
    if (phys && has_status(att, 0xEC, 0x10u)) {
        scale_by(a, 230, "Powerbreak", amods)
    }
    if (!phys && has_status(att, 0xEC, 0x20u)) {
        scale_by(a, 281, "+EC&20", amods)
    }
    if (!phys && has_status(att, 0xEC, 0x40u)) {
        scale_by(a, 230, "Mindbreak", amods)
    }
    r.attack = min(999, a + r.power)
    r.attack_mods = join(amods, ", ")
    // defense: record stat x support x target statuses + equipment
    var dmods : array<string>
    var d = tgt.stat_base[def_stat]
    r.defense_base = d
    if (phys && tgt.support == 2) {
        scale_by(d, 358, "Weapon Def+", dmods)
    }
    if (phys && has_status(tgt, 0xEB, 0x02u)) {
        scale_by(d, 358, "Protect", dmods)
    }
    if (!phys && has_status(tgt, 0xEB, 0x01u)) {
        scale_by(d, 358, "Shell", dmods)
    }
    if (has_status(tgt, 0xE8, 0x40u)) {
        scale_by(d, 460, "+E8&40", dmods)
    }
    if (has_status(tgt, 0xE9, 0x01u)) {
        scale_by(d, 25, "Frog", dmods)
    }
    if (has_status(tgt, 0xE9, 0x20u)) {
        scale_by(d, 358, "+E9&20", dmods)
    }
    if (phys && has_status(tgt, 0xEC, 0x80u)) {
        scale_by(d, 358, "+EC&80", dmods)
    }
    if (phys && has_status(tgt, 0xED, 0x01u)) {
        scale_by(d, 179, "+ED&01", dmods)
    }
    if (!phys && has_status(tgt, 0xED, 0x02u)) {
        scale_by(d, 358, "+ED&02", dmods)
    }
    if (!phys && has_status(tgt, 0xED, 0x04u)) {
        scale_by(d, 179, "+ED&04", dmods)
    }
    r.defense_items = has_status(tgt, 0xE9, 0x01u) ? 0 : tgt.stat_items[def_stat]
    r.defense = min(999, d + r.defense_items)
    r.defense_mods = join(dmods, ", ")
    r.base = max(1, r.attack - (r.defense >> 1))
    r.damage = max(1, r.base * mult / 100)
    r.affinity = r.element > 0 && r.element < 9 ? tgt.affinity[r.element] : 1
    finish_damage(r, tgt)
    if (info.kind == TechKind.Heal && ability != 0) {
        heal_value(r, tgt, mult, phys)
    } elif (info.kind == TechKind.Revive) {
        r.damage = info.revive_full ? tgt.max_hp : max(1, tgt.max_hp / 2)
        r.dmg_min = r.damage
        r.dmg_max = r.damage
    } elif (info.factor > 1 || info.cap_hp || info.kind == TechKind.MpDamage) {
        let cap = info.kind == TechKind.MpDamage ? tgt.mp : (info.cap_hp ? tgt.hp : 999)
        r.damage = min(clamp(r.damage * info.factor, -999, 999), cap)
        r.dmg_min = min(clamp(r.dmg_min * info.factor, -999, 999), cap)
        r.dmg_max = min(clamp(r.dmg_max * info.factor, -999, 999), cap)
    }
    if (info.kind == TechKind.Status || info.kind == TechKind.Info || info.kind == TechKind.Unknown) {
        r.damage = 0
        r.dmg_min = 0
        r.dmg_max = 0
        r.crit_damage = 0
    }
    // hit chance (the user only: always)
    r.side = choice == SideChoice.Front ? AttackSide.Front : (choice == SideChoice.Side ? AttackSide.Side :
        (choice == SideChoice.Back ? AttackSide.Back : side_of(att, tgt)))
    let frog = has_status(tgt, 0xE9, 0x01u)
    r.evade = clamp(tgt.stat_base[int(Stat.Evade)] + (frog ? 0 : tgt.stat_items[int(Stat.Evade)]), 0, 100)
    var e = r.evade / SIDE_DIVISOR[int(r.side)]
    var emods : array<string>
    emods |> push("{r.side} /{SIDE_DIVISOR[int(r.side)]}")
    if (has_status(tgt, 0xE9, 0x04u)) {
        e -= 20
        emods |> push("target Blind -20")
    }
    if (has_status(tgt, 0xEB, 0x10u)) {
        e -= 10
        emods |> push("target +EB&10 -10")
    }
    if (has_status(att, 0xE9, 0x04u)) {
        e += 50
        emods |> push("attacker Blind +50")
    }
    if (att.support == 13) {
        e -= 50
        emods |> push("Concentrate -50")
    } elif (att.support == 4) {
        e -= 15
        emods |> push("Turbo MP -15")
    }
    r.evade_final = clamp(e, 5, 95)
    r.evade_mods = join(emods, ", ")
    r.cannot_evade = info.self_only || info.beneficial || !can_evade(tgt)
    r.hit = r.cannot_evade || has_status(tgt, 0xEA, 0x02u) ? 100 : 100 - r.evade_final
    // the roll: +10 for attackers that are not enemies (0x080A2846);
    // real uses: Fight 77.7 % for 75, Powerbreak 77.0 % for shown 65
    if (tgt.hp == 0 || info.self_only || info.beneficial) {
        r.hit_roll = 100
    } else {
        r.hit_roll = r.hit > 0 && !is_enemy(att) ? min(100, r.hit + 10) : r.hit
    }
    r.hit_prob = roll_probability(r.hit_roll)
    // critical hit (Fight): job Evade (no items) / 10, +30 with +0xEA & 1
    if (ability == 0) {
        r.crit = clamp(att.stat_base[int(Stat.Evade)] / 10 + (has_status(att, 0xEA, 0x01u) ? 30 : 0), 0, 100)
    }
    r.crit_prob = roll_probability(r.crit)
    r.expected = r.hit_prob * ((1.0 - r.crit_prob) * float(r.damage) + r.crit_prob * float(r.crit_damage))
    return r
}

def fight(m : BattleMap; att, tgt : BattleUnit; choice : SideChoice) : AttackResult {
    return act(m, att, tgt, 0, choice)
}

// ------------------------------------------------------------ reactions

// The target's reaction (record +0x3A, 0x0812E6A4) to an action:
// 0x0812EA44 / 0x0812E6E0 decide whether it triggers, 0x0812C5CC makes
// the hit chance 0 for the dodging ones. Ability flags: +0x10 bit 6
// (field 17) no reaction, bit 15 reflectable, bit 16 can be caught,
// bit 17 MP can be absorbed, bit 18 physical.
struct ReactionResult {
    name : string
    triggers : bool
    dodge : bool                  // the attack's hit chance becomes 0
    counter : bool                // the target strikes back with Fight
    text : string
    back : AttackResult           // the strike back (target -> attacker)
}

def private ability_flag(ability, bit : int) : bool {
    return ability != 0 && gba_has_rom() && (gba_read32(ABILITY_TABLE + uint(ability) * 28u + 0x10u) & (1u << uint(bit))) != 0u
}

def reaction(m : BattleMap; att, tgt : BattleUnit; ability : int; r : AttackResult) : ReactionResult {
    var res = ReactionResult(name = tgt.reaction_name)
    let id = tgt.reaction
    if (id == 0 || tgt.hp == 0) {
        return res
    }
    let no_react = ability_flag(ability, 6)
    let physical = ability == 0 || ability_flag(ability, 18)
    let damaging = r.damage > 0 && r.tech != TechKind.Heal && r.tech != TechKind.Revive && r.tech != TechKind.Status
    let slot = weapon_slot(att)
    let bow = slot >= 0 && (att.equip[slot].kind == 13 || att.equip[slot].kind == 14)
    var why = ""
    // can the target hit the attacker back in melee (0x0812E1A8)?
    let reach = can_fight(m, tgt, att.x, att.y, why)
    if (id == 5) {
        res.triggers = ability == 0
        res.dodge = res.triggers
        res.text = "Reflex: dodges Fight"
    } elif (id == 6) {
        res.triggers = bow && (ability == 0 || (r.uses_weapon && !no_react))
        res.dodge = res.triggers
        res.text = "Block Arrows: dodges bow attacks"
    } elif (id == 7) {
        res.triggers = ability == 0 && reach
        res.dodge = res.triggers
        res.counter = res.triggers
        res.text = reach ? "Strikeback: dodges Fight and strikes back" : "Strikeback: the attacker is out of reach"
    } elif (id == 8 || id == 10) {
        res.triggers = (ability == 0 || (physical && !no_react)) && reach
        res.counter = res.triggers
        let what = id == 10 ? "Bonecrusher: strikes back x1.5" : "Counter: strikes back"
        res.text = reach ? what : "{what} (the attacker is out of reach)"
    } elif (id == 9) {
        res.triggers = ability == 0 && bow
        res.text = "Return Fire: catches the arrow and shoots back"
    } elif (id == 11) {
        res.triggers = ability != 0 && !no_react && ability_flag(ability, 15)
        res.text = "Return Magic: reflects the spell back"
    } elif (id == 15) {
        res.triggers = ability != 0 && !no_react && ability_flag(ability, 17)
        res.text = "Absorb MP: takes the MP of the spell"
    } elif (id == 4) {
        res.triggers = ability != 0 && is_enemy(att) != is_enemy(tgt) && ability_flag(ability, 16)
        res.text = "Catch: catches the thrown item"
    } elif (id == 12) {
        res.triggers = physical && !no_react && damaging
        res.text = "Dragonheart: gets Auto-Life when hit"
    } elif (id == 13) {
        res.triggers = !no_react && damaging && tgt.mp > 0
        res.text = "Damage > MP: takes the damage from MP"
    } elif (id == 14) {
        res.triggers = !no_react && damaging
        res.text = "Auto-Regen: gets Regen when hit"
    } elif (id >= 1 && id <= 3) {
        res.triggers = !no_react && damaging
        res.text = "{tgt.reaction_name}: when hit (the HP condition is not checked)"
    } else {
        res.text = tgt.reaction_name
    }
    if (res.counter) {
        res.back = act(m, tgt, att, 0, SideChoice.Auto)
        if (id == 10) {
            // 0x0813009C: x1.5 (kind 10) after the random part
            res.back.damage = (res.back.damage * 384) >> 8
            res.back.dmg_min = (res.back.dmg_min * 384) >> 8
            res.back.dmg_max = (res.back.dmg_max * 384) >> 8
            res.back.crit_damage = (res.back.crit_damage * 384) >> 8
        }
    }
    return res
}
