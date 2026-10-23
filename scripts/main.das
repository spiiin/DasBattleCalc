options gen2
options indenting = 4
// every frame builds strings and arrays (UI text, lists): the default
// linear heap only grows, so collect it between frames
options persistent_heap
options gc

// Desktop entry: SDL window + renderer, the ImGui backends and our loop.
// Options: --ui-scale K, --shot file.png [--frames N], --script "...".
require dassdl3/sdl3_imgui
require dassdl3/sdl3_scope
require gui_common
require strings
require app/shell
require core/game
require games/ffta/ffta

// between frames; collecting is cheap while the heap is small
let COLLECT_BYTES = 0x1000000ul     // 16 MB of heap + strings

def collect_frame_garbage() {
    if (heap_bytes_allocated() + string_heap_bytes_allocated() > COLLECT_BYTES) {
        unsafe {
            heap_collect(true, false)
        }
    }
}

def run(window : SDL_Window?; renderer : SDL_Renderer?) : SdlStatus {
    register_game(new FftaGame())
    shell_init(renderer, to_float(gui_arg("--ui-scale", "1.3")))
    let shot = gui_arg("--shot", "")
    let max_frames = gui_arg_int("--frames", shot != "" ? 8 : gui_script_end() + 1)
    var frames = 0
    var running = true
    var event = SDL_MakeEvent()
    var last = SDL_GetTicks()
    while (running) {
        gui_script_step(window, frames)
        while (is_some(poll_event(event))) {
            ImGui_SDL3_ProcessEvent(event)
            if (SDL_EventIsQuit(event)) {
                running = false
            }
        }
        let now = SDL_GetTicks()
        let dt = shot != "" ? 1.0 / 30.0 : float(now - last) / 1000.0
        last = now
        ImGui_ImplSDLRenderer3_NewFrame()
        ImGui_ImplSDL3_NewFrame()
        NewFrame()
        running = shell_frame(dt) && running
        Render()
        renderer |> clear(shell_background()) |> sdl_try
        ImGui_SDL3_Render(renderer)
        let script_shot = gui_script_shot(frames)
        if (script_shot != "") {
            gui_save_renderer_png(renderer, script_shot)
        }
        frames++
        collect_frame_garbage()
        if (shot != "" && frames == max_frames) {
            gui_save_renderer_png(renderer, shot)
        }
        renderer |> present() |> sdl_try
        if (max_frames > 0 && frames >= max_frames) {
            break
        }
    }
    shell_shutdown()
    return sdl_ok()
}

[export]
def main() : int {
    let result = sdl_scope() {
        with_sdl(SDL_INIT_VIDEO) |> sdl_use
        let window : SDL_Window? = with_window("DasBattleCalc", 1600, 900, SDL_WINDOW_RESIZABLE) |> sdl_use
        let renderer : SDL_Renderer? = window |> with_renderer() |> sdl_use
        with_imgui(window, renderer) |> sdl_use
        return run(window, renderer)
    }
    if (is_err(result)) {
        let error = unwrap_err(result)
        print("{error.operation}: {error.message}\n")
        return 1
    }
    return 0
}
