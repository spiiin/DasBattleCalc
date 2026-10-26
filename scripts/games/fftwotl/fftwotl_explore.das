options gen2
options indenting = 4

// Explore for FFT: The War of the Lions: the axes of an experiment
// (core/explore.das) are parameters of the attacker, the target or the
// scene; every combination is one action computed by the model
// (fftwotl_attack), one row.
//
// Parameters (atk.* or tgt.*; attacker.* / target.* mean the same): pa ma
// sp (current, with the equipment), pa_raw ma_raw sp_raw (without), brave
// faith hp max_hp mp max_mp ct level, move jump c_ev (read only), job,
// weapon, support, zodiac (0 Aries .. 11 Pisces, 12 Serpentarius),
// status.<name> (0 / 1: status.protect, status.shell, ...). Scene: action
// (an ability, Attack = 0), side (1 front, 2 side, 3 back, 0 = by the
// positions).
// Values of vary: from..to [step s], a, b, ..., jobs, weapons, supports,
// actions, sides.
// Columns of every row: the axes, the parameters the script reads, and
// damage healing dmg_min dmg_max hit crit expected reach distance mp_cost
// xa ya zodiac_rel.
module fftwotl_explore shared public

require math
require strings
require daslib/strings_boost
require ../../core/explore.das
require fftwotl_data
require fftwotl_battle
require fftwotl_attack

let MAX_POINTS_W = 20000

let METRICS_W = fixed_array<string>("damage", "healing", "dmg_min", "dmg_max", "hit", "crit", "expected", "reach",
    "distance", "mp_cost", "xa", "ya", "zodiac_rel")

let STAT_W_KEYS = fixed_array<string>("pa", "ma", "sp")

let SIDE_W_LABELS = fixed_array<string>("Auto", "Front", "Side", "Back")

let EXPLORE_W_GENERATORS = fixed_array<string>("jobs", "weapons", "supports", "actions", "sides")

// Explore: ready experiments (the editor starts with the first)
let EXPLORE_W_NAMES = fixed_array<string>("Damage by PA and Brave", "Every weapon", "Side and Protect",
    "Fire by MA and Faith", "Every action")
let EXPLORE_W_EXAMPLES = fixed_array<string>(
    "// the attacker and target of the Attack tab: Attack by the\n// attacker's PA, one line per Brave (knight swords, katanas\n// and bare hands use Brave)\nvary atk.pa 3..20\nvary atk.brave 40, 60, 80, 97\navg = expected\nplot avg by atk.pa per atk.brave title \"Average damage per Attack\"\n",
    "// every weapon in the attacker's hands, best first\nvary atk.weapon weapons\navg = expected\nwhere damage > 0\nsort avg desc\nplot damage, avg by atk.weapon bar\n",
    "vary side sides\nvary tgt.status.protect 0, 1\nplot damage, hit by side per tgt.status.protect bar\n",
    "// a spell: the scene picks the action\nscene with Fire\nvary atk.ma 5..30\nvary tgt.faith 30, 50, 70, 90\nplot damage by atk.ma per tgt.faith\n",
    "// every action of the attacker's skillsets\nvary action actions\nwhere damage != 0\navg = expected\nsort avg desc\nplot avg by action bar\n")

// what the experiment starts from: the Attack tab
struct SceneW {
    att : UnitW
    tgt : UnitW
    ability : int = 0
    side : int                      // 0 auto, 1 front, 2 side, 3 back
}

def side_value_w(att, tgt : UnitW; side : int) : SideW {
    return side == 1 ? SideW.Front : (side == 2 ? SideW.Side : (side == 3 ? SideW.Back : side_of_w(att, tgt)))
}

// a status name as a key: "Atheist" -> atheist, "Death Sentence" -> deathsentence
def status_key_w(i : int) : string {
    let name = status_name_w(i)
    var key = ""
    for (c in name) {
        if (is_alpha(c) || is_number(c)) {
            key += to_lower(to_char(c))
        }
    }
    return key
}

def private status_index_w(key : string) : int {
    for (i in range(1, STATUS_COUNT_W)) {
        if (status_key_w(i) == key) {
            return i
        }
    }
    return -1
}

def private item_value_w(it : ItemW) : Value {
    return vtext(it.id == ITEM_NONE ? "(none)" : it.name, double(it.id))
}

// a parameter of a unit; false: there is no such parameter
def unit_param_w(u : UnitW; key : string; var v : Value) : bool {
    let si = find_index(STAT_W_KEYS, key)
    if (si >= 0) {
        v = vnum(double(si == 0 ? u.pa : (si == 1 ? u.ma : u.sp)))
        return true
    }
    if (ends_with(key, "_raw")) {
        let ri = find_index(STAT_W_KEYS, slice(key, 0, length(key) - 4))
        if (ri >= 0) {
            v = vnum(double(u.raw[ri]))
            return true
        }
    }
    let nums = fixed_array<string>("brave", "faith", "hp", "max_hp", "mp", "max_mp", "ct", "level", "move", "jump",
        "c_ev", "zodiac")
    let ni = find_index(nums, key)
    if (ni >= 0) {
        let vals = fixed_array<int>(u.brave, u.faith, u.hp, u.max_hp, u.mp, u.max_mp, u.ct, u.level, u.move, u.jump,
            u.c_ev, u.zodiac_id)
        v = vnum(double(vals[ni]))
        return true
    }
    if (key == "job") {
        v = vtext(u.job, double(u.job_id))
        return true
    }
    if (key == "weapon") {
        v = item_value_w(u.equip[SLOT_RIGHT])
        return true
    }
    if (key == "support") {
        v = vtext(u.support == 0 ? "none" : ability_name_w(u.support), double(u.support))
        return true
    }
    if (starts_with(key, "status.")) {
        let i = status_index_w(slice(key, 7))
        if (i >= 0) {
            v = vnum(has_status_w(u, i) ? 1.0lf : 0.0lf)
            return true
        }
    }
    return false
}

// "" or why the value can not be set
def set_unit_param_w(var u : UnitW; key : string; v : Value) : string {
    let n = int(round(v.num))
    let si = find_index(STAT_W_KEYS, key)
    if (si >= 0) {
        // the current stat: raw = n - the equipment's bonus
        u.raw[si] = max(0, n - u.bonus[si])
    } elif (ends_with(key, "_raw") && find_index(STAT_W_KEYS, slice(key, 0, length(key) - 4)) >= 0) {
        u.raw[find_index(STAT_W_KEYS, slice(key, 0, length(key) - 4))] = n
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
    } elif (key == "zodiac") {
        u.zodiac_id = clamp(n, 0, 12)
        u.zodiac = ZODIAC_NAMES[u.zodiac_id]
    } elif (key == "job") {
        u.job_id = n
        u.job = job_name_w(n)
    } elif (key == "weapon") {
        u.items[SLOT_RIGHT] = n
    } elif (key == "support") {
        u.support = n
        rebuild_rsm_mask(u)
    } elif (starts_with(key, "status.")) {
        let i = status_index_w(slice(key, 7))
        if (i < 0) {
            return "no status '{slice(key, 7)}'"
        }
        set_status_bit(u.status, i, n != 0)
    } else {
        return "'{key}' can not be varied"
    }
    let pa = u.pa
    let ma = u.ma
    let sp = u.sp
    recompute_unit_w(u)
    if (key != "weapon" && key != "job" && find_index(STAT_W_KEYS, key) < 0 && !ends_with(key, "_raw")) {
        // keep the game's current stats when the edit does not touch them
        u.pa = pa
        u.ma = ma
        u.sp = sp
    }
    return ""
}

def private action_value_w(id : int) : Value {
    return vtext(action_name_w(id), double(id))
}

def private has_text_w(vals : array<Value>; name : string) : bool {
    for (v in vals) {
        if (v.text == name) {
            return true
        }
    }
    return false
}

// the values of `vary path src`; "" or the error
def axis_values_w(sc : SceneW; ax : Axis; var vals : array<Value>) : string {
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
        while ((st > 0.0lf ? x <= hi + eps : x >= hi - eps) && length(vals) <= MAX_POINTS_W) {
            vals |> push(vnum(x))
            x += st
        }
    } elif (n.kind == NodeKind.Call && n.text == "jobs") {
        for (j in range(1, JOB_COUNT_W)) {
            let name = job_name_w(j)
            if (name != "" && !has_text_w(vals, name)) {
                vals |> push(vtext(name, double(j)))
            }
        }
    } elif (n.kind == NodeKind.Call && n.text == "weapons") {
        for (iid in range(1, ITEM_COUNT_W)) {
            let it = read_item_w(iid)
            if (is_weapon_w(it) && it.kind != 32 && it.kind != 33 && !starts_with(it.name, "item ")) {
                vals |> push(item_value_w(it))
            }
        }
    } elif (n.kind == NodeKind.Call && n.text == "supports") {
        vals |> push(vtext("none", 0.0lf))
        for (id in abilities_of_kind(AB_SUPPORT)) {
            vals |> push(vtext(ability_name_w(id), double(id)))
        }
    } elif (n.kind == NodeKind.Call && n.text == "actions") {
        for (id in unit_actions(sc.att, false)) {
            vals |> push(action_value_w(id))
        }
    } elif (n.kind == NodeKind.Call && n.text == "sides") {
        for (s in range(1, 4)) {
            vals |> push(vtext(SIDE_W_LABELS[s], double(s)))
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

def private is_param_path_w(path : string) : bool {
    return starts_with(path, "atk.") || starts_with(path, "tgt.") || path == "action" || path == "side"
}

def private point_param_w(att, tgt : UnitW; ability, side : int; path : string; var v : Value) : bool {
    if (path == "action") {
        v = action_value_w(ability)
        return true
    }
    if (path == "side") {
        v = vtext(SIDE_W_LABELS[side & 3], double(side))
        return true
    }
    var owner = ""
    var key = ""
    split_path(path, owner, key)
    return unit_param_w(owner == "tgt" ? tgt : att, key, v)
}

def private metric_values_w(f : FightW; distance : int; var row : array<Value>) {
    let ok = !f.unsupported
    let nan = vnum(0.0lf / 0.0lf)
    row |> push(ok ? vnum(double(f.damage)) : nan)
    row |> push(vnum(f.healing ? 1.0lf : 0.0lf))
    row |> push(ok ? vnum(double(f.dmg_min)) : nan)
    row |> push(ok ? vnum(double(f.dmg_max)) : nan)
    row |> push(ok ? vnum(double(f.hit)) : nan)
    row |> push(vnum(double(f.crit)))
    row |> push(ok ? vnum(double(f.expected)) : nan)
    row |> push(vnum(distance <= f.reach ? 1.0lf : 0.0lf))
    row |> push(vnum(double(distance)))
    row |> push(vnum(double(f.mp_cost)))
    row |> push(vnum(double(f.xa)))
    row |> push(vnum(double(f.ya)))
    row |> push(vtext(ZODIAC_REL_NAMES[f.zodiac], double(f.zodiac)))
}

// WotL's point: the scene's units, the action and the side
class WotlPoints : ExploreModel {
    sc : SceneW = SceneW()
    att : UnitW
    tgt : UnitW
    ability : int
    side : int

    def override is_param_path(path : string) : bool {
        return is_param_path_w(path)
    }
    def override reset() : void {
        att = sc.att
        tgt = sc.tgt
        ability = sc.ability
        side = sc.side
    }
    def override probe_axis(path : string; var v : Value) : bool {
        return point_param_w(sc.att, sc.tgt, sc.ability, 0, path, v)
    }
    def override value(path : string; var v : Value) : bool {
        return point_param_w(att, tgt, ability, side, path, v)
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
            return owner == "tgt" ? set_unit_param_w(tgt, key, v) : set_unit_param_w(att, key, v)
        }
        return ""
    }
    def override axis_values(ax : Axis; var vals : array<Value>) : string {
        return axis_values_w(sc, ax, vals)
    }
    def override measure(var row : array<Value>) : void {
        let f <- action_w(att, tgt, ability, side_value_w(att, tgt, side))
        metric_values_w(f, abs(att.x - tgt.x) + abs(att.y - tgt.y), row)
    }
}

def run_experiment_w(sc : SceneW; var s : Script; var t : ETable) : string {
    var model = new WotlPoints(sc := sc, max_points = MAX_POINTS_W)
    model.metrics |> push_from(METRICS_W)
    let err = run_experiment(*model, s, t)
    unsafe {
        delete model
    }
    return err
}