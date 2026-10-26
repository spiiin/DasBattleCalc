options gen2
options indenting = 4

// FFT turn order (research/fft/notes.md, "Turn order"), seen in the
// game: every clock tick adds each unit's Speed to its CT (Haste x 3/2,
// Slow / 2; Stop: none, its timer counts the ticks down and the tick that
// ends it adds Speed). Units with CT >= 100 take their turns in battle
// slot order; a turn costs 100 (moved and acted), 80 (one of them) or 60
// (neither), and CT is then at most 60. The unit taking its turn now
// (its record's CT reads 0) goes first and ends with 100 - the cost. A
// dead unit ticks and takes instant turns (its count to the crystal).
// Charged abilities: the counter (+0x15D) drops by 1 a tick and the
// ability goes off at the start of the tick it reaches 0, before the
// turns (Ramza's Fire, CT 4: off at tick 4; Alicia's turn at tick 7 came
// after). Haste: Speed x 3 / 2 (6 -> 9 a tick), Slow: / 2 (6 -> 3) - seen.
module fft_turns shared public

require math
require fft_battle
require ../fftcore/fft_common.das public

let TURN_READY = 100

struct Turn {
    unit : int                      // index in the units
    ct : int                        // its CT when the turn starts
    tick : int                      // ticks since now
    nth : int                       // the unit's 1st, 2nd, ... turn
    charge : int                    // a charged ability going off (its id), 0 a turn
}

def tick_amount(u : FftUnit) : int {
    if (has_status(u, ST_HASTE) && !has_status(u, ST_SLOW)) {
        return u.speed * 3 / 2
    } elif (has_status(u, ST_SLOW) && !has_status(u, ST_HASTE)) {
        return u.speed / 2
    }
    return u.speed
}

def predict_turns(units : array<FftUnit>; count : int) : array<Turn> {
    var res : array<Turn>
    var ct : array<int>
    var nth : array<int>
    var stop : array<int>           // ticks of Stop left, 0 none
    var live : array<int>           // units that tick: not petrified / crystal
    for (i in range(length(units))) {
        let u = units[i]
        ct |> push(u.ct)
        nth |> push(0)
        stop |> push(has_status(u, ST_STOP) ? max(u.stop_timer, 1) : 0)
        if (!has_status(u, ST_PETRIFY) && !has_status(u, ST_CRYSTAL)) {
            live |> push(i)
        }
    }
    if (length(live) == 0) {
        return <- res
    }
    for (i in live) {
        if (units[i].active && length(res) < count) {
            nth[i]++
            res |> push(Turn(unit = i, ct = 100, tick = 0, nth = nth[i]))
            ct[i] = min(100 - turn_cost(units[i].assumed), 60)
        }
    }
    var charge : array<int>         // ticks left of a charged ability, -1 none
    for (u in units) {
        charge |> push(has_status(u, ST_CHARGING) && u.charge < 255 ? u.charge : -1)
    }
    var ticks = 0
    var guard = 0
    while (length(res) < count && guard < 100000) {
        guard++
        var best = -1
        for (i in live) {
            if (best < 0 && ct[i] >= TURN_READY && stop[i] == 0) {
                best = i
            }
        }
        if (best >= 0) {
            nth[best]++
            res |> push(Turn(unit = best, ct = ct[best], tick = ticks, nth = nth[best]))
            let cost = has_status(units[best], ST_DEAD) || units[best].hp <= 0 ? 100 : turn_cost(units[best].assumed)
            ct[best] = min(ct[best] - cost, 60)
        } else {
            ticks++
            // the charged abilities first
            for (i in live) {
                if (charge[i] > 0) {
                    charge[i]--
                    if (charge[i] == 0 && length(res) < count) {
                        res |> push(Turn(unit = i, ct = ct[i], tick = ticks, charge = max(units[i].charge_ability, 1)))
                        charge[i] = -1
                    }
                }
            }
            for (i in live) {
                if (stop[i] > 0) {
                    stop[i]--
                    if (stop[i] > 0) {
                        continue
                    }
                }
                ct[i] += tick_amount(units[i])
            }
        }
    }
    return <- res
}
