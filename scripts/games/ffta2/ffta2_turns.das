options gen2
options indenting = 4

// FFTA2 turn order (research/ffta2/notes.md, "Turn order"): the battle's
// list of (unit, CT) entries is sorted (0x020610D4, comparator
// 0x02060DC4: higher CT first, ties by the lower record address); the
// first one acts when its CT >= 100, else every entry gets a tick
// (0x02061098 / 0x02060F18): + its speed (object +0x14), doubled with
// Haste, halved with Slow or Speed down, + the clan privileges 11..15
// (2..10) for clan members. Quicken (status 4) puts a unit first and
// ready. A turn costs CT (by the turn-end script): 50, + 30 when the unit
// moved, + 20 when it acted. Haste / Slow count by the status bits (the
// game also keeps their durations; a bit alone does not change a tick).
module ffta2_turns shared public

require math
require ffta2_battle

let TURN_READY = 100

struct Turn2 {
    unit : int                      // index in the units
    ct : int                        // its CT when the turn starts
    tick : int                      // ticks since now
    nth : int                       // the unit's 1st, 2nd, ... turn
}

def turn_cost(how : TurnEnd2) : int {
    return how == TurnEnd2.MoveAndAct ? 100 : (how == TurnEnd2.ActOnly ? 70 : (how == TurnEnd2.MoveOnly ? 80 : 50))
}

// what a tick adds (0x02060F18)
def tick_amount(u : Unit2; privilege : int = 0) : int {
    var s = u.speed
    var k = 0
    if (has_status2(u, 22)) {           // Haste
        k++
    }
    if (has_status2(u, 23)) {           // Slow
        k--
    }
    if (has_status2(u, 35)) {           // Speed down
        k--
    }
    if (k > 0) {
        s = s * 2
    } elif (k < 0) {
        s = s / 2
    }
    if (s != 0 && privilege >= 11 && privilege <= 15 && (u.flags & 5) == 0) {
        s += 2 * (privilege - 10)
    }
    return s
}

// the next `count` turns: each unit ends its turns as its `assumed`;
// KO units (0 HP) do not take turns
def predict_turns2(units : array<Unit2>; count : int; privilege : int = 0) : array<Turn2> {
    var res : array<Turn2>
    var ct : array<int>
    var nth : array<int>
    var alive : array<int>
    for (i in range(length(units))) {
        ct |> push(units[i].ct)
        nth |> push(0)
        if (units[i].hp > 0 && !has_status2(units[i], 1)) {
            alive |> push(i)
        }
    }
    if (length(alive) == 0) {
        return <- res
    }
    // Quicken (status 4, entry +9): first and ready whatever its CT, once
    var quick : array<bool>
    for (i in range(length(units))) {
        quick |> push(has_status2(units[i], 4))
    }
    var ticks = 0
    var guard = 0
    while (length(res) < count && guard < 100000) {
        guard++
        // the first by the game's order: higher CT, then the lower record
        var best = alive[0]
        for (i in alive) {
            let before = quick[i] != quick[best] ? quick[i] : (ct[i] > ct[best] || (ct[i] == ct[best] &&
                units[i].record < units[best].record))
            if (before) {
                best = i
            }
        }
        if (ct[best] >= TURN_READY || quick[best]) {
            quick[best] = false
            nth[best]++
            res |> push(Turn2(unit = best, ct = ct[best], tick = ticks, nth = nth[best]))
            ct[best] = max(ct[best] - turn_cost(units[best].assumed), 0)
        } else {
            for (i in alive) {
                ct[i] += tick_amount(units[i], privilege)
            }
            ticks++
        }
    }
    return <- res
}
