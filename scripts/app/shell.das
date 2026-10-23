options gen2
options indenting = 4

// The application shell: main menu, status bar, dock layout and the four
// panels, filled by the current GameModule. Desktop and Web entries call
// shell_init / shell_frame / shell_shutdown around their own SDL loop.
module shell shared public

require sdl3
require imgui
require dasimgui/imgui_boost
require gui_common
require imgui_ext
require math
require strings
require ../ui/bnd_const.das
require ../ui/icons.das
require ../ui/bl_imgui.das
require ../core/game.das

var ui_scale = 1.3
var private current = 0
var private frame_no = 0
var private want_quit = false
var private renderer_ : SDL_Renderer?
var private layout_size = float2(0.0, 0.0)

// the renderer of the main window (for textures made by games)
def shell_renderer() : SDL_Renderer? {
    return renderer_
}

def at(x, y : float) {
    SetCursorScreenPos(ImVec2(x, y))
}

// A docked panel without a tab bar; returns its rectangle.
def panel(name : string) : float4 {
    Begin(name, null, ImGuiWindowFlags.None)
    imx_hide_tab_bar()
    let p = GetWindowPos()
    let s = GetWindowSize()
    return float4(p.x, p.y, s.x, s.y)
}

def panel_header(r : float4; caption : string; icon : int) {
    at(r.x + u(4.0), r.y + u(1.0))
    bl_label(caption, icon)
}

def menu(title : string; items : array<string>) : int {
    var picked = -1
    bl_push_popup_style()
    if (BeginMenu(title, true)) {
        bl_popup_rows() {
            for (i in range(length(items))) {
                if (bl_menu_item(items[i])) {
                    picked = i
                }
            }
        }
        EndMenu()
    }
    bl_pop_popup_style()
    return picked
}

def current_game() : GameModule? {
    return game_count() > 0 ? game_at(current) : null
}

def private menu_bar() {
    PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(u(4.0), u(3.0)))
    if (BeginMainMenuBar()) {
        if (menu("File", ["Quit"]) == 0) {
            want_quit = true
        }
        var titles : array<string>
        for (i in range(game_count())) {
            titles |> push(game_at(i)->title())
        }
        let g = menu("Game", titles)
        if (g >= 0 && g != current) {
            current = g
            log_line("game: {titles[g]}")
        }
        let v = menu("View", ["UI Scale +", "UI Scale -", "UI Scale 100%"])
        if (v >= 0) {
            ui_scale = v == 0 ? min(ui_scale + 0.1, 3.0) : (v == 1 ? max(ui_scale - 0.1, 0.6) : 1.0)
            bl_apply_style(ui_scale)
        }
        var game = current_game()
        if (game != null) {
            let caption = game->title()
            let label_w = u(BND_PAD_LEFT + BND_PAD_RIGHT + 16.0) + text_width(caption)
            SameLine(GetWindowWidth() - label_w - u(8.0), -1.0)
            bl_label(caption, ICON_GAME)
        }
        EndMainMenuBar()
    }
    PopStyleVar(1)
}

def private status_bar() {
    if (imx_begin_status_bar(u(24.0))) {
        let p = GetWindowPos()
        at(p.x + u(6.0), p.y + u(1.0))
        var game = current_game()
        bl_label(game != null ? game->status() : "no game", ICON_INFO)
    }
    End()
}

def private dock_layout(dockspace : uint) {
    let vp = GetMainViewport()
    DockBuilderSetNodeSize(dockspace, vp.WorkSize)
    var left, rest, right, center, bottom, middle : uint
    DockBuilderSplitNode(dockspace, ImGuiDir.Left, 0.22, left, rest)
    DockBuilderSplitNode(rest, ImGuiDir.Right, 0.32, right, center)
    DockBuilderSplitNode(center, ImGuiDir.Down, 0.42, bottom, middle)
    DockBuilderDockWindow("Roster", left)
    DockBuilderDockWindow("Inspector", right)
    DockBuilderDockWindow("Battle", middle)
    DockBuilderDockWindow("Calc", bottom)
    DockBuilderFinish(dockspace)
}

// Fonts, icons and style; the ImGui context must be current.
def shell_init(renderer : SDL_Renderer?; scale : float) {
    DisableIniPersistence()
    renderer_ = unsafe(reinterpret<SDL_Renderer?>(renderer))
    var io & = unsafe(GetIO())
    io.ConfigFlags |= ImGuiConfigFlags.DockingEnable
    let dir = gui_project_dir()
    var font = *io.Fonts |> AddFontFromFileTTF("{dir}/assets/fonts/DejaVuSans.ttf", 15.0, null, null)
    io.FontDefault = font
    imx_load_icons(renderer, "{dir}/assets/icons/ffta_icons16.png")
    ui_scale = scale
    bl_apply_style(ui_scale)
    frame_no = 0
    want_quit = false
}

// One ImGui frame (between NewFrame and Render); false after File > Quit.
def shell_frame(dt : float) : bool {
    menu_bar()
    status_bar()      // a side bar: before the dock space takes the rest
    let dockspace = DockSpaceOverViewport(0u, GetMainViewport(), 0, null)
    // lay out at start, and again while the window still settles (a page
    // canvas gets its size a few frames later)
    let ws = GetMainViewport().WorkSize
    if (frame_no == 0 || (frame_no < 120 && (abs(ws.x - layout_size.x) > 1.0 || abs(ws.y - layout_size.y) > 1.0))) {
        dock_layout(dockspace)
        layout_size = float2(ws.x, ws.y)
    }
    frame_no++
    var game = current_game()
    var r = panel("Roster")
    panel_header(r, "Roster", ICON_ROSTER)
    if (game != null) {
        game->draw_roster(r.x, r.y + u(26.0), r.z, r.w - u(26.0))
    }
    End()
    r = panel("Inspector")
    panel_header(r, "Inspector", ICON_INSPECTOR)
    if (game != null) {
        // the fields scroll in a child window under the header
        at(r.x, r.y + u(26.0))
        BeginChild("inspector_body", ImVec2(r.z, r.w - u(26.0)), ImGuiChildFlags.None, ImGuiWindowFlags.None)
        let top = GetCursorScreenPos().y
        let bottom = game->draw_inspector(r.x + u(8.0), top + u(4.0), GetContentRegionAvail().x - u(16.0))
        at(r.x, bottom)
        Dummy(ImVec2(1.0, u(8.0)))
        EndChild()
    }
    End()
    r = panel("Battle")
    if (game != null) {
        game->draw_scene(r.x, r.y, r.z, r.w)
    }
    End()
    r = panel("Calc")
    panel_header(r, "Calculation", ICON_CALC)
    if (game != null) {
        game->draw_calc(r.x + u(8.0), r.y + u(28.0), r.z - u(16.0), r.w - u(32.0))
    }
    End()
    return !want_quit
}

// Clear color of the frame (Blendish background), r, g, b, a in 0..255.
def shell_background() : uint4 {
    let c = bt.background
    return uint4((c >> 24u) & 255u, (c >> 16u) & 255u, (c >> 8u) & 255u, 255u)
}

def shell_shutdown() {
    pass
}
