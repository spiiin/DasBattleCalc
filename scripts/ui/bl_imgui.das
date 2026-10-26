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
require bnd_const   // BND_CORNER_* constants
require icons       // ICON_* of ffta_icons16.png
require math
require strings
require daslib/strings_boost

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
    var s = value == "" ? caption : (caption == "" ? value : "{caption}: {value}")
    // longer than the widget: cut with "..." (it would overflow the frame);
    // widgets sized to their text (bl_option) give room == the text width
    // up to float rounding - not a reason to cut
    let room = w - pleft - u(BND_PAD_RIGHT)
    if (w > 0.0 && text_width(s) > room + 0.5) {
        while (length(s) > 0 && text_width("{s}...") > room) {
            s = slice(s, 0, length(s) - 1)
        }
        s = "{s}..."
    }
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

// A field edited in place: ImGui's InputText over a text field's frame,
// one field at a time (id: the one being edited, "" none).
struct private InlineEdit {
    id : string
    buf : ImGuiInputTextBuffer
    focus : bool                    // focus the editor once (refocusing selects all)
    age : int                       // frames since editing started (focus lands a frame later)
}

def private start_edit(var ed : InlineEdit; id, text : string; size : int) {
    ed.id = id
    ed.focus = true
    ed.buf = ImGuiInputTextBuffer(text, size)
}

// true when the edit ends (Enter, or the focus left): the text is in ed.buf
def private inline_edit(var ed : InlineEdit; input_id : string; flags : ImGuiInputTextFlags; p : float2;
                        w, h : float; sharp : int) : bool {
    frame(p.x, p.y, w, h, BND_TEXT_RADIUS, sharp, bt.text_field, BL_ACTIVE, false)
    SetCursorScreenPos(ImVec2(p.x, p.y))
    PushStyleColor(ImGuiCol.FrameBg, 0u)
    PushStyleColor(ImGuiCol.FrameBgHovered, 0u)
    PushStyleColor(ImGuiCol.FrameBgActive, 0u)
    PushStyleColor(ImGuiCol.Text, abgr(bt.text_field.text_sel))
    PushStyleColor(ImGuiCol.TextSelectedBg, abgr(bt.text_field.item))
    PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(u(BND_PAD_LEFT), floor((h - GetFontSize()) * 0.5 - u(1.0))))
    SetNextItemWidth(w)
    if (ed.focus) {
        SetKeyboardFocusHere(0)
        ed.focus = false
        ed.age = 0
    }
    ed.age++
    let done = InputText(input_id, ed.buf, flags)
    PopStyleVar(1)
    PopStyleColor(5)
    if (done || (ed.age > 2 && !IsItemActive())) {
        ed.id = ""
        return true
    }
    return false
}

// bndNumberField: drag to change, click the end arrows to step,
// double-click to type (ImGui InputText edits, framed as a text field).
var private number_edit = InlineEdit()

def fmt_number(v : float; precision : int) : string {
    return precision <= 0 ? "{int(v)}" : (precision == 1 ? "{v:.1f}" : "{v:.2f}")
}

def private arrow(x, y, sz : float; color : uint) {
    // bndArrow: a triangle pointing along sign(s)
    *GetWindowDrawList() |> AddTriangleFilled(ImVec2(x, y), ImVec2(x - sz, y + abs(sz)), ImVec2(x - sz, y - abs(sz)), abgr(color))
}


def bl_number(id, caption : string; var value : float&; step : float; precision : int; w : float; sharp : int = 0) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    if (number_edit.id == id) {
        let flags = ImGuiInputTextFlags.EnterReturnsTrue | ImGuiInputTextFlags.CharsDecimal
        if (inline_edit(number_edit, "##{id}_edit", flags, float2(p.x, p.y), w, h, sharp)) {
            value = to_float(to_string(number_edit.buf))
            return true
        }
        return false
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
        number_edit |> start_edit(id, fmt_number(value, precision), 32)
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

// A piece of a line of code in its color (bl_code_area).
struct CodeSpan {
    start : int                     // bytes of the line, stop not included
    stop : int
    color : uint
}

// A multi-line code editor: ImGui's InputTextMultiline (caret, selection,
// clipboard, undo) with its own text transparent, and the same text drawn
// over it in colors from colorize (parts it leaves out: the default
// color). The field is as large as its text and an outer child scrolls
// it, so the overlay knows where every line is. error_line (from 1) gets
// a red background; 0: none.
def bl_code_area(id : string; var buf : ImGuiInputTextBuffer; w, h : float; error_line : int;
                 colorize : block<(line : string; var spans : array<CodeSpan>) : void>) : bool {
    let p = GetCursorScreenPos()
    let active = text_active == id
    // a dark field, as code editors have (colored words on light grey read badly)
    let fg = 0xdcdcdcffu
    var bg = GetWindowDrawList()
    *bg |> AddRectFilled(ImVec2(p.x, p.y), ImVec2(p.x + w, p.y + h), abgr(active ? 0x2a2a2affu : 0x323232ffu),
        u(BND_TEXT_RADIUS), ImDrawFlags.None)
    *bg |> AddRect(ImVec2(p.x, p.y), ImVec2(p.x + w, p.y + h), abgr(active ? bt.menu_item.inner_sel : 0x1e1e1effu),
        u(BND_TEXT_RADIUS), ImDrawFlags.None, 1.0)
    let padx = u(BND_PAD_LEFT)
    let pady = u(4.0)
    let lh = GetFontSize()
    var lines <- split(to_string(buf), "\n")
    var widest = 0.0
    for (l in lines) {
        widest = max(widest, text_width(l))
    }
    PushStyleColor(ImGuiCol.ChildBg, 0u)
    BeginChild("{id}_scroll", ImVec2(w, h), ImGuiChildFlags.None, ImGuiWindowFlags.HorizontalScrollbar)
    let room = GetContentRegionAvail()
    let fw = max(room.x, widest + padx * 2.0 + u(24.0))
    let fh = max(room.y, float(length(lines) + 1) * lh + pady * 2.0)
    let origin = GetCursorScreenPos()
    var dl = GetWindowDrawList()
    if (error_line > 0 && error_line <= length(lines)) {
        let ey = origin.y + pady + float(error_line - 1) * lh
        *dl |> AddRectFilled(ImVec2(origin.x, ey), ImVec2(origin.x + fw, ey + lh), abgr(0xd0404060u), 0.0,
            ImDrawFlags.None)
    }
    PushStyleColor(ImGuiCol.FrameBg, 0u)
    PushStyleColor(ImGuiCol.FrameBgHovered, abgr(0xffffff0au))
    PushStyleColor(ImGuiCol.FrameBgActive, 0u)
    PushStyleColor(ImGuiCol.Text, 0u)
    PushStyleColor(ImGuiCol.InputTextCursor, abgr(fg))
    // see-through: the field draws the selection in its own child window,
    // which ImGui renders over this window's colored text
    PushStyleColor(ImGuiCol.TextSelectedBg, abgr(0x4a7ad070u))
    PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(padx, pady))
    let changed = InputTextMultiline("##{id}", buf, float2(fw, fh), ImGuiInputTextFlags.None)
    if (IsItemActive()) {
        text_active = id
    } elif (active) {
        text_active = ""
    }
    PopStyleVar(1)
    PopStyleColor(6)
    // the text again, in colors (after an edit: the new text)
    if (changed) {
        lines <- split(to_string(buf), "\n")
    }
    for (i in range(length(lines))) {
        let line = lines[i]
        let ly = origin.y + pady + float(i) * lh
        if (ly > origin.y + fh || line == "") {
            continue
        }
        var spans : array<CodeSpan>
        invoke(colorize, line, spans)
        var at = 0
        for (k in range(length(spans) + 1)) {
            let start = k < length(spans) ? spans[k].start : length(line)
            if (start > at) {
                let x = origin.x + padx + text_width(slice(line, 0, at))
                *dl |> AddText(ImVec2(x, ly), abgr(fg), slice(line, at, start))
            }
            if (k < length(spans)) {
                let sp = spans[k]
                let x = origin.x + padx + text_width(slice(line, 0, sp.start))
                *dl |> AddText(ImVec2(x, ly), abgr(sp.color), slice(line, sp.start, sp.stop))
                at = sp.stop
            }
        }
    }
    EndChild()
    PopStyleColor(1)
    return changed
}

// bndTextField over a string value: drawn as a label, a click edits it in
// place with one shared buffer (only one field is edited at a time).
var private string_edit = InlineEdit()

def bl_string(id : string; var value : string&; w : float; sharp : int = 0) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    if (string_edit.id == id) {
        if (inline_edit(string_edit, "##{id}_str", ImGuiInputTextFlags.EnterReturnsTrue, float2(p.x, p.y), w, h, sharp)) {
            value = to_string(string_edit.buf)
            return true
        }
        return false
    }
    if (InvisibleButton(id, ImVec2(w, h))) {
        string_edit |> start_edit(id, value, 256)
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
    icon_label_value(p.x, p.y, w, h, open ? ICON_OPEN : ICON_CLOSED,
        bt.regular.text, false, caption)
    return open
}

// bndMenuItem inside a popup: hovered rows get the shaded selection box.
def bl_menu_item(caption : string; icon : int = -1) : bool {
    let p = GetCursorScreenPos()
    let h = u(21.0)
    // as wide as the caption: an auto-sized popup grows to the widest item
    let w = max(GetContentRegionAvail().x, max(u(160.0), text_width(caption) + u(icon >= 0 ? 34.0 : 16.0)))
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
    // opaque: what is under a popup would show through the menu color
    PushStyleColor(ImGuiCol.PopupBg, abgr(bt.menu.inner | 0xffu))
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
