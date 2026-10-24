options gen2
options indenting = 4

// FFTA2 Fight: the game's forecast (damage and hit chance), fitted to
// ~120 forecasts of the game with edited units (research/ffta2/notes.md,
// "Fight"; the game computes it in a script VM, not in ARM code).
// Stats are in the record's raw units (shown = raw / 4):
//   base   = (2 Atk4 - Def4) / 16, Atk4 = raw Attack + 4 x Attack of the
//            equipment (the weapon, or the job's bare-hand power), Def4 =
//            target's raw Defense + 4 x Defense of its equipment
//   side   x1.5, back x2 (by the target's facing), rounded down
//   element (weapon's) by the target's affinity: weak x1.5, half / 2,
//            immune 0, absorb -, rounded down
//   damage at least 1 (but immune / absorb), at most 999
//   hit    = 100 - target Evasion, 1..99
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

struct Fight2 {
    weapon : string                 // item name or "Bare hands"
    element : int                   // ELEMENT2_NAMES
    atk4 : int
    def4 : int
    base : int                      // before side and element
    side : Side2
    after_side : int
    affinity : int                  // the target's for the element, 1 normal
    damage : int                    // the forecast
    evasion : int
    hit : int                       // the forecast, %
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

// the side of the target the attacker stands at (facings in the field's
// numbering): in front of its facing, behind, or at a side
def side_of2(att, tgt : Unit2) : Side2 {
    let dirx = fixed_array<int>(0, -1, 0, 1)
    let diry = fixed_array<int>(1, 0, -1, 0)
    let dx = att.x - tgt.x
    let dy = att.y - tgt.y
    let offsets = fixed_array<int>(0, 3, 1, 2)
    for (k in range(4)) {
        let d = (tgt.facing + offsets[k]) & 3
        let vx = dirx[d]
        let vy = diry[d]
        let along = vx != 0 ? abs(dy) <= abs(dx) : abs(dx) <= abs(dy)
        if (dx * vx >= 0 && dy * vy >= 0 && along) {
            return k == 0 ? Side2.Front : (k == 3 ? Side2.Back : Side2.Side)
        }
    }
    return Side2.Front
}

// side: the side to use (from side_of2, or chosen by hand)
def fight2(att, tgt : Unit2; side : Side2) : Fight2 {
    var f = Fight2(side = side)
    let ws = weapon_slot2(att)
    var power = att.bare_power
    f.weapon = "Bare hands"
    if (ws >= 0) {
        power = att.equip[ws].bonus[0]
        f.weapon = att.equip[ws].name
        f.element = att.equip[ws].element
    }
    var item_atk = power
    for (k in range(EQUIP_SLOTS)) {
        if (k != ws && att.equip[k].id != 0) {
            item_atk += att.equip[k].bonus[0]
        }
    }
    var item_def = 0
    for (k in range(EQUIP_SLOTS)) {
        if (tgt.equip[k].id != 0) {
            item_def += tgt.equip[k].bonus[1]
        }
    }
    f.atk4 = att.raw[0] + 4 * item_atk
    f.def4 = tgt.raw[1] + 4 * item_def
    f.base = max(0, (2 * f.atk4 - f.def4) / 16)
    f.after_side = side == Side2.Back ? f.base * 2 : (side == Side2.Side ? f.base * 3 / 2 : f.base)
    f.affinity = f.element >= 1 && f.element <= 8 ? tgt.affinity[f.element - 1] : 1
    var d = f.after_side
    if (f.affinity == 0) {
        d = d * 3 / 2
    } elif (f.affinity == 2) {
        d = d / 2
    } elif (f.affinity == 3) {
        d = 0
    } elif (f.affinity == 4) {
        d = -d
    }
    if (f.affinity != 3 && f.affinity != 4) {
        d = clamp(d, 1, 999)
    }
    f.damage = d
    f.evasion = tgt.stat_total[5]
    f.hit = clamp(100 - f.evasion, 1, 99)
    return f
}
