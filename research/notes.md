# FFTA (USA, AFXE): turn order — what the game does

Read from the ROM (Thumb disassembly, `thumb.py`) and checked against the
running game in BizHawk 2.11 (mGBA core) with Lua scripts in this folder.
Addresses are for the USA ROM.

## Where the data is

- BizHawk `.State` = zip: `Core.bin.zst` (zstd), `Framebuffer.bmp`, ...
  For mGBA, `Core.bin` = 4-byte size + mGBA `GBASerializedState`
  (magic `0x01000009`): IWRAM at +0x19000 (32 KB), EWRAM at +0x21000 (256 KB).
- Unit record, 0x108 bytes (the clan at `0x02000080`, other battle units at
  `0x02002FC4` in the test save):

  | offset | field |
  |---|---|
  | +0x00 | u32 pointer to the name (ROM or RAM) |
  | +0x09 | level |
  | +0x18 / +0x1A / +0x1C | HP, max HP, MP |
  | +0x2A | 5 × u16 equipment item ids |
  | +0xD0 | CT |
  | +0xD2 | base Speed |
  | +0xD4 | CT reserve (see the tick) |
  | +0xE8..+0xED | status bits |
  | +0x104 | order byte: sorts the list and breaks ties |

- Battle participants: array of 0x90-byte wrappers, first word = unit record
  (`0x020223AC` in the test save; the app finds it by scanning). Wrapper
  +0x1E: side (0 player, 1 enemy, 2 guest — guessed from one battle).
- Text: `0xB1`.. = A-Z, `0xCB`.. = a-z, `0x00` ends; names typed by the
  player are `0x80, code - 1` pairs.
- Items: table at `0x0851D180`, 32 bytes per item, +0x14 signed speed bonus.

## Speed — `0x0812E368`

    s = max(0, base(+0xD2) + Σ speed bonus of the 5 items)    ; 0x080CA580
    if (+0xEC & 0x04) or (+0xEA & 0x02): s >>= 1
    if (+0xEA & 0x20): s <<= 1        ; Haste?
    if (+0xEA & 0x40): s >>= 1

Units with (+0xE8 & 0x40) or (+0xED & 0x40) or speed 0 do not gain CT (KO and
similar; status names are not identified yet).

## Tick — `0x0809DF7C`

    for each unit:  eligible ? CT += reserve + speed : CT = 0;  reserve = 0
    M = max CT
    if M > 1000:  E = min(M − 1000, 500)
                  for each unit: CT ≥ E ? (CT −= E, reserve = E) : (reserve = CT, CT = 0)

The excess moves into the reserve and comes back on the next tick, so the
actor shows CT = 1000 while nothing is lost.

## Next actor — `0x0809E05C`

1. A unit with (+0xE8 & 0x02) (Quick?) acts at once.
2. Else tick until an eligible unit has CT > 999.
3. The actor: max of `(CT + reserve) << 8 | order(+0x104)`; ineligible: −100.

## End of turn — `0x0809F8EC`

    CT = max(0, CT − 500 − (moved ? 200 : 0) − (acted ? 300 : 0));  reserve = 0

(Wikis say "CT = 500 − …"; the game subtracts, so CT above 1000 carries over.)

## Validation

- `probe.lua` / `writes.lua`: CT writes and their PCs (found the routines).
- `long.lua` + `turnsim.py`: 15 000 frames of the test battle (player turns
  end with Wait): 19 of 19 ticks equal to the model, including the actor.
  Lunais ends each turn at once (CT → 0 within the 20-frame log gap).
- `tests/test_ffta_turn_order.das`: the daslang model replays the 22 recorded
  turns of the test save — PASS.

Not checked yet: Haste / Slow / Stop / Quick in battle, equipment with speed
bonuses, other battles (wrapper array address, side byte).

# Stats and equipment (attack plan, stage 1)

Checked against the Status screen of every unit of the test save
(`status_copy.lua`: each record copied over Marc's, then Status opened) and
by `tests/test_ffta_stats.das` — PASS 5 of 5.

## Tables in ROM

- Items `0x0851D180`, 32 bytes: `+0x00` u16 name (text id), `+0x08` kind
  (1 Sword … 13 Bow, 14 Greatbow, 19 Gun, 20 Shield … 30 Item; names in
  `ffta_battle.das`), `+0x10..+0x17` signed bonuses W.Atk, W.Def, M.Pow,
  M.Res, Speed, Evade, Move, Jump. Getter `0x080CA7A4(item, stat)`: stats
  10..17 are these bytes; 10..13 of items 51, 302, 148, 286 get extra points
  when story flags are set (`0x080C95A8`), not modelled.
- Jobs `0x08521A14`, 52 bytes, index = record `+0x05`: `+0x00` u16 name,
  `+0x05` parent (255: use record `+0x07`, other nonzero: that job; e.g.
  Marc 0x50 → 0x02 Soldier), `+0x28` Move, `+0x29` Jump, `+0x2A` Evade.
  Lookup `0x080C8570(job, job2, field)` (jump table of 48 fields).
- Texts `0x08526680`: u32 pointers by text id. Codes: `0x80 n` = n + 1,
  `0x40 0x73` and `0x40 0x3E n` space, `0x40 0x3C n` kerning, `0xF5` `'`,
  `0xFF` `-`.

## Stats

| stat | function | formula |
|---|---|---|
| W.Atk / W.Def / M.Pow / M.Res | `0x080CA624` / `6B4` / `66C` / `6FC` | record `+0x20/+0x22/+0x24/+0x26` + Σ items, ≤ 999 |
| Speed | `0x080CA580` | record `+0xD2` + Σ items (statuses — see above) |
| Evade | `0x080CA5C4` | job `+0x2A` + Σ items, 0..100 |
| Move | `0x080CA394` | job `+0x28` (+1 if record `+0x3D` == 1) + Σ items |
| Jump | (same pattern) | job `+0x29` + Σ items |

Not checked yet: items with Move / Jump bonuses, the +0x3D Move bonus.

# Attack ("Fight", attack plan stage 3)

Model: `attack.py`. Checked against the game's own preview: `attack_probe.lua`
patches RAM (statuses, stats, facing, whole unit records) before the preview
of Marc → Montblanc and reads the game's damage (`0x0813023C` r0) and hit
chance (`0x0812C8C6` r0) — 18 of 18 cases equal (`python attack.py`).

Call chain of a real attack: `0x080A2918` → effect `0x08130200(att, tgt,
ability, weapon, kind, mode)` → damage `0x0812FE38`. The preview calls the
same with mode 2 (no random part). Hit: `0x0812EF94` → `0x0812C7F4`.

## Where things are

- Position and facing: wrapper `+0x08 >> 5` (x), `+0x0C >> 5` (y), `+0x1F`
  facing (0: +y, 1: −x, 2: −y, 3: +x); copied to record `+0xF6/+0xF7/+0xF8`
  before the computation (writing the record copy has no effect).
- Record `+0x28`: bit 15 enemy, bit 13 guest, bit 12 judge.
- Element affinities of the target: record `+0x0C..+0x14`, by element
  (1 Fire, 2 Wind, 3 Earth, 4 Water, 5 Ice, 6 Lightning, 7 Holy, 8 Dark):
  0 weak ×1.5, 1 normal, 2 immune, 3 absorb, 4 half. Weapon element: item `+0x09`.
- Unit getter `0x080C7EA4(u, id)`: ids 10..18 → `+0x0C..+0x14`, 19.. → u16
  `+0x18, +0x1A, …` (23 W.Atk `+0x20`, 24 W.Def `+0x22`, 25 M.Pow, 26 M.Res),
  29..33 equipment.
- Status tests `0x080CD92C…0x080CDC8C` (24 bytes each): one bit of
  `+0xE8..+0xED` each. Names below are guesses from the effects.

## Damage (`0x0812FE38`, physical, no ability)

    P = weapon W.Atk (item +0x10; bare hands: job entry +0x33, no parent chain)
        + W.Atk of the other non-weapon equipment;  0 if attacker Frog (E9&1)
    A = record W.Atk (+0x20) × attacker statuses + P,  ≤ 999
    D = record W.Def (+0x22) × target statuses + Σ equipment W.Def
        (no equipment if target Frog),  ≤ 999
    dmg = max(1, max(1, A − D/2) × P / 100)          (integer, D/2 = D >> 1)
    × element: weak ×1.5, immune 0, absorb −, half /2
    × 1.5 on a critical hit;  target EC&2 → 0
    real attack: + random whole number in [−dmg/10, +dmg/10]
    clamp −999..999

Status multipliers (each `v = v × k >> 8`): attacker E8&0x80 ×307 (1.2,
Boost?), E9&1 ×25 (Frog), E9&0x40 ×384 (1.5, Berserk?), EC&8 ×281, EC&0x10
×230; target EB&2 ×358 (Protect, 1.4), E8&0x40 ×460, E9&1 ×25, E9&0x20 ×358,
EC&0x80 ×358, ED&1 ×179. Magic-only ones: attacker EC&0x20 / EC&0x40, target
EB&1 (Shell), ED&2, ED&4. Support abilities (`0x080CD50C`: record `+0x3B` →
race list `0x0851BA84[+0x06]`, 8-byte entries, `+4` id) and mission bonuses
(`0x080D2BF4`, mission `0x02003C28`, 0 in the test save) are not modelled.

## Hit chance (`0x0812C7F4`)

    E = target Evade (job +0x2A + items; no items if Frog), 0..100
    E = E / (1 front, 2 side, 4 back)     side: first quadrant of 90° around
        the target's facing (front, left/right, back) holding the attacker
    E += −20 target Blind (E9&4) −10 target EB&0x10 +50 attacker Blind
         −50 / −15 attacker support ability 13 / 4
    shown = 100 − clamp(E, 5, 95)
    100 if the target cannot evade (HP 0, E8&0x40, E9&0x80, EA&0x80, EB&4,
    EC&2) or has EA&2.

The roll (`0x080A2846`) uses shown + 10 (≤ 100) when the attacker is not an
enemy: Marc → Montblanc shows 65 %, rolls 75 %. Roll `0x0812F1DC(p)`:
success when `rand%10000 + 1 ≤ 100p + rand%100`, i.e. (100p + 49.5) / 10000.
Height does not change the hit chance or the damage of Fight; direction
changes only the hit chance.

## Critical hit (`0x0812E0FC`)

    chance = job Evade (+0x2A, without items) / 10, +30 with EA&1, 0..100

On a crit the effect is computed again with mode 1 (×1.5) and the target
is knocked back one tile if it can be (`0x0809AA94`, `0x081302F8`).

Not checked yet: elements, crit ×1.5 and the random part in a real hit
(one real hit: 19 for preview 20 — inside 18..22), support abilities, bows
(range, height, line of fire — attack plan stage 2).

# Battle map (attack plan stage 2)

`0x02007F10` (read by `0x0801CC18` height, `0x0801CD08` flags, `0x0801CC7C`
"is a tile"): `+0x04` pointer to the tiles, 2 bytes each — height, flags;
`+0x08` tiles per row; `+0x0A / +0x0C` first x / y and `+0x0D / +0x0F` width /
height of the playable area. Height 0: no tile. Flags: `0x02` water (a unit in
it stands one lower, `0x08131BE0`), `0x01` unknown. Test save: 14 × 14,
heights 3..18, units on height 10.

Unit position: `0x08099E68` sets wrapper `+0x08 = x·32 + 16`, `+0x0C = y·32 + 16`,
`+0x0A = tile height · 16` and record `+0xF6/+0xF7`.

Weapon range: item `+0x0A` (swords 1, spears 2, bows 5, guns 8). Item `+0x0B`
(1 or 2) marks what is held in the hands (`0x0812E4F4` lists the equipment
with `+0x0B` 1..2 that is not a shield as weapons) — not a range type.

# Fight reach (who can attack whom)

Model: `reach.py`; checked by `range_probe.lua` (Marc's weapon and tile heights
patched, Fight opened, the result of the tile rule logged for every tile the
game tries): 190 of 190 equal — sword, spear, Longbow, gun, heights −4..+3.

- Target area `0x080B44F8`: rings of tiles around the attacker up to the range
  from `0x080B7C94` / `0x080B448C` (weapon `+0x0A`, bare hands 1), each tested
  by `0x080A0254` → for Fight `0x0809FEF0`.
- `0x0809FEF0`: the tile must exist (height ≠ 0), have no flag `0x01` or
  `0x08`, and not be the attacker's. Weapon kind (`0x0812EE98`: item `+0x08`,
  bare hands 17; a job with field 40 & 4 counts as a gun with range 4):
  - **bows, greatbows, guns** (13, 14, 19): `|dx| + |dy| ≤ range` — height and
    obstacles do not matter (heights +8 above the archer were in reach);
  - **other weapons** (`0x0812E1A8`, dh = target tile height − attacker's):
    the next tile with −3 ≤ dh ≤ 2;
  - **spears** (15): the next tile with −4 ≤ dh ≤ 3, or 2 tiles in a straight
    line with dh ≤ 2 and dh ≥ a bound set by the tile between (m = its height −
    attacker's): m < 0 → −3, 0 → −2, 1 → −1, 2 → 1, 3 → 2, higher → blocked.
- Heights are the raw tile heights (`0x0801CC18`); a unit standing in water is
  drawn one lower (`0x08131BE0`), which the rule does not use.

# Abilities (support, Soldier's Battle Tech)

Checked with `attack_probe.lua` (support: record `+0x3B` patched) and
`ability_probe.lua` (techs learned: `+0x40 + index` = 0x80; Euver moved next to
Marc for the enemy-only ones; the preview, then the real use and the record
diff); `tests/test_ffta_abilities.das` — 12 of 12.

## Tables

- Action abilities `0x0855187C`, 28 bytes (getter `0x080CCD50(id, field)`):
  `+0x00` name (text table 2, `0x085567F0`), `+0x04` MP cost (field 2),
  `+0x05` ≠ 0: power = weapon power (field 3), `+0x06 & 0x80`: Fight reach
  (field 4), `+0x0B` power (field 33), `+0x10` flags (fields 11..31 = bits
  0..20; field 29 = bit 18: physical — W.Atk / W.Def, else M.Pow / M.Res).
- Race ability lists `0x0851BA84[race +0x06]`, 8 bytes: `+0x00` name (text
  table 2), `+0x04` id in the table of its type, `+0x06` type (1 action,
  2 reaction, 3 support, 5 combo), `+0x07` AP / 10. Learned: record
  `+0x40 + index` bit 0x80 (`0x080CD544`). Support: record `+0x3B` = index.
- Support ids: 1 Weapon Atk+, 2 Weapon Def+, 3 Magic Pow+, 4 Turbo MP,
  5 Geomancy, 6 Monkey Grip, 7 Doublehand, 8 Double Sword, 9 Maintenance,
  10 Half MP, 11 Immunity, 12 Learning, 13 Concentrate, 15 Shieldbearer.
  Reactions: 1 Last Quicken … 8 Counter … 15 Absorb MP (not modelled).

## Support effects (`0x080CD50C` = the unit's support id)

| support | where | effect | checked |
|---|---|---|---|
| Weapon Atk+ (1) | `0x0812F48C`, attacker | physical attack value ×307/256 | 20 → 25 |
| Magic Pow+ (3) | same | magic attack value ×307/256 | — |
| Turbo MP (4) | same; `0x0812C610` | ×332/256 for abilities with an MP cost; Evade −15 | 65 → 80 % |
| Doublehand (7) | same | ×307/256 in Fight with a weapon of item `+0x0B` == 1 | 20 → 25 |
| Concentrate (13) | `0x0812C610` | Evade −50 | 65 → 95 % |
| Weapon Def+ (2) | `0x0812F770`, target | physical defense ×358/256 | 20 → 15 |

The support factor applies before the statuses (attack: `0x0812F410` →
`0x0812F48C` → `0x0812F528` → + P; defense: `0x0812F704` → `0x0812F770` →
`0x0812F798` → + items).

## Battle Tech (Soldier)

All use the damage function with the ability's data: physical → W.Atk / W.Def,
magic → M.Pow / M.Res; the multiplier is the weapon power when `+0x05` ≠ 0, else
the ability's `+0x0B`; the hit chance is the Fight one (Evade, side).

| # | ability | effect | game |
|---|---|---|---|
| 76 | First Aid | the user only; HP + (M.Pow − M.Res / 2) × 25 / 100 | +7; +38 with M.Pow 200 |
| 77 | Powerbreak | status `EC & 0x10` (W.Atk ×230/256) | 65 % |
| 78 | Mindbreak | status `EC & 0x40` (M.Pow ×230/256) | 65 % |
| 79 | Magicbreak | MP damage, the Fight formula | 20 / 65 %, real −19 MP |
| 80 | Speedbreak | status `EC & 0x04` (Speed / 2) | 50 % |
| 81 | Mug | HP damage (Fight formula), steals gil; enemies only | 20 / 50 %, real −19 HP |
| 82 | Provoke | Berserk = `E8 & 0x80` (W.Atk ×307/256); enemies only | 50 % |
| 83 | Sensor | info | — |

Not checked: the +10 of the roll for abilities (seen only in the Fight path),
the reach of Provoke / Sensor (ability data, not the weapon), the other jobs'
abilities and the reactions.

# Ability effects (all jobs)

Each action ability lists up to 4 effects (ability `+0x0C..+0x0F`, 0 / 1 = none)
in the effect table `0x08553E70` (4 bytes: `+1` kind, `+3` function). Kinds
`0x083A87B0` (12 bytes): `+0` handler, `+4` category (0 status, 1 HP, 2 MP,
6 revive, …), `+8` sign (1 harmful, 0xFF helpful; the value is multiplied by
it — the preview shows heals as negative). Functions `0x083A86F8[+3]`;
`ability_effects.txt` lists every ability with them. Over 351 abilities:

| function | effects | value |
|---|---:|---|
| `0x08131481` | 223 | 0: a status only (Protect, Sleep, Blind, Slow, …) |
| `0x0813189D` | 125 | the damage formula `0x0812FE38` with the ability (Fire, Holy, …) |
| `0x08131961` | 18 | the heal formula `0x08130150` (Cure, Raise, …) |
| `0x081318D5` / `0x08131A99` | 7 / 5 | the damage formula ×2 / ×3 (Holy Blade, Ultima …) |
| `0x08131931` | 8 | the formula, at most the target's MP (Rasp, Magicbreak) |
| `0x081319FD` + `0x08131751` | 4 | Drain: at most the target's HP, the user gets it back |
| `0x08131A61` / `0x08131A51` | 4 / 2 | revive with max HP / 2, max HP (Life, Full-Life) |
| others | ~30 | special (Demi, Death, steals, Blitz, …): not modelled |

A formula damage effect after a heal / revive one is the damage to undead
(Cure, Life: the second effect).

- **Spell damage**: the same formula as Fight with M.Pow / M.Res (magic flag:
  ability `+0x10` bit 18 clear) and the ability's power `+0x0B`; P = all
  equipment M.Pow, D = record M.Res × statuses + equipment M.Res. Element:
  ability `+0x02` (else the weapon's when the power is the weapon's).
  Fire from Montblanc's record: Montblanc 10, Euver 22 — equal to the game.
- **Heal** (`0x08130150`): A = record M.Pow × support × statuses (no
  equipment), D = the target's **record** M.Res (no equipment, no statuses);
  (A − D/2 ± random/10) × power / 100, 1..999. Cure (power 40) from Marc:
  Montblanc +3, himself +12; First Aid +7.
- **Hit**: harmful effects use the Fight hit chance (Evade, side; Fire 65 % on
  Montblanc, 50 % on Euver, 40 % on Lunais in the area); helpful ones (sign −1)
  have no roll in the preview (shown as 100 %).
- **Reach / area**: ability `+0x06` = range in tiles (0: the user; `& 0x80`:
  the weapon's Fight reach), `+0x09` = 5: an area of radius `+0x0A` around the
  target (Fire 1 hit Montblanc, Marc and Lunais). Height limits of spells are
  not checked.
- **Statuses**: Protect = `EB & 0x02` (+ a counter `+0xDE` = 3). The kind
  handlers set other bits; mapping every status kind to its bit is not done.

Checked: `tests/test_ffta_magic.das` (6 cases: Fire ×2, Thunder, Cure ×2,
Protect). Not checked: the +10 roll bonus for abilities, spell height limits,
undead, reflect, Doublecast and the special functions.

# Status bits (+0xE8..+0xED)

`status_bits.py` → `status_kinds.txt`: setters `0x080CDD1C…0x080CE1D4` (one per
bit: `(unit, on)` clears the bit, sets it when on ≠ 0); the handler of each
status effect kind (`0x083A87B0 +0`) calls them with `mov r1, #1` / `#0`; the
abilities using the kind name the bit. Harmful kinds also clear `E8 & 0x10`
(Astra blocks a status).

| byte | 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x80 |
|---|---|---|---|---|---|---|---|---|
| E8 | ? | Quick | Auto-Life | Regen | Astra | Reflect | Petrify | Berserk |
| E9 | Frog | Poison | Blind | Zombie | Invisible | Defense | Boost | Hibernate |
| EA | Advice (crit +30) | Mow Down? | monster? | Cover | Doom | Haste | Slow | Stop |
| EB | Shell | Protect | Sleep | Silence | Confuse | Charm | Immobilize | Disable |
| EC | Addle | Expert Guard | Speed down | W.Atk up | W.Atk down | M.Pow up | M.Pow down | W.Def up |
| ED | W.Def down | M.Res up | M.Res down | monster? | (Petrify) | ? | (no CT) | ? |

These agree with the effects found before: Boost ×1.5 attack (E9&0x40),
Defense ×1.4 W.Def (E9&0x20), Haste ×2 / Slow ÷2 speed, Blind −50 / −20 to hit,
Confuse −10 Evade, Sleep / Stop / Petrify cannot evade, W.Atk up ×1.1 / down ×0.9.

# Real hits (statistics)

`live_probe.lua`: the state is reloaded for every trial and the game's random
seed (`0x030034B0`; LCG `x × 0x41C64E6D + 0x3039`, `rand()` = bits 16..30,
`0x08002804`) is set to a random 32-bit value right before the action is
confirmed; `live_stats.py` sums up. Seeds in a line (t × K) do not work: the
rolls through the LCG come out correlated (a residue of `rand % 5` never came).

| series | game | model |
|---|---|---|
| Fight Marc → Montblanc, 300 | hit 77.7 ± 2.4 %; damage 18..22 uniform | 75.5 %; 20 ± 2 |
| crits in it | 20 / 233 = 8.6 ± 1.8 %; 27..33; pushed 20 / 20 | 5.5 %; 30 ± 3; knockback |
| Fight with Advice (EA & 1), 200 | crits 63 / 154 = 40.9 ± 4.0 % | 35.5 % |
| Powerbreak (shown 65 %), 200 | success 79.5 ± 2.9 % | 75.5 % (shown + 10) |
| Cure on himself, 100 | +10 / 11 / 12 / 13: 10 / 31 / 48 / 11 % | (30 ± 3) × 40 / 100: 14 / 29 / 43 / 14 % |

Element affinities by the preview (Flametongue, Fire 1, the target's `+0x0D`):
normal 35, weak 52, immune 0, absorb −35, half 17 — equal to the model.

So: the +10 of the roll holds for abilities too; the random part of a heal is
on the base.

## The roll is not (100p + 49.5) / 10000

`0x0812F1DC(p)` compares `rand₂ % 10000 + 1` with `100p + rand₁ % 100`, and
rand₁, rand₂ are two consecutive outputs of the LCG — they are correlated.
`roll_table.py` averages over random seeds: p 5 → 6.70 %, 35 → 40.94 %,
75 → 77.56 % (about 1.22 p % up to p ≈ 27, then about 0.92 % per point);
the calculator uses that table (`ROLL_CHANCE` in `ffta_attack.das`).

`roll_probe.lua` (the action is walked once, kept as an in-memory core state,
then every trial only sets a random seed and runs 50 frames): 1500 + 1500 Fight
hits — crit 74 / 1147 = 6.45 % (model 6.70 %, naive 5.49 %), with Advice
502 / 1159 = 43.3 % (model 40.94 %, z 1.6; naive 35.49 % is out, z 5.6); hit
76.5 % and 77.3 % (77.56 %). The crit chance in the roll is 35 with Advice
(traced), and the crit roll does not depend on the hit roll before it (the
conditional chance is the same for 0..11 LCG steps between them).

# Reactions

The reaction is record `+0x3A` (race list index, like the support at `+0x3B`);
`0x080CD4D4` → its id, `0x0812E6A4` → the id if the unit is not KO and its
statuses allow it (`0x08133ADC`, not modelled). `0x0812EA44(attacker, target,
ability)` → `0x0812E6E0`, a switch on the id (table `0x0812E728`). Ability
flags: `+0x10` bit 6 (field 17) no reaction, bit 15 reflectable, bit 16 can be
caught, bit 17 MP absorbable, bit 18 physical. "Reach" = the target's melee
rule `0x0812E1A8` towards the attacker.

| id | reaction | triggers on | effect |
|---|---|---|---|
| 1–3 | Last Quicken / Haste / Berserk | a harmful action with damage > 0, the status not on yet | the status |
| 4 | Catch | an ability that can be caught, from the other side | catches it |
| 5 | Reflex | Fight | the hit chance is 0 (`0x0812C5CC`) |
| 6 | Block Arrows | a bow / greatbow (Fight or a weapon ability) | the hit chance is 0 |
| 7 | Strikeback | Fight, in reach | the hit chance is 0, strikes back |
| 8 | Counter | Fight or a physical ability, in reach | strikes back (Fight) |
| 9 | Return Fire | Fight with a bow | shoots back |
| 10 | Bonecrusher | as Counter | strikes back ×1.5 (damage kind 10, `0x0813009C`) |
| 11 | Return Magic | a reflectable ability | reflects it |
| 12 | Dragonheart | physical damage > 0 | Auto-Life |
| 13 | Damage > MP | damage > 0, MP > 0 | the damage from MP |
| 14 | Auto-Regen | damage > 0, no Regen yet | Regen |
| 15 | Absorb MP | an ability with that flag | the MP |

Real uses (`live_probe.lua`, Montblanc made a human Soldier with the reaction,
Marc's Fight): Reflex — Marc's roll 0 (25 / 25 missed); Strikeback — always
missed, struck back for 4; Counter — the strike back is a Fight (A 96, D 140 →
4, roll 56 %: 82 / 144 = 56.9 %, crits 3 / 82), also after a miss, not after a
crit that pushed the target out of reach; Bonecrusher — 6 (crit 9). The rolls
follow the formula exactly (34 / 34 outcomes recomputed from the seeds).
Lesson: the series must use different Lua seeds — Counter and Bonecrusher with
the same seed repeated the same outcomes and looked like 30 % crits.

## Writing a state

`gba_save_state` (native/gba_mem.cpp) copies every entry of the loaded
BizHawk zip and replaces `Core.bin.zst` with the edited core: IWRAM at
mGBA `+0x19000`, EWRAM at `+0x21000` (after BizHawk's 4-byte size if the
loaded core had it). There is no zstd compressor in the project, so the
frame is made of raw blocks (magic, descriptor `0xE0` = 8-byte content
size + single segment, blocks of up to 128 KB with a 3-byte header,
type 0); the zip entry is deflated instead (state 104 KB vs 100 KB of
the original). BizHawk 2.11 loads it (`research/export_check.lua`).

What `export_battle` writes per unit: record `+0x05` / `+0x07` job,
`+0x18` HP, `+0x1A` Max HP, `+0x1C` MP, `+0x20..+0x26` stats, `+0xD2`
base Speed, `+0xD0` CT, `+0xD4` reserve, `+0x2A` items, `+0xE8..+0xED`
statuses, `+0x3B` / `+0x3A` support / reaction as race list indices (and
the learned bit `+0x40 + i`), wrapper `+0x08` / `+0x0C` (x·32+16,
y·32+16), `+0x0A` (tile height·16), `+0x1F` facing and record
`+0xF6/+0xF7/+0xF8`. In the game the moved sprite stands on the new tile
and the info panel shows the new HP / MP after it is redrawn (the panel
on screen at load time is the saved picture). Evade, Move and Jump come
from the job table and are not written.

## Learned abilities by job

A race ability list (`0x0851BA84[race]`) is ordered by job: the entries
of one job end with its combo (type 5), and the blocks follow the order
of the race's jobs (humans: Soldier 1–11, Paladin 12–22, Fighter 23–34,
Thief 35–46, Ninja 47–57, White Mage 58–68, Black Mage 69–80,
Illusionist 81–91, Blue Mage 92–117, Archer 118–128, Hunter 129–140;
entry 141 Blank Card after the last combo; Bangaa: 76 entries). The
editor groups the checkboxes this way
(`ability_blocks`); entry i learned = record `+0x40 + i` bit 0x80, which
the export writes back (other bits of the byte kept). Which learned
actions the game offers in battle (the job's set and the secondary set)
is not modelled: the Attack tab lists all learned actions.

## Second battle (2026-10-23)

The model checked on a battle it was not built from: 12 participants
(Goblins, a Red Cap, a Sprite, the clan: Soldier x2, White Monk, Black
Mage, Archer, White Mage; the Judge). Saves: `ffta_test_battle2_start`
(every CT 0) and `ffta_test_battle2` (Loki's turn); test
`tests/test_ffta_battle2.das`.

- Turn order: from the start the tick model reaches Loki's turn after 9
  ticks with the CT of all 11 units equal to the game's.
- Stats: the Status screens of all 12 units (status_copy.lua with
  PROBE_ACTOR = Loki, PROBE_MACRO for a menu already open) - 96 values,
  all equal.
- Fight forecasts (attack_probe.lua, PROBE_PLAN): 8 attackers copied over
  Loki's record (keeping Loki's flags, else the AI takes the turn) x 6
  targets put into Marc's place by the record pointer of his wrapper, and
  targets turned (+0x1F) for front / side / back: 66 forecasts, damage
  and shown hit all equal.
- The wrapper's +0x1E is not the team: here the Goblins have 0 (as the
  clan) and Cristine and Nusratt of the clan have 1. Teams come from the
  record flags +0x28 (0x8000 enemy, 0x2000 guest, 0x1000 judge): `team()`.
  It is the palette row of the unit's map sprite (see "Graphics").

# Graphics (2026-10-24): portraits, item icons, map sprites

Found with `gfx_probe.lua` (logs the decompressors and VRAM copies,
dumps VRAM / palette / OAM / EWRAM), `gfx_writes.lua`, `gfx_producer.lua`,
`gfx_portrait_ids.lua` and the disassembly; decoded and checked by
`gfx_decode.py`, `gfx_sheets.py` (portraits, icons) and `gfx_sprites.py`
(map sprites). Their outputs go to `research/gfx/` (not in the
repository: they are pictures from the ROM). Pointers below are ROM
addresses; "table T" = the game's offset table (`0x080071A8`): byte 0 ==
2 - entry i at T + 4 + u16[T + 4 + 2i], else at T + 4 + u32[T + 4 + 4i];
u16 at T + 2 = number of entries.

## Compression

- **LZSS** (`0x0800543C(dst, src)`): 4-byte big-endian output length,
  then opcodes by the high bits of each byte (Data Crystal, "Final
  Fantasy Tactics Advance: Compression Formats"): `1LLLLDDD DDDDDDDD`
  copy L+3 from D+1 back, `01NNNNNN` N+1 literals, `001NNNNN` N+2 zeros,
  `0001LLLL LLDDDDDD DDDDDDDD` copy, `0x01 N` N+3 x 0xFF, `0x02 N` N+3
  zeros, `0x00 N DDDD` copy N+5.
- **"A7" archive** (`0x08005318(archive, dst, first, count)`): `"A7"`,
  BE16 entry count, BE32 offset of a shared dictionary, BE32 offsets of
  the entries (from the archive start). Dictionary: kind, bits, and for
  kind 0 a BE16 output length (kind 3: each entry starts with its own
  BE16 length). An entry (`0x080051C4`): byte c with bit 7 - (c & 0x7F) + 1
  literal bytes follow; else ((c << 1) >> (8 - bits)) + 3 bytes are copied
  from the dictionary at ((c << 8) | next byte) & (0xFFFF >> (bits + 1)).
- GBA BIOS LZ77 (`0x0801F100` dispatches 0x10 / 0x11 / 0x01) was not met
  on these screens.

## Portraits (Status screen, battle HUD)

- Which portrait (`0x080CB868(dst, unit)`): a story character (record
  `+0x04` > 1) - byte `+0x0B` of its 14-byte entry at `0x085273D8 +
  14 * +0x04`; any other unit - job field `+0x0D` through the parent
  chain (`0x080C8570`: job `+0x05` is the parent job, 0xFF = the record's
  `+0x07`, 0 = this job). 103 portraits.
- Tiles: LZSS at table `0x083E105C`[portrait], 8bpp (64-byte tiles), the
  pixel values are OBJ colours 96..143.
- Palette (`0x080CB7C0(unit, ally)`): character entry `+0x0C` (ally) /
  `+0x0D` (enemy, record flags & 0x8000), else job `+0x0E` / `+0x0F`
  through the chain; it is entry n of the A7 archive `0x083D5A1C` (165
  entries, 48 colours = OBJ 96..143). `0x02002FC2 & 3` = 1 or 2 picks
  the archives `0x083D965C` / `0x083DD360` instead (a screen mode, not
  seen in battle).
- Layout: table `0x08417F88`[portrait] = u16 piece count, then 6 bytes
  per piece: y (signed), shape << 6 | 8bpp << 5, x low 8 bits, size << 6 |
  x bit 8, u16 first tile (32-byte units). The pieces fill up to 64 x 88
  pixels up-left of the origin (x -64..0, y -88..0); the screens show
  the portrait mirrored and the Status screen only its lower 56 rows.
- Checked: Marc's portrait from the ROM against the OBJ layer of the HUD
  (2455 pixels) and of Status (2224) - all equal; the numbers the game
  picks for the 5 units of the first battle (`gfx_portrait_ids.lua`) =
  the model's (Marc 56 / 112, Lunais 15 / 30, ...).

## Item icons (Status / equipment lists)

- Icon of item i = entry i of the A7 archive `0x083C83FC` (522 entries,
  128 bytes = 16 x 16, 4bpp tiles in the order top-left, top-right,
  bottom-left, bottom-right); entry 0 = the empty slot.
- Palette: k = byte `0x083C7FE4 + 4 + 2i` >> 4 (`0x080CB99C`), 0..2; the
  palette is `0x0841A100 + 32k` (the screen loads them as BG palettes
  13..15). Colour 0 transparent.
- Checked: Marc's 3 icons + the empty slot decode byte for byte to the
  VRAM of the Status screen; all 522 icons look right (`gfx/icons.png`).

## Map sprites (units on the battle field)

- Sprite set: story character - byte `+0x04` of its character entry;
  other units - job `+0x07` through the parent chain (as the portrait).
  243 sets: table `0x08390E44`[set] -> 84 animations of 12 bytes (u32
  pointer to the animation, 2 x u32 0).
- Animation: u32 frame count, then 20 bytes per frame: u32 tile offset
  from `0x0869B89C` (4bpp tiles, not compressed), u32 layout offset from
  `0x08852E7C`, then 0x108 / 0x110 (timing, not decoded), 0x80000, 0 or 1.
  The standing animation is 0 when facing (wrapper `+0x1F`) is 0 or 3, 1
  when 1 or 2; 2 and 3 are mirrored (seen on screen for facings 1..3;
  facing 0 only by the animation number).
- Layout: the same format as the portrait layout (u16 count, 6-byte
  pieces, 4bpp here), origin at the feet; the frame's tile count is the
  sum of its pieces. Layout 0: 16 x 40 (pieces 8x16 x 4 and 8x8 x 2,
  10 tiles), `0x61E`: 32 x 40 (16x8 x 2, 16x16 x 4, 20 tiles).
- Palette: row r = wrapper `+0x1E` (in the save), the palette is
  `0x08419D60 + 32r` (with `0x02002FC2 & 3` = 1 / 2: `0x0841B340` /
  `0x0841A860`); rows 0..2 and 12 seen. A special case writes row 13
  (`0x08097B7E`, when wrapper object `+0x30` & 0x4000).
- The game streams the current frame (`0x08021200`: tiles at
  `0x0869B89C` + object `+0x20`) into the unit's 16 / 32 OBJ tiles through
  a DMA queue (`0x08000AF0`); the sprite object is wrapper `+0x44`.
- Checked: every unit on screen in both test battles - the frame of its
  object drawn from the ROM against the OBJ layer: 0 different pixels
  for 9 of 12, 9..109 where another unit's sprite overlaps; all sets
  (`gfx/sprites.png`) look right (units, monsters, chests, crystals).

