options gen2
options indenting = 4

// Explore for Final Fantasy Tactics (PSX): the axes of an experiment
// (core/explore.das) are parameters of the attacker, the target or the
// scene; every combination is one action computed by the model
// (attack_forecast, ability_forecast), one row.
//
// Parameters (atk.* or tgt.*; attacker.* / target.* mean the same): pa ma
// sp (as in the record, with the equipment), brave faith hp max_hp mp
// max_mp ct level move jump, zodiac (0 Aries .. 11 Pisces, 12
// Serpentarius), weapon (the right hand; the item's bonuses follow),
// support, status.<name> (0 / 1: status.protect, status.shell, ...), job
// (read only: a job's PA / MA multipliers are not modelled). Scene: action
// (an ability, Attack = 0), side (1 front, 2 side, 3 back, 0 = by the
// positions).
// Values of vary: from..to [step s], a, b, ..., weapons, supports, actions,
// sides.
// Columns of every row: the axes, the parameters the script reads, and
// damage healing dmg_min dmg_max hit crit expected reach distance mp_cost
// xa ya zodiac_rel.
module fft_explore shared public

require math
require strings
require daslib/strings_boost
require ../../core/explore.das
require fft_battle
require fft_attack
require fft_abilities
require fft_reach

let MAX_POINTS_F = 20000

let METRICS_F = fixed_array<string>("damage", "healing", "dmg_min", "dmg_max", "hit", "crit", "expected", "reach",
    "distance", "mp_cost", "xa", "ya", "zodiac_rel")

let SIDE_F_LABELS = fixed_array<string>("Auto", "Front", "Side", "Back")

let ZODIAC_REL_F = fixed_array<string>("worst", "bad", "neutral", "good", "best")

let EXPLORE_F_GENERATORS = fixed_array<string>("weapons", "supports", "actions", "sides")

// the Jump abilities make one action (their reach: the best learned)
let JUMP_FIRST = 394
let JUMP_END = 406

// Explore: ready experiments (the editor starts with the first)
let EXPLORE_F_NAMES = fixed_array<string>("Damage by PA and Brave", "Every weapon", "Side and Protect",
    "Fire by MA and Faith", "Every action")
let EXPLORE_F_EXAMPLES = fixed_array<string>(
    "// the attacker and target of the Attack tab: Attack by the\n// attacker's PA, one line per Brave (knight swords and bare\n// hands use Brave)\nvary atk.pa 3..20\nvary atk.brave 40, 60, 80, 97\navg = expected\nplot avg by atk.pa per atk.brave title \"Average damage per Attack\"\n",
    "// every weapon in the attacker's right hand, best first\nvary atk.weapon weapons\navg = expected\nwhere damage > 0\nsort avg desc\nplot damage, avg by atk.weapon bar\n",
    "vary side sides\nvary tgt.status.protect 0, 1\nplot damage, hit by side per tgt.status.protect bar\n",
    "// a spell: the scene picks the action\nscene with Fire\nvary atk.ma 3..20\nvary tgt.faith 30, 50, 70, 90\nplot damage by atk.ma per tgt.faith\n",
    "// every action of the attacker's skillsets\nvary action actions\nwhere damage != 0\navg = expected\nsort avg desc\nplot avg by action bar\n")

// what the experiment starts from: the Attack tab
struct SceneF {
    att : FftUnit
    tgt : FftUnit
    ability : int = 0
    side : int                      // 0 auto, 1 front, 2 side, 3 back
}

// one action's result, as the Explore columns need it
struct FightF {
    unsupported : bool              // the ability's formula is not modelled
    damage : int                    // the most likely amount (the middle)
    dmg_min : int
    dmg_max : int
    healing : bool
    hit : int
    crit : int                      // %
    xa : int
    ya : int
    reach : bool
    mp_cost : int
    expected : float
}

// a status name as a key: "Death Sentence" -> deathsentence
def status_key_f(i : int) : string {
    var key = ""
    for (c in STATUS_NAMES[i]) {
        if (is_alpha(c) || is_number(c)) {
            key += to_lower(to_char(c))
        }
    }
    return key
}

def private status_index_f(key : string) : int {
    for (i in range(1, 40)) {
        if (status_key_f(i) == key) {
            return i
        }
    }
    return -1
}

def private split_path_f(path : string; var owner : string&; var key : string&) {
    let dot = find(path, ".")
    owner = dot < 0 ? path : slice(path, 0, dot)
    key = dot < 0 ? "" : slice(path, dot + 1)
}

def private item_value_f(item : int) : Value {
    return vtext(item <= 0 || item >= 0xFF ? "(none)" : item_name(item), double(item))
}

// an action's name: Attack, Jump (all the Jumps), the ability's
def action_name_f(id : int) : string {
    return id == 0 ? "Attack" : (id >= JUMP_FIRST && id < JUMP_END ? "Jump" : ability_name(id))
}

// the actions of a unit's skillsets (Attack first, the Jumps as one: the
// last learned, the longest reach)
def unit_actions_f(u : FftUnit; all_known : bool) : array<int> {
    var res : array<int>
    res |> push(0)
    var jump = -1
    for (ua in unit_abilities(u)) {
        if (!ua.learned && !all_known) {
            continue
        }
        if (ua.id >= JUMP_FIRST && ua.id < JUMP_END) {
            if (jump < 0) {
                jump = length(res)
                res |> push(ua.id)
            } else {
                res[jump] = ua.id
            }
        } elif (find_index(res, ua.id) < 0) {
            res |> push(ua.id)
        }
    }
    return <- res
}

// a parameter of a unit; false: there is no such parameter
def unit_param_f(u : FftUnit; key : string; var v : Value) : bool {
    let nums = fixed_array<string>("pa", "ma", "sp", "speed", "brave", "faith", "hp", "max_hp", "mp", "max_mp", "ct",
        "level", "move", "jump", "zodiac")
    let ni = find_index(nums, key)
    if (ni >= 0) {
        let vals = fixed_array<int>(u.pa, u.ma, u.speed, u.speed, u.brave, u.faith, u.hp, u.max_hp, u.mp, u.max_mp, u.ct,
            u.level, u.move, u.jump, u.zodiac)
        v = vnum(double(vals[ni]))
        return true
    }
    if (key == "job") {
        v = vtext(u.job, double(u.job_id))
        return true
    }
    if (key == "weapon") {
        v = item_value_f(u.equip[3])
        return true
    }
    if (key == "support") {
        v = vtext(u.support == 0 ? "none" : ability_name(u.support), double(u.support))
        return true
    }
    if (starts_with(key, "status.")) {
        let i = status_index_f(slice(key, 7))
        if (i >= 0) {
            v = vnum(has_status(u, i) ? 1.0lf : 0.0lf)
            return true
        }
    }
    return false
}

// "" or why the value can not be set
def set_unit_param_f(var u : FftUnit; key : string; v : Value) : string {
    let n = int(round(v.num))
    let before = u
    if (key == "pa") {
        u.pa = max(0, n)
    } elif (key == "ma") {
        u.ma = max(0, n)
    } elif (key == "sp" || key == "speed") {
        u.speed = max(1, n)
    } elif (key == "brave") {
        u.brave = clamp(n, 0, 100)
    } elif (key == "faith") {
        u.faith = clamp(n, 0, 100)
    } elif (key == "hp") {
        u.hp = n
    } elif (key == "max_hp") {
        u.max_hp = max(1, n)
    } elif (key == "mp") {
        u.mp = n
    } elif (key == "max_mp") {
        u.max_mp = n
    } elif (key == "ct") {
        u.ct = n
    } elif (key == "level") {
        u.level = n
    } elif (key == "move") {
        u.move = n
    } elif (key == "jump") {
        u.jump = n
    } elif (key == "zodiac") {
        u.zodiac = clamp(n, 0, 12)
    } elif (key == "weapon") {
        // the item's PA / MA / Speed bonuses and element follow
        u.equip[3] = n <= 0 ? 255 : n
        recompute_unit(u, before)
    } elif (key == "support") {
        u.support = n
        recompute_unit(u, before)
    } elif (starts_with(key, "status.")) {
        let i = status_index_f(slice(key, 7))
        if (i < 0) {
            return "no status '{slice(key, 7)}'"
        }
        let m = 0x80u >> uint(i & 7)
        u.status[i >> 3] = uint8(n != 0 ? (uint(u.status[i >> 3]) | m) : (uint(u.status[i >> 3]) & ~m))
    } else {
        return "'{key}' can not be varied"
    }
    return ""
}

// the target turned so that the attacker stands at `side` (1 front, 2
// side, 3 back); on an exact diagonal the attacker steps one tile along x
// first (a diagonal is always the side)
def private place_side(var a, t : FftUnit; side : int) {
    if (side <= 0) {
        return
    }
    var dx = a.x - t.x
    var dy = a.y - t.y
    if (abs(dx) == abs(dy)) {
        a.x += dx >= 0 ? 1 : -1
        dx = a.x - t.x
    }
    let dir = abs(dx) > abs(dy) ? (dx > 0 ? 3 : 1) : (dy > 0 ? 2 : 0)
    t.facing = (dir - (side == 1 ? 0 : (side == 2 ? 1 : 2))) & 3
}

// the average amount of one use: a hit, and the critical's (5%)
// + rand(0..XA - 1) to XA
def expected_f(f : FightF) : float {
    var d = float(f.dmg_min + f.dmg_max) * 0.5
    if (f.crit > 0 && f.xa > 0) {
        d += float(f.crit) / 100.0 * float(f.xa - 1) * 0.5 * float(f.ya)
    }
    return min(d, 999.0) * float(f.hit) / 100.0
}

// one action: Attack (0) or an ability, at `side` (0 by the positions)
def fight_f(a0, t0 : FftUnit; ability, side : int; m : FftMap) : FightF {
    var a = a0
    var t = t0
    place_side(a, t, side)
    var f = FightF()
    if (ability == 0) {
        let af = attack_forecast(a, t)
        f.dmg_min = af.damage_min
        f.dmg_max = af.damage_max
        f.healing = af.healed
        f.hit = af.hit
        f.crit = 5
        f.xa = (af.xa_min + af.xa_max) / 2
        f.ya = af.ya
        f.reach = attack_reaches(a0, unit_weapon(a0), m, t0.x, t0.y)
    } else {
        let ab = read_ability(ability)
        let bf = ability_forecast(a, t, ab)
        f.unsupported = !bf.known
        f.dmg_min = bf.amount_min
        f.dmg_max = bf.amount_max
        f.healing = bf.heal
        f.hit = bf.hit
        f.mp_cost = ab.mp
        let dist = abs(a0.x - t0.x) + abs(a0.y - t0.y)
        f.reach = dist <= (ab.kind == 4 ? ab.jump.x : ab.reach)
    }
    f.damage = (f.dmg_min + f.dmg_max) / 2
    f.expected = expected_f(f)
    return f
}

def private has_text_f(vals : array<Value>; name : string) : bool {
    for (v in vals) {
        if (v.text == name) {
            return true
        }
    }
    return false
}

// the values of `vary path src`; "" or the error
def axis_values_f(sc : SceneF; ax : Axis; var vals : array<Value>) : string {
    let e & = unsafe(ax.src)
    if (e.root < 0) {
        return "line {ax.line}: no values"
    }
    let n & = unsafe(e.nodes[e.root])
    if (n.kind == EX_LIST) {
        for (a in n.args) {
            vals |> push(eval_const(e, a))
        }
    } elif (n.kind == EX_CALL && n.text == "span") {
        let lo = eval_const(e, n.args[0]).num
        let hi = eval_const(e, n.args[1]).num
        var st = length(n.args) > 2 ? abs(eval_const(e, n.args[2]).num) : 1.0lf
        if (st == 0.0lf) {
            return "line {ax.line}: step 0"
        }
        if (hi < lo) {
            st = -st
        }
        var x = lo
        let eps = abs(st) * 1.0e-9lf
        while ((st > 0.0lf ? x <= hi + eps : x >= hi - eps) && length(vals) <= MAX_POINTS_F) {
            vals |> push(vnum(x))
            x += st
        }
    } elif (n.kind == EX_CALL && n.text == "weapons") {
        for (item in range(1, 128)) {
            let name = item_name(item)
            if ((item_flags(item) & 0x80) != 0 && name != "" && !has_text_f(vals, name)) {
                vals |> push(item_value_f(item))
            }
        }
    } elif (n.kind == EX_CALL && n.text == "supports") {
        vals |> push(vtext("none", 0.0lf))
        for (id in range(454, 486)) {
            let name = ability_name(id)
            if (name != "") {
                vals |> push(vtext(name, double(id)))
            }
        }
    } elif (n.kind == EX_CALL && n.text == "actions") {
        for (id in unit_actions_f(sc.att, false)) {
            vals |> push(vtext(action_name_f(id), double(id)))
        }
    } elif (n.kind == EX_CALL && n.text == "sides") {
        for (s in range(1, 4)) {
            vals |> push(vtext(SIDE_F_LABELS[s], double(s)))
        }
    } else {
        return "line {ax.line}: values are from..to [step s], a, b, ..., weapons, supports, actions, sides - not '{n.text}'"
    }
    if (length(vals) == 0) {
        return "line {ax.line}: no values for {ax.path}"
    }
    return ""
}

def private is_param_path_f(path : string) : bool {
    return starts_with(path, "atk.") || starts_with(path, "tgt.") || path == "action" || path == "side"
}

def private point_param_f(att, tgt : FftUnit; ability, side : int; path : string; var v : Value) : bool {
    if (path == "action") {
        v = vtext(action_name_f(ability), double(ability))
        return true
    }
    if (path == "side") {
        v = vtext(SIDE_F_LABELS[side & 3], double(side))
        return true
    }
    var owner = ""
    var key = ""
    split_path_f(path, owner, key)
    return unit_param_f(owner == "tgt" ? tgt : att, key, v)
}

def private metric_values_f(f : FightF; distance, zodiac : int; var row : array<Value>) {
    let ok = !f.unsupported
    let nan = vnum(0.0lf / 0.0lf)
    row |> push(ok ? vnum(double(f.damage)) : nan)
    row |> push(vnum(f.healing ? 1.0lf : 0.0lf))
    row |> push(ok ? vnum(double(f.dmg_min)) : nan)
    row |> push(ok ? vnum(double(f.dmg_max)) : nan)
    row |> push(ok ? vnum(double(f.hit)) : nan)
    row |> push(vnum(double(f.crit)))
    row |> push(ok ? vnum(double(f.expected)) : nan)
    row |> push(vnum(f.reach ? 1.0lf : 0.0lf))
    row |> push(vnum(double(distance)))
    row |> push(vnum(double(f.mp_cost)))
    row |> push(vnum(double(f.xa)))
    row |> push(vnum(double(f.ya)))
    row |> push(vtext(ZODIAC_REL_F[zodiac + 2], double(zodiac)))
}

def private short_name_f(name : string) : string {
    if (starts_with(name, "attacker.")) {
        return "atk.{slice(name, 9)}"
    }
    if (starts_with(name, "target.")) {
        return "tgt.{slice(name, 7)}"
    }
    return name
}

def private short_script_names_f(var s : Script) {
    for (ax in s.axes) {
        ax.path = short_name_f(ax.path)
    }
    for (st in s.steps) {
        for (n in st.e.nodes) {
            if (n.kind == EX_NAME) {
                n.text = short_name_f(n.text)
            }
        }
    }
    for (a in s.plot) {
        for (e in a.exprs) {
            for (n in e.nodes) {
                if (n.kind == EX_NAME) {
                    n.text = short_name_f(n.text)
                }
            }
        }
    }
}

// The table of the experiment: one row per combination of the axes,
// then the steps (columns, where, sort). "" or the error.
def run_experiment_f(sc : SceneF; m : FftMap; var s : Script; var t : ETable) : string {
    short_script_names_f(s)
    t.names |> clear()
    t.rows |> clear()
    var paths : array<string>
    var values : array<array<Value>>
    var total = 1
    for (ax in s.axes) {
        if (!is_param_path_f(ax.path)) {
            return "line {ax.line}: vary atk.<param>, tgt.<param>, action or side, not '{ax.path}'"
        }
        if (find_index(paths, ax.path) >= 0) {
            return "line {ax.line}: {ax.path} is already an axis"
        }
        var probe : Value
        if (!point_param_f(sc.att, sc.tgt, sc.ability, 0, ax.path, probe)) {
            return "line {ax.line}: no parameter '{ax.path}'"
        }
        var vals : array<Value>
        let err = axis_values_f(sc, ax, vals)
        if (err != "") {
            return err
        }
        total *= length(vals)
        if (total > MAX_POINTS_F) {
            return "line {ax.line}: too many points (more than {MAX_POINTS_F})"
        }
        paths |> push(ax.path)
        values |> emplace(vals)
    }
    var used : array<string>
    script_names(s, used)
    var extra : array<string>
    for (name in used) {
        var probe : Value
        if (find_index(paths, name) < 0 && find_index(METRICS_F, name) < 0 && is_param_path_f(name) &&
                point_param_f(sc.att, sc.tgt, sc.ability, sc.side, name, probe)) {
            extra |> push(name)
        }
    }
    for (p in paths) {
        t.names |> push(p)
    }
    for (name in METRICS_F) {
        t.names |> push(name)
    }
    for (p in extra) {
        t.names |> push(p)
    }
    var idx : array<int>
    idx |> resize(length(paths))
    for (_ in range(total)) {
        var att = sc.att
        var tgt = sc.tgt
        var ability = sc.ability
        var side = sc.side
        var row : array<Value>
        for (a in range(length(paths))) {
            let v = values[a][idx[a]]
            row |> push(v)
            let path = paths[a]
            if (path == "action") {
                ability = int(v.num)
            } elif (path == "side") {
                side = int(v.num)
            } else {
                var owner = ""
                var key = ""
                split_path_f(path, owner, key)
                let err = owner == "tgt" ? set_unit_param_f(tgt, key, v) : set_unit_param_f(att, key, v)
                if (err != "") {
                    return err
                }
            }
        }
        let f = fight_f(att, tgt, ability, side, m)
        metric_values_f(f, abs(att.x - tgt.x) + abs(att.y - tgt.y), zodiac_compat(att, tgt), row)
        for (p in extra) {
            var v : Value
            point_param_f(att, tgt, ability, side, p, v)
            row |> push(v)
        }
        t.rows |> emplace(row)
        var a = length(paths) - 1
        while (a >= 0) {
            idx[a]++
            if (idx[a] < length(values[a])) {
                break
            }
            idx[a] = 0
            a--
        }
    }
    return run_steps(s, t)
}
