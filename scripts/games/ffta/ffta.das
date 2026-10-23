options gen2
options indenting = 4

// Final Fantasy Tactics Advance: the game's panels. A BizHawk state
// (mGBA core) and the ROM are loaded; the battle units come from the
// state's RAM and the turn order from the model in ffta_battle.das.
module ffta shared public

require imgui
require dasimgui/imgui_boost
require daslib/fio
require gui_common
require gba_mem
require math
require strings
require daslib/strings_boost
require ../../ui/bnd_const.das
require ../../ui/bl_imgui.das
require ../../ui/inspector.das
require ../../core/game.das
require ../../core/result_try.das
require ../../app/shell.das
require ffta_battle
require ffta_attack
require ffta_field

let MAX_TURNS = 200

// x of the turn list columns
struct TurnColumns {
    x : float
    w : float
    num : float = 0.0
    name : float = 0.0
    when : float = 0.0
    nth : float = 0.0
    ends : float = 0.0
}

def turn_columns(x, w : float) : TurnColumns {
    return TurnColumns(x = x, w = w, num = x + u(12.0), name = x + u(40.0), when = x + u(220.0), nth = x + u(310.0),
        ends = x + u(370.0))
}


let STAT_SHORT = fixed_array<string>("Atk", "Def", "Pow", "Res", "Spd", "Eva", "Move", "Jump")

let STAT_LABELS = fixed_array<string>("W.Atk", "W.Def", "M.Pow", "M.Res", "Speed", "Evade", "Move", "Jump")

let KIND_FILTERS = fixed_array<string>("All", "Weapons", "Shields", "Head", "Body", "Shoes, armlets, rings")

def kind_matches(filter, kind : int) : bool {
    return (filter == 0 || (filter == 1 && kind <= 19) || (filter == 2 && kind == 20) ||
        (filter == 3 && kind >= 21 && kind <= 23) || (filter == 4 && kind >= 24 && kind <= 26) ||
        (filter == 5 && kind >= 27))
}

// what can be edited in a unit, as text: compared with the saved unit
def unit_key(u : BattleUnit) : string {
    return "{u.job_id} {u.support} {u.reaction} {u.hp} {u.max_hp} {u.mp} {u.ct} {u.reserve} {u.assumed} {u.stat_base} {u.items} {u.x} {u.y} {u.facing} {u.status} {[for (it in u.equip); it.id]} {u.learned}"
}

def bonus_text(it : Item) : string {
    let parts <- [for (i in range(STAT_COUNT)); "{STAT_SHORT[i]} {signed_text(it.bonus[i])}"; where it.bonus[i] != 0]
    return length(parts) > 0 ? join(parts, "  ") : "no stat bonus"
}

def signed_text(v : int) : string {
    return v > 0 ? "+{v}" : "{v}"
}

// text ending at x (right aligned)
def right_text(x, baseline : float; s : string; color : uint) {
    text_at_baseline(x - text_width(s), baseline, s, color)
}

def turn_end_text(how : TurnEnd) : string {
    return how == TurnEnd.MoveAndAct ? "Move + Act" : (how == TurnEnd.ActOnly ? "Act" : (how == TurnEnd.MoveOnly ? "Move" : "Wait"))
}

// last used paths, next to the project (not in the repository)
def private config_path() : string {
    return "{gui_project_dir()}/local.cfg"
}

class FftaGame : GameModule {
    units : array<BattleUnit>
    saved : array<BattleUnit>         // as read from the state: Revert
    item_catalog : array<Item>        // equipment, for the item list
    pick_slot : int = 0
    item_filter = ImGuiInputTextBuffer("", 64)
    item_kind_filter : int = 0
    turns : array<Turn>
    selected : int = -1
    turns_ahead : int = 24
    stats_open : bool = true
    calc_tab : int = 0                // 0 turn order, 1 attack
    scene_tab : int = 0               // 0 field, 1 the game screen
    battle_map : BattleMap
    field = FieldState()
    attacker : int = -1
    target : int = -1
    side_choice : int = 0             // SideChoice
    action : int = 0                  // 0 Fight, k: the attacker's k-th learned ability
    equip_open : bool = true
    status_open : bool = true
    abilities_open : bool = true
    job_open : table<string; bool>    // "race job": an open job block
    state_path : string
    rom_path : string
    export_path : string              // Export: the state with the edits
    message : string = "Load a BizHawk state (mGBA core) and the FFTA (USA) ROM"

    def FftaGame {
        for (line in split(fread(config_path()), "\n")) {
            if (starts_with(line, "state=")) {
                state_path = slice(line, 6)
            } elif (starts_with(line, "rom=")) {
                rom_path = slice(line, 4)
            }
        }
        state_path = gui_arg("--state", state_path)
        rom_path = gui_arg("--rom", rom_path)
        if (stat(state_path).is_valid && stat(rom_path).is_valid) {
            self->load()
        }
    }

    // the ROM, the state and the battle in it; "" or the first error
    def load_files() : string {
        try_ok(gba_load_rom(rom_path), "ROM: ")
        ensure(gba_rom_code() == "AFXE", "ROM {gba_rom_code()}: only FFTA (USA, AFXE) is supported")
        try_ok(gba_load_state(state_path), "State: ")
        try_ok(read_battle(units))
        return ""
    }

    def load() : void {
        let err = self->load_files()
        if (err != "") {
            message = err
            log_line(message)
            return
        }
        read_map(battle_map)
        field.cell = 0.0          // a new map: fit it again
        saved := units
        item_catalog |> clear()
        for (iid in range(1, ITEM_COUNT)) {
            let it = read_item(uint(iid))
            if (it.kind >= 1 && it.kind <= 29 && it.name != "" && it.name != "-") {
                item_catalog |> push(it)
            }
        }
        selected = length(units) > 0 ? 0 : -1
        self->update_turns()
        self->pick_attack()
        if (attacker >= 0) {
            selected = attacker
        }
        message = "{length(units)} units in battle"
        let dot = find(state_path, ".", max(0, length(state_path) - 6))
        export_path = dot >= 0 ? "{slice(state_path, 0, dot)}.edited{slice(state_path, dot)}" : "{state_path}.edited"
        log_line("loaded {state_path}: {message}")
        fwrite(config_path(), "state={state_path}\nrom={rom_path}\n")
    }

    // the unit taking its turn attacks the nearest unit of another side
    def pick_attack() : void {
        attacker = length(turns) > 0 ? turns[0].unit : selected
        target = -1
        var best = 1000
        for (i in range(length(units))) {
            if (attacker >= 0 && i != attacker && units[i].side != units[attacker].side) {
                let d = abs(units[i].x - units[attacker].x) + abs(units[i].y - units[attacker].y)
                if (d < best) {
                    best = d
                    target = i
                }
            }
        }
    }

    def update_turns() : void {
        turns <- predict_turns(units, turns_ahead)
    }

    def override id() : string {
        return "ffta"
    }

    def override title() : string {
        return "Final Fantasy Tactics Advance"
    }

    def source_fields(x, y, w : float) : float {
        let lw = u(54.0)
        var yy = y
        SetCursorScreenPos(ImVec2(x + u(6.0), yy))
        bl_label("State:", -1, lw)
        SetCursorScreenPos(ImVec2(x + u(6.0) + lw, yy))
        bl_string("state_path", state_path, w - lw - u(12.0))
        yy += u(23.0)
        SetCursorScreenPos(ImVec2(x + u(6.0), yy))
        bl_label("ROM:", -1, lw)
        SetCursorScreenPos(ImVec2(x + u(6.0) + lw, yy))
        bl_string("rom_path", rom_path, w - lw - u(12.0))
        yy += u(25.0)
        SetCursorScreenPos(ImVec2(x + u(6.0), yy))
        if (bl_tool_button("load", "Load", BND_ICON_FILE_REFRESH, w - u(12.0))) {
            self->load()
        }
        if (length(units) == 0) {
            return yy + u(30.0)
        }
        yy += u(30.0)
        SetCursorScreenPos(ImVec2(x + u(6.0), yy))
        bl_label("Export:", -1, lw)
        SetCursorScreenPos(ImVec2(x + u(6.0) + lw, yy))
        bl_string("export_path", export_path, w - lw - u(12.0))
        yy += u(25.0)
        SetCursorScreenPos(ImVec2(x + u(6.0), yy))
        if (bl_tool_button("export", "Export state with edits", BND_ICON_EXPORT, w - u(12.0))) {
            self->export_state()
        }
        return yy + u(30.0)
    }

    // the loaded state with the edited units, as a new file; "" or the
    // error, notes: what could not be written
    def export_files(var notes : string) : string {
        ensure(export_path != "" && export_path != state_path, "choose a path other than the loaded state")
        try_ok(export_battle(battle_map, units, saved, export_path, notes))
        return ""
    }

    def export_state() : void {
        var notes = ""
        let err = self->export_files(notes)
        message = err != "" ? "Export: {err}" : "exported to {export_path}"
        log_line(notes != "" ? "{message}; {notes}" : message)
    }

    def override draw_roster(x, y, w, h : float) : void {
        var ry = self->source_fields(x, y, w)
        let row_h = u(20.0)
        var dl = GetWindowDrawList()
        for (i in range(length(units))) {
            SetCursorScreenPos(ImVec2(x + u(2.0), ry))
            let clicked = InvisibleButton("##unit{i}", ImVec2(w - u(4.0), row_h))
            if (i == selected) {
                *dl |> AddRectFilled(ImVec2(x + u(2.0), ry), ImVec2(x + w - u(2.0), ry + row_h),
                    abgr(bt.menu_item.inner_sel), u(3.0), ImDrawFlags.None)
            } elif (IsItemHovered()) {
                *dl |> AddRectFilled(ImVec2(x + u(2.0), ry), ImVec2(x + w - u(2.0), ry + row_h),
                    abgr(0xffffff18u), 0.0, ImDrawFlags.None)
            }
            let un = units[i]
            let enemy = un.side == 1
            let color = i == selected ? 0xffffffffu : (enemy ? 0xffd0d0ffu : bt.regular.text)
            icon_label_value(x + u(8.0), ry, w, row_h, enemy ? BND_ICON_GHOST : BND_ICON_ARMATURE_DATA, color,
                false, "{un.name}  Lv{un.level}  Spd {un.speed}  CT {un.ct}")
            if (clicked) {
                selected = i
            }
            ry += row_h
        }
    }

    def override draw_inspector(x, y, w : float) : float {
        if (selected < 0 || selected >= length(units)) {
            return y
        }
        let before = unit_key(units[selected])
        let saved_key = unit_key(saved[selected])
        // revert buttons for the whole unit / all units
        var by = y
        let changed_any = self->any_changed()
        if (before != saved_key || changed_any) {
            let bw = floor((w - u(4.0)) * 0.5)
            SetCursorScreenPos(ImVec2(x, by))
            if (before != saved_key && bl_tool_button("revert_unit", "Revert unit", BND_ICON_LOOP_BACK, bw)) {
                units[selected] := saved[selected]
                self->update_turns()
            }
            SetCursorScreenPos(ImVec2(x + bw + u(4.0), by))
            if (changed_any && bl_tool_button("revert_all", "Revert all", BND_ICON_LOOP_BACK, bw)) {
                units := saved
                self->update_turns()
            }
            by += u(27.0)
        }
        by = self->job_row(units[selected], saved[selected], x, by, w)
        by = self->ability_row(units[selected], saved[selected], 3, x, by, w)
        by = self->ability_row(units[selected], saved[selected], 2, x, by, w)
        var bottom = inspect("unit{selected}", units[selected], saved[selected], x, by, w)
        bottom = self->stat_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        bottom = self->equip_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        bottom = self->status_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        bottom = self->ability_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        if (unit_key(units[selected]) != before) {
            recompute_unit(units[selected])
            self->update_turns()
        }
        return bottom
    }

    // the job: a list of the race's jobs (other races: the name only)
    def job_row(var unit : BattleUnit; saved_u : BattleUnit; x, y, w : float) : float {
        let lw = floor(w * 0.4)
        let bw = u(24.0)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Job:", -1, lw)
        SetCursorScreenPos(ImVec2(x + lw, y))
        var jobs <- race_jobs(unit.race)
        if (length(jobs) == 0) {
            bl_label(unit.job)
        } else {
            var names : array<string>
            var sel = -1
            for (k in range(length(jobs))) {
                names |> push(job_name(jobs[k], jobs[k]))
                if (jobs[k] == unit.job_id || (sel < 0 && names[k] == unit.job)) {
                    sel = k
                }
            }
            if (sel < 0) {
                names |> push(unit.job)
                sel = length(names) - 1
            }
            if (bl_choice("unit_job", names, sel, w - lw - bw) && sel < length(jobs)) {
                set_job(unit, jobs[sel])
            }
        }
        if (unit.job_id != saved_u.job_id && bl_revert_button("job_revert", x + w - u(22.0), y)) {
            unit.job_id = saved_u.job_id
            unit.job2 = saved_u.job2
            unit.job = saved_u.job
            unit.bare_power = saved_u.bare_power
            for (s in fixed_array(int(Stat.Evade), int(Stat.Move), int(Stat.Jump))) {
                unit.stat_base[s] = saved_u.stat_base[s]
            }
        }
        return y + u(30.0)
    }

    // Support (kind 3) / Reaction (kind 2): the race's abilities of that
    // kind, any of them (whether the unit learned it is not checked)
    def ability_row(var unit : BattleUnit; saved_u : BattleUnit; kind : int; x, y, w : float) : float {
        let lw = floor(w * 0.4)
        let bw = u(24.0)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label(kind == 3 ? "Support:" : "Reaction:", -1, lw)
        var list <- race_choices(unit.race, kind)
        var names <- ["none"]
        var sel = 0
        let cur = kind == 3 ? unit.support : unit.reaction
        for (k in range(length(list))) {
            names |> push(ffta_text2(list[k].name))
            if (list[k].id == cur) {
                sel = k + 1
            }
        }
        SetCursorScreenPos(ImVec2(x + lw, y))
        if (bl_choice(kind == 3 ? "unit_support" : "unit_reaction", names, sel, w - lw - bw)) {
            set_ability(unit, kind, sel == 0 ? 0 : list[sel - 1].id)
            if (kind == 3) {
                unit.support_name = names[sel]
            } else {
                unit.reaction_name = names[sel]
            }
        }
        let saved_id = kind == 3 ? saved_u.support : saved_u.reaction
        if (cur != saved_id && bl_revert_button(kind == 3 ? "support_revert" : "reaction_revert", x + w - u(22.0), y)) {
            if (kind == 3) {
                unit.support = saved_u.support
                unit.support_name = saved_u.support_name
            } else {
                unit.reaction = saved_u.reaction
                unit.reaction_name = saved_u.reaction_name
            }
        }
        return y + u(26.0)
    }

    def any_changed() : bool {
        for (i in range(length(units))) {
            if (i < length(saved) && unit_key(units[i]) != unit_key(saved[i])) {
                return true
            }
        }
        return false
    }

    // Status screen stats: base (editable; record / job) + equipment = total
    def stat_rows(var unit : BattleUnit; saved_u : BattleUnit; x, y, w : float) : float {
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("stats_section", "Stats", stats_open)) {
            return ry
        }
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let bw = u(24.0)
        let c_base = x + floor((w - bw) * 0.62)
        let c_items = x + floor((w - bw) * 0.8)
        let c_total = x + w - bw - u(6.0)
        right_text(c_base, ry + u(13.0), "base", dim)
        right_text(c_items, ry + u(13.0), "items", dim)
        right_text(c_total, ry + u(13.0), "total", dim)
        ry += u(18.0)
        let nw = u(70.0)
        for (i in range(STAT_COUNT)) {
            let b = ry + u(15.0)
            text_at_baseline(x + u(8.0), b, STAT_LABELS[i], fg)
            SetCursorScreenPos(ImVec2(c_base - nw, ry))
            var v = float(unit.stat_base[i])
            if (bl_number("stat_base{i}", "", v, 0.25, 0, nw)) {
                unit.stat_base[i] = clamp(int(round(v)), 0, 999)
            }
            let items = unit.stat_items[i]
            if (items != 0) {
                right_text(c_items, b, signed_text(items), items > 0 ? 0x70c070ffu : 0xe07070ffu)
            }
            right_text(c_total, b, "{unit.stat_total[i]}", fg)
            if (unit.stat_base[i] != saved_u.stat_base[i] && bl_revert_button("stat_revert{i}", x + w - u(22.0), ry)) {
                unit.stat_base[i] = saved_u.stat_base[i]
            }
            ry += u(23.0)
        }
        return ry
    }

    // equipment slots: a click opens the item list (name filter, kind
    // filter); the stats each item changes under it
    def equip_rows(var unit : BattleUnit; saved_u : BattleUnit; x, y, w : float) : float {
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("equip_section", "Equipment", equip_open)) {
            return ry
        }
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let bw = u(24.0)
        let kw = u(84.0)
        for (slot in range(5)) {
            let it = unit.equip[slot]
            SetCursorScreenPos(ImVec2(x, ry))
            let caption = it.id != 0 ? it.name : "(empty)"
            if (bl_tool_button("equip_slot{slot}", caption, -1, w - bw - kw - u(4.0))) {
                OpenPopup("##item_pick")
                pick_slot = slot
                item_filter = ImGuiInputTextBuffer("", 64)
            }
            if (it.id != 0) {
                right_text(x + w - bw - u(6.0), ry + u(15.0), item_kind_name(it.kind), dim)
            }
            if (it.id != saved_u.equip[slot].id && bl_revert_button("equip_revert{slot}", x + w - u(22.0), ry)) {
                unit.equip[slot] = saved_u.equip[slot]
            }
            ry += u(22.0)
            if (it.id != 0) {
                text_at_baseline(x + u(12.0), ry + u(13.0), bonus_text(it), dim)
                ry += u(19.0)
            }
        }
        self->item_picker(unit, x, w)
        return ry
    }

    // status bits +0xE8..+0xED as check boxes in two columns; a changed
    // bit is drawn in the accent color, the button reverts all of them
    def status_rows(var unit : BattleUnit; saved_u : BattleUnit; x, y, w : float) : float {
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        var status_changed = false
        for (i in range(6)) {
            status_changed = status_changed || unit.status[i] != saved_u.status[i]
        }
        if (status_changed && bl_revert_button("status_revert", x + w - u(22.0), y)) {
            unit.status = saved_u.status
        }
        SetCursorScreenPos(ImVec2(x, y))
        if (!bl_section("status_section", "Status", status_open)) {
            return ry
        }
        let cw = floor(w * 0.5)
        for (i in range(48)) {
            let col = i & 1
            let cx = x + u(6.0) + float(col) * cw
            SetCursorScreenPos(ImVec2(cx, ry))
            var on = has_status_bit(unit, i)
            let was = has_status_bit(saved_u, i)
            let caption = on != was ? "{STATUS_NAMES[i]} *" : STATUS_NAMES[i]
            if (bl_option("status_bit{i}", caption, on)) {
                let mask = 1u << uint(i & 7)
                unit.status[i >> 3] = on ? (unit.status[i >> 3] | mask) : (unit.status[i >> 3] & ~mask)
            }
            if (col == 1) {
                ry += u(21.0)
            }
        }
        return ry + u(4.0)
    }

    // Learned abilities (record +0x40 + i), one collapsible block per job
    // of the race list with a checkbox per ability; the unit's job is
    // open at first. "*": changed, R / S / C: reaction, support, combo.
    def ability_rows(var unit : BattleUnit; saved_u : BattleUnit; x, y, w : float) : float {
        var changed = false
        for (i in range(144)) {
            changed = changed || unit.learned[i] != saved_u.learned[i]
        }
        if (changed && bl_revert_button("abilities_revert", x + w - u(22.0), y)) {
            unit.learned = saved_u.learned
        }
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("abilities_section", "Abilities", abilities_open)) {
            return ry
        }
        let blocks <- ability_blocks(unit.race)
        let cw = floor(w * 0.5)
        for (b in blocks) {
            let key = "{unit.race} {b.job}"
            var have = 0
            var total = 0
            var diff = false
            for (i in range(b.first, b.last + 1)) {
                total++
                have += unit.learned[i] ? 1 : 0
                diff = diff || unit.learned[i] != saved_u.learned[i]
            }
            let jname = b.job >= 0 ? job_name(b.job, b.job) : "Other"
            if (!key_exists(job_open, key)) {
                // by name: Marc's job entry is not the race's Soldier entry
                job_open[key] = jname == unit.job || length(blocks) == 1
            }
            var open = job_open[key]
            SetCursorScreenPos(ImVec2(x + u(8.0), ry))
            bl_section("job_block{b.job}_{b.first}", "{jname}  {have} / {total}{diff ? " *" : ""}", open)
            job_open[key] = open
            ry += u(22.0)
            if (!open) {
                continue
            }
            var col = 0
            for (i in range(b.first, b.last + 1)) {
                let a = race_ability(unit.race, i)
                let mark = a.kind == 2 ? " (R)" : (a.kind == 3 ? " (S)" : (a.kind == 5 ? " (C)" : ""))
                let name = "{ffta_text2(a.name)}{mark}"
                SetCursorScreenPos(ImVec2(x + u(14.0) + float(col) * cw, ry))
                var on = unit.learned[i]
                if (bl_option("learned{i}", on != saved_u.learned[i] ? "{name} *" : name, on)) {
                    unit.learned[i] = on
                }
                col = 1 - col
                if (col == 0) {
                    ry += u(21.0)
                }
            }
            ry += col == 1 ? u(25.0) : u(4.0)
        }
        return ry + u(4.0)
    }

    // the list of equipment for the slot pick_slot
    def item_picker(var unit : BattleUnit; x, w : float) : void {
        SetNextWindowSize(ImVec2(max(w, u(330.0)), u(360.0)), ImGuiCond.Always)
        bl_push_popup_style()
        // opaque: the inspector text under it would show through
        PushStyleColor(ImGuiCol.PopupBg, abgr(bt.menu.inner | 0xffu))
        if (BeginPopup("##item_pick")) {
            let pw = GetContentRegionAvail().x
            let p = GetCursorScreenPos()
            SetCursorScreenPos(ImVec2(p.x + u(6.0), p.y + u(3.0)))
            // on the popup's dark background: the menu's light text
            bl_label("Name:", -1, u(52.0), bt.menu_item.text)
            SetCursorScreenPos(ImVec2(p.x + u(58.0), p.y + u(3.0)))
            if (!IsAnyItemActive()) {
                SetKeyboardFocusHere(0)
            }
            bl_text_field("item_filter", item_filter, pw - u(64.0))
            SetCursorScreenPos(ImVec2(p.x + u(6.0), p.y + u(28.0)))
            bl_label("Kind:", -1, u(52.0), bt.menu_item.text)
            SetCursorScreenPos(ImVec2(p.x + u(58.0), p.y + u(28.0)))
            var kinds <- [for (k in KIND_FILTERS); k]
            bl_choice("item_kind", kinds, item_kind_filter, pw - u(64.0))
            SetCursorScreenPos(ImVec2(p.x, p.y + u(56.0)))
            let filter = to_lower(to_string(item_filter))
            PushStyleColor(ImGuiCol.ChildBg, abgr(bt.menu.inner | 0xffu))
            BeginChild("item_list", ImVec2(pw, GetContentRegionAvail().y), ImGuiChildFlags.None, ImGuiWindowFlags.None)
            bl_popup_rows() {
                if (bl_menu_item("(empty)")) {
                    unit.equip[pick_slot] = Item()
                    CloseCurrentPopup()
                }
                for (it in item_catalog) {
                    if (!kind_matches(item_kind_filter, it.kind)) {
                        continue
                    }
                    if (filter != "" && find(to_lower(it.name), filter) < 0) {
                        continue
                    }
                    if (bl_menu_item("{it.name}   {item_kind_name(it.kind)}   {bonus_text(it)}")) {
                        unit.equip[pick_slot] = it
                        CloseCurrentPopup()
                    }
                }
            }
            EndChild()
            PopStyleColor(1)
            EndPopup()
        }
        PopStyleColor(1)
        bl_pop_popup_style()
    }

    def override draw_scene(x, y, w, h : float) : void {
        // tabs: the field / the screen stored in the state
        let tw = u(120.0)
        SetCursorScreenPos(ImVec2(x + u(8.0), y + u(6.0)))
        if (bl_radio_button("tab_field", "Field", BND_ICON_MESH_GRID, tw, BND_CORNER_RIGHT, scene_tab == 0)) {
            scene_tab = 0
        }
        SetCursorScreenPos(ImVec2(x + u(8.0) + tw, y + u(6.0)))
        if (bl_radio_button("tab_screen", "Screen", BND_ICON_IMAGE_DATA, tw, BND_CORNER_LEFT, scene_tab == 1)) {
            scene_tab = 1
        }
        let ty = y + u(32.0)
        if (scene_tab == 0) {
            self->field_view(x, ty, w, y + h - ty)
        } else {
            self->screen_view(x, ty, w, y + h - ty)
        }
    }

    // the field; below it what the mouse and keys do, turn buttons
    def field_view(x, y, w, h : float) : void {
        if (length(units) == 0) {
            SetCursorScreenPos(ImVec2(x + u(12.0), y + u(6.0)))
            bl_label(message, BND_ICON_INFO)
            return
        }
        let bar = u(28.0)
        let input = draw_field(battle_map, units, selected, target, attacker, field, x + u(8.0), y, w - u(16.0), h - bar)
        if (input.select >= 0) {
            selected = input.select
            attacker = input.select
        }
        if (input.target >= 0) {
            target = input.target
        }
        let by = y + h - bar + u(4.0)
        SetCursorScreenPos(ImVec2(x + u(8.0), by))
        if (bl_tool_button("turn_ccw", "", BND_ICON_LOOP_BACK, u(28.0), BND_CORNER_RIGHT) && selected >= 0) {
            turn(units[selected], false)
        }
        SetCursorScreenPos(ImVec2(x + u(36.0), by))
        if (bl_tool_button("turn_cw", "", BND_ICON_LOOP_FORWARDS, u(28.0), BND_CORNER_LEFT) && selected >= 0) {
            turn(units[selected], true)
        }
        SetCursorScreenPos(ImVec2(x + u(72.0), by))
        if (bl_tool_button("field_fit", "Fit", BND_ICON_ZOOM_ALL, u(56.0))) {
            field.cell = 0.0
        }
        SetCursorScreenPos(ImVec2(x + u(136.0), by))
        bl_label("Click: select   Right click: target   Drag: move   Q / E: turn   Wheel: zoom")
    }

    def screen_view(x, y, w, h : float) : void {
        if (!gba_frame_update(shell_renderer())) {
            SetCursorScreenPos(ImVec2(x + u(12.0), y + u(12.0)))
            bl_label(message, BND_ICON_INFO)
            return
        }
        let fw = gba_frame_width()
        let fh = gba_frame_height()
        let k = max(1.0, floor(min((w - u(16.0)) / fw, (h - u(40.0)) / fh)))
        let dx = x + floor((w - fw * k) * 0.5)
        let dy = y + u(8.0)
        gba_frame_draw(dx, dy, fw * k, fh * k)
        SetCursorScreenPos(ImVec2(dx, dy + fh * k + u(4.0)))
        bl_label("Screen stored in the state", BND_ICON_IMAGE_DATA)
    }

    def override draw_calc(x, y, w, h : float) : void {
        SetCursorScreenPos(ImVec2(x, y))
        if (length(units) == 0) {
            bl_label(message, BND_ICON_TIME)
            return
        }
        // tabs: turn order / attack
        let tw = u(120.0)
        if (bl_radio_button("tab_turns", "Turn order", BND_ICON_TIME, tw, BND_CORNER_RIGHT, calc_tab == 0)) {
            calc_tab = 0
        }
        SetCursorScreenPos(ImVec2(x + tw, y))
        if (bl_radio_button("tab_attack", "Attack", BND_ICON_HAND, tw, BND_CORNER_LEFT, calc_tab == 1)) {
            calc_tab = 1
        }
        let ty = y + u(28.0)
        if (calc_tab == 1) {
            self->attack_view(x, ty, w, y + h - ty)
        } else {
            self->turn_order(x, ty, w, y + h - ty)
        }
    }

    def turn_order(x, y, w, h : float) : void {
        SetCursorScreenPos(ImVec2(x, y))
        // header: what the list assumes, and how far ahead it goes
        let nw = u(170.0)
        bl_label("Turn order  (turn ends as 'Assumed turn' in Inspector)", BND_ICON_TIME, w - nw - u(8.0))
        SetCursorScreenPos(ImVec2(x + w - nw, y))
        var ahead = float(turns_ahead)
        if (bl_number("turns_ahead", "Turns ahead", ahead, 0.1, 0, nw)) {
            turns_ahead = clamp(int(round(ahead)), 1, MAX_TURNS)
            self->update_turns()
        }
        // column titles
        let row_h = u(22.0)
        let ty = y + u(26.0)
        let cols = turn_columns(x, w)
        var dl = GetWindowDrawList()
        let head = offset_color(bt.regular.text | 0xffu, 40)
        text_at_baseline(cols.num, ty + u(15.0), "#", head)
        text_at_baseline(cols.name, ty + u(15.0), "Unit", head)
        text_at_baseline(cols.when, ty + u(15.0), "In ticks", head)
        text_at_baseline(cols.nth, ty + u(15.0), "Turn", head)
        text_at_baseline(cols.ends, ty + u(15.0), "Ends with", head)
        *dl |> AddLine(ImVec2(x, ty + row_h), ImVec2(x + w, ty + row_h), abgr(bt.regular.outline), 1.0)
        // the rows scroll in a child window
        SetCursorScreenPos(ImVec2(x, ty + row_h + u(2.0)))
        let body_h = max(row_h, y + h - (ty + row_h + u(2.0)))
        BeginChild("turn_list", ImVec2(w, body_h), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        self->turn_rows(w, row_h)
        EndChild()
    }

    // Attack: attacker, action (Fight or a learned ability), target and
    // side from lists; the result (ffta_attack.das) and where each number
    // comes from
    def attack_view(x, y, w, h : float) : void {
        let n = length(units)
        attacker = clamp(attacker, 0, n - 1)
        target = clamp(target, 0, n - 1)
        var names : array<string>
        for (un in units) {
            names |> push(un.name)
        }
        let att = units[attacker]           // a copy: the rows below read it
        var actions <- [0]
        for (k in range(att.action_count)) {
            actions |> push(att.actions[k])
        }
        var action_names : array<string>
        for (aid in actions) {
            action_names |> push(ability_name(aid))
        }
        action = clamp(action, 0, length(actions) - 1)
        let auto_side = side_of(units[attacker], units[target])
        var sides <- ["Auto: {auto_side}", "Front", "Side", "Back"]
        let cw = floor((w - u(24.0)) / 4.0)
        let lw = u(58.0)
        let pick = $(i : int; caption, wid : string; items : array<string>; var value : int&) {
            let cx = x + float(i) * (cw + u(8.0))
            SetCursorScreenPos(ImVec2(cx, y))
            bl_label(caption, -1, lw)
            SetCursorScreenPos(ImVec2(cx + lw, y))
            bl_choice(wid, items, value, cw - lw)
        }
        pick(0, "Unit:", "atk_unit", names, attacker)
        pick(1, "Action:", "atk_action", action_names, action)
        pick(2, "Target:", "atk_target", names, target)
        pick(3, "Side:", "atk_side", sides, side_choice)
        let ability = actions[action]
        let info = tech_info(ability)
        if (attacker == target && !info.self_only) {
            SetCursorScreenPos(ImVec2(x, y + u(30.0)))
            bl_label("Pick a target other than the attacker", BND_ICON_INFO)
            return
        }
        let choice = side_choice == 1 ? SideChoice.Front : (side_choice == 2 ? SideChoice.Side :
            (side_choice == 3 ? SideChoice.Back : SideChoice.Auto))
        let tgt = info.self_only ? att : units[target]
        let r = act(battle_map, att, tgt, ability, choice)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let good = 0x70c070ffu
        let bad = 0xe07070ffu
        // the rows scroll in a child window
        SetCursorScreenPos(ImVec2(x, y + u(28.0)))
        BeginChild("attack_rows", ImVec2(w, max(u(40.0), h - u(28.0))), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        let top = GetCursorScreenPos().y
        let rw = floor((w - u(16.0)) * 0.5)
        let vx = u(90.0)
        var ly = top + u(20.0)
        var ry = ly
        let row = $(cx : float; var cy : float&; caption, value : string; color : uint) {
            text_at_baseline(cx, cy, caption, dim)
            text_at_baseline(cx + vx, cy, value, color)
            cy += u(19.0)
        }
        // what it does, and the damage formula
        let lx = x + u(4.0)
        let kind = r.physical ? "physical" : "magic"
        text_at_baseline(lx, ly - u(4.0), "{r.action_name} ({kind})", fg)
        ly += u(18.0)
        row(lx, ly, "Effect", r.effect, r.tech == TechKind.Unknown ? bad : fg)
        if (r.uses_weapon) {
            let element = r.element > 0 ? ", {ELEMENTS[r.element]}" : ""
            row(lx, ly, "Weapon", "{r.weapon}{element}", fg)
        }
        let reach = r.reach ? "yes" : "NO"
        row(lx, ly, "Reach", "{reach}: {r.reach_text}", r.reach ? fg : bad)
        if (r.mp_cost > 0) {
            row(lx, ly, "MP", "{r.mp_cost} of {att.mp}", att.mp >= r.mp_cost ? fg : bad)
        }
        if (r.note != "") {
            row(lx, ly, "Also", r.note, dim)
        }
        if (r.area > 0) {
            // everyone within the radius of the target tile (height not checked)
            var hit : array<string>
            for (i in range(n)) {
                let u = units[i]
                if (abs(u.x - tgt.x) + abs(u.y - tgt.y) <= r.area) {
                    let ur = act(battle_map, att, u, ability, choice)
                    hit |> push(ur.tech == TechKind.Status ? "{u.name} {ur.hit}%" : "{u.name} {ur.damage} ({ur.hit}%)")
                }
            }
            row(lx, ly, "Area", "radius {r.area}: {join(hit, ", ")}", fg)
        }
        let damaging = r.tech != TechKind.Status && r.tech != TechKind.Info
        if (damaging) {
            let amods = r.attack_mods != "" ? " ({r.attack_mods})" : ""
            let dmods = r.defense_mods != "" ? " ({r.defense_mods})" : ""
            let a_name = r.physical ? "W.Atk" : "M.Pow"
            let d_name = r.physical ? "W.Def" : "M.Res"
            row(lx, ly, "Attack A", "{a_name} {r.attack_base}{amods} + P {r.power} = {r.attack}", fg)
            row(lx, ly, "Defense D", "{d_name} {r.defense_base}{dmods} + items {r.defense_items} = {r.defense}", fg)
            row(lx, ly, "A - D/2", "{r.attack} - {r.defense >> 1} = {r.base}", fg)
            if (r.element > 0) {
                let aff = r.affinity == 0 ? "weak x1.5" : (r.affinity == 2 ? "immune" : (r.affinity == 3 ? "absorbs" :
                    (r.affinity == 4 ? "half" : "normal")))
                row(lx, ly, "Element", "{ELEMENTS[r.element]}: target {aff}", fg)
            }
            let what = r.tech == TechKind.Heal ? "Heal" : (r.tech == TechKind.MpDamage ? "MP damage" : "Damage")
            row(lx, ly, what, "{r.damage}  (real {r.dmg_min}..{r.dmg_max}; base x {r.multiplier} / 100)", good)
            if (r.ability == 0) {
                row(lx, ly, "Critical", "{r.crit_damage}  ({r.crit_min}..{r.crit_max}; x1.5, knockback)", fg)
            }
            if (r.dmg_min > 0 && (r.tech == TechKind.Fight || r.tech == TechKind.Damage)) {
                let most = (tgt.hp + r.dmg_min - 1) / r.dmg_min
                let least = (tgt.hp + r.dmg_max - 1) / r.dmg_max
                let hits = most == least ? "{most}" : "{least}..{most}"
                row(lx, ly, "Target HP", "{tgt.hp}/{tgt.max_hp}: KO in {hits} hits", fg)
            }
        }
        row(lx, ly, "Support", "{att.support_name} / target {tgt.support_name}", fg)
        // hit chance
        let hx = x + rw + u(16.0)
        text_at_baseline(hx, ry - u(4.0), r.tech == TechKind.Status ? "Success chance" : "Hit chance", fg)
        ry += u(18.0)
        let how = choice == SideChoice.Auto ? "{att.x},{att.y} -> {tgt.x},{tgt.y} facing {FACING_NAMES[tgt.facing & 3]}" : "chosen"
        if (!info.self_only) {
            row(hx, ry, "Side", "{r.side}  ({how})", fg)
        }
        if (r.cannot_evade) {
            row(hx, ry, "Evade", info.self_only ? "the user: always" : "target cannot evade", fg)
        } else {
            row(hx, ry, "Evade", "{r.evade}: {r.evade_mods} -> {r.evade_final} (5..95)", fg)
        }
        row(hx, ry, "Shown", "{r.hit}%  (the game's preview)", good)
        let bonus = r.hit_roll != r.hit ? " (shown + 10)" : ""
        let rr = info.self_only ? ReactionResult() : reaction(battle_map, att, tgt, ability, r)
        if (rr.dodge) {
            row(hx, ry, "Rolled", "0%  ({rr.name} dodges)", bad)
        } else {
            row(hx, ry, "Rolled", "{r.hit_roll}%{bonus}, real {fmt(":.1f", r.hit_prob * 100.0)}%", fg)
        }
        if (r.ability == 0) {
            row(hx, ry, "Critical", "{r.crit}% (job Evade / 10), real {fmt(":.1f", r.crit_prob * 100.0)}%", fg)
        }
        if (damaging) {
            row(hx, ry, "Expected", "{fmt(":.1f", rr.dodge ? 0.0 : r.expected)} per use", fg)
        }
        if (tgt.reaction != 0 && !info.self_only) {
            row(hx, ry, "Reaction", rr.triggers ? rr.text : "{rr.name}: does not trigger", rr.triggers ? bad : dim)
            if (rr.counter) {
                let b = rr.back
                row(hx, ry, "Strikes back", "{b.damage} ({b.dmg_min}..{b.dmg_max}), {b.hit_roll}% real {fmt(":.1f", b.hit_prob * 100.0)}%", bad)
            }
        }
        SetCursorScreenPos(ImVec2(x, max(ly, ry)))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }

    // one row per predicted turn: side bar, number, unit, ticks from now,
    // which turn of that unit it is, and how it is assumed to end
    def turn_rows(w, row_h : float) : void {
        var dl = GetWindowDrawList()
        let origin = GetCursorScreenPos()
        let cols = turn_columns(origin.x, w)
        var nth : array<int>
        nth |> resize(length(units))
        var time = 0
        for (k in range(length(turns))) {
            let t = turns[k]
            let un = units[t.unit]
            time += t.ticks
            nth[t.unit]++
            let ry = origin.y + float(k) * row_h
            SetCursorScreenPos(ImVec2(origin.x, ry))
            if (InvisibleButton("##turn{k}", ImVec2(w - u(14.0), row_h))) {
                selected = t.unit
            }
            let hovered = IsItemHovered()
            let now = k == 0 && t.ticks == 0 && t.ct >= CT_TURN
            var bg = k % 2 == 0 ? 0x00000000u : 0x0000001au
            if (t.unit == selected) {
                bg = 0x5680c260u
            } elif (hovered) {
                bg = 0xffffff18u
            }
            if ((bg & 0xffu) != 0u) {
                *dl |> AddRectFilled(ImVec2(origin.x, ry), ImVec2(origin.x + w - u(14.0), ry + row_h), abgr(bg), 0.0,
                    ImDrawFlags.None)
            }
            *dl |> AddRectFilled(ImVec2(origin.x + u(2.0), ry + u(3.0)), ImVec2(origin.x + u(6.0), ry + row_h - u(3.0)),
                abgr(side_color(un.side)), u(2.0), ImDrawFlags.None)
            let fg = t.unit == selected ? 0xffffffffu : bt.regular.text
            let dim = offset_color(fg, t.unit == selected ? -40 : 50)
            let ty = ry + floor((row_h - GetFontSize()) * 0.5)
            let tb = ty + GetFontSize() * 0.797
            text_at_baseline(cols.num, tb, "{k + 1}", dim)
            text_at_baseline(cols.name, tb, un.name, fg)
            text_at_baseline(cols.name + u(110.0), tb, "Lv{un.level}", dim)
            if (now) {
                let bx = cols.when
                *dl |> AddRectFilled(ImVec2(bx - u(4.0), ry + u(3.0)), ImVec2(bx + u(38.0), ry + row_h - u(3.0)),
                    abgr(0xe0a030ffu), u(4.0), ImDrawFlags.None)
                text_at_baseline(bx, tb, "NOW", 0x000000ffu)
            } else {
                text_at_baseline(cols.when, tb, "+{time}", fg)
            }
            text_at_baseline(cols.nth, tb, "{nth[t.unit]}", dim)
            text_at_baseline(cols.ends, tb, turn_end_text(un.assumed), dim)
        }
        SetCursorScreenPos(ImVec2(origin.x, origin.y + float(length(turns)) * row_h))
        Dummy(ImVec2(1.0, u(4.0)))
    }

    def override status() : string {
        return "FFTA: {message}"
    }
}
