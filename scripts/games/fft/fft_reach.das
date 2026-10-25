options gen2
options indenting = 4

// FFT (PSX) reach: the tiles a unit moves to and the tiles its Attack
// reaches (research/fft/notes.md, "Reach"), as the game marks them in the
// terrain (+5 bit 0x20 Move, 0x40 the action's range). Heights are the
// shown ones in half steps (FftMap.height).
// - Move: steps of 1 to the 4 sides, a height difference <= Jump up or
//   down; enemies (alive) block the way, allies and the dead do not; the
//   end is a free tile.
// - Attack by the weapon's flags (the weapon table +1): striking (0x80,
//   bare hands too) - the 4 neighbors; lunging (0x40, spears, cloth) -
//   straight lines up to the range; both - the target from 3 below to 2.5
//   above. Arc (0x10, bows): from 3 tiles to the range + (the attacker's
//   height - the target's) / 2, toward zero. Direct (0x20, guns,
//   crossbows, harps, books): from 3 to the range, any height. Tiles with
//   +6 bit 1 are never targets; a water tile's height counts + its depth.
module fft_reach shared public

require math
require fft_battle
require fft_attack

let REACH_MIN_RANGED = 3

def private tile_ok(m : FftMap; x, y : int) : bool {
    // height 0 is a tile too (MAP056's low corner)
    return x >= 0 && y >= 0 && x < m.w && y < m.h
}

// the tiles unit `i` moves to (w x h)
def move_reach(units : array<FftUnit>; m : FftMap; i : int) : array<bool> {
    var res : array<bool>
    res |> resize(m.w * m.h)
    if (i < 0 || i >= length(units) || !tile_ok(m, units[i].x, units[i].y)) {
        return <- res
    }
    let me = units[i]
    var taken : array<int>                      // 0 free, 1 a unit, 2 an enemy in the way
    taken |> resize(m.w * m.h)
    for (k in range(length(units))) {
        let un = units[k]
        if (k != i && tile_ok(m, un.x, un.y)) {
            let t = un.y * m.w + un.x
            taken[t] = max(taken[t], un.team != me.team && un.hp > 0 ? 2 : 1)
        }
    }
    var dist : array<int>
    dist |> resize(m.w * m.h)
    for (k in range(m.w * m.h)) {
        dist[k] = -1
    }
    var queue : array<int>
    let start = me.y * m.w + me.x
    dist[start] = 0
    queue |> push(start)
    var head = 0
    let dirs = fixed_array<int2>(int2(1, 0), int2(-1, 0), int2(0, 1), int2(0, -1))
    while (head < length(queue)) {
        let c = queue[head]
        head++
        if (dist[c] >= me.move) {
            continue
        }
        let cx = c % m.w
        let cy = c / m.w
        for (d in dirs) {
            let nx = cx + d.x
            let ny = cy + d.y
            if (!tile_ok(m, nx, ny)) {
                continue
            }
            let n = ny * m.w + nx
            if (dist[n] >= 0 || taken[n] == 2 || abs(m.height[n] - m.height[c]) > me.jump * 2) {
                continue
            }
            dist[n] = dist[c] + 1
            queue |> push(n)
        }
    }
    for (k in range(m.w * m.h)) {
        res[k] = dist[k] > 0 && taken[k] == 0
    }
    return <- res
}

// whether unit a's Attack reaches tile (x, y) from where it stands
def attack_reaches(a : FftUnit; w : FftWeapon; m : FftMap; x, y : int) : bool {
    if (!tile_ok(m, x, y) || !tile_ok(m, a.x, a.y)) {
        return false
    }
    if ((m.flags[y * m.w + x] & 2) != 0) {
        return false
    }
    let dx = x - a.x
    let dy = y - a.y
    let d = abs(dx) + abs(dy)
    // half steps, + the target above; water counts its depth up (a bow
    // does not reach (0, 0) of MAP056, 9 tiles away at depth 4)
    let t = y * m.w + x
    let s = a.y * m.w + a.x
    let dh2 = m.height[t] + m.depth[t] * 2 - m.height[s] - m.depth[s] * 2
    if (d == 0) {
        return false
    }
    if (w.item == 0 || (w.flags & 0x80) != 0) {
        return d == 1 && dh2 >= -6 && dh2 <= 5
    } elif ((w.flags & 0x40) != 0) {
        return (dx == 0 || dy == 0) && d <= w.reach && dh2 >= -6 && dh2 <= 5
    } elif ((w.flags & 0x10) != 0) {
        return d >= REACH_MIN_RANGED && d <= w.reach + (-dh2) / 4
    } elif ((w.flags & 0x20) != 0) {
        return d >= REACH_MIN_RANGED && d <= w.reach
    }
    return d == 1
}

// the tiles a's Attack reaches (w x h)
def attack_reach(a : FftUnit; m : FftMap) : array<bool> {
    var res : array<bool>
    res |> resize(m.w * m.h)
    let w = unit_weapon(a)
    for (y in range(m.h)) {
        for (x in range(m.w)) {
            res[y * m.w + x] = attack_reaches(a, w, m, x, y)
        }
    }
    return <- res
}
