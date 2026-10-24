options gen2
options indenting = 4

// The forecast by the game's own scripts (ffta2_vm.das), as 0x02070ACC
// runs an action: for each effect of the ability the condition (script
// 332), then the hit (784) and the amount (598) of the first effect that
// damages or heals. The natives read the unit model (ffta2_battle.das);
// research/ffta2/notes.md, "Natives and the exact Attack".
module ffta2_forecast shared public

require gba_mem
require math
require strings
require ffta2_battle
require ffta2_vm

struct VmScripts {
    rom : uint                      // gba_rom_serial when loaded
    cond : VmScript                 // pc.bin hash 332 'b'
    hit : VmScript                  // 784
    amount : VmScript               // 598 'c'
}

var private scripts : VmScripts

def private load_scripts() {
    if (scripts.rom != gba_rom_serial() || !scripts.cond.ok) {
        scripts.rom = gba_rom_serial()
        scripts.cond <- load_vm_script(332, int('b'))
        scripts.hit <- load_vm_script(784, 0)
        scripts.amount <- load_vm_script(598, int('c'))
    }
}

struct VmForecast {
    ok : bool                       // all three scripts ran with known natives
    no_effect : bool                // no effect applies to the target (the game shows 10001)
    problem : string
    effect : int = -1
    healing : bool
    hit : int
    amount : int
}

// natives: units are handles 1 (attacker) and 2 (target)
class ActionHost : VmHost {
    units : array<Unit2>
    effect : int
    privilege : int

    def unit(h : int) : Unit2 {
        return units[clamp(h - 1, 0, length(units) - 1)]
    }

    def override native(var vm : Vm; id : int) : bool {
        var r = 0
        let a1 = vm->arg(1)
        if (id == 18) {
            // the action's context: (1, ..) the current effect; (4, ..) the
            // race of Natural Selection; (5, ..) battle flags - none here
            r = a1 == 1 ? effect : 0
        } elif (id == 48 || id == 52 || id == 65 || id == 1717) {
            r = 0                                    // game flags: none here
        } elif (id == 50) {
            r = a1 == 369 ? privilege : 0            // game variables: 369 the clan privilege
        } elif (id == 4) {
            r = 0                                    // the random value: not in a forecast
        } elif (id == 1581) {
            r = (self->unit(a1).flags >> 10) & 1     // unit parameter 8 (+0x0A) bit 10
        } elif (id == 1543) {
            r = self->unit(a1).level                 // unit parameter 0x0E: record +0x1A
        } elif (id >= 1539 && id <= 1572) {
            r = self->unit_native(id, vm)
        } elif (id == 1634) {
            let u = self->unit(a1)
            vm->write_addr(vm->arg(2), u.x)
            vm->write_addr(vm->arg(3), u.y)
        } elif (id == 1635) {
            r = FACING_FROM_GAME[self->unit(a1).facing & 3]
        } elif (id == 1698) {
            let u = self->unit(a1)
            for (k in range(EQUIP_SLOTS)) {
                if (r == 0 && u.equip[k].id != 0 && u.equip[k].kind >= 1 && u.equip[k].kind <= 25) {
                    r = u.equip[k].id
                }
            }
        } elif (id == 1699) {
            r = 1                                    // the status-immunity table: assumed allowed
        } elif (id >= 2304 && id <= 2330) {
            r = item_native(id, self->item(a1))
        } elif (id >= 2561 && id <= 2599) {
            r = ability_native(id, a1, vm->arg(2))
        } elif (id >= 2843 && id <= 2875) {
            let u = self->unit(a1)
            if (id <= 2850) {
                r = u.affinity[id - 2843]
            } elif (id == 2851) {
                r = u.job_hit
            } elif (id == 2858) {
                r = u.bare_power
            } elif (id == 2860) {
                r = u.job_50
            } elif (id == 2875) {
                r = u.flying ? 1 : 0
            } else {
                return false
            }
        } else {
            return false
        }
        vm.ret_i = r
        return true
    }

    // an item as the units carry it (edits in the calculator count), else the ROM's
    def item(item_id : int) : Item2 {
        for (u in units) {
            for (it in u.equip) {
                if (it.id == item_id && item_id != 0) {
                    return it
                }
            }
        }
        return read_item2(item_id)
    }

    def unit_native(id : int; var vm : Vm) : int {
        let u = self->unit(vm->arg(1))
        if (id == 1539) {
            return u.race_id
        } elif (id == 1540) {
            return u.job_id
        } elif (id == 1557) {
            return u.hp
        } elif (id == 1558) {
            return u.max_hp
        } elif (id == 1559) {
            return u.mp
        } elif (id == 1560) {
            return u.max_mp
        } elif (id >= 1561 && id <= 1564) {
            return u.raw[id - 1561]
        } elif (id == 1566) {
            let slot = vm->arg(2)
            return slot >= 0 && slot < EQUIP_SLOTS ? u.equip[slot].id : 0
        } elif (id == 1568) {
            return has_status2(u, vm->arg(2)) ? 1 : 0
        } elif (id == 1569) {
            return u.reaction
        } elif (id == 1570) {
            return u.support
        } elif (id == 1571) {
            return u.flags & 1
        } elif (id == 1572) {
            return (u.flags >> 2) & 1
        }
        vm.unsupported = vm.unsupported != "" ? vm.unsupported : "native {id}"
        return 0
    }
}

def private item_native(id : int; it : Item2) : int {
    if (id == 2304) {
        return it.kind
    } elif (id == 2306) {
        return it.element
    } elif (id == 2316) {
        return it.code
    } elif (id >= 2317 && id <= 2322) {
        return it.bonus[id - 2317]                   // +0x13.. Attack, Defense, Magick, Resistance, Speed, Evasion
    } elif (id == 2330) {
        return it.two_hand ? 1 : 0
    }
    return 0
}

def private ability_native(id, ability, k : int) : int {
    let ab = read_ability2(ability)
    let fx = ab.fx[clamp(k, 0, 3)]
    if (id == 2561) {
        return ab.element
    } elif (id == 2562) {
        return ab.mp
    } elif (id == 2564) {
        return ab.power
    } elif (id == 2572) {
        return fx.x
    } elif (id == 2573) {
        return fx.y
    } elif (id == 2575) {
        return fx.w
    } elif (id == 2579) {
        return int((ab.flags >> 3u) & 1u)
    } elif (id == 2594) {
        return int((ab.flags >> 18u) & 1u)
    } elif (id == 2599) {
        return int((ab.flags >> 28u) & 1u)
    }
    return 0
}

// the forecast of `ab` by att on tgt, run by the game's scripts
def vm_forecast(att, tgt : Unit2; ab : Ability2; privilege : int = 0) : VmForecast {
    var res = VmForecast()
    load_scripts()
    if (!scripts.cond.ok || !scripts.hit.ok || !scripts.amount.ok) {
        res.problem = "the scripts are not in this ROM"
        return res
    }
    var host = new ActionHost(privilege = privilege)
    host.units |> push(att)
    host.units |> push(tgt)
    var vm = new Vm()
    let args <- [1, 2, ab.id, 1]
    for (k in range(4)) {
        let fx = ab.fx[k]
        if (res.effect >= 0 || fx.x == 0) {
            continue
        }
        host.effect = k
        let cond = vm->run(scripts.cond, fx.x, args, host)
        if (vm.unsupported != "") {
            res.problem = "condition {fx.x}: {vm.unsupported}"
            break
        }
        if (cond == 0 || (fx.y != 1 && fx.y != 17)) {
            continue
        }
        res.effect = k
        res.healing = fx.y == 17
        res.hit = vm->run(scripts.hit, fx.z, args, host)
        if (vm.unsupported != "") {
            res.problem = "hit {fx.z}: {vm.unsupported}"
            break
        }
        res.amount = clamp(vm->run(scripts.amount, fx.w, args, host), -999, 999)
        res.no_effect = res.hit == 0                 // the forecast then has no entry (shows 10001)
        if (vm.unsupported != "") {
            res.problem = "amount {fx.w}: {vm.unsupported}"
            break
        }
        res.ok = true
    }
    if (res.effect < 0 && res.problem == "") {
        res.no_effect = true
        res.ok = true
    }
    unsafe {
        delete host
        delete vm
    }
    return res
}
