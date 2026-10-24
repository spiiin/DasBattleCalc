options gen2
options indenting = 4

// The FFTA battle on the shared field (ui/battle_field.das): the map and
// units converted, the tiles the attacker can Fight highlighted, moves and
// turns applied to the units. Changes stay in the calculator (the state
// is not written).
module ffta_field shared public

require math
require ../../ui/battle_field.das public
require ffta_battle
require ffta_attack
require ffta_gfx

// facing 0 +y, 1 -x, 2 -y, 3 +x; on screen +x goes down-right and +y
// down-left, so facing + 1 turns clockwise
def turn(var u : BattleUnit; clockwise : bool) {
    u.facing = (u.facing + (clockwise ? 1 : 3)) & 3
    u.position = "{u.x}, {u.y}, facing {FACING_NAMES[u.facing]}"
}

def field_map(m : BattleMap) : FieldMap {
    var f = FieldMap(w = m.w, h = m.h, x0 = m.x0, y0 = m.y0)
    f.height := m.height
    f.water |> resize(m.w * m.h)
    for (i in range(m.w * m.h)) {
        f.water[i] = (m.flags[i] & 2) != 0
    }
    return <- f
}

def field_unit(un : BattleUnit) : FieldUnit {
    // the frame's shadow is drawn ~8 game pixels above its origin: put the
    // origin 8 below the tile center so the shadow lies on the tile
    return FieldUnit(name = un.name, x = un.x, y = un.y, facing = un.facing, team = team(un), alive = un.hp > 0,
        sprite = unit_sprite(un), sprite_dy = 8.0)
}

// the field; returns what was clicked (moves and turns already applied)
def draw_field(m : BattleMap; var units : array<BattleUnit>; selected, target, attacker : int; var st : FieldState;
               x, y, w, h : float) : FieldInput {
    // which tiles the attacker can hit with Fight
    var reach : array<bool>
    if (attacker >= 0 && attacker < length(units) && st.drag < 0) {
        reach |> resize(m.w * m.h)
        for (ty in range(m.h)) {
            for (tx in range(m.w)) {
                var why = ""
                reach[ty * m.w + tx] = can_fight(m, units[attacker], tx + m.x0, ty + m.y0, why)
            }
        }
    }
    var fu : array<FieldUnit>
    for (un in units) {
        fu |> push(field_unit(un))
    }
    let res = draw_battle_field(field_map(m), fu, selected, target, reach, st, x, y, w, h)
    if (res.moved >= 0) {
        let k = res.moved
        units[k].x = res.move_x
        units[k].y = res.move_y
        units[k].position = "{res.move_x}, {res.move_y}, facing {FACING_NAMES[units[k].facing]}"
    }
    if (res.turn != 0 && selected >= 0 && selected < length(units)) {
        turn(units[selected], res.turn > 0)
    }
    return res
}
