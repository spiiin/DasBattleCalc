options gen2
options indenting = 4

// Explore: experiments over a game model, in a short language. Game-
// agnostic: the game turns the axes (vary) into a table of points; this
// module parses the script, evaluates expressions and runs the steps.
//
//   // comment
//   vary atk.watk 50..300 step 10        // an axis: both ends included
//   vary atk.job jobs                    // a generator of the game
//   vary tgt.wdef 50, 100, 150           // a list
//   avg = damage * hit_real / 100        // a computed column
//   where reach && avg > 0               // keep rows
//   sort avg desc                        // or: sort avg
//   plot avg, damage by atk.watk per atk.job bar log y title "..."
//   scene Marc vs Euver with Fire from back
//
// Parsed by a dasPEG grammar (peg_statement; modules/dasPEG of daScript).
// Expressions: numbers, "strings", true / false, column names (dotted:
// atk.watk), + - * / %, < <= > >= == !=, && || !, a ? b : c, calls: abs
// min max clamp round floor ceil sqrt pow exp log log10 log2. A statement
// ends at the end of a line, unless a ( is still open.
module explore shared public

require math
require daslib/match
require strings
require daslib/strings_boost
require peg/peg

// ------------------------------------------------------------ values

// a number, or a label with a number (a job: its name and id); a plain
// string has num 0
struct Value {
    num : double
    text : string
}

def vnum(x : double) : Value {
    return Value(num = x)
}

def vtext(s : string; x : double = 0.0lf) : Value {
    return Value(num = x, text = s)
}

def is_true(v : Value) : bool {
    return v.text != "" || v.num != 0.0lf
}

def value_text(v : Value) : string {
    if (v.text != "") {
        return v.text
    }
    if (is_nan(v.num)) {
        return "-"
    }
    // whole numbers without decimals (also 2.9999999999999996 = log10(1000))
    let r = round(v.num)
    if (abs(v.num - r) < 1.0e-9lf * max(1.0lf, abs(v.num)) && abs(v.num) < 1.0e15lf) {
        return "{int64(r)}"
    }
    return fmt(":.2f", v.num)
}

// sort order: labels by text, numbers by value
def value_less(a, b : Value) : bool {
    if (a.text != "" && b.text != "") {
        return a.text < b.text
    }
    return a.num < b.num
}

def value_equal(a, b : Value) : bool {
    if (a.text != "" || b.text != "") {
        return a.text == b.text
    }
    return a.num == b.num
}

// ------------------------------------------------------------ expressions


// What a node of the grammar is: an expression (Num .. List, the kinds of
// an ExprNode too), a statement, or an option of plot / scene.
enum NodeKind {
    Num
    Str
    Name
    Call
    Unary
    Binary
    Ternary
    List
    Expression                      // a statement: a lone expression
    Vary
    Let
    Where
    Sort
    SortDesc
    Plot
    Scene
    Items                           // Exprs: the items in args
    PlotY                           // plot options: the y list
    PlotBy
    PlotPer
    PlotKind
    PlotLog
    PlotTitle
    SceneVs                         // scene options
    SceneWith
    SceneFrom
}

struct ExprNode {
    kind : NodeKind
    num : double
    text : string                   // name, function, operator
    col : int = -1                  // NodeKind.Name: the column, after bind
    args : array<int>
}

// one expression: its nodes, the root, the source line
struct Expr {
    nodes : array<ExprNode>
    root : int = -1
    line : int
}

let FUNCTIONS = fixed_array<string>("abs", "min", "max", "clamp", "round", "floor", "ceil", "sqrt", "pow", "exp", "log",
    "log10", "log2")

// ------------------------------------------------------------ grammar (dasPEG)

// What the grammar builds; turned into an Expr / Script afterwards (the
// actions of a PEG parser must not change shared state - it backtracks).
// One type for every rule (lists and the void-like ones too): dasPEG keeps
// a cache per rule, and caches of different types made generic instances
// with the same name (internal error in the interpreter, wrong calls in
// the AOT C++).
struct PNode {
    kind : NodeKind
    num : double
    text : string                   // for: the path, let: the column
    args : array<PNode?>
}


// a fresh node of kind with the items of a list node
def private relist(kind : NodeKind; text : string; var l : PNode?) : PNode? {
    var n = new PNode(kind = kind, text = text)
    for (a in l.args) {
        n.args |> push(a)
    }
    return n
}

def private pn(kind : NodeKind; text : string = ""; num : double = 0.0lf) : PNode? {
    return new PNode(kind = kind, text = text, num = num)
}

def private pn_args(kind : NodeKind; text : string; var args : array<PNode?>) : PNode? {
    var n = new PNode(kind = kind, text = text)
    n.args <- args
    return n
}

def private pn1(kind : NodeKind; text : string; var a : PNode?) : PNode? {
    var n = new PNode(kind = kind, text = text)
    n.args |> push(a)
    return n
}

def private pn2(kind : NodeKind; text : string; var a, b : PNode?) : PNode? {
    var n = new PNode(kind = kind, text = text)
    n.args |> push(a)
    n.args |> push(b)
    return n
}

def private pn3(var a, b, c : PNode?) : PNode? {
    var n = new PNode(kind = NodeKind.Ternary)
    n.args |> push(a)
    n.args |> push(b)
    n.args |> push(c)
    return n
}

// One statement (or one expression) of the Explore language. Whitespace
// includes newlines: the script is cut into statements before.
def private peg_statement(src : string; blk : block<(st : PNode?; err : array<ParsingError>) : void>) {
    parse(src) {
        var Input : PNode?
        rule(S, Stmt as st, S, EOF) {
            return st
        }
        rule(S, Expr as e, S, EOF) {
            return pn1(NodeKind.Expression, "", e)
        }

        var Stmt : PNode?
        rule("vary", SS, "{Name}" as path, SS, Values as v) {
            return pn1(NodeKind.Vary, path, v)
        }
        rule("where", SS, Expr as e) {
            return pn1(NodeKind.Where, "", e)
        }
        rule("sort", SS, Expr as e, SS, "desc", End) {
            return pn1(NodeKind.SortDesc, "", e)
        }
        rule("sort", SS, Expr as e, SS, "asc", End) {
            return pn1(NodeKind.Sort, "", e)
        }
        rule("sort", SS, Expr as e) {
            return pn1(NodeKind.Sort, "", e)
        }
        rule("plot", SS, Exprs as ys, *PlotOpt as opts) {
            opts |> push(relist(NodeKind.PlotY, "", ys))
            return pn_args(NodeKind.Plot, "", opts)
        }
        rule("scene", +SceneOpt as opts) {
            return pn_args(NodeKind.Scene, "", opts)
        }
        rule("{Ident}" as col, S, "=", S, Expr as e) {
            return pn1(NodeKind.Let, col, e)
        }

        // vary: from..to [step s] (both ends included), a, b, c, or a
        // generator of the game: jobs, weapons "Sword"
        var Values : PNode?
        rule(Expr as a, S, "..", S, Expr as b, SS, "step", SS, Expr as st) {
            var n = pn2(NodeKind.Call, "span", a, b)
            n.args |> push(st)
            return n
        }
        rule(Expr as a, S, "..", S, Expr as b) {
            return pn2(NodeKind.Call, "span", a, b)
        }
        rule("{Ident}" as g, SS, string_ as arg) {
            return pn1(NodeKind.Call, g, pn(NodeKind.Str, arg))
        }
        rule(Exprs as l) {
            return relist(NodeKind.List, "", l)
        }

        // plot y1, y2 [by x] [per series] [line|bar|scatter] [log x|y|xy] [title "..."]
        var PlotOpt : PNode?
        rule(SS, "by", SS, Expr as e) {
            return pn1(NodeKind.PlotBy, "", e)
        }
        rule(SS, "per", SS, Expr as e) {
            return pn1(NodeKind.PlotPer, "", e)
        }
        rule(SS, "line", End) {
            return pn(NodeKind.PlotKind, "line")
        }
        rule(SS, "bar", End) {
            return pn(NodeKind.PlotKind, "bar")
        }
        rule(SS, "scatter", End) {
            return pn(NodeKind.PlotKind, "scatter")
        }
        rule(SS, "log", SS, "xy", End) {
            return pn(NodeKind.PlotLog, "xy")
        }
        rule(SS, "log", SS, "x", End) {
            return pn(NodeKind.PlotLog, "x")
        }
        rule(SS, "log", SS, "y", End) {
            return pn(NodeKind.PlotLog, "y")
        }
        rule(SS, "title", SS, string_ as t) {
            return pn(NodeKind.PlotTitle, t)
        }

        // scene Marc vs Euver | with Fire | with "First Aid" | from back
        var SceneOpt : PNode?
        rule(SS, Word as a, SS, "vs", SS, Word as b) {
            return pn2(NodeKind.SceneVs, "", a, b)
        }
        rule(SS, "with", SS, Word as w) {
            return pn1(NodeKind.SceneWith, "", w)
        }
        rule(SS, "from", SS, "{Ident}" as side) {
            return pn(NodeKind.SceneFrom, side)
        }
        var Word : PNode?
        rule(string_ as s) {
            return pn(NodeKind.Str, s)
        }
        rule("{Ident}" as s) {
            return pn(NodeKind.Str, s)
        }

        var Exprs : PNode?
        rule(*CommaExpr as els, Expr as last) {
            els |> push(last)
            return pn_args(NodeKind.Items, "", els)
        }
        var CommaExpr : PNode?
        rule(Expr as e, S, ",", S) {
            return e
        }

        // precedence, lowest first: ?: || && == != < <= > >= + - * / %
        var Expr : PNode?
        rule(Or as c, S, "?", S, Expr as a, S, ":", S, Expr as b) {
            return pn3(c, a, b)
        }
        rule(Or as x) {
            return x
        }
        var Or : PNode?
        rule(Or as a, S, "||", S, And as b) {
            return pn2(NodeKind.Binary, "||", a, b)
        }
        rule(And as x) {
            return x
        }
        var And : PNode?
        rule(And as a, S, "&&", S, Eq as b) {
            return pn2(NodeKind.Binary, "&&", a, b)
        }
        rule(Eq as x) {
            return x
        }
        var Eq : PNode?
        rule(Eq as a, S, "==", S, Rel as b) {
            return pn2(NodeKind.Binary, "==", a, b)
        }
        rule(Eq as a, S, "!=", S, Rel as b) {
            return pn2(NodeKind.Binary, "!=", a, b)
        }
        rule(Rel as x) {
            return x
        }
        var Rel : PNode?
        rule(Rel as a, S, "<=", S, Add as b) {
            return pn2(NodeKind.Binary, "<=", a, b)
        }
        rule(Rel as a, S, ">=", S, Add as b) {
            return pn2(NodeKind.Binary, ">=", a, b)
        }
        rule(Rel as a, S, "<", S, Add as b) {
            return pn2(NodeKind.Binary, "<", a, b)
        }
        rule(Rel as a, S, ">", S, Add as b) {
            return pn2(NodeKind.Binary, ">", a, b)
        }
        rule(Add as x) {
            return x
        }
        var Add : PNode?
        rule(Add as a, S, "+", S, Mul as b) {
            return pn2(NodeKind.Binary, "+", a, b)
        }
        rule(Add as a, S, "-", S, Mul as b) {
            return pn2(NodeKind.Binary, "-", a, b)
        }
        rule(Mul as x) {
            return x
        }
        var Mul : PNode?
        rule(Mul as a, S, "*", S, Unary as b) {
            return pn2(NodeKind.Binary, "*", a, b)
        }
        rule(Mul as a, S, "/", S, Unary as b) {
            return pn2(NodeKind.Binary, "/", a, b)
        }
        rule(Mul as a, S, "%", S, Unary as b) {
            return pn2(NodeKind.Binary, "%", a, b)
        }
        rule(Unary as x) {
            return x
        }
        var Unary : PNode?
        rule("-", S, Unary as a) {
            return pn1(NodeKind.Unary, "-", a)
        }
        rule("!", S, Unary as a) {
            return pn1(NodeKind.Unary, "!", a)
        }
        rule(Primary as x) {
            return x
        }

        var Primary : PNode?
        rule("(", S, Expr as e, S, ")") {
            return e
        }
        rule("{Number}" as t) {
            return pn(NodeKind.Num, "", double(t))
        }
        rule(string_ as t) {
            return pn(NodeKind.Str, t)
        }
        rule("true", End) {
            return pn(NodeKind.Num, "", 1.0lf)
        }
        rule("false", End) {
            return pn(NodeKind.Num, "", 0.0lf)
        }
        rule("{Ident}" as f, S, "(", S, ")") {
            var none : array<PNode?>
            return pn_args(NodeKind.Call, f, none)
        }
        rule("{Ident}" as f, S, "(", S, Exprs as l, S, ")") {
            return relist(NodeKind.Call, f, l)
        }
        rule("{Name}" as n) {
            return pn(NodeKind.Name, n)
        }

        var Number : PNode?
        rule(+set('0'..'9'), ".", +set('0'..'9')) {
            return null
        }
        rule(+set('0'..'9')) {
            return null
        }
        var Ident : PNode?
        rule(set('a'..'z', 'A'..'Z', '_'), *set('0'..'9', 'a'..'z', 'A'..'Z', '_')) {
            return null
        }
        // a dotted name; ".." (a range) is not part of it
        var Name : PNode?
        rule(Ident, *NamePart) {
            return null
        }
        var NamePart : PNode?
        rule(".", Ident) {
            return null
        }
        // a keyword ends here (not "bar" of "barrier")
        var End : PNode?
        rule(!set('0'..'9', 'a'..'z', 'A'..'Z', '_', '.')) {
            return null
        }
        var S : PNode?
        rule(*set(' ', '\t', '\r', '\n')) {
            return null
        }
        var SS : PNode?
        rule(+set(' ', '\t', '\r', '\n')) {
            return null
        }
    }
}


// PNode tree -> the nodes of an Expr
def private flatten(p : PNode?; var e : Expr) : int {
    var node = ExprNode(kind = p.kind, num = p.num, text = p.text)
    for (a in p.args) {
        node.args |> push(flatten(a, e))
    }
    e.nodes |> emplace(node)
    return length(e.nodes) - 1
}

def private to_expr(p : PNode?; line : int) : Expr {
    var e = Expr(line = line)
    if (p != null) {
        e.root = flatten(p, e)
    }
    return <- e
}

// "line N: syntax error near '...'": the furthest place the parser
// reached (dasPEG's own text names the last rule it tried there, which
// is rarely the helpful one); base: the first line of the statement
def private syntax_error(src : string; base : int; err : array<ParsingError>) : string {
    var at = 0
    for (x in err) {
        at = max(at, x.index)
    }
    at = clamp(at, 0, length(src))
    var line = base
    for (i in range(at)) {
        if (character_at(src, i) == '\n') {
            line++
        }
    }
    if (strip(slice(src, at)) == "") {
        return "line {line}: syntax error: the statement is not finished"
    }
    return "line {line}: syntax error near '{slice(src, at, min(at + 12, length(src)))}'"
}

// a whole expression from source text (for tests and tools)
def parse_expression(src : string; var e : Expr) : string {
    var err = ""
    peg_statement(src) $(st; errs) {
        if (length(errs) > 0 || st == null) {
            err = length(errs) > 0 ? syntax_error(src, 1, errs) : "line 1: syntax error"
        } elif (st.kind != NodeKind.Expression) {
            err = "line 1: an expression, not a statement"
        } else {
            e = to_expr(st.args[0], 1)
        }
    }
    return err
}

// the names an expression reads (to know which columns it needs)
def expr_names(e : Expr; var names : array<string>) {
    for (n in e.nodes) {
        if (n.kind == NodeKind.Name && find_index(names, n.text) < 0) {
            names |> push(n.text)
        }
    }
}

// ------------------------------------------------------------ table

struct ETable {
    names : array<string>
    rows : array<array<Value>>
}

def column_index(t : ETable; name : string) : int {
    return find_index(t.names, name)
}

// names -> columns; "" or the error with the known names
def bind(var e : Expr; t : ETable) : string {
    for (n in e.nodes) {
        if (n.kind == NodeKind.Name) {
            n.col = column_index(t, n.text)
            if (n.col < 0) {
                return "line {e.line}: no column '{n.text}' (columns: {join(t.names, ", ")})"
            }
        } elif (n.kind == NodeKind.Call && find_index(FUNCTIONS, n.text) < 0) {
            return "line {e.line}: unknown function '{n.text}' (functions: {join(FUNCTIONS, ", ")})"
        } elif (n.kind == NodeKind.List) {
            return "line {e.line}: a list [ ] is only allowed in `for` and in plot(y = ...)"
        }
    }
    return ""
}

def private num_arg(e : Expr; row : array<Value>; n : ExprNode; i : int) : double {
    return i < length(n.args) ? eval_node(e, row, n.args[i]).num : 0.0lf
}

def private eval_call(e : Expr; row : array<Value>; n : ExprNode) : Value {
    let f = n.text
    let a = num_arg(e, row, n, 0)
    if (f == "min" || f == "max") {
        var r = a
        for (i in range(1, length(n.args))) {
            let b = num_arg(e, row, n, i)
            r = f == "min" ? min(r, b) : max(r, b)
        }
        return vnum(r)
    }
    let b = num_arg(e, row, n, 1)
    if (f == "abs") {
        return vnum(abs(a))
    } elif (f == "clamp") {
        return vnum(clamp(a, b, num_arg(e, row, n, 2)))
    } elif (f == "round") {
        return vnum(round(a))
    } elif (f == "floor") {
        return vnum(floor(a))
    } elif (f == "ceil") {
        return vnum(ceil(a))
    } elif (f == "sqrt") {
        return vnum(sqrt(a))
    } elif (f == "pow") {
        return vnum(pow(a, b))
    } elif (f == "exp") {
        return vnum(exp(a))
    } elif (f == "log") {
        return vnum(log(a))
    } elif (f == "log10") {
        return vnum(log(a) / log(10.0lf))
    } elif (f == "log2") {
        return vnum(log(a) / log(2.0lf))
    }
    return vnum(0.0lf)
}

def private vbool(b : bool) : Value => vnum(b ? 1.0lf : 0.0lf)

def private eval_binary(op : string; a, b : Value) : Value {
    let x = a.num
    let y = b.num
    return match (op) {
        "==" => vbool(value_equal(a, b))
        "!=" => vbool(!value_equal(a, b))
        "&&" => vbool(is_true(a) && is_true(b))
        "||" => vbool(is_true(a) || is_true(b))
        "+" => vnum(x + y)
        "-" => vnum(x - y)
        "*" => vnum(x * y)
        "/" => vnum(x / y)
        "%" => vnum(y != 0.0lf ? x - y * floor(x / y) : 0.0lf)
        "<" => vbool(value_less(a, b))
        ">" => vbool(value_less(b, a))
        "<=" => vbool(!value_less(b, a))
        ">=" => vbool(!value_less(a, b))
        _ => vnum(0.0lf)
    }
}

// && and || stop early, as in daslang
def private eval_binary_node(e : Expr; row : array<Value>; n : ExprNode) : Value {
    let a = eval_node(e, row, n.args[0])
    if (n.text == "&&" && !is_true(a)) {
        return vnum(0.0lf)
    }
    if (n.text == "||" && is_true(a)) {
        return vnum(1.0lf)
    }
    return eval_binary(n.text, a, eval_node(e, row, n.args[1]))
}

def eval_node(e : Expr; row : array<Value>; i : int) : Value {
    assume n = e.nodes[i]
    return match (n.kind) {
        NodeKind.Num => vnum(n.num)
        NodeKind.Str => vtext(n.text)
        NodeKind.Name => n.col >= 0 && n.col < length(row) ? row[n.col] : vnum(0.0lf)
        NodeKind.Call => eval_call(e, row, n)
        NodeKind.Unary => (n.text == "!" ? vbool(!is_true(eval_node(e, row, n.args[0])))
            : vnum(-eval_node(e, row, n.args[0]).num))
        NodeKind.Binary => eval_binary_node(e, row, n)
        NodeKind.Ternary => (is_true(eval_node(e, row, n.args[0])) ? eval_node(e, row, n.args[1])
            : eval_node(e, row, n.args[2]))
        _ => vnum(0.0lf)
    }
}

def eval_expr(e : Expr; row : array<Value>) : Value {
    return e.root >= 0 ? eval_node(e, row, e.root) : vnum(0.0lf)
}

// a constant expression (no columns): range bounds, list items
def eval_const(e : Expr; i : int) : Value {
    var empty : array<Value>
    return eval_node(e, empty, i)
}

// ------------------------------------------------------------ script

enum StepKind {
    Let
    Where
    Order
    OrderDesc
}

struct Axis {
    path : string                   // attacker.watk
    src : Expr = Expr()             // range(...), [ ... ], jobs()
    line : int
}

struct Step {
    kind : StepKind
    name : string                   // Let: the new column
    e : Expr = Expr()
    line : int
}

// plot( ) and scene( ): name = expression (y may be a list)
struct NamedArg {
    name : string
    exprs : array<Expr>
    line : int
    list : bool                     // name = [a, b]
}

struct Script {
    axes : array<Axis>
    steps : array<Step>
    plot : array<NamedArg>
    has_plot : bool
    scene : array<NamedArg>
}

let STATEMENTS = fixed_array<string>("vary", "where", "sort", "plot", "scene")

// A statement of the script: its text (comments blanked, so offsets and
// lines stay) and the line it starts on.
struct SourceStmt {
    text : string
    line : int
}

// Statements end at the end of a line, unless a ( or [ is still open.
def private split_statements(src : string; var out : array<SourceStmt>) : string {
    let n = length(src)
    var buf = ""
    var start_line = 1
    var line = 1
    var depth = 0
    var i = 0
    var in_str = false
    while (i <= n) {
        let c = i < n ? character_at(src, i) : int('\n')
        if (in_str) {
            buf += to_char(c)
            if (c == '"') {
                in_str = false
            } elif (c == '\n') {
                return "line {line}: unterminated string"
            }
        } elif (c == '"') {
            in_str = true
            buf += to_char(c)
        } elif (c == '/' && i + 1 < n && character_at(src, i + 1) == '/') {
            while (i < n && character_at(src, i) != '\n') {
                buf += " "
                i++
            }
            continue
        } elif (c == '\n' && depth == 0) {
            if (strip(buf) != "") {
                out |> push(SourceStmt(text = buf, line = start_line))
            }
            buf = ""
            start_line = line + 1
        } else {
            if (c == '(' || c == '[') {
                depth++
            } elif (c == ')' || c == ']') {
                depth = max(depth - 1, 0)
            }
            if (buf == "" && (c == ' ' || c == '\t' || c == '\r')) {
                // leading blanks of a statement are not kept
            } else {
                buf += to_char(c)
            }
        }
        if (c == '\n') {
            line++
        }
        i++
    }
    return ""
}

// the first word of a statement, and whether "=" (not "==") follows it
def private first_word(s : string; var assign : bool&) : string {
    var j = 0
    let n = length(s)
    while (j < n && (is_alpha(character_at(s, j)) || is_number(character_at(s, j)) || character_at(s, j) == '_')) {
        j++
    }
    var k = j
    while (k < n && (character_at(s, k) == ' ' || character_at(s, k) == '\t')) {
        k++
    }
    assign = k < n && character_at(s, k) == '=' && !(k + 1 < n && character_at(s, k + 1) == '=')
    return slice(s, 0, j)
}

def private arg_of(name : string; p : PNode?; line : int) : NamedArg {
    var na = NamedArg(name = name, line = line)
    na.exprs |> emplace(to_expr(p, line))
    return <- na
}

def private plot_args(p : PNode?; line : int; var s : Script) : string {
    var kinds = 0
    for (o in p.args) {
        if (o.kind == NodeKind.PlotY) {
            var na = NamedArg(name = "y", line = line, list = true)
            for (v in o.args) {
                na.exprs |> emplace(to_expr(v, line))
            }
            s.plot |> emplace(na)
        } elif (o.kind == NodeKind.PlotBy || o.kind == NodeKind.PlotPer) {
            let name = o.kind == NodeKind.PlotBy ? "x" : "series"
            if (find_arg(s.plot, name) >= 0) {
                return "line {line}: plot has two '{o.kind == NodeKind.PlotBy ? "by" : "per"}'"
            }
            s.plot |> emplace(arg_of(name, o.args[0], line))
        } elif (o.kind == NodeKind.PlotKind) {
            kinds++
            s.plot |> emplace(arg_of("kind", pn(NodeKind.Str, o.text), line))
        } elif (o.kind == NodeKind.PlotLog) {
            if (o.text == "x" || o.text == "xy") {
                s.plot |> emplace(arg_of("log_x", pn(NodeKind.Num, "", 1.0lf), line))
            }
            if (o.text == "y" || o.text == "xy") {
                s.plot |> emplace(arg_of("log_y", pn(NodeKind.Num, "", 1.0lf), line))
            }
        } elif (o.kind == NodeKind.PlotTitle) {
            s.plot |> emplace(arg_of("title", pn(NodeKind.Str, o.text), line))
        }
    }
    return kinds > 1 ? "line {line}: plot is line, bar or scatter - one of them" : ""
}

let SIDE_WORDS = fixed_array<string>("auto", "front", "side", "back")

def private scene_args(p : PNode?; line : int; var s : Script) : string {
    for (o in p.args) {
        if (o.kind == NodeKind.SceneVs) {
            s.scene |> emplace(arg_of("attacker", o.args[0], line))
            s.scene |> emplace(arg_of("target", o.args[1], line))
        } elif (o.kind == NodeKind.SceneWith) {
            s.scene |> emplace(arg_of("action", o.args[0], line))
        } elif (o.kind == NodeKind.SceneFrom) {
            let k = find_index(SIDE_WORDS, o.text)
            if (k < 0) {
                return "line {line}: from front, side, back or auto - not '{o.text}'"
            }
            s.scene |> emplace(arg_of("side", pn(NodeKind.Num, "", double(k)), line))
        }
    }
    return ""
}

// the statements that become a step over the table
def private is_step(k : NodeKind) : bool {
    return match (k) {
        NodeKind.Let | NodeKind.Where | NodeKind.Sort | NodeKind.SortDesc => true
        _ => false
    }
}

def private step_kind(k : NodeKind) : StepKind {
    return match (k) {
        NodeKind.Let => StepKind.Let
        NodeKind.Where => StepKind.Where
        NodeKind.Sort => StepKind.Order
        _ => StepKind.OrderDesc
    }
}

// "" or "line N: what is wrong"
def parse_script(src : string; var s : Script) : string {
    var stmts : array<SourceStmt>
    let err = split_statements(src, stmts)
    if (err != "") {
        return err
    }
    for (ss in stmts) {
        var assign = false
        let word = first_word(ss.text, assign)
        if (find_index(STATEMENTS, word) < 0 && !assign) {
            return "line {ss.line}: unknown statement '{word}' (vary, name = ..., where, sort, plot, scene)"
        }
        var res = ""
        peg_statement(ss.text) $(p; errs) {
            if (length(errs) > 0 || p == null) {
                res = length(errs) > 0 ? syntax_error(ss.text, ss.line, errs) : "line {ss.line}: syntax error"
                return
            }
            let line = ss.line
            if (p.kind == NodeKind.Vary) {
                var ax = Axis(path = p.text, line = line)
                let v = p.args[0]
                // a lone name is a generator of the game: jobs, weapons
                if (v.kind == NodeKind.List && length(v.args) == 1 && v.args[0].kind == NodeKind.Name) {
                    var none : array<PNode?>
                    ax.src = to_expr(pn_args(NodeKind.Call, v.args[0].text, none), line)
                } else {
                    ax.src = to_expr(v, line)
                }
                s.axes |> emplace(ax)
            } elif (is_step(p.kind)) {
                var st = Step(kind = step_kind(p.kind), name = p.text, line = line)
                st.e = to_expr(p.args[0], line)
                s.steps |> emplace(st)
            } elif (p.kind == NodeKind.Plot) {
                if (s.has_plot) {
                    res = "line {line}: only one plot per experiment"
                    return
                }
                s.has_plot = true
                res = plot_args(p, line, s)
            } elif (p.kind == NodeKind.Scene) {
                res = scene_args(p, line, s)
            } else {
                res = "line {line}: {word} needs more, like: {word} ..."
            }
        }
        if (res != "") {
            return res
        }
    }
    return ""
}


def find_arg(args : array<NamedArg>; name : string) : int {
    for (i in range(length(args))) {
        if (args[i].name == name) {
            return i
        }
    }
    return -1
}

// every name the steps and the plot read (to know the needed columns)
def script_names(s : Script; var names : array<string>) {
    for (st in s.steps) {
        expr_names(st.e, names)
    }
    for (a in s.plot) {
        for (e in a.exprs) {
            expr_names(e, names)
        }
    }
}

// let / where / order_by over the table, in the script's order
def run_steps(var s : Script; var t : ETable) : string {
    for (st in s.steps) {
        if (st.kind == StepKind.Let && column_index(t, st.name) >= 0) {
            return "line {st.line}: column '{st.name}' already exists"
        }
        let err = bind(st.e, t)
        if (err != "") {
            return err
        }
        if (st.kind == StepKind.Let) {
            t.names |> push(st.name)
            for (row in t.rows) {
                row |> push(eval_expr(st.e, row))
            }
        } elif (st.kind == StepKind.Where) {
            var kept : array<array<Value>>
            for (row in t.rows) {
                if (is_true(eval_expr(st.e, row))) {
                    kept |> push_clone(row)
                }
            }
            t.rows <- kept
        } else {
            var keys : array<tuple<Value; int>>
            for (i in range(length(t.rows))) {
                keys |> push((eval_expr(st.e, t.rows[i]), i))
            }
            let desc = st.kind == StepKind.OrderDesc
            sort(keys) $(a, b) {
                // stable: equal keys keep their order
                if (value_less(a._0, b._0)) {
                    return !desc
                }
                if (value_less(b._0, a._0)) {
                    return desc
                }
                return a._1 < b._1
            }
            var sorted : array<array<Value>>
            for (k in keys) {
                sorted |> push_clone(t.rows[k._1])
            }
            t.rows <- sorted
        }
    }
    return ""
}

// ------------------------------------------------------------ chart data

enum ChartKind {
    Line
    Bar
    Scatter
}

struct ChartSeries {
    name : string
    xs : array<double>              // the x value, or the category index
    ys : array<double>
    rows : array<int>               // the table row of each point
}

// what plot( ) asks for, with the values from the table
struct Chart {
    kind : ChartKind
    log_x : bool
    log_y : bool
    title : string
    x_name : string
    y_name : string
    series_name : string            // plot(series = ...), "" without
    categories : array<string>      // x labels when x is not a number
    series : array<ChartSeries>
}

let PLOT_ARGS = fixed_array<string>("x", "y", "series", "kind", "log_x", "log_y", "title")

// an expression as text again (legend, axis names)
def expr_text(e : Expr) : string {
    return e.root >= 0 ? node_text(e, e.root, 0) : ""
}

def private parens(on : bool; s : string) : string => on ? "({s})" : s

def private args_text(e : Expr; n : ExprNode) : string => join([for (a in n.args); node_text(e, a, 0)], ", ")

// outer: the binding power of the operator around (parentheses when lower)
def private node_text(e : Expr; i, outer : int) : string {
    assume n = e.nodes[i]
    return match (n.kind) {
        NodeKind.Num => value_text(vnum(n.num))
        NodeKind.Str => "\"{n.text}\""
        NodeKind.Name => n.text
        NodeKind.Call => "{n.text}({args_text(e, n)})"
        NodeKind.List => "[{args_text(e, n)}]"
        NodeKind.Unary => "{n.text}{node_text(e, n.args[0], 9)}"
        NodeKind.Ternary => parens(outer > 0,
            "{node_text(e, n.args[0], 1)} ? {node_text(e, n.args[1], 0)} : {node_text(e, n.args[2], 0)}")
        NodeKind.Binary => binary_text(e, n, outer)
        _ => ""
    }
}

def private binary_text(e : Expr; n : ExprNode; outer : int) : string {
    let p = binary_power(n.text)
    return parens(p < outer, "{node_text(e, n.args[0], p)} {n.text} {node_text(e, n.args[1], p + 1)}")
}

def private binary_power(op : string) : int {
    return match (op) {
        "||" => 1
        "&&" => 2
        "==" | "!=" => 3
        "<" | "<=" | ">" | ">=" => 4
        "+" | "-" => 5
        _ => 6
    }
}

def private plot_flag(s : Script; name : string) : bool {
    let i = find_arg(s.plot, name)
    return i >= 0 && length(s.plot[i].exprs) > 0 && is_true(eval_const(s.plot[i].exprs[0], s.plot[i].exprs[0].root))
}

// The chart of plot( ) over the table (after the steps); without plot( ):
// x = default_x, y = default_y. "" or the error.
def build_chart(var s : Script; t : ETable; default_x, default_y : string; var c : Chart) : string {
    c = Chart()
    for (a in s.plot) {
        if (find_index(PLOT_ARGS, a.name) < 0) {
            return "line {a.line}: plot( ) has no '{a.name}' (x, y, series, kind, log_x, log_y, title)"
        }
    }
    var xe = Expr()
    var ys : array<Expr>
    var se = Expr()
    let xi = find_arg(s.plot, "x")
    if (xi >= 0) {
        xe := s.plot[xi].exprs[0]
    } else {
        xe.nodes |> emplace(ExprNode(kind = NodeKind.Name, text = default_x))
        xe.root = 0
    }
    let yi = find_arg(s.plot, "y")
    if (yi >= 0) {
        for (e in s.plot[yi].exprs) {
            ys |> push_clone(e)
        }
    } else {
        var e = Expr()
        e.nodes |> emplace(ExprNode(kind = NodeKind.Name, text = default_y))
        e.root = 0
        ys |> emplace(e)
    }
    let si = find_arg(s.plot, "series")
    if (si >= 0) {
        se := s.plot[si].exprs[0]
    }
    var err = bind(xe, t)
    for (e in ys) {
        if (err == "") {
            err = bind(e, t)
        }
    }
    if (err == "" && se.root >= 0) {
        err = bind(se, t)
    }
    if (err != "") {
        return err
    }
    let ki = find_arg(s.plot, "kind")
    var kind = ""
    if (ki >= 0) {
        kind = eval_const(s.plot[ki].exprs[0], s.plot[ki].exprs[0].root).text
        if (kind != "line" && kind != "bar" && kind != "scatter") {
            return "line {s.plot[ki].line}: kind = \"line\", \"bar\" or \"scatter\""
        }
    }
    let ti = find_arg(s.plot, "title")
    if (ti >= 0) {
        c.title = eval_const(s.plot[ti].exprs[0], s.plot[ti].exprs[0].root).text
    }
    c.log_x = plot_flag(s, "log_x")
    c.log_y = plot_flag(s, "log_y")
    c.x_name = expr_text(xe)
    c.y_name = join([for (e in ys); expr_text(e)], ", ")
    c.series_name = se.root >= 0 ? expr_text(se) : ""
    // x as text (a job, a weapon): categories; so is any x of a bar chart
    var text_x = false
    for (row in t.rows) {
        text_x = text_x || eval_expr(xe, row).text != ""
    }
    c.kind = match (kind) {
        "bar" => ChartKind.Bar
        "scatter" => ChartKind.Scatter
        "line" => ChartKind.Line
        _ => text_x ? ChartKind.Bar : ChartKind.Line
    }
    let categorical = text_x || c.kind == ChartKind.Bar
    var keys : array<string>
    for (r in range(length(t.rows))) {
        let row & = unsafe(t.rows[r])
        let xv = eval_expr(xe, row)
        var x = xv.num
        if (categorical) {
            let cat = value_text(xv)
            var ci = find_index(c.categories, cat)
            if (ci < 0) {
                c.categories |> push(cat)
                ci = length(c.categories) - 1
            }
            x = double(ci)
        }
        let group = se.root >= 0 ? value_text(eval_expr(se, row)) : ""
        for (k in range(length(ys))) {
            let y = eval_expr(ys[k], row).num
            if (is_nan(y) || (c.log_y && y <= 0.0lf) || (c.log_x && !categorical && x <= 0.0lf)) {
                continue
            }
            let name = se.root < 0 ? expr_text(ys[k]) : (length(ys) > 1 ? "{expr_text(ys[k])}: {group}" : group)
            var si2 = find_index(keys, name)
            if (si2 < 0) {
                keys |> push(name)
                c.series |> emplace(ChartSeries(name = name))
                si2 = length(keys) - 1
            }
            c.series[si2].xs |> push(x)
            c.series[si2].ys |> push(y)
            c.series[si2].rows |> push(r)
        }
    }
    if (categorical) {
        c.log_x = false
    }
    return ""
}

// ------------------------------------------------------------ highlighting

let HL_PLAIN = 0
let HL_STMT = 1                     // vary where sort plot scene
let HL_WORD = 2                     // by per step log bar title vs ...
let HL_NAME = 3                     // a column or a parameter: the game tells which
let HL_NUM = 4
let HL_STR = 5
let HL_COMMENT = 6
let HL_FUNC = 7                     // name(
let HL_OP = 8
let HL_DEF = 9                      // the new column of "name = ..."

struct HlSpan {
    start : int                     // bytes of the line, stop not included
    stop : int
    kind : int
    text : string
}

let HL_WORDS = fixed_array<string>("by", "per", "step", "bar", "line", "scatter", "log", "title", "vs", "with", "from",
    "desc", "asc", "true", "false")

// The words of one line of a script, for colors: a lexer, not the
// parser (it runs every frame and must not fail on half-typed text).
def highlight_line(s : string; var spans : array<HlSpan>) {
    let n = length(s)
    var i = 0
    var first = true
    var prev = ""
    var scene = false
    while (i < n) {
        let c = character_at(s, i)
        var j = i + 1
        var kind = HL_PLAIN
        if (c == '/' && i + 1 < n && character_at(s, i + 1) == '/') {
            j = n
            kind = HL_COMMENT
        } elif (c == '"') {
            while (j < n && character_at(s, j) != '"') {
                j++
            }
            j = min(j + 1, n)
            kind = HL_STR
        } elif (is_number(c)) {
            while (j < n && (is_number(character_at(s, j))
                    || (character_at(s, j) == '.' && j + 1 < n && is_number(character_at(s, j + 1))))) {
                j++
            }
            kind = HL_NUM
        } elif (is_alpha(c) || c == '_') {
            while (j < n && (is_alpha(character_at(s, j)) || is_number(character_at(s, j)) || character_at(s, j) == '_'
                    || (character_at(s, j) == '.' && j + 1 < n && character_at(s, j + 1) != '.'))) {
                j++
            }
            let word = slice(s, i, j)
            var k = j
            while (k < n && (character_at(s, k) == ' ' || character_at(s, k) == '\t')) {
                k++
            }
            let next = k < n ? character_at(s, k) : 0
            if (first && find_index(STATEMENTS, word) >= 0) {
                kind = HL_STMT
                scene = word == "scene"
            } elif (first && next == '=' && !(k + 1 < n && character_at(s, k + 1) == '=')) {
                kind = HL_DEF
            } elif (next == '(') {
                kind = HL_FUNC
            } elif (find_index(HL_WORDS, word) >= 0 || (prev == "log" && (word == "x" || word == "y" || word == "xy"))
                    || (prev == "from" && find_index(SIDE_WORDS, word) >= 0)) {
                kind = HL_WORD
            } elif (scene) {
                kind = HL_PLAIN             // unit and ability names
            } else {
                kind = HL_NAME
            }
            prev = word
            first = false
        } elif (c != ' ' && c != '\t' && c != '\r') {
            while (j < n && find("+-*/%<>=!&|?:.,", slice(s, j, j + 1)) >= 0
                    && !(character_at(s, j) == '/' && j + 1 < n && character_at(s, j + 1) == '/')) {
                j++
            }
            kind = HL_OP
            first = false
        }
        if (kind != HL_PLAIN || (c != ' ' && c != '\t')) {
            spans |> push(HlSpan(start = i, stop = j, kind = kind, text = slice(s, i, j)))
        }
        i = j
    }
}

// ------------------------------------------------------------ CSV

def private csv_field(s : string) : string {
    if (find(s, ",") < 0 && find(s, "\"") < 0 && find(s, "\n") < 0) {
        return s
    }
    return "\"{replace(s, "\"", "\"\"")}\""
}

// a number in full (not rounded for the table), a label as its text
def private csv_value(v : Value) : string {
    if (v.text != "") {
        return v.text
    }
    if (is_nan(v.num)) {
        return ""
    }
    let r = round(v.num)
    return abs(v.num - r) < 1.0e-9lf * max(1.0lf, abs(v.num)) && abs(v.num) < 1.0e15lf ? "{int64(r)}" : "{v.num}"
}

// The table as CSV (comma, a dot in numbers, a header line); rows in
// order (the view's sorting), all rows when order is empty.
def table_csv(t : ETable; order : array<int>) : string {
    var lines : array<string>
    lines |> push(join([for (n in t.names); csv_field(n)], ","))
    let n = length(order) > 0 ? length(order) : length(t.rows)
    for (k in range(n)) {
        let r = length(order) > 0 ? order[k] : k
        lines |> push(join([for (v in t.rows[r]); csv_field(csv_value(v))], ","))
    }
    return join(lines, "\n") + "\n"
}
