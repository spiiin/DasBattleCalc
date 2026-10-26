options gen2
options indenting = 4

// Final Fantasy Tactics A2 (NDS): the game's panels. A BizHawk state
// (melonDS core) and the ROM are loaded; the units come from the state's
// RAM (ffta2_battle.das). Phase 1: units, stats, equipment, the field
// (flat: the heights of the map are not known yet).
module ffta2 shared public

require imgui
require dasimgui/imgui_boost
require daslib/fio
require gui_common
require gba_mem
require math
require strings
require daslib/strings_boost
require ../../ui/bnd_const.das
require ../../ui/icons.das
require ../../ui/bl_imgui.das
require ../../ui/inspector.das
require ../../ui/battle_field.das
require ../../ui/roster.das
require ../../core/game.das
require ../../core/config.das
require ../../core/result_try.das
require ../../core/explore.das
require ../../ui/explore_view.das
require ../../ui/explore_panel.das
require ../../app/shell.das
require ffta2_battle
require ffta2_attack
require ffta2_forecast
require ffta2_turns
require ffta2_explore

let private STAT2_SHORT = fixed_array<string>("Atk", "Def", "Mag", "Res", "Spd", "Eva", "Move", "Jump")

def private signed2(v : int) : string {
    return v > 0 ? "+{v}" : "{v}"
}

def private bonus2_text(it : Item2) : string {
    let parts <- [for (i in range(STAT2_COUNT)); "{STAT2_SHORT[i]} {signed2(it.bonus[i])}"; where it.bonus[i] != 0]
    return length(parts) > 0 ? join(parts, "  ") : "no stat bonus"
}

// equipment kinds (equipment +0), by their items
let private GBA_ICON_BASE2 = 65536       // GBA_GFX_ICON_BASE: icon ids drawn by gba_gfx

let private KIND2_NAMES = fixed_array<string>("", "Knife", "Sword", "Blade", "Saber", "Knightsword", "Rapier",
    "Greatsword", "Broadsword", "Katana", "Spear", "Rod", "Staff", "Pole", "Knuckles", "Bow", "Greatbow", "Gun",
    "Instrument", "Hand-cannon", "-", "Axe", "Hammer", "Mace", "Card", "Book", "Shield", "Helm", "Ribbon", "Hat",
    "Armor", "Clothing", "Robe", "Shoes", "Gloves", "Accessory")

def private kind2_name(kind : int) : string {
    return kind > 0 && kind < length(KIND2_NAMES) ? KIND2_NAMES[kind] : "kind {kind}"
}

def private right2(x, baseline : float; s : string; color : uint) {
    text_at_baseline(x - text_width(s), baseline, s, color)
}

def private magick_text(ab : Ability2) : string {
    return ab.id == ATTACK_ABILITY ? "" : (is_magick2(ab) ? ", magick" : ", physical")
}

// Explore editor colors: what a word of the script is
class Ffta2Game : GameModule {
    units : array<Unit2>
    saved : array<Unit2>              // as read from the state: Revert
    selected : int = -1
    target : int = -1
    field = FieldState()
    field_map : FieldMap
    map2 : Map2
    scene_tab : int = 0               // 0 field, 1 the game screen, 2 the Explore chart
    calc_tab : int = 0                // 0 turn order, 1 attack, 2 explore, 3 units
    side_choice : int = 0             // 0 auto, 1 + Side2
    privilege : int = 0               // the clan privilege (game variable 369), 0 none
    actions : array<int>              // the abilities the model computes, Attack first
    action_names : array<string>
    action : int = 0                  // index in actions
    action_filter : string
    rom_serial : uint                 // actions are rebuilt for another ROM
    stats_open : bool = true
    equip_open : bool = true
    status_open : bool = false
    abilities_open : bool = true
    job_open : table<string; bool>    // "unit job": an open job block of the abilities
    pick_slot : int = 0
    item_filter = ImGuiInputTextBuffer("", 64)
    item_all : bool = false           // the item list: every item, not only what the job can wear
    turns_ahead : int = 24            // Turn order: how many turns to predict
    known_only : bool = true          // the Attack tab's actions: only what the attacker knows (unit_knows)
    rom_sprites2 : bool = true        // the units' sprites from the ROM on the field (View menu, local.cfg)
    rom_icons2 : bool = true          // item icons from the ROM
    state_path : string
    rom_path : string
    loaded_state : string
    loaded_rom : string
    export_path : string              // Export: the state with the edits
    from_args : bool
    message : string = "Load a BizHawk state (melonDS core) and the FFTA2 (USA) ROM"
    // Explore: the script, its table and chart
    explore : ExplorePanel = make_explore_panel("explore2", EXPLORE2_NAMES, EXPLORE2_EXAMPLES,
        EXPLORE2_GENERATORS, METRICS2)

    def Ffta2Game {
        state_path = config_get("ffta2_state")
        rom_sprites2 = config_get("ffta2_rom_sprites", "1") == "1"
        rom_icons2 = config_get("ffta2_rom_icons", "1") == "1"
        rom_path = config_get("ffta2_rom")
        // the command line names the files of the game it starts with
        if (gui_arg("--game", "") == "ffta2") {
            from_args = gui_arg("--state", "") != "" || gui_arg("--rom", "") != ""
            state_path = gui_arg("--state", state_path)
            rom_path = gui_arg("--rom", rom_path)
        }
    }

    def override id() : string {
        return "ffta2"
    }

    // the units' sprites from the ROM, remembered in local.cfg
    def override view_items() : array<string> {
        return <- ["ROM sprites: {rom_sprites2 ? "on" : "off"}", "ROM icons: {rom_icons2 ? "on" : "off"}"]
    }

    // an item's icon for bl_tool_button / bl_menu_item, -1 when off
    def item_icon2(it : Item2) : int {
        if (!rom_icons2 || it.id == 0) {
            return -1
        }
        let h = nds_item_icon(shell_renderer(), it.icon)
        return h >= 0 ? GBA_ICON_BASE2 + h : -1
    }

    def override view_pick(i : int) : void {
        if (i == 0) {
            rom_sprites2 = !rom_sprites2
            config_set("ffta2_rom_sprites", rom_sprites2 ? "1" : "0")
        } elif (i == 1) {
            rom_icons2 = !rom_icons2
            config_set("ffta2_rom_icons", rom_icons2 ? "1" : "0")
        }
    }

    def override title() : string {
        return "Final Fantasy Tactics A2"
    }

    def override status() : string {
        return "FFTA2: {message}"
    }

    def override accepts_rom(code : string) : bool {
        return code == FFTA2_CODE
    }

    // the web page's files (always at the same paths): load them again
    def override reload() : void {
        state_path = gui_arg("--state", state_path)
        rom_path = gui_arg("--rom", rom_path)
        self->load(false)
    }

    def override activate() : void {
        if (length(units) == 0) {
            if (stat(state_path).is_valid && stat(rom_path).is_valid) {
                self->load(!from_args)
            }
        } elif (gba_rom_code() != FFTA2_CODE) {
            gba_load_rom(loaded_rom)
            gba_load_state(loaded_state)
        }
    }

    def load_files() : string {
        try_ok(gba_load_rom(rom_path), "ROM: ")
        ensure(gba_rom_code() == FFTA2_CODE, "ROM {gba_rom_code()}: only FFTA2 (USA, A6FE) is supported")
        try_ok(gba_load_state(state_path), "State: ")
        try_ok(read_battle2(units))
        return ""
    }

    def load(remember : bool = true) : void {
        let err = self->load_files()
        if (err != "") {
            message = err
            log_line(message)
            return
        }
        loaded_state = state_path
        loaded_rom = rom_path
        saved := units
        self->make_map()
        field.cell = 0.0
        selected = length(units) > 0 ? length(units) - 1 : -1
        target = -1
        message = "{length(units)} units in battle"
        let dot = find(state_path, ".", max(0, length(state_path) - 6))
        export_path = dot >= 0 ? "{slice(state_path, 0, dot)}.edited{slice(state_path, dot)}" : "{state_path}.edited"
        log_line("loaded {state_path}: {message}")
        if (remember) {
            config_set("ffta2_state", state_path)
            config_set("ffta2_rom", rom_path)
        }
    }

    // the battle map (heights shown as the game shows them); a flat field
    // around the units when the state has none
    // the loaded state with the edited units as a new file
    def export_state() : void {
        var err = ""
        if (export_path == "" || export_path == state_path) {
            err = "choose a path other than the loaded state"
        } else {
            err = export_battle2(units, map2, export_path)
        }
        message = err != "" ? "Export: {err}" : "exported to {export_path}"
        log_line(message)
    }

    def make_map() : void {
        if (read_map2(map2)) {
            field_map = FieldMap(w = map2.w, h = map2.h, shown_shift = -1)
            field_map.height |> resize(map2.w * map2.h)
            field_map.water |> resize(map2.w * map2.h)
            for (i in range(map2.w * map2.h)) {
                field_map.height[i] = map2.height[i] + 1
            }
            return
        }
        var w = 1
        var h = 1
        for (un in units) {
            w = max(w, un.x + 2)
            h = max(h, un.y + 2)
        }
        field_map <- flat_field(w, h)
    }

    def override draw_roster(x, y, w, h : float) : void {
        var pressed = 0
        var ry = source_fields(state_path, rom_path, export_path, length(units) > 0, x, y, w, pressed)
        if (pressed == ROSTER_LOAD) {
            self->load()
        } elif (pressed == ROSTER_EXPORT) {
            self->export_state()
        }
        for (i in range(length(units))) {
            let un = units[i]
            let text = "{un.name}  Lv{un.level}  Spd {un.stat_total[4]}  CT {un.ct}"
            if (roster_row(i, i == selected, un.team, text, x, ry, w)) {
                selected = i
            }
            ry += u(ROSTER_ROW_H)
        }
    }

    def override draw_inspector(x, y, w : float) : float {
        if (selected < 0 || selected >= length(units)) {
            return y
        }
        var by = y
        if (inspect_changed(units[selected], saved[selected])) {
            SetCursorScreenPos(ImVec2(x, by))
            if (bl_tool_button("revert_unit", "Revert unit", ICON_TURN_CCW, w)) {
                units[selected] := saved[selected]
            }
            by += u(27.0)
        }
        by = self->job_row(units[selected], saved[selected], x, by, w)
        by = self->ability_row2(units[selected], saved[selected], true, x, by, w)
        by = self->ability_row2(units[selected], saved[selected], false, x, by, w)
        var bottom = inspect("unit2_{selected}", units[selected], saved[selected], x, by, w)
        bottom = self->stat_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        bottom = self->equip_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        bottom = self->status_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        bottom = self->ability_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        recompute_unit(units[selected])
        return bottom
    }

    // the job: a list of the jobs of the unit's class (a monster: its own)
    def job_row(var unit : Unit2; saved_u : Unit2; x, y, w : float) : float {
        let lw = floor(w * 0.4)
        let bw = u(24.0)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Job:", -1, lw)
        SetCursorScreenPos(ImVec2(x + lw, y))
        let jobs <- class_jobs(saved_u.job_id)
        var names : array<string>
        var sel = -1
        for (k in range(length(jobs))) {
            names |> push(job_name(jobs[k]))
            if (jobs[k] == unit.job_id) {
                sel = k
            }
        }
        if (sel < 0) {
            names |> push(unit.job)
            sel = length(names) - 1
        }
        if (bl_choice("unit2_job", names, sel, w - lw - bw) && sel < length(jobs)) {
            set_job2(unit, jobs[sel])
        }
        if (unit.job_id != saved_u.job_id && bl_revert_button("job2_revert", x + w - u(22.0), y)) {
            set_job2(unit, saved_u.job_id)
        }
        return y + u(26.0)
    }

    // Support / Reaction: any of the game's (whether the unit learned it
    // is not checked)
    def ability_row2(var unit : Unit2; saved_u : Unit2; support : bool; x, y, w : float) : float {
        let lw = floor(w * 0.4)
        let bw = u(24.0)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label(support ? "Support:" : "Reaction:", -1, lw)
        let list <- support ? support_ids() : reaction_ids()
        var names <- ["none"]
        var sel = 0
        let cur = support ? unit.support : unit.reaction
        for (k in range(length(list))) {
            names |> push(ability_name2(list[k]))
            if (list[k] == cur) {
                sel = k + 1
            }
        }
        SetCursorScreenPos(ImVec2(x + lw, y))
        if (bl_choice(support ? "unit2_support" : "unit2_reaction", names, sel, w - lw - bw)) {
            let aid = sel == 0 ? 0 : list[sel - 1]
            if (support) {
                unit.support = aid
                unit.support_name = names[sel]
            } else {
                unit.reaction = aid
            }
        }
        let saved_id = support ? saved_u.support : saved_u.reaction
        if (cur != saved_id && bl_revert_button(support ? "support2_revert" : "reaction2_revert", x + w - u(22.0), y)) {
            if (support) {
                unit.support = saved_u.support
                unit.support_name = saved_u.support_name
            } else {
                unit.reaction = saved_u.reaction
            }
        }
        return y + u(26.0)
    }

    // statuses 1..71 (record +0x28 bits) as check boxes in two columns;
    // "*": changed, the button reverts all of them
    def status_rows(var unit : Unit2; saved_u : Unit2; x, y, w : float) : float {
        var names : array<string>
        var changed = false
        for (n in range(1, 72)) {
            changed = changed || has_status2(unit, n) != has_status2(saved_u, n)
            if (has_status2(unit, n)) {
                names |> push(status_name(n))
            }
        }
        if (changed && bl_revert_button("status2_revert", x + w - u(22.0), y)) {
            unit.status = saved_u.status
        }
        SetCursorScreenPos(ImVec2(x, y))
        let now = length(names) > 0 ? join(names, ", ") : "none"
        var ry = y + u(23.0)
        if (!bl_section("status2_section", "Status: {now}", status_open)) {
            return ry
        }
        let cw = floor(w * 0.5)
        var col = 0
        for (n in range(1, 72)) {
            let name = status_name(n)
            if (name == "" || name == "-") {
                continue
            }
            SetCursorScreenPos(ImVec2(x + u(6.0) + float(col) * cw, ry))
            var on = has_status2(unit, n)
            let caption = on != has_status2(saved_u, n) ? "{name} *" : name
            if (bl_option("status2_{n}", caption, on)) {
                let mask = 1u << uint(n & 7)
                let b = uint(unit.status[n >> 3])
                unit.status[n >> 3] = uint8(on ? (b | mask) : (b & ~mask))
            }
            col = 1 - col
            if (col == 0) {
                ry += u(21.0)
            }
        }
        return ry + (col == 1 ? u(25.0) : u(4.0))
    }

    // Learned abilities (record +0x52 + the ability's index for the job
    // class: AP, bit 7 mastered), one collapsible block per job of the
    // unit's class with a check box per ability (mastered); the unit's
    // job is open at first. "*": changed, "AP n": learning.
    def ability_rows(var unit : Unit2; saved_u : Unit2; x, y, w : float) : float {
        var changed = false
        for (i in range(LEARNED_SIZE)) {
            changed = changed || unit.learned[i] != saved_u.learned[i]
        }
        if (changed && bl_revert_button("abilities2_revert", x + w - u(22.0), y)) {
            unit.learned = saved_u.learned
        }
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("abilities2_section", "Abilities", abilities_open)) {
            return ry
        }
        let cls = job_class(unit.job_id)
        let cw = floor(w * 0.5)
        for (j in class_jobs(unit.job_id)) {
            let list <- job_abilities(j)
            if (length(list) == 0) {
                continue
            }
            var have = 0
            var diff = false
            for (aid in list) {
                let sl = learn_slot(read_ability2(aid), cls)
                have += (uint(unit.learned[sl]) & 0x80u) != 0u ? 1 : 0
                diff = diff || unit.learned[sl] != saved_u.learned[sl]
            }
            let key = "{unit.name} {j}"
            if (!key_exists(job_open, key)) {
                job_open[key] = j == unit.job_id
            }
            var open = job_open[key]
            SetCursorScreenPos(ImVec2(x + u(8.0), ry))
            bl_section("job2_block{j}", "{job_name(j)}  {have} / {length(list)}{diff ? " *" : ""}", open)
            job_open[key] = open
            ry += u(22.0)
            if (!open) {
                continue
            }
            var col = 0
            for (aid in list) {
                let sl = learn_slot(read_ability2(aid), cls)
                let v = uint(unit.learned[sl])
                let ap = (v & 0x7Fu) != 0u && (v & 0x80u) == 0u ? " (AP {v & 0x7Fu})" : ""
                let name = "{read_ability2(aid).name}{ap}"
                SetCursorScreenPos(ImVec2(x + u(14.0) + float(col) * cw, ry))
                var on = (v & 0x80u) != 0u
                let caption = unit.learned[sl] != saved_u.learned[sl] ? "{name} *" : name
                if (bl_option("learned2_{j}_{aid}", caption, on)) {
                    unit.learned[sl] = uint8(on ? (v | 0x80u) : (v & 0x7Fu))
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

    // Unit Info stats: base (raw / 4, Speed, job Move / Jump) + equipment
    def stat_rows(var un : Unit2; saved_u : Unit2; x, y, w : float) : float {
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("stats2_section", "Stats", stats_open)) {
            return ry
        }
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let c_base = x + floor(w * 0.6)
        let c_items = x + floor(w * 0.8)
        let c_total = x + w - u(6.0)
        right2(c_base, ry + u(13.0), "base", dim)
        right2(c_items, ry + u(13.0), "items", dim)
        right2(c_total, ry + u(13.0), "total", dim)
        ry += u(18.0)
        for (i in range(STAT2_COUNT)) {
            let b = ry + u(15.0)
            text_at_baseline(x + u(8.0), b, STAT2_LABELS[i], fg)
            if (i < 5) {
                // Attack .. Resistance: the record holds raw = shown x 4; Speed
                let nw = u(78.0)
                SetCursorScreenPos(ImVec2(c_base - nw, ry))
                var v = float(un.stat_base[i])
                if (bl_number("stat2_{i}", "", v, 0.2, 0, nw)) {
                    let n = clamp(int(round(v)), 0, i < 4 ? 16383 : 255)
                    if (i < 4) {
                        un.raw[i] = n * 4 + (un.raw[i] & 3)
                    } else {
                        un.base_speed = n
                    }
                }
                let changed = i < 4 ? un.raw[i] != saved_u.raw[i] : un.base_speed != saved_u.base_speed
                if (changed && bl_revert_button("stat2_revert{i}", c_base - nw - u(24.0), ry)) {
                    if (i < 4) {
                        un.raw[i] = saved_u.raw[i]
                    } else {
                        un.base_speed = saved_u.base_speed
                    }
                }
            } else {
                right2(c_base, b, "{un.stat_base[i]}", fg)
            }
            let items = un.stat_items[i]
            if (items != 0) {
                right2(c_items, b, signed2(items), items > 0 ? 0x70c070ffu : 0xe07070ffu)
            }
            right2(c_total, b, "{un.stat_total[i]}", fg)
            ry += u(21.0)
        }
        return ry
    }

    // equipment slots: a click opens the list of items the unit's job
    // can wear (name filter; "All items" shows the rest too); the stats
    // each item changes under it
    def equip_rows(var un : Unit2; saved_u : Unit2; x, y, w : float) : float {
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("equip2_section", "Equipment", equip_open)) {
            return ry
        }
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let bw = u(24.0)
        let kw = u(96.0)
        for (slot in range(EQUIP_SLOTS)) {
            let it = un.equip[slot]
            SetCursorScreenPos(ImVec2(x, ry))
            let caption = it.id != 0 ? it.name : "(empty)"
            if (bl_tool_button("equip2_slot{slot}", caption, self->item_icon2(it), w - bw - kw - u(4.0))) {
                OpenPopup("##item2_pick")
                pick_slot = slot
                item_filter = ImGuiInputTextBuffer("", 64)
            }
            if (it.id != 0) {
                let bad = can_equip(un.job_id, it) ? "" : " (!)"
                right2(x + w - bw - u(6.0), ry + u(15.0), "{kind2_name(it.kind)}{bad}", dim)
            }
            if (it.id != saved_u.equip[slot].id && bl_revert_button("equip2_revert{slot}", x + w - u(22.0), ry)) {
                un.equip[slot] = saved_u.equip[slot]
                un.items[slot] = saved_u.items[slot]
            }
            ry += u(22.0)
            if (it.id != 0) {
                text_at_baseline(x + u(12.0), ry + u(13.0), bonus2_text(it), dim)
                ry += u(19.0)
            }
        }
        self->item_picker(un, x, w)
        return ry
    }

    // the list of equipment for the slot pick_slot: what the job can wear
    def item_picker(var un : Unit2; x, w : float) : void {
        SetNextWindowSize(ImVec2(max(w, u(330.0)), u(360.0)), ImGuiCond.Always)
        bl_push_popup_style()
        PushStyleColor(ImGuiCol.PopupBg, abgr(bt.menu.inner | 0xffu))
        if (BeginPopup("##item2_pick")) {
            let pw = GetContentRegionAvail().x
            let p = GetCursorScreenPos()
            SetCursorScreenPos(ImVec2(p.x + u(6.0), p.y + u(3.0)))
            bl_label("Name:", -1, u(52.0), bt.menu_item.text)
            SetCursorScreenPos(ImVec2(p.x + u(58.0), p.y + u(3.0)))
            if (!IsAnyItemActive()) {
                SetKeyboardFocusHere(0)
            }
            bl_text_field("item2_filter", item_filter, pw - u(64.0))
            SetCursorScreenPos(ImVec2(p.x + u(6.0), p.y + u(28.0)))
            bl_option("item2_all", "All items (not only what {un.job} can wear)", item_all)
            SetCursorScreenPos(ImVec2(p.x, p.y + u(56.0)))
            let filter = to_lower(to_string(item_filter))
            PushStyleColor(ImGuiCol.ChildBg, abgr(bt.menu.inner | 0xffu))
            BeginChild("item2_list", ImVec2(pw, GetContentRegionAvail().y), ImGuiChildFlags.None, ImGuiWindowFlags.None)
            bl_popup_rows() {
                if (bl_menu_item("(empty)")) {
                    un.equip[pick_slot] = Item2()
                    un.items[pick_slot] = 0
                    CloseCurrentPopup()
                }
                for (iid in range(1, item_count())) {
                    let it = read_item2(iid)
                    if (it.kind <= 0 || it.name == "" || it.name == "-" || (!item_all && !can_equip(un.job_id, it))) {
                        continue
                    }
                    if (filter != "" && find(to_lower(it.name), filter) < 0) {
                        continue
                    }
                    if (bl_menu_item("{it.name}   {kind2_name(it.kind)}   {bonus2_text(it)}", self->item_icon2(it))) {
                        un.equip[pick_slot] = it
                        un.items[pick_slot] = it.id
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
        let tw = u(120.0)
        SetCursorScreenPos(ImVec2(x + u(8.0), y + u(6.0)))
        if (bl_radio_button("tab2_field", "Field", ICON_FIELD, tw, BND_CORNER_RIGHT, scene_tab == 0)) {
            scene_tab = 0
        }
        SetCursorScreenPos(ImVec2(x + u(8.0) + tw, y + u(6.0)))
        if (bl_radio_button("tab2_screen", "Screen", ICON_SCREEN, tw, BND_CORNER_ALL, scene_tab == 1)) {
            scene_tab = 1
        }
        SetCursorScreenPos(ImVec2(x + u(8.0) + tw * 2.0, y + u(6.0)))
        if (bl_radio_button("tab2_chart", "Chart", ICON_CHART, tw, BND_CORNER_LEFT, scene_tab == 2)) {
            scene_tab = 2
        }
        let ty = y + u(32.0)
        if (scene_tab == 0) {
            self->field_view(x, ty, w, y + h - ty)
        } elif (scene_tab == 1) {
            self->screen_view(x, ty, w, y + h - ty)
        } else {
            let have_units = length(units) > 0
            explore |> explore_chart_view(x + u(8.0), ty, w - u(16.0), y + h - ty - u(6.0), have_units) $(s; var t) {
                return self->explore_points(s, t)
            }
        }
    }

    def field_view(x, y, w, h : float) : void {
        if (length(units) == 0) {
            SetCursorScreenPos(ImVec2(x + u(12.0), y + u(6.0)))
            bl_label(message, ICON_INFO)
            return
        }
        var fu : array<FieldUnit>
        for (un in units) {
            // standing: frame 0 facing +y / +x, 1 facing -x / -y; -y and +x mirrored (as in FFTA)
            let f = field_view_facing(field_map, field, un.facing)
            let spr = rom_sprites2 ? nds_unit_sprite(shell_renderer(), unit_gfx_set(un), 0, f == 0 || f == 3 ? 0 : 1, f >= 2) : -1
            fu |> push(FieldUnit(name = un.name, x = un.x, y = un.y, facing = un.facing, team = un.team, alive = un.hp > 0,
                sprite = spr, sprite_dy = 4.0))
        }
        let bar = u(28.0)
        // the tiles the selected unit reaches with the Attack tab's action
        var reach : array<bool>
        if (length(actions) == 0) {
            self->make_actions()
        }
        if (selected >= 0 && selected < length(units) && length(actions) > 0 && field_map.w > 0) {
            let ab = read_ability2(actions[clamp(action, 0, length(actions) - 1)])
            reach |> resize(field_map.w * field_map.h)
            for (ty in range(field_map.h)) {
                for (tx in range(field_map.w)) {
                    reach[ty * field_map.w + tx] = (field_map.height[ty * field_map.w + tx] > 0 &&
                        in_reach_on(units[selected], ab, map2, tx + field_map.x0, ty + field_map.y0))
                }
            }
        }
        let input = draw_battle_field(field_map, fu, selected, target, reach, field, x + u(8.0), y, w - u(16.0), h - bar)
        if (input.select >= 0) {
            selected = input.select
            if (target == selected) {
                target = -1
            }
        }
        if (input.target >= 0) {
            target = input.target
        }
        if (input.moved >= 0) {
            units[input.moved].x = input.move_x
            units[input.moved].y = input.move_y
            recompute_unit(units[input.moved])
        }
        var tr = input.turn
        let bt_turn = field_bar(field, x + u(8.0), y + h - bar + u(4.0))
        if (bt_turn != 0) {
            tr = bt_turn
        }
        if (tr != 0 && selected >= 0) {
            units[selected].facing = (units[selected].facing + (tr > 0 ? 1 : 3)) & 3
            recompute_unit(units[selected])
        }
    }

    def screen_view(x, y, w, h : float) : void {
        if (!gba_frame_update(shell_renderer())) {
            SetCursorScreenPos(ImVec2(x + u(12.0), y + u(12.0)))
            bl_label(message, ICON_INFO)
            return
        }
        let fw = gba_frame_width()
        let fh = gba_frame_height()
        let k = max(1.0, floor(min((w - u(16.0)) / fw, (h - u(40.0)) / fh)))
        let dx = x + floor((w - fw * k) * 0.5)
        let dy = y + u(8.0)
        gba_frame_draw(dx, dy, fw * k, fh * k)
        SetCursorScreenPos(ImVec2(dx, dy + fh * k + u(4.0)))
        bl_label("Screen stored in the state", ICON_SCREEN)
    }

    // the units with their Unit Info stats, the one with the highest CT first
    def override draw_calc(x, y, w, h : float) : void {
        if (rom_serial != gba_rom_serial()) {
            rom_serial = gba_rom_serial()
            actions |> clear()
        }
        SetCursorScreenPos(ImVec2(x, y))
        if (length(units) == 0) {
            bl_label(message, ICON_TURNS)
            return
        }
        let tw = u(120.0)
        if (bl_radio_button("tab2_turns", "Turn order", ICON_TURNS, tw, BND_CORNER_RIGHT, calc_tab == 0)) {
            calc_tab = 0
        }
        SetCursorScreenPos(ImVec2(x + tw, y))
        if (bl_radio_button("tab2_attack", "Attack", ICON_ATTACK, tw, BND_CORNER_ALL, calc_tab == 1)) {
            calc_tab = 1
        }
        SetCursorScreenPos(ImVec2(x + tw * 2.0, y))
        if (bl_radio_button("tab2_explore", "Explore", ICON_CHART, tw, BND_CORNER_ALL, calc_tab == 2)) {
            calc_tab = 2
        }
        SetCursorScreenPos(ImVec2(x + tw * 3.0, y))
        if (bl_radio_button("tab2_units", "Units", ICON_UNIT, tw, BND_CORNER_LEFT, calc_tab == 3)) {
            calc_tab = 3
        }
        let ty = y + u(28.0)
        if (calc_tab == 1) {
            self->attack_view(x, ty, w, y + h - ty)
        } elif (calc_tab == 2) {
            let att = units[clamp(selected, 0, length(units) - 1)]
            let msg = explore_view(explore, x, ty, w, y + h - ty, state_path, $(key) {
                var v : Value
                return unit_param2(att, key, v)
            }, $(s; var t) {
                return self->explore_points(s, t)
            })
            if (msg != "") {
                message = msg
                log_line(msg)
            }
        } elif (calc_tab == 3) {
            self->unit_table(x, ty, w, y + h - ty)
        } else {
            self->turn_view(x, ty, w, y + h - ty)
        }
    }

    // the scene of the Attack tab, changed by
    // scene Luso vs Sasarr with Fire from back; "" or the error
    def explore_scene(s : Script; var sc : Scene2) : string {
        if (selected < 0 || selected >= length(units)) {
            selected = 0
        }
        self->pick_target()
        if (length(actions) == 0) {
            self->make_actions()
        }
        var att = selected
        var tgt = target >= 0 ? target : selected
        var ability = length(actions) > 0 ? actions[clamp(action, 0, length(actions) - 1)] : ATTACK_ABILITY
        var side = side_choice
        for (a in s.scene) {
            let v = eval_const(a.exprs[0], a.exprs[0].root)
            if (a.name == "attacker" || a.name == "target") {
                var found = -1
                for (i in range(length(units))) {
                    if (units[i].name == v.text) {
                        found = i
                    }
                }
                if (found < 0) {
                    let all = join([for (un in units); un.name], ", ")
                    return "line {a.line}: no unit '{v.text}' ({all})"
                }
                if (a.name == "attacker") {
                    att = found
                } else {
                    tgt = found
                }
            } elif (a.name == "action") {
                ability = -1
                for (aid in actions) {
                    if ((aid == ATTACK_ABILITY ? "Attack" : read_ability2(aid).name) == v.text) {
                        ability = aid
                    }
                }
                if (ability < 0) {
                    return "line {a.line}: no action '{v.text}' (Attack or an ability that damages or heals)"
                }
            } elif (a.name == "side") {
                side = clamp(int(v.num), 0, 3)
            } else {
                return "line {a.line}: scene( ) takes attacker, target, action, side - not '{a.name}'"
            }
        }
        sc = Scene2(att = units[att], tgt = units[tgt], ability = ability, side = side, privilege = privilege)
        sc.map := map2
        return ""
    }

    // Explore: a parsed script -> the table of its points
    def explore_points(var s : Script; var t : ETable) : string {
        var sc = Scene2()
        try_ok(self->explore_scene(s, sc))
        return run_experiment2(sc, s, t)
    }

    // the selected unit attacks the target (right click on the field;
    // until then the nearest unit of another team)
    def pick_target() : void {
        if (target >= 0 && target < length(units) && target != selected) {
            return
        }
        target = -1
        var best = 1000
        for (i in range(length(units))) {
            if (selected >= 0 && i != selected && units[i].team != units[selected].team) {
                let d = abs(units[i].x - units[selected].x) + abs(units[i].y - units[selected].y)
                if (d < best) {
                    best = d
                    target = i
                }
            }
        }
    }

    // Fight: the forecast and how it is made (ffta2_attack.das)
    def attack_view(x, y, w, h : float) : void {
        self->pick_target()
        if (selected < 0 || target < 0) {
            SetCursorScreenPos(ImVec2(x, y))
            bl_label("Select an attacker and right-click a target on the field", ICON_INFO)
            return
        }
        let att = units[selected]
        let tgt = units[target]
        let auto_side = side_of2(att, tgt)
        let side = side_choice == 1 ? Side2.Front : (side_choice == 2 ? Side2.Side : (side_choice == 3 ? Side2.Back : auto_side))
        if (length(actions) == 0) {
            self->make_actions()
        }
        let ab = read_ability2(actions[clamp(action, 0, length(actions) - 1)])
        var f <- action2(att, tgt, ab, side, privilege)
        // the forecast by the game's own scripts (the VM); the translated
        // formula above explains it and is checked against it
        let vt = side_choice == 0 ? tgt : face_for_side(att, tgt, side)
        let v = vm_forecast(att, vt, ab, privilege)
        var vm_note = ""
        if (v.ok) {
            if (!f.unsupported && (f.hit != v.hit || f.damage != v.amount) && !v.no_effect) {
                vm_note = "the step-by-step formula gives {f.damage} / {f.hit}%; the game's scripts win"
            }
            f.hit = v.hit
            f.damage = v.amount
            f.healing = v.healing
            f.unsupported = false
            fill_real(f, att, privilege)
        } else {
            vm_note = "the game's scripts could not run: {v.problem}"
        }
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        // the action: a name filter, then the matching actions
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("{att.name} -> {tgt.name}:", ICON_ATTACK)
        let lx = x + text_width("{att.name} -> {tgt.name}:") + u(30.0)
        SetCursorScreenPos(ImVec2(lx, y))
        bl_string("action2_filter", action_filter, u(110.0))
        var names : array<string>
        var ids : array<int>
        var cur = 0
        let flt = to_lower(action_filter)
        for (k in range(length(actions))) {
            let name = action_names[k]
            if (k == action || ((flt == "" || find(to_lower(name), flt) >= 0) && (!known_only || unit_knows(att, actions[k])))) {
                if (k == action) {
                    cur = length(names)
                }
                names |> push(name)
                ids |> push(k)
            }
        }
        SetCursorScreenPos(ImVec2(lx + u(114.0), y))
        if (bl_choice("action2_choice", names, cur, u(200.0))) {
            action = ids[cur]
        }
        SetCursorScreenPos(ImVec2(lx + u(320.0), y))
        bl_option("action2_known", "Learned only", known_only)
        // second row: the side and the clan privilege
        let ry2 = y + u(26.0)
        SetCursorScreenPos(ImVec2(x + u(22.0), ry2))
        bl_label("Side:")
        SetCursorScreenPos(ImVec2(x + u(70.0), ry2))
        var sides <- ["Auto ({SIDE2_NAMES[int(auto_side)]})", "Front", "Side", "Back"]
        bl_choice("side2_choice", sides, side_choice, u(156.0))
        SetCursorScreenPos(ImVec2(x + u(234.0), ry2))
        bl_label("Privilege:")
        SetCursorScreenPos(ImVec2(x + u(310.0), ry2))
        var pv = float(privilege)
        if (bl_number("privilege2", "", pv, 1.0, 0, u(120.0))) {
            privilege = clamp(int(round(pv)), 0, 99)
        }
        var ry = y + u(54.0)
        let col = x + u(150.0)
        let what = f.healing ? "healing" : "damage"
        // every effect that applies: "Sleep 60%", ...
        var others : array<string>
        for (e in v.effects) {
            if (e.index != v.effect) {
                let amount = e.amount != 0 ? " {e.amount}" : ""
                others |> push(e.problem != "" ? "{effect_text(e.apply)} (not computed: {e.problem})" : "{effect_text(e.apply)}{amount} {e.hit}%{e.after_hit ? " if it hits" : ""}")
            }
        }
        let status_only = v.ok && v.effect < 0 && length(others) > 0
        var big = v.ok && v.no_effect ? "No effect on {tgt.name}   ({ab.name})" : (f.unsupported ? "Not computed: {v.problem}" : "Forecast: {f.damage} {what}, {f.hit}% hit   ({ab.name}{magick_text(ab)})")
        if (status_only) {
            big = "Forecast: {join(others, ", ")}   ({ab.name}{magick_text(ab)})"
        }
        text_at_baseline(x + u(8.0), ry + u(15.0), big, fg)
        ry += u(21.0)
        if (status_only) {
            text_at_baseline(x + u(8.0), ry + u(15.0),
                "Hit: the target job's status base +- statuses (1..99); 100 on a helpless target, 0 where it can not land", dim)
            ry += u(21.0)
            return
        }
        if (length(others) > 0) {
            text_at_baseline(x + u(8.0), ry + u(15.0), "Also: {join(others, ", ")}", fg)
            ry += u(21.0)
        }
        let crit = f.crit_prob > 0.0 ? ", critical {fmt(":.2f", f.crit_prob * 100.0)}% (x2)" : ""
        let real = "Real: hit {fmt(":.1f", f.hit_prob * 100.0)}%{crit}, {what} {f.dmg_min}..{f.dmg_max}, ~{fmt(":.1f", f.expected)} per use"
        text_at_baseline(x + u(8.0), ry + u(15.0), real, fg)
        ry += u(21.0)
        if (vm_note != "") {
            text_at_baseline(x + u(8.0), ry + u(15.0), vm_note, 0xe0a060ffu)
            ry += u(21.0)
        }
        if (battle_rng != 0u && tgt.rng_seed != 0u) {
            let r = roll_attack(f, battle_rng, tgt.rng_seed)
            let next = r.hit ? "{r.damage} {what}{r.crit ? " (critical)" : ""}" : "miss"
            text_at_baseline(x + u(8.0), ry + u(15.0),
                "Next roll from the save's generators: {next} (if {att.name} acts before anything else rolls)", dim)
            ry += u(21.0)
        }
        ry += u(7.0)
        var rows : array<tuple<string; string>>
        let ws = weapon_slot2(att)
        let power = f.weapon == ab.name ? "{ab.name} power {ab.power}" : (ws >= 0 ? "{f.weapon} {att.equip[ws].bonus[0]}" : "bare hands {att.bare_power} (job)")
        let mg = is_magick2(ab)
        rows |> push((mg ? "Magick x10" : "Attack x10", "{f.atk10} (raw {att.raw[mg ? 2 : 0]})"))
        rows |> push(("Power x10", "{f.power10} ({power} + {mg ? "Magick" : "Attack"} of {mg ? "the" : "other"} items)"))
        rows |> push((mg ? "Resistance x10" : "Defense x10", "{f.def10} (raw {tgt.raw[mg ? 3 : 1]}), its equipment x10 {f.armor10}"))
        rows |> push(("Base", "{f.base} = {f.atk10} x 25/100 + {f.power10} - ({f.def10} x 25/100 + {f.armor10}) / 2"))
        rows |> push(("Scaled", "{f.scaled} = base x (100 + privilege {f.privilege}) / 100 / 10 / 2"))
        let side_k = f.side == Side2.Back ? "x2" : (f.side == Side2.Side ? "x1.5" : "x1")
        rows |> push(("Side", f.by_side ? "{SIDE2_NAMES[int(f.side)]} {side_k} -> {f.after_side}" : "not by side: x1.5 -> {f.after_side}"))
        let aff = f.affinity >= 0 && f.affinity < 5 ? AFFINITY_NAMES[f.affinity] : "{f.affinity}"
        rows |> push(("Element", "{ELEMENT2_NAMES[f.element]}: target {aff} -> {f.damage} (1..999)"))
        if (length(f.mods) > 0) {
            rows |> push(("Modifiers", join(f.mods, ", ")))
        }
        let hit_mods = length(f.hit_mods) > 0 ? ", {join(f.hit_mods, ", ")}" : ""
        rows |> push(("Hit", "{tgt.job_hit} (job) - Evasion {f.evasion}{hit_mods} = {f.hit}% (1..99)"))
        let rr = reach_range(att, ab)
        let dist = abs(att.x - tgt.x) + abs(att.y - tgt.y)
        let reach_text = in_reach_on(att, ab, map2, tgt.x, tgt.y) ? "in reach" : "OUT OF REACH"
        let dh = map2.w > 0 ? ", height {map_height(map2, tgt.x, tgt.y) - map_height(map2, att.x, att.y)}" : ""
        rows |> push(("Reach", "{dist} tiles{dh}: {reach_text} ({rr.x}..{rr.y})"))
        // the target's reaction (0x020636DC) and its counter-attack
        let re <- reaction2(att, tgt, ab, map2, privilege)
        if (re.id != 0) {
            let when = re.why != "" ? " ({re.why})" : ""
            rows |> push(("Reaction", re.triggers ? "{re.name}: {re.effect}{when}" : "{re.name}: does not trigger{when}"))
            if (re.counter) {
                let cf & = unsafe(re.counter_fight)
                rows |> push(("Counter", "{tgt.name} -> {att.name}: {cf.damage} damage, {cf.hit}% hit, {cf.dmg_min}..{cf.dmg_max}, ~{fmt(":.1f", cf.expected)}"))
            }
        } else {
            rows |> push(("Reaction", "none"))
        }
        for (r in rows) {
            text_at_baseline(x + u(8.0), ry + u(15.0), r._0, dim)
            text_at_baseline(col, ry + u(15.0), r._1, fg)
            ry += u(21.0)
        }
    }

    // Attack and every ability with a damage or healing effect (the VM
    // computes them; the step-by-step formula covers most)
    def make_actions() : void {
        actions |> clear()
        action_names |> clear()
        actions |> push(ATTACK_ABILITY)
        action_names |> push("Attack")
        for (aid in range(1, ability_count())) {
            let ab = read_ability2(aid)
            if (aid != ATTACK_ABILITY && (damages_or_heals(ab) || inflicts_status(ab))) {
                actions |> push(aid)
                action_names |> push(ab.name)
            }
        }
        // --action <name>: the action to start with (screenshots, checks)
        let want = gui_arg("--action", "")
        for (k in range(length(action_names))) {
            if (want != "" && action_names[k] == want) {
                action = k
            }
        }
    }

    // the next turns (ffta2_turns.das): each unit ends its turns as its
    // Assumed turn (Inspector)
    def turn_view(x, y, w, h : float) : void {
        let turns <- predict_turns2(units, turns_ahead, privilege)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let nw = u(180.0)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Turn order  (CT 100+ acts; a tick adds Speed; a turn: 50, +30 moved, +20 acted)", ICON_TURNS,
            w - nw - u(8.0))
        SetCursorScreenPos(ImVec2(x + w - nw - u(4.0), y))
        var ahead = float(turns_ahead)
        if (bl_number("turns2_ahead", "Turns ahead", ahead, 0.1, 0, nw)) {
            turns_ahead = clamp(int(round(ahead)), 1, 200)
        }
        let row_h = u(21.0)
        let cols = fixed_array<float>(12.0, 44.0, 150.0, 260.0, 330.0, 390.0)
        let heads = fixed_array<string>("#", "Unit", "Job", "In ticks", "Turn", "CT", "Ends with")
        var ry = y + u(26.0)
        for (k in range(6)) {
            text_at_baseline(x + u(cols[k]), ry + u(14.0), heads[k], dim)
        }
        text_at_baseline(x + u(450.0), ry + u(14.0), heads[6], dim)
        ry += row_h
        SetCursorScreenPos(ImVec2(x, ry))
        BeginChild("ffta2_turns", ImVec2(w, y + h - ry), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        var dl = GetWindowDrawList()
        var yy = GetCursorScreenPos().y
        let names = fixed_array<string>("Move + Act", "Act", "Move", "Wait")
        for (k in range(length(turns))) {
            let t = turns[k]
            let un = units[t.unit]
            SetCursorScreenPos(ImVec2(x, yy))
            if (InvisibleButton("##turn2_{k}", ImVec2(w - u(4.0), row_h))) {
                selected = t.unit
            }
            if (t.unit == selected) {
                *dl |> AddRectFilled(ImVec2(x, yy), ImVec2(x + w - u(4.0), yy + row_h), abgr(bt.menu_item.inner_sel), 0.0,
                    ImDrawFlags.None)
            }
            *dl |> AddRectFilled(ImVec2(x + u(2.0), yy + u(3.0)), ImVec2(x + u(6.0), yy + row_h - u(3.0)),
                abgr(side_color(un.team)), u(2.0), ImDrawFlags.None)
            let b = yy + u(15.0)
            text_at_baseline(x + u(cols[0]), b, "{k + 1}", dim)
            text_at_baseline(x + u(cols[1]), b, un.name, team_text_color(un.team))
            text_at_baseline(x + u(cols[2]), b, un.job, fg)
            text_at_baseline(x + u(cols[3]), b, t.tick == 0 ? "now" : "+{t.tick}", fg)
            text_at_baseline(x + u(cols[4]), b, "{t.nth}", fg)
            text_at_baseline(x + u(cols[5]), b, "{t.ct}", fg)
            text_at_baseline(x + u(450.0), b, names[int(un.assumed)], dim)
            yy += row_h
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }

    def unit_table(x, y, w, h : float) : void {
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Units  (by CT: the next to act first)", ICON_TURNS)
        var order : array<int>
        for (i in range(length(units))) {
            order |> push(i)
        }
        sort(order) $(a, b) => units[a].ct > units[b].ct || (units[a].ct == units[b].ct && a < b)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let row_h = u(21.0)
        var cols : array<float>
        let names = fixed_array<string>("Unit", "Job", "Lv", "HP", "MP", "CT", "Atk", "Def", "Mag", "Res", "Spd", "Eva",
            "Move", "Jump")
        let widths = fixed_array<float>(86.0, 94.0, 28.0, 62.0, 48.0, 38.0, 32.0, 32.0, 32.0, 32.0, 32.0, 32.0, 40.0, 38.0)
        var cx = x + u(12.0)
        for (k in range(length(widths))) {
            cols |> push(cx)
            cx += u(widths[k])
        }
        var ry = y + u(26.0)
        for (k in range(length(names))) {
            text_at_baseline(cols[k], ry + u(14.0), names[k], dim)
        }
        ry += row_h
        SetCursorScreenPos(ImVec2(x, ry))
        BeginChild("ffta2_units", ImVec2(w, y + h - ry), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        var dl = GetWindowDrawList()
        var yy = GetCursorScreenPos().y
        for (i in order) {
            let un = units[i]
            SetCursorScreenPos(ImVec2(x, yy))
            if (InvisibleButton("##row2_{i}", ImVec2(w - u(4.0), row_h))) {
                selected = i
            }
            if (i == selected) {
                *dl |> AddRectFilled(ImVec2(x, yy), ImVec2(x + w - u(4.0), yy + row_h), abgr(bt.menu_item.inner_sel), 0.0,
                    ImDrawFlags.None)
            }
            *dl |> AddRectFilled(ImVec2(x + u(2.0), yy + u(3.0)), ImVec2(x + u(6.0), yy + row_h - u(3.0)),
                abgr(side_color(un.team)), u(2.0), ImDrawFlags.None)
            let b = yy + u(15.0)
            let cells <- [un.name, un.job, "{un.level}", "{un.hp}/{un.max_hp}", "{un.mp}/{un.max_mp}", "{un.ct}"]
            for (k in range(length(cells))) {
                text_at_baseline(cols[k], b, cells[k], k == 0 ? team_text_color(un.team) : fg)
            }
            for (s in range(STAT2_COUNT)) {
                text_at_baseline(cols[6 + s], b, "{un.stat_total[s]}", fg)
            }
            yy += row_h
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }
}

// any field of the unit differs from the loaded one
def private inspect_changed(a, b : Unit2) : bool {
    return (a.hp != b.hp || a.max_hp != b.max_hp || a.mp != b.mp || a.max_mp != b.max_mp || a.ct != b.ct ||
        a.x != b.x || a.y != b.y || a.facing != b.facing || a.job_id != b.job_id || a.support != b.support ||
        a.reaction != b.reaction || a.base_speed != b.base_speed || "{a.raw}" != "{b.raw}" || "{a.items} {a.status}" != "{b.items} {b.status}" ||
        "{a.learned}" != "{b.learned}")
}
