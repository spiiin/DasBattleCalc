options gen2
options indenting = 4

// Explore for FFTA2: the axes of an experiment (core/explore.das) are
// parameters of the attacker, the target or the scene; every combination
// is one action computed by the model (action2; the game's scripts by the
// VM when the step-by-step formula does not cover the ability), one row.
//
// Parameters (atk.* or tgt.*; attacker.* / target.* mean the same):
// attack defense magick resistance (as the Unit Info screen shows them
// before the equipment: raw / 4; *_raw: the record's value), speed,
// evasion move jump (read only), *_total (with the equipment, read only),
// hp max_hp mp max_mp ct level, job, weapon, support, status.<name>
// (0 / 1: status.protect, status.shell ...). Scene: action (an ability,
// Attack = 799), side (1 front, 2 side, 3 back, 0 = by the positions),
// privilege (the clan privilege, game variable 369).
// Values of vary: from..to [step s], a, b, ..., jobs, weapons, supports,
// actions, sides.
// Columns of every row: the axes, the parameters the script reads, and
// damage healing dmg_min dmg_max hit hit_real crit expected reach
// distance mp_cost attack defense power base scaled after_side affinity.
module ffta2_explore shared public

require math
require strings
require daslib/strings_boost
require ../../core/explore.das
require ffta2_battle
require ffta2_attack
require ffta2_forecast

let MAX_POINTS2 = 20000

let METRICS2 = fixed_array<string>("damage", "healing", "dmg_min", "dmg_max", "hit", "hit_real", "crit", "expected",
    "reach", "distance", "mp_cost", "attack", "defense", "power", "base", "scaled", "after_side", "affinity")

let STAT2_KEYS = fixed_array<string>("attack", "defense", "magick", "resistance", "speed", "evasion", "move", "jump")

let SIDE2_LABELS = fixed_array<string>("Auto", "Front", "Side", "Back")

let EXPLORE2_GENERATORS = fixed_array<string>("jobs", "weapons", "supports", "actions", "sides")

// Explore: ready experiments (the editor starts with the first)
let EXPLORE2_NAMES = fixed_array<string>("Damage by Attack and target Defense", "Every weapon",
    "Side and Protect", "Fire by Magick and Shell", "Every action")
let EXPLORE2_EXAMPLES = fixed_array<string>(
    "// the attacker and target of the Attack tab: Attack by the base\n// Attack (before the equipment), one line per target Defense\nvary atk.attack 20..120 step 5\nvary tgt.defense 20, 40, 60, 80\navg = expected\nplot avg by atk.attack per tgt.defense title \"Average damage per Attack\"\n",
    "// every weapon in the attacker's hands, best first (the reach\n// column: the target is within the weapon's range)\nvary atk.weapon weapons\navg = expected\nsort avg desc\nplot damage, avg by atk.weapon bar\n",
    "vary side sides\nvary tgt.status.protect 0, 1\nplot damage by side per tgt.status.protect bar\n",
    "// a spell: the scene picks the action\nscene with Fire\nvary atk.magick 10..120 step 5\nvary tgt.status.shell 0, 1\nplot damage by atk.magick per tgt.status.shell\n",
    "// every action the model computes: Attack and the abilities\n// that damage or heal\nvary action actions\nwhere damage > 0\navg = expected\nsort avg desc\nplot avg by action bar log y\n")

// what the experiment starts from: the Attack tab
struct Scene2 {
    att : Unit2
    tgt : Unit2
    ability : int = 799
    side : int                      // 0 auto, 1 front, 2 side, 3 back
    privilege : int
    map : Map2                      // heights for the reach column (empty: flat)
}

// one action as the Attack tab computes it: the step-by-step formula, or
// the game's scripts (the VM) when the formula does not cover the ability
def compute_action2(att, tgt : Unit2; ab : Ability2; side : int; privilege : int) : Fight2 {
    let auto_side = side_of2(att, tgt)
    let s = side == 1 ? Side2.Front : (side == 2 ? Side2.Side : (side == 3 ? Side2.Back : auto_side))
    var f <- action2(att, tgt, ab, s, privilege)
    if (f.unsupported) {
        let vt = side == 0 ? tgt : face_for_side(att, tgt, s)
        let v = vm_forecast(att, vt, ab, privilege)
        if (v.ok) {
            f.hit = v.no_effect ? 0 : v.hit
            f.damage = v.no_effect ? 0 : v.amount
            f.healing = v.healing
            f.unsupported = false
            fill_real(f, att, privilege)
        }
    }
    return <- f
}

// a status name as a key: "Defense↑" -> defenseup, "Evasion 0" -> evasion0
def status_key2(i : int) : string {
    let name = status_name(i)
    if (name == "" || name == "-") {
        return ""
    }
    var key = ""
    for (c in name) {
        if (is_alpha(c) || is_number(c)) {
            key += to_lower(to_char(c))
        }
    }
    if (find(name, "↑") >= 0) {
        key += "up"
    } elif (find(name, "↓") >= 0) {
        key += "down"
    }
    return key
}

def private status_index2(key : string) : int {
    for (i in range(1, 72)) {
        if (status_key2(i) == key) {
            return i
        }
    }
    return -1
}

def private item_value2(it : Item2) : Value {
    return vtext(it.id == 0 ? "(none)" : it.name, double(it.id))
}

// a parameter of a unit; false: there is no such parameter
def unit_param2(u : Unit2; key : string; var v : Value) : bool {
    let si = find_index(STAT2_KEYS, key)
    if (si >= 0) {
        v = vnum(double(u.stat_base[si]))
        return true
    }
    if (ends_with(key, "_raw")) {
        let ri = find_index(STAT2_KEYS, slice(key, 0, length(key) - 4))
        if (ri >= 0 && ri < 4) {
            v = vnum(double(u.raw[ri]))
            return true
        }
    }
    if (ends_with(key, "_total")) {
        let ti = find_index(STAT2_KEYS, slice(key, 0, length(key) - 6))
        if (ti >= 0) {
            v = vnum(double(u.stat_total[ti]))
            return true
        }
    }
    if (key == "hp" || key == "max_hp" || key == "mp" || key == "max_mp" || key == "ct" || key == "level") {
        let n = key == "hp" ? u.hp : (key == "max_hp" ? u.max_hp : (key == "mp" ? u.mp : (key == "max_mp" ? u.max_mp :
            (key == "ct" ? u.ct : u.level))))
        v = vnum(double(n))
        return true
    }
    if (key == "job") {
        v = vtext(u.job, double(u.job_id))
        return true
    }
    if (key == "weapon") {
        let slot = weapon_slot2(u)
        v = slot >= 0 ? item_value2(u.equip[slot]) : vtext("Bare hands", 0.0lf)
        return true
    }
    if (key == "support") {
        v = vtext(u.support_name, double(u.support))
        return true
    }
    if (starts_with(key, "status.")) {
        let i = status_index2(slice(key, 7))
        if (i >= 0) {
            v = vnum(has_status2(u, i) ? 1.0lf : 0.0lf)
            return true
        }
    }
    return false
}

// "" or why the value can not be set
def set_unit_param2(var u : Unit2; key : string; v : Value) : string {
    let n = int(round(v.num))
    let si = find_index(STAT2_KEYS, key)
    if (si >= 0 && si < 4) {
        u.raw[si] = n * 4                    // shown = raw / 4
    } elif (ends_with(key, "_raw") && find_index(STAT2_KEYS, slice(key, 0, length(key) - 4)) >= 0 &&
            find_index(STAT2_KEYS, slice(key, 0, length(key) - 4)) < 4) {
        u.raw[find_index(STAT2_KEYS, slice(key, 0, length(key) - 4))] = n
    } elif (key == "speed") {
        u.base_speed = n
        u.speed = n
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
    } elif (key == "job") {
        set_job2(u, n)
    } elif (key == "weapon") {
        let slot = max(weapon_slot2(u), 0)
        u.equip[slot] = read_item2(n)
        u.items[slot] = n
    } elif (key == "support") {
        u.support = n
        u.support_name = n == 0 ? "none" : v.text
    } elif (starts_with(key, "status.")) {
        let i = status_index2(slice(key, 7))
        if (i < 0) {
            return "no status '{slice(key, 7)}'"
        }
        let mask = 1u << uint(i & 7)
        let b = uint(u.status[i >> 3])
        u.status[i >> 3] = uint8(n != 0 ? (b | mask) : (b & ~mask))
    } else {
        return "'{key}' can not be varied"
    }
    recompute_unit(u)
    return ""
}

// Attack and every ability with a damage or healing effect (the Attack
// tab's list)
def explore_actions2() : array<int> {
    var res : array<int>
    res |> push(ATTACK_ABILITY)
    for (aid in range(1, ability_count())) {
        if (aid != ATTACK_ABILITY && damages_or_heals(read_ability2(aid))) {
            res |> push(aid)
        }
    }
    return <- res
}

def private has_text2(vals : array<Value>; name : string) : bool {
    for (v in vals) {
        if (v.text == name) {
            return true
        }
    }
    return false
}

def private action_value(id : int) : Value {
    return vtext(id == ATTACK_ABILITY ? "Attack" : read_ability2(id).name, double(id))
}

// the values of `vary path src`; "" or the error
def axis_values2(sc : Scene2; ax : Axis; var vals : array<Value>) : string {
    let e & = unsafe(ax.src)
    if (e.root < 0) {
        return "line {ax.line}: no values"
    }
    let n & = unsafe(e.nodes[e.root])
    if (n.kind == NodeKind.List) {
        for (a in n.args) {
            vals |> push(eval_const(e, a))
        }
    } elif (n.kind == NodeKind.Call && n.text == "span") {
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
        while ((st > 0.0lf ? x <= hi + eps : x >= hi - eps) && length(vals) <= MAX_POINTS2) {
            vals |> push(vnum(x))
            x += st
        }
    } elif (n.kind == NodeKind.Call && n.text == "jobs") {
        for (j in range(1, 249)) {
            let name = job_name(j)
            if (name != "" && name != "-" && !has_text2(vals, name)) {
                vals |> push(vtext(name, double(j)))
            }
        }
    } elif (n.kind == NodeKind.Call && n.text == "weapons") {
        for (iid in range(1, item_count())) {
            let it = read_item2(iid)
            if (is_weapon2(it) && it.name != "" && it.name != "-") {
                vals |> push(item_value2(it))
            }
        }
    } elif (n.kind == NodeKind.Call && n.text == "supports") {
        vals |> push(vtext("none", 0.0lf))
        for (id in range(851, 882)) {
            vals |> push(vtext(read_ability2(id).name, double(id)))
        }
    } elif (n.kind == NodeKind.Call && n.text == "actions") {
        for (id in explore_actions2()) {
            vals |> push(action_value(id))
        }
    } elif (n.kind == NodeKind.Call && n.text == "sides") {
        for (s in range(1, 4)) {
            vals |> push(vtext(SIDE2_LABELS[s], double(s)))
        }
    } else {
        return ("line {ax.line}: values are from..to [step s], a, b, ..., jobs, weapons, supports, actions, " +
            "sides - not '{n.text}'")
    }
    if (length(vals) == 0) {
        return "line {ax.line}: no values for {ax.path}"
    }
    return ""
}

def private is_param_path2(path : string) : bool {
    return (starts_with(path, "atk.") || starts_with(path, "tgt.") || path == "action" || path == "side" ||
        path == "privilege")
}

def private point_param2(att, tgt : Unit2; ability, side, privilege : int; path : string; var v : Value) : bool {
    if (path == "action") {
        v = action_value(ability)
        return true
    }
    if (path == "side") {
        v = vtext(SIDE2_LABELS[side & 3], double(side))
        return true
    }
    if (path == "privilege") {
        v = vnum(double(privilege))
        return true
    }
    var owner = ""
    var key = ""
    split_path(path, owner, key)
    return unit_param2(owner == "tgt" ? tgt : att, key, v)
}

def private metric_values2(f : Fight2; reach : bool; distance, mp : int; var row : array<Value>) {
    let ok = !f.unsupported
    let nan = vnum(0.0lf / 0.0lf)
    row |> push(ok ? vnum(double(f.damage)) : nan)
    row |> push(vnum(f.healing ? 1.0lf : 0.0lf))
    row |> push(ok ? vnum(double(f.dmg_min)) : nan)
    row |> push(ok ? vnum(double(f.dmg_max)) : nan)
    row |> push(ok ? vnum(double(f.hit)) : nan)
    row |> push(ok ? vnum(double(f.hit_prob) * 100.0lf) : nan)
    row |> push(ok ? vnum(double(f.crit_prob) * 100.0lf) : nan)
    row |> push(ok ? vnum(double(f.expected)) : nan)
    row |> push(vnum(reach ? 1.0lf : 0.0lf))
    row |> push(vnum(double(distance)))
    row |> push(vnum(double(mp)))
    row |> push(vnum(double(f.atk10) / 10.0lf))
    row |> push(vnum(double(f.def10) / 10.0lf))
    row |> push(vnum(double(f.power10) / 10.0lf))
    row |> push(vnum(double(f.base)))
    row |> push(vnum(double(f.scaled)))
    row |> push(vnum(double(f.after_side)))
    row |> push(vtext(f.affinity >= 0 && f.affinity < 5 ? AFFINITY_NAMES[f.affinity] : "{f.affinity}", double(f.affinity)))
}

// FFTA2's point: the scene's units, the action, the side and the privilege
class Ffta2Points : ExploreModel {
    sc : Scene2 = Scene2()
    att : Unit2
    tgt : Unit2
    ability : int
    side : int
    privilege : int

    def override is_param_path(path : string) : bool {
        return is_param_path2(path)
    }
    def override reset() : void {
        att = sc.att
        tgt = sc.tgt
        ability = sc.ability
        side = sc.side
        privilege = sc.privilege
    }
    def override probe_axis(path : string; var v : Value) : bool {
        return point_param2(sc.att, sc.tgt, sc.ability, 0, 0, path, v)
    }
    def override value(path : string; var v : Value) : bool {
        return point_param2(att, tgt, ability, side, privilege, path, v)
    }
    def override set(path : string; v : Value) : string {
        if (path == "action") {
            ability = int(v.num)
        } elif (path == "side") {
            side = int(v.num)
        } elif (path == "privilege") {
            privilege = int(v.num)
        } else {
            var owner = ""
            var key = ""
            split_path(path, owner, key)
            return owner == "tgt" ? set_unit_param2(tgt, key, v) : set_unit_param2(att, key, v)
        }
        return ""
    }
    def override axis_values(ax : Axis; var vals : array<Value>) : string {
        return axis_values2(sc, ax, vals)
    }
    def override measure(var row : array<Value>) : void {
        let ab = read_ability2(ability)
        // an ability for the user only targets the attacker
        let on = ab.range_kind == 8 ? att : tgt
        let f <- compute_action2(att, on, ab, side, privilege)
        metric_values2(f, in_reach_on(att, ab, sc.map, on.x, on.y), abs(att.x - on.x) + abs(att.y - on.y), ab.mp, row)
    }
}

def run_experiment2(sc : Scene2; var s : Script; var t : ETable) : string {
    var model = new Ffta2Points(sc := sc, max_points = MAX_POINTS2,
        axis_hint = "atk.<param>, tgt.<param>, action, side or privilege")
    model.metrics |> push_from(METRICS2)
    let err = run_experiment(*model, s, t)
    unsafe {
        delete model
    }
    return err
}