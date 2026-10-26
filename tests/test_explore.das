options gen2
options indenting = 4
options stack = 1000000     // the dasPEG parser of the Explore language recurses

// The Explore language (scripts/core/explore.das) without a game:
// expressions, statements (vary, name = ..., where, sort, plot, scene),
// the steps over a table, the chart data.
//   battlecalc tests/test_explore.das
require strings
require daslib/strings_boost
require ../scripts/core/explore.das
require ./test_check.das


def calc(src : string; t : ETable; row : array<Value>) : string {
    var e = Expr()
    var err = parse_expression(src, e)
    if (err == "") {
        err = bind(e, t)
    }
    return err != "" ? "error: {err}" : value_text(eval_expr(e, row))
}

def root_of(e : Expr) : ExprNode {
    return <- clone(e.nodes[e.root])
}

[export]
def main() : int {
    var t : ETable
    t.names <- ["a", "b", "atk.job"]
    let row <- [vnum(6.0lf), vnum(4.0lf), vtext("Soldier", 2.0lf)]
    for (c in [("1 + 2 * 3", "7"), ("(1 + 2) * 3", "9"), ("a - b - 1", "1"), ("a / b", "1.50"), ("-a + 10", "4"),
            ("a > b ? a : b", "6"), ("a < b || b == 4", "1"), ("!(a > b) && true", "0"), ("max(a, b, 9)", "9"),
            ("min(a, b)", "4"), ("pow(2, 10)", "1024"), ("log10(1000)", "3"), ("round(2.5) + floor(1.9)", "4"),
            ("a % 4", "2"), ("atk.job == \"Soldier\"", "1"), ("atk.job", "Soldier"), ("clamp(a, 0, 5)", "5"),
            ("a > b && b > 1 ? 1 : 2", "1"), ("1 < 2 == 1", "1"), ("sqrt(b) * 3", "6")]) {
        let r = calc(c._0, t, row)
        check("{c._0} = {r} (want {c._1})", r == c._1)
    }
    for (c in [("a +", "line 1: syntax error: the statement is not finished"), ("foo(a)", "unknown function"),
            ("c + 1", "no column 'c'"), ("(a + b", "line 1: syntax error: the statement is not finished"),
            ("a $ b", "line 1: syntax error near '$ b'")]) {
        let r = calc(c._0, t, row)
        check("{c._0}: {r}", find(r, c._1) >= 0)
    }
    // a script: axes, steps, plot
    var s = Script()
    let src = ("// test\nvary atk.watk 50..300 step 10\nvary atk.job jobs\nx2 = a * 2\nwhere x2 > 5\n" +
        "sort b desc\nplot x2, b by a per atk.job log y title \"T\"\n")
    var err = parse_script(src, s)
    check("script parses: {err}", err == "")
    check("2 axes", length(s.axes) == 2 && s.axes[0].path == "atk.watk" && s.axes[1].path == "atk.job"
        && root_of(s.axes[0].src).text == "span" && length(root_of(s.axes[0].src).args) == 3
        && root_of(s.axes[1].src).text == "jobs")
    check("3 steps", length(s.steps) == 3 && s.steps[0].kind == StepKind.Let && s.steps[2].kind == StepKind.OrderDesc)
    check("plot args", s.has_plot && length(s.plot) == 5 && length(s.plot[find_arg(s.plot, "y")].exprs) == 2
        && find_arg(s.plot, "series") >= 0 && find_arg(s.plot, "log_y") >= 0 && find_arg(s.plot, "title") >= 0)
    // the forms of vary and scene
    var s3 = Script()
    err = parse_script(("vary tgt.wdef 50, 100, 150\nvary atk.weapon weapons \"Sword\"\nvary side 1..3\n" +
        "scene Marc vs \"Judge\" with \"First Aid\" from back\n"), s3)
    check("vary forms: {err}", err == "" && length(s3.axes) == 3 && root_of(s3.axes[0].src).kind == NodeKind.List
        && length(root_of(s3.axes[0].src).args) == 3 && root_of(s3.axes[1].src).text == "weapons"
        && root_of(s3.axes[2].src).text == "span")
    check("scene", length(s3.scene) == 4 && s3.scene[find_arg(s3.scene, "action")].exprs[0].nodes[0].text == "First Aid"
        && s3.scene[find_arg(s3.scene, "side")].exprs[0].nodes[0].num == 3.0lf)
    var tt : ETable
    tt.names <- ["a", "b", "atk.job"]
    for (i in range(5)) {
        var r <- [vnum(double(i)), vnum(double(10 - i)), vtext("J{i}", double(i))]
        tt.rows |> emplace(r)
    }
    err = run_steps(s, tt)
    check("steps run: {err}", err == "")
    check("let + where + order: {length(tt.rows)} rows", length(tt.rows) == 2 && tt.rows[0][1].num == 7.0lf
        && tt.rows[1][3].num == 8.0lf)
    // the chart of plot: 2 y x 2 series values, one point each
    var ch : Chart
    err = build_chart(s, tt, "a", "b", ch)
    check("chart: {err}, {length(ch.series)} series", err == "" && length(ch.series) == 4 && ch.log_y
        && ch.kind == ChartKind.Line && ch.series[0].name == "x2: J3" && length(ch.series[0].xs) == 1 && ch.title == "T")
    for (c in [("a * (b + 1) - -a", "a * (b + 1) - -a"), ("(a > 1 ? 2 : 3) + max(a, 1)", "(a > 1 ? 2 : 3) + max(a, 1)"),
            ("a - (b - 1)", "a - (b - 1)"), ("a / b * 2", "a / b * 2")]) {
        var e = Expr()
        parse_expression(c._0, e)
        check("text of {c._0}: {expr_text(e)}", expr_text(e) == c._1)
    }
    for (c in [("x = 1\nx = 2\n", "already exists"), ("where\n", "line 1: where needs more"),
            ("vary a 1, 2\ny = z\n", "line 2: no column 'z'"), ("bogus(1)\n", "unknown statement"),
            ("q = 1 2\n", "line 1: syntax error near '2'"),
            ("a2 = 1\n\n// c\nb2 = max(a,\n  )\n", "line 4: syntax error"),
            ("plot a by a by a\n", "two 'by'"), ("plot a line bar\n", "one of them"),
            ("scene from top\n", "from front, side, back"), ("sort a down\n", "line 1: syntax error near 'down'")]) {
        var s2 = Script()
        var t2 : ETable
        t2.names <- ["a"]
        var e2 = parse_script(c._0, s2)
        if (e2 == "") {
            e2 = run_steps(s2, t2)
        }
        check("{c._0}-> {e2}", find(e2, c._1) >= 0)
    }
    // CSV: header, rows in the given order, quoting, numbers in full
    var tc : ETable
    tc.names <- ["name", "x"]
    var r1 <- [vtext("Steal: Armor, \"x\"", 1.0lf), vnum(2.5lf)]
    var r2 <- [vtext("Fight", 0.0lf), vnum(1.0lf / 3.0lf)]
    tc.rows |> emplace(r1)
    tc.rows |> emplace(r2)
    let csv = table_csv(tc, [1, 0])
    check("csv: {csv}", csv == "name,x\nFight,0.3333333333333333\n\"Steal: Armor, \"\"x\"\"\",2.5\n")
    // the highlighting lexer: the kind of every word (HL_* numbers)
    for (c in [("vary atk.watk 50..300 step 10 // c", "1 3 4 8 4 2 4 6"), ("avg = max(a, 1.5)", "9 8 7 8 3 8 4 8"),
            ("plot avg by atk.watk log y title \"T\"", "1 3 2 3 2 2 2 5"), ("scene Marc vs Euver from back", "1 0 2 0 2 2"),
            ("where a == 1 && b", "1 3 8 4 8 3")]) {
        var spans : array<HlSpan>
        highlight_line(c._0, spans)
        let kinds = join([for (sp in spans); "{sp.kind}"], " ")
        check("highlight '{c._0}': {kinds}", kinds == c._1)
    }
    return report()
}
