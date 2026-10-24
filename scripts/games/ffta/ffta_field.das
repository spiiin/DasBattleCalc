options gen2
options indenting = 4

// The battle field, top-down: the map tiles (shade and number = height)
// and the units as discs in their side color with an arrow for the
// facing. Click selects a unit (and makes it the attacker), right click
// makes it the attack target, dragging moves it to a free tile, Q / E
// turn the selected unit. Changes stay in the calculator (the state is
// not written).
module ffta_field shared public

require imgui
require dasimgui/imgui_boost
require math
require strings
require ../../ui/bnd_const.das
require ../../ui/icons.das
require ../../ui/bl_imgui.das
require ffta_battle
require ffta_attack
require ffta_gfx
require gba_mem

// by team (TEAM_*): player, enemy, guest, judge
def side_color(side : int) : uint {
    return side == TEAM_PLAYER ? 0x3f86ffffu : (side == TEAM_ENEMY ? 0xe8423cffu : (side == TEAM_GUEST ? 0x3fbf5fffu :
        0xe6b422ffu))
}

// a name in a list, in the team's color (light: on the grey panels)
def team_text_color(side : int) : uint {
    return side == TEAM_PLAYER ? 0xd8e6ffffu : (side == TEAM_ENEMY ? 0xffc4c0ffu : (side == TEAM_GUEST ? 0xc8f0d0ffu :
        0xfff0b0ffu))
}

// what the user did on the field this frame
struct FieldInput {
    select : int = -1               // clicked unit
    target : int = -1               // right-clicked unit
    changed : bool = false          // a unit moved or turned
}

struct FieldState {
    drag : int = -1                 // unit being dragged
    cell : float = 0.0              // tile size before the UI scale; 0: fit
}

let FIELD_CELL_MIN = 6.0
let FIELD_CELL_MAX = 160.0

def unit_at(units : array<BattleUnit>; x, y : int) : int {
    for (i in range(length(units))) {
        if (units[i].x == x && units[i].y == y && units[i].hp > 0) {
            return i
        }
    }
    for (i in range(length(units))) {
        if (units[i].x == x && units[i].y == y) {
            return i
        }
    }
    return -1
}

// facing 0 +y, 1 -x, 2 -y, 3 +x; on screen x goes right and y down, so
// facing + 1 turns clockwise
def turn(var u : BattleUnit; clockwise : bool) {
    u.facing = (u.facing + (clockwise ? 1 : 3)) & 3
    u.position = "{u.x}, {u.y}, facing {FACING_NAMES[u.facing]}"
}

def private tile_color(height, lo, hi : int) : uint {
    let t = hi > lo ? float(height - lo) / float(hi - lo) : 0.5
    let v = uint(70.0 + t * 110.0)
    return (v << 24u) | ((v + 8u) << 16u) | ((v - 6u) << 8u) | 0xffu
}

def draw_field(m : BattleMap; var units : array<BattleUnit>; selected, target, attacker : int; var st : FieldState;
               x, y, w, h : float) : FieldInput {
    var res = FieldInput()
    if (m.w == 0 || m.h == 0) {
        SetCursorScreenPos(ImVec2(x + u(12.0), y + u(12.0)))
        bl_label("No battle map in this state", ICON_INFO)
        return res
    }
    // the tile size is the user's (mouse wheel); until then it fits the view
    let fit = max(floor(min(w / float(m.w), h / float(m.h))), 2.0)
    SetCursorScreenPos(ImVec2(x, y))
    BeginChild("ffta_field_view", ImVec2(w, h), ImGuiChildFlags.None,
        ImGuiWindowFlags.HorizontalScrollbar | ImGuiWindowFlags.NoScrollWithMouse)
    let io & = unsafe(GetIO())
    let wheel = IsWindowHovered() ? io.MouseWheel : 0.0
    var cell = st.cell > 0.0 ? floor(u(st.cell)) : fit
    let org = GetCursorScreenPos()                    // already moved by the scroll
    let avail = GetContentRegionAvail()
    var ox = org.x + max(0.0, floor((avail.x - cell * float(m.w)) * 0.5))
    var oy = org.y + max(0.0, floor((avail.y - cell * float(m.h)) * 0.5))
    if (wheel != 0.0) {
        // zoom around the mouse: the map point under it stays in place
        let mp0 = GetMousePos()
        let fx = (mp0.x - ox) / cell
        let fy = (mp0.y - oy) / cell
        // from the stored size, not the rounded pixels: at 6 px a step of
        // 15 % rounds back down to 6 and the zoom would stick
        let base = st.cell > 0.0 ? st.cell : cell / u(1.0)
        st.cell = clamp(base * (wheel > 0.0 ? 1.15 : 1.0 / 1.15), FIELD_CELL_MIN, FIELD_CELL_MAX)
        let nc = floor(u(st.cell))
        SetScrollX(max(0.0, GetScrollX() + fx * (nc - cell)))
        SetScrollY(max(0.0, GetScrollY() + fy * (nc - cell)))
        cell = nc
        ox = org.x + max(0.0, floor((avail.x - cell * float(m.w)) * 0.5))
        oy = org.y + max(0.0, floor((avail.y - cell * float(m.h)) * 0.5))
    }
    var lo = 255
    var hi = 0
    for (v in m.height) {
        if (v > 0) {
            lo = min(lo, v)
            hi = max(hi, v)
        }
    }
    var dl = GetWindowDrawList()
    let fg = bt.regular.text | 0xffu
    // tiles: shade by height, the height number, a mark for flagged tiles
    for (ty in range(m.h)) {
        for (tx in range(m.w)) {
            let hgt = m.height[ty * m.w + tx]
            if (hgt == 0) {
                continue
            }
            let px = ox + float(tx) * cell
            let py = oy + float(ty) * cell
            let water = (m.flags[ty * m.w + tx] & 2) != 0
            let col = water ? 0x3a6a9affu : tile_color(hgt, lo, hi)
            *dl |> AddRectFilled(ImVec2(px, py), ImVec2(px + cell - 1.0, py + cell - 1.0), abgr(col), 0.0, ImDrawFlags.None)
            if (cell >= u(22.0)) {
                text_at_baseline(px + u(2.0), py + u(12.0), "{hgt}", 0x00000070u)
            }
        }
    }
    // tiles the attacker can hit with Fight: an orange frame
    if (attacker >= 0 && attacker < length(units) && st.drag < 0) {
        let att = units[attacker]
        for (ty in range(m.h)) {
            for (tx in range(m.w)) {
                var why = ""
                if (can_fight(m, att, tx + m.x0, ty + m.y0, why)) {
                    let px = ox + float(tx) * cell
                    let py = oy + float(ty) * cell
                    *dl |> AddRectFilled(ImVec2(px, py), ImVec2(px + cell - 1.0, py + cell - 1.0), abgr(0xffa03050u),
                        0.0, ImDrawFlags.None)
                    *dl |> AddRect(ImVec2(px + 1.0, py + 1.0), ImVec2(px + cell - 2.0, py + cell - 2.0),
                        abgr(0xffa030ffu), 0.0, ImDrawFlags.None, u(1.5))
                }
            }
        }
    }
    // units, top rows first: a sprite overlaps the row above it
    let r = cell * 0.4
    var order <- [for (i in range(length(units))); i]
    sort(order) $(a, b) => units[a].y < units[b].y || (units[a].y == units[b].y && units[a].x < units[b].x)
    for (i in order) {
        if (i == st.drag) {
            continue
        }
        let cx = ox + (float(units[i].x - m.x0) + 0.5) * cell
        let cy = oy + (float(units[i].y - m.y0) + 0.5) * cell
        draw_unit(dl, units[i], cx, cy, r, i == selected, i == target)
    }
    // input over the whole grid
    SetCursorScreenPos(ImVec2(ox, oy))
    InvisibleButton("ffta_field", ImVec2(cell * float(m.w), cell * float(m.h)),
        ImGuiButtonFlags.MouseButtonLeft | ImGuiButtonFlags.MouseButtonRight)
    let mp = GetMousePos()
    let mx = int(floor((mp.x - ox) / cell)) + m.x0
    let my = int(floor((mp.y - oy) / cell)) + m.y0
    let under = unit_at(units, mx, my)
    let hovered = IsItemHovered()
    if (hovered && IsMouseClicked(ImGuiMouseButton.Left, false) && under >= 0) {
        res.select = under
        st.drag = under
    }
    if (hovered && IsMouseClicked(ImGuiMouseButton.Right, false) && under >= 0) {
        res.target = under
    }
    if (st.drag >= 0) {
        let d = st.drag
        if (IsMouseDown(ImGuiMouseButton.Left)) {
            draw_unit(dl, units[d], mp.x, mp.y, r, true, d == target)
        } else {
            let free = under < 0 || under == d
            if (tile_height(m, mx, my) > 0 && free && (mx != units[d].x || my != units[d].y)) {
                units[d].x = mx
                units[d].y = my
                units[d].position = "{mx}, {my}, facing {FACING_NAMES[units[d].facing]}"
                res.changed = true
            }
            st.drag = -1
        }
    }
    if (hovered && selected >= 0 && selected < length(units)) {
        if (IsKeyPressed(ImGuiKey.Q, false)) {
            turn(units[selected], false)
            res.changed = true
        }
        if (IsKeyPressed(ImGuiKey.E, false)) {
            turn(units[selected], true)
            res.changed = true
        }
    }
    if (hovered && st.drag < 0 && tile_height(m, mx, my) > 0) {
        let who = under >= 0 ? "  {units[under].name}" : ""
        bl_tooltip("{mx}, {my}  height {tile_height(m, mx, my)}{who}")
    }
    EndChild()
    return res
}

// a disc in the side color, the facing arrow, two letters of the name;
// white ring: selected, orange ring: attack target. With the sprites from
// the ROM: the sprite standing on a shadow in the side color.
def draw_unit(var dl : ImDrawList?; un : BattleUnit; cx, cy, r : float; sel, tgt : bool) {
    let col = un.hp > 0 ? side_color(team(un)) : 0x707070ffu
    let dx = float(DIR_X[un.facing & 3])
    let dy = float(DIR_Y[un.facing & 3])
    let sprite = unit_sprite(un)
    if (sprite >= 0) {
        draw_unit_sprite(dl, un, sprite, col, cx, cy, r, sel, tgt)
        return
    }
    // arrow: a triangle out of the disc in the facing direction
    let tip = ImVec2(cx + dx * r * 1.45, cy + dy * r * 1.45)
    let b1 = ImVec2(cx + dx * r * 0.7 - dy * r * 0.55, cy + dy * r * 0.7 + dx * r * 0.55)
    let b2 = ImVec2(cx + dx * r * 0.7 + dy * r * 0.55, cy + dy * r * 0.7 - dx * r * 0.55)
    *dl |> AddTriangleFilled(tip, b1, b2, abgr(0xf0f0f0ffu))
    *dl |> AddCircleFilled(ImVec2(cx, cy), r, abgr(col), 24)
    if (tgt) {
        *dl |> AddCircle(ImVec2(cx, cy), r + u(3.0), abgr(0xffa030ffu), 24, u(2.5))
    }
    if (sel) {
        *dl |> AddCircle(ImVec2(cx, cy), r, abgr(0xffffffffu), 24, u(2.0))
    }
    let short = length(un.name) > 2 ? slice(un.name, 0, 2) : un.name
    text_at_baseline(cx - text_width(short) * 0.5, cy + u(5.0), short, 0xffffffffu)
}

def private draw_unit_sprite(var dl : ImDrawList?; un : BattleUnit; sprite : int; col : uint; cx, cy, r : float; sel, tgt : bool) {
    let dx = float(DIR_X[un.facing & 3])
    let dy = float(DIR_Y[un.facing & 3])
    // the feet a little below the tile center; a human (16 px wide) is
    // about a tile wide
    let fy = cy + r * 0.45
    let shadow = ImVec2(r * 0.95, r * 0.45)
    *dl |> AddEllipseFilled(ImVec2(cx, fy), shadow, abgr((col & 0xffffff00u) | 0xb0u), 0.0, 24)
    let tip = ImVec2(cx + dx * r * 1.35, fy + dy * r * 0.75)
    let b1 = ImVec2(cx + dx * r * 0.9 - dy * r * 0.35, fy + dy * r * 0.42 + dx * r * 0.2)
    let b2 = ImVec2(cx + dx * r * 0.9 + dy * r * 0.35, fy + dy * r * 0.42 - dx * r * 0.2)
    *dl |> AddTriangleFilled(tip, b1, b2, abgr(0xf0f0f0ffu))
    if (tgt) {
        *dl |> AddEllipse(ImVec2(cx, fy), ImVec2(shadow.x + u(3.0), shadow.y + u(3.0)), abgr(0xffa030ffu), 0.0, 24, u(2.5))
    }
    if (sel) {
        *dl |> AddEllipse(ImVec2(cx, fy), shadow, abgr(0xffffffffu), 0.0, 24, u(2.0))
    }
    let s = r * 2.5 / 16.0
    let w = gba_gfx_width(sprite) * s
    let h = gba_gfx_height(sprite) * s
    gba_gfx_draw(sprite, cx - gba_gfx_origin_x(sprite) * s, fy - gba_gfx_origin_y(sprite) * s, w, h,
        un.hp > 0 ? 1.0 : 0.45)
}
