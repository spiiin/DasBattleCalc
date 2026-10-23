// Web only: dasImgui calls the dasClipboard C API for ImGui copy / paste. dasClipboard
// has no Web backend, so the two functions it needs go through SDL (SDL3
// keeps an in-page clipboard and uses the browser one where allowed).
#include "daScript/daScript.h"
#include "aot_builtin_clipboard.h"
#include <SDL3/SDL.h>
#include <string>

namespace das {
static std::string g_clip;

int32_t builtin_clipboard_set_text(const char * text, int32_t text_size) {
    g_clip.assign(text, size_t(text_size));
    return SDL_SetClipboardText(g_clip.c_str()) ? int32_t(ClipboardStatus::ok) : int32_t(ClipboardStatus::failed);
}

const char * builtin_clipboard_get_text_temporary(int32_t & status) {
    char * s = SDL_GetClipboardText();
    g_clip = s ? s : "";
    SDL_free(s);
    status = int32_t(g_clip.empty() ? ClipboardStatus::no_text : ClipboardStatus::ok);
    return g_clip.c_str();
}
}
