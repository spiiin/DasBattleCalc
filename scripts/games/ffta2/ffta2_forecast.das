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
require daslib/strings_boost
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

// The statuses an apply function (script 897) puts on the target: its
// native_1615(target, status, 1, 0) calls (research/ffta2/notes.md,
// "Statuses"). Several: the game picks one.
let private APPLY_STATUS = fixed_array<int2>(
    int2(12, 58), int2(43, 17), int2(44, 15), int2(45, 14), int2(46, 18), int2(48, 16), int2(49, 25), int2(51, 26),
    int2(53, 5), int2(54, 8), int2(55, 10), int2(56, 7), int2(57, 6), int2(58, 22), int2(61, 34), int2(64, 12),
    int2(65, 9), int2(66, 28), int2(67, 29), int2(68, 27), int2(69, 13), int2(71, 11), int2(72, 46), int2(73, 33),
    int2(74, 23), int2(76, 31), int2(77, 32), int2(78, 30), int2(79, 21), int2(80, 24), int2(89, 36), int2(90, 40),
    int2(91, 38), int2(92, 42), int2(93, 47), int2(96, 55), int2(98, 57), int2(100, 50), int2(101, 51),
    int2(102, 52), int2(103, 49), int2(107, 54), int2(108, 37), int2(109, 41), int2(110, 43), int2(111, 39),
    int2(112, 48), int2(113, 35), int2(155, 4), int2(156, 17), int2(158, 70), int2(159, 56), int2(161, 71),
    int2(162, 20), int2(177, 72))
let private APPLY_MANY = fixed_array<string>("82: 3 10 13 31 32", "86: 9 23 24 31 32", "87: 10 29 31",
    "88: 9 27 31", "62: 5 6 8 22 25 26")

// the status an apply function puts on the target, -1: none or several
def apply_status(apply : int) : int {
    for (p in APPLY_STATUS) {
        if (p.x == apply) {
            return p.y
        }
    }
    return -1
}

// what an effect does, for the forecast: "damage", "Sleep", ...
def effect_text(apply : int) : string {
    if (apply == 1) {
        return "damage"
    } elif (apply == 17) {
        return "healing"
    } elif (apply == 3) {
        return "MP damage"
    } elif (apply == 18) {
        return "MP healing"
    } elif (apply == 13) {
        return "KO"
    } elif (apply == 14 || apply == 36 || apply == 37 || apply == 39) {
        return "revive"
    } elif (apply >= 19 && apply <= 35) {
        return "removes statuses"
    }
    let s = apply_status(apply)
    if (s >= 0) {
        return status_name(s)
    }
    for (m in APPLY_MANY) {
        if (starts_with(m, "{apply}:")) {
            var names : array<string>
            for (n in split(slice(m, find(m, ":") + 2), " ")) {
                names |> push(status_name(to_int(n)))
            }
            return "one of {join(names, " / ")}"
        }
    }
    return "effect {apply}"
}

// it puts a status on the target (an effect with a known status)
def inflicts_status(ab : Ability2) : bool {
    if (ab.name == "" || ab.name == "-") {
        return false
    }
    for (fx in ab.fx) {
        if (fx.x != 0 && apply_status(fx.y) >= 0) {
            return true
        }
    }
    return false
}

// one effect of the ability that applies to the target
struct VmEffect {
    index : int                     // 0..3 in Ability2.fx
    apply : int                     // the apply function (script 897): 1 damage, 17 healing, 64.. statuses
    hit : int
    amount : int                    // 0 when the effect has no amount function
    problem : string                // a native the model does not know (hit / amount not computed)
    after_hit : bool                // its hit asks whether the effect before it hit: the chance if it did
}

struct VmForecast {
    ok : bool                       // all three scripts ran with known natives
    no_effect : bool                // no effect applies to the target (the game shows 10001)
    problem : string
    effect : int = -1               // the first effect that damages or heals
    healing : bool
    hit : int
    amount : int
    effects : array<VmEffect>       // every effect whose condition holds
}

// natives: units are handles 1 (attacker) and 2 (target)
class ActionHost : VmHost {
    units : array<Unit2>
    effect : int
    landed : int                    // native 18 (2): the previous effect hit (1 for the effects after the first)
    asked_landed : bool
    privilege : int

    def unit(h : int) : Unit2 {
        return units[clamp(h - 1, 0, length(units) - 1)]
    }

    def override native(var vm : Vm; id : int) : bool {
        var r = 0
        let a1 = vm->arg(1)
        if (id == 18) {
            // the action's context: (1, ..) the current effect; (4, ..) the
            // race of Natural Selection; (5, ..) battle flags - none here;
            // (2, ..) whether the previous effect hit
            r = a1 == 1 ? effect : (a1 == 2 ? landed : 0)
            asked_landed = asked_landed || a1 == 2
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
            r = status_rule(a1, vm->arg(2))         // (apply function, a status of the target)
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
                r = job_byte(u.job_id, 41 + id - 2851)  // job +41.. (2855: +45, the status hit base)
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
        return <- res
    }
    var host = new ActionHost(privilege = privilege)
    host.units |> push(att)
    host.units |> push(tgt)
    var vm = new Vm()
    let args <- [1, 2, ab.id, 1]
    for (k in range(4)) {
        let fx = ab.fx[k]
        if (fx.x == 0) {
            continue
        }
        host.effect = k
        host.landed = length(res.effects) > 0 ? 1 : 0
        host.asked_landed = false
        let cond = vm->run(scripts.cond, fx.x, args, host)
        if (vm.unsupported != "") {
            res.problem = "condition {fx.x}: {vm.unsupported}"
            break
        }
        if (cond == 0) {
            continue
        }
        // a damage or healing effect must run; another one that can not
        // is only marked
        let main = res.effect < 0 && (fx.y == 1 || fx.y == 17)
        var e = VmEffect(index = k, apply = fx.y)
        if (fx.z != 0) {
            e.hit = vm->run(scripts.hit, fx.z, args, host)
            if (vm.unsupported != "") {
                e.problem = "hit {fx.z}: {vm.unsupported}"
            }
        }
        e.after_hit = host.asked_landed && host.landed != 0
        if (fx.w != 0 && e.problem == "") {
            e.amount = clamp(vm->run(scripts.amount, fx.w, args, host), -999, 999)
            if (vm.unsupported != "") {
                e.problem = "amount {fx.w}: {vm.unsupported}"
            }
        }
        if (main && e.problem != "") {
            res.problem = e.problem
            break
        }
        res.effects |> push(e)
        if (main) {
            res.effect = k
            res.healing = fx.y == 17
            res.hit = e.hit
            res.amount = e.amount
            res.no_effect = res.hit == 0             // the forecast then has no entry (shows 10001)
        }
    }
    if (res.problem == "") {
        res.ok = true
        if (res.effect < 0) {
            res.no_effect = true
        }
    }
    unsafe {
        delete host
        delete vm
    }
    return <- res
}
