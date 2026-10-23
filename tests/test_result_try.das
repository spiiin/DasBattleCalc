options gen2
options indenting = 4

// try_ok / ensure (scripts/core/result_try.das): the first error wins,
// later steps do not run, prefixes are added.
//   battlecalc tests/test_result_try.das
require ../scripts/core/result_try.das

var steps = 0

def step(err : string) : string {
    steps++
    return err
}

def chain(a, b : string; ok : bool) : string {
    try_ok(step(a), "A: ")
    ensure(ok, "not ok")
    try_ok(step(b))
    return ""
}

[export]
def main() : int {
    var failed = 0
    for (c in [("", "", true, "", 2), ("bad", "", true, "A: bad", 1), ("", "", false, "not ok", 1),
            ("", "late", true, "late", 2)]) {
        steps = 0
        let r = chain(c._0, c._1, c._2)
        let ok = r == c._3 && steps == c._4
        print("chain({c._0}, {c._1}, {c._2}) = \"{r}\", {steps} steps  {ok ? "ok" : "FAIL"}\n")
        if (!ok) {
            failed++
        }
    }
    print(failed == 0 ? "PASS 4 cases\n" : "FAIL {failed}\n")
    return failed == 0 ? 0 : 1
}
