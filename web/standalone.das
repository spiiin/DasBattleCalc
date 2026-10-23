options gen2
require daslib/aot_standalone
require daslib/aot_cpp
require daslib/ast
require daslib/rtti
require daslib/c_api_header

// Build-time only (web/generator.cpp, as in dasNES): emits the program as
// standalone C++ (battlecalc.das.cpp / .h) - a context class whose methods
// are the [export] functions. No module registrations: the compiler must
// not get into the browser build.
[export]
def emit(var program : ProgramPtr; var pctx : smart_ptr<Context>; output : string) : bool {
    let (modules, no_aot) = getRequiredModulesFor(program, true)
    verify(!no_aot)
    var registrations : array<StandaloneModuleEntry>
    let cfg = StandaloneContextCfg(context_name = "ctx_bc", file_stem = "battlecalc", class_name = "Standalone",
        cpp_output_dir = output, registers_modules = false)
    return runStandaloneVisitor(program, modules, registrations, pctx, cfg)
}
