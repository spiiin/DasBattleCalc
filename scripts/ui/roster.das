options gen2
options indenting = 4

// The roster panel shared by the games: the files to load (state, ROM,
// optionally the export path) and one row per unit with a bar in its
// side color.
module roster shared public

require imgui
require dasimgui/imgui_boost
require bnd_const
require icons
require bl_imgui
require battle_field
require gui_common
require strings
require daslib/strings_boost

let ROSTER_LOAD = 1
let ROSTER_EXPORT = 2

// the path fields and buttons; action: ROSTER_* pressed (0 none);
// exporting - also the export path and its button. Returns the bottom y.
// On the desktop each field has "..." (the system's file dialog: a chosen
// state / ROM loads at once, a chosen export path exports), and a file
// dropped on the window goes to the state or the ROM by its extension and
// loads.
def source_fields(var state_path : string&; var rom_path : string&; var export_path : string&; exporting : bool;
                  x, y, w : float; var action : int&) : float {
    action = 0
    let picked_state = owned(gui_file_dialog_result(DIALOG_STATE))
    if (picked_state != "") {
        state_path = picked_state
        action = ROSTER_LOAD
    }
    let picked_rom = owned(gui_file_dialog_result(DIALOG_ROM))
    if (picked_rom != "") {
        rom_path = picked_rom
        action = ROSTER_LOAD
    }
    let picked_export = owned(gui_file_dialog_result(DIALOG_EXPORT))
    if (picked_export != "" && exporting) {
        export_path = picked_export
        action = ROSTER_EXPORT
    }
    let dropped = owned(gui_take_dropped())
    if (dropped != "") {
        let kind = dropped_kind(dropped)
        if (kind == 1) {
            state_path = dropped
            action = ROSTER_LOAD
        } elif (kind == 2) {
            rom_path = dropped
            action = ROSTER_LOAD
        }
    }
    let lw = u(54.0)
    let dialogs = gui_has_file_dialog()
    let bw = dialogs ? u(26.0) : 0.0
    let fw = w - lw - u(12.0) - bw
    var yy = y
    path_row("State:", "state", state_path, DIALOG_STATE, false, "Save states", STATE_EXTS, x, yy, lw, fw, bw)
    yy += u(23.0)
    path_row("ROM:", "rom", rom_path, DIALOG_ROM, false, "ROMs and discs", ROM_EXTS, x, yy, lw, fw, bw)
    yy += u(25.0)
    SetCursorScreenPos(ImVec2(x + u(6.0), yy))
    if (bl_tool_button("load", "Load", ICON_LOAD, w - u(12.0))) {
        action = ROSTER_LOAD
    }
    if (!exporting) {
        return yy + u(30.0)
    }
    yy += u(30.0)
    path_row("Export:", "export", export_path, DIALOG_EXPORT, true, "Save states", STATE_EXTS, x, yy, lw, fw, bw)
    yy += u(25.0)
    SetCursorScreenPos(ImVec2(x + u(6.0), yy))
    if (bl_tool_button("export", "Export state with edits", ICON_EXPORT, w - u(12.0))) {
        action = ROSTER_EXPORT
    }
    return yy + u(30.0)
}

// a copy of a native function's text: it points at a buffer the next
// call overwrites
def private owned(s : string) : string {
    return s == "" ? "" : "{s}"
}

// the file dialogs' requests (gui_file_dialog ids) and their filters
let private DIALOG_STATE = 1
let private DIALOG_ROM = 2
let private DIALOG_EXPORT = 3
let private STATE_EXTS = "State;ppst"
let private ROM_EXTS = "gba;nds;zip;cue;bin;iso"

// a dropped file by its extension: 1 a save state (BizHawk .State,
// PPSSPP .ppst), 2 a ROM or a disc, 0 neither
def private dropped_kind(path : string) : int {
    let dot = rfind(path, ".")
    let ext = dot >= 0 ? to_lower(slice(path, dot + 1)) : ""
    if (find_index(split(to_lower(STATE_EXTS), ";"), ext) >= 0) {
        return 1
    }
    return find_index(split(ROM_EXTS, ";"), ext) >= 0 ? 2 : 0
}

// a label, the path field and its "..." (the system's file dialog; bw 0:
// there is none)
def private path_row(caption, id : string; var path : string&; dialog : int; save : bool; title, exts : string;
                     x, yy, lw, fw, bw : float) {
    SetCursorScreenPos(ImVec2(x + u(6.0), yy))
    bl_label(caption, -1, lw)
    SetCursorScreenPos(ImVec2(x + u(6.0) + lw, yy))
    bl_string("{id}_path", path, fw)
    if (bw > 0.0) {
        SetCursorScreenPos(ImVec2(x + u(6.0) + lw + fw, yy))
        if (bl_tool_button("{id}_pick", "...", -1, bw)) {
            gui_file_dialog(dialog, save, title, exts, path)
        }
    }
}

let ROSTER_ROW_H = 20.0

// one unit: the side bar, an icon and the text; true when clicked
def roster_row(i : int; selected : bool; side : int; text : string; x, y, w : float) : bool {
    let row_h = u(ROSTER_ROW_H)
    var dl = GetWindowDrawList()
    SetCursorScreenPos(ImVec2(x + u(2.0), y))
    let clicked = InvisibleButton("##unit{i}", ImVec2(w - u(4.0), row_h))
    if (selected) {
        *dl |> AddRectFilled(ImVec2(x + u(2.0), y), ImVec2(x + w - u(2.0), y + row_h),
            abgr(bt.menu_item.inner_sel), u(3.0), ImDrawFlags.None)
    } elif (IsItemHovered()) {
        *dl |> AddRectFilled(ImVec2(x + u(2.0), y), ImVec2(x + w - u(2.0), y + row_h),
            abgr(0xffffff18u), 0.0, ImDrawFlags.None)
    }
    // the team: a bar in its color, the name tinted
    *dl |> AddRectFilled(ImVec2(x + u(3.0), y + u(3.0)), ImVec2(x + u(7.0), y + row_h - u(3.0)),
        abgr(side_color(side)), u(2.0), ImDrawFlags.None)
    let color = selected ? 0xffffffffu : team_text_color(side)
    icon_label_value(x + u(10.0), y, w - u(8.0), row_h, side == TEAM_ENEMY ? ICON_ENEMY : ICON_UNIT, color, false, text)
    return clicked
}
