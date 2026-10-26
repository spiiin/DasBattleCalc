options gen2
options indenting = 4

// Final Fantasy Tactics: The War of the Lions (PSP, USA, ULUS10297): the
// game's panels. A PPSSPP save state (.ppst) is loaded; the units and the
// game's tables come from its RAM (fftwotl_battle.das, fftwotl_data.das),
// no ISO is needed. The field shows the map's heights (read_map_w).
module fftwotl shared public

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
require fftwotl_data
require fftwotl_battle
require fftwotl_attack
require fftwotl_turns
require fftwotl_explore
require fftwotl_map

let private STAT_W_LABELS = fixed_array<string>("PA", "MA", "Speed")

def private right_w(x, baseline : float; s : string; color : uint) {
    text_at_baseline(x - text_width(s), baseline, s, color)
}

def private signed_w(v : int) : string {
    return v > 0 ? "+{v}" : "{v}"
}

// what an item gives, one line
def item_text_w(it : ItemW) : string {
    if (it.id == ITEM_NONE) {
        return ""
    }
    var parts : array<string>
    if (is_weapon_w(it)) {
        parts |> push("WP {it.wp}")
        if (it.w_ev != 0) {
            parts |> push("evade {it.w_ev}%")
        }
        parts |> push("range {it.reach}")
    }
    if (it.p_ev != 0 || it.m_ev != 0) {
        parts |> push("evade {it.p_ev}% / {it.m_ev}%")
    }
    if (it.hp != 0) {
        parts |> push("HP +{it.hp}")
    }
    if (it.mp != 0) {
        parts |> push("MP +{it.mp}")
    }
    let stats = fixed_array<int>(it.pa, it.ma, it.sp, it.move, it.jump)
    let snames = fixed_array<string>("PA", "MA", "Speed", "Move", "Jump")
    for (k in range(5)) {
        if (stats[k] != 0) {
            parts |> push("{snames[k]} {signed_w(stats[k])}")
        }
    }
    if (it.element != 0) {
        parts |> push(element_text(it.element))
    }
    if (it.inflict != 0 && is_weapon_w(it)) {
        parts |> push(inflict_text(it.inflict))
    }
    let always = status_text(it.always)
    if (always != "-") {
        parts |> push("always {always}")
    }
    let immune = status_text(it.immune)
    if (immune != "-") {
        parts |> push("immune {immune}")
    }
    let el = fixed_array<int>(it.absorb, it.cancel, it.half, it.weak, it.strengthen)
    let elw = fixed_array<string>("absorbs", "nullifies", "halves", "weak", "strengthens")
    for (k in range(5)) {
        if (el[k] != 0) {
            parts |> push("{elw[k]} {element_text(el[k])}")
        }
    }
    return length(parts) > 0 ? join(parts, ", ") : "no bonus"
}

// Explore editor colors: what a word of the script is
class WotlGame : GameModule {
    units : array<UnitW>
    saved : array<UnitW>              // as read from the state: Revert
    selected : int = -1
    target : int = -1
    field = FieldState()
    field_map : FieldMap
    map_w : MapW
    scene_tab : int = 0               // 0 field, 1 the Explore chart
    calc_tab : int = 0                // 0 turn order, 1 attack, 2 explore, 3 units, 4 items, 5 abilities
    side_choice : int = 0             // 0 auto, 1 + SideW
    actions : array<int>              // the selected unit's actions (Attack = 0 first)
    actions_of : int = -1             // for which unit (index) they were made
    action : int = 0
    all_abilities : bool = false      // the Attack tab: every ability, not only the unit's skillsets
    stats_open : bool = true
    equip_open : bool = true
    status_open : bool = false
    learned_open : bool = false
    job_open : table<string; bool>    // "unit job": an open job block of the learned abilities
    pick_slot : int = 0
    item_filter = ImGuiInputTextBuffer("", 64)
    item_all : bool = false
    turns_ahead : int = 24
    arith_alg : int = 1               // the Attack tab's Arithmeticks: algorithm, number, magick
    arith_num : int = 3
    arith_spell : int = 0
    state_path : string
    iso_path : string                 // the ISO (optional): the graphics - sprites, icons, the map's mesh
    disc_serial : uint = 0xFFFFFFFFu // psx_disc_serial() after opening iso_path (another game may open its disc)
    loaded_state : string
    export_path : string
    from_args : bool
    message : string = "Load a PPSSPP save state (.ppst) of FFT: The War of the Lions (USA)"
    // the Items / Abilities tabs: the game's tables
    table_filter = ImGuiInputTextBuffer("", 64)
    table_pick : int = -1
    // Explore
    explore : ExplorePanel = make_explore_panel("explorew", EXPLORE_W_NAMES, EXPLORE_W_EXAMPLES,
        EXPLORE_W_GENERATORS, METRICS_W)

    def WotlGame {
        state_path = config_get("wotl_state")
        iso_path = config_get("wotl_iso")
        if (gui_arg("--game", "") == "fftwotl") {
            from_args = gui_arg("--state", "") != ""
            state_path = gui_arg("--state", state_path)
            iso_path = gui_arg("--rom", iso_path)
        }
    }

    def override id() : string {
        return "fftwotl"
    }

    def override title() : string {
        return "FFT: The War of the Lions"
    }

    def override status() : string {
        return "WotL: {message}"
    }

    // the web page's files: a PPSSPP state (its header: version "v1." at
    // +0x10) is this game's - there is no ROM
    def override accepts_rom(code : string) : bool {
        var ok = false
        fopen(gui_arg("--state", ""), "rb") $(f) {
            if (f != null) {
                fload(f, 20l) $(data) {
                    ok = length(data) == 20 && data[16] == uint8(0x76) && data[17] == uint8(0x31) && data[18] == uint8(0x2E)
                }
            }
        }
        return ok
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
        } else {
            if (!gba_state_is_psp()) {
                gba_load_state(loaded_state)
            }
            if (iso_path != "" && psx_disc_serial() != disc_serial) {
                self->open_iso()
                self->make_map()
            }
        }
    }

    // the ISO for the graphics (the disc reader is shared with FFT PSX)
    def open_iso() : void {
        if (iso_path == "") {
            return
        }
        if (!psx_has_disc() || psx_disc_serial() != disc_serial) {
            let err = psx_open_disc(iso_path)
            disc_serial = psx_disc_serial()
            if (err != "") {
                log_line("ISO: {err} (no graphics)")
            } elif (psp_pack_count() == 0) {
                log_line("ISO: no PSP_GAME/USRDIR/fftpack.bin (no graphics)")
            }
        }
    }

    // the item's icon for bl_menu_item (GBA_GFX_ICON_BASE + the handle), -1
    def item_icon_id(iid : int) : int {
        let h = self->has_iso() ? psp_item_icon(shell_renderer(), iid) : -1
        return h >= 0 ? 65536 + h : -1
    }

    def has_iso() : bool {
        return iso_path != "" && psx_has_disc() && psx_disc_serial() == disc_serial && psp_pack_count() > 0
    }

    def load(remember : bool = true) : void {
        var err = gba_load_state(state_path)
        if (err == "") {
            err = read_battle_w(units)
        } else {
            err = "State: {err}"
        }
        if (err != "") {
            message = err
            log_line(message)
            return
        }
        loaded_state = state_path
        saved := units
        if (iso_path != "" && psx_disc_serial() != disc_serial) {
            self->open_iso()
        }
        self->make_map()
        field.cell = 0.0
        selected = 0
        for (i in range(length(units))) {
            if (units[i].active) {
                selected = i
            }
        }
        target = -1
        actions_of = -1
        message = "{length(units)} units in battle"
        let dot = find(state_path, ".", max(0, length(state_path) - 6))
        export_path = dot >= 0 ? "{slice(state_path, 0, dot)}.edited{slice(state_path, dot)}" : "{state_path}.edited"
        log_line("loaded {state_path}: {message}")
        if (remember) {
            config_set("wotl_state", state_path)
            config_set("wotl_iso", iso_path)
        }
    }

    def export_state() : void {
        var err = ""
        if (export_path == "" || export_path == state_path) {
            err = "choose a path other than the loaded state"
        } else {
            err = export_battle_w(units, export_path)
        }
        message = err != "" ? "Export: {err}" : "exported to {export_path} (PPSSPP: File > Load State...)"
        log_line(message)
    }

    // the battle map with its heights (water: depth); a flat field around
    // the units when the state has none
    def make_map() : void {
        if (read_map_w(map_w)) {
            field_map = FieldMap(w = map_w.w, h = map_w.h, shown_shift = -1, mirror = true)
            field_map.height |> resize(map_w.w * map_w.h)
            field_map.water |> resize(map_w.w * map_w.h)
            for (i in range(map_w.w * map_w.h)) {
                field_map.height[i] = map_w.height[i] + 1
                field_map.water[i] = map_w.depth[i] > 0
            }
            if (self->has_iso()) {
                let err = load_map_mesh_w(shell_renderer(), field_map.polys)
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
        var ry = source_fields(state_path, iso_path, export_path, length(units) > 0, x, y, w, pressed)
        if (pressed == ROSTER_LOAD) {
            self->load()
        } elif (pressed == ROSTER_EXPORT) {
            self->export_state()
        }
        for (i in range(length(units))) {
            let un = units[i]
            let turn = un.active ? "  (turn)" : ""
            let text = "{un.name}  Lv{un.level}  {un.job}  CT {un.ct}{turn}"
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
        if (inspect_changed_w(units[selected], saved[selected])) {
            SetCursorScreenPos(ImVec2(x, by))
            if (bl_tool_button("revert_unit_w", "Revert unit", ICON_TURN_CCW, w)) {
                units[selected] := saved[selected]
            }
            by += u(27.0)
        }
        by = self->job_row(units[selected], saved[selected], x, by, w)
        by = self->skillset_row(units[selected], saved[selected], false, x, by, w)
        by = self->skillset_row(units[selected], saved[selected], true, x, by, w)
        for (k in range(3)) {
            by = self->rsm_row(units[selected], saved[selected], k, x, by, w)
        }
        var bottom = inspect("unitw_{selected}", units[selected], saved[selected], x, by, w)
        bottom = self->stat_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        bottom = self->equip_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        bottom = self->status_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        bottom = self->learned_rows(units[selected], saved[selected], x, bottom + u(6.0), w)
        return bottom
    }

    // the job: any job with a name (story jobs, generic jobs, monsters)
    def job_row(var unit : UnitW; saved_u : UnitW; x, y, w : float) : float {
        let lw = floor(w * 0.4)
        let bw = u(24.0)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Job:", -1, lw)
        SetCursorScreenPos(ImVec2(x + lw, y))
        var names : array<string>
        var ids : array<int>
        var sel = 0
        for (j in range(1, JOB_COUNT_W)) {
            let n = job_name_w(j)
            if (n != "") {
                if (j == unit.job_id) {
                    sel = length(names)
                }
                names |> push("{n} ({j})")
                ids |> push(j)
            }
        }
        if (bl_choice("unitw_job", names, sel, w - lw - bw)) {
            unit.job_id = ids[sel]
            unit.job = job_name_w(unit.job_id)
            recompute_unit_w(unit)
        }
        if (unit.job_id != saved_u.job_id && bl_revert_button("jobw_revert", x + w - u(22.0), y)) {
            unit.job_id = saved_u.job_id
            unit.job = saved_u.job
            recompute_unit_w(unit)
        }
        return y + u(26.0)
    }

    // primary / secondary skillset: any skillset with a name
    def skillset_row(var unit : UnitW; saved_u : UnitW; second : bool; x, y, w : float) : float {
        let lw = floor(w * 0.4)
        let bw = u(24.0)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label(second ? "Secondary:" : "Primary:", -1, lw)
        var names <- ["none"]
        var ids <- [0]
        var sel = 0
        let cur = second ? unit.secondary : unit.primary
        for (s in range(1, SKILLSET_COUNT_W)) {
            let n = skillset_name_w(s)
            if (n != "") {
                if (s == cur) {
                    sel = length(names)
                }
                names |> push(n)
                ids |> push(s)
            }
        }
        SetCursorScreenPos(ImVec2(x + lw, y))
        if (bl_choice(second ? "unitw_secondary" : "unitw_primary", names, sel, w - lw - bw)) {
            if (second) {
                unit.secondary = ids[sel]
            } else {
                unit.primary = ids[sel]
            }
            actions_of = -1
        }
        let old = second ? saved_u.secondary : saved_u.primary
        if (cur != old && bl_revert_button(second ? "secondaryw_revert" : "primaryw_revert", x + w - u(22.0), y)) {
            if (second) {
                unit.secondary = old
            } else {
                unit.primary = old
            }
            actions_of = -1
        }
        return y + u(26.0)
    }

    // reaction (0), support (1), movement (2): any of the game's
    def rsm_row(var unit : UnitW; saved_u : UnitW; k : int; x, y, w : float) : float {
        let lw = floor(w * 0.4)
        let bw = u(24.0)
        let labels = fixed_array<string>("Reaction:", "Support:", "Movement:")
        let kinds = fixed_array<int>(AB_REACTION, AB_SUPPORT, AB_MOVEMENT)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label(labels[k], -1, lw)
        let list <- abilities_of_kind(kinds[k])
        var names <- ["none"]
        var sel = 0
        let cur = k == 0 ? unit.reaction : (k == 1 ? unit.support : unit.movement)
        for (i in range(length(list))) {
            names |> push(ability_name_w(list[i]))
            if (list[i] == cur) {
                sel = i + 1
            }
        }
        SetCursorScreenPos(ImVec2(x + lw, y))
        if (bl_choice("unitw_rsm{k}", names, sel, w - lw - bw)) {
            let aid = sel == 0 ? 0 : list[sel - 1]
            if (k == 0) {
                unit.reaction = aid
            } elif (k == 1) {
                unit.support = aid
            } else {
                unit.movement = aid
            }
            rebuild_rsm_mask(unit)
        }
        let old = k == 0 ? saved_u.reaction : (k == 1 ? saved_u.support : saved_u.movement)
        if (cur != old && bl_revert_button("rsmw_revert{k}", x + w - u(22.0), y)) {
            if (k == 0) {
                unit.reaction = old
            } elif (k == 1) {
                unit.support = old
            } else {
                unit.movement = old
            }
            unit.rsm_mask = saved_u.rsm_mask
        }
        return y + u(26.0)
    }

    // PA / MA / Speed: raw (editable) + equipment = current; Move, Jump,
    // evades as the game keeps them
    def stat_rows(var un : UnitW; saved_u : UnitW; x, y, w : float) : float {
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("statsw_section", "Stats", stats_open)) {
            return ry
        }
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let c_base = x + floor(w * 0.6)
        let c_items = x + floor(w * 0.8)
        let c_total = x + w - u(6.0)
        right_w(c_base, ry + u(13.0), "base", dim)
        right_w(c_items, ry + u(13.0), "items", dim)
        right_w(c_total, ry + u(13.0), "total", dim)
        ry += u(18.0)
        for (i in range(3)) {
            let b = ry + u(15.0)
            text_at_baseline(x + u(8.0), b, STAT_W_LABELS[i], fg)
            let nw = u(78.0)
            SetCursorScreenPos(ImVec2(c_base - nw, ry))
            var v = float(un.raw[i])
            if (bl_number("statw_{i}", "", v, 0.2, 0, nw)) {
                un.raw[i] = clamp(int(round(v)), 0, 99)
                recompute_unit_w(un)
            }
            if (un.raw[i] != saved_u.raw[i] && bl_revert_button("statw_revert{i}", c_base - nw - u(24.0), ry)) {
                un.raw[i] = saved_u.raw[i]
                recompute_unit_w(un)
            }
            if (un.bonus[i] != 0) {
                right_w(c_items, b, signed_w(un.bonus[i]), un.bonus[i] > 0 ? 0x70c070ffu : 0xe07070ffu)
            }
            let cur = i == 0 ? un.pa : (i == 1 ? un.ma : un.sp)
            right_w(c_total, b, "{cur}", fg)
            ry += u(21.0)
        }
        var rows : array<tuple<string; string>>
        rows |> push(("Move / Jump", "{un.move} / {un.jump}"))
        rows |> push(("Weapon power", "R {un.wp[0]}, L {un.wp[1]}"))
        rows |> push(("Evade (phys)", "class {un.c_ev}%, shield L {un.s_ev[0]}% R {un.s_ev[1]}%, accessory {un.a_ev}%"))
        rows |> push(("Evade (magic)", "shield L {un.sm_ev[0]}% R {un.sm_ev[1]}%, accessory {un.am_ev}%"))
        let el = fixed_array<int>(un.absorb, un.cancel, un.half, un.weak, un.strengthen)
        let eln = fixed_array<string>("absorbs", "nullifies", "halves", "weak", "strengthens")
        var ep : array<string>
        for (k in range(5)) {
            if (el[k] != 0) {
                ep |> push("{eln[k]} {element_text(el[k])}")
            }
        }
        rows |> push(("Elements", length(ep) > 0 ? join(ep, "; ") : "-"))
        for (r in rows) {
            text_at_baseline(x + u(8.0), ry + u(15.0), r._0, dim)
            text_at_baseline(x + floor(w * 0.36), ry + u(15.0), r._1, fg)
            ry += u(21.0)
        }
        return ry
    }

    // seven equipment slots: a click opens the list of items for the slot
    // (what the job can wear; "All items" shows the rest too)
    def equip_rows(var un : UnitW; saved_u : UnitW; x, y, w : float) : float {
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("equipw_section", "Equipment", equip_open)) {
            return ry
        }
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let bw = u(24.0)
        let kw = u(110.0)
        let job = read_job_w(un.job_id)
        let iso = self->has_iso()
        let iw = iso ? u(20.0) : 0.0
        for (slot in range(7)) {
            let it = un.equip[slot]
            let icon = iso && it.id != ITEM_NONE ? psp_item_icon(shell_renderer(), it.id) : -1
            if (icon >= 0) {
                gba_gfx_draw(icon, x, ry + u(2.0), u(16.0), u(16.0), 1.0)
            }
            SetCursorScreenPos(ImVec2(x + iw, ry))
            let caption = it.id != ITEM_NONE ? it.name : "({SLOT_W_NAMES[slot]}: empty)"
            if (bl_tool_button("equipw_slot{slot}", caption, -1, w - bw - kw - u(4.0) - iw)) {
                OpenPopup("##itemw_pick")
                pick_slot = slot
                item_filter = ImGuiInputTextBuffer("", 64)
            }
            if (it.id != ITEM_NONE) {
                let bad = job_can_equip(job, it.kind) ? "" : " (!)"
                right_w(x + w - bw - u(6.0), ry + u(15.0), "{KIND_W_NAMES[it.kind]}{bad}", dim)
            }
            if (un.items[slot] != saved_u.items[slot] && bl_revert_button("equipw_revert{slot}", x + w - u(22.0), ry)) {
                un.items[slot] = saved_u.items[slot]
                recompute_unit_w(un)
            }
            ry += u(22.0)
            if (it.id != ITEM_NONE) {
                text_at_baseline(x + u(12.0), ry + u(13.0), item_text_w(it), dim)
                ry += u(19.0)
            }
        }
        self->item_picker(un, x, w)
        return ry
    }

    def item_picker(var un : UnitW; x, w : float) : void {
        SetNextWindowSize(ImVec2(max(w, u(360.0)), u(380.0)), ImGuiCond.Always)
        bl_push_popup_style()
        PushStyleColor(ImGuiCol.PopupBg, abgr(bt.menu.inner | 0xffu))
        if (BeginPopup("##itemw_pick")) {
            let pw = GetContentRegionAvail().x
            let p = GetCursorScreenPos()
            SetCursorScreenPos(ImVec2(p.x + u(6.0), p.y + u(3.0)))
            bl_label("Name:", -1, u(52.0), bt.menu_item.text)
            SetCursorScreenPos(ImVec2(p.x + u(58.0), p.y + u(3.0)))
            if (!IsAnyItemActive()) {
                SetKeyboardFocusHere(0)
            }
            bl_text_field("itemw_filter", item_filter, pw - u(64.0))
            SetCursorScreenPos(ImVec2(p.x + u(6.0), p.y + u(28.0)))
            bl_option("itemw_all", "All items (not only what {un.job} can wear)", item_all)
            SetCursorScreenPos(ImVec2(p.x, p.y + u(56.0)))
            let filter = to_lower(to_string(item_filter))
            let job = read_job_w(un.job_id)
            PushStyleColor(ImGuiCol.ChildBg, abgr(bt.menu.inner | 0xffu))
            BeginChild("itemw_list", ImVec2(pw, GetContentRegionAvail().y), ImGuiChildFlags.None, ImGuiWindowFlags.None)
            bl_popup_rows() {
                if (bl_menu_item("(empty)")) {
                    un.items[pick_slot] = ITEM_NONE
                    recompute_unit_w(un)
                    CloseCurrentPopup()
                }
                for (iid in range(1, ITEM_COUNT_W)) {
                    let it = read_item_w(iid)
                    if (it.id == ITEM_NONE || starts_with(it.name, "item ") || !item_fits_slot(it, pick_slot) ||
                            (!item_all && !job_can_equip(job, it.kind))) {
                        continue
                    }
                    if (filter != "" && find(to_lower(it.name), filter) < 0) {
                        continue
                    }
                    if (bl_menu_item("{it.name}   {KIND_W_NAMES[it.kind]}   {item_text_w(it)}", self->item_icon_id(it.id))) {
                        un.items[pick_slot] = it.id
                        recompute_unit_w(un)
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

    // statuses (record +0x62) as check boxes in two columns
    def status_rows(var unit : UnitW; saved_u : UnitW; x, y, w : float) : float {
        var names : array<string>
        var changed = false
        for (n in range(1, STATUS_COUNT_W)) {
            changed = changed || status_bit(unit.status, n) != status_bit(saved_u.status, n)
            if (status_bit(unit.status, n)) {
                names |> push(status_name_w(n))
            }
        }
        if (changed && bl_revert_button("statusw_revert", x + w - u(22.0), y)) {
            unit.status = saved_u.status
        }
        SetCursorScreenPos(ImVec2(x, y))
        let now = length(names) > 0 ? join(names, ", ") : "none"
        var ry = y + u(23.0)
        if (!bl_section("statusw_section", "Status: {now}", status_open)) {
            return ry
        }
        let cw = floor(w * 0.5)
        var col = 0
        for (n in range(1, STATUS_COUNT_W)) {
            let name = status_name_w(n)
            if (name == "" || n == 14) {
                continue
            }
            SetCursorScreenPos(ImVec2(x + u(6.0) + float(col) * cw, ry))
            var on = status_bit(unit.status, n)
            let caption = on != status_bit(saved_u.status, n) ? "{name} *" : name
            if (bl_option("statusw_{n}", caption, on)) {
                set_status_bit(unit.status, n, on)
            }
            col = 1 - col
            if (col == 0) {
                ry += u(21.0)
            }
        }
        return ry + (col == 1 ? u(25.0) : u(4.0))
    }

    // learned abilities (record +0xA3): one collapsible block per job
    // with a skillset, a check box per ability; the unit's base job and
    // its current job's are open at first. "*": changed.
    def learned_rows(var unit : UnitW; saved_u : UnitW; x, y, w : float) : float {
        var changed = false
        for (i in range(LEARNED_W_SIZE)) {
            changed = changed || unit.learned[i] != saved_u.learned[i]
        }
        if (changed && bl_revert_button("learnedw_revert", x + w - u(22.0), y)) {
            unit.learned = saved_u.learned
        }
        SetCursorScreenPos(ImVec2(x, y))
        var ry = y + u(23.0)
        if (!bl_section("learnedw_section", "Learned abilities", learned_open)) {
            return ry
        }
        let cw = floor(w * 0.5)
        let cur_set = read_job_w(unit.job_id).skillset
        for (j in range(LEARN_JOBS_W)) {
            let ssid = learn_skillset(unit, j)
            if (ssid == 0) {
                continue
            }
            let ss <- read_skillset_w(ssid)
            var total = 0
            var have = 0
            var diff = false
            for (k in range(22)) {
                if (ss.slots[k] != 0) {
                    total++
                    have += learned_bit(unit, j, k) ? 1 : 0
                    diff = diff || learned_bit(unit, j, k) != learned_bit(saved_u, j, k)
                }
            }
            if (total == 0) {
                continue
            }
            let key = "{unit.slot} {j}"
            if (!key_exists(job_open, key)) {
                job_open[key] = j == 0 || ssid == cur_set
            }
            var open = job_open[key]
            SetCursorScreenPos(ImVec2(x + u(8.0), ry))
            let mark = diff ? " *" : ""
            let block_title = j == 0 ? "{ss.name} (base)" : "{LEARN_JOB_NAMES[j]}: {ss.name}"
            bl_section("learnw_block{j}", "{block_title}  {have} / {total}{mark}", open)
            job_open[key] = open
            ry += u(22.0)
            if (!open) {
                continue
            }
            var col = 0
            for (k in range(22)) {
                let aid = ss.slots[k]
                if (aid == 0) {
                    continue
                }
                SetCursorScreenPos(ImVec2(x + u(14.0) + float(col) * cw, ry))
                var on = learned_bit(unit, j, k)
                let name = ability_name_w(aid)
                let caption = on != learned_bit(saved_u, j, k) ? "{name} *" : name
                if (bl_option("learnw_{j}_{k}", caption, on)) {
                    set_learned_bit(unit, j, k, on)
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

    def override draw_scene(x, y, w, h : float) : void {
        let tw = u(120.0)
        SetCursorScreenPos(ImVec2(x + u(8.0), y + u(6.0)))
        if (bl_radio_button("tabw_field", "Field", ICON_FIELD, tw, BND_CORNER_RIGHT, scene_tab == 0)) {
            scene_tab = 0
        }
        SetCursorScreenPos(ImVec2(x + u(8.0) + tw, y + u(6.0)))
        if (bl_radio_button("tabw_chart", "Chart", ICON_CHART, tw, BND_CORNER_LEFT, scene_tab == 1)) {
            scene_tab = 1
        }
        let ty = y + u(32.0)
        if (scene_tab == 0) {
            self->field_view(x, ty, w, y + h - ty)
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
        let iso = self->has_iso()
        for (un in units) {
            // standing: the front frame faces down-left, the back one
            // up-left; the right ones mirrored
            let f = facing_to_field(un.facing)
            let vf = field_view_facing(field_map, field, f)
            let spr = iso ? psp_unit_sprite(shell_renderer(), un.sheet, un.palette, stand_frame_w(un.sheet, vf == 1 || vf == 2),
                vf >= 2) : -1
            fu |> push(FieldUnit(name = un.name, x = un.x, y = un.y, facing = f, team = un.team,
                alive = un.hp > 0, sprite = spr, sprite_scale = 0.75))
        }
        let bar = u(28.0)
        // the tiles in reach of the Attack tab's action (reach_w: the range
        // and the height limit of the weapon / ability)
        var reach : array<bool>
        self->make_actions()
        if (selected >= 0 && selected < length(units) && length(actions) > 0) {
            let f <- action_w(units[selected], units[selected], actions[clamp(action, 0, length(actions) - 1)],
                SideW.Front)
            reach |> resize(field_map.w * field_map.h)
            for (ty in range(field_map.h)) {
                for (tx in range(field_map.w)) {
                    reach[ty * field_map.w + tx] = reach_w(units[selected], f, map_w, tx, ty, false).ok
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
            recompute_unit_w(units[input.moved])
        }
        var tr = input.turn
        let bt_turn = field_bar(field, x + u(8.0), y + h - bar + u(4.0))
        if (bt_turn != 0) {
            tr = bt_turn
        }
        if (tr != 0 && selected >= 0) {
            units[selected].facing = (units[selected].facing + (tr > 0 ? 1 : 3)) & 3
            recompute_unit_w(units[selected])
        }
    }

    def override draw_calc(x, y, w, h : float) : void {
        SetCursorScreenPos(ImVec2(x, y))
        if (length(units) == 0) {
            bl_label(message, ICON_TURNS)
            return
        }
        let tw = u(104.0)
        let tabs = fixed_array<string>("Turn order", "Attack", "Explore", "Units", "Items", "Abilities")
        let icons = fixed_array<int>(ICON_TURNS, ICON_ATTACK, ICON_CHART, ICON_UNIT, ICON_INSPECTOR, ICON_CALC)
        for (k in range(6)) {
            SetCursorScreenPos(ImVec2(x + tw * float(k), y))
            let corner = k == 0 ? BND_CORNER_RIGHT : (k == 5 ? BND_CORNER_LEFT : BND_CORNER_ALL)
            if (bl_radio_button("tabw_calc{k}", tabs[k], icons[k], tw, corner, calc_tab == k)) {
                calc_tab = k
                table_pick = -1
            }
        }
        let ty = y + u(28.0)
        if (calc_tab == 1) {
            self->attack_view(x, ty, w, y + h - ty)
        } elif (calc_tab == 2) {
            let att = units[clamp(selected, 0, length(units) - 1)]
            let msg = explore_view(explore, x, ty, w, y + h - ty, state_path, $(key) {
                var v : Value
                return unit_param_w(att, key, v)
            }, $(s; var t) {
                return self->explore_points(s, t)
            })
            if (msg != "") {
                message = msg
                log_line(msg)
            }
        } elif (calc_tab == 3) {
            self->unit_table(x, ty, w, y + h - ty)
        } elif (calc_tab == 4) {
            self->items_view(x, ty, w, y + h - ty)
        } elif (calc_tab == 5) {
            self->abilities_view(x, ty, w, y + h - ty)
        } else {
            self->turn_view(x, ty, w, y + h - ty)
        }
    }

    // the selected unit's actions: Attack and its skillsets' (or all)
    def make_actions() : void {
        if (actions_of == selected * 2 + (all_abilities ? 1 : 0) && length(actions) > 0) {
            return
        }
        actions_of = selected * 2 + (all_abilities ? 1 : 0)
        actions |> clear()
        if (selected < 0 || selected >= length(units)) {
            return
        }
        if (all_abilities) {
            actions |> push(ATTACK_W)
            for (aid in range(1, ABILITY_COUNT_W)) {
                let k = read_ability_w(aid).kind
                let jump = k == AB_JUMP && aid != 394
                if ((k == AB_NORMAL || k == AB_ITEM || k == AB_CHARGE || k == AB_THROW || k == AB_JUMP) && !jump &&
                        ability_name_w(aid) != "") {
                    actions |> push(aid)
                }
            }
        } else {
            actions <- unit_actions(units[selected], false)
        }
        action = 0
        let want = gui_arg("--action", "")
        for (k in range(length(actions))) {
            if (want != "" && action_name_w(actions[k]) == want) {
                action = k
            }
        }
    }

    def pick_target() : void {
        if (target >= 0 && target < length(units) && target != selected) {
            return
        }
        target = -1
        var best = 1000
        for (i in range(length(units))) {
            // the other side: enemies against the player and the guests
            let foe = (units[i].team == TEAM_ENEMY) != (units[selected].team == TEAM_ENEMY)
            if (selected >= 0 && i != selected && foe && units[i].hp > 0) {
                let d = abs(units[i].x - units[selected].x) + abs(units[i].y - units[selected].y)
                if (d < best) {
                    best = d
                    target = i
                }
            }
        }
    }

    // the forecast and how it is made (fftwotl_attack.das)
    def attack_view(x, y, w, h : float) : void {
        self->pick_target()
        if (selected < 0 || target < 0) {
            SetCursorScreenPos(ImVec2(x, y))
            bl_label("Select an attacker and right-click a target on the field", ICON_INFO)
            return
        }
        self->make_actions()
        let att = units[selected]
        let tgt = units[target]
        let auto_side = side_of_w(att, tgt)
        let side = side_choice == 1 ? SideW.Front : (side_choice == 2 ? SideW.Side : (side_choice == 3 ? SideW.Back : auto_side))
        let aid = length(actions) > 0 ? actions[clamp(action, 0, length(actions) - 1)] : ATTACK_W
        let f <- action_w(att, tgt, aid, side)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        SetCursorScreenPos(ImVec2(x, y))
        let head = "{att.name} -> {tgt.name}:"
        bl_label(head, ICON_ATTACK)
        let lx = x + text_width(head) + u(30.0)
        var names : array<string>
        for (a in actions) {
            names |> push(action_name_w(a))
        }
        SetCursorScreenPos(ImVec2(lx, y))
        var cur = clamp(action, 0, max(0, length(actions) - 1))
        if (length(names) > 0 && bl_choice("actionw_choice", names, cur, u(220.0))) {
            action = cur
        }
        SetCursorScreenPos(ImVec2(lx + u(226.0), y))
        if (bl_option("actionw_all", "Every ability", all_abilities)) {
            actions_of = -1
        }
        let ry2 = y + u(26.0)
        SetCursorScreenPos(ImVec2(x + u(22.0), ry2))
        bl_label("Side:")
        SetCursorScreenPos(ImVec2(x + u(70.0), ry2))
        var sides <- ["Auto ({SIDE_W_NAMES[int(auto_side)]})", "Front", "Side", "Back"]
        bl_choice("sidew_choice", sides, side_choice, u(156.0))
        var ry = y + u(54.0)
        let col = x + u(150.0)
        let what = f.mp_effect ? (f.damage < 0 ? "MP restored" : "MP damage") : (f.damage < 0 ? "HP restored" : "damage")
        let note = f.note != "" ? ", {f.note}" : ""
        let big = f.unsupported ? "Not computed: {f.note}" : "Forecast: {abs(f.damage)} {what}, {f.hit}% hit{note}   ({f.name})"
        text_at_baseline(x + u(8.0), ry + u(15.0), big, fg)
        ry += u(21.0)
        if (!f.unsupported) {
            let rng = f.dmg_min != f.dmg_max ? ", {abs(f.dmg_min)}..{abs(f.dmg_max)}" : ""
            let crit = f.crit > 0 ? ", critical ~{f.crit}% (+0..99% of XA)" : ""
            text_at_baseline(x + u(8.0), ry + u(15.0), "Average {fmt(":.1f", f.expected)} per use{rng}{crit}", fg)
            ry += u(21.0)
        }
        text_at_baseline(x + u(8.0), ry + u(15.0),
            "Matches 291 of the game's own forecasts (Attack, magicks, statuses, Arts of War, Throw, Jump, ...); the rest: formulas.md", 0xe0a060ffu)
        ry += u(28.0)
        // Arithmeticks (the attacker's set 21, or every ability): the units
        // hit and what the magick does to each
        let arith = att.primary == 21 || att.secondary == 21 || all_abilities
        var arith_rows : array<tuple<string; string>>
        if (arith) {
            let spells <- arith_spells_w()
            SetCursorScreenPos(ImVec2(x + u(8.0), ry))
            bl_label("Arithmeticks:")
            var algs <- [for (a in ARITH_ALGS); a]
            var nums <- [for (n in ARITH_NUMS); n]
            var snames <- [for (sp in spells); ability_name_w(sp)]
            SetCursorScreenPos(ImVec2(x + u(116.0), ry))
            bl_choice("arithw_alg", algs, arith_alg, u(90.0))
            SetCursorScreenPos(ImVec2(x + u(210.0), ry))
            bl_choice("arithw_num", nums, arith_num, u(130.0))
            SetCursorScreenPos(ImVec2(x + u(344.0), ry))
            arith_spell = clamp(arith_spell, 0, max(length(spells) - 1, 0))
            bl_choice("arithw_spell", snames, arith_spell, u(140.0))
            ry += u(28.0)
            if (length(spells) > 0) {
                let sp = spells[arith_spell]
                let hit_ids <- arith_targets_w(units, arith_alg, arith_num, map_w)
                if (length(hit_ids) == 0) {
                    arith_rows |> push(("Arithmeticks", "no unit fits"))
                }
                for (i in hit_ids) {
                    let t = units[i]
                    let af <- action_w(att, t, sp, side_of_w(att, t))
                    let v = arith_value_w(t, arith_alg, map_w)
                    let amount = af.damage == 0 ? "" : "{abs(af.damage)} {af.damage < 0 ? "healed" : "damage"}, "
                    let anote = af.note != "" ? ", {af.note}" : ""
                    arith_rows |> push((t.name, "{ARITH_ALGS[arith_alg]} {v}: {amount}{af.hit}%{anote}"))
                }
            }
        }
        var rows : array<tuple<string; string>>
        if (f.formula != 0) {
            let wn = f.weapon != "" ? ", {f.weapon}" : ""
            rows |> push(("Formula", "0x{fmt(":02x", f.formula)}{wn}"))
        }
        if (length(f.mods) > 0) {
            rows |> push(("Damage", join(f.mods, "; ")))
        }
        rows |> push(("Hit", "{join(f.hit_mods, "; ")} -> {f.hit}%"))
        rows |> push(("Zodiac", "{att.zodiac} vs {tgt.zodiac}: {ZODIAC_REL_NAMES[f.zodiac]}"))
        let rr = reach_w(att, f, map_w, tgt.x, tgt.y, tgt.high)
        rows |> push(("Reach", "{rr.ok ? "in reach" : "OUT OF REACH"}: {rr.why}"))
        if (f.mp_cost != 0 || f.ct != 0) {
            rows |> push(("Cost", "MP {f.mp_cost}, charge {f.ct} ticks"))
        }
        // the target's reaction and its counter-attack
        let re <- reaction_w(att, tgt, f)
        if (re.id != 0) {
            let when = re.why != "" ? " ({re.why})" : ""
            let roll = re.chance < 100 ? " on Brave {re.chance}%" : ""
            rows |> push(("Reaction", re.triggers ? "{re.name}: {re.effect}{roll}{when}" : "{re.name}: does not trigger{when}"))
            if (re.counter) {
                let cf & = unsafe(re.counter_fight)
                rows |> push(("Counter", "{tgt.name} -> {att.name}: {cf.damage} damage, {cf.hit}% hit ({join(cf.mods, "; ")})"))
            }
        } else {
            rows |> push(("Reaction", "none"))
        }
        if (length(arith_rows) > 0) {
            // the Arithmeticks' units first
            for (r in rows) {
                arith_rows |> push(r)
            }
            rows <- arith_rows
        }
        // the rows scroll when the panel is low
        SetCursorScreenPos(ImVec2(x, ry))
        BeginChild("wotl_attack_rows", ImVec2(w, max(u(40.0), y + h - ry)), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        var yy = GetCursorScreenPos().y
        for (r in rows) {
            text_at_baseline(x + u(8.0), yy + u(15.0), r._0, dim)
            text_at_baseline(col, yy + u(15.0), r._1, fg)
            yy += u(21.0)
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }

    def turn_view(x, y, w, h : float) : void {
        let turns <- predict_turns_w(units, turns_ahead)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let nw = u(180.0)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Turn order  (a tick adds Speed; CT 100+ acts; after a turn CT = min(60, CT - 100 / 80 / 60))",
            ICON_TURNS, w - nw - u(8.0))
        SetCursorScreenPos(ImVec2(x + w - nw - u(4.0), y))
        var ahead = float(turns_ahead)
        if (bl_number("turnsw_ahead", "Turns ahead", ahead, 0.1, 0, nw)) {
            turns_ahead = clamp(int(round(ahead)), 1, 200)
        }
        let row_h = u(21.0)
        let cols = fixed_array<float>(12.0, 44.0, 150.0, 270.0, 340.0, 400.0)
        let heads = fixed_array<string>("#", "Unit", "Job", "In ticks", "Turn", "CT", "Ends with")
        var ry = y + u(26.0)
        for (k in range(6)) {
            text_at_baseline(x + u(cols[k]), ry + u(14.0), heads[k], dim)
        }
        text_at_baseline(x + u(460.0), ry + u(14.0), heads[6], dim)
        ry += row_h
        SetCursorScreenPos(ImVec2(x, ry))
        BeginChild("wotl_turns", ImVec2(w, y + h - ry), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        var dl = GetWindowDrawList()
        var yy = GetCursorScreenPos().y
        let names = fixed_array<string>("Move + Act", "Act", "Move", "Wait")
        for (k in range(length(turns))) {
            let t = turns[k]
            let un = units[t.unit]
            SetCursorScreenPos(ImVec2(x, yy))
            if (InvisibleButton("##turnw_{k}", ImVec2(w - u(4.0), row_h))) {
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
            text_at_baseline(x + u(460.0), b, names[int(un.assumed)], dim)
            yy += row_h
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }

    def unit_table(x, y, w, h : float) : void {
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Units  (by CT)", ICON_TURNS)
        var order : array<int>
        for (i in range(length(units))) {
            order |> push(i)
        }
        sort(order) $(a, b) => units[a].ct > units[b].ct || (units[a].ct == units[b].ct && a < b)
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        let row_h = u(21.0)
        var cols : array<float>
        let names = fixed_array<string>("Unit", "Job", "Lv", "HP", "MP", "CT", "Br", "Fa", "PA", "MA", "Sp", "Mv", "Jp",
            "C-EV")
        let widths = fixed_array<float>(90.0, 100.0, 28.0, 62.0, 48.0, 38.0, 32.0, 32.0, 32.0, 32.0, 32.0, 32.0, 32.0, 40.0)
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
        BeginChild("wotl_units", ImVec2(w, y + h - ry), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        var dl = GetWindowDrawList()
        var yy = GetCursorScreenPos().y
        for (i in order) {
            let un = units[i]
            SetCursorScreenPos(ImVec2(x, yy))
            if (InvisibleButton("##roww_{i}", ImVec2(w - u(4.0), row_h))) {
                selected = i
            }
            if (i == selected) {
                *dl |> AddRectFilled(ImVec2(x, yy), ImVec2(x + w - u(4.0), yy + row_h), abgr(bt.menu_item.inner_sel), 0.0,
                    ImDrawFlags.None)
            }
            *dl |> AddRectFilled(ImVec2(x + u(2.0), yy + u(3.0)), ImVec2(x + u(6.0), yy + row_h - u(3.0)),
                abgr(side_color(un.team)), u(2.0), ImDrawFlags.None)
            let b = yy + u(15.0)
            let cells <- [un.name, un.job, "{un.level}", "{un.hp}/{un.max_hp}", "{un.mp}/{un.max_mp}", "{un.ct}",
                "{un.brave}", "{un.faith}", "{un.pa}", "{un.ma}", "{un.sp}", "{un.move}", "{un.jump}", "{un.c_ev}%"]
            for (k in range(length(cells))) {
                text_at_baseline(cols[k], b, cells[k], k == 0 ? team_text_color(un.team) : fg)
            }
            yy += row_h
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
    }

    // the game's item table (BOOT.BIN in the state's RAM): a list with a
    // name filter; a click shows the item's record
    def items_view(x, y, w, h : float) : void {
        self->table_list(x, y, w, h, true)
    }

    def abilities_view(x, y, w, h : float) : void {
        self->table_list(x, y, w, h, false)
    }

    def table_list(x, y, w, h : float; items : bool) : void {
        let fg = bt.regular.text | 0xffu
        let dim = offset_color(fg, 60)
        SetCursorScreenPos(ImVec2(x, y))
        bl_label("Name:", -1, u(52.0))
        SetCursorScreenPos(ImVec2(x + u(56.0), y))
        bl_text_field(items ? "itemsw_filter" : "abilitiesw_filter", table_filter, u(200.0))
        let lw = floor(w * 0.42)
        let filter = to_lower(to_string(table_filter))
        let ly = y + u(26.0)
        SetCursorScreenPos(ImVec2(x, ly))
        BeginChild(items ? "wotl_items" : "wotl_abilities", ImVec2(lw, y + h - ly), ImGuiChildFlags.None,
            ImGuiWindowFlags.None)
        var dl = GetWindowDrawList()
        var yy = GetCursorScreenPos().y
        let row_h = u(20.0)
        let n = items ? ITEM_COUNT_W : ABILITY_COUNT_W
        for (tid in range(1, n)) {
            let name = items ? item_name_w(tid) : ability_name_w(tid)
            if (name == "" || name == "-" || starts_with(name, "item ") || (filter != "" && find(to_lower(name), filter) < 0)) {
                continue
            }
            SetCursorScreenPos(ImVec2(x, yy))
            if (InvisibleButton("##tbl_{tid}", ImVec2(lw - u(4.0), row_h))) {
                table_pick = tid
            }
            if (tid == table_pick) {
                *dl |> AddRectFilled(ImVec2(x, yy), ImVec2(x + lw - u(4.0), yy + row_h), abgr(bt.menu_item.inner_sel), 0.0,
                    ImDrawFlags.None)
            }
            let extra = items ? KIND_W_NAMES[read_item_w(tid).kind] : "0x{fmt(":03x", tid)}"
            let icon = items && self->has_iso() ? psp_item_icon(shell_renderer(), tid) : -1
            if (icon >= 0) {
                gba_gfx_draw(icon, x + u(4.0), yy + u(2.0), u(16.0), u(16.0), 1.0)
            }
            text_at_baseline(x + u(icon >= 0 ? 24.0 : 6.0), yy + u(14.0), name, fg)
            right_w(x + lw - u(10.0), yy + u(14.0), extra, dim)
            yy += row_h
        }
        SetCursorScreenPos(ImVec2(x, yy))
        Dummy(ImVec2(1.0, u(4.0)))
        EndChild()
        if (table_pick <= 0) {
            return
        }
        var rows : array<tuple<string; string>>
        if (items) {
            let it = read_item_w(table_pick)
            rows |> push(("Item", "{it.name} (0x{fmt(":03x", table_pick)})"))
            rows |> push(("Kind", "{KIND_W_NAMES[it.kind]}, flags 0x{fmt(":02x", it.flags)}"))
            rows |> push(("Price", "{it.price} gil, level {it.level}"))
            if (is_weapon_w(it)) {
                rows |> push(("Weapon", "WP {it.wp}, evade {it.w_ev}%, range {it.reach}, formula 0x{fmt(":02x", it.formula)}"))
                rows |> push(("Attack flags", "0x{fmt(":02x", it.wflags)}{(it.wflags & 0x04) != 0 ? ", two-handable" : ""}{(it.wflags & 0x08) != 0 ? ", dual-wieldable" : ""}"))
            }
            if (it.formula != 0 && !is_weapon_w(it)) {
                rows |> push(("Use", "formula 0x{fmt(":02x", it.formula)}, X {it.x}"))
            }
            rows |> push(("Bonus", item_text_w(it)))
            if (it.inflict != 0) {
                rows |> push(("Status", inflict_text(it.inflict)))
            }
            let start = status_text(it.start)
            if (start != "-") {
                rows |> push(("Starts with", start))
            }
        } else {
            let a = read_ability_w(table_pick)
            let kinds = fixed_array<string>("-", "action", "item", "throw", "jump", "aim", "arithmetick", "reaction",
                "support", "movement")
            rows |> push(("Ability", "{a.name} (0x{fmt(":03x", table_pick)}), {kinds[a.kind & 15]}"))
            rows |> push(("Learn", "{a.jp} JP, {a.learn_rate}% chance"))
            if (a.kind == AB_NORMAL) {
                rows |> push(("Formula", "0x{fmt(":02x", a.formula)}, X {a.x}, Y {a.y}"))
                rows |> push(("Range", "{a.reach}, area {a.area}, vertical {a.vertical}"))
                rows |> push(("Cost", "MP {a.mp}, charge {a.ct} ticks"))
                rows |> push(("Element", element_text(a.element)))
                if (a.inflict != 0) {
                    rows |> push(("Status", inflict_text(a.inflict)))
                }
                rows |> push(("Flags", "0x{fmt(":02x", a.f1)} 0x{fmt(":02x", a.f2)} 0x{fmt(":02x", a.f3)} 0x{fmt(":02x", a.f4)}{(a.f4 & 0x02) != 0 ? ", evadable" : ""}{(a.f3 & 0x80) != 0 ? ", reflectable" : ""}{(a.f3 & 0x20) != 0 ? ", Silence blocks" : ""}"))
            } elif (a.kind == AB_ITEM) {
                rows |> push(("Uses", item_name_w(a.item)))
            } elif (a.kind == AB_CHARGE) {
                rows |> push(("Aim", "+{a.x}, charge {a.ct} ticks"))
            } elif (a.kind == AB_THROW) {
                rows |> push(("Throws", KIND_W_NAMES[a.throw_kind]))
            } elif (a.kind == AB_JUMP) {
                rows |> push(("Jump", "horizontal {a.jump_h}, vertical {a.jump_v}"))
            }
        }
        var ry = ly
        let tx = x + lw + u(12.0)
        for (r in rows) {
            text_at_baseline(tx, ry + u(15.0), r._0, dim)
            text_at_baseline(tx + u(100.0), ry + u(15.0), r._1, fg)
            ry += u(21.0)
        }
    }

    // the scene of the Attack tab, changed by
    // scene AAAAA vs Lezalas with Fire from back; "" or the error
    def explore_scene(s : Script; var sc : SceneW) : string {
        if (selected < 0 || selected >= length(units)) {
            selected = 0
        }
        self->pick_target()
        self->make_actions()
        var att = selected
        var tgt = target >= 0 ? target : selected
        var ability = length(actions) > 0 ? actions[clamp(action, 0, length(actions) - 1)] : ATTACK_W
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
                ability = v.text == "Attack" ? ATTACK_W : ability_id_named(v.text)
                if (ability == 0 && v.text != "Attack") {
                    return "line {a.line}: no action '{v.text}'"
                }
            } elif (a.name == "side") {
                side = clamp(int(v.num), 0, 3)
            } else {
                return "line {a.line}: scene( ) takes attacker, target, action, side - not '{a.name}'"
            }
        }
        sc = SceneW(att = units[att], tgt = units[tgt], ability = ability, side = side)
        return ""
    }

    // Explore: a parsed script -> the table of its points
    def explore_points(var s : Script; var t : ETable) : string {
        var sc = SceneW()
        try_ok(self->explore_scene(s, sc))
        return run_experiment_w(sc, s, t)
    }
}

// any field the editor changes differs from the loaded one
def private inspect_changed_w(a, b : UnitW) : bool {
    return (a.hp != b.hp || a.max_hp != b.max_hp || a.mp != b.mp || a.max_mp != b.max_mp || a.ct != b.ct ||
        a.x != b.x || a.y != b.y || a.facing != b.facing || a.job_id != b.job_id || a.level != b.level ||
        a.exp != b.exp || a.brave != b.brave || a.faith != b.faith || a.primary != b.primary ||
        a.secondary != b.secondary || a.reaction != b.reaction || a.support != b.support || a.movement != b.movement ||
        "{a.raw} {a.items} {a.status} {a.learned}" != "{b.raw} {b.items} {b.status} {b.learned}")
}
