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
require ../../app/shell.das
require ffta2_battle
require ffta2_attack

let private STAT2_SHORT = fixed_array<string>("Atk", "Def", "Mag", "Res", "Spd", "Eva", "Move", "Jump")

def private signed2(v : int) : string {
    return v > 0 ? "+{v}" : "{v}"
}

def private bonus2_text(it : Item2) : string {
    let parts <- [for (i in range(STAT2_COUNT)); "{STAT2_SHORT[i]} {signed2(it.bonus[i])}"; where it.bonus[i] != 0]
    return length(parts) > 0 ? join(parts, "  ") : "no stat bonus"
}

def private right2(x, baseline : float; s : string; color : uint) {
    text_at_baseline(x - text_width(s), baseline, s, color)
}

class Ffta2Game : GameModule {
    units : array<Unit2>
    saved : array<Unit2>              // as read from the state: Revert
    selected : int = -1
    target : int = -1
    field = FieldState()
    field_map : FieldMap
    scene_tab : int = 0               // 0 field, 1 the game screen
    calc_tab : int = 0                // 0 units, 1 attack
    side_choice : int = 0             // 0 auto, 1 + Side2
    privilege : int = 0               // the clan privilege (game variable 369), 0 none
    stats_open : bool = true
    equip_open : bool = true
    state_path : string
    rom_path : string
    loaded_state : string
    loaded_rom : string
    no_export : string                // the roster's export field (not used: NDS states are not written)
    from_args : bool
    message : string = "Load a BizHawk state (melonDS core) and the FFTA2 (USA) ROM"

    def Ffta2Game {
        state_path = config_get("ffta2_state")
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
        log_line("loaded {state_path}: {message}")
        if (remember) {
            config_set("ffta2_state", state_path)
            config_set("ffta2_rom", rom_path)
        }
    }

    // the map's heights are not read yet: a flat field around the units
    def make_map() : void {
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
        var ry = source_fields(state_path, rom_path, no_export, false, x, y, w, pressed)
        if (pressed == ROSTER_LOAD) {
            self->load()
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
        var bottom = inspect("unit2_{selected}", units[selected], saved[selected], x, by, w)
        bottom = self->stat_rows(units[selected], x, bottom + u(6.0), w)
        bottom = self->equip_rows(units[selected], x, bottom + u(6.0), w)
        var names : array<string>
        for (n in range(1, 72)) {
            if (has_status2(units[selected], n)) {
                names |> push(status_name(n))
            }
        }
        SetCursorScreenPos(ImVec2(x, bottom + u(6.0)))
        bl_label("Status: {length(names) > 0 ? join(names, ", ") : "none"}")
        return bottom + u(30.0)
    }

    // Unit Info stats: base (raw / 4, Speed, job Move / Jump) + equipment
    def stat_rows(un : Unit2; x, y, w : float) : float {
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
            right2(c_base, b, "{un.stat_base[i]}", fg)
            let items = un.stat_items[i]
            if (items != 0) {
                right2(c_items, b, signed2(items), items > 0 ? 0x70c070ffu : 0xe07070ffu)
            }
            right2(c_total, b, "{un.stat_total[i]}", fg)
            ry += u(21.0)
        }
        return ry
    }

    def equip_rows(un : Unit2; x, y, w : float) : float {
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("equip2_section", "Equipment", equip_open)) {
            return ry
        }
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        for (slot in range(EQUIP_SLOTS)) {
            let it = un.equip[slot]
            if (it.id == 0) {
                continue
            }
            text_at_baseline(x + u(8.0), ry + u(15.0), it.name, fg)
            ry += u(20.0)
            text_at_baseline(x + u(16.0), ry + u(13.0), bonus2_text(it), dim)
            ry += u(19.0)
        }
        if (ry == y + u(23.0)) {
            text_at_baseline(x + u(8.0), ry + u(15.0), "(none)", dim)
            ry += u(20.0)
        }
        return ry
    }

    def override draw_scene(x, y, w, h : float) : void {
        let tw = u(120.0)
        SetCursorScreenPos(ImVec2(x + u(8.0), y + u(6.0)))
        if (bl_radio_button("tab2_field", "Field", ICON_FIELD, tw, BND_CORNER_RIGHT, scene_tab == 0)) {
            scene_tab = 0
        }
        SetCursorScreenPos(ImVec2(x + u(8.0) + tw, y + u(6.0)))
        if (bl_radio_button("tab2_screen", "Screen", ICON_SCREEN, tw, BND_CORNER_LEFT, scene_tab == 1)) {
            scene_tab = 1
        }
        let ty = y + u(32.0)
        if (scene_tab == 0) {
            self->field_view(x, ty, w, y + h - ty)
        } else {
            self->screen_view(x, ty, w, y + h - ty)
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
            fu |> push(FieldUnit(name = un.name, x = un.x, y = un.y, facing = un.facing, team = un.team, alive = un.hp > 0))
        }
        let bar = u(28.0)
        var reach : array<bool>
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
        SetCursorScreenPos(ImVec2(x, y))
        if (length(units) == 0) {
            bl_label(message, ICON_TURNS)
            return
        }
        let tw = u(120.0)
        if (bl_radio_button("tab2_units", "Units", ICON_TURNS, tw, BND_CORNER_RIGHT, calc_tab == 0)) {
            calc_tab = 0
        }
        SetCursorScreenPos(ImVec2(x + tw, y))
        if (bl_radio_button("tab2_attack", "Attack", ICON_ATTACK, tw, BND_CORNER_LEFT, calc_tab == 1)) {
            calc_tab = 1
        }
        let ty = y + u(28.0)
        if (calc_tab == 1) {
            self->attack_view(x, ty, w, y + h - ty)
        } else {
            self->unit_table(x, ty, w, y + h - ty)
        }
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
        let f <- fight2(att, tgt, side, privilege)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("{att.name} -> {tgt.name}: Attack with {f.weapon}", ICON_ATTACK)
        SetCursorScreenPos(ImVec2(x + w - u(250.0), y))
        bl_label("Side:", -1, u(50.0))
        SetCursorScreenPos(ImVec2(x + w - u(200.0), y))
        var sides <- ["Auto ({SIDE2_NAMES[int(auto_side)]})", "Front", "Side", "Back"]
        bl_choice("side2_choice", sides, side_choice, u(200.0))
        SetCursorScreenPos(ImVec2(x + w - u(250.0), y + u(26.0)))
        bl_label("Privilege:", -1, u(80.0))
        SetCursorScreenPos(ImVec2(x + w - u(170.0), y + u(26.0)))
        var pv = float(privilege)
        if (bl_number("privilege2", "", pv, 1.0, 0, u(170.0))) {
            privilege = clamp(int(round(pv)), 0, 99)
        }
        var ry = y + u(30.0)
        let col = x + u(150.0)
        let big = "{f.damage} damage   {f.hit}% hit   ~{fmt(":.1f", float(f.damage) * float(f.hit) / 100.0)} expected"
        text_at_baseline(x + u(8.0), ry + u(15.0), big, fg)
        ry += u(28.0)
        var rows : array<tuple<string; string>>
        let ws = weapon_slot2(att)
        let power = ws >= 0 ? "{f.weapon} {att.equip[ws].bonus[0]}" : "bare hands {att.bare_power} (job)"
        rows |> push(("Attack x10", "{f.atk10} (raw {att.raw[0]})"))
        rows |> push(("Weapon x10", "{f.power10} ({power} + Attack of other items)"))
        rows |> push(("Defense x10", "{f.def10} (raw {tgt.raw[1]}), armour x10 {f.armor10}"))
        rows |> push(("Base", "{f.base} = {f.atk10} x 25/100 + {f.power10} - ({f.def10} x 25/100 + {f.armor10}) / 2"))
        rows |> push(("Scaled", "{f.scaled} = base x (100 + privilege {f.privilege}) / 100 / 10 / 2"))
        let side_k = f.side == Side2.Back ? "x2" : (f.side == Side2.Side ? "x1.5" : "x1")
        rows |> push(("Side", "{SIDE2_NAMES[int(f.side)]} {side_k} -> {f.after_side}"))
        let aff = f.affinity >= 0 && f.affinity < 5 ? AFFINITY_NAMES[f.affinity] : "{f.affinity}"
        rows |> push(("Element", "{ELEMENT2_NAMES[f.element]}: target {aff} -> {f.damage} (1..999)"))
        if (length(f.mods) > 0) {
            rows |> push(("Modifiers", join(f.mods, ", ")))
        }
        let hit_mods = length(f.hit_mods) > 0 ? ", {join(f.hit_mods, ", ")}" : ""
        rows |> push(("Hit", "{tgt.job_hit} (job) - Evasion {f.evasion}{hit_mods} = {f.hit}% (1..99)"))
        rows |> push(("Distance", "{abs(att.x - tgt.x) + abs(att.y - tgt.y)} tiles (reach is not checked yet)"))
        for (r in rows) {
            text_at_baseline(x + u(8.0), ry + u(15.0), r._0, dim)
            text_at_baseline(col, ry + u(15.0), r._1, fg)
            ry += u(21.0)
        }
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
        a.x != b.x || a.y != b.y || a.facing != b.facing)
}
