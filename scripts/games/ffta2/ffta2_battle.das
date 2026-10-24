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
let FFTA2_FACING_NAMES = fixed_array<string>("+y", "-x", "-y", "+x")

let private SYSDATA_IDX = "system/rom/sysdata_rom.idx"
let private SYSDATA_PAK = "system/rom/sysdata.pak"
let private MESSAGE_IDX = "system/rom/JD_message_rom_0.idx"
let private MESSAGE_PAK = "system/rom/JD_message_0.pak"
let private JOB_FILE = 1                // sysdata: jobs, 72 bytes
let private JOB_SIZE = 72
let private EQUIP_FILE = 16             // sysdata: equipment, 40 bytes by item id
let private EQUIP_SIZE = 40
let private NAMES = 0                   // JD_message tables
let private JOB_NAMES = 1
let private ITEM_NAMES = 11
let private MENU_TEXT = 9               // menu words: races at 92..98
let private RACE_TEXT = 91

// Attack, Defense, Magick, Resistance, Speed, Evasion, Move, Jump: the
// order of the equipment's bonuses (+19..+26) and of the Unit Info screen
let STAT2_COUNT = 8
let STAT2_LABELS = fixed_array<string>("Attack", "Defense", "Magick", "Resistance", "Speed", "Evasion", "Move", "Jump")

struct Item2 {
    id : int
    name : string
    kind : int                      // equipment +0 u16
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
    @caption = "Team byte" @readonly team_byte : int     // record +0x0A: 0x88 clan, 0x99 / 0x9B enemies, 0x9C guest
    @caption = "Position" @readonly position : string
    @hide team : int                // TEAM_*
    @hide raw : int[4]              // record +0x3C: Attack, Defense, Magick, Resistance x 4
    @hide base_speed : int          // record +0x1C
    @hide x : int                   // object +0x0C / +0x0D
    @hide y : int
    @hide facing : int              // object +0x0E: 0 +y, 1 -x, 2 -y, 3 +x (as FFTA, see notes)
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
    for (s in range(STAT2_COUNT)) {
        it.bonus[s] = int(int8(nds_buf_read8(buf, base + 19 + s)))
    }
    return it
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
    u.facing = int(gba_read8(obj + 0x0Eu)) & 3
    u.ct = int(gba_read16(obj + 0x16u))
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

// The battle objects: in main RAM a word p at address a such that the
// record at p points back at a (+0x00: the object's +0x04, its record
// pointer) - the global list pointer (0x02083344) lies in a page the state
// does not hold. In object order; "" or the error.
def read_battle2(var units : array<Unit2>) : string {
    units |> clear()
    ensure(gba_has_state(), "no state loaded")
    ensure(gba_state_is_nds(), "not an NDS (melonDS) state")
    var a = RAM_LO + 0x4u
    while (a < RAM_HI) {
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
    return ""
}
