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

let ROSTER_LOAD = 1
let ROSTER_EXPORT = 2

// the path fields and buttons; action: ROSTER_* pressed (0 none);
// exporting - also the export path and its button. Returns the bottom y.
def source_fields(var state_path : string&; var rom_path : string&; var export_path : string&; exporting : bool;
                  x, y, w : float; var action : int&) : float {
    action = 0
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
    if (bl_tool_button("load", "Load", ICON_LOAD, w - u(12.0))) {
        action = ROSTER_LOAD
    }
    if (!exporting) {
        return yy + u(30.0)
    }
    yy += u(30.0)
    SetCursorScreenPos(ImVec2(x + u(6.0), yy))
    bl_label("Export:", -1, lw)
    SetCursorScreenPos(ImVec2(x + u(6.0) + lw, yy))
    bl_string("export_path", export_path, w - lw - u(12.0))
    yy += u(25.0)
    SetCursorScreenPos(ImVec2(x + u(6.0), yy))
    if (bl_tool_button("export", "Export state with edits", ICON_EXPORT, w - u(12.0))) {
        action = ROSTER_EXPORT
    }
    return yy + u(30.0)
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
