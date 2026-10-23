options gen2
options indenting = 4

// Blendish (Blender 2.5-2.7 widgets, oui-blendish) redrawn on ImGui.
// The geometry, theme colors and label layout follow blendish.c one to one
// (bndToolButton, bndRadioButton, bndOptionButton, bndChoiceButton,
// bndNumberField, bndSlider, bndTextField, bndColorButton, bndMenuItem,
// bndLabel, bndSplitterWidgets); behavior (hover, drag, focus, popups,
// text editing) is ImGui's. All Blendish units are multiplied by bl_scale.
module bl_imgui shared public

require imgui
require dasimgui/imgui_boost
require imgui_ext
require bnd_const   // BND_ICON_* / BND_CORNER_* constants
require math
require strings

// ------------------------------------------------------------ theme

struct BndWidgetTheme {
    outline : uint
    item : uint
    inner : uint
    inner_sel : uint
    text : uint
    text_sel : uint
    shade_top : int
    shade_down : int
}

struct BndTheme {
    background : uint
    regular : BndWidgetTheme
    tool : BndWidgetTheme
    radio : BndWidgetTheme
    text_field : BndWidgetTheme
    option : BndWidgetTheme
    choice : BndWidgetTheme
    number : BndWidgetTheme
    slider : BndWidgetTheme
    menu : BndWidgetTheme
    menu_item : BndWidgetTheme
}

// blendish.c bnd_theme, colors as 0xRRGGBBAA
def blendish_theme() : BndTheme {
    let black = 0x000000ffu
    let white = 0xffffffffu
    return BndTheme(background = 0x727272ffu,
        regular = BndWidgetTheme(outline = 0x191919ffu, item = 0x191919ffu, inner = 0x999999ffu, inner_sel = 0x646464ffu,
            text = black, text_sel = white, shade_top = 0, shade_down = 0),
        tool = BndWidgetTheme(outline = 0x191919ffu, item = 0x191919ffu, inner = 0x999999ffu, inner_sel = 0x646464ffu,
            text = black, text_sel = white, shade_top = 15, shade_down = -15),
        radio = BndWidgetTheme(outline = black, item = white, inner = 0x464646ffu, inner_sel = 0x5680c2ffu,
            text = white, text_sel = black, shade_top = 15, shade_down = -15),
        text_field = BndWidgetTheme(outline = 0x191919ffu, item = 0x5a5a5affu, inner = 0x999999ffu, inner_sel = 0x999999ffu,
            text = black, text_sel = white, shade_top = 0, shade_down = 25),
        option = BndWidgetTheme(outline = black, item = white, inner = 0x464646ffu, inner_sel = 0x464646ffu,
            text = black, text_sel = white, shade_top = 15, shade_down = -15),
        choice = BndWidgetTheme(outline = black, item = white, inner = 0x464646ffu, inner_sel = 0x464646ffu,
            text = white, text_sel = 0xccccccffu, shade_top = 15, shade_down = -15),
        number = BndWidgetTheme(outline = 0x191919ffu, item = 0x5a5a5affu, inner = 0xb4b4b4ffu, inner_sel = 0x999999ffu,
            text = black, text_sel = white, shade_top = -20, shade_down = 0),
        slider = BndWidgetTheme(outline = 0x191919ffu, item = 0x808080ffu, inner = 0xb4b4b4ffu, inner_sel = 0x999999ffu,
            text = black, text_sel = white, shade_top = -20, shade_down = 0),
        menu = BndWidgetTheme(outline = black, item = 0x646464ffu, inner = 0x191919e6u, inner_sel = 0x2d2d2de6u,
            text = 0xa0a0a0ffu, text_sel = white, shade_top = 0, shade_down = 0),
        menu_item = BndWidgetTheme(outline = black, item = 0xacacac80u, inner = 0x00000000u, inner_sel = 0x5680c2ffu,
            text = white, text_sel = black, shade_top = 38, shade_down = 0))
}

var bt : BndTheme = blendish_theme()
var bl_scale = 1.0

let BL_DEFAULT = 0
let BL_HOVER = 1
let BL_ACTIVE = 2

let BND_TOOL_RADIUS = 4.0
let BND_OPTION_RADIUS = 4.0
let BND_TEXT_RADIUS = 4.0
let BND_NUMBER_RADIUS = 10.0
let BND_PAD_LEFT = 8.0
let BND_PAD_RIGHT = 8.0

def offset_color(c : uint; delta : int) : uint {
    let r = clamp(int((c >> 24u) & 255u) + delta, 0, 255)
    let g = clamp(int((c >> 16u) & 255u) + delta, 0, 255)
    let b = clamp(int((c >> 8u) & 255u) + delta, 0, 255)
    return (uint(r) << 24u) | (uint(g) << 16u) | (uint(b) << 8u) | (c & 255u)
}

def transparent(c : uint) : uint {
    // BND_TRANSPARENT_ALPHA 0.9
    return (c & 0xffffff00u) | uint(float(c & 255u) * 0.9)
}

def abgr(c : uint) : uint {
    return ((c >> 24u) & 255u) | (((c >> 16u) & 255u) << 8u) | (((c >> 8u) & 255u) << 16u) | ((c & 255u) << 24u)
}

def u(v : float) : float {
    return v * bl_scale
}

def text_color(t : BndWidgetTheme; state : int) : uint {
    return state == BL_ACTIVE ? t.text_sel : t.text
}

// bndInnerColors
def inner_colors(t : BndWidgetTheme; state : int; flip : bool) : tuple<top : uint; down : uint> {
    if (state == BL_HOVER) {
        let c = offset_color(t.inner, 15)
        return (top = offset_color(c, t.shade_top), down = offset_color(c, t.shade_down))
    } elif (state == BL_ACTIVE) {
        return (top = offset_color(t.inner_sel, flip ? t.shade_down : t.shade_top),
                down = offset_color(t.inner_sel, flip ? t.shade_top : t.shade_down))
    }
    return (top = offset_color(t.inner, t.shade_top), down = offset_color(t.inner, t.shade_down))
}

def frame(x, y, w, h, radius : float; sharp : int; t : BndWidgetTheme; state : int; flip : bool) {
    let c = inner_colors(t, state, flip)
    imx_bnd_box(x, y, w, h, radius, sharp, c.top, c.down, transparent(t.outline), bl_scale)
}

def item_state() : int {
    return IsItemActive() ? BL_ACTIVE : (IsItemHovered() ? BL_HOVER : BL_DEFAULT)
}

// ------------------------------------------------------------ text

// DejaVu Sans: ascender is ~0.8 of the line height ImGui sizes fonts by.
def text_at_baseline(x, baseline : float; s : string; color : uint) {
    let fs = GetFontSize()
    *GetWindowDrawList() |> AddText(ImVec2(floor(x), floor(baseline - fs * 0.797 + 0.5)), abgr(color), s)
}

def text_width(s : string) : float {
    return CalcTextSize(s, false, -1.0).x
}

def bl_icon(x, y : float; icon : int) {
    imx_icon_at(floor(x), floor(y), icon, u(16.0), 1.0)
}

// bndIconLabelValue: icon at (x+4, y+2), label from x+8 (+16 with an icon),
// baseline 21-7 below the top; "label: value" centered or left aligned.
def icon_label_value(x, y, w, h : float; icon : int; color : uint; center : bool; caption : string; value : string = "") {
    var pleft = u(BND_PAD_LEFT)
    if (caption == "" && value == "") {
        if (icon >= 0) {
            bl_icon(x + u(2.0), y + u(2.0), icon)
        }
        return
    }
    if (icon >= 0) {
        bl_icon(x + u(4.0), y + u(2.0), icon)
        pleft += u(16.0)
    }
    let s = value == "" ? caption : (caption == "" ? value : "{caption}: {value}")
    let baseline = y + u(14.0)
    var tx = x + pleft
    if (center) {
        tx += ((w - u(BND_PAD_RIGHT) - pleft) - text_width(s)) * 0.5
    }
    text_at_baseline(tx, baseline, s, color)
}

// ------------------------------------------------------------ widgets
// x, y come from the ImGui cursor; w in pixels; sharp = BND_CORNER_* bits.

def bl_tool_button(id, caption : string; icon : int; w : float; sharp : int = 0; selected : bool = false) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    let clicked = InvisibleButton(id, ImVec2(w, h))
    let st = selected ? BL_ACTIVE : item_state()
    frame(p.x, p.y, w, h, BND_TOOL_RADIUS, sharp, bt.tool, st, true)
    icon_label_value(p.x, p.y, w, h, icon, text_color(bt.tool, st), true, caption)
    return clicked
}

def bl_radio_button(id, caption : string; icon : int; w : float; sharp : int; selected : bool) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    let clicked = InvisibleButton(id, ImVec2(w, h))
    let st = selected ? BL_ACTIVE : item_state()
    frame(p.x, p.y, w, h, BND_OPTION_RADIUS, sharp, bt.radio, st == BL_ACTIVE && !selected ? BL_HOVER : st, true)
    icon_label_value(p.x, p.y, w, h, icon, text_color(bt.radio, st), true, caption)
    return clicked
}

// bndOptionButton: a 14x15 box at the bottom left, label 12 px to the right.
def bl_option_width(caption : string) : float {
    return u(12.0 + BND_PAD_LEFT + BND_PAD_RIGHT) + text_width(caption)
}

def bl_option(id, caption : string; var value : bool&) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    let w = bl_option_width(caption)
    let clicked = InvisibleButton(id, ImVec2(w, h))
    if (clicked) {
        value = !value
    }
    let st = value ? BL_ACTIVE : (IsItemHovered() ? BL_HOVER : BL_DEFAULT)
    let ox = p.x
    let oy = p.y + h - u(15.0 + 3.0)
    frame(ox, oy, u(14.0), u(15.0), BND_OPTION_RADIUS, 0, bt.option, st, true)
    if (value) {   // bndCheck
        let c = abgr(transparent(bt.option.item))
        var dl = GetWindowDrawList()
        *dl |> AddLine(ImVec2(ox + u(4.0), oy + u(5.0)), ImVec2(ox + u(7.0), oy + u(8.0)), c, u(2.0))
        *dl |> AddLine(ImVec2(ox + u(7.0), oy + u(8.0)), ImVec2(ox + u(14.0), oy + u(1.0)), c, u(2.0))
    }
    icon_label_value(p.x + u(12.0), p.y, w - u(12.0), h, -1, text_color(bt.option, st), false, caption)
    return clicked
}

// bndNumberField: drag to change, click the end arrows to step,
// double-click to type (ImGui InputText edits, framed as a text field).
var bl_editing = ""
var bl_edit_buf : ImGuiInputTextBuffer
var bl_edit_focus = false   // focus the editor once (refocusing selects all)
var bl_edit_age = 0         // frames since editing started (focus lands a frame later)

def fmt_number(v : float; precision : int) : string {
    return precision <= 0 ? "{int(v)}" : (precision == 1 ? "{v:.1f}" : "{v:.2f}")
}

def private arrow(x, y, sz : float; color : uint) {
    // bndArrow: a triangle pointing along sign(s)
    *GetWindowDrawList() |> AddTriangleFilled(ImVec2(x, y), ImVec2(x - sz, y + abs(sz)), ImVec2(x - sz, y - abs(sz)), abgr(color))
}

def private edit_in_place(id : string; var value : float&; p : float2; w, h : float; sharp : int) : bool {
    frame(p.x, p.y, w, h, BND_TEXT_RADIUS, sharp, bt.text_field, BL_ACTIVE, false)
    SetCursorScreenPos(ImVec2(p.x, p.y))
    PushStyleColor(ImGuiCol.FrameBg, 0u)
    PushStyleColor(ImGuiCol.FrameBgHovered, 0u)
    PushStyleColor(ImGuiCol.FrameBgActive, 0u)
    PushStyleColor(ImGuiCol.Text, abgr(bt.text_field.text_sel))
    PushStyleColor(ImGuiCol.TextSelectedBg, abgr(bt.text_field.item))
    PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(u(BND_PAD_LEFT), floor((h - GetFontSize()) * 0.5 - u(1.0))))
    SetNextItemWidth(w)
    if (bl_edit_focus) {
        SetKeyboardFocusHere(0)
        bl_edit_focus = false
        bl_edit_age = 0
    }
    bl_edit_age++
    let done = InputText("##{id}_edit", bl_edit_buf, ImGuiInputTextFlags.EnterReturnsTrue | ImGuiInputTextFlags.CharsDecimal)
    PopStyleVar(1)
    PopStyleColor(5)
    if (done || (bl_edit_age > 2 && !IsItemActive())) {
        value = to_float(to_string(bl_edit_buf))
        bl_editing = ""
        return true
    }
    return false
}

def bl_number(id, caption : string; var value : float&; step : float; precision : int; w : float; sharp : int = 0) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    if (bl_editing == id) {
        return edit_in_place(id, value, float2(p.x, p.y), w, h, sharp)
    }
    InvisibleButton(id, ImVec2(w, h))
    var changed = false
    if (IsItemClicked(ImGuiMouseButton.Left)) {
        let mx = GetMousePos().x
        if (mx < p.x + u(12.0)) {
            value -= step * 10.0
            changed = true
        } elif (mx > p.x + w - u(12.0)) {
            value += step * 10.0
            changed = true
        }
    }
    let dragging = IsItemActive() && IsMouseDragging(ImGuiMouseButton.Left, 2.0)
    if (dragging) {
        value += GetIO().MouseDelta.x * step
        changed = true
    }
    if (IsItemHovered() && IsMouseDoubleClicked(ImGuiMouseButton.Left)) {
        bl_editing = id
        bl_edit_focus = true
        bl_edit_buf = ImGuiInputTextBuffer(fmt_number(value, precision), 32)
    }
    let st = dragging ? BL_ACTIVE : (IsItemHovered() ? BL_HOVER : BL_DEFAULT)
    frame(p.x, p.y, w, h, BND_NUMBER_RADIUS, sharp, bt.number, st, false)
    icon_label_value(p.x, p.y, w, h, -1, text_color(bt.number, st), true, caption, fmt_number(value, precision))
    let ac = transparent(bt.number.item)
    arrow(p.x + u(8.0), p.y + u(10.0), -u(4.0), ac)
    arrow(p.x + w - u(8.0), p.y + u(10.0), u(4.0), ac)
    return changed
}

// bndSlider: the item-colored fill is the same box clipped at the value.
def bl_slider(id, caption : string; var value : float&; lo, hi : float; value_text : string; w : float; sharp : int = 0) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    InvisibleButton(id, ImVec2(w, h))
    var changed = false
    if (IsItemActive()) {
        value = lo + saturate((GetMousePos().x - p.x - u(4.0)) / (w - u(8.0))) * (hi - lo)
        changed = true
    }
    let st = item_state()
    let c = inner_colors(bt.slider, st, false)
    imx_bnd_box(p.x, p.y, w, h, BND_NUMBER_RADIUS, sharp, c.top, c.down, 0u, bl_scale)
    let t = bt.slider
    let ft = offset_color(t.item, st == BL_ACTIVE ? t.shade_top : t.shade_down)
    let fd = offset_color(t.item, st == BL_ACTIVE ? t.shade_down : t.shade_top)
    let progress = saturate((value - lo) / (hi - lo))
    var dl = GetWindowDrawList()
    *dl |> PushClipRect(ImVec2(p.x, p.y), ImVec2(p.x + u(8.0) + (w - u(8.0)) * progress, p.y + h), true)
    imx_bnd_box(p.x, p.y, w, h, BND_NUMBER_RADIUS, sharp, ft, fd, 0u, bl_scale)
    *dl |> PopClipRect()
    imx_bnd_box(p.x, p.y, w, h, BND_NUMBER_RADIUS, sharp, 0u, 0u, transparent(t.outline), bl_scale)
    icon_label_value(p.x, p.y, w, h, -1, text_color(t, st), true, caption, value_text)
    return changed
}

// bndTextField drawn under an ImGui InputText with a transparent frame.
var private text_active = ""

def bl_text_field(id : string; var buf : ImGuiInputTextBuffer; w : float; sharp : int = 0) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    let active = text_active == id
    frame(p.x, p.y, w, h, BND_TEXT_RADIUS, sharp, bt.text_field, active ? BL_ACTIVE : BL_DEFAULT, false)
    PushStyleColor(ImGuiCol.FrameBg, 0u)
    PushStyleColor(ImGuiCol.FrameBgHovered, abgr(0xffffff14u))
    PushStyleColor(ImGuiCol.FrameBgActive, 0u)
    PushStyleColor(ImGuiCol.Text, abgr(text_color(bt.text_field, active ? BL_ACTIVE : BL_DEFAULT)))
    PushStyleColor(ImGuiCol.TextSelectedBg, abgr(bt.text_field.item))
    PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(u(BND_PAD_LEFT), floor((h - GetFontSize()) * 0.5 - u(1.0))))
    PushStyleVar(ImGuiStyleVar.FrameRounding, u(BND_TEXT_RADIUS))
    SetNextItemWidth(w)
    let changed = InputText("##{id}", buf)
    if (IsItemActive()) {
        text_active = id
    } elif (active) {
        text_active = ""
    }
    PopStyleVar(2)
    PopStyleColor(5)
    return changed
}

// bndTextField over a string value: drawn as a label, a click edits it in
// place with one shared buffer (only one field is edited at a time).
var private str_editing = ""
var private str_buf : ImGuiInputTextBuffer
var private str_focus = false
var private str_age = 0

def bl_string(id : string; var value : string&; w : float; sharp : int = 0) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    if (str_editing == id) {
        frame(p.x, p.y, w, h, BND_TEXT_RADIUS, sharp, bt.text_field, BL_ACTIVE, false)
        PushStyleColor(ImGuiCol.FrameBg, 0u)
        PushStyleColor(ImGuiCol.FrameBgHovered, 0u)
        PushStyleColor(ImGuiCol.FrameBgActive, 0u)
        PushStyleColor(ImGuiCol.Text, abgr(bt.text_field.text_sel))
        PushStyleColor(ImGuiCol.TextSelectedBg, abgr(bt.text_field.item))
        PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(u(BND_PAD_LEFT), floor((h - GetFontSize()) * 0.5 - u(1.0))))
        SetNextItemWidth(w)
        if (str_focus) {
            SetKeyboardFocusHere(0)
            str_focus = false
            str_age = 0
        }
        str_age++
        let done = InputText("##{id}_str", str_buf, ImGuiInputTextFlags.EnterReturnsTrue)
        PopStyleVar(1)
        PopStyleColor(5)
        if (done || (str_age > 2 && !IsItemActive())) {
            value = to_string(str_buf)
            str_editing = ""
            return true
        }
        return false
    }
    let clicked = InvisibleButton(id, ImVec2(w, h))
    if (clicked) {
        str_editing = id
        str_focus = true
        str_buf = ImGuiInputTextBuffer(value, 256)
    }
    let st = IsItemHovered() ? BL_HOVER : BL_DEFAULT
    frame(p.x, p.y, w, h, BND_TEXT_RADIUS, sharp, bt.text_field, st, false)
    icon_label_value(p.x, p.y, w, h, -1, text_color(bt.text_field, st), false, value)
    return false
}

def bl_color_button(id : string; color : uint; w : float; sharp : int = 0) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    let clicked = InvisibleButton(id, ImVec2(w, h))
    imx_bnd_box(p.x, p.y, w, h, BND_TOOL_RADIUS, sharp, color | 255u, color | 255u, transparent(bt.tool.outline), bl_scale)
    return clicked
}

// bndLabel: regular text, left aligned, optional icon.
def bl_label(caption : string; icon : int = -1; w : float = 0.0; color : uint = 0u) {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    let width = w > 0.0 ? w : u(BND_PAD_LEFT + BND_PAD_RIGHT + (icon >= 0 ? 16.0 : 0.0)) + text_width(caption)
    Dummy(ImVec2(width, h))
    icon_label_value(p.x, p.y, width, h, icon, color != 0u ? color : bt.regular.text, false, caption)
}

// A collapsible panel title as in demo 05: disclosure icon + label, no fill.
def bl_section(id, caption : string; var open : bool&) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    let w = GetContentRegionAvail().x
    if (InvisibleButton(id, ImVec2(w, h))) {
        open = !open
    }
    icon_label_value(p.x, p.y, w, h, open ? BND_ICON_DISCLOSURE_TRI_DOWN : BND_ICON_DISCLOSURE_TRI_RIGHT,
        bt.regular.text, false, caption)
    return open
}

// bndMenuItem inside a popup: hovered rows get the shaded selection box.
def bl_menu_item(caption : string; icon : int = -1) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    let w = max(GetContentRegionAvail().x, u(160.0))
    let clicked = InvisibleButton("##mi_{caption}", ImVec2(w, h))
    let hovered = IsItemHovered()
    let t = bt.menu_item
    if (hovered) {
        imx_bnd_box(p.x - u(1.0), p.y - u(1.0), w + u(2.0), h + u(3.0), 0.0, 15, offset_color(t.inner_sel, t.shade_top),
            offset_color(t.inner_sel, t.shade_down), 0u, bl_scale)
    }
    icon_label_value(p.x, p.y, w, h, icon, text_color(t, hovered ? BL_ACTIVE : BL_DEFAULT), false, caption)
    if (clicked) {
        CloseCurrentPopup()
    }
    return clicked
}

// Popup frame colors (bndMenuBackground) for menus and choice lists.
def bl_push_popup_style() {
    PushStyleColor(ImGuiCol.PopupBg, abgr(bt.menu.inner))
    PushStyleColor(ImGuiCol.Border, abgr(transparent(bt.menu.outline)))
    PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(0.0, u(3.0)))
}

def bl_pop_popup_style() {
    PopStyleVar(1)
    PopStyleColor(2)
}

// A tooltip in the menu colors (Blender: dark box, light text); the
// default style has the panel's dark text on a dark background.
def bl_tooltip(text : string) {
    PushStyleColor(ImGuiCol.PopupBg, abgr(bt.menu.inner))
    PushStyleColor(ImGuiCol.Border, abgr(transparent(bt.menu.outline)))
    PushStyleColor(ImGuiCol.Text, abgr(bt.menu_item.text))
    PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(u(6.0), u(4.0)))
    SetTooltip(text)
    PopStyleVar(1)
    PopStyleColor(3)
}

// Inside an open popup: rows touch each other.
def bl_popup_rows(blk : block<() : void>) {
    PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(0.0, 0.0))
    invoke(blk)
    PopStyleVar(1)
}

// bndChoiceButton + a popup list of bndMenuItems.
def bl_choice(id : string; items : array<string>; var selected : int&; w : float; sharp : int = 0) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    if (InvisibleButton(id, ImVec2(w, h))) {
        OpenPopup("##{id}_popup")
    }
    let st = IsPopupOpen("##{id}_popup") ? BL_ACTIVE : item_state()
    frame(p.x, p.y, w, h, BND_OPTION_RADIUS, sharp, bt.choice, st, true)
    icon_label_value(p.x, p.y, w - u(14.0), h, -1, text_color(bt.choice, st), false, items[selected])
    // bndUpDownArrow at (x+w-10, y+10), size 5
    let c = abgr(transparent(bt.choice.item))
    let ax = p.x + w - u(10.0)
    let ay = p.y + u(10.0)
    let s = u(5.0)
    let aw = 1.1 * s
    var dl = GetWindowDrawList()
    *dl |> AddTriangleFilled(ImVec2(ax, ay - u(1.0)), ImVec2(ax + aw * 0.5, ay - s - u(1.0)), ImVec2(ax + aw, ay - u(1.0)), c)
    *dl |> AddTriangleFilled(ImVec2(ax, ay + u(1.0)), ImVec2(ax + aw, ay + u(1.0)), ImVec2(ax + aw * 0.5, ay + s + u(1.0)), c)
    var changed = false
    // the list opens below the button, or above it when there is more
    // room there; taller than the room, it scrolls (wheel, scrollbar)
    let vp = GetMainViewport()
    let full = float(length(items)) * h + u(6.0)
    let below = vp.WorkPos.y + vp.WorkSize.y - (p.y + h) - u(4.0)
    let above = p.y - vp.WorkPos.y - u(4.0)
    let up = full > below && above > below
    let ph = min(full, max(up ? above : below, h * 3.0))
    // wide enough for the longest item (and the scrollbar), on screen
    var tw = 0.0
    for (it in items) {
        tw = max(tw, text_width(it))
    }
    let bar = ph < full ? GetStyle().ScrollbarSize : 0.0
    // bl_menu_item rows are at least 160 wide
    let pw = min(max(max(w, u(160.0)), tw + u(BND_PAD_LEFT + BND_PAD_RIGHT + 8.0)) + bar, vp.WorkSize.x)
    let px = clamp(p.x, vp.WorkPos.x, vp.WorkPos.x + vp.WorkSize.x - pw)
    SetNextWindowPos(ImVec2(px, up ? p.y - ph : p.y + h), ImGuiCond.Always, ImVec2(0.0, 0.0))
    SetNextWindowSize(ImVec2(pw, ph), ImGuiCond.Always)
    bl_push_popup_style()
    if (BeginPopup("##{id}_popup")) {
        let appearing = IsWindowAppearing()
        bl_popup_rows() {
            for (i in range(length(items))) {
                if (bl_menu_item(items[i])) {
                    selected = i
                    changed = true
                }
                if (appearing && i == selected) {
                    SetScrollHereY(0.5)     // the current item in view
                }
            }
        }
        EndPopup()
    }
    bl_pop_popup_style()
    return changed
}

// bndSplitterWidgets: hatched corners of an area (bottom-left, top-right).
def bl_splitter_widgets(x, y, w, h : float) {
    var dl = GetWindowDrawList()
    let light = abgr(transparent(offset_color(bt.background, 100)))
    let dark = abgr(transparent(offset_color(bt.background, -100)))
    let mid = abgr(transparent(bt.background))
    let x2 = x + w
    let y2 = y + h
    for (k in range(3)) {
        let base = float(k) * 4.0
        for (j, c in [0.0, 1.0, 2.0], [dark, mid, light]) {
            let a = u(13.0 - base - j)
            if (a > 0.0) {
                *dl |> AddLine(ImVec2(x, y2 - a), ImVec2(x + a, y2), c, bl_scale)
            }
            let b = u(11.0 - base + j)
            if (b > 0.0) {
                *dl |> AddLine(ImVec2(x2 - b, y), ImVec2(x2, y + b), c, bl_scale)
            }
        }
    }
}

// ------------------------------------------------------------ ImGui style

def bl_set_color(col : ImGuiCol; c : uint) {
    imx_style_color(int(col), c)
}

// Colors of what ImGui still draws itself (windows, popups, scrollbars,
// dock separators, menu bar highlight), metrics of Blendish at scale 1.
def bl_apply_style(scale : float) {
    bl_scale = scale
    StyleColorsDark()
    imx_style_blendish()
    let back = bt.background
    bl_set_color(ImGuiCol.Text, bt.regular.text)
    bl_set_color(ImGuiCol.TextDisabled, 0x3c3c3cffu)
    bl_set_color(ImGuiCol.WindowBg, back)
    bl_set_color(ImGuiCol.ChildBg, back)
    bl_set_color(ImGuiCol.PopupBg, bt.menu.inner)
    bl_set_color(ImGuiCol.Border, transparent(bt.menu.outline))
    bl_set_color(ImGuiCol.MenuBarBg, back)
    bl_set_color(ImGuiCol.TitleBg, back)
    bl_set_color(ImGuiCol.TitleBgActive, back)
    bl_set_color(ImGuiCol.FrameBg, bt.text_field.inner)
    bl_set_color(ImGuiCol.Header, offset_color(bt.menu_item.inner_sel, bt.menu_item.shade_top))
    bl_set_color(ImGuiCol.HeaderHovered, offset_color(bt.menu_item.inner_sel, bt.menu_item.shade_top))
    bl_set_color(ImGuiCol.HeaderActive, bt.menu_item.inner_sel)
    bl_set_color(ImGuiCol.ScrollbarBg, 0x00000000u)
    bl_set_color(ImGuiCol.ScrollbarGrab, 0x646464b4u)
    bl_set_color(ImGuiCol.ScrollbarGrabHovered, 0x737373b4u)
    bl_set_color(ImGuiCol.ScrollbarGrabActive, 0x828282b4u)
    bl_set_color(ImGuiCol.Separator, offset_color(back, -40))
    bl_set_color(ImGuiCol.SeparatorHovered, offset_color(back, -60))
    bl_set_color(ImGuiCol.SeparatorActive, bt.menu_item.inner_sel)
    bl_set_color(ImGuiCol.ResizeGrip, 0x00000000u)
    bl_set_color(ImGuiCol.ResizeGripHovered, 0x00000000u)
    bl_set_color(ImGuiCol.ResizeGripActive, 0x00000000u)
    bl_set_color(ImGuiCol.DockingPreview, 0x5680c280u)
    bl_set_color(ImGuiCol.DockingEmptyBg, back)
    bl_set_color(ImGuiCol.TextSelectedBg, bt.text_field.item)
    imx_capture_style()
    imx_ui_scale(scale)
}
