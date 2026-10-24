options gen2
options indenting = 4

// FFTA (USA, AFXE) battle state from RAM, and the turn order model.
// Everything here was read from the ROM and checked against the running
// game, see research/notes.md. Addresses are for the USA ROM.
module ffta_battle shared public

require gba_mem
require math
require strings
require daslib/strings_boost
require daslib/linq
require daslib/linq_boost
require ../../core/gba_struct.das
require ../../core/result_try.das
require ../../core/teams.das public

let UNIT_STRIDE = 0x108u          // unit record size
let WRAPPER_STRIDE = 0x90u        // battle participant ("wrapper") size
let ITEM_TABLE = 0x0851D180u      // 32 bytes per item, see ItemRecord
let ITEM_COUNT = 378              // ids 1..377; kind 1..29 equipment, 30 items
let JOB_TABLE = 0x08521A14u       // 52 bytes per job, see JobRecord
let TEXT_TABLE = 0x08526680u      // pointers to texts: items, jobs, ...
let TEXT_TABLE2 = 0x085567F0u     // pointers to texts: menus, abilities, ...
let ABILITY_TABLE = 0x0855187Cu   // action abilities, 28 bytes each
let RACE_ABILITIES = 0x0851BA84u  // per race (+0x06): pointer to 8-byte entries
let MAX_ACTIONS = 128
let CT_TURN = 1000                // a unit takes its turn above 999

// How a turn ends (0x0809F8EC): CT -= 500, -200 if moved, -300 if acted.
enum TurnEnd {
    MoveAndAct
    ActOnly
    MoveOnly
    WaitOnly
}

// The stats of the Status screen, in the order of the item bonuses:
// bonus i is at item +0x10 + i (getter 0x080CA7A4, stats 10..17).
enum Stat {
    WAtk
    WDef
    MPow
    MRes
    Speed
    Evade
    Move
    Jump
}

let STAT_COUNT = 8
let STAT_NAMES = fixed_array<string>("Weapon Atk", "Weapon Def", "Magic Pow", "Magic Res", "Speed", "Evade", "Move",
    "Jump")

// item +0x08, named after the items of each kind
let ITEM_KINDS = fixed_array<string>("-", "Sword", "Blade", "Saber", "Knightsword", "Greatsword", "Broadsword",
    "Knife", "Rapier", "Katana", "Staff", "Rod", "Mace", "Bow", "Greatbow", "Spear", "Instrument", "Knuckles",
    "Soul", "Gun", "Shield", "Helmet", "Hair", "Hat", "Armor", "Clothing", "Robe", "Shoes", "Armlet", "Ring",
    "Item")

struct Item {
    id : int                        // 0: empty slot
    name : string
    kind : int
    element : int                   // ELEMENTS, 0: none
    weapon_range : int              // +0x0A: sword 1, spear 2, bow 5, gun 8
    hands : int                     // +0x0B: 1 one-handed, 2 two-handed (?)
    bonus : int[8]                  // by Stat
}

// item +0x09 and the affinity bytes of a unit (record +0x0C + element)
let FACING_NAMES = fixed_array<string>("+y", "-x", "-y", "+x")
let DIR_X = fixed_array<int>(0, -1, 0, 1)       // table 0x083A842C, by facing
let DIR_Y = fixed_array<int>(1, 0, -1, 0)

let ELEMENTS = fixed_array<string>("None", "Fire", "Wind", "Earth", "Water", "Ice", "Lightning", "Holy", "Dark")

def is_weapon(it : Item) : bool {
    return it.kind >= 1 && it.kind <= 19
}

struct BattleUnit {
    @readonly name : string
    @hide job : string              // drawn by the game module (a job list)
    @hide job_id : int              // record +0x05, JOB_TABLE index
    @hide job2 : int                // record +0x07
    @hide race : int                // record +0x06
    @hide character : int           // record +0x04: a story character when > 1
    @hide move_plus : int           // record +0x3D == 1: Move + 1
    @readonly record : uint
    @hide wrapper : uint            // its participant entry (WRAPPER_STRIDE)
    @readonly level : int
    @caption = "HP" @min = 0 hp : int
    @caption = "Max HP" @min = 1 max_hp : int
    @caption = "MP" @min = 0 mp : int
    @hide base_speed : int          // Stats show base + items
    @hide item_speed : int
    @caption = "Speed" @readonly speed : int
    @caption = "CT" ct : int
    @caption = "Reserve" reserve : int
    @caption = "Sprite palette" @readonly side : int   // wrapper +0x1E: palette row of the map sprite (teams: team())
    @caption = "Tie order" @readonly order : int
    @caption = "Status" @readonly status_text : string
    @caption = "Position" @readonly position : string
    @caption = "Assumed turn" assumed : TurnEnd
    @hide status : uint[6]          // +0xE8..+0xED
    @hide items : uint[5]           // +0x2A, equipment item ids
    @hide equip : Item[5]
    @hide stat_base : int[8]        // by Stat: job / record
    @hide stat_items : int[8]       // sum of the equipment bonuses
    @hide stat_total : int[8]       // as the Status screen shows it
    @hide x : int                   // tile, wrapper +0x08 >> 5
    @hide y : int                   // tile, wrapper +0x0C >> 5
    @hide facing : int              // wrapper +0x1F: 0 +y, 1 -x, 2 -y, 3 +x
    @hide flags : uint              // +0x28: 0x8000 enemy, 0x2000 guest, 0x1000 judge
    @hide affinity : int[9]         // +0x0C, by element: 0 weak, 1 normal, 2 immune, 3 absorb, 4 half
    @hide bare_power : int          // job +0x33: Fight power bare-handed
    @hide support_name : string     // drawn by the game module (a list)
    @hide support : int             // support ability id (1 Weapon Atk+, 13 Concentrate, ...)
    @hide reaction_name : string
    @hide reaction : int            // reaction id (5 Reflex, 7 Strikeback, 8 Counter, ...)
    @hide learned : bool[144]       // race list entry i learned (+0x40 + i bit 0x80)
    @hide actions : int[128]        // learned action abilities (ABILITY_TABLE ids)
    @hide action_count : int
}

// ------------------------------------------------------------ text

// FFTA text: 0xB1.. A-Z, 0xCB.. a-z, 0x00 ends; other codes are shown as
// <xx>. Names typed by the player (in RAM) are 0x80 + (code - 1).
def ffta_text(ptr : uint; max_len : int = 24) : string {
    var res = ""
    var a = ptr
    for (_ in range(max_len)) {
        var c = int(gba_read8(a))
        a++
        if (c == 0x80) {
            c = int(gba_read8(a)) + 1
            a++
        }
        if (c == 0) {
            break
        } elif (c == 1) {
            continue
        } elif (c == 0x40) {
            // 0x40 0x3C n: kerning; 0x40 0x3E n and 0x40 0x73: space
            let k = int(gba_read8(a))
            a += k == 0x3C || k == 0x3E ? 2u : 1u
            if (k != 0x3C) {
                res += " "
            }
        } elif (c == 0x81) {
            // 0x81 n: a symbol ("Damage > MP" has 0x81 0x03)
            let k = int(gba_read8(a))
            a++
            res += k == 3 ? ">" : "?"
        } elif (c == 0xF5) {
            res += "'"
        } elif (c == 0xFF) {
            res += "-"
        } elif (c >= 0xA7 && c <= 0xB0) {
            // digits: "Masamune 100", "LV3 Def-less", "Excalibur2"
            res += to_char(c - 0xA7 + '0')
        } elif (c == 0xE5) {
            res += "."
        } elif (c == 0xEB) {
            res += "?"
        } elif (c == 0xEF) {
            res += ":"                  // "Steal: Armor", "Aim: Legs"
        } elif (c == 0xFE) {
            res += "+"                  // "Weapon Atk+"
        } elif (c >= 0xB1 && c <= 0xCA) {
            res += to_char(c - 0xB1 + 'A')
        } elif (c >= 0xCB && c <= 0xE4) {
            res += to_char(c - 0xCB + 'a')
        } else {
            res += "<{fmt(":02x", c)}>"
        }
    }
    return res
}

// text number id of the ROM text table (items, jobs, ...)
def ffta_text_id(id : int) : string {
    return gba_has_rom() ? ffta_text(gba_read32(TEXT_TABLE + uint(id) * 4u), 32) : "#{id}"
}

// the second text table: ability names (ABILITY_TABLE +0x00, race list
// entries +0x00)
def ffta_text2(id : int) : string {
    return gba_has_rom() ? ffta_text(gba_read32(TEXT_TABLE2 + uint(id) * 4u), 32) : "#{id}"
}

def ability_name(id : int) : string {
    return id == 0 ? "Fight" : ffta_text2(int(gba_read16(ABILITY_TABLE + uint(id) * 28u)))
}

// A race's ability list (RACE_ABILITIES[race], 8 bytes per entry):
// +0x00 name (TEXT_TABLE2), +0x04 id in the table of its type, +0x06
// type (1 action, 2 reaction, 3 support, 5 combo), +0x07 AP / 10. A unit
// has learned entry i when record +0x40 + i has bit 0x80; its support is
// the entry at record +0x3B.
struct RaceAbility {
    name : int
    id : int
    kind : int
}

def race_ability(race, index : int) : RaceAbility {
    if (!gba_has_rom() || index <= 0) {
        return RaceAbility()
    }
    let e = gba_read32(RACE_ABILITIES + uint(race) * 4u) + uint(index) * 8u
    return RaceAbility(name = int(gba_read16(e)), id = int(gba_read16(e + 4u)), kind = int(gba_read8(e + 6u)))
}

// ------------------------------------------------------------ items, jobs

struct ItemRecord {
    @offset = 0x00 name : uint16          // text id
    @offset = 0x08 kind : uint8           // ITEM_KINDS
    @offset = 0x09 element : uint8        // ELEMENTS
    @offset = 0x0A weapon_range : uint8   // tiles
    @offset = 0x0B hands : uint8          // 1 or 2: held in the hands
    @offset = 0x10 bonus : uint8[8]       // signed, by Stat
}

def private signed8(b : uint8) : int {
    return int(b) >= 128 ? int(b) - 256 : int(b)
}

// Stats 10..13 of items 51, 302, 148, 286 get extra points when some
// story flags are set (0x080C95A8); not modelled.
def read_item(id : uint) : Item {
    var it = Item(id = int(id))
    if (id == 0u || !gba_has_rom()) {
        return it
    }
    var r : ItemRecord
    read_struct(ITEM_TABLE + id * 32u, r)
    it.name = ffta_text_id(int(r.name))
    it.kind = int(r.kind)
    it.element = int(r.element)
    it.weapon_range = int(r.weapon_range)
    it.hands = int(r.hands)
    for (i in range(STAT_COUNT)) {
        it.bonus[i] = signed8(r.bonus[i])
    }
    return it
}

def item_kind_name(kind : int) : string {
    return kind >= 0 && kind < length(ITEM_KINDS) ? ITEM_KINDS[kind] : "kind {kind}"
}

struct JobRecord {
    @offset = 0x00 name : uint16          // text id
    @offset = 0x05 parent : uint8         // 255: the unit's +0x07; other: that job
    @offset = 0x07 sprite : uint8         // map sprite set (ffta_gfx.das)
    @offset = 0x28 move : uint8
    @offset = 0x29 jump : uint8
    @offset = 0x2A evade : uint8
}

// 0x080C8570: a job entry with a nonzero +0x05 takes its fields from
// another entry (255: the unit's second job, record +0x07).
def read_job(job, job2 : uint) : JobRecord {
    var r : JobRecord
    if (!gba_has_rom()) {
        return r
    }
    var id = job
    for (_ in range(16)) {
        read_struct(JOB_TABLE + id * 52u, r)
        if (uint(r.parent) == 255u) {
            id = job2
        } elif (r.parent != 0u8) {
            id = uint(r.parent)
        } else {
            break
        }
    }
    return r
}

// Status screen stats: W.Atk 0x080CA624, W.Def 0x080CA6B4, M.Pow
// 0x080CA66C, M.Res 0x080CA6FC = record + items, at most 999; Evade
// 0x080CA5C4 = job +0x2A + items, 0..100; Move 0x080CA394 = job +0x28
// (+1 if record +0x3D == 1) + items; Jump = job +0x29 + items.
def stat_total(stat : int; base, items : int) : int {
    let v = base + items
    if (stat == int(Stat.Evade)) {
        return clamp(v, 0, 100)
    } elif (stat == int(Stat.Speed) || stat == int(Stat.Move) || stat == int(Stat.Jump)) {
        return max(v, 0)
    }
    return clamp(v, 0, 999)
}

// The supports (kind 3) or reactions (kind 2) a race can learn, one per
// id, in list order.
def race_choices(race, kind : int) : array<RaceAbility> {
    var res : array<RaceAbility>
    for (i in range(1, 200)) {
        let a = race_ability(race, i)
        if (a.name == 0 || a.kind > 5) {
            break
        }
        if (a.kind == kind && a.id > 0) {
            var seen = false
            for (o in res) {
                seen = seen || o.id == a.id
            }
            if (!seen) {
                res |> push(a)
            }
        }
    }
    return <- res
}

// The jobs of a race (+0x06): 1 Human, 2 Bangaa, 3 Nu Mou, 4 Viera,
// 5 Moogle; other races (monsters, judges) keep their job.
def race_jobs(race : int) : array<int> {
    var res : array<int>
    let lo = race == 1 ? 2 : (race == 2 ? 13 : (race == 3 ? 20 : (race == 4 ? 28 : (race == 5 ? 36 : 0))))
    let hi = race == 1 ? 12 : (race == 2 ? 19 : (race == 3 ? 27 : (race == 4 ? 35 : (race == 5 ? 43 : -1))))
    for (j in range(lo, hi + 1)) {
        res |> push(j)
    }
    return <- res
}

def job_name(job, job2 : int) : string {
    return ffta_text_id(int(read_job(uint(job), uint(job2)).name))
}

// A job change: Move, Jump, the Evade base and the bare-handed power come
// from the job table; the record stats (W.Atk ... Speed) stay.
def set_job(var u : BattleUnit; job : int) {
    u.job_id = job
    u.job2 = job
    let j = read_job(uint(job), uint(job))
    u.job = ffta_text_id(int(j.name))
    u.stat_base[int(Stat.Evade)] = int(j.evade)
    u.stat_base[int(Stat.Move)] = int(j.move) + u.move_plus
    u.stat_base[int(Stat.Jump)] = int(j.jump)
    u.bare_power = gba_has_rom() ? int(gba_read8(JOB_TABLE + uint(job) * 52u + 0x33u)) : 0
}

// The learned action abilities (kind 1) in race list order.
def update_actions(var u : BattleUnit) {
    u.action_count = 0
    for (i in range(1, 144)) {
        if (u.learned[i] && u.action_count < MAX_ACTIONS) {
            let a = race_ability(u.race, i)
            if (a.kind == 1 && a.id > 0) {
                u.actions[u.action_count] = a.id
                u.action_count++
            }
        }
    }
}

// A race ability list by job: the entries of a job end with its combo
// (kind 5), the blocks go in the order of race_jobs (Soldier, Paladin,
// ...). Entries after the last combo, and races without jobs, form one
// block with job -1.
struct AbilityBlock {
    job : int
    first : int                     // race list indices first .. last
    last : int
}

def ability_blocks(race : int) : array<AbilityBlock> {
    var res : array<AbilityBlock>
    let jobs <- race_jobs(race)
    var first = 1
    var i = 1
    while (i < 144) {
        let a = race_ability(race, i)
        if (a.name == 0 || a.kind > 5) {
            break
        }
        if (a.kind == 5 && length(jobs) > 0) {
            let k = length(res)
            res |> push(AbilityBlock(job = k < length(jobs) ? jobs[k] : -1, first = first, last = i))
            first = i + 1
        }
        i++
    }
    if (i > first) {
        res |> push(AbilityBlock(job = -1, first = first, last = i - 1))
    }
    return <- res
}

// After an edit of the base stats or the equipment: the item sums, the
// totals, the speed of the turn model and the texts.
def recompute_unit(var u : BattleUnit) {
    u.hp = clamp(u.hp, 0, u.max_hp)
    for (s in range(STAT_COUNT)) {
        u.stat_items[s] = 0
    }
    for (i in range(5)) {
        u.items[i] = uint(u.equip[i].id)
        for (s in range(STAT_COUNT)) {
            u.stat_items[s] += u.equip[i].bonus[s]
        }
    }
    for (s in range(STAT_COUNT)) {
        u.stat_total[s] = stat_total(s, u.stat_base[s], u.stat_items[s])
    }
    u.base_speed = u.stat_base[int(Stat.Speed)]
    u.item_speed = u.stat_items[int(Stat.Speed)]
    u.speed = effective_speed(u)
    u.status_text = status_text(u)
    u.position = "{u.x}, {u.y}, facing {FACING_NAMES[u.facing & 3]}"
    update_actions(u)
}

// ------------------------------------------------------------ speed

// 0x0812E368: base + equipment, halved by +0xEC&4 or +0xEA&2,
// doubled by +0xEA&0x20 (Haste?), halved by +0xEA&0x40
def effective_speed(u : BattleUnit) : int {
    var s = max(u.base_speed + u.item_speed, 0)
    if ((u.status[4] & 0x04u) != 0u || (u.status[2] & 0x02u) != 0u) {
        s = s / 2
    }
    if ((u.status[2] & 0x20u) != 0u) {
        s = s * 2
    }
    if ((u.status[2] & 0x40u) != 0u) {
        s = s / 2
    }
    return s
}

// 0x080CD92C / 0x080CDCEC: units that do not gain CT (KO and similar)
def eligible(u : BattleUnit) : bool {
    return (u.status[0] & 0x40u) == 0u && (u.status[5] & 0x40u) == 0u && u.speed > 0
}

// Status bits +0xE8..+0xED, bit k of byte b at (b - 0xE8) * 8 + k.
// Names from the abilities whose status effect sets the bit (setters
// 0x080CDD1C.., research/status_bits.py -> status_kinds.txt); "?": no
// ability sets it, named by its effect if one is known.
let STATUS_NAMES = fixed_array<string>(
    "E8&01 ?", "Quick", "Auto-Life", "Regen", "Astra", "Reflect", "Petrify", "Berserk",
    "Frog", "Poison", "Blind", "Zombie", "Invisible", "Defense", "Boost", "Hibernate",
    "Advice (crit +30)", "Mow Down?", "EA&04 (monster)", "Cover", "Doom", "Haste", "Slow", "Stop",
    "Shell", "Protect", "Sleep", "Silence", "Confuse", "Charm", "Immobilize", "Disable",
    "Addle", "Expert Guard", "Speed down", "W.Atk up", "W.Atk down", "M.Pow up", "M.Pow down", "W.Def up",
    "W.Def down", "M.Res up", "M.Res down", "ED&08 (monster)", "ED&10 (Petrify)", "ED&20 ?", "ED&40 (no CT)", "ED&80 ?")

def has_status_bit(u : BattleUnit; index : int) : bool {
    return (u.status[index >> 3] & (1u << uint(index & 7))) != 0u
}

def status_text(u : BattleUnit) : string {
    let parts <- [for (i in range(48)); STATUS_NAMES[i]; where has_status_bit(u, i)]
    return length(parts) == 0 ? "none" : join(parts, ", ")
}

// ------------------------------------------------------------ RAM

// The unit record in RAM, 0x108 bytes (research/notes.md)
struct UnitRecord {
    @offset = 0x00 name : uint            // pointer to the name text
    @offset = 0x04 character : uint8      // story character (> 1), CHARACTER_TABLE index
    @offset = 0x05 job : uint8            // JOB_TABLE index
    @offset = 0x06 race : uint8           // RACE_ABILITIES index
    @offset = 0x07 job2 : uint8           // used by jobs with parent 255
    @offset = 0x09 level : uint8
    @offset = 0x0C affinity : uint8[9]    // by element
    @offset = 0x18 hp : uint16
    @offset = 0x1A max_hp : uint16
    @offset = 0x1C mp : uint16
    @offset = 0x20 stats : uint16[4]      // W.Atk, W.Def, M.Pow, M.Res
    @offset = 0x28 flags : uint16         // 0x8000 enemy, 0x2000 guest, 0x1000 judge
    @offset = 0x2A items : uint16[5]      // equipment item ids
    @offset = 0x3A reaction : uint8       // race list index of the reaction ability
    @offset = 0x3B support : uint8        // race list index of the support ability
    @offset = 0x3D move_plus : uint8      // 1: Move + 1
    @offset = 0x40 learned : uint8[144]   // race list entry i: bit 0x80 learned
    @offset = 0xD0 ct : uint16
    @offset = 0xD2 speed : uint16         // base Speed
    @offset = 0xD4 reserve : uint16       // CT reserve (see tick)
    @offset = 0xE8 status : uint8[6]      // status bits +0xE8..+0xED
    @offset = 0x104 order : uint8         // list order, breaks ties
}

def read_unit(rec : uint) : BattleUnit {
    var r : UnitRecord
    read_struct(rec, r)
    var u = BattleUnit(record = rec, name = ffta_text(r.name), level = int(r.level), hp = int(r.hp),
        max_hp = int(r.max_hp), mp = int(r.mp), ct = int(r.ct), base_speed = int(r.speed),
        reserve = int(r.reserve), order = int(r.order))
    u.job_id = int(r.job)
    u.job2 = int(r.job2)
    u.race = int(r.race)
    u.character = int(r.character)
    u.move_plus = r.move_plus == 1u8 ? 1 : 0
    let job = read_job(uint(r.job), uint(r.job2))
    u.job = ffta_text_id(int(job.name))
    for (i in range(4)) {
        u.stat_base[i] = int(r.stats[i])
    }
    u.stat_base[int(Stat.Speed)] = int(r.speed)
    u.stat_base[int(Stat.Evade)] = int(job.evade)
    u.stat_base[int(Stat.Move)] = int(job.move) + (r.move_plus == 1u8 ? 1 : 0)
    u.stat_base[int(Stat.Jump)] = int(job.jump)
    for (i in range(5)) {
        u.items[i] = uint(r.items[i])
        u.equip[i] = read_item(u.items[i])
        for (s in range(STAT_COUNT)) {
            u.stat_items[s] += u.equip[i].bonus[s]
        }
    }
    for (s in range(STAT_COUNT)) {
        u.stat_total[s] = stat_total(s, u.stat_base[s], u.stat_items[s])
    }
    u.item_speed = u.stat_items[int(Stat.Speed)]
    u.flags = uint(r.flags)
    for (e in range(9)) {
        u.affinity[e] = int(r.affinity[e])
    }
    // 0x08130820 reads the unit's own job entry, without the parent chain
    u.bare_power = gba_has_rom() ? int(gba_read8(JOB_TABLE + uint(r.job) * 52u + 0x33u)) : 0
    let sup = race_ability(int(r.race), int(r.support))
    u.support = sup.kind == 3 ? sup.id : 0
    u.support_name = u.support != 0 ? ffta_text2(sup.name) : "none"
    let rea = race_ability(int(r.race), int(r.reaction))
    u.reaction = rea.kind == 2 ? rea.id : 0
    u.reaction_name = u.reaction != 0 ? ffta_text2(rea.name) : "none"
    for (i in range(1, 144)) {
        u.learned[i] = (uint(r.learned[i]) & 0x80u) != 0u
    }
    update_actions(u)
    for (i in range(6)) {
        u.status[i] = uint(r.status[i])
    }
    u.speed = effective_speed(u)
    u.status_text = status_text(u)
    return u
}

def private valid_record(rec : uint) : bool {
    if (rec < 0x02000000u || rec >= 0x02040000u - UNIT_STRIDE) {
        return false
    }
    let name = gba_read32(rec)
    let hp = gba_read16(rec + 0x18u)
    let max_hp = gba_read16(rec + 0x1Au)
    let region = name >> 24u
    return (region == 2u || region == 8u) && max_hp > 0u && max_hp < 1000u && hp <= max_hp
}

// The participants: an array of 0x90-byte wrappers whose first word
// points to the unit record (0x020223AC in the test save). Found by
// scanning EWRAM for the longest run of such wrappers.
def find_wrappers() : uint {
    var best = 0u
    var best_len = 0
    var a = 0x02000000u
    while (a < 0x02040000u - WRAPPER_STRIDE * 4u) {
        var n = 0
        while (valid_record(gba_read32(a + uint(n) * WRAPPER_STRIDE))) {
            n++
        }
        if (n > best_len) {
            best_len = n
            best = a
        }
        a += 4u
    }
    return best_len >= 2 ? best : 0u
}

// Whose unit: from the record flags +0x28. Not the wrapper's +0x1E
// (side): in the second battle the goblins have 0 there, like Marc, and
// Cristine and Nusratt of the clan have 1. TEAM_*: core/teams.das.
def team(u : BattleUnit) : int {
    if ((u.flags & 0x8000u) != 0u) {
        return TEAM_ENEMY
    }
    if ((u.flags & 0x1000u) != 0u) {
        return TEAM_JUDGE
    }
    return (u.flags & 0x2000u) != 0u ? TEAM_GUEST : TEAM_PLAYER
}

def read_battle(var units : array<BattleUnit>) : string {
    units |> clear()
    ensure(gba_has_state(), "no state loaded")
    let w = find_wrappers()
    ensure(w != 0u, "no battle in this state")
    var k = 0u
    while (true) {
        let rec = gba_read32(w + k * WRAPPER_STRIDE)
        if (!valid_record(rec)) {
            break
        }
        var u = read_unit(rec)
        let wr = w + k * WRAPPER_STRIDE
        u.wrapper = wr
        u.side = int(gba_read8(wr + 0x1Eu))
        u.x = int(gba_read16(wr + 0x08u) >> 5u)
        u.y = int(gba_read16(wr + 0x0Cu) >> 5u)
        u.facing = int(gba_read8(wr + 0x1Fu))
        u.position = "{u.x}, {u.y}, facing {FACING_NAMES[u.facing & 3]}"
        units |> push(u)
        k++
    }
    return ""
}

// ------------------------------------------------------------ the map

// The battle map (0x02007F10, read by 0x0801CC18 / 0x0801CD08 /
// 0x0801CC7C): +0x04 pointer to the tiles, 2 bytes each (height, flags),
// +0x08 tiles per row, +0x0A / +0x0C first x / y, +0x0D / +0x0F width /
// height of the playable area. Height 0: no tile.
let MAP_INFO = 0x02007F10u

struct BattleMap {
    w : int
    h : int
    x0 : int
    y0 : int
    height : array<int>             // (y - y0) * w + (x - x0)
    flags : array<int>              // 0x01 ?, 0x02 water (a unit in it stands 1 lower)
}

def read_map(var m : BattleMap) : bool {
    m.height |> clear()
    m.flags |> clear()
    m.w = int(gba_read8(MAP_INFO + 0x0Du))
    m.h = int(gba_read8(MAP_INFO + 0x0Fu))
    m.x0 = int(gba_read8(MAP_INFO + 0x0Au))
    m.y0 = int(gba_read8(MAP_INFO + 0x0Cu))
    let stride = gba_read8(MAP_INFO + 0x08u)
    let tiles = gba_read32(MAP_INFO + 0x04u)
    if (m.w == 0 || m.h == 0 || m.w > 64 || m.h > 64 || tiles < 0x02000000u || tiles >= 0x02040000u) {
        m.w = 0
        m.h = 0
        return false
    }
    for (y in range(m.h)) {
        for (x in range(m.w)) {
            let a = tiles + (uint(y + m.y0) * stride + uint(x + m.x0)) * 2u
            m.height |> push(int(gba_read8(a)))
            m.flags |> push(int(gba_read8(a + 1u)))
        }
    }
    return true
}

// the height of tile (x, y), 0: no tile
def tile_height(m : BattleMap; x, y : int) : int {
    let tx = x - m.x0
    let ty = y - m.y0
    return tx >= 0 && ty >= 0 && tx < m.w && ty < m.h ? m.height[ty * m.w + tx] : 0
}

def tile_flags(m : BattleMap; x, y : int) : int {
    let tx = x - m.x0
    let ty = y - m.y0
    return tx >= 0 && ty >= 0 && tx < m.w && ty < m.h ? m.flags[ty * m.w + tx] : 0
}

// ------------------------------------------------------------ the model

// 0x0809DF7C: everyone gains reserve + speed; the excess of the top CT
// over 1000 (at most 500) moves from every CT into the reserve.
def tick(var units : array<BattleUnit>) {
    var top = -8000
    for (u in units) {
        if (eligible(u)) {
            u.ct = u.ct + u.reserve + u.speed
        } else {
            u.ct = 0
        }
        u.reserve = 0
        top = max(top, u.ct)
    }
    if (top > CT_TURN) {
        let e = min(top - CT_TURN, 500)
        for (u in units) {
            let d = u.ct - e
            if (d < 0) {
                u.reserve = u.ct
                u.ct = 0
            } else {
                u.reserve = e
                u.ct = d
            }
        }
    }
}

// 0x0809E05C: Quick (+0xE8 & 2) first; else tick until an eligible unit
// has CT > 999, then the largest (CT + reserve) << 8 | order. Returns the
// index and the number of ticks it took.
def next_actor(var units : array<BattleUnit>; var ticks : int&) : int {
    ticks = 0
    for (i in range(length(units))) {
        if ((units[i].status[0] & 0x02u) != 0u && eligible(units[i])) {
            units[i].reserve = 0x1000
            return i
        }
    }
    while (ticks < 10000 && count(units, $(u) => eligible(u) && u.ct > CT_TURN - 1) == 0) {
        tick(units)
        ticks++
    }
    if (length(units) == 0) {
        return -1
    }
    let indices <- [for (i in range(length(units))); i]
    return _max_by(indices, actor_key(units[_]))
}

// the actor is the max of (CT + reserve) << 8 | order; not eligible: -100
def actor_key(u : BattleUnit) : int {
    return (eligible(u) ? u.ct + u.reserve : -100) * 256 + u.order
}

def end_turn(var u : BattleUnit; how : TurnEnd) {
    var ct = u.ct - 500
    if (how == TurnEnd.MoveAndAct || how == TurnEnd.MoveOnly) {
        ct -= 200
    }
    if (how == TurnEnd.MoveAndAct || how == TurnEnd.ActOnly) {
        ct -= 300
    }
    u.ct = max(ct, 0)
    u.reserve = 0
}

struct Turn {
    unit : int        // index in the units array
    ticks : int       // ticks spent waiting for this turn
    ct : int          // CT at the start of the turn
}

// The next `count` turns. If a unit is mid-turn (CT >= 1000 in the
// state), it is the first entry. Each unit ends its turns as assumed.
def predict_turns(units : array<BattleUnit>; count : int) : array<Turn> {
    var sim := units
    var res : array<Turn>
    var current = -1
    var top = CT_TURN - 1
    for (i in range(length(sim))) {
        if (eligible(sim[i]) && sim[i].ct > top) {
            top = sim[i].ct
            current = i
        }
    }
    if (current >= 0) {
        res |> push(Turn(unit = current, ticks = 0, ct = sim[current].ct))
        end_turn(sim[current], sim[current].assumed)
    }
    while (length(res) < count) {
        var ticks = 0
        let i = next_actor(sim, ticks)
        if (i < 0) {
            break
        }
        res |> push(Turn(unit = i, ticks = ticks, ct = sim[i].ct))
        end_turn(sim[i], sim[i].assumed)
    }
    return <- res
}

// ------------------------------------------------------------ export

// Race list index of an ability (kind 2 reaction, 3 support), 0 if the
// race has none with this id.
def race_index(race, kind, id : int) : int {
    if (id == 0) {
        return 0
    }
    for (i in range(1, 144)) {
        let a = race_ability(race, i)
        if (a.kind == kind && a.id == id) {
            return i
        }
    }
    return 0
}

// Equips a support (kind 3) or reaction (kind 2) and marks it learned,
// as the game requires; 0 removes it.
def set_ability(var u : BattleUnit; kind, id : int) {
    if (kind == 3) {
        u.support = id
    } else {
        u.reaction = id
    }
    let idx = race_index(u.race, kind, id)
    if (idx > 0 && idx < 144) {
        u.learned[idx] = true
    }
}

// Puts a unit into the edit copy of RAM (gba_edit_begin): the record
// fields the editor changes, its position and facing in the wrapper and
// the record copy (+0xF6 / +0xF7 / +0xF8). Evade, Move and Jump come from
// the job and can not be written; their edits are reported.
def write_unit(m : BattleMap; u, orig : BattleUnit) : string {
    let rec = u.record
    var notes = ""
    gba_edit8(rec + 0x05u, uint(u.job_id))
    gba_edit8(rec + 0x07u, uint(u.job2))
    gba_edit16(rec + 0x18u, uint(u.hp))
    gba_edit16(rec + 0x1Au, uint(u.max_hp))
    gba_edit16(rec + 0x1Cu, uint(u.mp))
    for (i in range(4)) {
        gba_edit16(rec + 0x20u + uint(i) * 2u, uint(clamp(u.stat_base[i], 0, 999)))
    }
    gba_edit16(rec + 0xD2u, uint(clamp(u.stat_base[int(Stat.Speed)], 0, 999)))
    gba_edit16(rec + 0xD0u, uint(u.ct))
    gba_edit16(rec + 0xD4u, uint(u.reserve))
    for (i in range(5)) {
        gba_edit16(rec + 0x2Au + uint(i) * 2u, uint(u.equip[i].id))
    }
    for (i in range(6)) {
        gba_edit8(rec + 0xE8u + uint(i), u.status[i])
    }
    for (i in range(1, 144)) {
        if (u.learned[i] != orig.learned[i]) {
            let b = gba_read8(rec + 0x40u + uint(i))
            gba_edit8(rec + 0x40u + uint(i), u.learned[i] ? (b | 0x80u) : (b & 0x7Fu))
        }
    }
    for (c in [(0x3Bu, 3, u.support, orig.support), (0x3Au, 2, u.reaction, orig.reaction)]) {
        let idx = race_index(u.race, c._1, c._2)
        if (idx == 0 && c._2 != 0) {
            notes += "{u.name}: the race has no ability {c._2}; "
        } elif (c._2 != c._3) {
            gba_edit8(rec + c._0, uint(idx))
            if (idx != 0) {
                gba_edit8(rec + 0x40u + uint(idx), gba_read8(rec + 0x40u + uint(idx)) | 0x80u)
            }
        }
    }
    for (s in [Stat.Evade, Stat.Move, Stat.Jump]) {
        if (u.stat_base[int(s)] != orig.stat_base[int(s)] && u.job_id == orig.job_id) {
            notes += "{u.name}: {STAT_NAMES[int(s)]} comes from the job, not written; "
        }
    }
    if (u.wrapper != 0u) {
        gba_edit16(u.wrapper + 0x08u, uint(u.x * 32 + 16))
        gba_edit16(u.wrapper + 0x0Cu, uint(u.y * 32 + 16))
        gba_edit16(u.wrapper + 0x0Au, uint(tile_height(m, u.x, u.y) * 16))
        gba_edit8(u.wrapper + 0x1Fu, uint(u.facing & 3))
        gba_edit8(rec + 0xF6u, uint(u.x))
        gba_edit8(rec + 0xF7u, uint(u.y))
        gba_edit8(rec + 0xF8u, uint(u.facing & 3))
    }
    return notes
}

// Writes the loaded state with the edited units to path. Returns an
// error ("") and the notes on what could not be written.
def export_battle(m : BattleMap; units, orig : array<BattleUnit>; path : string; var notes : string) : string {
    notes = ""
    ensure(gba_has_state(), "no state loaded")
    gba_edit_begin()
    for (i in range(length(units))) {
        notes += write_unit(m, units[i], i < length(orig) ? orig[i] : units[i])
    }
    try_ok(gba_save_state(path))
    return ""
}
