#pragma once
// Common pieces of the hand written daScript bindings.
#include "daScript/daScript.h"
#include "daScript/ast/ast_interop.h"
#include "daScript/ast/ast_handle.h"
#include "gui_common.h"
#include <cmath>
#include <cstring>

MAKE_TYPE_FACTORY(SDL_Window, SDL_Window);
MAKE_TYPE_FACTORY(SDL_Renderer, SDL_Renderer);
MAKE_TYPE_FACTORY(SDL_Event, SDL_Event);
MAKE_TYPE_FACTORY(GuiFont, GuiFont);

// Binds a C function under its own name; worstDefault keeps calls from
// being optimized away (they all have UI side effects).
#define GUI_BIND(F) das::addExtern<DAS_BIND_FUN(F)>(*this, lib, #F, das::SideEffects::worstDefault, #F)
#define GUI_BIND_AS(F, NAME) das::addExtern<DAS_BIND_FUN(F)>(*this, lib, NAME, das::SideEffects::worstDefault, #F)

// An opaque native handle type, used only through pointers.
#define GUI_OPAQUE(NAME) addAnnotation(new das::DummyTypeAnnotation(#NAME, #NAME, 1, 1))

namespace gui_das {
// Copies a native buffer into a daScript string.
inline char * to_das_string(const char * s, int len, das::Context * ctx, das::LineInfoArg * at) {
    return ctx->allocateString(s, uint64_t(len), at);
}
// Requires sdl3 and gui_common (if not self) and starts a library.
inline bool start(das::Module * self, das::ModuleLibrary & lib, std::initializer_list<const char *> deps) {
    lib.addBuiltInModule();
    for (auto name : deps) {
        auto mod = das::Module::require(name);
        if (!mod || !mod->initDependencies()) return false;
        lib.addModule(mod);
    }
    (void)self;
    return true;
}
}
