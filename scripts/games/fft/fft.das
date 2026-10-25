options gen2
options indenting = 4

// Final Fantasy Tactics (PSX, USA) - the game module: the units of a
// BizHawk Nymashock state (fft_battle.das), the map's heights, the turn
// order by CT (fft_turns.das), Attack (fft_attack.das). The state's RAM
// holds the units, the terrain and the battle text; the disc (the ROM
// field: .cue or .bin, optional) gives the graphics - the units' sprites,
// the items' icons, the map's textured mesh (fft_map.das).
module fft shared public

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
require fft_battle
require fft_turns
require fft_attack
require fft_map
require fft_reach
require fft_abilities
require fft_reactions

def private turn_end_text(how : TurnEnd) : string {
    return how == TurnEnd.MoveAndAct ? "Move + Act" : (how == TurnEnd.ActOnly ? "Act" : (how == TurnEnd.MoveOnly ? "Move" : "Wait"))
}

class FftGame : GameModule {
    units : array<FftUnit>
    saved : array<FftUnit>            // as read from the state: Revert
    selected : int = -1
    field = FieldState()
    field_map : FieldMap
    map : FftMap
    scene_tab : int = 0               // 0 field, 1 the game screen
    calc_tab : int = 0                // 0 turn order, 1 units, 2 attack
    attack_target : int = -1
    action_sel : int = 0              // the Attack tab's action: 0 Attack, k the unit's k-th ability
    action_unit : int = -1            // whose abilities action_sel picks from
    all_abilities : bool = false      // also the abilities not learned
    turns_ahead : int = 24
    state_path : string
    rom_path : string                 // the disc (.cue / .bin): the graphics
    export_path : string
    disc_path : string                // the disc opened
    disc_serial : uint                // psx_disc_serial() when we opened it
    from_args : bool
    equip_open : bool = true
    message : string = "Load a BizHawk state (Nymashock core) of Final Fantasy Tactics (USA)"

    def FftGame {
        state_path = config_get("fft_state")
        rom_path = config_get("fft_rom")
        if (gui_arg("--game", "") == "fft") {
            from_args = gui_arg("--state", "") != ""
            state_path = gui_arg("--state", state_path)
            rom_path = gui_arg("--rom", rom_path)
        }
    }

    def override id() : string {
        return "fft"
    }

    def override title() : string {
        return "Final Fantasy Tactics"
    }

    def override status() : string {
        return "FFT: {message}"
    }

    def override accepts_rom(code : string) : bool {
        return code == FFT_CODE
    }

    def override reload() : void {
        state_path = gui_arg("--state", state_path)
        self->load(false)
    }

    def override activate() : void {
        if (length(units) == 0) {
            if (stat(state_path).is_valid) {
                self->load(!from_args)
            }
            return
        }
        if (!gba_state_is_psx()) {
            gba_load_state(state_path)
        }
        // another game (War of the Lions) may have opened its disc in the
        // shared reader meanwhile: ours again, and the map's textures
        if (self->open_disc()) {
            self->make_map()
        }
    }

    // our disc in the shared reader (psx_mem.cpp); true when (re)opened -
    // the cached textures are gone then
    def open_disc() : bool {
        if (rom_path == "" || (psx_has_disc() && disc_path == rom_path && disc_serial == psx_disc_serial())) {
            return false
        }
        disc_path = rom_path
        let err = psx_open_disc(rom_path)
        if (err != "") {
            log_line("Disc: {err} (no graphics)")
        }
        disc_serial = psx_disc_serial()
        return true
    }

    def load_files() : string {
        try_ok(gba_load_state(state_path), "State: ")
        try_ok(read_battle(units))
        self->open_disc()
        return ""
    }

    def load(remember : bool = true) : void {
        let err = self->load_files()
        if (err != "") {
            message = err
            log_line(message)
            return
        }
        saved := units
        self->make_map()
        field.cell = 0.0
        selected = length(units) > 0 ? 0 : -1
        message = "{length(units)} units in battle"
        let dot = find(state_path, ".", max(0, length(state_path) - 6))
        export_path = dot >= 0 ? "{slice(state_path, 0, dot)}.edited{slice(state_path, dot)}" : "{state_path}.edited"
        log_line("loaded {state_path}: {message}")
        if (remember) {
            config_set("fft_state", state_path)
            config_set("fft_rom", rom_path)
        }
    }

    def export_state() : void {
        var err = ""
        if (export_path == "" || export_path == state_path) {
            err = "choose a path other than the loaded state"
        } else {
            err = export_battle(units, export_path)
        }
        message = err != "" ? "Export: {err}" : "exported to {export_path} (BizHawk: File > Load State)"
        log_line(message)
    }

    // the field: the shown height (half units rounded down) + 1, 0 no tile
    def make_map() : void {
        if (read_map(map)) {
            // the game's camera sees the mirror image of the field's view
            // (+x up-right, +y up-left): research/fftwotl/graphics.md
            field_map = FieldMap(w = map.w, h = map.h, shown_shift = -1, mirror = true)
            field_map.height |> resize(map.w * map.h)
            field_map.water |> resize(map.w * map.h)
            for (i in range(map.w * map.h)) {
                field_map.height[i] = map.height[i] / 2 + 1
            }
            if (psx_has_disc()) {
                let err = load_map_mesh(shell_renderer(), field_map.polys)
                if (err != "") {
                    log_line("Map mesh: {err}")
                }
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
            let text = "{un.name}  Lv{un.level}  Sp {un.speed}  CT {un.ct}"
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
        var bottom = inspect("fft_unit{selected}", units[selected], saved[selected], x, y, w)
        bottom = self->equip_rows(units[selected], x, bottom + u(6.0), w)
        update_unit(units[selected])
        return bottom
    }

    def equip_rows(un : FftUnit; x, y, w : float) : float {
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("fft_equip_section", "Equipment", equip_open)) {
            return ry
        }
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let lw = floor(w * 0.4)
        for (k in range(EQUIP_SLOTS)) {
            let iid = un.equip[k]
            text_at_baseline(x + u(8.0), ry + u(15.0), EQUIP_LABELS[k], dim)
            let icon = iid > 0 && iid < 0xFF ? psx_item_icon(shell_renderer(), iid) : -1
            if (icon >= 0) {
                gba_gfx_draw(icon, x + lw, ry + u(2.0), u(16.0), u(16.0), 1.0)
            }
            text_at_baseline(x + lw + (icon >= 0 ? u(20.0) : 0.0), ry + u(15.0), iid == 0xFF || iid == 0 ? "-" : item_name(iid), fg)
            ry += u(21.0)
        }
        return ry
    }

    def override draw_scene(x, y, w, h : float) : void {
        let tw = u(120.0)
        SetCursorScreenPos(ImVec2(x + u(8.0), y + u(6.0)))
        if (bl_radio_button("fft_tab_field", "Field", ICON_FIELD, tw, BND_CORNER_RIGHT, scene_tab == 0)) {
            scene_tab = 0
        }
        SetCursorScreenPos(ImVec2(x + u(8.0) + tw, y + u(6.0)))
        if (bl_radio_button("fft_tab_screen", "Screen", ICON_SCREEN, tw, BND_CORNER_LEFT, scene_tab == 1)) {
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
            // standing: frame 2 (three quarters, facing down-left on the
            // screen) and 6 (up-left); the right ones mirrored
            let f = facing_to_field(un.facing)
            let vf = field_view_facing(field_map, f)
            let spr = (psx_has_disc() ? psx_unit_sprite(shell_renderer(), unit_sprite(un), un.palette,
                vf == 1 || vf == 2 ? 6 : 2, vf >= 2) : -1)
            fu |> push(FieldUnit(name = un.name, x = un.x, y = un.y, facing = f, team = un.team, alive = un.hp > 0,
                sprite = spr, sprite_scale = 0.75))
        }
        let bar = u(28.0)
        // the selected unit's Move, or its Attack on the Attack tab
        var reach : array<bool>
        if (selected >= 0 && selected < length(units) && map.w > 0) {
            reach <- calc_tab == 2 ? attack_reach(units[selected], map) : move_reach(units, map, selected)
        }
        let input = draw_battle_field(field_map, fu, selected, calc_tab == 2 ? attack_target : -1, reach, field, x + u(8.0), y,
            w - u(16.0), h - bar)
        if (input.select >= 0) {
            selected = input.select
        }
        if (input.target >= 0) {
            attack_target = input.target
            calc_tab = 2
        }
        if (input.moved >= 0) {
            units[input.moved].x = input.move_x
            units[input.moved].y = input.move_y
            update_unit(units[input.moved])
        }
        var tr = input.turn
        let bt_turn = field_bar(field, x + u(8.0), y + h - bar + u(4.0))
        if (bt_turn != 0) {
            tr = bt_turn
        }
        if (tr != 0 && selected >= 0) {
            // turned in the field's numbering
            let f = (facing_to_field(units[selected].facing) + (tr > 0 ? 1 : 3)) & 3
            units[selected].facing = facing_to_field(f)
            update_unit(units[selected])
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

    def override draw_calc(x, y, w, h : float) : void {
        SetCursorScreenPos(ImVec2(x, y))
        if (length(units) == 0) {
            bl_label(message, ICON_TURNS)
            return
        }
        let tw = u(120.0)
        if (bl_radio_button("fft_tab_turns", "Turn order", ICON_TURNS, tw, BND_CORNER_RIGHT, calc_tab == 0)) {
            calc_tab = 0
        }
        SetCursorScreenPos(ImVec2(x + tw, y))
        if (bl_radio_button("fft_tab_units", "Units", ICON_UNIT, tw, BND_CORNER_ALL, calc_tab == 1)) {
            calc_tab = 1
        }
        SetCursorScreenPos(ImVec2(x + tw * 2.0, y))
        if (bl_radio_button("fft_tab_attack", "Attack", ICON_ATTACK, tw, BND_CORNER_LEFT, calc_tab == 2)) {
            calc_tab = 2
        }
        let ty = y + u(28.0)
        if (calc_tab == 2) {
            self->attack_view(x, ty, w, y + h - ty)
        } elif (calc_tab == 1) {
            self->unit_table(x, ty, w, y + h - ty)
        } else {
            self->turn_view(x, ty, w, y + h - ty)
        }
    }

    def turn_view(x, y, w, h : float) : void {
        let turns <- predict_turns(units, turns_ahead)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let nw = u(180.0)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Turn order  (CT 100+ acts; a tick adds Speed; a turn: -100 / -80 / -60, at most 60 after)", ICON_TURNS,
            w - nw - u(8.0))
        SetCursorScreenPos(ImVec2(x + w - nw - u(4.0), y))
        var ahead = float(turns_ahead)
        if (bl_number("fft_turns_ahead", "Turns ahead", ahead, 0.1, 0, nw)) {
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
        BeginChild("fft_turns", ImVec2(w, y + h - ry), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        var dl = GetWindowDrawList()
        var yy = GetCursorScreenPos().y
        for (k in range(length(turns))) {
            let t = turns[k]
            let un = units[t.unit]
            SetCursorScreenPos(ImVec2(x, yy))
            if (InvisibleButton("##fft_turn{k}", ImVec2(w - u(4.0), row_h))) {
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
            text_at_baseline(x + u(cols[3]), b, t.tick == 0 ? "now" : "+{t.tick}", fg)
            if (t.charge != 0) {
                // a charged ability going off, before the turns of its tick
                text_at_baseline(x + u(cols[1]), b, "{ability_name(t.charge)} ({un.name})", team_text_color(un.team))
                text_at_baseline(x + u(cols[2]), b, "charged", dim)
                text_at_baseline(x + u(450.0), b, "goes off", dim)
            } else {
                text_at_baseline(x + u(cols[1]), b, un.name, team_text_color(un.team))
                text_at_baseline(x + u(cols[2]), b, un.job, fg)
                text_at_baseline(x + u(cols[4]), b, "{t.nth}", fg)
                text_at_baseline(x + u(cols[5]), b, "{t.ct}", fg)
                text_at_baseline(x + u(450.0), b, turn_end_text(un.assumed), dim)
            }
            yy += row_h
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }

    // Attack from the selected unit at every other unit (as they stand)
    def attack_view(x, y, w, h : float) : void {
        if (selected < 0 || selected >= length(units)) {
            return
        }
        let a = units[selected]
        let wpn = unit_weapon(a)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        // the action: Attack or one of the unit's abilities
        if (action_unit != selected) {
            action_unit = selected
            action_sel = 0
        }
        let abilities <- unit_abilities(a)
        var shown : array<int>                        // ability ids in the choice after Attack
        var items : array<string>
        items |> push("Attack")
        var jump_listed = false
        for (ua in abilities) {
            // the Jump abilities (their reach) make one Jump command
            let jump = ua.id >= 0x18A && ua.id < 0x196
            if ((ua.learned || all_abilities) && !(jump && jump_listed)) {
                shown |> push(ua.id)
                let name = jump ? "Jump" : ability_name(ua.id)
                items |> push(ua.learned ? name : "{name} (not learned)")
                jump_listed = jump_listed || jump
            }
        }
        action_sel = clamp(action_sel, 0, length(items) - 1)
        SetCursorScreenPos(ImVec2(x, y))
        bl_choice("fft_action", items, action_sel, u(220.0))
        SetCursorScreenPos(ImVec2(x + u(228.0), y))
        bl_option("fft_all_abilities", "Not learned too", all_abilities)
        if (action_sel > 0) {
            self->ability_view(a, read_ability(shown[action_sel - 1]), x, y + u(26.0), w, h - u(26.0))
            return
        }
        let head = wpn.item == 0 ? "bare hands" : "{wpn.name} (WP {wpn.wp}, range {wpn.reach})"
        SetCursorScreenPos(ImVec2(x + u(380.0), y))
        bl_label("with {head}  (dim: out of reach)", -1, w - u(380.0))
        let row_h = u(21.0)
        let names = fixed_array<string>("Target", "Dist", "Side", "Damage", "Critical", "Hit", "HP after")
        let widths = fixed_array<float>(110.0, 50.0, 60.0, 80.0, 80.0, 50.0, 80.0)
        var cols : array<float>
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
        BeginChild("fft_attack", ImVec2(w, y + h - ry), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        var dl = GetWindowDrawList()
        var yy = GetCursorScreenPos().y
        let sides = fixed_array<string>("front", "side", "back")
        if (attack_target < 0 || attack_target >= length(units) || attack_target == selected) {
            // an enemy in reach, else any other unit alive
            attack_target = -1
            for (round in range(2)) {
                for (i in range(length(units))) {
                    let t = units[i]
                    let fits = round == 1 || (t.team != a.team && attack_reaches(a, wpn, map, t.x, t.y))
                    if (attack_target < 0 && i != selected && t.hp > 0 && fits) {
                        attack_target = i
                    }
                }
            }
        }
        for (i in range(length(units))) {
            let t = units[i]
            if (i == selected || t.hp <= 0) {
                continue
            }
            let f = attack_forecast(a, t)
            let dist = abs(t.x - a.x) + abs(t.y - a.y)
            SetCursorScreenPos(ImVec2(x, yy))
            if (InvisibleButton("##fft_atk{i}", ImVec2(w - u(4.0), row_h))) {
                attack_target = i
            }
            if (i == attack_target) {
                *dl |> AddRectFilled(ImVec2(x, yy), ImVec2(x + w - u(4.0), yy + row_h), abgr(bt.menu_item.inner_sel), 0.0,
                    ImDrawFlags.None)
            }
            *dl |> AddRectFilled(ImVec2(x + u(2.0), yy + u(3.0)), ImVec2(x + u(6.0), yy + row_h - u(3.0)),
                abgr(side_color(t.team)), u(2.0), ImDrawFlags.None)
            let b = yy + u(15.0)
            let col = attack_reaches(a, wpn, map, t.x, t.y) ? fg : dim
            let dmg = f.damage_min == f.damage_max ? "{f.damage_min}" : "{f.damage_min}..{f.damage_max}"
            text_at_baseline(cols[0], b, t.name, team_text_color(t.team))
            text_at_baseline(cols[1], b, "{dist}", col)
            text_at_baseline(cols[2], b, sides[f.side], col)
            text_at_baseline(cols[3], b, dmg, col)
            text_at_baseline(cols[4], b, "..{f.crit_max}", dim)
            text_at_baseline(cols[5], b, "{f.hit}%", col)
            text_at_baseline(cols[6], b, "{max(0, t.hp - f.damage_max)}/{t.max_hp}", col)
            yy += row_h
        }
        if (attack_target >= 0 && attack_target < length(units)) {
            let f = attack_forecast(a, units[attack_target])
            yy += u(8.0)
            let xa = f.xa_min == f.xa_max ? "{f.xa_min}" : "{f.xa_min}..{f.xa_max}"
            var lines : array<string>
            lines |> push("{units[attack_target].name}: {f.formula}, XA {xa}, YA {f.ya}")
            lines |> push("critical (5%): XA + rand(0..XA - 1)")
            lines |> push("evades, {f.evades}")
            lines |> push("reaction: {reaction_text(reaction_to(a, units[attack_target], FftAbility(), f.damage_max))}")
            for (n in f.notes) {
                lines |> push(n)
            }
            for (l in lines) {
                text_at_baseline(x + u(12.0), yy + u(14.0), l, dim)
                yy += u(19.0)
            }
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }

    // an ability from the selected unit at every other unit (as they stand)
    def ability_view(a : FftUnit; ab : FftAbility; x, y, w, h : float) : void {
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        SetCursorScreenPos(ImVec2(x, y))
        let reach = ab.reach == 0 ? "self" : "range {ab.reach}"
        let mp = ab.mp > 0 ? "MP {ab.mp}, " : ""
        let ct = ab.ct > 0 ? "CT {ab.ct}, " : "now, "
        let area = ab.area > 0 ? ", area {ab.area}" : ""
        bl_label("{ab.name}: {mp}{ct}{reach}{area}  (dim: out of range)", ICON_ATTACK, w)
        let row_h = u(21.0)
        let names = fixed_array<string>("Target", "Dist", "Effect", "Amount", "Hit", "HP after")
        let widths = fixed_array<float>(110.0, 50.0, 190.0, 80.0, 50.0, 80.0)
        var cols : array<float>
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
        BeginChild("fft_ability", ImVec2(w, y + h - ry), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        var dl = GetWindowDrawList()
        var yy = GetCursorScreenPos().y
        for (i in range(length(units))) {
            let t = units[i]
            let self_only = ab.reach == 0
            // the caster too when the area holds it (flags 2 bit 0: never)
            let caster_hit = ab.area > 0 && (uint(ab.flags[1]) & 1u) == 0u
            if ((i == selected) != self_only && !(caster_hit && i == selected)) {
                continue
            }
            // the dead: only for revival
            if (t.hp <= 0 && ab.formula != 0x0D && ab.formula != 0x4B) {
                continue
            }
            let f = ability_forecast(a, t, ab)
            let dist = abs(t.x - a.x) + abs(t.y - a.y)
            SetCursorScreenPos(ImVec2(x, yy))
            if (InvisibleButton("##fft_ab{i}", ImVec2(w - u(4.0), row_h))) {
                attack_target = i
            }
            if (i == attack_target) {
                *dl |> AddRectFilled(ImVec2(x, yy), ImVec2(x + w - u(4.0), yy + row_h), abgr(bt.menu_item.inner_sel), 0.0,
                    ImDrawFlags.None)
            }
            *dl |> AddRectFilled(ImVec2(x + u(2.0), yy + u(3.0)), ImVec2(x + u(6.0), yy + row_h - u(3.0)),
                abgr(side_color(t.team)), u(2.0), ImDrawFlags.None)
            let b = yy + u(15.0)
            let col = dist <= ab.reach + ab.area ? fg : dim
            let range_text = "{f.amount_min}..{f.amount_max}"
            let amount = f.amount_max == 0 ? "-" : (f.amount_min == f.amount_max ? "{f.amount_min}" : range_text)
            let after = f.heal ? min(t.max_hp, t.hp + f.amount_max) : max(0, t.hp - f.amount_max)
            text_at_baseline(cols[0], b, t.name, team_text_color(t.team))
            text_at_baseline(cols[1], b, "{dist}", col)
            text_at_baseline(cols[2], b, f.effect, f.known ? col : dim)
            text_at_baseline(cols[3], b, f.heal && f.amount_max > 0 ? "+{amount}" : amount, col)
            text_at_baseline(cols[4], b, "{f.hit}%", col)
            text_at_baseline(cols[5], b, f.amount_max == 0 ? "" : "{after}/{t.max_hp}", col)
            yy += row_h
        }
        if (attack_target >= 0 && attack_target < length(units)) {
            let f = ability_forecast(a, units[attack_target], ab)
            yy += u(8.0)
            var lines : array<string>
            let how = f.known ? f.formula : "this formula is not modelled yet"
            lines |> push("{units[attack_target].name}: {how}")
            let dealt = f.heal ? 0 : f.amount_max
            lines |> push("reaction: {reaction_text(reaction_to(a, units[attack_target], ab, dealt))}")
            for (n in f.notes) {
                lines |> push(n)
            }
            for (l in lines) {
                text_at_baseline(x + u(12.0), yy + u(14.0), l, dim)
                yy += u(19.0)
            }
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }

    def unit_table(x, y, w, h : float) : void {
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Units", ICON_UNIT)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let row_h = u(21.0)
        var cols : array<float>
        let names = fixed_array<string>("Unit", "Job", "Lv", "HP", "MP", "Br", "Fa", "PA", "MA", "Sp", "CT", "Mv", "Jp")
        let widths = fixed_array<float>(90.0, 100.0, 28.0, 64.0, 50.0, 32.0, 32.0, 32.0, 32.0, 32.0, 38.0, 32.0, 32.0)
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
        BeginChild("fft_units", ImVec2(w, y + h - ry), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        var dl = GetWindowDrawList()
        var yy = GetCursorScreenPos().y
        for (i in range(length(units))) {
            let un = units[i]
            SetCursorScreenPos(ImVec2(x, yy))
            if (InvisibleButton("##fft_row{i}", ImVec2(w - u(4.0), row_h))) {
                selected = i
            }
            if (i == selected) {
                *dl |> AddRectFilled(ImVec2(x, yy), ImVec2(x + w - u(4.0), yy + row_h), abgr(bt.menu_item.inner_sel), 0.0,
                    ImDrawFlags.None)
            }
            *dl |> AddRectFilled(ImVec2(x + u(2.0), yy + u(3.0)), ImVec2(x + u(6.0), yy + row_h - u(3.0)),
                abgr(side_color(un.team)), u(2.0), ImDrawFlags.None)
            let b = yy + u(15.0)
            let cells <- [un.name, un.job, "{un.level}", "{un.hp}/{un.max_hp}", "{un.mp}/{un.max_mp}", "{un.brave}",
                "{un.faith}", "{un.pa}", "{un.ma}", "{un.speed}", "{un.ct}", "{un.move}", "{un.jump}"]
            for (k in range(length(cells))) {
                text_at_baseline(cols[k], b, cells[k], k == 0 ? team_text_color(un.team) : fg)
            }
            yy += row_h
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }
}
