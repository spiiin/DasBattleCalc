# Final Fantasy Tactics (PSX, USA, SCUS-94221): research notes

The disc: `Final Fantasy Tactics (USA).bin` (MODE2/2352, one track): ISO9660
(`psx.py ls / get`): `SCUS_942.21` (the executable, loaded at 0x80010000,
text 0x56800), `BATTLE.BIN` (1.4 MB, the battle code), `MAP/` (MAPnnn.GNS +
resources), `EVENT/`, `EFFECT/`, `WORLD/`, `SOUND/`.

## Reading the main RAM from a state (2026-10-25)

BizHawk 2.11's Nymashock core runs in the waterbox like melonDS: Core.bin.zst
is the host's image. The 2 MB main RAM lies in it in one piece (found by
the executable's code: SCUS_942.21 + 0xE000 = RAM 0x8001E000, a 32-byte
signature no other page holds; first battle: RAM at image offset 117528).
`native/psx_mem.cpp`; addresses 0x00 / 0x80 / 0xA0xxxxxx, mirrored every
2 MB. Writing a state: the RAM is copied back in place (BizHawk loads it;
an HP edit shows in the game). BizHawk's memory domains: MainRAM, GPURAM
(VRAM, 1 MB), SPURAM, BiosROM.

`tests/test_psx_mem.das`.

## Battle records (first battle, Orbonne Monastery)

21 slots x 0x1C0 bytes at 0x801908CC; +0x01 0xFF: empty. In the first
battle: Ramza, Agrias, Gafgarion, Alicia, Lavian (allies), Lezales,
Wezaleff, Viggs, Dish, Fukes (Death Corps), Rad (Ramza's squire).

| offset | field |
|---|---|
| +0x00 | sprite set (Ramza 0x02, generics 0x80 / 0x81) |
| +0x01 | unit id (0xFF empty) |
| +0x03 | job (Squire 0x02 for Ramza; generics 0x4A Squire, 0x4B Chemist, 0x4C Knight, 0x4D Archer) |
| +0x04 | palette (enemies 2) |
| +0x05 | flags: bit 4 enemy (0x94), allies 0x84 / 0xC4 / 0xCC, Rad 0x04 |
| +0x06 | gender: 0x80 male, 0x40 female (0x20 monster - the Guide) |
| +0x09 | high nibble the zodiac: 0 Aries .. 11 Pisces, 12 Serpentarius |
| +0x12 / +0x13 | primary / secondary skill set |
| +0x14 / +0x16 / +0x18 u16 | reaction / support / movement ability (Lezales: 0x1BF Weapon Guard, 0x1E0 Equip Change) |
| +0x1A..+0x20 | equipment: head, body, accessory, right hand, right shield, left hand, left shield (0xFF none) |
| +0x21 / +0x22 | Exp / level (the panel: Lv.09 Exp.08) |
| +0x23 / +0x24 | original / current Brave (56) |
| +0x25 / +0x26 | original / current Faith (63) |
| +0x28 / +0x2A | HP / max HP (113) |
| +0x2C / +0x2E | MP / max MP (24) |
| +0x30..+0x32 | original PA, MA, Speed; +0x36..+0x38 current |
| +0x39 | CT (Lezales 80 = the panel's 080; Ramza 0 while his turn shows 100) |
| +0x3A / +0x3B | Move / Jump |
| +0x47 / +0x48 | x / y on the map; +0x49 bits 0..1 facing (0 +y, 1 -x, 2 -y, 3 +x), bit 7 the upper floor |
| +0x58..+0x5C | statuses, 40 bits in FFT's order (0x80 of byte 0 first; Dead bit 2, Stop bit 30 = 0x02 of byte 3) |
| +0x5D.. | status timers; +0x63 Stop's ticks left |
| +0x12C | name (FFT text), then the job's name at +0x13C |

FFT text: 0..9 = 0x00..0x09, A..Z 0x0A..0x23, a..z 0x24..0x3D, 0xFA space,
0xFE ends a string. The battle text is in RAM: the item names one after
another from item 0 (empty), found by "Dagger", "Mythril Knife" (items 1,
2); Broad Sword 0x13, Escutcheon (shield) 0x80, Leather Helmet 0x90.

## Map

The battle is MAP056 (10 x 14): the cursor from Ramza's tile (6, 3) to +x
shows 11h, 10h, 9.5h, 8h. A map: `MAPnnn.GNS` - 20-byte records (+5 the
resource type: 0x17 texture, 0x2E primary mesh, 0x30 alternative meshes,
0x31 end; +8 u32 sector, +12 u32 size). The mesh's u32 at +0x68 points at
the terrain: u8 width, u8 length, then 8 bytes per tile, 256 tiles per
floor (two floors): +0 bits 0..5 surface, +2 height, +3 bits 0..4 slope
height (the shown height = height + slope / 2), tile = y * width + x.

In RAM the terrain is at 0x8018F8CC, the same bytes but +5 (bit 5 / 6 set
on a connected area around the units: marks of the battle). The header at
0x800F6860: u32 width, u32 length, u32 8, u32 13, ..., +0x18 the terrain
pointer.

## Probing

`plan_probe.lua` (inputs, shots, RAM dumps; BizHawk's pad names: "P1 X"
cross, "P1 ○" circle, "P1 □", "P1 △", "P1 D-Pad Up" ...), `ct_probe.lua`
(CT / HP / tile changes). The earlier "Wait / Status do not work" was
Cross: in the US version Cross cancels and Circle confirms.

The ability names follow the item names in RAM the same way (anchor "Cure",
"Cure 2"; id 1 = Cure; 0x1A6.. reactions, 0x1C6.. supports, 0x1E6..
movement).

## Turn order (seen in the game, slot 2 state)

`ct_probe.lua` from Lavian's turn, the AI playing (`ct2.txt`): every
clock tick adds Speed to CT (Haste x 3/2, Slow / 2 - not seen yet); Stop
freezes CT and its timer (+0x63) counts the ticks down, the tick that ends
it also adds Speed (Viggs: Stop 7 -> his turn at +7 with CT 108). Units
with CT >= 100 act in slot order. The unit taking its turn reads CT 0 and
the pointer 0x8016D004 is at its record; it ends with CT 100 - cost, cost
100 (moved and acted), 80 (one), 60 (neither), at most 60 after. Dead units
(the crystal count) tick and take instant turns. `fft_turns.das`,
`tests/test_fft_turns.das`.

## Attack (the game's forecast)

The battle menu opens on Move; **Circle confirms, Cross cancels** (US).
Act -> Attack -> a tip box (Circle) -> the cursor on the attacker; in the
first battle's camera Down = -x. The forecast: "-042Hp 66%".

Ramza (Mythril Sword, PA 6, Capricorn, male) at (6, 3) -> Lezales (Knight,
Mythril Shield, Iron Sword, Weapon Guard) at (5, 3), `fft_test_ramza2`
(BizHawk's saved state at Ramza's next turn from slot 2):

- damage 42 = PA 6 x WP 7;
- Lezales' facing edited (+0x49): +x (towards Ramza) 66%, +y / -y 74%,
  -x 100%: front = 100 x (1 - C-Ev 10%) x (1 - shield 22%) x (1 - weapon
  5%, only with Weapon Guard) x (1 - accessory 0), floored (66.7 -> 66);
  side - no class evade; back - the accessory only;
- Lezales' zodiac edited (+0x09): Taurus 49, Aries 35, Cancer 21: the
  zodiac changes XA (PA) in integer steps, XA + XA / 4 (good: 7 x 7), XA -
  XA / 4 (bad: 5 x 7), XA / 2 (opposite, both male: 3 x 7).

Tables in RAM (the executable's data):

| address | entry |
|---|---|
| 0x80062EB8 | items, 12 B: +3 flags (0x80 weapon, 0x40 shield, 0x20 head, 0x10 body, 0x08 accessory), +4 the index in the type's table, +5 item type (1 knife, 3 sword, 4 knight sword, ..., 0x0C bow, 0x13 shield), +8 u16 price |
| 0x80063AB8 | weapons, 8 B: range, flags, formula, -, WP, W-Ev, element, status |
| 0x80063EB8 | shields, 2 B: physical, magic evade (Mythril Shield 22, 5) |
| 0x80063ED8 | head / body: HP, MP bonus |
| 0x80063F58 | accessories, 2 B: physical, magic evade (Small Mantle 10, 10) |
| 0x800610CF | jobs, 48 B a job: Move, Jump, C-Ev (Knight 3 3 10, Holy Knight 25) |

Not seen in the game yet (the Battle Mechanics Guide, `fft_attack.das`):
the other weapon types' XA, the critical (5%: XA + rand(0..XA - 1); the
first battle's 60 = (7 + 3) x 6 and 36 = (6 + 3) x 4 fit), Attack UP /
Defense UP / Protect / Berserk, the statuses that cancel evades, the
elements, two swords, the height and the range checks.

## Graphics (from the disc)

Formats as FFTPatcher's sprite editor (github.com/Glain/FFTPatcher,
ShishiSpriteEditor) and GaneshaDx (github.com/Garmichael/GaneshaDx) read
them; checked by rendering (`native/gba_gfx.cpp`, `scripts/games/fft/fft_map.das`).

- **Unit sprites.** BATTLE.BIN +0x2DCD4: 159 x (u32 sector, u32 size) of
  the .SPR sheets (1 RAMUZA, 2 RAMUZA2, ..., 0x60 MINA_M, 0x61 MINA_W,
  0x62 ITEM_M, 0x64 KNIGHT_M, 0x66 YUMI_M: generics 0x60 + 2 (job -
  0x4A) + female); +0x2D748: 4 B per sprite, byte 0 the SHP (0 TYPE1, 1
  TYPE2, 2 CYOKO, 3 MON, 4 OTHER, 5 RUKA, 6 ARUTE, 7 KANZEN). The record's
  +0x00 below 0x80 is the sprite, 0x80 / 0x81 a generic male / female.
  SPR: 16 palettes x 16 BGR555 (the record's +0x04 picks: enemies 2),
  256 x 288 4bpp (low nibble first), then 200 rows packed (nibbles high
  first; 0, n: n zeros; n = 0 / 7 / 8: the length in the next 1 / 2 / 3
  nibbles, low first; then nibble pairs swapped). SHP (BATTLE/TYPE1.SHP):
  u32 the second table, u16 the first frame of the lower half (+256 rows);
  u32 frame offsets from 0x0C (frame 0 at 0), a frame at offset + 0x40A:
  u8 pieces - 1, then 4 B per piece: s8 x, s8 y (from the feet), u16: bits
  0..4 x / 8, 5..9 y / 8 in the sheet, 10..13 the size (8x8 .. 56x56,
  `SPR_SIZES`), 14 / 15 flips; the first piece in front. Standing: frame 2
  (three quarters, facing the viewer's left) and 6 (the back); mirrored for
  the other two.
- **Item icons.** EVENT/ITEM.BIN: 256 x 256 4bpp + 16 palettes; 15 icons
  of 16 x 16 a row from row 2 (the first two: the "Orbonne Monastery"
  title). The item table (0x80062EB8, 12 B): +0 the palette, +1 the icon.
- **The map.** The battle's MAPnnn.GNS is in RAM (first battle at
  0x80124604): matched against the disc's GNS files (`psx_find_map`, 56).
  GNS: 20-byte records, +3 the situation (0 default), +5 the kind (0x17
  texture 256 x 1024 4bpp, 0x2E the primary mesh, 0x30 other states, 0x31
  end), +8 sector, +12 size. The mesh: u32 at +0x40 the polygons, +0x44
  16 palettes, +0x68 the terrain; u16 counts (textured tri, quad,
  untextured tri, quad), s16 x, y, z per corner (x, z 28 a tile, y -12 a
  height step), normals of the textured, texture records (10 / 12 B: u,
  v, palette, -, u, v, page (bits 0..1), -, u, v [, u, v]), 4 B per
  untextured, 2 B of terrain binding per textured (z << 1 | upper, x).
  Quad corners 0 1 / 2 3. MAP056: 63 + 372 textured, 27 + 45 untextured.
  The field draws the polygons back to front (by the diagonal) with the
  units between, textures per (page, palette).

## Reach (the game's marks)

Opening Move or an action's targeting marks the terrain's +5 in RAM: bit
0x20 the tiles to move to, 0x40 the action's range (the bits stay until the
next marking). States saved with the marks shown (`fft_reach_*.State`,
`tests/test_fft_reach.das`): Ramza's Move with Move / Jump edited (5/3,
7/3, 3/8, 6/1), his Attack with a sword, a spear, a bow, a crossbow, a gun
(+0x1D edited) and tiles' heights edited.

- **Move**: breadth first, a step to the 4 sides costs 1, the shown
  heights (with half steps) differ by at most Jump, up or down; living
  enemies block the way, allies and the dead do not; the end must be
  free. Water's depth and terrain kinds (not on this map) not seen.
- **Attack** by the weapon table's +1 flags: 0x80 striking (swords,
  knives, axes, rods, staves, flails, bags; bare hands) the 4 neighbors;
  0x40 lunging (spears, cloth: range 2) straight lines up to the range;
  for both the target may be from 3 below to 2.5 above (14 above 11: no;
  13.5: yes; 8: yes; 7.5: no). 0x10 arc (bows, range 5): 3 tiles to range
  + (attacker - target) / 2 in whole steps, toward zero (target 5 above:
  -2, still 3; 6 above: -3, no). 0x20 direct (guns 8, crossbows 4, harps
  and books 3): 3 tiles to the range, any height (a target 19 above at 3
  tiles: yes). Water: the target's height + its depth (MAP056's (0, 0):
  height 0, depth 4, 9 tiles from Ramza at 11: out; without the depth:
  in). +6 bit 1 (the tower's top): never a target.

## Abilities (the game's forecast)

The tables are War of the Lions' layout (research/fftwotl/layouts.md) at
other addresses: ability common data 8 B x 512 at 0x8005EBF0 (Cure, id 1:
`32 00 5a 41 81 75 00 80`), action data 14 B at +0x1000 (Cure `04 01 01
00 00 e2 00 00 0c 00 0e 00 04 06`), item abilities' items at +0x2420,
Charge (CT, power) at +0x2454; skillsets 25 B at 0x80064A94 (5 Squire
.. 0x18 Mime, 0x19..0x1B Ramza's Guts by chapter, 0x20 Dark Sword, 0x21
Holy Sword); Chemist items (formula, X, inflict) at 0x80063F98; inflict
statuses 6 B at 0x80063FC4. The names follow the item names in RAM (0x42
'+', D1 1D '-', DA 76 an apostrophe).

Learned abilities: the battle record +0x99, 3 B per job from Squire (2 B
actions in skillset order, 0x80 the first; 1 B R/S/M). Ramza's Guts uses
Squire's: 0xC4 = Accumulate, Dash, Wish - his menu. +0x96..+0x98: f0 for
everyone (unlocked jobs?). Special skillsets (Holy Sword ...): all known.

Forecasts (Ramza PA 6 MA 4 Faith 63 at Lezales Faith 51; other skillsets
given to Ramza by RAM edits: +0x13 the secondary, +0x99 + 3 x job FF FF):

| ability | game | model |
|---|---|---|
| Dash (37, Y 4) | 18, 100% | PA' x rand(1..4); the forecast shows one roll (3 here); PA 7: 21, 10: 30, Taurus target: 21 |
| Throw Stone (37, Y 2) | 12, 66% | PA' x rand(1..2), physical evade (roll 2) |
| Head Break (25, Y 45) | 38% | PA + WP + 45 = 58, evades |
| Power Break (2B, X 3, Y 50) | 36% | PA + 50 = 56, evades |
| Magic Break (2C) | 9 MP, 36% | half of max MP rounded up |
| Fire (08, Y 14) | 17, 95% | MA x 14 x Fa x Fa / 10000, magic evade (shield 5%) |
| Cure (0C, Y 14) | +17, 100% | the same, healing |
| Slow (0A, X 180) | 56% | (MA + 180) x Fa x Fa / 10000, magic evade |
| Poison (0A, X 160) | 49% | the same |
| Stasis Sword (2D, Y 2) | 54, 100%, Stop | PA x (WP + 2) |
| Night Sword (30) | 42, 100% | PA x WP |
| Frog (0A), Death (0E) | 0% on everyone | Lezales, Viggs (enemies), Alicia (guest): not the target; Poison (same 0A) 49% - open |

The evades: see "Modifiers and evades" below (the pass share).

## Export (a state with edits)

`export_battle` writes the inspector's stats into the loaded state's RAM
copy (gba_edit_*, the PSX branch of gba_save_state copies the 2 MB back
into the waterbox image): Brave / Faith (original and current), HP / MP
and their maxima, PA / MA / Speed (current; the original moved by the
same amount), CT, Move, Jump. Loaded in BizHawk: the panel shows HP
077/113 once redrawn (moving the cursor), Move 6 gives the model's range.
Not the tile or the facing: the game logic takes them (its Move range
went around Lezales moved to (4, 3)) but his sprite stayed at (5, 3);
the sprite's object with its own position is not found yet (a step of
Ramza changed only the GPU lists, the cursor and the camera).

## More forecasts (2026-10-25)

Ramza's right hand edited (+0x1D), at Lezales (front, 66%): Dagger WP 3 ->
18 = (6 + 6) / 2 x 3; Defender WP 16 -> 48 = (6 x 56 / 100 = 3) x 16;
Battle Axe WP 9 -> 36 = one roll of rand(1..6) (4) x 9. Long Bow at Viggs
(side, no shield: 100%): 24 = 6 x 4; Charge+1 28 = (6 + 1) x 4, Charge+4
40 = (6 + 4) x 4: K is added to XA. Chakra on himself 30 = PA x 5;
Potion 30.

Wish: the caster's max HP / 5 (floored) x 2, any target: 113 -> 44 (not
the 46 of rounding 2/5 up), 200 -> 80, 100 -> 40; Lezales' max HP 200
-> still 44.

The cursor's tile while targeting: 0x800E4E90 (x), 0x800E4E98 (y); in the
first battle's camera Down x - 1, Up x + 1, Left y + 1, Right y - 1.

## Modifiers and evades (the game's forecast)

**Active abilities** are bits in the record, not the ids at +0x14..+0x18:
+0x8B..+0x8E reactions 0x1A6.., +0x8F..+0x92 supports 0x1C6.., +0x93..
movement 0x1E6.. (0x80 first). Lezales: +0x8E 0x40 Weapon Guard, +0x92
0x20 Equip Change (all the enemies); Fukes +0x91 0x08 Throw Item (the
Chemist's innate). Setting Attack UP's id at +0x16 changed nothing; its
bit (+0x90 0x10) gave 56.

Ramza's sword at Lezales (42, 66%), one edit each:

| edit | game | |
|---|---|---|
| Attack UP (Ramza) | 56 | XA 6 x 4 / 3 = 8 |
| Defense UP / Protect (Lezales) | 28 | XA x 2 / 3 |
| Berserk (Ramza) | 63 | XA x 3 / 2 |
| Sleep / Charging (Lezales) | 63, 100% | x 3 / 2, no evades |
| Chicken / Frog (Lezales) | 63 | x 3 / 2 |
| Concentrate (Ramza) | 42, 100% | no evades |
| Darkness (Ramza) / Defending (Lezales) | 42, 40% | evades x 2 |
| no Weapon Guard bit (Lezales) | 70% | no weapon evade |
| bare hands | 18 | PA x (PA x Br / 100) = 6 x 3 |
| bare hands + Martial Arts | 27 | the PA factor 6 -> 9, x 3 (not 3 -> 4, x 6) |

**Hit = base x pass / 100**, where pass is the share past the evades from
100, the slots in the engine's order - accessory, right hand, left hand,
class - each step floored; a hand gives its weapon's evade with Weapon
Guard, else its shield's. Lezales: 100 -> 95 -> 74 -> 66; with Darkness
100 -> 90 -> 50 -> 40. Breaks (PA + WP + Y): Head 58 -> 38, Shield 68 ->
44, Weapon 43 -> 28, Armor 53 -> 34; Power / Magic Break (PA + Y) 56 ->
36. Magic the same with magic evades: Slow 59 x 95 / 100 = 56.

Frog and Death show 0% at Lezales, Viggs and Alicia alike (the first
battle; Ramza casting with Black Magic given by RAM edits), while Poison
and Slow (the same formula 0A) give 49% / 56%. Frog's data `03 00 00 00
00 e2 42 00 0a 78 00 73 05 0c`, Poison's `04 01 02 00 00 e2 42 00 0a a0 00
27 03 06`: they differ in range / area / vertical (0 for Frog and Death,
2 for Poison), X and the inflicted status. Open: the vertical 0, the
statuses Frog / Dead, or the first battle itself (try another battle).

## Charged abilities, Haste, Slow (the game)

Ramza set Fire (CT 4) on Lezales (fft_test_charge.State: Act -> Black
Magic given by edits -> Fire -> Unit), then Wait (Down, Down, Circle, a
facing, Circle). The record: +0x58 0x08 Charging, **+0x15D the charge
counter** (4; 255 none), +0x16F the skillset, +0x170 u16 the ability,
+0x178.. the target. `ct_probe.lua` (now also logging +0x58, +0x5B,
+0x15D): the counter drops by 1 a tick (4 -> 1 in 3 ticks, Ramza's CT
growing as usual: 20 -> 38); at tick 4 it reaches 0 and Fire goes off
(Lezales -17, Ramza -22: he stands in its area) before Alicia's turn,
which came at tick 7 with CT 102. The order: Gafgarion +3 (101), Fire +4,
Alicia and Lavian (dead) +7 (102), Agrias, Lezales, Wezaleff, Dish,
Fukes, Rad +10 (100) - `predict_turns` gives the same.

Haste / Slow (fft_test_haste.State: +0x5B 0x08 / 0x04 with the timers
+0x61 / +0x62 - without a timer the status is gone at the next status
check): Lezales 40 -> 67 in 3 ticks (Speed 6 x 3 / 2 = 9), Agrias 40 ->
49 -> 61 -> 67 -> 70 (6 / 2 = 3). Timers from +0x5D: Poison, Regen,
Protect, Shell, Haste, Slow, Stop (+0x63), ...

## Reactions (the game)

The reaction bits (+0x8B: 0x1A6 A Save .. 0x1C5 Hamedo, 0x80 first) work
when set in RAM, at the target Lezales (Brave 60):

| bits | game | |
|---|---|---|
| Blade Grasp + Weapon Guard | 26% | 66 x (100 - 60) / 100 |
| Blade Grasp | 28% | 70 (no weapon evade) x 40 / 100 |
| Blade Grasp, Brave 90 | 7% | 70 x 10 / 100 |
| Abandon | 44% | each evade x 2: 100 -> 56 -> 44 |
| A Save, Brave 100 | "A Save", PA 7 -> 8 | after the hit |
| Counter, Brave 100 | he struck back, "Missed!" | Ramza had turned to him: front, Squire's class evade 10 -> 90% |

So the attacker faces its target after acting; a counter meets its front.
`fft_reactions.das` (reaction_to) ports War of the Lions' reaction_w with
the PSX ids; the other reactions (Hamedo, Counter Tackle, Dragon Spirit,
HP Restore, Meatbone Slash, Counter Magic, ...) follow the reference and
are not checked.

## Elements (the game)

The record's +0x6D..+0x71: absorb, cancel, half, weak, strengthen (element
bits 0x80 Fire, 0x40 Lightning, 0x20 Ice, 0x10 Wind, 0x08 Earth, 0x04
Water, 0x02 Holy, 0x01 Dark), the battle's copy of the equipment's item
attributes (25 B at 0x800642C4 by the item's +7: PA, MA, Speed, Move,
Jump bonuses, 3 x 5 status bytes - always, immune, at the start - then
the 5 element bytes; Battle Boots 0x2A: Move +1) and the job's. Edited
at Lezales / Ramza:

| | Fire (MA 4 x 14 = 56) | Ice Brand (WP 13: 78) |
|---|---|---|
| absorb | +17 | |
| cancel | 0% | |
| half | 8 | 39 |
| weak | 35 | 156 |
| Ramza's strengthen | 22 (MA 4 -> 5) | 91 (XA 6 -> 7) |

So the element comes after XA x YA (MA x Y) and before Faith (weak Fire:
56 x 2 = 112 -> 35, not 17 x 2 = 34); Strengthen is x 5 / 4 on XA / MA.
The critical is not in the forecast; the model adds XA + rand(0..XA - 1)
to the modified XA (the code's order, research/fftwotl/formulas.md 2.2).

## Facing and the camera (correction)

**The record's facing: 0 -y, 1 -x, 2 +y, 3 +x** - not 0 +y as first
written. A Long Bow shot by Ramza moved to (5, 6), +y of Lezales at (5, 3)
(fft_test_moved.State), his facing edited: 0 -> 100% (his back), 2 -> 66%
(his front), 1 / 3 -> 74%. The earlier checks attacked along x only,
where 0 and 2 are both "side".

**The game's camera sees the mirror image of the field's view** (the
War of the Lions session found it on the same map): in the game +x goes
up-right and +y up-left (the cursor: Down x - 1 is down-left; Ramza's
walk to (5, 6) went up-left), the field draws +x down-right and +y
down-left - a mirror, no rotation of the camera gives it. FieldMap.mirror
(battle_field.das) draws tile (x, y) at (h - 1 - y, w - 1 - x); the
monastery's tower now stands top-left with its door to the right, as in
the game. The units' frames follow the facing as drawn
(field_view_facing).

## Throw and Jump (the game)

**Jump** (the Lancer skillset 0x12 given to Ramza; the command opens the
targeting at once, the Level / Vertical Jump abilities only set its reach:
2 B each at ABILITY_COMMON + 0x243C) at Lezales, never evaded (100%):
Mythril Sword 42 = PA 6 x WP 7; Spear (WP 9) 81 = PA 6 x 3 / 2 x 9; bare
hands 18 = 6 x (6 x 56 / 100); Lezales with Protect 28.

**Throw** (the Ninja skillset 0x14): the list holds the stocked items of
the learned types (each ability's item type: + 0x2430 - Shuriken 0x20,
Knife 1, Sword 3, ...). **The party's stock is a count per item id at
0x800596E0** (Potion 5, Hi-Potion 2, X-Potion, Ether, Hi-Ether, Elixir 1
in the first battle; "Can't throw. None in stock." without). With the
stock edited (fft_test_throw.State): Broad Sword 24, Defender 96,
Shuriken 24, Magic Shuriken 42 = Speed 6 x WP, 66% (evaded as Attack).
The calculator throws the best stocked item of the type.

## The editor (the game)

The inspector edits the job, the skillsets, R/S/M and the equipment
(`recompute_unit`: the game keeps derived fields in the record - the
ability bits +0x8B.. from the innate abilities and the set R/S/M, the
elements +0x6D.. from the job (+41..+44) and the items' attributes, PA /
MA / Speed / Move / Jump and max HP / MP moved by the items' bonuses, a
new job's Move / Jump) and the statuses (+0x58; a timed status new in the
edit gets 32 ticks at +0x5D + its number - 24). The jobs' names: the list
from "Squire", "Chemist" is 0x4A..; the story jobs before it (Ramza's
Squire is job 2, his skillset Guts 26), the monsters after. Skillsets:
"Basic Skill", "Item" are 5, 6.

Exported, each edit alone, Ramza's Attack at Lezales (42, 66%) in the
game: without his Mythril Shield 42 85% (the model: left hand 22% gone);
Ramza with the Attack UP support (id 465, bit +0x90 0x10) 56; with
Defender (a Squire can't wear it - the game uses it anyway) 48; Lezales
as an Archer 42 66% (his sprite stays a Knight); Lezales with Protect 28.

## Explore and the second battle (2026-10-25)

Explore (`fft_explore.das`) runs the same forecasts as the Attack tab; a
forced side turns the target (on an exact diagonal the attacker steps
one tile along x first - a diagonal is always the side). On
`fft_test_ramza2` the experiments give the game's numbers: sides 66 / 74
/ 100%, zodiac 35 / 49 / 21, Dagger 18, Defender 48, Attack UP 56,
Protect 28, Fire (MA 4) 17 at 95%. A weapon or support set by an axis
goes through `recompute_unit` (its bonuses), as in the editor; a job is
read only - changing it would need the job's PA / MA multipliers and the
raw stats, not modelled.

`fft_test_battle2.State` (BizHawk slot 2, 2026-10-25): Gariland, Ramza
Lv1 and Delita with cadets against thieves, Barney's turn. 11 units in
records 0..5 and 16..20; the map, its textures and the sprites read as in
the first battle. Barney acting shows CT 100 in the game; Delita and
Santos (record CT 2) have acted this round.

Forecasts on `fft_test_battle2` (2026-10-26). Gariland is the tutorial
battle: a "Check" hint pops up when targeting starts (○ closes it). The
cursor here: Up x + 1, Down x - 1, Left y + 1. Thieves moved next to
Barney by edits of +0x47 / +0x48 are not targetable (the game finds the
unit on a tile elsewhere) and no enemy is in Barney's reach, so the
forecasts are at Candy (an ally next to him). Barney (Dagger, PA 4, Sp 6,
Scorpio, male) at Candy (Taurus, female: the best pair, XA 5 -> 7):

| edit | game | model |
|---|---|---|
| none (front) | 21 95% | (4 + 6) / 2 = 5 -> 7, x WP 3 |
| Candy facing +y / -x (back / side) | 21 100% | no class evade, no shield |
| Barney's right hand Broad Sword (19) | 24 95% | PA 4 -> 6 x WP 4 |
| bare hands (255) | 12 95% | PA 4 -> 6 x (4 x 55 / 100 = 2) |
| Dash | 18 100% | one roll of PA 6 x rand(1..4) |

The probe's edit values are decimal (`1924E9:1:19`, not `13`).
