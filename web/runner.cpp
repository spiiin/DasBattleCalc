// Web host: the standalone AOT context of scripts/main_web.das (no daScript
// compiler or interpreter in the page). SDL main callbacks drive it; the
// page calls web_reload() after writing new files, web_stop() to end.
#include "battlecalc.das.h"
#include "gui_common.h"
#define SDL_MAIN_USE_CALLBACKS 1
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <emscripten.h>
#include <cstdio>
#include <memory>

namespace {
struct Session {
    das::daScriptEnvironment environment;
    das::daScriptEnvironmentGuard guard{&environment, nullptr};
    std::unique_ptr<das::ctx_bc::Standalone> context;
    bool initialized = false;
};
Session * g_session = nullptr;
bool stop_requested = false, reload_requested = false;

template <typename F> SDL_AppResult invoke(F && call) {
    try {
        const int code = call();
        return code < 0 ? SDL_APP_FAILURE : code > 0 ? SDL_APP_SUCCESS : SDL_APP_CONTINUE;
    } catch (const std::exception & e) {
        fprintf(stderr, "Script exception: %s\n", e.what());
        return SDL_APP_FAILURE;
    }
}
}

extern "C" EMSCRIPTEN_KEEPALIVE void web_stop() { stop_requested = true; }
extern "C" EMSCRIPTEN_KEEPALIVE void web_reload() { reload_requested = true; }
// script heap + string heap in bytes (to watch it from the page console)
extern "C" EMSCRIPTEN_KEEPALIVE double web_heap_bytes() {
    if (!g_session || !g_session->context) return 0;
    auto & c = *g_session->context;
    return double(c.heap->bytesAllocated() + c.stringHeap->bytesAllocated());
}

SDL_AppResult SDL_AppInit(void ** appstate, int argc, char ** argv) {
    stop_requested = reload_requested = false;
    gui_set_args(argc, argv);
    auto * s = new Session();
    *appstate = g_session = s;
    return invoke([&] {
        s->context = std::make_unique<das::ctx_bc::Standalone>();
        s->initialized = true;
        return s->context->app_init();
    });
}

SDL_AppResult SDL_AppIterate(void * state) {
    if (stop_requested) return SDL_APP_SUCCESS;
    auto & s = *static_cast<Session *>(state);
    if (reload_requested) {
        reload_requested = false;
        const auto r = invoke([&] { return s.context->app_reload(); });
        if (r != SDL_APP_CONTINUE) return r;
    }
    const auto r = invoke([&] { return s.context->app_frame(); });
    // the frame's strings and arrays: nothing of the script is on the
    // stack here, the globals are the only roots
    if (s.context->heap->bytesAllocated() + s.context->stringHeap->bytesAllocated() > (16u << 20))
        s.context->collectHeap(nullptr, true, false);
    return r;
}

SDL_AppResult SDL_AppEvent(void * state, SDL_Event * event) {
    auto & s = *static_cast<Session *>(state);
    return invoke([&] { return s.context->app_event(*event); });
}

void SDL_AppQuit(void * state, SDL_AppResult result) {
    auto * s = static_cast<Session *>(state);
    if (s && s->initialized) {
        const auto cleanup = invoke([&] { s->context->app_quit(); return 0; });
        if (cleanup == SDL_APP_FAILURE) result = cleanup;
    }
    delete s;
    g_session = nullptr;
    SDL_Quit();
    das::clearGlobalAotLibrary();
    EM_ASM({ if (Module.onSessionEnd) Module.onSessionEnd($0); }, result == SDL_APP_FAILURE ? 1 : 0);
}
