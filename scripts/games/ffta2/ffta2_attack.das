options gen2
options indenting = 4

// FFTA2 Attack (ability 799): the game's forecast, translated from its
// scripts (research/ffta2/notes.md, "Script VM"; `vmdec.py rom.nds '#598/c'
// +1` damage, `'#784' +1` hit). Stats in the record's raw units (shown =
// raw / 4). Not translated yet: game variables the scripts read (only the
// clan privilege is a parameter), other abilities, the real hit's critical
// and spread (sub_92A0), the status immunities of the hit (sub_4390).
module ffta2_attack shared public

require math
require strings
require ffta2_battle

enum Side2 {
    Front
    Side
    Back
}

let SIDE2_NAMES = fixed_array<string>("Front", "Side", "Back")
let AFFINITY_NAMES = fixed_array<string>("Weak", "Normal", "Half", "Immune", "Absorb")

let ATTACK_ABILITY = 799

struct Fight2 {
    weapon : string                 // item name or "Bare hands"
    element : int                   // ELEMENT2_NAMES
    atk10 : int                     // raw Attack x 10 after supports and statuses
    def10 : int                     // target's raw Defense x 10 after its supports and statuses
    power10 : int                   // (weapon or bare hands + other items' Attack) x 10
    armor10 : int                   // target's equipment Defense x 10
    base : int                      // atk10/4 + power10 - (def10/4 + armor10)/2
    privilege : int                 // the clan privilege's bonus, %
    scaled : int                    // base x (100 + privilege) / 100 / 10 / 2
    side : Side2                    // as the game counts it (job and support exceptions)
    after_side : int
    affinity : int                  // the target's for the element after the attacker's, 1 normal
    damage : int                    // the forecast (minus: absorbed)
    mods : array<string>            // what changed the numbers
    evasion : int                   // target's equipment Evasion
    hit : int                       // the forecast, %
    hit_mods : array<string>
    // the real attack (research/ffta2/notes.md, "The real attack")
    hit_prob : float                // the roll: target's generator, v % 10000 <= hit x 100
    crit : int                      // critical chance as the script has it, %
    crit_prob : float               // the roll: v % 10000 < crit x 100
    spread : array<float2>          // damage values (x) and their probability (y), given a hit
    dmg_min : int
    dmg_max : int
    expected : float                // average damage per attack (misses count 0)
}

// The game's rolls take a 16-bit value v of an LCG (seed x 0x5D588B65 +
// 0x269EC3, the seed's high half), uniform over 0..65535. 65536 = q x m +
// rem: residues of v % m below rem come q + 1 times, the others q times.

// the probability of v % 10000 <= t (t < 0: 0)
def private mod10000_le(t : int) : float {
    if (t < 0) {
        return 0.0
    }
    let k = min(t, 9999) + 1
    return float(k * 6 + min(k, 5536)) / 65536.0
}

// sub_A980(n): (v % (n x 100)) / 100 - the probability of each 0..n-1
def private rand_dist(n : int) : array<float> {
    let m = n * 100
    let q = 65536 / m
    let rem = 65536 % m
    var res : array<float>
    for (b in range(n)) {
        res |> push(float(100 * q + clamp(rem - 100 * b, 0, 100)) / 65536.0)
    }
    return <- res
}

// sub_92A0 for a hit of `base` damage: the critical doubles it, then
// + (rand(3) - 1) x rand(|d| / 5 + 1) (|d| / 5 == 0: + rand(3) - 1),
// clamped as the forecast
def private add_spread(var out : array<float2>; base : int; p : float) {
    let sgn <- rand_dist(3)
    let v1 = abs(base / 5)
    let mag <- rand_dist(v1 + 1)
    for (si in range(3)) {
        for (m in range(length(mag))) {
            let step = v1 > 0 ? (si - 1) * m : si - 1
            if (v1 == 0 && m > 0) {
                continue
            }
            var d = base + step
            d = base < 0 ? clamp(d, -999, -1) : clamp(d, 1, 999)
            let q = p * sgn[si] * (v1 > 0 ? mag[m] : 1.0)
            var found = false
            for (e in out) {
                if (int(e.x) == d) {
                    e.y += q
                    found = true
                }
            }
            if (!found) {
                out |> push(float2(float(d), q))
            }
        }
    }
}

// the critical chance of Attack (sub_92A0): 5 %, the privilege (16..20,
// or 23..29 for the attacker's race), the attacker's Critical up status
// and Death Strike support +3 each
def crit_chance(privilege : int; att : Unit2) : int {
    var c = 5
    if (privilege == 19 || privilege == 20) {
        c = 8
    } elif (privilege == 17 || privilege == 18) {
        c = 7
    } elif (privilege == 16) {
        c = 6
    } elif (privilege >= 23 && privilege <= 29 && clan_member(att) && att.race_id == privilege - 22) {
        c = 6
    }
    if (has_status2(att, 18)) {
        c += 3
    }
    if (att.support == 868) {
        c += 3
    }
    return c
}

def is_weapon2(it : Item2) : bool {
    return it.id != 0 && it.kind >= 1 && it.kind <= 25
}

// the equipment slot of the weapon, -1: bare hands
def weapon_slot2(u : Unit2) : int {
    for (i in range(EQUIP_SLOTS)) {
        if (is_weapon2(u.equip[i])) {
            return i
        }
    }
    return -1
}

def private clan_member(u : Unit2) : bool {
    return (u.team_byte & 5) == 0           // natives 1571 / 1572: record +0x0A bits 0, 2
}

// sub_A2B0: 0 front, 1 back, 2 side; facings and tiles as the game has
// them (object +0x0E: 0 +y, 1 -x, 2 +x, 3 -y). A diagonal behind is a side.
def side_of2(att, tgt : Unit2) : Side2 {
    let f = FACING_FROM_GAME[tgt.facing & 3]
    let dx = att.x - tgt.x
    let dy = att.y - tgt.y
    var along = dy                          // toward the facing
    var across = abs(dx)
    if (f == 3) {
        along = -dy
    } elif (f == 2) {
        along = dx
        across = abs(dy)
    } elif (f == 1) {
        along = -dx
        across = abs(dy)
    }
    if (along >= across) {
        return Side2.Front
    }
    return along <= -1 - across ? Side2.Back : Side2.Side
}

// sub_B0D0: the target's equipment for an element: the strongest code of
// the element's five (1 absorb, 2 immune, 3 half, 4 weak), else an
// armour piece of the element halves it; 1 normal when nothing
def private equip_affinity(tgt : Unit2; e : int) : int {
    var code = 0
    for (it in tgt.equip) {
        let c = it.code
        if (it.id != 0 && c >= 5 * (e - 1) + 1 && c <= 5 * (e - 1) + 4 && (code == 0 || code > c)) {
            code = c
        }
    }
    if (code == 0) {
        for (it in tgt.equip) {
            if (it.id >= 289 && it.element == e) {
                code = 5 * (e - 1) + 3
            }
        }
    }
    let k = code % 5
    return code == 0 ? 1 : (k == 1 ? 4 : (k == 2 ? 3 : (k == 3 ? 2 : (k == 4 ? 0 : 1))))
}

// sub_AA10 / sub_AD90: the job's affinity, the equipment's if it is not
// normal (the stronger of both); Oil makes Fire weak; a weapon of the
// element (code 5 x element: no item has one) or Geomancy lowers it a step
def element_affinity(e, weapon_code : int; att, tgt : Unit2) : int {
    var a = 1
    if (e >= 1 && e <= 8) {
        a = tgt.affinity[e - 1]
        let eq = equip_affinity(tgt, e)
        if (eq != 1 && (a == 1 || a < eq)) {
            a = eq
        }
        if (e == 1 && has_status2(tgt, 46)) {
            a = 0
        }
    }
    if ((e >= 1 && e <= 8 && weapon_code == 5 * e) || (att.support == 856 && e != 0)) {
        a = a >= 1 && a <= 4 ? a - 1 : a
    }
    return a
}

def private scale(var v : int&; k : int; why : string; var mods : array<string>) {
    v = v * k / 10
    mods |> push("{why} x{fmt(":.1f", float(k) / 10.0)}")
}

// the clan privilege (game variable 369) as the damage bonus, % (sub_67E0)
def privilege_damage(privilege : int; att, tgt : Unit2) : int {
    var b = 0
    if (privilege >= 1 && privilege <= 5) {
        b += clan_member(att) ? 5 * privilege : 0
        b -= clan_member(tgt) ? 5 * privilege : 0
    } elif (privilege >= 23 && privilege <= 29) {
        b += clan_member(att) && att.race_id == privilege - 22 ? 5 : 0
        b -= clan_member(tgt) && tgt.race_id == privilege - 22 ? 5 : 0
    }
    return b
}

// side: as side_of2 counts it or chosen by hand; privilege: game variable 369
def fight2(att, tgt : Unit2; side : Side2; privilege : int = 0) : Fight2 {
    var f = Fight2()
    // the attacker's Attack (raw x 10) and its modifiers
    var v0 = att.raw[0] * 10
    if (att.support == 851 || att.support == 877 || att.support == 879) {
        scale(v0, 12, att.support_name, f.mods)
    }
    if (att.support == 869 && att.hp == att.max_hp) {
        scale(v0, 15, "Unscarred", f.mods)
    }
    if (has_status2(att, 10)) {
        scale(v0, 12, "Berserk", f.mods)
    }
    if (has_status2(att, 36)) {
        scale(v0, 12, "Attack up", f.mods)
    }
    if (has_status2(att, 37)) {
        scale(v0, 8, "Attack down", f.mods)
    }
    let ws = weapon_slot2(att)
    var cannon = false
    for (it in att.equip) {
        cannon = cannon || (it.id != 0 && it.kind == 19)
    }
    if (has_status2(att, 16)) {
        scale(v0, 18, "Focus", f.mods)
    } elif (has_status2(att, 49) && cannon) {
        scale(v0, 18, "Combustion", f.mods)
    }
    f.atk10 = max(v0, 1)
    // the target's Defense
    var v3 = tgt.raw[1] * 10
    if (tgt.support == 852 || tgt.support == 877 || tgt.support == 879) {
        scale(v3, 12, "target {tgt.support_name}", f.mods)
    }
    if (tgt.support == 869 && tgt.hp == tgt.max_hp) {
        scale(v3, 15, "target Unscarred", f.mods)
    }
    if (has_status2(tgt, 15)) {
        scale(v3, 12, "target Shield", f.mods)
    }
    if (has_status2(tgt, 26)) {
        scale(v3, 13, "target Protect", f.mods)
    }
    if (has_status2(tgt, 40)) {
        scale(v3, 12, "target Defense up", f.mods)
    }
    if (has_status2(tgt, 41)) {
        scale(v3, 8, "target Defense down", f.mods)
    }
    f.def10 = v3
    // the weapon's power (bare hands: the job's), the element
    var power = att.bare_power
    var weapon_code = 0
    f.weapon = "Bare hands"
    if (ws >= 0) {
        power = att.equip[ws].bonus[0]
        f.weapon = att.equip[ws].name
        f.element = att.equip[ws].element
        weapon_code = att.equip[ws].code
        if (att.support == 859) {
            var two = 0
            for (it in att.equip) {
                two += is_weapon2(it) && it.two_hand ? 1 : 0
            }
            if (two == 1) {
                scale(power, 12, "Doublehand", f.mods)
            }
        }
    }
    for (it in att.equip) {
        if (it.id > 288) {
            power += it.bonus[0]
        }
    }
    f.power10 = power * 10
    var armor = 0
    for (it in tgt.equip) {
        if (it.id != 0) {
            armor += it.bonus[1]
        }
    }
    f.armor10 = armor * 10
    f.base = f.atk10 * 25 / 100 + f.power10 - (f.def10 * 25 / 100 + f.armor10) / 2
    f.privilege = privilege_damage(privilege, att, tgt)
    f.scaled = f.base * (100 + f.privilege) / 100 / 10 / 2
    // the side: some jobs (job +50 == 2, Crushatrice and the next) always
    // count as hit at the side, Vigilance always in front
    f.side = side
    if (tgt.job_50 == 2 || tgt.job_id == 137 || tgt.job_id == 138) {
        f.side = Side2.Side
    }
    if (tgt.support == 876) {
        f.side = Side2.Front
    }
    var d = f.scaled
    if (f.side == Side2.Side) {
        d = d * 3 / 2
    } elif (f.side == Side2.Back) {
        d = d * 2
    }
    f.after_side = d
    if (privilege == 35 && clan_member(att)) {
        f.element = 0
    }
    f.affinity = element_affinity(f.element, weapon_code, att, tgt)
    if (f.affinity == 2) {
        d = d / 2
    } elif (f.affinity == 0) {
        d = d * 3 / 2
    }
    if (f.affinity == 4) {
        d = clamp(-d, -999, -1)
    } else {
        d = clamp(d, 1, 999)
    }
    if (f.affinity == 3) {
        d = 0
    }
    if (has_status2(tgt, 34) && d > 0) {
        d = 0
        f.mods |> push("target Bulwark: no damage")
    }
    f.damage = d
    // the hit (script 784, sub_5DD0)
    for (it in tgt.equip) {
        if (it.id != 0) {
            f.evasion += it.bonus[5]
        }
    }
    var h = tgt.job_hit - f.evasion
    if (privilege >= 6 && privilege <= 10) {
        h += clan_member(att) ? 2 * (privilege - 5) : 0
        h -= clan_member(tgt) ? 2 * (privilege - 5) : 0
    } elif (privilege >= 23 && privilege <= 29) {
        h += clan_member(att) && att.race_id == privilege - 22 ? 2 : 0
        h -= clan_member(tgt) && tgt.race_id == privilege - 22 ? 2 : 0
    }
    if (att.support == 865) {
        h += 5
        f.hit_mods |> push("Concentration +5")
    }
    if (has_status2(att, 13)) {
        h -= 30
        f.hit_mods |> push("Blind -30")
    }
    if (has_status2(att, 54)) {
        h += 30
        f.hit_mods |> push("Accuracy up +30")
    }
    if (has_status2(att, 52) && cannon) {
        h += 30
        f.hit_mods |> push("Precision +30")
    }
    if (has_status2(tgt, 57)) {
        h -= 20
        f.hit_mods |> push("target Evasion up -20")
    }
    h = clamp(h, 1, 99)
    for (n in fixed_array<int>(2, 9, 27, 24, 17, 34)) {
        if (has_status2(tgt, n)) {
            h = 100
            f.hit_mods |> push("target {status_name(n)}: 100")
        }
    }
    if (tgt.support == 881 && !elusion_reaches(att, tgt)) {
        h = 0
        f.hit_mods |> push("target Elusion: out of reach")
    }
    f.hit = h
    f.hit_prob = h >= 100 ? 1.0 : (h <= 0 ? 0.0 : mod10000_le(h * 100))
    f.crit = crit_chance(privilege, att)
    f.crit_prob = mod10000_le(f.crit * 100 - 1)
    if (f.damage == 0) {
        f.spread |> push(float2(0.0, 1.0))
    } else {
        add_spread(f.spread, f.damage, 1.0 - f.crit_prob)
        add_spread(f.spread, clamp(f.damage * 2, -1998, 1998), f.crit_prob)
    }
    sort(f.spread) $(a, b) => a.x < b.x
    f.dmg_min = int(f.spread[0].x)
    f.dmg_max = int(f.spread[length(f.spread) - 1].x)
    var mean = 0.0
    for (e in f.spread) {
        mean += e.x * e.y
    }
    f.expected = mean * f.hit_prob
    return <- f
}

// sub_84B0: Elusion lets only close attacks hit
def private elusion_reaches(att, tgt : Unit2) : bool {
    let d = abs(att.x - tgt.x) + abs(att.y - tgt.y)
    let in_line = att.x == tgt.x || att.y == tgt.y
    if (d > 3) {
        return false
    }
    if (d == 3) {
        if (tgt.job_50 != 2) {
            return false
        }
        if (tgt.job_id == 132) {
            return att.y > tgt.y && !in_line
        }
        return !in_line
    }
    if (d == 2) {
        if (tgt.job_50 != 2) {
            return false
        }
        if (tgt.job_id == 132) {
            return att.y > tgt.y || att.x != tgt.x
        }
        return true
    }
    return true
}

struct AttackRoll {
    hit : bool
    crit : bool
    damage : int                    // 0 on a miss
}

// The next Attack exactly, from the generators: the hit on the target's
// (0x0206F204: >= 100 hits and < 1 misses without a roll), the critical
// and the spread on the battle's (sub_92A0; rolled even on a miss).
// Valid while nothing else rolls before it.
def roll_attack(f : Fight2; battle_seed, target_seed : uint) : AttackRoll {
    var r = AttackRoll()
    var ts = target_seed
    r.hit = f.hit >= 100 || (f.hit > 0 && rng_next(ts) % 10000 <= f.hit * 100)
    if (f.damage == 0) {
        return r
    }
    var bs = battle_seed
    var d = f.damage
    if ((rng_next(bs) % 10000) / 100 < f.crit) {
        r.crit = true
        d = d * 2
    }
    let v1 = abs(d / 5)
    let sgn = (rng_next(bs) % 300) / 100 - 1
    if (v1 > 0) {
        d += sgn * ((rng_next(bs) % (100 * (v1 + 1))) / 100)
    } else {
        d += sgn
    }
    d = f.damage < 0 ? clamp(d, -999, -1) : clamp(d, 1, 999)
    r.damage = r.hit ? d : 0
    return r
}
