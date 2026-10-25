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
