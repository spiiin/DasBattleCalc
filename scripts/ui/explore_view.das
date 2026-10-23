options gen2
options indenting = 4

// Explore views: the result table (sortable, scrolls both ways, only the
// visible rows are drawn) and the chart (lines, bars, points; linear or
// log axes; legend; the point under the mouse). Data: core/explore.das.
module explore_view shared public

require imgui
require dasimgui/imgui_boost
require math
require strings
require daslib/strings_boost
require bnd_const
require bl_imgui
require ../core/explore.das

// ------------------------------------------------------------ table

struct TableView {
    sort_col : int = -1             // -1: the table's own order
    sort_desc : bool
    order : array<int>              // rows in view order
    widths : array<float>
    version : int = -1              // the table the order and widths are for
    sorted_by : int = -2
    sorted_desc : bool
    scroll_x : float
    hover_row : int = -1            // table row under the mouse, -1 none
}

def private refresh_view(var v : TableView; t : ETable; version : int) {
    if (v.version != version) {
        v.version = version
        v.sorted_by = -2
        v.widths |> clear()
        for (c in range(length(t.names))) {
            var wd = text_width(t.names[c])
            for (r in range(min(length(t.rows), 300))) {
                wd = max(wd, text_width(value_text(t.rows[r][c])))
            }
            v.widths |> push(clamp(wd + u(18.0), u(48.0), u(240.0)))
        }
        if (v.sort_col >= length(t.names)) {
            v.sort_col = -1
        }
    }
    if (v.sorted_by == v.sort_col && v.sorted_desc == v.sort_desc && length(v.order) == length(t.rows)) {
        return
    }
    v.sorted_by = v.sort_col
    v.sorted_desc = v.sort_desc
    v.order <- [for (i in range(length(t.rows))); i]
    let col = v.sort_col
    if (col >= 0) {
        let desc = v.sort_desc
        sort(v.order) $(a, b) {
            let x = t.rows[a][col]
            let y = t.rows[b][col]
            if (value_less(x, y)) {
                return !desc
            }
            if (value_less(y, x)) {
                return desc
            }
            return a < b
        }
    }
}

// a table of the experiment; version changes when the table does
def draw_etable(id : string; t : ETable; version : int; var v : TableView; x, y, w, h : float) {
    refresh_view(v, t, version)
    v.hover_row = -1
    var dl = GetWindowDrawList()
    let row_h = u(20.0)
    let fg = bt.regular.text | 0xffu
    let dim = offset_color(fg, 50)
    // header: sticks to the top, follows the horizontal scroll of the body
    *dl |> PushClipRect(ImVec2(x, y), ImVec2(x + w, y + row_h), true)
    var hx = x - v.scroll_x
    for (c in range(length(t.names))) {
        let cw = v.widths[c]
        SetCursorScreenPos(ImVec2(hx, y))
        if (InvisibleButton("##{id}_h{c}", ImVec2(cw, row_h))) {
            if (v.sort_col == c) {
                if (v.sort_desc) {
                    v.sort_col = -1
                } else {
                    v.sort_desc = true
                }
            } else {
                v.sort_col = c
                v.sort_desc = false
            }
        }
        if (IsItemHovered()) {
            *dl |> AddRectFilled(ImVec2(hx, y), ImVec2(hx + cw, y + row_h), abgr(0xffffff18u), 0.0, ImDrawFlags.None)
        }
        let mark = v.sort_col == c ? (v.sort_desc ? " v" : " ^") : ""
        text_at_baseline(hx + u(6.0), y + row_h - u(5.0), "{t.names[c]}{mark}", dim)
        hx += cw
    }
    *dl |> PopClipRect()
    *dl |> AddLine(ImVec2(x, y + row_h), ImVec2(x + w, y + row_h), abgr(bt.regular.outline), 1.0)
    // body
    SetCursorScreenPos(ImVec2(x, y + row_h + u(2.0)))
    BeginChild("{id}_body", ImVec2(w, max(u(20.0), h - row_h - u(2.0))), ImGuiChildFlags.None,
        ImGuiWindowFlags.HorizontalScrollbar)
    var bl = GetWindowDrawList()
    v.scroll_x = GetScrollX()
    let origin = GetCursorScreenPos()
    var total_w = 0.0
    for (cw in v.widths) {
        total_w += cw
    }
    let n = length(v.order)
    let first = clamp(int(GetScrollY() / row_h), 0, n)
    let last = clamp(first + int(GetWindowHeight() / row_h) + 2, 0, n)
    let mouse = GetMousePos()
    let inside = IsWindowHovered()
    for (k in range(first, last)) {
        let r = v.order[k]
        let ry = origin.y + float(k) * row_h
        let hovered = inside && mouse.y >= ry && mouse.y < ry + row_h
        if (hovered) {
            v.hover_row = r
        }
        let bg = hovered ? 0xffffff18u : (k % 2 == 0 ? 0x00000000u : 0x0000001au)
        if ((bg & 0xffu) != 0u) {
            *bl |> AddRectFilled(ImVec2(origin.x, ry), ImVec2(origin.x + total_w, ry + row_h), abgr(bg), 0.0,
                ImDrawFlags.None)
        }
        var cx = origin.x
        for (c in range(length(t.names))) {
            let cell = t.rows[r][c]
            let s = value_text(cell)
            // numbers right-aligned, labels left
            let tx = cell.text != "" ? cx + u(6.0) : cx + v.widths[c] - u(8.0) - text_width(s)
            text_at_baseline(tx, ry + row_h - u(5.0), s, fg)
            cx += v.widths[c]
        }
    }
    SetCursorScreenPos(origin)
    Dummy(ImVec2(total_w, float(n) * row_h))
    EndChild()
}

// ------------------------------------------------------------ chart

let CHART_COLORS = fixed_array<uint>(0x5aa0f0ffu, 0xf0a040ffu, 0x70c070ffu, 0xe06060ffu, 0xb080e0ffu, 0x50c8c8ffu,
    0xe0d050ffu, 0xe080b0ffu, 0xb0b0b0ffu, 0x90e0a0ffu, 0x8080f0ffu, 0xc09060ffu)

def chart_color(i : int) : uint {
    return CHART_COLORS[i % length(CHART_COLORS)]
}

def private tr(v : double; logv : bool) : double {
    return logv ? log(v) / log(10.0lf) : v
}

// 1-2-5 steps for about `count` ticks
def private nice_step(span : double; count : int) : double {
    let raw = span / double(max(count, 1))
    if (raw <= 0.0lf || is_nan(raw)) {
        return 1.0lf
    }
    let mag = pow(10.0lf, floor(log(raw) / log(10.0lf)))
    let k = raw / mag
    return (k < 1.5lf ? 1.0lf : (k < 3.0lf ? 2.0lf : (k < 7.0lf ? 5.0lf : 10.0lf))) * mag
}

def private tick_text(v, step : double) : string {
    if (abs(v) < step * 1.0e-6lf) {
        return "0"
    }
    if (step >= 1.0lf) {
        return value_text(vnum(round(v)))
    }
    let digits = clamp(int(ceil(-log(step) / log(10.0lf))), 1, 6)
    return fmt(":.{digits}f", v)
}

// tick positions (in the transformed space) and their labels
def private axis_ticks(lo, hi : double; logv : bool; count : int; var at : array<double>; var labels : array<string>) {
    if (logv && hi - lo < 1.0lf) {
        // less than a decade: round values in between, placed on the log scale
        let a = pow(10.0lf, lo)
        let b = pow(10.0lf, hi)
        let step = nice_step(b - a, count)
        var v = ceil(a / step) * step
        while (v <= b + step * 1.0e-9lf) {
            if (v > 0.0lf) {
                at |> push(log(v) / log(10.0lf))
                labels |> push(tick_text(v, step))
            }
            v += step
        }
        return
    }
    if (logv) {
        let step = max(1.0lf, round(nice_step(hi - lo, count)))
        var k = ceil(lo / step) * step
        while (k <= hi + 1.0e-9lf) {
            at |> push(k)
            labels |> push(value_text(vnum(pow(10.0lf, k))))
            k += step
        }
        return
    }
    let step = nice_step(hi - lo, count)
    var v = ceil(lo / step) * step
    while (v <= hi + step * 1.0e-9lf) {
        at |> push(v)
        labels |> push(logv ? value_text(vnum(pow(10.0lf, v))) : tick_text(v, step))
        v += step
    }
}

// what is under the mouse
struct ChartHover {
    series : int = -1
    point : int = -1
}

def draw_chart(id : string; c : Chart; x, y, w, h : float) : ChartHover {
    var hover = ChartHover()
    var dl = GetWindowDrawList()
    let fg = bt.regular.text | 0xffu
    let dim = offset_color(fg, 50)
    let fs = GetFontSize()
    // legend rows on top
    var lx = x + u(8.0)
    var ly = y + u(4.0)
    if (c.title != "") {
        text_at_baseline(lx, ly + fs, c.title, fg)
        ly += fs + u(6.0)
    }
    if (c.series_name != "") {
        text_at_baseline(lx, ly + fs * 0.8, "{c.series_name}:", dim)
        lx += text_width("{c.series_name}:") + u(10.0)
    }
    let shown = min(length(c.series), 24)
    for (i in range(shown)) {
        let name = c.series[i].name
        let iw = u(18.0) + text_width(name) + u(12.0)
        if (lx + iw > x + w && lx > x + u(8.0)) {
            lx = x + u(8.0)
            ly += fs + u(4.0)
        }
        *dl |> AddRectFilled(ImVec2(lx, ly + fs * 0.3), ImVec2(lx + u(12.0), ly + fs * 0.3 + u(6.0)),
            abgr(chart_color(i)), u(2.0), ImDrawFlags.None)
        text_at_baseline(lx + u(16.0), ly + fs * 0.8, name, fg)
        lx += iw
    }
    if (length(c.series) > shown) {
        text_at_baseline(lx, ly + fs * 0.8, "+{length(c.series) - shown} more", dim)
    }
    // the y name has a line of its own, under the legend
    let yname = c.log_y ? "{c.y_name}  (log)" : c.y_name
    text_at_baseline(x + u(8.0), ly + fs * 2.0 + u(6.0), yname, fg)
    let top = ly + fs * 2.0 + u(14.0)
    let left = x + u(64.0)
    let right = x + w - u(14.0)
    let bottom = y + h - u(40.0)
    if (right - left < u(40.0) || bottom - top < u(40.0)) {
        return hover
    }
    // ranges in the transformed space
    let categorical = length(c.categories) > 0
    var x0 = 1.0e300lf
    var x1 = -1.0e300lf
    var y0 = 1.0e300lf
    var y1 = -1.0e300lf
    for (s in c.series) {
        for (k in range(length(s.xs))) {
            let tx = categorical ? s.xs[k] : tr(s.xs[k], c.log_x)
            let ty = tr(s.ys[k], c.log_y)
            x0 = min(x0, tx)
            x1 = max(x1, tx)
            y0 = min(y0, ty)
            y1 = max(y1, ty)
        }
    }
    if (x0 > x1) {
        text_at_baseline(left, top + fs, "No points to plot", dim)
        return hover
    }
    if (categorical) {
        x0 = -0.5lf
        x1 = double(length(c.categories)) - 0.5lf
    }
    if (c.kind == CH_BAR && !c.log_y) {
        y0 = min(y0, 0.0lf)
        y1 = max(y1, 0.0lf)
    }
    if (x1 - x0 < 1.0e-12lf) {
        x0 -= 1.0lf
        x1 += 1.0lf
    }
    if (y1 - y0 < 1.0e-12lf) {
        y0 -= 1.0lf
        y1 += 1.0lf
    }
    let pad = (y1 - y0) * 0.05lf
    y1 += pad
    if (!(c.kind == CH_BAR && y0 == 0.0lf)) {
        y0 -= pad
    }
    let sx = $(v : double) => float(double(left) + (v - x0) / (x1 - x0) * double(right - left))
    let sy = $(v : double) => float(double(bottom) - (v - y0) / (y1 - y0) * double(bottom - top))
    // plot area, grid, ticks
    *dl |> AddRectFilled(ImVec2(left, top), ImVec2(right, bottom), abgr(0x3c3c3cffu), 0.0, ImDrawFlags.None)
    var yat : array<double>
    var ylab : array<string>
    axis_ticks(y0, y1, c.log_y, max(2, int((bottom - top) / u(40.0))), yat, ylab)
    for (k in range(length(yat))) {
        let py = sy(yat[k])
        *dl |> AddLine(ImVec2(left, py), ImVec2(right, py), abgr(0x4c4c4cffu), 1.0)
        text_at_baseline(left - u(6.0) - text_width(ylab[k]), py + fs * 0.35, ylab[k], dim)
    }
    if (categorical) {
        let slot = (right - left) / float(max(1, length(c.categories)))
        var every = 1
        var widest = 0.0
        for (s in c.categories) {
            widest = max(widest, text_width(s))
        }
        while (slot * float(every) < min(widest, u(110.0)) + u(8.0) && every < length(c.categories)) {
            every++
        }
        for (k in range(length(c.categories))) {
            if (k % every != 0) {
                continue
            }
            var s = c.categories[k]
            let room = slot * float(every) - u(6.0)
            while (length(s) > 3 && text_width(s) > room) {
                s = slice(s, 0, length(s) - 2)
            }
            let px = sx(double(k))
            text_at_baseline(px - text_width(s) * 0.5, bottom + fs + u(4.0), s, dim)
        }
    } else {
        var xat : array<double>
        var xlab : array<string>
        axis_ticks(x0, x1, c.log_x, max(2, int((right - left) / u(70.0))), xat, xlab)
        for (k in range(length(xat))) {
            let px = sx(xat[k])
            *dl |> AddLine(ImVec2(px, top), ImVec2(px, bottom), abgr(0x4c4c4cffu), 1.0)
            text_at_baseline(px - text_width(xlab[k]) * 0.5, bottom + fs + u(4.0), xlab[k], dim)
        }
    }
    *dl |> AddRect(ImVec2(left, top), ImVec2(right, bottom), abgr(0x2a2a2affu), 0.0, ImDrawFlags.None, 1.0)
    let xname = c.log_x ? "{c.x_name}  (log)" : c.x_name
    text_at_baseline((left + right) * 0.5 - text_width(xname) * 0.5, bottom + fs * 2.0 + u(10.0), xname, fg)
    // the data
    let mouse = GetMousePos()
    var best = u(10.0) * u(10.0)
    *dl |> PushClipRect(ImVec2(left, top), ImVec2(right, bottom), true)
    let nser = length(c.series)
    let slot = categorical ? (right - left) / float(max(1, length(c.categories))) : 0.0
    let bar_w = slot * 0.8 / float(max(1, nser))
    for (i in range(nser)) {
        let s & = unsafe(c.series[i])
        let col = abgr(chart_color(i))
        let n = length(s.xs)
        // points of a line in x order
        var order <- [for (k in range(n)); k]
        if (c.kind == CH_LINE) {
            sort(order) $(a, b) => s.xs[a] < s.xs[b]
        }
        var prev = ImVec2(0.0, 0.0)
        for (j in range(n)) {
            let k = order[j]
            let tx = categorical ? s.xs[k] : tr(s.xs[k], c.log_x)
            var px = sx(tx)
            let py = sy(tr(s.ys[k], c.log_y))
            if (c.kind == CH_BAR) {
                px = sx(s.xs[k]) - slot * 0.4 + bar_w * (float(i) + 0.5)
                let base = sy(c.log_y ? y0 : 0.0lf)
                *dl |> AddRectFilled(ImVec2(px - bar_w * 0.45, min(py, base)), ImVec2(px + bar_w * 0.45, max(py, base)),
                    col, 0.0, ImDrawFlags.None)
                if (mouse.x >= px - bar_w * 0.5 && mouse.x <= px + bar_w * 0.5 && mouse.y >= min(py, base) - u(2.0)
                        && mouse.y <= max(py, base) + u(2.0)) {
                    hover = ChartHover(series = i, point = k)
                    best = 0.0
                }
                continue
            }
            if (c.kind == CH_LINE && j > 0) {
                *dl |> AddLine(prev, ImVec2(px, py), col, u(2.0))
            }
            if (c.kind == CH_SCATTER || n <= 40) {
                *dl |> AddCircleFilled(ImVec2(px, py), c.kind == CH_SCATTER ? u(3.5) : u(2.5), col, 12)
            }
            prev = ImVec2(px, py)
            let dx = mouse.x - px
            let dy = mouse.y - py
            if (dx * dx + dy * dy < best) {
                best = dx * dx + dy * dy
                hover = ChartHover(series = i, point = k)
            }
        }
    }
    *dl |> PopClipRect()
    SetCursorScreenPos(ImVec2(left, top))
    InvisibleButton("##{id}_plot", ImVec2(right - left, bottom - top))
    if (!IsItemHovered()) {
        return ChartHover()
    }
    if (hover.series >= 0) {
        let s & = unsafe(c.series[hover.series])
        let k = hover.point
        let xs = categorical ? c.categories[int(s.xs[k])] : value_text(vnum(s.xs[k]))
        if (c.kind != CH_BAR) {
            let px = sx(categorical ? s.xs[k] : tr(s.xs[k], c.log_x))
            let py = sy(tr(s.ys[k], c.log_y))
            *dl |> AddCircle(ImVec2(px, py), u(5.0), abgr(0xffffffffu), 12, u(1.5))
        }
        let head = c.series_name != "" ? "{c.series_name} = {s.name}" : s.name
        bl_tooltip("{head}\n{c.x_name} = {xs}\n{c.y_name} = {value_text(vnum(s.ys[k]))}")
    }
    return hover
}
