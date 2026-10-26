options gen2
options indenting = 4

// The field's drawn view (scripts/ui/battle_field.das): a mirrored and /
// or turned map (FieldView) - every tile lands inside the drawn map, two
// tiles never share a place, field_game_tile undoes field_view_point; a
// turn is clockwise on the screen (+x: down-right -> down-left) and the
// facings turn with it.
//   battlecalc tests/test_battle_field_view.das
require math
require ../scripts/ui/battle_field.das
require ./test_check.das


[export]
def main() : int {
    let w = 10
    let h = 14
    for (mi in range(2)) {
        for (rot in range(4)) {
            let v = FieldView(mirror = mi == 1, rot = rot, w = w, h = h, x0 = 3, y0 = 5)
            let swapped = (mi == 1) != ((rot & 1) != 0)
            let vw = swapped ? h : w
            let vh = swapped ? w : h
            var seen : array<bool>
            seen |> resize(w * h)
            var ok = true
            for (ty in range(h)) {
                for (tx in range(w)) {
                    let q = field_view_point(v, float2(float(tx), float(ty)))
                    let vx = int(floor(q.x + 0.5))
                    let vy = int(floor(q.y + 0.5))
                    if (vx < 0 || vy < 0 || vx >= vw || vy >= vh || seen[vy * vw + vx]) {
                        ok = false
                        continue
                    }
                    seen[vy * vw + vx] = true
                    let g = field_game_tile(v, vx, vy)
                    ok = ok && g.x == tx + 3 && g.y == ty + 5
                }
            }
            check("mirror {mi} rot {rot}: tiles map one to one and back", ok)
        }
    }
    // a turn: +x (1, 0) relative to the origin goes to (0, 1) - drawn
    // down-left instead of down-right
    let v1 = FieldView(rot = 1, w = w, h = h)
    let a = field_view_point(v1, float2(0.0, 0.0))
    let b = field_view_point(v1, float2(1.0, 0.0))
    check("turn: +x -> +y", b.x - a.x == 0.0 && b.y - a.y == 1.0)
    var st = FieldState(view_rot = 1)
    let m = FieldMap(w = w, h = h)
    check("turn: facing +y (0) -> -x (1)", field_view_facing(m, st, 0) == 1)
    let mm = FieldMap(w = w, h = h, mirror = true)
    st.view_rot = 0
    check("mirror: facing +y -> -x, -x -> +y", field_view_facing(mm, st, 0) == 1 && field_view_facing(mm, st, 1) == 0)
    return report()
}
