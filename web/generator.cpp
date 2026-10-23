// Build-time AOT generator (wasm32, runs in Node): compiles
// scripts/main_web.das with all native modules and emits standalone C++
// through web/standalone.das. Pattern of dasNES native/standalone_generate.cpp.
// usage: node generator.js <project> <out> <daScript root> <dassdl3 dir> <dasImgui daslib dir>
#include "daScript/daScript.h"
#include <emscripten.h>
#include <fstream>
#include <iostream>

DECLARE_MODULE(Module_dasSDL3);
DECLARE_MODULE(Module_dasIMGUI);
DECLARE_MODULE(Module_imgui_sdl3);
DECLARE_MODULE(Module_gui_common);
DECLARE_MODULE(Module_imgui_ext);
DECLARE_MODULE(Module_gba_mem);
using namespace das;

static int generate() {
    TextPrinter log;
    auto access = make_smart<FsFileAccess>();
    access->addFsRoot("dassdl3", "/dassdl3");
    access->addFsRoot("dasimgui", "/dasimgui");
    access->addFsRoot("peg", "/das/modules/dasPEG/peg");
    access->addFsRoot("detail", "/das/modules/dasPEG/peg/detail");
    CodeOfPolicies policy;
    policy.aot_module = true;
    policy.tune_frozen = true;
    policy.fail_on_lack_of_aot_export = true;
    policy.keep_symbol_tables = true;   // the emitter reads global / function indices after simulate
    // separate module groups: the emitter's modules (aot_cpp, ast, ...)
    // must not count as part of the program
    ModuleGroup modules, driverModules;
    auto program = compileDaScript("/app/scripts/main_web.das", access, log, modules, policy);
    if (program->failed()) {
        for (auto & e : program->errors) log << reportError(e.at, e.what, e.extra, e.fixme, e.cerr);
        return 1;
    }
    auto context = make_smart<Context>(program->getContextStackSize());
    if (!program->simulate(*context, log)) return 2;
    auto driver = compileDaScript("/app/web/standalone.das", access, log, driverModules, policy);
    if (driver->failed()) {
        for (auto & e : driver->errors) log << reportError(e.at, e.what, e.extra, e.fixme, e.cerr);
        return 1;
    }
    Context driverContext(driver->getContextStackSize());
    if (!driver->simulate(driverContext, log)) return 2;
    auto entry = driverContext.findFunction("emit");
    if (!entry) return 3;
    const char * output = "/out";
    vec4f args[] = {cast<Program *>::from(program.get()), cast<Context *>::from(context.get()), cast<char *>::from(output)};
    auto value = driverContext.evalWithCatch(entry, args);
    if (auto error = driverContext.getException()) { log << error << "\n"; return 4; }
    if (!cast<bool>::to(value)) return 5;
    // dasSDL3's catch-order workaround for the pinned daScript (as dasNES)
    const std::string path = "/out/battlecalc.das.cpp";
    std::ifstream in(path, std::ios::binary);
    if (!in) return 6;
    std::string generated((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    in.close();
    const std::string from = "das_try_recover(__context__,", to = "das::SDL_AotTryRecover(__context__,";
    for (size_t pos = 0; (pos = generated.find(from, pos)) != std::string::npos; pos += to.size())
        generated.replace(pos, from.size(), to);
    std::ofstream out(path, std::ios::binary);
    out << generated;
    return out ? 0 : 7;
}

int main(int argc, char ** argv) {
    if (argc != 6) return 8;
    EM_ASM({
        const mount = (dir, root) => { FS.mkdir(dir); FS.mount(NODEFS, {root: UTF8ToString(root)}, dir); };
        mount('/app', $0); mount('/out', $1); mount('/das', $2); mount('/dassdl3', $3); mount('/dasimgui', $4);
    }, argv[1], argv[2], argv[3], argv[4], argv[5]);
    setDasRoot("/das");
    NEED_ALL_DEFAULT_MODULES;
    NEED_MODULE(Module_dasSDL3);
    NEED_MODULE(Module_dasIMGUI);
    NEED_MODULE(Module_imgui_sdl3);
    NEED_MODULE(Module_gui_common);
    NEED_MODULE(Module_imgui_ext);
    NEED_MODULE(Module_gba_mem);
    Module::Initialize();
    int result = 1;
    try {
        result = generate();
    } catch (const std::exception & e) {
        std::cerr << "Standalone generation failed: " << e.what() << '\n';
    }
    Module::Shutdown();
    if (result) std::cerr << "generator: error " << result << '\n';
    return result;
}
