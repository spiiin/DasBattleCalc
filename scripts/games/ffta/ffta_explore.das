options gen2
options indenting = 4

// Explore for FFTA: the axes of an experiment (core/explore.das) are
// parameters of the attacker, the target or the scene; every
// combination is one attack computed by the model (act), one row.
//
// Parameters (atk.* or tgt.*; attacker.* / target.* mean the same):
// watk wdef mpow mres speed evade move jump (the base value, as the
// inspector edits it; *_total: with the equipment, read only), hp
// max_hp mp ct level, job, weapon, support, reaction, status.<name>
// (0 / 1: status.protect, status.haste ...). Scene: action (an ability,
// Fight = 0), side (1 front, 2 side, 3 back, 0 = by the positions).
// Values of vary: from..to [step s] (both ends included), a, b, ...,
// jobs, weapons, weapons "Sword", supports, reactions, actions, sides.
// Columns of every row: the axes, the parameters the script reads, and
// damage dmg_min dmg_max crit_damage hit hit_real crit expected reach
// mp_cost attack defense base evade distance.
module ffta_explore shared public

require math
require strings
require daslib/strings_boost
require ../../core/explore.das
require ffta_battle
require ffta_attack

let MAX_POINTS = 20000

let METRICS = fixed_array<string>("damage", "dmg_min", "dmg_max", "crit_damage", "hit", "hit_real", "crit", "expected",
    "reach", "mp_cost", "attack", "defense", "base", "evade", "distance")

let STAT_KEYS = fixed_array<string>("watk", "wdef", "mpow", "mres", "speed", "evade", "move", "jump")

let SIDE_LABELS = fixed_array<string>("Auto", "Front", "Side", "Back")

// what the experiment starts from: the Attack tab (the map is passed on
// its own: it holds arrays and is not copied)
struct Scene {
    att : BattleUnit
    tgt : BattleUnit
    ability : int
    side : int                      // 0 auto, 1 front, 2 side, 3 back
}

// a status name as a key: "Advice (crit +30)" -> advice, "Auto-Life" ->
// autolife; unnamed bits ("E8&01 ?") have none
def status_key(i : int) : string {
    let name = STATUS_NAMES[i]
    if (find(name, "&") >= 0) {
        return ""
    }
    var key = ""
    for (c in name) {
        if (c == '(') {
            break
        }
        if (is_alpha(c) || is_number(c)) {
            key += to_lower(to_char(c))
        }
    }
    return key
}

def private status_index(key : string) : int {
    for (i in range(48)) {
        if (status_key(i) == key) {
            return i
        }
    }
    return -1
}

def private item_value(it : Item) : Value {
    return vtext(it.id == 0 ? "(none)" : it.name, double(it.id))
}

def private ability_value(kind, id : int) : Value {
    return vtext(id == 0 ? "none" : ability_name_of(kind, id), double(id))
}

// support / reaction names come from the race lists
def private ability_name_of(kind, id : int) : string {
    return kind == 0 ? ability_name(id) : "{id}"
}

// a parameter of a unit; false: there is no such parameter
def unit_param(u : BattleUnit; key : string; var v : Value) : bool {
    let si = find_index(STAT_KEYS, key)
    if (si >= 0) {
        v = vnum(double(u.stat_base[si]))
        return true
    }
    if (ends_with(key, "_total")) {
        let ti = find_index(STAT_KEYS, slice(key, 0, length(key) - 6))
        if (ti >= 0) {
            v = vnum(double(u.stat_total[ti]))
            return true
        }
    }
    if (key == "hp" || key == "max_hp" || key == "mp" || key == "ct" || key == "level") {
        v = vnum(double(key == "hp" ? u.hp : (key == "max_hp" ? u.max_hp : (key == "mp" ? u.mp : (key == "ct" ? u.ct :
            u.level)))))
        return true
    }
    if (key == "job") {
        v = vtext(u.job, double(u.job_id))
        return true
    }
    if (key == "weapon") {
        let slot = weapon_slot(u)
        v = slot >= 0 ? item_value(u.equip[slot]) : vtext("Bare hands", 0.0lf)
        return true
    }
    if (key == "support") {
        v = vtext(u.support_name, double(u.support))
        return true
    }
    if (key == "reaction") {
        v = vtext(u.reaction_name, double(u.reaction))
        return true
    }
    if (starts_with(key, "status.")) {
        let i = status_index(slice(key, 7))
        if (i >= 0) {
            v = vnum(has_status_bit(u, i) ? 1.0lf : 0.0lf)
            return true
        }
    }
    return false
}

// "" or why the value can not be set
def set_unit_param(var u : BattleUnit; key : string; v : Value) : string {
    let si = find_index(STAT_KEYS, key)
    let n = int(round(v.num))
    if (si >= 0) {
        u.stat_base[si] = n
    } elif (key == "hp") {
        u.hp = n
    } elif (key == "max_hp") {
        u.max_hp = max(1, n)
    } elif (key == "mp") {
        u.mp = n
    } elif (key == "ct") {
        u.ct = n
    } elif (key == "job") {
        set_job(u, n)
    } elif (key == "weapon") {
        let slot = weapon_slot(u)
        u.equip[slot >= 0 ? slot : 0] = read_item(uint(n))
    } elif (key == "support" || key == "reaction") {
        set_ability(u, key == "support" ? 3 : 2, n)
        if (key == "support") {
            u.support_name = v.text
        } else {
            u.reaction_name = v.text
        }
    } elif (starts_with(key, "status.")) {
        let i = status_index(slice(key, 7))
        if (i < 0) {
            return "no status '{slice(key, 7)}'"
        }
        let mask = 1u << uint(i & 7)
        u.status[i >> 3] = n != 0 ? (u.status[i >> 3] | mask) : (u.status[i >> 3] & ~mask)
    } else {
        return "'{key}' can not be varied"
    }
    recompute_unit(u)
    return ""
}

// ------------------------------------------------------------ axis values

def private race_ability_values(u : BattleUnit; kind : int; var vals : array<Value>) {
    vals |> push(vtext("none", 0.0lf))
    for (a in race_choices(u.race, kind)) {
        vals |> push(vtext(ffta_text2(a.name), double(a.id)))
    }
}

// the values of `for (path in src)`; "" or the error
def axis_values(sc : Scene; ax : Axis; var vals : array<Value>) : string {
    let e & = unsafe(ax.src)
    if (e.root < 0) {
        return "line {ax.line}: no values"
    }
    let n & = unsafe(e.nodes[e.root])
    var owner = ""
    var key = ""
    split_path(ax.path, owner, key)
    let u & = unsafe(owner == "tgt" ? sc.tgt : sc.att)
    if (n.kind == NodeKind.List) {
        for (a in n.args) {
            vals |> push(eval_const(e, a))
        }
    } elif (n.kind == NodeKind.Call && n.text == "span") {
        // from..to [step s]: both ends included; downwards when to < from
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
        while ((st > 0.0lf ? x <= hi + eps : x >= hi - eps) && length(vals) <= MAX_POINTS) {
            vals |> push(vnum(x))
            x += st
        }
    } elif (n.kind == NodeKind.Call && n.text == "jobs") {
        for (j in race_jobs(u.race)) {
            vals |> push(vtext(job_name(j, j), double(j)))
        }
        if (length(vals) == 0) {
            vals |> push(vtext(u.job, double(u.job_id)))
        }
    } elif (n.kind == NodeKind.Call && n.text == "weapons") {
        let want = length(n.args) > 0 ? eval_const(e, n.args[0]).text : ""
        for (iid in range(1, ITEM_COUNT)) {
            let it = read_item(uint(iid))
            if (it.kind >= 1 && it.kind <= 19 && it.name != "" && it.name != "-"
                    && (want == "" || item_kind_name(it.kind) == want)) {
                vals |> push(item_value(it))
            }
        }
    } elif (n.kind == NodeKind.Call && (n.text == "supports" || n.text == "reactions")) {
        race_ability_values(u, n.text == "supports" ? 3 : 2, vals)
    } elif (n.kind == NodeKind.Call && n.text == "actions") {
        vals |> push(vtext("Fight", 0.0lf))
        for (k in range(sc.att.action_count)) {
            vals |> push(vtext(ability_name(sc.att.actions[k]), double(sc.att.actions[k])))
        }
    } elif (n.kind == NodeKind.Call && n.text == "sides") {
        for (s in range(1, 4)) {
            vals |> push(vtext(SIDE_LABELS[s], double(s)))
        }
    } else {
        return ("line {ax.line}: values are from..to [step s], a, b, ..., jobs, weapons, weapons \"Sword\", " +
            "supports, reactions, actions, sides - not '{n.text}'")
    }
    if (length(vals) == 0) {
        return "line {ax.line}: no values for {ax.path}"
    }
    return ""
}

// ------------------------------------------------------------ points

def private is_param_path(path : string) : bool {
    return starts_with(path, "atk.") || starts_with(path, "tgt.") || path == "action" || path == "side"
}

// a parameter of the point: units after the axes, the scene
def private point_param(att, tgt : BattleUnit; ability, side : int; path : string; var v : Value) : bool {
    if (path == "action") {
        v = vtext(ability == 0 ? "Fight" : ability_name(ability), double(ability))
        return true
    }
    if (path == "side") {
        v = vtext(SIDE_LABELS[side & 3], double(side))
        return true
    }
    var owner = ""
    var key = ""
    split_path(path, owner, key)
    return unit_param(owner == "tgt" ? tgt : att, key, v)
}

def private metric_values(r : AttackResult; var row : array<Value>) {
    row |> push(vnum(double(r.damage)))
    row |> push(vnum(double(r.dmg_min)))
    row |> push(vnum(double(r.dmg_max)))
    row |> push(vnum(double(r.crit_damage)))
    row |> push(vnum(double(r.hit)))
    row |> push(vnum(double(r.hit_roll)))
    row |> push(vnum(double(r.crit)))
    row |> push(vnum(double(r.expected)))
    row |> push(vnum(r.reach ? 1.0lf : 0.0lf))
    row |> push(vnum(double(r.mp_cost)))
    row |> push(vnum(double(r.attack)))
    row |> push(vnum(double(r.defense)))
    row |> push(vnum(double(r.base)))
    row |> push(vnum(double(r.evade_final)))
    row |> push(vnum(double(r.distance)))
}

// attacker.x / target.x -> atk.x / tgt.x, in the axes and every name
// FFTA's point: the scene's units, the action and the side
class FftaPoints : ExploreModel {
    map : BattleMap
    sc : Scene
    att : BattleUnit
    tgt : BattleUnit
    ability : int
    side : int

    def override is_param_path(path : string) : bool {
        return is_param_path(path)
    }
    def override reset() : void {
        att = sc.att
        tgt = sc.tgt
        ability = sc.ability
        side = sc.side
    }
    def override probe_axis(path : string; var v : Value) : bool {
        return path == "action" || path == "side" || point_param(sc.att, sc.tgt, 0, 0, path, v)
    }
    def override value(path : string; var v : Value) : bool {
        return point_param(att, tgt, ability, side, path, v)
    }
    def override set(path : string; v : Value) : string {
        if (path == "action") {
            ability = int(v.num)
        } elif (path == "side") {
            side = int(v.num)
        } else {
            var owner = ""
            var key = ""
            split_path(path, owner, key)
            return owner == "tgt" ? set_unit_param(tgt, key, v) : set_unit_param(att, key, v)
        }
        return ""
    }
    def override axis_values(ax : Axis; var vals : array<Value>) : string {
        return axis_values(sc, ax, vals)
    }
    def override measure(var row : array<Value>) : void {
        let choice = side == 1 ? SideChoice.Front : (side == 2 ? SideChoice.Side : (side == 3 ? SideChoice.Back :
            SideChoice.Auto))
        let r = act(map, att, tech_info(ability).self_only ? att : tgt, ability, choice)
        metric_values(r, row)
    }
}

def run_experiment(m : BattleMap; sc : Scene; var s : Script; var t : ETable) : string {
    var model = new FftaPoints(map := m, sc := sc, max_points = MAX_POINTS)
    model.metrics |> push_from(METRICS)
    let err = run_experiment(*model, s, t)
    unsafe {
        delete model
    }
    return err
}