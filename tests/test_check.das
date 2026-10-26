options gen2
options indenting = 4

// What every test counts: check() each case, report() at the end (the
// last line, PASS or FAIL, and the exit code).
module test_check shared public

var failed = 0
var total = 0

def check(what : string; ok : bool) {
    total++
    if (!ok) {
        failed++
        print("FAIL {what}\n")
    }
}

def report() : int {
    print(failed == 0 ? "PASS {total} cases\n" : "FAIL {failed} of {total}\n")
    return failed == 0 ? 0 : 1
}

// the index of the element with this name (units, items), -1 when none
def find_named(arr : array<auto(T)>; name : string) : int {
    for (i in range(length(arr))) {
        if (arr[i].name == name) {
            return i
        }
    }
    return -1
}
