// Desktop host: compiles a daScript entry script and calls its main().
// Usage: battlecalc [script.das] [--ui-scale K] [--shot out.png] [--frames N] [--script "..."]
#include "daScript/daScript.h"
#include "gui_common.h"
#include <SDL3/SDL.h>
#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>
#include <string>

DECLARE_MODULE(Module_dasSDL3);
DECLARE_MODULE(Module_dasIMGUI);
DECLARE_MODULE(Module_Clipboard);
DECLARE_MODULE(Module_imgui_sdl3);
DECLARE_MODULE(Module_gui_common);
DECLARE_MODULE(Module_imgui_ext);
DECLARE_MODULE(Module_gba_mem);

static int run_script(const char * path) {
    using namespace das;
    TextPrinter out;
    ModuleGroup modules;
    auto access = make_smart<FsFileAccess>();
    access->addFsRoot("dassdl3", DASSDL3_MODULE_ROOT_DIR);
    access->addFsRoot("dasimgui", std::string(DAS_ROOT_DIR) + "/modules/dasImgui/daslib");
    // dasPEG (parser generator): require peg/peg; its own detail/ modules
    access->addFsRoot("peg", std::string(DAS_ROOT_DIR) + "/modules/dasPEG/peg");
    access->addFsRoot("detail", std::string(DAS_ROOT_DIR) + "/modules/dasPEG/peg/detail");
    auto program = compileDaScript(path, access, out, modules);
    auto print_errors = [&] {
        for (const auto & err : program->errors)
            out << reportError(err.at, err.what, err.extra, err.fixme, err.cerr);
    };
    if (program->failed()) { print_errors(); return 1; }
    Context context(program->getContextStackSize());
    if (!program->simulate(context, out)) { print_errors(); return 1; }
    auto entry = context.findFunction("main");
    if (!entry || !verifyCall<int32_t>(entry->debugInfo, modules)) {
        out << "Expected [export] def main() : int\n";
        return 1;
    }
    auto value = context.evalWithCatch(entry, nullptr);
    if (const char * error = context.getException()) {
        out << "Script exception: " << error << "\n";
        return 1;
    }
    return cast<int32_t>::to(value);
}

int main(int argc, char ** argv) {
    gui_set_args(argc, argv);
    das::setCommandLineArguments(argc, argv);
    SDL_SetMainReady();
    das::setDasRoot(DAS_ROOT_DIR);
    NEED_ALL_DEFAULT_MODULES;
    NEED_MODULE(Module_dasSDL3);
    NEED_MODULE(Module_Clipboard);
    NEED_MODULE(Module_dasIMGUI);
    NEED_MODULE(Module_imgui_sdl3);
    NEED_MODULE(Module_gui_common);
    NEED_MODULE(Module_imgui_ext);
    NEED_MODULE(Module_gba_mem);
    das::Module::Initialize();
    // the first argument is the script unless it is an option
    std::string script = std::string(GUI_PROJECT_DIR) + "/scripts/main.das";
    if (argc > 1 && argv[1][0] != '-') script = argv[1];
    int status = run_script(script.c_str());
    SDL_Quit();
    das::Module::Shutdown();
    return status;
}
