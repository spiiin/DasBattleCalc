options gen2
options indenting = 4

// FFTA2 (NDS, USA, A6FE): the battle units of a melonDS state and the
// tables of the ROM they refer to (research/ffta2/notes.md). Two RAM
// structures point at each other: the character record (0x11C bytes:
// job, race, name, level, HP / MP, raw stats, equipment) and the battle
// object (0x48 bytes: tile, facing, Speed, CT).
module ffta2_battle shared public

require gba_mem
require math
require strings
require ../../core/teams.das public
require ../../core/result_try.das
require ffta2_charset

let FFTA2_CODE = "A6FE"
let RECORD_SIZE = 0x11Cu
let OBJECT_SIZE = 0x48u
let EQUIP_SLOTS = 5
// facing in the field's numbering (0 +y, 1 -x, 2 -y, 3 +x, as FFTA);
// the game's object +0x0E is 0 +y, 1 -x, 2 +x, 3 -y (the side of a Fight
// by the target's facing, research/ffta2/notes.md) - the table maps both
// ways
let FFTA2_FACING_NAMES = fixed_array<string>("+y", "-x", "-y", "+x")
let FACING_FROM_GAME = fixed_array<int>(0, 1, 3, 2)
let ELEMENT2_NAMES = fixed_array<string>("None", "Fire", "Wind", "Earth", "Water", "Ice", "Lightning", "Holy", "Dark")

let private SYSDATA_IDX = "system/rom/sysdata_rom.idx"
let private SYSDATA_PAK = "system/rom/sysdata.pak"
let private MESSAGE_IDX = "system/rom/JD_message_rom_0.idx"
let private MESSAGE_PAK = "system/rom/JD_message_0.pak"
let private JOB_FILE = 1                // sysdata: jobs, 72 bytes
let private JOB_SIZE = 72
let private EQUIP_FILE = 16             // sysdata: equipment, 40 bytes by item id
let private EQUIP_SIZE = 40
let private ABILITY_FILE = 4            // sysdata: abilities, 0x34 bytes
let private ABILITY_SIZE = 52
let private NAMES = 0                   // JD_message tables
let private JOB_NAMES = 1
let private ITEM_NAMES = 11
let private ABILITY_NAMES = 3
let private STATUS_NAMES = 12
let private MENU_TEXT = 9               // menu words: races at 92..98
let private RACE_TEXT = 91

// Attack, Defense, Magick, Resistance, Speed, Evasion, Move, Jump: the
// order of the equipment's bonuses (+19..+26) and of the Unit Info screen
let STAT2_COUNT = 8
let STAT2_LABELS = fixed_array<string>("Attack", "Defense", "Magick", "Resistance", "Speed", "Evasion", "Move", "Jump")

// how a turn ends (its CT cost: 50, +30 moved, +20 acted)
enum TurnEnd2 {
    MoveAndAct
    ActOnly
    MoveOnly
    Wait
}

struct Item2 {
    id : int
    name : string
    kind : int                      // equipment +0 u16: 1..25 weapons, 26 shields, ...
    element : int                   // +4: ELEMENT2_NAMES
    code : int                      // +0x12: special property; 1..40 by element, 5 each: 1 absorb, 2 immune, 3 half, 4 weak
    reach : int                     // +5: weapon range (swords 1, spears 2, bows 5..7, guns 7..8)
    two_hand : bool                 // +0x24 bit 2 (Doublehand counts such weapons)
    bonus : int[8]                  // by STAT2_LABELS
}

struct Unit2 {
    @readonly name : string
    @readonly job : string
    @readonly race : string
    @hide job_id : int              // record +0x06
    @hide race_id : int             // record +0x07: 1 Hume .. 7 Gria, 20 monster
    @hide name_id : int             // record +0x0C: 0x8000 a story character
    @readonly record : uint
    @readonly object : uint
    @readonly level : int
    @caption = "HP" @min = 0 hp : int
    @caption = "Max HP" @min = 1 max_hp : int
    @caption = "MP" @min = 0 mp : int
    @caption = "Max MP" @min = 0 max_mp : int
    @caption = "CT" ct : int
    @caption = "Turn speed" speed : int    // object +0x14: what a tick adds to CT
    @caption = "Assumed turn" assumed : TurnEnd2
    @caption = "Team byte" @readonly team_byte : int     // record +0x0A: 0x88 clan, 0x99 / 0x9B enemies, 0x9C guest
    @caption = "Position" @readonly position : string
    @hide team : int                // TEAM_*
    @hide flags : int               // record +0x0A u16 (bit 0 enemy, 2 guest, 10 ...)
    @hide raw : int[4]              // record +0x3C: Attack, Defense, Magick, Resistance x 4
    @hide base_speed : int          // record +0x1C
    @hide x : int                   // object +0x0C / +0x0D
    @hide y : int
    @hide facing : int              // FACING_FROM_GAME[object +0x0E]: 0 +y, 1 -x, 2 -y, 3 +x
    @hide affinity : int[8]         // job +33.., by element 1..8: 0 weak, 1 normal, 2 half, 3 immune, 4 absorb
    @hide bare_power : int          // job +48: Fight power without a weapon
    @hide job_hit : int             // job +41: the base of a hit on this unit (100)
    @hide job_50 : int              // job +50: 2 - never hit from the back
    @hide flying : bool             // job +66 bit 3 (native 2875)
    @caption = "Support" @readonly support_name : string
    @hide support : int             // record +0x50: ability id (851 Attack+ .. 881 Elusion), 0 none
    @hide reaction : int            // record +0x4E
    @hide status : uint8[9]         // record +0x28: status n = bit n & 7 of byte n >> 3 (JD_message 12)
    @caption = "RNG seed" @readonly rng_seed : uint   // its generator (rolls hits on it), 0: not found
    @hide items : int[5]            // record +0x44, item ids (0 empty)
    @hide equip : Item2[5]
    @hide stat_base : int[8]        // raw / 4, Speed, job Move / Jump
    @hide stat_items : int[8]
    @hide stat_total : int[8]       // as the Unit Info screen shows it
}

// ------------------------------------------------------------ text

// FFTA2 text (ffta2_charset): one byte per character up to 0xA8, 0xC0 00
// line break, 0xC1 / 0xC3 00 end, 0xC2 .. 0xCF (but C0, C3, C8) take a
// parameter byte and are dropped.
def ffta2_text(buf, off, len : int) : string {
    var res = ""
    var i = 0
    while (i < len) {
        let c = int(nds_buf_read8(buf, off + i))
        i++
        if (c < length(FFTA2_CHARS)) {
            res += FFTA2_CHARS[c]
        } elif (c == 0xC0) {
            res += " "
            i++
        } elif (c == 0xC1 || c == 0xC3) {
            break
        } elif (c == 0xC8) {
            i++
        } elif (c >= 0xC2 && c <= 0xCF) {
            i++                         // a parameter: a variable, a sprite
        } else {
            res += "<{fmt(":02X", c)}>"
        }
    }
    return res
}

// a string of a JD_message table: i16 count, then (i32 length, u32
// offset, u16 lines) each
def ffta2_message(tab, index : int) : string {
    let buf = nds_pak_file(MESSAGE_IDX, MESSAGE_PAK, tab)
    if (buf < 0 || index < 0 || index >= int(nds_buf_read16(buf, 0))) {
        return ""
    }
    let len = int(nds_buf_read32(buf, 2 + index * 10))
    let off = int(nds_buf_read32(buf, 6 + index * 10))
    return ffta2_text(buf, off, len)
}

def status_name(n : int) : string {
    return ffta2_message(STATUS_NAMES, n)
}

def has_status2(u : Unit2; n : int) : bool {
    return n >= 0 && n < 72 && (uint(u.status[n >> 3]) & (1u << uint(n & 7))) != 0u
}

def race_name(race : int) : string {
    return race >= 1 && race <= 7 ? ffta2_message(MENU_TEXT, RACE_TEXT + race) : "Monster"
}

def job_name(job : int) : string {
    return ffta2_message(JOB_NAMES, job)
}

// ------------------------------------------------------------ ROM tables

def job_byte(job, off : int) : int {
    let buf = nds_pak_file(SYSDATA_IDX, SYSDATA_PAK, JOB_FILE)
    return int(nds_buf_read8(buf, job * JOB_SIZE + off))
}

def item_count() : int {
    return nds_buf_size(nds_pak_file(SYSDATA_IDX, SYSDATA_PAK, EQUIP_FILE)) / EQUIP_SIZE
}

def read_item2(id : int) : Item2 {
    var it = Item2(id = id)
    if (id <= 0 || id >= item_count()) {
        return it
    }
    let buf = nds_pak_file(SYSDATA_IDX, SYSDATA_PAK, EQUIP_FILE)
    let base = id * EQUIP_SIZE
    it.name = ffta2_message(ITEM_NAMES, id)
    it.kind = int(nds_buf_read16(buf, base))
    it.element = int(nds_buf_read8(buf, base + 4))
    it.code = int(nds_buf_read8(buf, base + 0x12))
    it.reach = int(nds_buf_read8(buf, base + 5))
    it.two_hand = (nds_buf_read8(buf, base + 0x24) & 4u) != 0u
    for (s in range(STAT2_COUNT)) {
        it.bonus[s] = int(int8(nds_buf_read8(buf, base + 19 + s)))
    }
    return it
}

// An ability (sysdata 4; research/ffta2/notes.md, "Abilities"). Up to
// four effects: the type (a function of script 332 deciding whether it
// applies to the target), the functions applying it (script 897), of
// its hit (784), of its amount (598); Attack and the damage spells:
// 0F 01 01 01.
struct Ability2 {
    id : int
    name : string
    element : int                   // +2
    mp : int                        // +3: MP cost
    power : int                     // +6
    flags : uint                    // +0x20: bit 3 magick, 18 x2 vs counters, 28 by side
    range_kind : int                // +0x0B: 7 the weapon's range, 8 the user only
    reach : int                     // +0x0C: tiles (else)
    area : int                      // +0x0E: the area's radius
    fx : int4[4]                    // +0x10: effects (type = condition, apply, hit, amount functions)
}

def ability_count() : int {
    return nds_buf_size(nds_pak_file(SYSDATA_IDX, SYSDATA_PAK, ABILITY_FILE)) / ABILITY_SIZE
}

def read_ability2(id : int) : Ability2 {
    var a = Ability2(id = id)
    if (id <= 0 || id >= ability_count()) {
        return a
    }
    let buf = nds_pak_file(SYSDATA_IDX, SYSDATA_PAK, ABILITY_FILE)
    let base = id * ABILITY_SIZE
    a.name = ffta2_message(ABILITY_NAMES, id)
    a.element = int(nds_buf_read8(buf, base + 2))
    a.mp = int(nds_buf_read8(buf, base + 3))
    a.power = int(nds_buf_read16(buf, base + 6))
    a.flags = nds_buf_read32(buf, base + 0x20)
    a.range_kind = int(nds_buf_read8(buf, base + 0x0B))
    a.reach = int(nds_buf_read8(buf, base + 0x0C))
    a.area = int(nds_buf_read8(buf, base + 0x0E))
    for (k in range(4)) {
        let o = base + 0x10 + 4 * k
        a.fx[k] = int4(int(nds_buf_read8(buf, o)), int(nds_buf_read8(buf, o + 1)), int(nds_buf_read8(buf, o + 2)),
            int(nds_buf_read8(buf, o + 3)))
    }
    return a
}

def is_magick2(a : Ability2) : bool {
    return (a.flags & 8u) != 0u
}

def by_side2(a : Ability2) : bool {
    return (a.flags & 0x10000000u) != 0u
}

// ------------------------------------------------------------ units

let private RAM_LO = 0x02000000u
let private RAM_HI = 0x02400000u

def private in_ram(p : uint) : bool {
    return p >= RAM_LO && p + RECORD_SIZE <= RAM_HI
}

def team_of(team_byte : int) : int {
    if (team_byte == 0x88) {
        return TEAM_PLAYER
    }
    return team_byte == 0x9C ? TEAM_GUEST : TEAM_ENEMY
}

// the job and what comes from its table (affinities, bare hands, ...)
def set_job2(var u : Unit2; job : int) {
    u.job_id = job
    u.job = job_name(job)
    for (e in range(8)) {
        u.affinity[e] = job_byte(job, 33 + e)
    }
    u.bare_power = job_byte(job, 48)
    u.job_hit = job_byte(job, 41)
    u.job_50 = job_byte(job, 50)
    u.flying = (job_byte(job, 66) & 8) != 0
}

// base, items and total of each stat (after an edit of the equipment)
def recompute_unit(var u : Unit2) {
    for (s in range(4)) {
        u.stat_base[s] = u.raw[s] / 4
    }
    u.stat_base[4] = u.base_speed
    u.stat_base[5] = 0
    u.stat_base[6] = job_byte(u.job_id, 17)
    u.stat_base[7] = job_byte(u.job_id, 18)
    for (s in range(STAT2_COUNT)) {
        var sum = 0
        for (k in range(EQUIP_SLOTS)) {
            sum += u.equip[k].bonus[s]
        }
        u.stat_items[s] = sum
        u.stat_total[s] = u.stat_base[s] + sum
    }
    u.position = "{u.x}, {u.y}, facing {FFTA2_FACING_NAMES[u.facing & 3]}"
}

def read_unit2(rec, obj : uint) : Unit2 {
    var u = Unit2(record = rec, object = obj)
    u.job_id = int(gba_read8(rec + 0x06u))
    u.race_id = int(gba_read8(rec + 0x07u))
    u.team_byte = int(gba_read8(rec + 0x0Au))
    u.flags = int(gba_read16(rec + 0x0Au))
    u.team = team_of(u.team_byte)
    u.name_id = int(gba_read16(rec + 0x0Cu))
    u.name = ffta2_message(NAMES, u.name_id & 0x7FFF)
    u.job = job_name(u.job_id)
    u.race = race_name(u.race_id)
    u.level = int(gba_read16(rec + 0x1Au))
    u.base_speed = int(gba_read8(rec + 0x1Cu))
    u.hp = int(gba_read16(obj + 0x08u))
    u.max_hp = int(gba_read16(rec + 0x36u))
    u.mp = int(gba_read16(rec + 0x38u))
    u.max_mp = int(gba_read16(rec + 0x3Au))
    for (s in range(4)) {
        u.raw[s] = int(gba_read16(rec + 0x3Cu + uint(s) * 2u))
    }
    for (k in range(EQUIP_SLOTS)) {
        u.items[k] = int(gba_read16(rec + 0x44u + uint(k) * 2u))
        u.equip[k] = read_item2(u.items[k])
    }
    u.x = int(gba_read8(obj + 0x0Cu))
    u.y = int(gba_read8(obj + 0x0Du))
    u.facing = FACING_FROM_GAME[int(gba_read8(obj + 0x0Eu)) & 3]
    set_job2(u, u.job_id)
    u.support = int(gba_read16(rec + 0x50u))
    u.reaction = int(gba_read16(rec + 0x4Eu))
    u.support_name = u.support != 0 ? ffta2_message(ABILITY_NAMES, u.support) : "none"
    for (k in range(9)) {
        u.status[k] = uint8(gba_read8(rec + 0x28u + uint(k)))
    }
    u.ct = int(gba_read16(obj + 0x16u))
    u.speed = int(gba_read16(obj + 0x14u))
    u.assumed = TurnEnd2.MoveAndAct
    recompute_unit(u)
    return u
}

// a unit, not some other pair of structures pointing at each other:
// level 1..99, HP within 1..999, a team byte 0x8x / 0x9x, a tile
def private plausible_unit(rec, obj : uint) : bool {
    let level = gba_read16(rec + 0x1Au)
    let max_hp = gba_read16(rec + 0x36u)
    let team_byte = gba_read8(rec + 0x0Au)
    return (level >= 1u && level <= 99u && max_hp >= 1u && max_hp <= 999u && gba_read16(obj + 0x08u) <= max_hp &&
        (team_byte & 0xE0u) == 0x80u && gba_read8(obj + 0x0Cu) < 64u && gba_read8(obj + 0x0Du) < 64u)
}

// The battle map ("PANL", research/ffta2/notes.md, "Map"): u32 magic,
// u32 size = 12 + w x h x 12, u8 w, u8 h at +8, then 12-byte tiles row by
// row from +0x0C: +0 the height (as the game shows it), +4 flags (bit 31:
// no tile). Found by its pointer [[0x0212EEA8] + 0xF4], else by a scan.
struct Map2 {
    w : int
    h : int
    height : array<int>             // -1: no tile
    flags : array<uint>
}

def private panl_at(p : uint) : bool {
    if (p < RAM_LO || p + 16u > RAM_HI || gba_read32(p) != 0x4C4E4150u) {
        return false
    }
    let w = gba_read8(p + 8u)
    let h = gba_read8(p + 9u)
    return w > 0u && h > 0u && gba_read32(p + 4u) == 12u + w * h * 12u
}

def read_map2(var m : Map2) : bool {
    m = Map2()
    var p = 0u
    let ptr = gba_read32(0x0212EEA8u)
    if (ptr >= RAM_LO && ptr < RAM_HI && panl_at(gba_read32(ptr + 0xF4u))) {
        p = gba_read32(ptr + 0xF4u)
    } else {
        var a = RAM_LO
        while (a < RAM_HI && p == 0u) {
            if (panl_at(a)) {
                p = a
            }
            a += 4u
        }
    }
    if (p == 0u) {
        return false
    }
    m.w = int(gba_read8(p + 8u))
    m.h = int(gba_read8(p + 9u))
    for (i in range(m.w * m.h)) {
        let t = p + 0x0Cu + uint(i) * 12u
        let fl = gba_read32(t + 4u)
        m.flags |> push(fl)
        m.height |> push((fl & 0x80000000u) != 0u ? -1 : int(gba_read8(t)))
    }
    return true
}

def map_height(m : Map2; x, y : int) : int {
    return x >= 0 && y >= 0 && x < m.w && y < m.h ? m.height[y * m.w + x] : -1
}

// The game's generators (0x0206F264 the battle's, 0x0205E950 a unit's):
// seed = seed x RNG_MUL + RNG_INC, the value is the seed's high half.
let RNG_MUL = 0x5D588B65u
let RNG_INC = 0x269EC3u

// the battle generator's seed of the loaded state (damage rolls), 0 when not found
var battle_rng : uint

def rng_next(var seed : uint&) : int {
    seed = seed * RNG_MUL + RNG_INC
    return int(seed >> 16u)
}

// The battle objects: in main RAM a word p at address a such that the
// record at p points back at a (+0x00: the object's +0x04, its record
// pointer) - the global list pointer (0x02083344) lies in a page the state
// does not hold. In object order; "" or the error.
def read_battle2(var units : array<Unit2>) : string {
    units |> clear()
    ensure(gba_has_state(), "no state loaded")
    ensure(gba_state_is_nds(), "not an NDS (melonDS) state")
    var a = RAM_LO + 0x4u
    battle_rng = 0u
    var seeds : table<uint; uint>
    while (a < RAM_HI) {
        // a generator: +0x14 multiplier, +0x18 increment, +0x10 seed, +0x0C its unit's record (0: the battle's)
        if (gba_read32(a + 0x14u) == RNG_MUL && gba_read32(a + 0x18u) == RNG_INC) {
            let owner = gba_read32(a + 0x0Cu)
            if (owner == 0u && a >= 0x02200000u) {
                battle_rng = gba_read32(a + 0x10u)
            } elif (in_ram(owner)) {
                seeds |> insert(owner, gba_read32(a + 0x10u))
            }
        }
        let rec = gba_read32(a)
        if (in_ram(rec) && gba_read32(rec) == a) {
            let obj = a - 4u
            if (plausible_unit(rec, obj)) {
                units |> push(read_unit2(rec, obj))
            }
        }
        a += 4u
    }
    ensure(length(units) > 0, "no battle in this state")
    for (u in units) {
        u.rng_seed = seeds?[u.record] ?? 0u
    }
    return ""
}
