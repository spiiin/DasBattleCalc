options gen2
options indenting = 4

// Final Fantasy Tactics (PSX, USA, SCUS-94221): the battle units of a
// BizHawk Nymashock state (research/fft/notes.md). The battle records are
// an array of 21 x 0x1C0 bytes at 0x801908CC (+0x01 0xFF: an empty slot);
// a record holds the unit's job, level, Brave / Faith, HP / MP, PA / MA /
// Speed, CT, Move / Jump, equipment, tile and its name and job name as
// FFT text. The map's terrain: 8 bytes per tile, as in the map file.
module fft_battle shared public

require gba_mem
require math
require strings
require ../../core/teams.das public
require ../../core/result_try.das
require daslib/strings_boost

let FFT_CODE = "SCUS"
let UNIT_TABLE = 0x801908CCu
let UNIT_SIZE = 0x1C0u
let UNIT_SLOTS = 21
let EQUIP_SLOTS = 7
let EQUIP_LABELS = fixed_array<string>("Head", "Body", "Accessory", "Right hand", "Right shield", "Left hand",
    "Left shield")
// the map's header in the code's data: u32 width, u32 length, ...,
// +0x18 the terrain (8 bytes per tile, 256 tiles per floor)
let MAP_HEADER = 0x800F6860u
// the record's facing (+0x49 & 3): 0 -y, 1 -x, 2 +y, 3 +x - a bow shot
// from +y of Lezales: facing 0 100% (his back), 2 66% (his front), 1 / 3
// 74%; the field numbers them 0 +y, 1 -x, 2 -y, 3 +x (facing_to_field)
let FACING_NAMES = fixed_array<string>("-y", "-x", "+y", "+x")
let private FACING_FIELD = fixed_array<int>(2, 1, 0, 3)

// the record's facing <-> the field's (the same swap both ways)
def facing_to_field(f : int) : int {
    return FACING_FIELD[f & 3]
}
// the unit taking its turn: a pointer to its record (also at 0x8016C5E8;
// 0x80192D94 is the last unit that acted)
let ACTIVE_UNIT = 0x8016D004u
// statuses: 5 bytes at +0x58, 40 bits in FFT's order (the bit of byte k:
// 0x80 first); timers from +0x5D
let STATUS_NAMES = fixed_array<string>(
    "?", "Crystal", "Dead", "Undead", "Charging", "Jump", "Defending", "Performing",
    "Petrify", "Invite", "Darkness", "Confusion", "Silence", "Blood Suck", "Dark Evil Looking", "Treasure",
    "Oil", "Float", "Reraise", "Transparent", "Berserk", "Chicken", "Frog", "Critical",
    "Poison", "Regen", "Protect", "Shell", "Haste", "Slow", "Stop", "Wall",
    "Faith", "Innocent", "Charm", "Sleep", "Don't Move", "Don't Act", "Reflect", "Death Sentence")
let ST_DEAD = 2
let ST_PETRIFY = 8
let ST_CRYSTAL = 1
let ST_HASTE = 28
let ST_SLOW = 29
let ST_STOP = 30
let ST_CHARGING = 4
let ZODIAC_NAMES = fixed_array<string>("Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra", "Scorpio",
    "Sagittarius", "Capricorn", "Aquarius", "Pisces", "Serpentarius")

// FFT text: 0..9, A..Z, a..z, 0xFA space, 0x42 '+', 0xFE the end;
// 0xD0..0xDA start a two-byte character: D1 1D '-', DA 76 '''
def fft_text(at : uint; max_len : int) : string {
    var res = ""
    var i = 0
    while (i < max_len) {
        let c = int(gba_read8(at + uint(i)))
        i++
        if (c == 0xFE || c == 0xFF) {
            break
        } elif (c < 10) {
            res += to_char('0' + c)
        } elif (c < 36) {
            res += to_char('A' + c - 10)
        } elif (c < 62) {
            res += to_char('a' + c - 36)
        } elif (c == 0xFA) {
            res += " "
        } elif (c == 0x42) {
            res += "+"
        } elif (c >= 0xD0 && c <= 0xDA) {
            let d = int(gba_read8(at + uint(i)))
            i++
            res += c == 0xD1 && d == 0x1D ? "-" : (c == 0xDA && d == 0x76 ? "'" : "?")
        } else {
            res += "?"
        }
    }
    return res
}

enum TurnEnd {
    MoveAndAct
    ActOnly
    MoveOnly
    Wait
}

struct FftUnit {
    @readonly name : string
    @readonly job : string
    @readonly record : uint
    @hide slot : int                // 0..20 in the battle table
    @hide job_id : int              // +0x03
    @hide sprite_set : int          // +0x00
    @readonly level : int           // +0x22
    @readonly exp : int             // +0x21
    @caption = "Brave" @min = 0 brave : int     // +0x24 (+0x23 the original)
    @caption = "Faith" @min = 0 faith : int     // +0x26 (+0x25)
    @caption = "HP" @min = 0 hp : int           // +0x28 u16
    @caption = "Max HP" @min = 1 max_hp : int   // +0x2A
    @caption = "MP" @min = 0 mp : int           // +0x2C
    @caption = "Max MP" @min = 0 max_mp : int   // +0x2E
    @caption = "PA" pa : int                    // +0x36 (+0x30 the original)
    @caption = "MA" ma : int                    // +0x37 (+0x31)
    @caption = "Speed" speed : int              // +0x38 (+0x32)
    @caption = "CT" ct : int                    // +0x39
    @caption = "Move" move : int                // +0x3A
    @caption = "Jump" jump : int                // +0x3B
    @caption = "Assumed turn" assumed : TurnEnd
    @caption = "Position" @readonly position : string
    @hide x : int                   // +0x47
    @hide y : int                   // +0x48
    @hide facing : int              // +0x49 bits 0..1: 0 -y, 1 -x, 2 +y, 3 +x; bit 7 the upper floor
    @hide upper : bool
    @hide team : int                // TEAM_*: +0x05 bit 4 an enemy
    @hide flags : int               // +0x05
    @hide palette : int             // +0x04
    @hide equip : int[EQUIP_SLOTS]  // +0x1A.. item ids, 0xFF none
    @hide status : uint8[5]         // +0x58
    @hide stop_timer : int          // +0x63: ticks left of Stop
    @hide charge : int              // +0x15D: ticks left of the ability being charged, 255 none
    @hide charge_ability : int      // +0x170 u16: that ability (+0x16F its skillset)
    @hide gender : int              // +0x06: 0x80 male, 0x40 female, 0x20 monster
    @hide zodiac : int              // +0x09 high nibble: 0 Aries .. 11 Pisces, 12 Serpentarius
    @hide primary : int             // +0x12 skillset
    @hide secondary : int           // +0x13
    @hide reaction : int            // +0x14 u16 ability id (0x1BF Weapon Guard)
    @hide support : int             // +0x16 u16
    @hide movement : int            // +0x18 u16
    @hide skills : uint8[11]        // +0x8B: the active R/S/M as bits (has_ability)
    @hide elements : uint8[5]       // +0x6D: absorb, cancel, half, weak, strengthen (element bits)
    @caption = "Zodiac" @readonly zodiac_text : string
    @caption = "Abilities" @readonly ability_text : string
    @caption = "Elements" @readonly element_info : string
    @hide active : bool             // taking its turn (its record's CT reads 0 meanwhile)
    @caption = "Status" @readonly status_text : string
}

def has_status(u : FftUnit; n : int) : bool {
    return n >= 0 && n < 40 && (uint(u.status[n >> 3]) & (0x80u >> uint(n & 7))) != 0u
}

// the battle sprite (BATTLE.BIN's table): +0x00 below 0x80; 0x80 / 0x81
// a generic male / female - by the job, 0x60 + 2 x (job - 0x4A) (Squire
// MINA_M, Chemist ITEM_M, Knight KNIGHT_M, Archer YUMI_M, ...) + 1 female
def unit_sprite(u : FftUnit) : int {
    if (u.sprite_set < 0x80) {
        return u.sprite_set
    }
    if (u.job_id >= 0x4A && u.job_id <= 0x5D) {
        return 0x60 + (u.job_id - 0x4A) * 2 + ((u.sprite_set & 1) != 0 || (u.gender & 0x40) != 0 ? 1 : 0)
    }
    return -1
}

// The active reactions, supports and movement abilities - the set ones
// and the innate (a Chemist's Throw Item): bits from the record's +0x8B,
// 0x80 first - reactions 0x1A6.., supports 0x1C6.. (+0x8F), movement
// 0x1E6.. (+0x93). The game's forecasts follow these bits, not the ids at
// +0x14..+0x18 (an Attack UP id alone changed nothing, its bit did).
def has_ability(u : FftUnit; id : int) : bool {
    let i = id - 0x1A6
    return i >= 0 && i < 88 && (uint(u.skills[i >> 3]) & (0x80u >> uint(i & 7))) != 0u
}

// elements: 0x80 Fire, 0x40 Lightning, 0x20 Ice, 0x10 Wind, 0x08 Earth,
// 0x04 Water, 0x02 Holy, 0x01 Dark; the unit's affinities (from its
// equipment and job, as the game keeps them in the record)
let EL_ABSORB = 0
let EL_CANCEL = 1
let EL_HALF = 2
let EL_WEAK = 3
let EL_STRENGTHEN = 4
let ELEMENT_NAMES = fixed_array<string>("Fire", "Lightning", "Ice", "Wind", "Earth", "Water", "Holy", "Dark")

def has_element(u : FftUnit; kind : int; element : int) : bool {
    return (int(u.elements[kind]) & element) != 0
}

def element_text(element : int) : string {
    var names : array<string>
    for (k in range(8)) {
        if ((element & (0x80 >> k)) != 0) {
            names |> push(ELEMENT_NAMES[k])
        }
    }
    return length(names) > 0 ? join(names, ", ") : "none"
}

def unit_present(rec : uint) : bool {
    return gba_read8(rec + 0x01u) != 0xFFu && gba_read8(rec + 0x12Cu) != 0xFFu
}

def read_unit(slot : int) : FftUnit {
    let rec = UNIT_TABLE + uint(slot) * UNIT_SIZE
    var u = FftUnit(record = rec, slot = slot)
    u.sprite_set = int(gba_read8(rec))
    u.job_id = int(gba_read8(rec + 0x03u))
    u.palette = int(gba_read8(rec + 0x04u))
    u.flags = int(gba_read8(rec + 0x05u))
    u.gender = int(gba_read8(rec + 0x06u))
    u.zodiac = int(gba_read8(rec + 0x09u)) >> 4
    u.primary = int(gba_read8(rec + 0x12u))
    u.secondary = int(gba_read8(rec + 0x13u))
    u.reaction = int(gba_read16(rec + 0x14u))
    u.support = int(gba_read16(rec + 0x16u))
    u.movement = int(gba_read16(rec + 0x18u))
    for (k in range(11)) {
        u.skills[k] = uint8(gba_read8(rec + 0x8Bu + uint(k)))
    }
    for (k in range(5)) {
        u.elements[k] = uint8(gba_read8(rec + 0x6Du + uint(k)))
    }
    u.team = (u.flags & 0x10) != 0 ? TEAM_ENEMY : TEAM_PLAYER
    for (k in range(EQUIP_SLOTS)) {
        u.equip[k] = int(gba_read8(rec + 0x1Au + uint(k)))
    }
    u.exp = int(gba_read8(rec + 0x21u))
    u.level = int(gba_read8(rec + 0x22u))
    u.brave = int(gba_read8(rec + 0x24u))
    u.faith = int(gba_read8(rec + 0x26u))
    u.hp = int(gba_read16(rec + 0x28u))
    u.max_hp = int(gba_read16(rec + 0x2Au))
    u.mp = int(gba_read16(rec + 0x2Cu))
    u.max_mp = int(gba_read16(rec + 0x2Eu))
    u.pa = int(gba_read8(rec + 0x36u))
    u.ma = int(gba_read8(rec + 0x37u))
    u.speed = int(gba_read8(rec + 0x38u))
    u.ct = int(gba_read8(rec + 0x39u))
    u.move = int(gba_read8(rec + 0x3Au))
    u.jump = int(gba_read8(rec + 0x3Bu))
    u.x = int(gba_read8(rec + 0x47u))
    u.y = int(gba_read8(rec + 0x48u))
    let f = int(gba_read8(rec + 0x49u))
    u.facing = f & 3
    u.upper = (f & 0x80) != 0
    for (k in range(5)) {
        u.status[k] = uint8(gba_read8(rec + 0x58u + uint(k)))
    }
    u.stop_timer = int(gba_read8(rec + 0x63u))
    u.charge = int(gba_read8(rec + 0x15Du))
    u.charge_ability = int(gba_read16(rec + 0x170u))
    u.active = gba_read32(ACTIVE_UNIT) == rec
    u.name = fft_text(rec + 0x12Cu, 16)
    u.job = fft_text(rec + 0x13Cu, 20)
    update_unit(u)
    return u
}

def update_unit(var u : FftUnit) {
    u.position = "{u.x}, {u.y}{u.upper ? " (upper)" : ""}, facing {FACING_NAMES[u.facing & 3]}"
    var names : array<string>
    for (n in range(1, 40)) {
        if (has_status(u, n)) {
            names |> push(n == ST_STOP ? "Stop ({u.stop_timer})" : STATUS_NAMES[n])
        }
    }
    u.status_text = length(names) > 0 ? join(names, ", ") : "none"
    let sex = (u.gender & 0x20) != 0 ? "monster" : ((u.gender & 0x40) != 0 ? "female" : "male")
    u.zodiac_text = "{u.zodiac < 13 ? ZODIAC_NAMES[u.zodiac] : "?"}, {sex}"
    var abil : array<string>
    for (id in range(0x1A6, 0x1FE)) {
        if (has_ability(u, id)) {
            abil |> push(ability_name(id))
        }
    }
    u.ability_text = length(abil) > 0 ? join(abil, ", ") : "none"
    let kinds = fixed_array<string>("absorbs", "cancels", "halves", "weak to", "strengthens")
    var els : array<string>
    for (k in range(5)) {
        if (int(u.elements[k]) != 0) {
            els |> push("{kinds[k]} {element_text(int(u.elements[k]))}")
        }
    }
    u.element_info = length(els) > 0 ? join(els, "; ") : "none"
}

// the battle's units in slot order; "" or the error
def read_battle(var units : array<FftUnit>) : string {
    units |> clear()
    ensure(gba_has_state(), "no state loaded")
    ensure(gba_state_is_psx(), "not a PSX (Nymashock) state")
    for (slot in range(UNIT_SLOTS)) {
        if (unit_present(UNIT_TABLE + uint(slot) * UNIT_SIZE)) {
            units |> push(read_unit(slot))
        }
    }
    ensure(length(units) > 0, "no battle in this state")
    return ""
}

// ------------------------------------------------------------ map

struct FftMap {
    w : int
    h : int
    height : array<int>             // the tile's height in half units (x 2: slopes are halves), -1 none
    upper : array<int>              // the upper floor's, -1 none
    flags : array<int>              // +6: bit 1 - not a target (the tower's top in MAP056)
    depth : array<int>              // +3 bits 5..7: water's depth in height steps
}

// a tile: +2 the height, +3 bits 0..4 the slope's height, +0 bits 0..5
// the surface; the shown height = height + slope / 2
def private tile_height2(t : uint) : int {
    return int(gba_read8(t + 2u)) * 2 + int(gba_read8(t + 3u) & 31u)
}

def read_map(var m : FftMap) : bool {
    m = FftMap()
    let w = int(gba_read32(MAP_HEADER))
    let h = int(gba_read32(MAP_HEADER + 4u))
    let tiles = gba_read32(MAP_HEADER + 0x18u)
    if (w < 1 || h < 1 || w * h > 256 || tiles < 0x80000000u || tiles >= 0x80200000u) {
        return false
    }
    m.w = w
    m.h = h
    for (i in range(w * h)) {
        let t = tiles + uint(i) * 8u
        m.height |> push(tile_height2(t))
        m.flags |> push(int(gba_read8(t + 6u)))
        m.depth |> push(int(gba_read8(t + 3u)) >> 5)
        let u = tiles + 256u * 8u + uint(i) * 8u
        let any = gba_read32(u) != 0u || gba_read32(u + 4u) != 0u
        m.upper |> push(any ? tile_height2(u) : -1)
    }
    return true
}

// the shown height (in tiles' units, halves) of a tile
def map_height(m : FftMap; x, y : int) : float {
    return x >= 0 && y >= 0 && x < m.w && y < m.h ? float(m.height[y * m.w + x]) * 0.5 : -1.0
}

// ------------------------------------------------------------ text tables

// The battle text in RAM: lists of names one after another (0xFE ends a
// name) from id 0 (empty), found by their first two names: the items by
// "Dagger", "Mythril Knife" (1, 2), the abilities by "Cure", "Cure 2".
struct private TextList {
    serial : uint
    names : array<string>
}

var private item_names : TextList
var private ability_names : TextList

def private find_text(s : array<uint8>) : uint {
    var a = 0x80100000u
    while (a < 0x801F0000u) {
        if (gba_read8(a) == uint(s[0])) {
            var ok = true
            for (i in range(1, length(s))) {
                if (gba_read8(a + uint(i)) != uint(s[i])) {
                    ok = false
                    break
                }
            }
            if (ok) {
                return a
            }
        }
        a++
    }
    return 0u
}

// FFT text of a plain string (digits, letters, spaces)
def private fft_encode(s : string) : array<uint8> {
    var res : array<uint8>
    for (c in s) {
        res |> push(uint8(c >= '0' && c <= '9' ? c - '0' : (c >= 'A' && c <= 'Z' ? c - 'A' + 10
            : (c >= 'a' && c <= 'z' ? c - 'a' + 36 : 250))))
    }
    return <- res
}

def private text_list(var list : TextList; first, second : string; count : int; id : int) : string {
    if (list.serial != gba_state_serial()) {
        list.serial = gba_state_serial()
        list.names |> clear()
        var anchor : array<uint8>
        anchor |> push(uint8(0xFE))
        for (c in fft_encode(first)) {
            anchor |> push(c)
        }
        anchor |> push(uint8(0xFE))
        for (c in fft_encode(second)) {
            anchor |> push(c)
        }
        anchor |> push(uint8(0xFE))
        let at = find_text(anchor)
        if (at != 0u) {
            var a = at + 1u
            list.names |> push("")
            for (_ in range(1, count)) {
                list.names |> push(fft_text(a, 24))
                while (gba_read8(a) != 0xFEu) {
                    a++
                }
                a++
            }
        }
    }
    if (id <= 0) {
        return ""
    }
    return id < length(list.names) ? list.names[id] : "#{id}"
}

def item_name(id : int) : string {
    return id == 0xFF ? "" : text_list(item_names, "Dagger", "Mythril Knife", 256, id)
}

def ability_name(id : int) : string {
    return text_list(ability_names, "Cure", "Cure 2", 512, id)
}

// ------------------------------------------------------------ export

// Puts a unit into the edit copy of RAM (gba_edit_begin): the stats the
// calculator edits (the inspector), not the position. Brave / Faith set the original and the current;
// PA / MA / Speed the current (+0x36..) and move the original (+0x30..)
// by the same amount, so a buff seen in the state stays.
def write_unit(u : FftUnit) {
    let r = u.record
    gba_edit8(r + 0x23u, uint(clamp(u.brave, 0, 100)))
    gba_edit8(r + 0x24u, uint(clamp(u.brave, 0, 100)))
    gba_edit8(r + 0x25u, uint(clamp(u.faith, 0, 100)))
    gba_edit8(r + 0x26u, uint(clamp(u.faith, 0, 100)))
    gba_edit16(r + 0x28u, uint(clamp(u.hp, 0, 999)))
    gba_edit16(r + 0x2Au, uint(clamp(u.max_hp, 1, 999)))
    gba_edit16(r + 0x2Cu, uint(clamp(u.mp, 0, 999)))
    gba_edit16(r + 0x2Eu, uint(clamp(u.max_mp, 0, 999)))
    let stats = fixed_array<int>(u.pa, u.ma, u.speed)
    for (k in range(3)) {
        let old_cur = int(gba_read8(r + 0x36u + uint(k)))
        let old_orig = int(gba_read8(r + 0x30u + uint(k)))
        gba_edit8(r + 0x36u + uint(k), uint(clamp(stats[k], 0, 99)))
        gba_edit8(r + 0x30u + uint(k), uint(clamp(old_orig + stats[k] - old_cur, 0, 99)))
    }
    gba_edit8(r + 0x39u, uint(clamp(u.ct, 0, 255)))
    gba_edit8(r + 0x3Au, uint(clamp(u.move, 0, 255)))
    gba_edit8(r + 0x3Bu, uint(clamp(u.jump, 0, 255)))
    // not the tile (+0x47 / +0x48) nor the facing: the game takes them
    // (its Move range follows), but the sprite stays where it was - its
    // object keeps its own position (not found yet)
}

// Writes the loaded BizHawk state with the units to path. "" or the error.
def export_battle(units : array<FftUnit>; path : string) : string {
    if (!gba_has_state()) {
        return "no state loaded"
    }
    gba_edit_begin()
    for (u in units) {
        write_unit(u)
    }
    return gba_save_state(path)
}
