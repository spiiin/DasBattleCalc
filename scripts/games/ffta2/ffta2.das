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

def private right2(x, baseline : float; s : string; color : uint) {
    text_at_baseline(x - text_width(s), baseline, s, color)
}

def private magick_text(ab : Ability2) : string {
    return ab.id == ATTACK_ABILITY ? "" : (is_magick2(ab) ? ", magick" : ", physical")
}

// Explore editor colors: what a word of the script is
def private explore2_color(sp : HlSpan; defs : array<string>; att : Unit2) : uint {
    if (sp.kind == HL_STMT) {
        return 0xf0c040ffu              // vary where sort plot scene
    } elif (sp.kind == HL_WORD) {
        return 0x80b8f0ffu              // by per step log bar ...
    } elif (sp.kind == HL_NUM) {
        return 0xf0a060ffu
    } elif (sp.kind == HL_STR) {
        return 0xb0e090ffu
    } elif (sp.kind == HL_COMMENT) {
        return 0x8c8c8cffu
    } elif (sp.kind == HL_FUNC) {
        return 0xc8a0f0ffu
    } elif (sp.kind == HL_OP) {
        return 0xc8c8c8ffu
    } elif (sp.kind == HL_DEF) {
        return 0xf0e0a0ffu              // a new column
    } elif (sp.kind != HL_NAME) {
        return 0xdcdcdcffu
    }
    let name = sp.text
    if (find_index(EXPLORE2_GENERATORS, name) >= 0) {
        return 0xc8a0f0ffu
    }
    if (find_index(METRICS2, name) >= 0) {
        return 0x60d0d0ffu              // a column of every point
    }
    if (find_index(defs, name) >= 0) {
        return 0xf0e0a0ffu
    }
    if (name == "side" || name == "action" || name == "privilege") {
        return 0x90d070ffu
    }
    let dot = find(name, ".")
    if (dot > 0) {
        let owner = slice(name, 0, dot)
        var v : Value
        if ((owner == "atk" || owner == "tgt" || owner == "attacker" || owner == "target") &&
                unit_param2(att, slice(name, dot + 1), v)) {
            return 0x90d070ffu          // a parameter
        }
    }
    return 0xff7070ffu                  // nothing by this name: a typo?
}

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
    state_path : string
    rom_path : string
    loaded_state : string
    loaded_rom : string
    no_export : string                // the roster's export field (not used: NDS states are not written)
    from_args : bool
    message : string = "Load a BizHawk state (melonDS core) and the FFTA2 (USA) ROM"
    // Explore: the script, its table and chart
    explore_src : ImGuiInputTextBuffer = ImGuiInputTextBuffer(EXPLORE2_EXAMPLES[0], 8192)
    explore_example : int = 0
    explore_table : ETable = ETable()
    explore_chart : Chart = Chart()
    explore_error : string
    explore_info : string
    explore_version : int = 0
    explore_ran : bool = false
    explore_tview : TableView = TableView()
    explore_split : float = 0.42      // the editor's share of the width (the bar drags it)

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

    // the battle map (heights shown as the game shows them); a flat field
    // around the units when the state has none
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
            self->chart_view(x + u(8.0), ty, w - u(16.0), y + h - ty - u(6.0))
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
                        in_reach(units[selected], ab, tx + field_map.x0, ty + field_map.y0))
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
            self->explore_view(x, ty, w, y + h - ty)
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
        return ""
    }

    def explore_run() : void {
        explore_ran = true
        let t0 = ref_time_ticks()
        var s = Script()
        var sc = Scene2()
        var err = parse_script(to_string(explore_src), s)
        if (err == "") {
            err = self->explore_scene(s, sc)
        }
        if (err == "") {
            err = run_experiment2(sc, s, explore_table)
        }
        if (err == "") {
            let xn = length(explore_table.names) > 0 ? explore_table.names[0] : "damage"
            err = build_chart(s, explore_table, xn, "damage", explore_chart)
        }
        if (err != "") {
            explore_table = ETable()
            explore_chart = Chart()
        }
        explore_error = err
        explore_version++
        let ms = get_time_usec(t0) / 1000
        explore_info = err == "" ? "{length(explore_table.rows)} rows x {length(explore_table.names)} columns, {ms} ms" : ""
    }

    // Calculation > Explore: examples, Run; the script; the table
    def explore_view(x, y, w, h : float) : void {
        if (!explore_ran) {
            self->explore_run()
        }
        let ew = floor(w * explore_split)
        // the bar between the editor and the table: drag to resize
        SetCursorScreenPos(ImVec2(x + ew + u(1.0), y + u(26.0)))
        InvisibleButton("##explore2_split", ImVec2(u(6.0), max(u(10.0), h - u(26.0))))
        if (IsItemHovered() || IsItemActive()) {
            SetMouseCursor(ImGuiMouseCursor.ResizeEW)
            *GetWindowDrawList() |> AddRectFilled(ImVec2(x + ew + u(3.0), y + u(26.0)), ImVec2(x + ew + u(5.0), y + h),
                abgr(bt.menu_item.inner_sel), 0.0, ImDrawFlags.None)
        }
        if (IsItemActive()) {
            explore_split = clamp((GetMousePos().x - x - u(4.0)) / w, 0.15, 0.85)
        }
        SetCursorScreenPos(ImVec2(x, y))
        var pick = explore_example
        var names <- [for (n in EXPLORE2_NAMES); n]
        if (bl_choice("explore2_example", names, pick, ew - u(88.0))) {
            explore_example = pick
            explore_src = ImGuiInputTextBuffer(EXPLORE2_EXAMPLES[pick], 8192)
            self->explore_run()
        }
        SetCursorScreenPos(ImVec2(x + ew - u(80.0), y))
        let run_click = bl_tool_button("explore2_run", "Run", ICON_CHART, u(80.0))
        let eh = h - u(26.0) - (explore_error != "" ? u(22.0) : 0.0)
        SetCursorScreenPos(ImVec2(x, y + u(26.0)))
        // the columns the script makes (name = ...), the line of the error
        var defs : array<string>
        for (line in split(to_string(explore_src), "\n")) {
            var spans : array<HlSpan>
            highlight_line(line, spans)
            if (length(spans) > 0 && spans[0].kind == HL_DEF) {
                defs |> push(spans[0].text)
            }
        }
        var error_line = 0
        if (starts_with(explore_error, "line ")) {
            error_line = to_int(slice(explore_error, 5, max(5, find(explore_error, ":"))))
        }
        let att = units[clamp(selected, 0, length(units) - 1)]
        bl_code_area("explore2_src", explore_src, ew, max(u(40.0), eh), error_line) $(line; var out) {
            var spans : array<HlSpan>
            highlight_line(line, spans)
            for (sp in spans) {
                out |> push(CodeSpan(start = sp.start, stop = sp.stop, color = explore2_color(sp, defs, att)))
            }
        }
        let editing = IsItemActive()
        // Ctrl+Enter in the editor runs it too
        if (run_click || (editing && GetIO().KeyCtrl && IsKeyPressed(ImGuiKey.Enter, false))) {
            self->explore_run()
        }
        if (explore_error != "") {
            SetCursorScreenPos(ImVec2(x, y + h - u(21.0)))
            bl_label(explore_error, ICON_INFO, ew, 0xff8080ffu)
            if (IsItemHovered()) {
                bl_tooltip(explore_error)
            }
        }
        let tx = x + ew + u(8.0)
        let tw = w - ew - u(8.0)
        let cw = u(70.0)
        SetCursorScreenPos(ImVec2(tx, y))
        bl_label(explore_info != "" ? "{explore_info}; chart: Battle > Chart" : "", ICON_INFO, tw - cw - u(4.0))
        SetCursorScreenPos(ImVec2(tx + tw - cw, y))
        if (bl_tool_button("explore2_csv", "CSV", ICON_EXPORT, cw) && length(explore_table.names) > 0) {
            self->explore_csv()
        }
        draw_etable("explore2_table", explore_table, explore_version, explore_tview, tx, y + u(26.0), tw, h - u(26.0))
    }

    // the table as CSV in the order it is shown, next to the state: on the
    // desktop a file, in the browser a download (gui_save_text)
    def explore_csv() : void {
        let dot = find(state_path, ".", max(0, length(state_path) - 6))
        let base = dot >= 0 ? slice(state_path, 0, dot) : state_path
        let path = "{base}.explore.csv"
        let err = gui_save_text(path, table_csv(explore_table, explore_tview.order))
        message = err != "" ? "CSV: {err}" : "table saved to {path}"
        log_line(message)
    }

    // Battle > Chart: the chart of the last Explore run
    def chart_view(x, y, w, h : float) : void {
        if (!explore_ran && length(units) > 0) {
            self->explore_run()
        }
        if (explore_error != "") {
            SetCursorScreenPos(ImVec2(x + u(4.0), y + u(6.0)))
            bl_label("Explore: {explore_error}", ICON_INFO)
            return
        }
        if (length(explore_chart.series) == 0) {
            SetCursorScreenPos(ImVec2(x + u(4.0), y + u(6.0)))
            bl_label("No data: write an experiment in Calculation > Explore", ICON_INFO)
            return
        }
        draw_chart("explore2_chart", explore_chart, x, y, w, h)
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
            if (k == action || flt == "" || find(to_lower(name), flt) >= 0) {
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
        let big = v.ok && v.no_effect ? "No effect on {tgt.name}   ({ab.name})" : (f.unsupported ? "Not computed: {v.problem}" : "Forecast: {f.damage} {what}, {f.hit}% hit   ({ab.name}{magick_text(ab)})")
        text_at_baseline(x + u(8.0), ry + u(15.0), big, fg)
        ry += u(21.0)
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
        let reach_text = in_reach(att, ab, tgt.x, tgt.y) ? "in reach" : "OUT OF REACH"
        rows |> push(("Reach", "{dist} tiles: {reach_text} ({rr.x}..{rr.y}; heights not checked yet)"))
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
            if (aid != ATTACK_ABILITY && damages_or_heals(ab)) {
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
        let turns <- predict_turns2(units, 24, privilege)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Turn order  (CT 100+ acts; a tick adds Speed; a turn: 50, +30 moved, +20 acted)", ICON_TURNS)
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
        a.x != b.x || a.y != b.y || a.facing != b.facing)
}
