options gen2
options indenting = 4

// Final Fantasy Tactics: The War of the Lions (PSP, USA, ULUS10297): the
// game's tables, read from the RAM of a PPSSPP state (BOOT.BIN is loaded
// at a fixed address: RAM = file offset + 0x08803FAC). Layouts:
// research/fftwotl/layouts.md; the text: research/fftwotl/notes.md.
module fftwotl_data shared public

require gba_mem
require math
require strings
require daslib/strings_boost
require ../../core/util.das

let WOTL_GAME_ID = "ULUS10297"
let private GAME_ID_AT = 0x08B18354u

// tables (RAM addresses)
let private ABILITY_COMMON = 0x08A754C0u       // 8 B x 512
let private ABILITY_ACTION = 0x08A764C0u       // 14 B x 0x170
let private ABILITY_ITEM = 0x08A778E0u         // 1 B: item of 0x170..0x17D
let private ABILITY_THROW = 0x08A778F0u        // 1 B: item type of 0x17E..0x189
let private ABILITY_JUMP = 0x08A778FCu         // 2 B: horizontal, vertical of 0x18A..0x195
let private ABILITY_CHARGE = 0x08A77914u       // 2 B: CT, power bonus of 0x196..0x19D
let private ITEM_OLD = 0x08B29288u             // 12 B, ids 0..0xFF
let private ITEM_NEW = 0x08A5ADACu             // 12 B, ids 0x100..0x13B
let private ATTR_OLD = 0x08B2A694u             // 25 B, attribute ids 0..0x4F
let private ATTR_NEW = 0x08A5B1B8u             // 25 B, 0x50..
let private INFLICT = 0x08B2A394u              // 6 B x 128
let private JOBS = 0x08A77988u                 // 49 B x 0xA9
let private SKILLSETS = 0x08A799E4u            // 25 B x 179 (0..0xAF, then 0xE0..0xE2)
let private MONSTER_SKILLSETS = 0x08A7AB60u    // 5 B x 48 (0xB0..0xDF)
let private STATUS_ATTR = 0x08A7AD50u          // 16 B x 40

// name lists: the address of the entry-0 string, the count
let private JOB_NAMES = 0x08A92FF4u
let private ITEM_NAMES = 0x08A935FDu
let private ABILITY_NAMES = 0x08A95399u
let private STATUS_NAMES = 0x08A96AC8u
let private SKILLSET_NAMES = 0x08A9775Du

let ITEM_COUNT_W = 316
let ABILITY_COUNT_W = 512
let JOB_COUNT_W = 169
let SKILLSET_COUNT_W = 227
let STATUS_COUNT_W = 40

// ability kinds (low nibble of the common data byte 3)
let AB_NORMAL = 1
let AB_ITEM = 2
let AB_THROW = 3
let AB_JUMP = 4
let AB_CHARGE = 5
let AB_MATH = 6
let AB_REACTION = 7
let AB_SUPPORT = 8
let AB_MOVEMENT = 9

// item kinds (item byte 5; also the bit of the job's equip flags)
let KIND_W_NAMES = fixed_array<string>("", "Knife", "Ninja Blade", "Sword", "Knight's Sword", "Katana", "Axe", "Rod",
    "Staff", "Flail", "Gun", "Crossbow", "Bow", "Instrument", "Book", "Polearm", "Pole", "Bag", "Cloth", "Shield",
    "Helmet", "Hat", "Hair Adornment", "Armor", "Clothing", "Robe", "Shoes", "Armguard", "Ring", "Armlet", "Cloak",
    "Perfume", "Shuriken", "Bomb", "Item", "Fell Sword", "Lip Rouge")
let KIND_SHIELD = 19

// elements: bit 0x80 >> n
let ELEMENT_W_NAMES = fixed_array<string>("Fire", "Lightning", "Ice", "Wind", "Earth", "Water", "Holy", "Dark")

// equipment slots of the unit record (+0x1A, u16 each)
let SLOT_W_NAMES = fixed_array<string>("Head", "Body", "Accessory", "Right hand", "Right shield", "Left hand",
    "Left shield")
let SLOT_HEAD = 0
let SLOT_BODY = 1
let SLOT_ACCESSORY = 2
let SLOT_RIGHT = 3
let SLOT_RIGHT_SHIELD = 4
let SLOT_LEFT = 5
let SLOT_LEFT_SHIELD = 6
let ITEM_NONE = 255                // an empty slot (item 0xFF is a dummy)

// ------------------------------------------------------------ text

// The single-byte FFT encoding: 0..9 digits, 0x0A.. A..Z, 0x24.. a..z,
// 0x95 / 0xFA space, 0xFE the end of a string; two-byte symbols after
// 0xD0..0xDA (0xD1 0x1D "-", 0xDA 0x62 / 0x63 "è").
def wotl_char(c, next : int; var len : int&) : string {
    len = 1
    if (c < 10) {
        return "{c}"
    } elif (c < 0x24) {
        return to_char(65 + c - 10)
    } elif (c < 0x3E) {
        return to_char(97 + c - 0x24)
    } elif (c == 0x95 || c == 0xFA) {
        return " "
    } elif (c == 0x93) {
        return "'"
    } elif (c == 0x42) {
        return "+"
    } elif (c == 0x46) {
        return ":"
    } elif (c >= 0xD0 && c <= 0xDA) {
        len = 2
        if (c == 0xD1 && next == 0x1D) {
            return "-"
        } elif (c == 0xDA && (next == 0x62 || next == 0x63)) {
            return "è"
        }
        return "?"
    }
    return "?"
}

// the string at a (up to 0xFE, at most max_len bytes)
def wotl_text(a : uint; max_len : int = 64) : string {
    var res = ""
    var i = 0
    while (i < max_len) {
        let c = int(gba_read8(a + uint(i)))
        if (c == 0xFE) {
            break
        }
        var len = 1
        res += wotl_char(c, int(gba_read8(a + uint(i) + 1u)), len)
        i += len
    }
    return res
}

struct private NameCache {
    serial : uint = 0xFFFFFFFFu
    jobs : array<string>
    items : array<string>
    abilities : array<string>
    statuses : array<string>
    skillsets : array<string>
}

var private names = NameCache()

// a list of n strings separated by 0xFE from a
def private read_list(a : uint; n : int) : array<string> {
    var res : array<string>
    var p = a
    for (i in range(n)) {
        var len = 0
        while (len < 200 && gba_read8(p + uint(len)) != 0xFEu) {
            len++
        }
        res |> push(wotl_text(p, len))
        p += uint(len + 1)
    }
    return <- res
}

def private ensure_names() {
    if (names.serial == gba_state_serial()) {
        return
    }
    names.serial = gba_state_serial()
    names.jobs <- read_list(JOB_NAMES, JOB_COUNT_W)
    names.items <- read_list(ITEM_NAMES, ITEM_COUNT_W)
    names.abilities <- read_list(ABILITY_NAMES, ABILITY_COUNT_W)
    names.statuses <- read_list(STATUS_NAMES, STATUS_COUNT_W)
    names.skillsets <- read_list(SKILLSET_NAMES, SKILLSET_COUNT_W)
}

def private name_at(list : array<string>; i : int) : string {
    return i >= 0 && i < length(list) ? list[i] : ""
}

def job_name_w(job : int) : string {
    ensure_names()
    return name_at(names.jobs, job)
}

// dummy items are named like "{92}{94}{b6}-0278": shown as "item N"
def item_name_w(id : int) : string {
    ensure_names()
    if (id == ITEM_NONE || id <= 0) {
        return "-"
    }
    let s = name_at(names.items, id)
    return s == "" || starts_with(s, "???") ? "item {id}" : s
}

def ability_name_w(id : int) : string {
    ensure_names()
    return name_at(names.abilities, id)
}

def status_name_w(n : int) : string {
    ensure_names()
    return name_at(names.statuses, n)
}

def skillset_name_w(id : int) : string {
    ensure_names()
    return name_at(names.skillsets, id)
}

// the state is this game: the game id in BOOT.BIN
def is_wotl_state() : bool {
    if (!gba_has_state() || !gba_state_is_psp()) {
        return false
    }
    var s = ""
    for (i in range(9)) {
        s += to_char(int(gba_read8(GAME_ID_AT + uint(i))))
    }
    return s == WOTL_GAME_ID
}

// ------------------------------------------------------------ statuses

// 40 statuses, bit n = byte n / 8, mask 0x80 >> n % 8 (as the unit
// record and the tables keep them)
def status_bit(sts : uint8[5]; n : int) : bool {
    return n >= 0 && n < STATUS_COUNT_W && msb_bit(sts, n)
}

def set_status_bit(var sts : uint8[5]; n : int; on : bool) {
    set_msb_bit(sts, n, on)
}

def read_statuses(a : uint) : uint8[5] {
    var s : uint8[5]
    for (k in range(5)) {
        s[k] = uint8(gba_read8(a + uint(k)))
    }
    return s
}

// status numbers (the order of the status names)
let ST_DEAD = 2
let ST_UNDEAD = 3
let ST_CHARGING = 4
let ST_JUMP = 5
let ST_DEFENDING = 6
let ST_PETRIFY = 8
let ST_INVITE = 9
let ST_DARKNESS = 10
let ST_CONFUSION = 11
let ST_SILENCE = 12
let ST_OIL = 16
let ST_FLOAT = 17
let ST_RERAISE = 18
let ST_TRANSPARENT = 19
let ST_BERSERK = 20
let ST_CHICKEN = 21
let ST_FROG = 22
let ST_CRITICAL = 23
let ST_POISON = 24
let ST_REGEN = 25
let ST_PROTECT = 26
let ST_SHELL = 27
let ST_HASTE = 28
let ST_SLOW = 29
let ST_STOP = 30
let ST_WALL = 31
let ST_FAITH = 32
let ST_INNOCENT = 33
let ST_CHARM = 34
let ST_SLEEP = 35
let ST_DONT_MOVE = 36
let ST_DONT_ACT = 37
let ST_REFLECT = 38
let ST_DOOM = 39

// a status's clock: its CT (0: until removed) and whether it stops the
// unit's own CT (Stop, Sleep, ...: "freeze CT")
def status_ct_w(n : int) : int {
    return int(gba_read8(STATUS_ATTR + uint(n) * 16u + 3u))
}

def status_freezes_ct(n : int) : bool {
    return (gba_read8(STATUS_ATTR + uint(n) * 16u + 4u) & 0x80u) != 0u
}

// ------------------------------------------------------------ items

struct ItemW {
    id : int
    name : string
    kind : int                      // KIND_W_NAMES
    flags : int                     // 0x80 weapon, 0x40 shield, 0x20 head, 0x10 body, 0x08 accessory
    level : int
    price : int
    attr : int                      // the attribute record (0 none)
    // weapon
    reach : int
    wflags : int                    // 0x80 striking, 0x40 lunging, 0x20 direct, 0x10 arc, 0x08 dual, 0x04 two-handable, 0x02 throwable, 0x01 forced two hands
    formula : int
    wp : int
    w_ev : int
    element : int
    inflict : int
    // shield / accessory: evade %; head / body: HP / MP bonus
    p_ev : int
    m_ev : int
    hp : int
    mp : int
    // chemist item: formula (above), X, inflict (above)
    x : int
    // attributes
    pa : int
    ma : int
    sp : int
    move : int
    jump : int
    always : uint8[5]               // statuses always on
    immune : uint8[5]
    start : uint8[5]
    absorb : int
    cancel : int
    half : int
    weak : int
    strengthen : int
}

def private item_base(id : int) : uint {
    return id < 0x100 ? ITEM_OLD + uint(id) * 12u : ITEM_NEW + uint(id - 0x100) * 12u
}

// the secondary record of an item: by the range of ids of its category
// (layouts.md, "Items"): table address and entry size, 0 when none
def private item_secondary(id : int; var size : int&) : uint {
    size = 0
    if (id > 0 && id < 0x80) {
        size = 8
        return 0x08B29E88u + uint(id) * 8u
    } elif (id >= 0x80 && id < 0x90) {
        size = 2
        return 0x08B2A288u + uint(id - 0x80) * 2u
    } elif (id >= 0x90 && id < 0xD0) {
        size = 2
        return 0x08B2A2A8u + uint(id - 0x90) * 2u
    } elif (id >= 0xD0 && id < 0xF0) {
        size = 2
        return 0x08B2A328u + uint(id - 0xD0) * 2u
    } elif (id >= 0xF0 && id < 0xFE) {
        size = 3
        return 0x08B2A368u + uint(id - 0xF0) * 3u
    } elif (id >= 0x100 && id < 0x120) {
        size = 8
        return 0x08A5B07Cu + uint(id - 0x100) * 8u
    } elif (id >= 0x120 && id < 0x124) {
        size = 2
        return 0x08A5B17Cu + uint(id - 0x120) * 2u
    } elif (id >= 0x124 && id < 0x134) {
        size = 2
        return 0x08A5B184u + uint(id - 0x124) * 2u
    } elif (id >= 0x134 && id < 0x13C) {
        size = 2
        return 0x08A5B1A4u + uint(id - 0x134) * 2u
    }
    return 0u
}

def read_item_w(id : int) : ItemW {
    var it = ItemW(id = id)
    if (id <= 0 || id >= ITEM_COUNT_W || id == ITEM_NONE || id == 254) {
        it.id = ITEM_NONE
        it.name = "-"
        return it
    }
    let b = item_base(id)
    it.name = item_name_w(id)
    it.level = int(gba_read8(b + 2u))
    it.flags = int(gba_read8(b + 3u))
    it.kind = int(gba_read8(b + 5u))
    it.attr = int(gba_read8(b + 7u))
    it.price = int(gba_read16(b + 8u))
    var size = 0
    let s = item_secondary(id, size)
    if (size == 8) {
        it.reach = int(gba_read8(s))
        it.wflags = int(gba_read8(s + 1u))
        it.formula = int(gba_read8(s + 2u))
        it.wp = int(gba_read8(s + 4u))
        it.w_ev = int(gba_read8(s + 5u))
        it.element = int(gba_read8(s + 6u))
        it.inflict = int(gba_read8(s + 7u))
    } elif (size == 3) {
        it.formula = int(gba_read8(s))
        it.x = int(gba_read8(s + 1u))
        it.inflict = int(gba_read8(s + 2u))
    } elif (size == 2) {
        let a = int(gba_read8(s))
        let c = int(gba_read8(s + 1u))
        if ((it.flags & 0x30) != 0) {
            it.hp = a
            it.mp = c
        } else {
            it.p_ev = a
            it.m_ev = c
        }
    }
    if (it.attr != 0) {
        let a = it.attr < 0x50 ? ATTR_OLD + uint(it.attr) * 25u : ATTR_NEW + uint(it.attr - 0x50) * 25u
        it.pa = int(gba_read8(a))
        it.ma = int(gba_read8(a + 1u))
        it.sp = int(gba_read8(a + 2u))
        it.move = int(gba_read8(a + 3u))
        it.jump = int(gba_read8(a + 4u))
        it.always = read_statuses(a + 5u)
        it.immune = read_statuses(a + 10u)
        it.start = read_statuses(a + 15u)
        it.absorb = int(gba_read8(a + 20u))
        it.cancel = int(gba_read8(a + 21u))
        it.half = int(gba_read8(a + 22u))
        it.weak = int(gba_read8(a + 23u))
        it.strengthen = int(gba_read8(a + 24u))
    }
    return it
}

def is_weapon_w(it : ItemW) : bool {
    return (it.flags & 0x80) != 0
}

def is_shield_w(it : ItemW) : bool {
    return (it.flags & 0x40) != 0
}

// the slots an item can go to (SLOT_*)
def item_fits_slot(it : ItemW; slot : int) : bool {
    if (it.id == ITEM_NONE) {
        return true
    }
    if (slot == SLOT_HEAD) {
        return (it.flags & 0x20) != 0
    } elif (slot == SLOT_BODY) {
        return (it.flags & 0x10) != 0
    } elif (slot == SLOT_ACCESSORY) {
        return (it.flags & 0x08) != 0
    } elif (slot == SLOT_RIGHT || slot == SLOT_LEFT) {
        return (it.flags & 0xC0) != 0
    }
    return (it.flags & 0x40) != 0
}

def element_text(mask : int) : string {
    var parts : array<string>
    for (e in range(8)) {
        if ((mask & (0x80 >> e)) != 0) {
            parts |> push(ELEMENT_W_NAMES[e])
        }
    }
    return join_or(parts, ", ", "-")
}

def status_text(sts : uint8[5]) : string {
    var parts : array<string>
    for (n in range(STATUS_COUNT_W)) {
        if (status_bit(sts, n)) {
            parts |> push(status_name_w(n))
        }
    }
    return join_or(parts, ", ", "-")
}

// an inflict-status record: 0x80 all or nothing, 0x40 random one, 0x20
// separate, 0x10 cancel (remove); the statuses
struct InflictW {
    mode : int
    statuses : uint8[5]
}

def read_inflict_w(id : int) : InflictW {
    var r : InflictW
    if (id <= 0 || id >= 128) {
        return r
    }
    let a = INFLICT + uint(id) * 6u
    r.mode = int(gba_read8(a))
    r.statuses = read_statuses(a + 1u)
    return r
}

def inflict_text(id : int) : string {
    if (id <= 0) {
        return "-"
    }
    let r = read_inflict_w(id)
    let how = (r.mode & 0x10) != 0 ? "removes " : ((r.mode & 0x40) != 0 ? "one of " : "")
    return "{how}{status_text(r.statuses)}"
}

// ------------------------------------------------------------ abilities

struct AbilityW {
    id : int
    name : string
    jp : int
    learn_rate : int
    kind : int                      // AB_*
    learn_flags : int               // common byte 3 high nibble
    ai : int4                       // common bytes 4..7
    // action data (normal abilities)
    reach : int
    area : int
    vertical : int
    f1 : int                        // 0x80 self, 0x20 weapon range, 0x10 vertical fixed, 0x08 vertical tolerance, 0x04 weapon strike, 0x02 auto, 0x01 cannot target self
    f2 : int                        // 0x80 no enemies, 0x40 no allies, 0x20 top-down, 0x10 does not follow, 0x08 random fire, 0x04 linear, 0x02 3 directions, 0x01 not the caster
    f3 : int                        // 0x80 reflectable, 0x40 Arithmeticks, 0x20 Silence blocks, 0x10 no Mimic, 0x08 normal attack, 0x04 persevere, 0x02 quote, 0x01 animate on miss
    f4 : int                        // 0x80 counter flood, 0x40 counter magic, 0x20 direct, 0x10 Shirahadori, 0x08 needs a sword, 0x04 needs Materia Blade, 0x02 evadable, 0x01 no targeting
    element : int
    formula : int
    x : int
    y : int
    inflict : int
    ct : int
    mp : int
    // other kinds: the item used (Items), the item kind thrown (Throw),
    // the jump's reach (horizontal, vertical), Aim's CT and power bonus
    item : int
    throw_kind : int
    jump_h : int
    jump_v : int
}

def read_ability_w(id : int) : AbilityW {
    var a = AbilityW(id = id)
    if (id <= 0 || id >= ABILITY_COUNT_W) {
        return a
    }
    let c = ABILITY_COMMON + uint(id) * 8u
    a.name = ability_name_w(id)
    a.jp = int(gba_read16(c))
    a.learn_rate = int(gba_read8(c + 2u))
    let t = int(gba_read8(c + 3u))
    a.kind = t & 15
    a.learn_flags = t & 0xF0
    a.ai = int4(int(gba_read8(c + 4u)), int(gba_read8(c + 5u)), int(gba_read8(c + 6u)), int(gba_read8(c + 7u)))
    if (id < 0x170) {
        let d = ABILITY_ACTION + uint(id) * 14u
        a.reach = int(gba_read8(d))
        a.area = int(gba_read8(d + 1u))
        a.vertical = int(gba_read8(d + 2u))
        a.f1 = int(gba_read8(d + 3u))
        a.f2 = int(gba_read8(d + 4u))
        a.f3 = int(gba_read8(d + 5u))
        a.f4 = int(gba_read8(d + 6u))
        a.element = int(gba_read8(d + 7u))
        a.formula = int(gba_read8(d + 8u))
        a.x = int(gba_read8(d + 9u))
        a.y = int(gba_read8(d + 10u))
        a.inflict = int(gba_read8(d + 11u))
        a.ct = int(gba_read8(d + 12u))
        a.mp = int(gba_read8(d + 13u))
    } elif (id < 0x17E) {
        a.item = int(gba_read8(ABILITY_ITEM + uint(id - 0x170)))
    } elif (id < 0x18A) {
        a.throw_kind = int(gba_read8(ABILITY_THROW + uint(id - 0x17E)))
    } elif (id < 0x196) {
        a.jump_h = int(gba_read8(ABILITY_JUMP + uint(id - 0x18A) * 2u))
        a.jump_v = int(gba_read8(ABILITY_JUMP + uint(id - 0x18A) * 2u + 1u))
    } elif (id < 0x19E) {
        a.ct = int(gba_read8(ABILITY_CHARGE + uint(id - 0x196) * 2u))
        a.x = int(gba_read8(ABILITY_CHARGE + uint(id - 0x196) * 2u + 1u))
    }
    return a
}

// ------------------------------------------------------------ jobs

struct JobW {
    id : int
    name : string
    skillset : int
    innate : int[4]                 // abilities
    equip : uint8[5]                // a bit per item kind: byte k / 8, 0x80 >> k % 8
    hp_c : int                      // growth constants and multipliers
    hp_m : int
    mp_c : int
    mp_m : int
    sp_c : int
    sp_m : int
    pa_c : int
    pa_m : int
    ma_c : int
    ma_m : int
    move : int
    jump : int
    c_ev : int
    always : uint8[5]
    immune : uint8[5]
    start : uint8[5]
    absorb : int
    cancel : int
    half : int
    weak : int
}

def read_job_w(job : int) : JobW {
    var j = JobW(id = job)
    if (job <= 0 || job >= JOB_COUNT_W) {
        return j
    }
    let b = JOBS + uint(job) * 49u
    j.name = job_name_w(job)
    j.skillset = int(gba_read8(b))
    for (k in range(4)) {
        j.innate[k] = int(gba_read16(b + 1u + uint(k) * 2u))
    }
    for (k in range(5)) {
        j.equip[k] = uint8(gba_read8(b + 9u + uint(k)))
    }
    j.hp_c = int(gba_read8(b + 14u))
    j.hp_m = int(gba_read8(b + 15u))
    j.mp_c = int(gba_read8(b + 16u))
    j.mp_m = int(gba_read8(b + 17u))
    j.sp_c = int(gba_read8(b + 18u))
    j.sp_m = int(gba_read8(b + 19u))
    j.pa_c = int(gba_read8(b + 20u))
    j.pa_m = int(gba_read8(b + 21u))
    j.ma_c = int(gba_read8(b + 22u))
    j.ma_m = int(gba_read8(b + 23u))
    j.move = int(gba_read8(b + 24u))
    j.jump = int(gba_read8(b + 25u)) & 0x7F
    j.c_ev = int(gba_read8(b + 26u))
    j.always = read_statuses(b + 27u)
    j.immune = read_statuses(b + 32u)
    j.start = read_statuses(b + 37u)
    j.absorb = int(gba_read8(b + 42u))
    j.cancel = int(gba_read8(b + 43u))
    j.half = int(gba_read8(b + 44u))
    j.weak = int(gba_read8(b + 45u))
    return j
}

def job_can_equip(j : JobW; kind : int) : bool {
    return kind >= 0 && kind < 40 && msb_bit(j.equip, kind)
}

// ------------------------------------------------------------ skillsets

struct SkillsetW {
    id : int
    name : string
    actions : array<int>            // ability ids (no empty slots)
    rsm : array<int>                // reaction / support / movement ability ids
    slots : int[22]                 // by slot (the learned bits' order): 16 actions, 6 R/S/M; 0 empty
}

def read_skillset_w(id : int) : SkillsetW {
    var s = SkillsetW(id = id, name = skillset_name_w(id))
    if (id <= 0) {
        return <- s
    }
    if (id >= 0xB0 && id < 0xE0) {
        // a monster's: high bits, then four ability low bytes
        let b = MONSTER_SKILLSETS + uint(id - 0xB0) * 5u
        let hi = int(gba_read8(b))
        for (k in range(4)) {
            let lo = int(gba_read8(b + 1u + uint(k)))
            let ab = lo + ((hi & (128 >> k)) != 0 ? 256 : 0)
            if (ab != 0) {
                s.actions |> push(ab)
            }
        }
        return <- s
    }
    let entry = id < 0xB0 ? id : (id >= 0xE0 && id <= 0xE2 ? 176 + id - 0xE0 : -1)
    if (entry < 0) {
        return <- s
    }
    let b = SKILLSETS + uint(entry) * 25u
    let hi = int(gba_read8(b)) << 8 | int(gba_read8(b + 1u))
    let hi_rsm = int(gba_read8(b + 2u))
    for (k in range(16)) {
        let lo = int(gba_read8(b + 3u + uint(k)))
        let ab = lo + ((hi & (32768 >> k)) != 0 ? 256 : 0)
        if (lo != 0) {
            s.actions |> push(ab)
            s.slots[k] = ab
        }
    }
    for (k in range(6)) {
        let lo = int(gba_read8(b + 19u + uint(k)))
        if (lo != 0) {
            s.rsm |> push(lo + ((hi_rsm & (128 >> k)) != 0 ? 256 : 0))
            s.slots[16 + k] = lo + ((hi_rsm & (128 >> k)) != 0 ? 256 : 0)
        }
    }
    return <- s
}

// every ability of a kind (AB_REACTION, ...), by id
def abilities_of_kind(kind : int) : array<int> {
    var res : array<int>
    for (id in range(1, ABILITY_COUNT_W)) {
        if ((int(gba_read8(ABILITY_COMMON + uint(id) * 8u + 3u)) & 15) == kind && ability_name_w(id) != "") {
            res |> push(id)
        }
    }
    return <- res
}
