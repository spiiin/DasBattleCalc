options gen2
options indenting = 4

// FFT: The War of the Lions: the battle units of a PPSSPP state. 21
// records of 0x1E8 bytes at 0x092E5CB4 (the PSX "Battle Stats" with u16
// equipment and a few fields moved; research/fftwotl/notes.md).
module fftwotl_battle shared public

require gba_mem
require math
require strings
require ../../core/teams.das public
require ../../core/result_try.das
require fftwotl_data
require ../../core/util.das
require ../fftcore/fft_common.das public

let UNIT_BASE_W = 0x092E5CB4u
let UNIT_SIZE_W = 0x1E8u
let UNIT_SLOTS_W = 21

// learned abilities (record +0xA3): 3 bytes per job - the action
// abilities of its skillset (16 bits, 0x80 of the first byte = the first
// ability), the reaction / support / movement abilities (6 bits) - for
// the base job (Squire's Fundaments, a story character's own skillset),
// Chemist .. Mime (skillsets 6 .. 24), Dark Knight (Darkness), Onion Knight
let LEARN_JOBS_W = 22
let LEARNED_W_SIZE = 66
let LEARN_JOB_NAMES = fixed_array<string>("Base", "Chemist", "Knight", "Archer", "Monk", "White Mage", "Black Mage",
    "Time Mage", "Summoner", "Thief", "Orator", "Mystic", "Geomancer", "Dragoon", "Samurai", "Ninja",
    "Arithmetician", "Bard", "Dancer", "Mime", "Dark Knight", "Onion Knight")

// how a turn ends (the CT it costs: 100 moved and acted, 80 one of them,
// 60 neither)
struct UnitW {
    @readonly name : string
    @readonly job : string
    @hide job_id : int              // +0x03
    @hide identity : int            // +0x00: 0x80 generic male, 0x81 female, 0x82 monster, else a story character
    @hide palette : int             // +0x04: the sprite palette (0..7)
    @hide sheet : int               // +0x181: the battle sprite sheet
    @readonly slot : int            // the record's number
    @readonly record : uint
    @caption = "Level" @min = 1 @max = 99 level : int
    @caption = "Exp" @min = 0 @max = 99 exp : int
    @caption = "Brave" @min = 0 @max = 100 brave : int
    @caption = "Faith" @min = 0 @max = 100 faith : int
    @caption = "HP" @min = 0 hp : int
    @caption = "Max HP" @min = 1 max_hp : int
    @caption = "MP" @min = 0 mp : int
    @caption = "Max MP" @min = 0 max_mp : int
    @caption = "CT" @min = 0 @max = 255 ct : int
    @caption = "Assumed turn" assumed : TurnEnd
    @caption = "Zodiac" @readonly zodiac : string
    @caption = "Team byte" @readonly team_byte : int    // +0x05: 0x10 red (enemy), 0x08 controlled by the player, 0x04 immortal
    @caption = "Position" @readonly position : string
    @hide team : int                // TEAM_*
    @hide gender : int              // +0x06: 0x80 male, 0x40 female, 0x20 monster
    @hide zodiac_id : int           // +0x09 >> 4
    @hide on_field : bool           // +0x2E != 0 (not "on the field": see read_battle_w)
    @hide active : bool             // +0x1AA: it is this unit's turn (its CT already paid 100)
    @hide raw : int[3]              // +0x38: PA, MA, Speed without the equipment
    @hide bonus : int[3]            // +0x3B: from the equipment
    @hide pa : int                  // +0x3E.. current (raw + bonus)
    @hide ma : int
    @hide sp : int
    @hide move : int                // +0x42
    @hide jump : int                // +0x43
    @hide wp : int[2]               // +0x44: right, left hand weapon power (as the game shows it)
    @hide w_ev : int[2]             // +0x46
    @hide a_ev : int                // +0x48: physical evade of the accessory
    @hide s_ev : int[2]             // +0x49: left, right shield (physical)
    @hide c_ev : int                // +0x4B: class evade
    @hide am_ev : int               // +0x4C: magic evade of the accessory
    @hide sm_ev : int[2]            // +0x4D: left, right shield (magic)
    @hide x : int                   // +0x4F
    @hide y : int                   // +0x50
    @hide high : bool               // +0x51 bit 7: on the upper level of the tile
    @hide facing : int              // +0x51 & 3
    @hide innate_st : uint8[5]      // +0x58 statuses always on
    @hide immune : uint8[5]         // +0x5D
    @hide status : uint8[5]         // +0x62 current
    @hide status_ct : uint8[16]     // +0x67: Poison .. Doom clocks
    @hide absorb : int              // +0x77 elements
    @hide cancel : int
    @hide half : int
    @hide weak : int
    @hide strengthen : int
    @hide primary : int             // +0x12 skillset
    @hide secondary : int           // +0x13
    @hide reaction : int            // +0x14 ability
    @hide support : int             // +0x16
    @hide movement : int            // +0x18
    @hide innate : int[4]           // +0x0A abilities always on (the job's)
    @hide learned : uint8[LEARNED_W_SIZE]  // +0xA3, LEARN_JOB_NAMES x 3 bytes
    @hide rsm_mask : uint8[11]      // +0x95: the abilities in effect - reactions (4 bytes, 0x1A6 + n),
                                    // supports (4, 0x1C6 + n), movement (3, 0x1E6 + n), 0x80 first
    @hide items : int[7]            // +0x1A, SLOT_* (0xFF none)
    @hide equip : ItemW[7]
}

def facing_to_field(f : int) : int {
    return (f & 1) != 0 ? f & 3 : 2 - (f & 3)       // the field: 0 +y, 1 -x, 2 -y, 3 +x
}

def team_of_w(team_byte : int) : int {
    if ((team_byte & 0x30) == 0x10) {
        return TEAM_ENEMY
    }
    // a unit of our side the player does not control (bit 0x08) is a guest
    return (team_byte & 0x30) == 0 && (team_byte & 0x08) != 0 ? TEAM_PLAYER : TEAM_GUEST
}

def has_status_w(u : UnitW; n : int) : bool {
    return status_bit(u.status, n) || status_bit(u.innate_st, n)
}

// a reaction / support / movement ability in effect: the record's bit
// masks (+0x95), as the game checks them - the ids at +0x14..0x18 alone do
// not change a forecast (the FFT PSX battle code, same engine)
def has_ability_w(u : UnitW; id : int) : bool {
    let n = id - 0x1A6
    if (n < 0 || n >= 88) {
        return false
    }
    return msb_bit(u.rsm_mask, n)
}

// the masks again from the job's innate abilities and the chosen
// reaction / support / movement (after an edit in the inspector)
def rebuild_rsm_mask(var u : UnitW) {
    for (k in range(11)) {
        u.rsm_mask[k] = uint8(0)
    }
    for (id in [u.innate[0], u.innate[1], u.innate[2], u.innate[3], u.reaction, u.support, u.movement]) {
        let n = id - 0x1A6
        if (n >= 0 && n < 88) {
            set_msb_bit(u.rsm_mask, n, true)
        }
    }
}

// the stats the game keeps (current PA / MA / Speed, Move, Jump, evades)
// again from the job, the equipment and its attributes, after an edit
def recompute_unit_w(var u : UnitW) {
    let j = read_job_w(u.job_id)
    for (k in range(7)) {
        u.equip[k] = read_item_w(u.items[k])
    }
    var b = int3(0, 0, 0)
    var mv = 0
    var jp = 0
    for (k in range(7)) {
        b += int3(u.equip[k].pa, u.equip[k].ma, u.equip[k].sp)
        mv += u.equip[k].move
        jp += u.equip[k].jump
    }
    u.bonus[0] = b.x
    u.bonus[1] = b.y
    u.bonus[2] = b.z
    u.pa = u.raw[0] + b.x
    u.ma = u.raw[1] + b.y
    u.sp = u.raw[2] + b.z
    if (j.id != 0) {
        u.move = j.move + mv
        u.jump = j.jump + jp
        u.c_ev = j.c_ev
    }
    for (h in range(2)) {
        let w = u.equip[h == 0 ? SLOT_RIGHT : SLOT_LEFT]
        u.wp[h] = is_weapon_w(w) ? w.wp : 0
        u.w_ev[h] = is_weapon_w(w) ? w.w_ev : 0
    }
    let ls = u.equip[SLOT_LEFT_SHIELD]
    let rs = u.equip[SLOT_RIGHT_SHIELD]
    u.s_ev[0] = ls.p_ev
    u.s_ev[1] = rs.p_ev
    u.sm_ev[0] = ls.m_ev
    u.sm_ev[1] = rs.m_ev
    u.a_ev = u.equip[SLOT_ACCESSORY].p_ev
    u.am_ev = u.equip[SLOT_ACCESSORY].m_ev
    u.position = "{u.x}, {u.y}{u.high ? " (upper)" : ""}, facing {FFT_FACING_NAMES[u.facing & 3]}"
}

def read_unit_w(slot : int) : UnitW {
    let r = UNIT_BASE_W + uint(slot) * UNIT_SIZE_W
    var u = UnitW(slot = slot, record = r)
    u.identity = int(gba_read8(r))
    u.palette = int(gba_read8(r + 4u))
    u.sheet = int(gba_read8(r + 0x181u))
    u.job_id = int(gba_read8(r + 0x03u))
    u.job = job_name_w(u.job_id)
    u.team_byte = int(gba_read8(r + 0x05u))
    u.team = team_of_w(u.team_byte)
    u.gender = int(gba_read8(r + 0x06u))
    u.zodiac_id = int(gba_read8(r + 0x09u)) >> 4
    u.zodiac = u.zodiac_id < length(ZODIAC_NAMES) ? ZODIAC_NAMES[u.zodiac_id] : "?"
    for (k in range(4)) {
        u.innate[k] = int(gba_read16(r + 0x0Au + uint(k) * 2u))
    }
    u.primary = int(gba_read8(r + 0x12u))
    u.secondary = int(gba_read8(r + 0x13u))
    u.reaction = int(gba_read16(r + 0x14u))
    u.support = int(gba_read16(r + 0x16u))
    u.movement = int(gba_read16(r + 0x18u))
    for (k in range(7)) {
        u.items[k] = int(gba_read16(r + 0x1Au + uint(k) * 2u))
    }
    u.exp = int(gba_read8(r + 0x28u))
    u.level = int(gba_read8(r + 0x29u))
    u.brave = int(gba_read8(r + 0x2Bu))
    u.faith = int(gba_read8(r + 0x2Du))
    u.on_field = gba_read8(r + 0x2Eu) != 0u
    u.hp = int(gba_read16(r + 0x30u))
    u.max_hp = int(gba_read16(r + 0x32u))
    u.mp = int(gba_read16(r + 0x34u))
    u.max_mp = int(gba_read16(r + 0x36u))
    for (k in range(3)) {
        u.raw[k] = int(gba_read8(r + 0x38u + uint(k)))
    }
    u.ct = int(gba_read8(r + 0x41u))
    u.x = int(gba_read8(r + 0x4Fu))
    u.y = int(gba_read8(r + 0x50u))
    let hf = int(gba_read8(r + 0x51u))
    u.high = (hf & 0x80) != 0
    u.facing = hf & 3
    u.innate_st = read_statuses(r + 0x58u)
    u.immune = read_statuses(r + 0x5Du)
    u.status = read_statuses(r + 0x62u)
    for (k in range(16)) {
        u.status_ct[k] = uint8(gba_read8(r + 0x67u + uint(k)))
    }
    u.absorb = int(gba_read8(r + 0x77u))
    u.cancel = int(gba_read8(r + 0x78u))
    u.half = int(gba_read8(r + 0x79u))
    u.weak = int(gba_read8(r + 0x7Au))
    u.strengthen = int(gba_read8(r + 0x7Bu))
    for (k in range(LEARNED_W_SIZE)) {
        u.learned[k] = uint8(gba_read8(r + 0xA3u + uint(k)))
    }
    for (k in range(11)) {
        u.rsm_mask[k] = uint8(gba_read8(r + 0x95u + uint(k)))
    }
    u.active = gba_read8(r + 0x1AAu) != 0u
    u.name = wotl_text(r + 0x14Eu, 16)
    if (u.name == "") {
        u.name = u.job
    }
    u.assumed = TurnEnd.MoveAndAct
    recompute_unit_w(u)
    // the game's own current stats and Move / Jump / C-EV (they include
    // what the model does not know, e.g. Move+ abilities)
    u.pa = int(gba_read8(r + 0x3Eu))
    u.ma = int(gba_read8(r + 0x3Fu))
    u.sp = int(gba_read8(r + 0x40u))
    u.move = int(gba_read8(r + 0x42u))
    u.jump = int(gba_read8(r + 0x43u))
    u.c_ev = int(gba_read8(r + 0x4Bu))
    return u
}

// The units in battle: records with an ENTD slot (+0x01 != 0xFF), a level
// and max HP. (+0x2E is not "on the field": in the Gariland battle only the
// unit at its turn has it, the other four of the party 0.)
def read_battle_w(var units : array<UnitW>) : string {
    units |> clear()
    ensure(gba_has_state(), "no state loaded")
    ensure(gba_state_is_psp(), "not a PSP (PPSSPP) state")
    ensure(is_wotl_state(), "not FFT: The War of the Lions (USA, ULUS10297)")
    for (slot in range(UNIT_SLOTS_W)) {
        let r = UNIT_BASE_W + uint(slot) * UNIT_SIZE_W
        let level = gba_read8(r + 0x29u)
        let max_hp = gba_read16(r + 0x32u)
        if (level < 1u || level > 99u || max_hp < 1u || max_hp > 999u || gba_read8(r + 0x01u) == 0xFFu) {
            continue
        }
        units |> push(read_unit_w(slot))
    }
    ensure(length(units) > 0, "no battle in this state")
    return ""
}

// ------------------------------------------------------------ map

// The battle map: tiles of 8 bytes (the GNS terrain format) at 0x092E8530
// by y * width + x, the upper level 0x800 later; the size at 0x093EBB6C
// (height, rows) and 0x093EBB6D (width) - the code of the game reads them.
// Tile: +0 surface type (low 6 bits), +2 height, +3 slope height (low 5
// bits) and depth (high 3: water), +4 slope type. Checked: the heights the
// game's cursor shows on five tiles of the first battle.
let MAP_TILES_W = 0x092E8530u
let MAP_SIZE_W = 0x093EBB6Cu

struct MapW {
    w : int
    h : int
    height : array<int>             // in h (the tile's height byte), lower level
    slope : array<int>              // slope height (the higher side: height + slope)
    depth : array<int>              // water depth
    upper : array<int>              // the upper level's height, 0 none
    blocked : array<bool>           // +6 bit 0x02: the cursor can not select it (the tower of Orbonne)
}

def read_map_w(var m : MapW) : bool {
    m = MapW()
    m.h = int(gba_read8(MAP_SIZE_W))
    m.w = int(gba_read8(MAP_SIZE_W + 1u))
    if (m.w <= 0 || m.h <= 0 || m.w * m.h > 256) {
        m.w = 0
        m.h = 0
        return false
    }
    for (i in range(m.w * m.h)) {
        let t = MAP_TILES_W + uint(i) * 8u
        m.height |> push(int(gba_read8(t + 2u)))
        let sd = int(gba_read8(t + 3u))
        m.slope |> push(sd & 31)
        m.depth |> push(sd >> 5)
        m.upper |> push(int(gba_read8(t + 0x800u + 2u)))
        m.blocked |> push((gba_read8(t + 6u) & 2u) != 0u)
    }
    return true
}

// the tile's height for the reach, in half h: the height x 2 + the slope
// (the middle of a slope) + the water's depth x 2 (its surface) - fitted
// to the tiles the game lights (reach1.txt); -1 off the map
def stand_half_w(m : MapW; x, y : int; high : bool = false) : int {
    if (x < 0 || y < 0 || x >= m.w || y >= m.h) {
        return -1
    }
    let i = y * m.w + x
    return high && m.upper[i] > 0 ? m.upper[i] * 2 : m.height[i] * 2 + m.slope[i] + m.depth[i] * 2
}

def map_height_w(m : MapW; x, y : int; high : bool = false) : int {
    if (x < 0 || y < 0 || x >= m.w || y >= m.h) {
        return -1
    }
    let i = y * m.w + x
    return high && m.upper[i] > 0 ? m.upper[i] : m.height[i]
}

// ------------------------------------------------------------ export

// Puts a unit into the edit copy of RAM (gba_edit_begin): the fields the
// calculator edits, and the derived ones (current PA / MA / Speed, WP,
// evades) as recompute_unit_w gives them.
def write_unit_w(u : UnitW) {
    let r = u.record
    gba_edit8(r + 0x03u, uint(u.job_id))
    gba_edit8(r + 0x12u, uint(u.primary))
    gba_edit8(r + 0x13u, uint(u.secondary))
    gba_edit16(r + 0x14u, uint(u.reaction))
    gba_edit16(r + 0x16u, uint(u.support))
    gba_edit16(r + 0x18u, uint(u.movement))
    for (k in range(7)) {
        gba_edit16(r + 0x1Au + uint(k) * 2u, uint(u.items[k]))
    }
    gba_edit8(r + 0x28u, uint(u.exp))
    gba_edit8(r + 0x29u, uint(u.level))
    gba_edit8(r + 0x2Bu, uint(u.brave))
    gba_edit8(r + 0x2Du, uint(u.faith))
    gba_edit16(r + 0x30u, uint(u.hp))
    gba_edit16(r + 0x32u, uint(u.max_hp))
    gba_edit16(r + 0x34u, uint(u.mp))
    gba_edit16(r + 0x36u, uint(u.max_mp))
    for (k in range(3)) {
        gba_edit8(r + 0x38u + uint(k), uint(clamp(u.raw[k], 0, 255)))
        gba_edit8(r + 0x3Bu + uint(k), uint(clamp(u.bonus[k], 0, 255)))
    }
    gba_edit8(r + 0x3Eu, uint(clamp(u.pa, 0, 255)))
    gba_edit8(r + 0x3Fu, uint(clamp(u.ma, 0, 255)))
    gba_edit8(r + 0x40u, uint(clamp(u.sp, 0, 255)))
    gba_edit8(r + 0x41u, uint(u.ct))
    gba_edit8(r + 0x42u, uint(u.move))
    gba_edit8(r + 0x43u, uint(u.jump))
    for (h in range(2)) {
        gba_edit8(r + 0x44u + uint(h), uint(u.wp[h]))
        gba_edit8(r + 0x46u + uint(h), uint(u.w_ev[h]))
        gba_edit8(r + 0x49u + uint(h), uint(u.s_ev[h]))
        gba_edit8(r + 0x4Du + uint(h), uint(u.sm_ev[h]))
    }
    gba_edit8(r + 0x48u, uint(u.a_ev))
    gba_edit8(r + 0x4Bu, uint(u.c_ev))
    gba_edit8(r + 0x4Cu, uint(u.am_ev))
    gba_edit8(r + 0x4Fu, uint(u.x))
    gba_edit8(r + 0x50u, uint(u.y))
    gba_edit8(r + 0x51u, (gba_read8(r + 0x51u) & 0x7Cu) | (u.high ? 0x80u : 0u) | uint(u.facing & 3))
    for (k in range(5)) {
        gba_edit8(r + 0x62u + uint(k), uint(u.status[k]))
    }
    for (k in range(LEARNED_W_SIZE)) {
        gba_edit8(r + 0xA3u + uint(k), uint(u.learned[k]))
    }
    for (k in range(11)) {
        gba_edit8(r + 0x95u + uint(k), uint(u.rsm_mask[k]))
    }
}

// the skillset of a learning job (LEARN_JOB_NAMES) for this unit, 0 none
def learn_skillset(u : UnitW; j : int) : int {
    if (j == 0) {
        return u.identity < 128 ? read_job_w(u.identity).skillset : 5
    } elif (j <= 19) {
        return 5 + j
    }
    return j == 20 ? 224 : 0
}

// learned bit of ability slot k (0..15 actions, 16..21 R/S/M) of job j
def learned_bit(u : UnitW; j, k : int) : bool {
    let b = j * 3 + (k < 16 ? k / 8 : 2)
    let m = k < 16 ? (0x80u >> uint(k & 7)) : (0x80u >> uint(k - 16))
    return (uint(u.learned[b]) & m) != 0u
}

def set_learned_bit(var u : UnitW; j, k : int; on : bool) {
    let b = j * 3 + (k < 16 ? k / 8 : 2)
    let m = k < 16 ? (0x80u >> uint(k & 7)) : (0x80u >> uint(k - 16))
    u.learned[b] = uint8(on ? (uint(u.learned[b]) | m) : (uint(u.learned[b]) & ~m))
}

// Writes the loaded PPSSPP state with the units to path. "" or the error.
def export_battle_w(units : array<UnitW>; path : string) : string {
    if (!gba_has_state()) {
        return "no state loaded"
    }
    gba_edit_begin()
    for (u in units) {
        write_unit_w(u)
    }
    return gba_save_state(path)
}
