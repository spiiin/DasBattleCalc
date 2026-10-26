options gen2
options indenting = 4

// What Final Fantasy Tactics (PSX) and The War of the Lions (its PSP port,
// the same battle engine) share: names of the game's tables, the way a
// turn ends and its cost, the Explore vocabulary.
module fft_common shared public

require daslib/match

let ZODIAC_NAMES = fixed_array<string>("Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra", "Scorpio",
    "Sagittarius", "Capricorn", "Aquarius", "Pisces", "Serpentarius")
// the elements: bit 0x80 >> n of the element bytes
let FFT_ELEMENT_NAMES = fixed_array<string>("Fire", "Lightning", "Ice", "Wind", "Earth", "Water", "Holy", "Dark")
// the record's facing (PSX +0x49 & 3, PSP +0x51 low bits): 0 -y, 1 -x,
// 2 +y, 3 +x; the field numbers them 0 +y, 1 -x, 2 -y, 3 +x
// (facing_to_field). Checked by the forecasts: a bow shot from +y of
// Lezales hits 100% at facing 0 (his back), 66% at 2 (his front), 74% at
// 1 / 3; WotL forecast1.txt / forecast6.txt, the attacker on each axis.
let FFT_FACING_NAMES = fixed_array<string>("-y", "-x", "+y", "+x")
// the equipment slots of a unit record (WotL: +0x1A, u16 each)
let FFT_SLOT_NAMES = fixed_array<string>("Head", "Body", "Accessory", "Right hand", "Right shield", "Left hand",
    "Left shield")

// how a turn ends: the CT it leaves (turn_cost)
enum TurnEnd {
    MoveAndAct
    ActOnly
    MoveOnly
    Wait
}

def turn_cost(how : TurnEnd) : int {
    return match (how) {
        TurnEnd.MoveAndAct => 100
        TurnEnd.Wait => 60
        _ => 80
    }
}

// Explore: the sides, the columns of every point, the generators, the
// names of the examples
let FFT_SIDE_LABELS = fixed_array<string>("Auto", "Front", "Side", "Back")
let FFT_METRICS = fixed_array<string>("damage", "healing", "dmg_min", "dmg_max", "hit", "crit", "expected", "reach",
    "distance", "mp_cost", "xa", "ya", "zodiac_rel")
let FFT_GENERATORS = fixed_array<string>("jobs", "weapons", "supports", "actions", "sides")
let FFT_EXPLORE_NAMES = fixed_array<string>("Damage by PA and Brave", "Every weapon", "Side and Protect",
    "Fire by MA and Faith", "Every action")

// a unit's reaction (k 0), support (1) or movement (2) ability
def rsm_of(u; k : int) : int {
    return k == 0 ? u.reaction : (k == 1 ? u.support : u.movement)
}

def set_rsm(var u; k, id : int) {
    if (k == 0) {
        u.reaction = id
    } elif (k == 1) {
        u.support = id
    } else {
        u.movement = id
    }
}
