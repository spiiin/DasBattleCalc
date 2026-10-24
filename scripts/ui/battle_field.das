options gen2
options indenting = 4

// A battle field in the isometric view of the Tactics games (screen x =
// 16 (x - y), y = 8 (x + y) - 8 height in game pixels): the map tiles
// (shade and number = height) and the units - a sprite (a gba_gfx handle
// from the game), or a disc in the side color with an arrow for the facing.
// Click selects a unit, right click makes it the target, dragging asks to
// move it to a free tile, Q / E ask to turn the selected unit. The field
// changes nothing itself: the game applies what FieldInput asks for.
module battle_field shared public

require imgui
require dasimgui/imgui_boost
require math
require strings
require gba_mem
require bnd_const
require icons
require bl_imgui
require ../core/teams.das public

// The map: tiles of w x h from (x0, y0) in the game's coordinates;
// height 0 - no tile; water - a unit there stands one lower.
struct FieldMap {
    w : int
    h : int
    x0 : int
    y0 : int
    height : array<int>
    water : array<bool>
    shown_shift : int               // the game's height = height + shown_shift (0 must mean "no tile")
}

// facing 0 +y, 1 -x, 2 -y, 3 +x (FFTA's numbering; a game maps its own)
struct FieldUnit {
    name : string
    x : int
    y : int
    facing : int
    team : int                      // TEAM_*
    alive : bool = true
    sprite : int = -1               // gba_gfx handle, -1: the disc
    sprite_dy : float = 0.0         // game pixels to put the frame's origin below the tile center
}

// what the user did on the field this frame
struct FieldInput {
    select : int = -1               // clicked unit
    target : int = -1               // right-clicked unit
    moved : int = -1                // a unit dropped on a free tile...
    move_x : int = 0                // ...at these game coordinates
    move_y : int = 0
    turn : int = 0                  // the selected unit: -1 counterclockwise, 1 clockwise
}

struct FieldState {
    drag : int = -1                 // unit being dragged
    cell : float = 0.0              // half a tile's width (16 game pixels) before the UI scale; 0: fit
}

let FIELD_CELL_MIN = 6.0
let FIELD_CELL_MAX = 160.0
let FIELD_DIR_X = fixed_array<int>(0, -1, 0, 1)
let FIELD_DIR_Y = fixed_array<int>(1, 0, -1, 0)
let FIELD_FACING_NAMES = fixed_array<string>("+y", "-x", "-y", "+x")

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

// the unit on a tile: a living one first
def field_unit_at(units : array<FieldUnit>; x, y : int) : int {
    for (i in range(length(units))) {
        if (units[i].x == x && units[i].y == y && units[i].alive) {
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

def field_height(m : FieldMap; x, y : int) : int {
    let tx = x - m.x0
    let ty = y - m.y0
    return tx >= 0 && ty >= 0 && tx < m.w && ty < m.h ? m.height[ty * m.w + tx] : 0
}

// a flat map of w x h at height 1 (no heights known)
def flat_field(w, h : int) : FieldMap {
    var m = FieldMap(w = w, h = h)
    m.height |> resize(w * h)
    m.water |> resize(w * h)
    for (i in range(w * h)) {
        m.height[i] = 1
    }
    return <- m
}

def private tile_color(height, lo, hi : int) : uint {
    let t = hi > lo ? float(height - lo) / float(hi - lo) : 0.5
    let v = uint(70.0 + t * 110.0)
    return (v << 24u) | ((v + 8u) << 16u) | ((v - 6u) << 8u) | 0xffu
}

// the screen geometry of the field: cell = half a tile's width
struct private IsoView {
    ox : float
    oy : float
    cell : float
    rows : float                    // m.h: shifts x - y to the right
    top : float                     // room above the highest tile, in cells (heights from base)
    base : int                      // the height the walls go down to
}

// the center of the top face of tile (tx, ty) at height hgt (map coords)
def private iso_point(v : IsoView; tx, ty : int; hgt : float) : float2 {
    return float2(v.ox + (float(tx - ty) + v.rows) * v.cell,
        v.oy + (float(tx + ty) * 0.5 + v.top + 0.5 - (hgt - float(v.base)) * 0.5) * v.cell)
}

// screen direction of a facing: +x down-right, +y down-left
def private facing_dir(facing : int) : float2 {
    let dx = float(FIELD_DIR_X[facing & 3])
    let dy = float(FIELD_DIR_Y[facing & 3])
    let d = float2(dx - dy, (dx + dy) * 0.5)
    return d / length(d)
}

def private inside_convex(p : float2; pts : array<float2>) : bool {
    var sign = 0.0
    let n = length(pts)
    for (i in range(n)) {
        let a = pts[i]
        let b = pts[(i + 1) % n]
        let c = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        if (c != 0.0) {
            if (sign == 0.0) {
                sign = c
            } elif (sign * c < 0.0) {
                return false
            }
        }
    }
    return true
}

// the outline of a tile with its walls (convex): top, right, the right and
// bottom and left corners lowered to the base, left
def private tile_outline(v : IsoView; tx, ty, hgt : int) : array<float2> {
    let c = iso_point(v, tx, ty, float(hgt))
    let wall = float(hgt - v.base) * 0.5 * v.cell
    return <- [c + float2(0.0, -0.5 * v.cell), c + float2(v.cell, 0.0), c + float2(v.cell, wall),
        c + float2(0.0, 0.5 * v.cell + wall), c + float2(-v.cell, wall), c + float2(-v.cell, 0.0)]
}

def private shade(c : uint; k : float) : uint {
    let r = uint(float((c >> 24u) & 255u) * k)
    let g = uint(float((c >> 16u) & 255u) * k)
    let b = uint(float((c >> 8u) & 255u) * k)
    return (r << 24u) | (g << 16u) | (b << 8u) | (c & 255u)
}

def private diamond_outline(var dl : ImDrawList?; c : float2; v : IsoView; inset : float; col : uint; thick : float) {
    let hw = v.cell - inset * 2.0
    let hh = v.cell * 0.5 - inset
    *dl |> AddQuad(ImVec2(c.x, c.y - hh), ImVec2(c.x + hw, c.y), ImVec2(c.x, c.y + hh), ImVec2(c.x - hw, c.y), abgr(col), thick)
}

// the height the feet stand at: a unit in water stands 1 lower
def private stand_height(m : FieldMap; x, y : int) : float {
    let tx = x - m.x0
    let ty = y - m.y0
    let hgt = field_height(m, x, y)
    let water = tx >= 0 && ty >= 0 && tx < m.w && ty < m.h && m.water[ty * m.w + tx]
    return float(water ? hgt - 1 : hgt)
}

// reach: tiles to highlight (w x h, empty - none)
def draw_battle_field(m : FieldMap; units : array<FieldUnit>; selected, target : int; reach : array<bool>;
                      var st : FieldState; x, y, w, h : float) : FieldInput {
    var res = FieldInput()
    if (m.w == 0 || m.h == 0) {
        SetCursorScreenPos(ImVec2(x + u(12.0), y + u(12.0)))
        bl_label("No battle map in this state", ICON_INFO)
        return res
    }
    var lo = 255
    var hi = 0
    for (hv in m.height) {
        if (hv > 0) {
            lo = min(lo, hv)
            hi = max(hi, hv)
        }
    }
    // the field in cells: x - y spans m.w + m.h, x + y half of it, plus the
    // heights and room for the sprites of the back row
    let top = float(hi - max(0, lo - 1)) * 0.5 + 2.5
    let span_w = float(m.w + m.h)
    let span_h = span_w * 0.5 + top + 0.5
    // the size is the user's (mouse wheel); until then it fits the view
    let fit = max(floor(min(w / span_w, h / span_h)), 2.0)
    SetCursorScreenPos(ImVec2(x, y))
    BeginChild("battle_field_view", ImVec2(w, h), ImGuiChildFlags.None,
        ImGuiWindowFlags.HorizontalScrollbar | ImGuiWindowFlags.NoScrollWithMouse)
    let io & = unsafe(GetIO())
    let wheel = IsWindowHovered() ? io.MouseWheel : 0.0
    var cell = st.cell > 0.0 ? floor(u(st.cell)) : fit
    let org = GetCursorScreenPos()                    // already moved by the scroll
    let avail = GetContentRegionAvail()
    var ox = org.x + max(0.0, floor((avail.x - cell * span_w) * 0.5))
    var oy = org.y + max(0.0, floor((avail.y - cell * span_h) * 0.5))
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
        ox = org.x + max(0.0, floor((avail.x - cell * span_w) * 0.5))
        oy = org.y + max(0.0, floor((avail.y - cell * span_h) * 0.5))
    }
    let v = IsoView(ox = ox, oy = oy, cell = cell, rows = float(m.h), top = top, base = max(0, lo - 1))
    var dl = GetWindowDrawList()
    let show_reach = length(reach) == m.w * m.h && st.drag < 0
    // back to front by diagonals: a tile, its marks, then the units on the
    // diagonal (a higher tile in front hides their feet)
    var unit_rects : array<float4>                    // where each unit was drawn (picking)
    unit_rects |> resize(length(units))
    var drawn : array<int>                            // units in the order drawn
    for (d in range(m.w + m.h - 1)) {
        for (tx in range(max(0, d - m.h + 1), min(m.w, d + 1))) {
            let ty = d - tx
            let hgt = m.height[ty * m.w + tx]
            if (hgt == 0) {
                continue
            }
            let c = iso_point(v, tx, ty, float(hgt))
            let wall = float(hgt - v.base) * 0.5 * cell
            let col = m.water[ty * m.w + tx] ? 0x3a6a9affu : tile_color(hgt, lo, hi)
            let l = ImVec2(c.x - cell, c.y)
            let r = ImVec2(c.x + cell, c.y)
            let b = ImVec2(c.x, c.y + cell * 0.5)
            let t = ImVec2(c.x, c.y - cell * 0.5)
            *dl |> AddQuadFilled(l, b, ImVec2(b.x, b.y + wall), ImVec2(l.x, l.y + wall), abgr(shade(col, 0.72)))
            *dl |> AddQuadFilled(b, r, ImVec2(r.x, r.y + wall), ImVec2(b.x, b.y + wall), abgr(shade(col, 0.55)))
            *dl |> AddQuadFilled(t, r, b, l, abgr(col))
            *dl |> AddQuad(t, r, b, l, abgr(shade(col, 0.85)), 1.0)
            if (show_reach && reach[ty * m.w + tx]) {
                *dl |> AddQuadFilled(t, r, b, l, abgr(0xffa03050u))
                diamond_outline(dl, c, v, u(1.5), 0xffa030ffu, u(1.5))
            }
            if (cell >= u(22.0) && hi > lo) {
                let hs = "{hgt + m.shown_shift}"
                text_at_baseline(c.x - text_width(hs) * 0.5, c.y + u(5.0), hs, 0x00000070u)
            }
            let here = field_unit_at(units, tx + m.x0, ty + m.y0)
            if (here >= 0 && here == target && here != st.drag) {
                diamond_outline(dl, c, v, 0.0, 0xffa030ffu, u(2.5))
            }
            if (here >= 0 && here == selected && here != st.drag) {
                diamond_outline(dl, c, v, u(2.0), 0xffffffffu, u(2.0))
            }
        }
        for (i in range(length(units))) {
            let ux = units[i].x - m.x0
            let uy = units[i].y - m.y0
            if (i == st.drag || ux + uy != d || ux < 0 || uy < 0 || ux >= m.w || uy >= m.h) {
                continue
            }
            let feet = iso_point(v, ux, uy, stand_height(m, units[i].x, units[i].y))
            unit_rects[i] = draw_field_unit(dl, units[i], feet, cell)
            drawn |> push(i)
        }
    }
    // input over the whole field
    SetCursorScreenPos(ImVec2(ox, oy))
    InvisibleButton("battle_field", ImVec2(cell * span_w, cell * span_h),
        ImGuiButtonFlags.MouseButtonLeft | ImGuiButtonFlags.MouseButtonRight)
    let mp = GetMousePos()
    let mouse = float2(mp.x, mp.y)
    // the tile under the mouse: the front-most whose outline holds it
    var mx = -1000
    var my = -1000
    for (dr in range(m.w + m.h - 1)) {
        let d = m.w + m.h - 2 - dr
        for (tx in range(max(0, d - m.h + 1), min(m.w, d + 1))) {
            let ty = d - tx
            let hgt = m.height[ty * m.w + tx]
            if (mx == -1000 && hgt > 0 && inside_convex(mouse, tile_outline(v, tx, ty, hgt))) {
                mx = tx + m.x0
                my = ty + m.y0
            }
        }
        if (mx != -1000) {
            break
        }
    }
    // a unit under the mouse: its figure (front-most first), else its tile
    var under = -1
    for (k in range(length(drawn))) {
        let i = drawn[length(drawn) - 1 - k]
        let rc = unit_rects[i]
        if (under < 0 && mouse.x >= rc.x && mouse.x < rc.z && mouse.y >= rc.y && mouse.y < rc.w) {
            under = i
        }
    }
    if (under < 0) {
        under = field_unit_at(units, mx, my)
    }
    let hovered = IsItemHovered()
    if (hovered && IsMouseClicked(ImGuiMouseButton.Left, false) && under >= 0) {
        res.select = under
        st.drag = under
    }
    if (hovered && IsMouseClicked(ImGuiMouseButton.Right, false) && under >= 0) {
        res.target = under
    }
    if (st.drag >= 0 && st.drag < length(units)) {
        let dg = st.drag
        if (IsMouseDown(ImGuiMouseButton.Left)) {
            draw_field_unit(dl, units[dg], mouse, cell)
        } else {
            let at = field_unit_at(units, mx, my)
            let free = at < 0 || at == dg
            if (field_height(m, mx, my) > 0 && free && (mx != units[dg].x || my != units[dg].y)) {
                res.moved = dg
                res.move_x = mx
                res.move_y = my
            }
            st.drag = -1
        }
    } else {
        st.drag = -1
    }
    if (hovered && selected >= 0 && selected < length(units)) {
        if (IsKeyPressed(ImGuiKey.Q, false)) {
            res.turn = -1
        }
        if (IsKeyPressed(ImGuiKey.E, false)) {
            res.turn = 1
        }
    }
    if (hovered && st.drag < 0 && field_height(m, mx, my) > 0) {
        let who = under >= 0 ? "  {units[under].name}" : ""
        bl_tooltip("{mx}, {my}  height {field_height(m, mx, my) + m.shown_shift}{who}")
    }
    EndChild()
    return res
}

// A unit standing at `feet` (the center of its tile's top face): its
// sprite, or a disc in the side color with the facing arrow and two
// letters of the name. Returns the rectangle it covers (x0, y0, x1, y1)
// for picking.
def draw_field_unit(var dl : ImDrawList?; un : FieldUnit; feet : float2; cell : float) : float4 {
    if (un.sprite >= 0) {
        let s = cell / 16.0                          // game pixels -> screen
        let x0 = feet.x - gba_gfx_origin_x(un.sprite) * s
        let y0 = feet.y + un.sprite_dy * s - gba_gfx_origin_y(un.sprite) * s
        let sw = gba_gfx_width(un.sprite) * s
        let sh = gba_gfx_height(un.sprite) * s
        gba_gfx_draw(un.sprite, x0, y0, sw, sh, un.alive ? 1.0 : 0.45)
        return float4(x0, y0, x0 + sw, y0 + sh)
    }
    let col = un.alive ? side_color(un.team) : 0x707070ffu
    let r = cell * 0.4
    let c = float2(feet.x, feet.y - r * 0.9)
    let f = facing_dir(un.facing)
    // arrow: a triangle out of the disc in the facing direction
    let tip = ImVec2(c.x + f.x * r * 1.45, c.y + f.y * r * 1.45)
    let b1 = ImVec2(c.x + f.x * r * 0.7 - f.y * r * 0.55, c.y + f.y * r * 0.7 + f.x * r * 0.55)
    let b2 = ImVec2(c.x + f.x * r * 0.7 + f.y * r * 0.55, c.y + f.y * r * 0.7 - f.x * r * 0.55)
    *dl |> AddTriangleFilled(tip, b1, b2, abgr(0xf0f0f0ffu))
    *dl |> AddCircleFilled(ImVec2(c.x, c.y), r, abgr(col), 24)
    let short = length(un.name) > 2 ? slice(un.name, 0, 2) : un.name
    text_at_baseline(c.x - text_width(short) * 0.5, c.y + u(5.0), short, 0xffffffffu)
    return float4(c.x - r, c.y - r, c.x + r, c.y + r)
}

// below the field: turn buttons, Fit and the help line; returns the turn
// asked for (-1, 0, 1)
def field_bar(var st : FieldState; x, y : float) : int {
    var res = 0
    SetCursorScreenPos(ImVec2(x, y))
    if (bl_tool_button("turn_ccw", "", ICON_TURN_CCW, u(28.0), BND_CORNER_RIGHT)) {
        res = -1
    }
    SetCursorScreenPos(ImVec2(x + u(28.0), y))
    if (bl_tool_button("turn_cw", "", ICON_TURN_CW, u(28.0), BND_CORNER_LEFT)) {
        res = 1
    }
    SetCursorScreenPos(ImVec2(x + u(64.0), y))
    if (bl_tool_button("field_fit", "Fit", ICON_FIT, u(56.0))) {
        st.cell = 0.0
    }
    SetCursorScreenPos(ImVec2(x + u(128.0), y))
    bl_label("Click: select   Right click: target   Drag: move   Q / E: turn   Wheel: zoom")
    return res
}
