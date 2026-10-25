options gen2
options indenting = 4
options stack = 1000000     // the dasPEG parser of the Explore language recurses
// every frame builds strings and arrays: the host collects the heap
// between frames (web/runner.cpp), which needs these two
options persistent_heap
options gc

// Web entry (web/: standalone AOT build). The browser owns the loop: the
// host calls app_init / app_frame / app_event / app_quit, and app_reload
// after the page put new files at the --state / --rom paths.
require dassdl3/sdl3_boost
require dassdl3/sdl3_scope
require math
require imgui
require imgui_sdl3
require gui_common
require strings
require app/shell
require core/game
require games/ffta/ffta
require games/ffta2/ffta2
require games/fftwotl/fftwotl

var window : SDL_Window?
var renderer : SDL_Renderer?
var context : ImGuiContext?
var last : uint64

def report(result : SdlStatus) : int {
    if (is_err(result)) {
        let error = unwrap_err(result)
        print("{error.operation}: {error.message}\n")
        return -1
    }
    return 0
}

let WINDOW_FILL_DOCUMENT = 0x200000ul    // SDL 3.4: the canvas follows the page size

def initialize() : SdlStatus {
    sdl_init() |> sdl_try
    window = create_window("DasBattleCalc", 1280, 800, SDL_WINDOW_RESIZABLE | WINDOW_FILL_DOCUMENT) |> sdl_try
    renderer = create_renderer(window) |> sdl_try
    context = CreateContext(null)
    SetCurrentContext(context)
    sdl_status(ImGui_SDL3_Init(window, renderer), "ImGui_SDL3_Init") |> sdl_try
    register_game(new FftaGame())
    register_game(new Ffta2Game())
    register_game(new WotlGame())
    shell_init(renderer, to_float(gui_arg("--ui-scale", "1.0")))
    last = SDL_GetTicks()
    return sdl_ok()
}

def draw_frame() : SdlStatus {
    let now = SDL_GetTicks()
    let dt = min(float(now - last) / 1000.0, 0.1)
    last = now
    ImGui_ImplSDLRenderer3_NewFrame()
    ImGui_ImplSDL3_NewFrame()
    NewFrame()
    shell_frame(dt)       // File > Quit: a page can not close itself
    Render()
    renderer |> clear(shell_background()) |> sdl_try
    ImGui_SDL3_Render(renderer)
    renderer |> present() |> sdl_try
    return sdl_ok()
}

[export]
def app_init() : int {
    return report(initialize())
}

[export]
def app_frame() : int {
    return report(draw_frame())
}

[export]
def app_event(event : SDL_Event) : int {
    ImGui_SDL3_ProcessEvent(event)
    return SDL_EventIsQuit(event) ? 1 : 0
}

[export]
def app_reload() : int {
    shell_reload()
    return 0
}

[export]
def app_quit() : void {
    shell_shutdown()
    if (context != null) {
        ImGui_ImplSDLRenderer3_Shutdown()
        ImGui_ImplSDL3_Shutdown()
        DestroyContext(context)
        context = null
    }
    destroy_renderer(renderer)
    renderer = null
    destroy_window(window)
    window = null
}
