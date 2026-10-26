options gen2
options indenting = 4

// FFT: The War of the Lions: turn order by clock ticks (research/fftwotl/
// formulas.md, 1): a tick adds Speed to CT (Haste x 3 / 2, Slow / 2,
// Stop, Sleep, Stone: 0); every unit with CT >= 100 then takes a turn, in
// the unit list's order; after it CT = min(60, CT - 100 / 80 / 60)
// (moved and acted / one of them / neither). The state at a unit's turn
// holds its CT already less 100 (Ramza at his turn: 4, the others at 104
// waiting), so the acting unit gets back what it does not spend.
// Unverified: the order of units ready at the same tick (here: by record).
module fftwotl_turns shared public

require math
require fftwotl_data
require fftwotl_battle
require ../fftcore/fft_common.das public

let TURN_READY_W = 100

struct TurnW {
    unit : int                      // index in the units
    ct : int                        // its CT when the turn starts
    tick : int                      // ticks since now
    nth : int                       // the unit's 1st, 2nd, ... turn
}

// what a tick adds to the unit's CT
def tick_amount_w(u : UnitW) : int {
    if (has_status_w(u, ST_STOP) || has_status_w(u, ST_SLEEP) || has_status_w(u, ST_PETRIFY)) {
        return 0
    }
    if (has_status_w(u, ST_HASTE)) {
        return u.sp * 3 / 2
    }
    return has_status_w(u, ST_SLOW) ? u.sp / 2 : u.sp
}

def private can_act(u : UnitW) : bool {
    return u.hp > 0 && !has_status_w(u, ST_DEAD) && !has_status_w(u, 1) && !has_status_w(u, ST_PETRIFY)
}

// the next `count` turns, each unit ending its turns as its `assumed`
def predict_turns_w(units : array<UnitW>; count : int) : array<TurnW> {
    var res : array<TurnW>
    var ct : array<int>
    var nth : array<int>
    var alive : array<int>
    for (i in range(length(units))) {
        ct |> push(units[i].ct)
        nth |> push(0)
        if (can_act(units[i])) {
            alive |> push(i)
        }
    }
    if (length(alive) == 0) {
        return <- res
    }
    // the unit list's order: by the record
    sort(alive) $(a, b) => units[a].slot < units[b].slot
    // the unit whose turn it is (it paid 100 at the start)
    for (i in alive) {
        if (units[i].active && length(res) < count) {
            nth[i]++
            res |> push(TurnW(unit = i, ct = ct[i] + TURN_READY_W, tick = 0, nth = nth[i]))
            ct[i] = min(60, ct[i] + TURN_READY_W - turn_cost(units[i].assumed))
        }
    }
    var ticks = 0
    var guard = 0
    while (length(res) < count && guard < 10000) {
        guard++
        var any = false
        for (i in alive) {
            if (ct[i] >= TURN_READY_W && length(res) < count) {
                any = true
                nth[i]++
                res |> push(TurnW(unit = i, ct = ct[i], tick = ticks, nth = nth[i]))
                ct[i] = min(60, ct[i] - turn_cost(units[i].assumed))
            }
        }
        if (!any) {
            for (i in alive) {
                ct[i] += tick_amount_w(units[i])
            }
            ticks++
        }
    }
    return <- res
}
