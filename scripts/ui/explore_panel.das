options gen2
options indenting = 4

// The Explore tab of a game (Calculation > Explore) and its chart (Battle
// > Chart): the editor with the game's examples, the table and the chart
// of the last run. Game-agnostic: the game runs a parsed script (`run`)
// and tells which unit parameters exist (`is_param`, for the colors).
module explore_panel shared public

require imgui
require dasimgui/imgui_boost
require gui_common
require math
require strings
require daslib/strings_boost
require bnd_const
require bl_imgui
require icons
require ../core/explore.das
require ./explore_view.das

struct ExplorePanel {
    id : string                     // the prefix of the widget ids
    names : array<string>           // the examples: their names and scripts
    examples : array<string>
    generators : array<string>      // what `vary x <generator>` takes
    metrics : array<string>         // the columns of every point
    src : ImGuiInputTextBuffer
    example : int
    points : ETable = ETable()      // the table of the last run
    chart : Chart = Chart()
    error : string
    info : string
    version : int
    ran : bool
    tview : TableView = TableView()
    split : float = 0.42            // the editor's share of the width (the bar drags it)
}

// the run of a parsed script: the table of points, "" or the error
typedef ExploreRun = block<(var s : Script; var t : ETable) : string>

// is_param: the game has a unit parameter of this name (after "atk.")
typedef ExploreParam = block<(key : string) : bool>

def make_explore_panel(id : string; names, examples, generators, metrics) : ExplorePanel {
    var p = ExplorePanel(id = id, src = ImGuiInputTextBuffer(examples[0], 8192))
    p.names |> push_from(names)
    p.examples |> push_from(examples)
    p.generators |> push_from(generators)
    p.metrics |> push_from(metrics)
    return <- p
}

// the colors of the highlighting kinds (HL_*): statements, words, names
// (by the game), numbers, strings, comments, functions, operators, columns
let private HL_COLORS = fixed_array<uint>(0xdcdcdcffu, 0xf0c040ffu, 0x80b8f0ffu, 0u, 0xf0a060ffu, 0xb0e090ffu,
    0x8c8c8cffu, 0xc8a0f0ffu, 0xc8c8c8ffu, 0xf0e0a0ffu)

// the color of a word of the script; defs: the columns it makes
def explore_color(p : ExplorePanel; sp : HlSpan; defs : array<string>; is_param : ExploreParam) : uint {
    if (sp.kind != HL_NAME) {
        return sp.kind >= 0 && sp.kind < length(HL_COLORS) ? HL_COLORS[sp.kind] : HL_COLORS[HL_PLAIN]
    }
    let name = sp.text
    if (find_index(p.generators, name) >= 0) {
        return HL_COLORS[HL_FUNC]
    }
    if (find_index(p.metrics, name) >= 0) {
        return 0x60d0d0ffu          // a column of every point
    }
    if (find_index(defs, name) >= 0) {
        return HL_COLORS[HL_DEF]
    }
    if (name == "side" || name == "action") {
        return 0x90d070ffu
    }
    let dot = find(name, ".")
    if (dot > 0) {
        let owner = slice(name, 0, dot)
        if ((owner == "atk" || owner == "tgt" || owner == "attacker" || owner == "target")
                && invoke(is_param, slice(name, dot + 1))) {
            return 0x90d070ffu      // a parameter
        }
    }
    return 0xff7070ffu              // nothing by this name: a typo?
}

def explore_run(var p : ExplorePanel; run : ExploreRun) {
    p.ran = true
    let t0 = ref_time_ticks()
    var s = Script()
    var err = parse_script(to_string(p.src), s)
    if (err == "") {
        err = invoke(run, s, p.points)
    }
    if (err == "") {
        let xn = length(p.points.names) > 0 ? p.points.names[0] : "damage"
        err = build_chart(s, p.points, xn, "damage", p.chart)
    }
    if (err != "") {
        p.points = ETable()
        p.chart = Chart()
    }
    p.error = err
    p.version++
    let ms = get_time_usec(t0) / 1000
    p.info = err == "" ? "{length(p.points.rows)} rows x {length(p.points.names)} columns, {ms} ms" : ""
}

// Calculation > Explore: examples, Run; the script; the table. The
// table as CSV goes next to the state (returns the message).
def explore_view(var p : ExplorePanel; x, y, w, h : float; state_path : string; is_param : ExploreParam;
                 run : ExploreRun) : string {
    if (!p.ran) {
        p |> explore_run(run)
    }
    let ew = floor(w * p.split)
    // the bar between the editor and the table: drag to resize
    SetCursorScreenPos(ImVec2(x + ew + u(1.0), y + u(26.0)))
    InvisibleButton("##{p.id}_split", ImVec2(u(6.0), max(u(10.0), h - u(26.0))))
    if (IsItemHovered() || IsItemActive()) {
        SetMouseCursor(ImGuiMouseCursor.ResizeEW)
        *GetWindowDrawList() |> AddRectFilled(ImVec2(x + ew + u(3.0), y + u(26.0)), ImVec2(x + ew + u(5.0), y + h),
            abgr(bt.menu_item.inner_sel), 0.0, ImDrawFlags.None)
    }
    if (IsItemActive()) {
        p.split = clamp((GetMousePos().x - x - u(4.0)) / w, 0.15, 0.85)
    }
    SetCursorScreenPos(ImVec2(x, y))
    var pick = p.example
    if (bl_choice("{p.id}_example", p.names, pick, ew - u(88.0))) {
        p.example = pick
        p.src = ImGuiInputTextBuffer(p.examples[pick], 8192)
        p |> explore_run(run)
    }
    SetCursorScreenPos(ImVec2(x + ew - u(80.0), y))
    let run_click = bl_tool_button("{p.id}_run", "Run", ICON_CHART, u(80.0))
    let eh = h - u(26.0) - (p.error != "" ? u(22.0) : 0.0)
    SetCursorScreenPos(ImVec2(x, y + u(26.0)))
    // the columns the script makes (name = ...), the line of the error
    var defs : array<string>
    for (line in split(to_string(p.src), "\n")) {
        var spans : array<HlSpan>
        highlight_line(line, spans)
        if (length(spans) > 0 && spans[0].kind == HL_DEF) {
            defs |> push(spans[0].text)
        }
    }
    var error_line = 0
    if (starts_with(p.error, "line ")) {
        error_line = to_int(slice(p.error, 5, max(5, find(p.error, ":"))))
    }
    bl_code_area("{p.id}_src", p.src, ew, max(u(40.0), eh), error_line) $(line; var out) {
        var spans : array<HlSpan>
        highlight_line(line, spans)
        for (sp in spans) {
            out |> push(CodeSpan(start = sp.start, stop = sp.stop, color = explore_color(p, sp, defs, is_param)))
        }
    }
    let editing = IsItemActive()
    // Ctrl+Enter in the editor runs it too
    if (run_click || (editing && GetIO().KeyCtrl && IsKeyPressed(ImGuiKey.Enter, false))) {
        p |> explore_run(run)
    }
    if (p.error != "") {
        SetCursorScreenPos(ImVec2(x, y + h - u(21.0)))
        bl_label(p.error, ICON_INFO, ew, 0xff8080ffu)
        if (IsItemHovered()) {
            bl_tooltip(p.error)
        }
    }
    let tx = x + ew + u(8.0)
    let tw = w - ew - u(8.0)
    let cw = u(70.0)
    SetCursorScreenPos(ImVec2(tx, y))
    bl_label(p.info != "" ? "{p.info}; chart: Battle > Chart" : "", ICON_INFO, tw - cw - u(4.0))
    SetCursorScreenPos(ImVec2(tx + tw - cw, y))
    var message = ""
    if (bl_tool_button("{p.id}_csv", "CSV", ICON_EXPORT, cw) && length(p.points.names) > 0) {
        message = explore_csv(p, state_path)
    }
    draw_etable("{p.id}_table", p.points, p.version, p.tview, tx, y + u(26.0), tw, h - u(26.0))
    return message
}

// the table as CSV in the order it is shown, next to the state: on the
// desktop a file, in the browser a download (gui_save_text)
def explore_csv(p : ExplorePanel; state_path : string) : string {
    let dot = find(state_path, ".", max(0, length(state_path) - 6))
    let base = dot >= 0 ? slice(state_path, 0, dot) : state_path
    let path = "{base}.explore.csv"
    let err = gui_save_text(path, table_csv(p.points, p.tview.order))
    return err != "" ? "CSV: {err}" : "table saved to {path}"
}

// Battle > Chart: the chart of the last Explore run (runs it first when
// there are units and it has not run yet)
def explore_chart_view(var p : ExplorePanel; x, y, w, h : float; have_units : bool; run : ExploreRun) {
    if (!p.ran && have_units) {
        p |> explore_run(run)
    }
    if (p.error != "") {
        SetCursorScreenPos(ImVec2(x + u(4.0), y + u(6.0)))
        bl_label("Explore: {p.error}", ICON_INFO)
        return
    }
    if (length(p.chart.series) == 0) {
        SetCursorScreenPos(ImVec2(x + u(4.0), y + u(6.0)))
        bl_label("No data: write an experiment in Calculation > Explore", ICON_INFO)
        return
    }
    draw_chart("{p.id}_chart", p.chart, x, y, w, h)
}
