options gen2
options indenting = 4

// FFTA2 actions: the game's forecast and the real roll, translated from
// its scripts (research/ffta2/notes.md, "Script VM"; `vmdec.py rom.nds
// '#598/c' +1` amount, `'#784' +1` hit): Attack and the abilities whose
// amount is function 1 (physical and magick damage, healing spells).
// Stats in the record's raw units (shown = raw / 4). Not translated yet:
// other amount functions (fixed amounts, rends, items), game variables
// the scripts read (only the clan privilege is a parameter), the status
// immunities of the hit (sub_4390), areas.
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
    ability : Ability2
    unsupported : bool              // its amount is another function
    healing : bool                  // applied as healing (the amount is HP restored)
    by_side : bool                  // the side counts (else x1.5)
    hit_unsupported : bool          // its hit is another function
    effect : int                    // the ability's effect used (0..3), -1 none
    weapon : string                 // the weapon (Attack, techniques without power) or the ability
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

// Script 332, the effect types (conditions): 1 applies, 0 not, -1 the
// type is not translated. Most end with: not on KO (1) / 0 HP (2), not on
// Invisible (14) unless the attacker has Reveal (866).
def effect_applies(t : int; ab : Ability2; att, tgt : Unit2) : int {
    let hidden = has_status2(tgt, 14) && att.support != 866
    let down = has_status2(tgt, 1) || has_status2(tgt, 2)
    let job = tgt.job_id
    if (t == 15) {
        var v = !down
        if (has_status2(tgt, 14)) {
            v = att.support == 866 || ab.id == 635
        }
        return v ? 1 : 0
    } elif (t == 24) {
        let ae = (att.team_byte & 1) != 0
        let te = (tgt.team_byte & 1) != 0
        return ae != te && !down && !hidden ? 1 : 0
    } elif (t == 33) {
        return !tgt.flying && !has_status2(tgt, 1) && !hidden ? 1 : 0
    } elif (t == 35) {
        let human = job < 62 || (job > 140 && job < 147) || job > 156
        return human && !down && !hidden ? 1 : 0
    } elif (t == 37) {
        return tgt.flying && !has_status2(tgt, 2) && tgt.hp != 0 && !hidden ? 1 : 0
    } elif (t == 39) {
        return job >= 62 && job < 140 && !down && !hidden ? 1 : 0
    }
    return -1
}

// an effect of it damages or heals (apply function 1 / 17)
def damages_or_heals(ab : Ability2) : bool {
    if (ab.name == "" || ab.name == "-") {
        return false
    }
    for (fx in ab.fx) {
        if (fx.x != 0 && (fx.y == 1 || fx.y == 17)) {
            return true
        }
    }
    return false
}

// the model computes it: an effect damages or heals with an amount
// function 1..4 and a translated condition and hit
def translated_ability(ab : Ability2) : bool {
    if (ab.name == "" || ab.name == "-" || ab.id == 244) {
        return false
    }
    for (fx in ab.fx) {
        let cond_ok = fx.x == 15 || fx.x == 24 || fx.x == 33 || fx.x == 35 || fx.x == 37 || fx.x == 39
        let hit_ok = fx.z == 1 || fx.z == 2 || fx.z == 3 || fx.z == 9
        if (cond_ok && hit_ok && (fx.y == 1 || fx.y == 17) && fx.w >= 1 && fx.w <= 4) {
            return true
        }
    }
    return false
}

// Attack (ability 799); side: as side_of2 counts it or chosen by hand;
// privilege: game variable 369
def fight2(att, tgt : Unit2; side : Side2; privilege : int = 0) : Fight2 {
    return <- action2(att, tgt, read_ability2(ATTACK_ABILITY), side, privilege)
}

// an ability whose amount is function 1 (sub_67E0: Attack, the damage
// spells and techniques, the healing spells); other functions: unsupported
def action2(att, tgt : Unit2; ab : Ability2; side : Side2; privilege : int = 0) : Fight2 {
    var f = Fight2(ability = ab)
    let magick = is_magick2(ab)
    let attack = ab.id == ATTACK_ABILITY
    let turbo = att.support == 855 && ab.mp != 0
    // the effect: the first whose condition holds and that damages or heals
    f.effect = -1
    for (k in range(4)) {
        let fx = ab.fx[k]
        if (f.effect < 0 && fx.x != 0 && (fx.y == 1 || fx.y == 17)) {
            let c = effect_applies(fx.x, ab, att, tgt)
            if (c < 0) {
                f.unsupported = true
                f.mods |> push("effect condition {fx.x} is not translated")
            }
            if (c != 0) {
                f.effect = k
            }
        }
    }
    let fx = f.effect >= 0 ? ab.fx[f.effect] : int4(0)
    let fx_apply = fx.y
    let fx_hit = fx.z
    let fx_amount = fx.w
    let healing = fx_apply == 17                    // F1 with a6: the target's equipment does not count
    f.healing = healing
    if (f.effect < 0) {
        f.unsupported = true
        f.mods |> push("no damage or healing effect applies")
    } elif (fx_amount < 1 || fx_amount > 4 || ab.id == 244) {
        f.unsupported = true
        f.mods |> push("its amount (function {fx_amount}) is not translated")
    }
    // the attacker's Attack / Magick (raw x 10) and its modifiers
    var v0 = att.raw[magick ? 2 : 0] * 10
    if (magick) {
        if (att.support == 853 || att.support == 878 || att.support == 879) {
            scale(v0, 12, att.support_name, f.mods)
        }
    } elif (att.support == 851 || att.support == 877 || att.support == 879) {
        scale(v0, 12, att.support_name, f.mods)
    }
    if (att.support == 869 && att.hp == att.max_hp) {
        scale(v0, 15, "Unscarred", f.mods)
    }
    if (turbo) {
        scale(v0, 15, "Turbo MP", f.mods)
    }
    var cannon = false
    for (it in att.equip) {
        cannon = cannon || (it.id != 0 && it.kind == 19)
    }
    if (magick) {
        if (has_status2(att, 38)) {
            scale(v0, 12, "Magick up", f.mods)
        }
        if (has_status2(att, 39)) {
            scale(v0, 8, "Magick down", f.mods)
        }
    } else {
        if (has_status2(att, 10)) {
            scale(v0, 12, "Berserk", f.mods)
        }
        if (has_status2(att, 36)) {
            scale(v0, 12, "Attack up", f.mods)
        }
        if (has_status2(att, 37)) {
            scale(v0, 8, "Attack down", f.mods)
        }
        if (has_status2(att, 16)) {
            scale(v0, 18, "Focus", f.mods)
        } elif (has_status2(att, 49) && attack && cannon) {
            scale(v0, 18, "Combustion", f.mods)
        }
    }
    f.atk10 = max(v0, 1)
    // the target's Defense / Resistance
    var v3 = tgt.raw[magick ? 3 : 1] * 10
    if (magick) {
        if (tgt.support == 854 || tgt.support == 878 || tgt.support == 879) {
            scale(v3, 12, "target {tgt.support_name}", f.mods)
        }
    } elif (tgt.support == 852 || tgt.support == 877 || tgt.support == 879) {
        scale(v3, 12, "target {tgt.support_name}", f.mods)
    }
    if (tgt.support == 869 && tgt.hp == tgt.max_hp) {
        scale(v3, 15, "target Unscarred", f.mods)
    }
    if (has_status2(tgt, 15)) {
        scale(v3, 12, "target Shield", f.mods)
    }
    if (magick) {
        if (has_status2(tgt, 25)) {
            scale(v3, 13, "target Shell", f.mods)
        }
        if (has_status2(tgt, 42)) {
            scale(v3, 12, "target Resistance up", f.mods)
        }
        if (has_status2(tgt, 43)) {
            scale(v3, 8, "target Resistance down", f.mods)
        }
    } else {
        if (has_status2(tgt, 26)) {
            scale(v3, 13, "target Protect", f.mods)
        }
        if (has_status2(tgt, 40)) {
            scale(v3, 12, "target Defense up", f.mods)
        }
        if (has_status2(tgt, 41)) {
            scale(v3, 8, "target Defense down", f.mods)
        }
    }
    f.def10 = v3
    // the power: the ability's, or (none, or Attack) the weapon's / the
    // job's bare hands with the weapon's element; plus the equipment
    let ws = weapon_slot2(att)
    var power = ab.power
    var weapon_code = 0
    f.element = ab.element
    f.weapon = ab.name
    if (!magick && (power == 0 || attack)) {
        power = att.bare_power
        f.weapon = "Bare hands"
        if (ws >= 0) {
            power = att.equip[ws].bonus[0]
            f.weapon = att.equip[ws].name
            if (f.element == 0) {
                f.element = att.equip[ws].element
            }
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
    }
    if (ws >= 0) {
        weapon_code = att.equip[ws].code
    }
    for (it in att.equip) {
        if (magick ? it.id != 0 : it.id > 288) {
            power += it.bonus[magick ? 2 : 0]
        }
    }
    f.power10 = power * 10
    var armor = 0
    for (it in tgt.equip) {
        if (it.id != 0) {
            armor += it.bonus[magick ? 3 : 1]
        }
    }
    f.armor10 = healing ? 0 : armor * 10
    f.base = f.atk10 * 25 / 100 + f.power10 - (f.def10 * 25 / 100 + f.armor10) / 2
    f.privilege = privilege_damage(privilege, att, tgt)
    f.scaled = f.base * (100 + f.privilege) / 100 / 10 / 2
    var d = f.scaled
    if (turbo) {
        d = d * 3 / 2
    }
    if ((ab.flags & 0x40000u) != 0u && (tgt.reaction == 829 || tgt.reaction == 841 || has_status2(tgt, 58))) {
        d = d * 2
        f.mods |> push("vs a counter x2")
    }
    // the side counts only for abilities by side (the others: x1.5);
    // some jobs (job +50 == 2, Crushatrice and the next) always count as
    // hit at the side, Vigilance always in front
    f.side = side
    f.by_side = by_side2(ab)
    if (f.by_side) {
        if (tgt.job_50 == 2 || tgt.job_id == 137 || tgt.job_id == 138) {
            f.side = Side2.Side
        }
        if (tgt.support == 876) {
            f.side = Side2.Front
        }
        if (f.side == Side2.Side) {
            d = d * 3 / 2
        } elif (f.side == Side2.Back) {
            d = d * 2
        }
    } else {
        d = d * 3 / 2
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
    // amount functions 2 / 3 / 4: the result x2 / x3 / 2, clamped again
    if (fx_amount == 2 || fx_amount == 3 || fx_amount == 4) {
        d = fx_amount == 4 ? d / 2 : d * fx_amount
        d = clamp(d, -999, 999)
        f.mods |> push(fx_amount == 4 ? "effect amount / 2" : "effect amount x{fx_amount}")
    }
    if (has_status2(tgt, 34) && d > 0 && !healing) {
        d = 0
        f.mods |> push("target Bulwark: no damage")
    }
    f.damage = d
    // the hit: script 784, function fx_hit - 1 / 2 / 3: sub_5DD0 (job +41
    // + a bonus - equipment Evasion, divided), 9: 100 (but Elusion)
    for (it in tgt.equip) {
        if (it.id != 0) {
            f.evasion += it.bonus[5]
        }
    }
    var h = 100
    if (fx_hit == 1 || fx_hit == 2 || fx_hit == 3) {
        let bonus = fx_hit == 2 ? 20 : 0
        let divisor = fx_hit == 3 ? 2 : 1
        h = tgt.job_hit + bonus - f.evasion
        if (bonus != 0) {
            f.hit_mods |> push("ability +{bonus}")
        }
        if (privilege >= 6 && privilege <= 10) {
            h += clan_member(att) ? 2 * (privilege - 5) : 0
            h -= clan_member(tgt) ? 2 * (privilege - 5) : 0
        } elif (privilege >= 23 && privilege <= 29) {
            h += clan_member(att) && att.race_id == privilege - 22 ? 2 : 0
            h -= clan_member(tgt) && tgt.race_id == privilege - 22 ? 2 : 0
        }
        if (turbo) {
            h += 15
            f.hit_mods |> push("Turbo MP +15")
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
        if (has_status2(att, 52) && attack && cannon) {
            h += 30
            f.hit_mods |> push("Precision +30")
        }
        if (has_status2(tgt, 57)) {
            h -= 20
            f.hit_mods |> push("target Evasion up -20")
        }
        h = h / divisor
        if (divisor != 1) {
            f.hit_mods |> push("/ {divisor}")
        }
        h = clamp(h, 1, 99)
        for (n in fixed_array<int>(2, 9, 27, 24, 17, 34)) {
            if (has_status2(tgt, n)) {
                h = 100
                f.hit_mods |> push("target {status_name(n)}: 100")
            }
        }
    } elif (fx_hit != 9) {
        f.hit_unsupported = true
        f.hit_mods |> push("hit function {fx_hit} is not translated")
    }
    if (tgt.support == 881 && !elusion_reaches(att, tgt)) {
        h = 0
        f.hit_mods |> push("target Elusion: out of reach")
    }
    f.hit = h
    fill_real(f, att, privilege)
    return <- f
}

// the real use from the forecast (f.hit, f.damage): the hit roll, the
// critical (Attack only: sub_92A0 rolls it for ability 799 alone) and
// the spread
def fill_real(var f : Fight2; att : Unit2; privilege : int) {
    let attack = f.ability.id == ATTACK_ABILITY
    let h = f.hit
    f.spread |> clear()
    f.hit_prob = h >= 100 ? 1.0 : (h <= 0 ? 0.0 : mod10000_le(h * 100))
    f.crit = attack ? crit_chance(privilege, att) : 0
    f.crit_prob = attack ? mod10000_le(f.crit * 100 - 1) : 0.0
    if (f.damage == 0) {
        f.spread |> push(float2(0.0, 1.0))
    } else {
        add_spread(f.spread, f.damage, 1.0 - f.crit_prob)
        if (f.crit_prob > 0.0) {
            add_spread(f.spread, clamp(f.damage * 2, -1998, 1998), f.crit_prob)
        }
    }
    sort(f.spread) $(a, b) => a.x < b.x
    f.dmg_min = int(f.spread[0].x)
    f.dmg_max = int(f.spread[length(f.spread) - 1].x)
    var mean = 0.0
    for (e in f.spread) {
        mean += e.x * e.y
    }
    f.expected = mean * f.hit_prob
}

// a copy of the target facing so that att hits it from `side`
def face_for_side(att, tgt : Unit2; side : Side2) : Unit2 {
    var t = tgt
    for (fc in range(4)) {
        t.facing = fc
        if (side_of2(att, t) == side) {
            return t
        }
    }
    return tgt
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
    if (f.ability.id == ATTACK_ABILITY && (rng_next(bs) % 10000) / 100 < f.crit) {
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
