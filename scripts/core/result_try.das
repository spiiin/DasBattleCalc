options gen2
options indenting = 4

// Early return on an error string, in the spirit of a Result builder's
// bind: our loaders return "" on success or the error text. In a
// function (or block) that returns string:
//
//   def load_files() : string {
//       try_ok(gba_load_rom(path), "ROM: ")       // error -> "ROM: " + error
//       ensure(gba_rom_code() == "AFXE", "not FFTA (USA)")
//       try_ok(read_battle(units))
//       return ""
//   }
//
// try_ok(err [, prefix]) evaluates err once; if it is not "", the
// enclosing function returns prefix + err. ensure(cond, msg) returns msg
// when cond is false. Both are statements, not expressions.
module result_try shared public

require daslib/ast
require daslib/ast_boost
require daslib/templates_boost
require daslib/macro_boost

def private is_string(e : ExpressionPtr) : bool {
    return e._type != null && e._type.baseType == Type.tString
}

[call_macro(name="try_ok")]
class private TryOkMacro : AstCallMacro {
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        let n = length(expr.arguments)
        macro_verify(n == 1 || n == 2, prog, expr.at, "try_ok(err) or try_ok(err, prefix)")
        macro_verify(is_string(expr.arguments[0]), prog, expr.at,
            "try_ok: the first argument must be a string (\"\" = success)")
        macro_verify(n == 1 || is_string(expr.arguments[1]), prog, expr.at,
            "try_ok: the prefix must be a string")
        let name = make_unique_private_name("__try_err", expr.at)
        var value = clone_expression(expr.arguments[0])
        if (n == 1) {
            return <- qmacro_block() {
                let $i(name) = $e(value)
                if ($i(name) != "") {
                    return $i(name)
                }
            }
        }
        var prefix = clone_expression(expr.arguments[1])
        return <- qmacro_block() {
            let $i(name) = $e(value)
            if ($i(name) != "") {
                return $e(prefix) + $i(name)
            }
        }
    }
}

[call_macro(name="ensure")]
class private EnsureMacro : AstCallMacro {
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments) == 2, prog, expr.at, "ensure(condition, message)")
        let c = expr.arguments[0]
        macro_verify(c._type != null && c._type.baseType == Type.tBool, prog, expr.at,
            "ensure: the condition must be bool")
        macro_verify(is_string(expr.arguments[1]), prog, expr.at, "ensure: the message must be a string")
        var cond = clone_expression(c)
        var msg = clone_expression(expr.arguments[1])
        return <- qmacro_block() {
            if (!($e(cond))) {
                return $e(msg)
            }
        }
    }
}
