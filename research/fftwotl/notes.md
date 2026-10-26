# Final Fantasy Tactics: The War of the Lions (PSP, USA, ULUS10297 v1.00)

Notes for the WotL part of the calculator: the save state, the RAM, the tables of BOOT.BIN, how the game is probed.
Table layouts: [layouts.md](layouts.md); formulas: [formulas.md](formulas.md).

## Save state (PPSSPP .ppst)

PPSSPP 1.20.4 (portable: `memstick/PSP/PPSSPP_STATE/ULUS10297_1.00_N.ppst`, slot N + 1 in the menu; a .jpg screenshot
next to it).

- Header 0xB0: `u32 revision (5), u32 compression (0 none, 1 snappy, 2 zstd), u32 stored size, u32 raw size,
  char version[32] ("v1.20.4"), char title[128]`. Then the body (one zstd frame).
- The raw body is PPSSPP's ChunkFile: sections with a 16-byte title. The first after `SaveStart` is `Memory` (at 0x28):
  `u32 version (3), u32 model, u32 marker 0x42, u32 RAM size 0x2000000`, then the 32 MB user RAM (address 0x08000000)
  at raw offset 0x48, then VRAM and the scratchpad.
- Writing (`native/psp_mem.cpp`): the body with the edited RAM as a zstd frame of raw (stored) blocks — every zstd
  decoder reads it, no compressor needed; the header's sizes updated. PPSSPP loads such a file (checked: HP edited in
  the file shows in the game).

## RAM

BOOT.BIN (an ELF, not encrypted; ISO `PSP_GAME/SYSDIR/BOOT.BIN`, LBA 0x1FDB0) is loaded as one segment: file offset
0x54 -> 0x08804000, i.e. **RAM = BOOT.BIN offset + 0x08803FAC** (the same constant as FFTPatcher's PspIso). memsz
0xFE5200: the BSS runs to 0x097E9200. The game id string: 0x08B18354 "ULUS10297".

### Battle units

21 records of **0x1E8 bytes** at **0x092E5CB4** (PSX: 0x1C0 at 0x801908CC). Slot order in the first battle: 0 Ramza,
1..10 the other units on the field, 11..15 units not deployed (HP full, +0x2E = 0), 16..20 empty. The layout is the
PSX "Battle Stats" (ffhacktics wiki) with these differences:

| offset | PSX | |
|---|---|---|
| 0x00..0x19 | same | identity, ENTD slot, job +0x03, palette, team/flags +0x05, gender +0x06, zodiac +0x09 (high nibble), innate abilities u16 x 4 +0x0A, skillsets +0x12 / +0x13, reaction / support / movement u16 +0x14 / +0x16 / +0x18 |
| 0x1A..0x27 | 0x1A..0x20 bytes | equipment **u16** (WotL has items >= 256): head, body, accessory, right weapon, right shield, left weapon, left shield (0xFF = none) |
| 0x28 | 0x21 | experience; 0x29 level; 0x2A / 0x2B Brave (original, current); 0x2C / 0x2D Faith |
| 0x2E | 0x27 | 1 for the units on the field, 0 for the dead / not deployed (meaning unverified) |
| 0x51.. | 0x49.. | 0x51 height bit / facing (0 -y, 1 -x, 2 +y, 3 +x; checked by forecasts, forecast6.txt); 0x52..0x57 equippable kinds; 0x58 innate statuses (5), 0x5D immunities, **0x62 current statuses** (KO units: 0x20 in the first byte), 0x67 status clocks (16), 0x77 elements absorb / cancel / half / weak / strengthen |
| 0x7C.. | 0x72.. (+10) | raw HP / MP / SP / PA / MA (3 bytes each), growth constants |
| 0xA0 | 0x96 | unlocked jobs (3 bytes); **0xA3: learned abilities**, 3 bytes per job (16 action bits, 6 R/S/M bits) for 22 jobs: the base job (Fundaments or a story character's own skillset), Chemist .. Mime (skillsets 6 .. 24), Dark Knight (Darkness), Onion Knight; 0xE5 job levels (nibbles) |
| 0x14E | 0x12C (+0x22) | the name (FFT text, up to 0xFE; Ramza's: the player's name) |
| 0x1A7.. | 0x183.. (+0x24) | 0x1A8 equipped flags (0x08 sword), **0x1AA: it is this unit's turn**, 0x1AB moved, 0x1AC acted |
| 0x30.. | 0x28.. (+8) | HP, max HP, MP, max MP (u16); 0x38.. PA MA SP raw, 0x3B.. equipment bonus, 0x3E.. current; 0x41 CT (Ramza at his turn: 4, the others ready at 104: at the start of a turn the game takes 100 from CT; the screen shows 100); 0x42 Move, 0x43 Jump, 0x44.. WP, W-EV, A-EV, S-EV, C-EV (+0x4B), magic evades; 0x4F X, 0x50 Y, 0x51 height bit / facing |

Example, Ramza at his first turn: Lv 9, Exp 35, Brave 53, Faith 47, HP 111, MP 24, X 6, Y 3, zodiac 0x90 (Capricorn).

### Tables (BOOT.BIN, in RAM)

| RAM | what |
|---|---|
| 0x08A754C0 | ability common data, 8 B x 504 (u16 JP cost, learn chance, flags + type in the low nibble, AI) |
| 0x08A764C0 | ability action data, 14 B by ability id 0..0x16F (range, area, vertical, 4 flag bytes, element, formula, X, Y, inflict status, CT, MP) |
| 0x08B29288 | items 0..255, 12 B (palette, graphic, level, type flags, secondary index, item type, ?, attributes, u16 price, shop) |
| 0x08A5ADAC | items 256..315 (WotL additions), 12 B; accessor 0x08A18600 picks the table by id |
| 0x08B29E88 / 0x08A5B07C | weapon secondary data, 8 B (range, flags, formula, ?, WP, W-EV, element, inflict status) |
| 0x08B2A288 / 0x08A5B17C | shields (physical, magical evade) |
| 0x08B2A2A8 / 0x08A5B184 | helmets / armor (HP, MP) |
| 0x08B2A328 / 0x08A5B1A4 | accessories (physical, magical evade) |
| 0x08B2A394 | inflict status, 6 B |
| 0x08B2A694 / 0x08A5B1B8 | item attributes, 25 B (0..0x4F / 0x50..) |

Text (single-byte FFT encoding: 0x00..0x09 digits, 0x0A.. A..Z, 0x24.. a..z, 0x95 space, 0xFE end of a string,
0xD1 xx two-byte symbols, 0x93 apostrophe): item names from 0x08A935FD (item 0 = empty string), ability names from
0x08A95399 (ability 0 = empty).

Team (+0x05): 0x10 red = enemy, 0x08 controlled by the player; a unit of our side without 0x08 is a guest (Agrias,
Gaffgarion, Alicia, Lavian, Ladd in the first battle: the game shows them as guests).

Checked against the game: the Status screen after an exported edit shows the new Bravery, weapon (WP), secondary
skillset; the HP number of the panel is the game's own copy until it is redrawn (the record holds the new HP).

## Battle map

Tiles of 8 bytes (the GNS terrain format) at **0x092E8530**, index y x width + x; the upper level 0x800 later. The size:
**0x093EBB6C height (rows), 0x093EBB6D width** (the game's code reads both: 0x0887C070..). Tile: +0 surface type (low 6
bits), +2 height, +3 slope height (low 5 bits) and depth (high 3 bits: water), +4 slope type, +6 / +7 flags. Found with
the target cursor (x 0x093E189C, y 0x093E18A4) and the heights the game shows (5,3) 11, (5,2) 11, (5,1) 9, (6,3) 11,
(7,3) 10; the first battle's map is 10 x 14.

## Abilities and supports (checked)

`fcgroups.py` writes Ramza's secondary skillset and learned bits, opens the ability and reads its forecast: damage
(+0x1B6), healing (+0x1B8), MP damage (+0x1BA), hit; `forecast3.txt`. `fcvary.py --supports` sets bits of the record's
ability masks: `forecast4.txt`. Settled:
- evades combine into **one factor truncated at each step** (100 x 78 / 100 x 90 / 100 = 70), then hit x factor / 100
  (Rend Power base 69 -> 48, 87 -> 60, 67 -> 46);
- chance formulas: zodiac scales **both** addends (Rend Power PA 7 + Y 62 = 69; Umbra MA 5 + X 250); Arts of War: the
  chance constant is **Y** (45..55), X the effect (stat -X, X% of MP); base at most 100;
- Rush / Stone: the forecast is PA' x [(Y + 2) / 2] (PA' through Protect and zodiac), Stone evadable, Rush not;
- Cure: MA' x Y x Faith, Shell no effect, an undead target takes the amount as damage; Potion 30, undead: damage;
- **R/S/M abilities in effect are the record's bit masks** +0x95 (reactions, 4 bytes, 0x1A6 + n, 0x80 first), +0x99
  (supports, 4), +0x9D (movement, 3); the ids at +0x14..0x18 alone change nothing. Attack Boost x 4/3, Defense Boost
  x 2/3, Concentration 100%, Brawler (bare) PA x 3/2, **Doublehand doubles the stat** (not WP), Parry adds the
  weapon's evade, Reflexes doubles the evades.

## Reactions (checked)

`fcvary.py --reactions` (`forecast5.txt`): reaction bits of the target's mask (+0x95 .. +0x98, 0x1A6 + n) and the
forecast. **Shirahadori** multiplies the hit by (100 - Brave) / 100 after the evades, from any side, bows too (Brave 58:
70% -> 29%, Brave 100 -> 0, Brave 20 -> 56); **Archer's Bane** the same against a bow; Counter and First Strike do
not change the forecast; Parry from the back adds nothing (only the accessory counts there). A real attack (Lezalas
with Counter, Brave 100; Ramza's class evade 0): Ramza hits for 49 (104 -> 55), the counter takes 48 (111 -> 63) - the
model's Attack of Lezalas (PA 7, zodiac good 8, x WP 6). The rest of the reactions (when they trigger, their Brave
roll) follows formulas.md 5 unchecked.

## Throw and Jump (checked)

`fctj.py` (`forecast7.txt`, `forecast8.txt`): Ramza with the Ninja (skillset 20) / Dragoon (18) set as the secondary,
every ability learned (+0xA3 + job x 3), at Lezalas.

- **The party's stock in battle: a count per item id at 0x092EABA0** (the first battle: Potion 5, Hi-Potion 2, X-Potion,
  Ether, Hi-Ether, Elixir, Antidote 1, Eye Drops 2, ..., Phoenix Down 2 - the PSX game has the same stock). The Throw
  list shows the stocked items of the learned kinds (the ability's item kind: 0x08A778F0 + id - 0x17E); with the stock
  edited to one item the list has one entry.
- **Throw = Speed' x WP** of the item, the target's modifiers and the zodiac only (Speed 6 -> 7): Shuriken 28, Fuma 49,
  Yagyu Darkrood 70, the bombs 56 (Flameburst on a fire-weak target 112, absorbing 0), Mythril Knife 28, Broadsword 28,
  Mythril Sword 49, Spear 63; Protect 20, Speed 10 -> 48, the target charging 44 (100%); evaded as Attack (70%, C-EV
  50: 39%).
- **Jump = PA' x WP** (a polearm: PA x 3 / 2; bare hands PA' x [PA x Brave / 100]), never evaded (100% even with C-EV
  50): Mythril Sword 49, Spear 99 (PA 6 x 3 / 2 = 9, zodiac 11, x 9), bare 21, Gungnir 319; Protect 35, the
  target charging 77, PA 10 -> 84, zodiac neutral 42; Gungnir's lightning on a weak target - still 319: **Jump has no
  element**. The command opens the targeting at once; the learned Jumps (0x18A..0x195) set its reach.

## Status magicks, drains, Gravity, Rend Helm, Aurablast (checked)

`fcgroups.py --status` (`forecast9.txt`), Ramza with the set as the secondary, at Lezalas:

- **Chance (MA + X) x Faith x Faith / 10000, the zodiac on both addends**, then the magic evade: Poison, Stop, Toad,
  Gravity, Quick, Protect, Haste, Empowerment, Invigoration (formulas 0x09 .. 0x12) - all as the model already had
  (Shell / Arcane Defense only for the harmful ones).
- **Percent amounts are rounded up**: Gravity 25% of 134 = 34, Invigoration 34, Empowerment 33% of MP 17 = 6 (the model
  had the drains rounded down).
- **Death** on the undead (Lezalas made undead): heals 134 (max HP) at 40% - the chance without the magic evade, as a
  healing. **Death and Toad on the living Lezalas: 0%** in the game for every MA / Faith / zodiac; Poison and Stop on
  him work: he is **immortal** (team byte bit 0x04, see "The second battle").
- **Rend Helm .. Rend Weapon (0x25): zodiac on the sum (PA + WP + Y)** - (6 + 7 + 45) x 5 / 4 = 72, PA 20: 90, the
  worst zodiac 29 (then the evades: 50, 63, 20%); Rend Power .. MP (0x2B / 0x2C) scale PA and Y apart (7 + 62 = 69).
- **Aurablast (0x31): PA' x [(PA + Y) / 2]** - the modifiers and the zodiac on the first PA only: 7 x 4 = 28, PA 10:
  12 x 6 = 72, the target's Protect: 5 x 4 = 20.

## Reach with the heights (checked)

`fcreach.py`: Ramza (or `--unit`) with a weapon in the right hand, moved to a tile (`--pos`, the record's X / Y: the
game takes the range from them), the Attack targeting open; **a tile in reach has bit 0x40 in its byte 5** (the
tile array). `reach1.txt` (the first battle: 9 weapons from the bridge, sword / Javelin / Longbow from 4 more tiles)
fitted the rules; `reach2.txt` (Gariland, Ganelon: sword, Javelin, Longbow, Romandan Pistol from 4 tiles) was not
used to fit them and matches tile for tile (`tests/test_fftwotl_reach.das`).

- Heights in half h: the tile's height x 2 + its slope (the middle of a slope) + the water's depth x 2 (its surface).
- Tiles with **byte 6 bit 0x02** (the tower of Orbonne) are never selectable.
- Striking weapons (attack flags 0x80; bare hands): their range, **3 h up or down** (2.5 h reached, 4 h not; the guides
  say 2 up / 3 down). Lunging (0x40: polearms, poles, cloths): a straight line of 2, **3.5 h up, 4 h down next to it,
  3 h down two tiles away**.
- Direct (0x20: guns, crossbows, instruments, books) and arcing (0x10: bows): **never closer than 3 tiles** (a harp
  or a book: exactly 3), any height; **bows +1 tile per 2 h** the target is lower ([(attacker - target) / 2] in h).
- The units in battle: every record with an ENTD slot (+0x01 != 0xFF); +0x2E is not "on the field" (Gariland: only
  the unit at its turn has it).

## Abilities' reach (checked)

`fcareach.py` (`reach3.txt`: the first battle, 3 tiles x Fire, Poison, Aurablast, Rend Helm, Rush, Stone, Tailwind,
Chant, Throw, Jump - fitted; `reach4.txt`: Gariland, Ganelon, Fire / Aurablast / Throw / Jump from 3 tiles - held out,
matches tile for tile):

- An ability's range, the **own tile too** unless action flag 1 bit 0x01 (Fire, Poison, Stone light it; Aurablast,
  Chant not). **Flag 1 bit 0x08 (vertical tolerance): the height within the ability's vertical** (Aurablast and Chant:
  3 h); without it any height.
- The tiles the weapons can not select (byte 6 bit 0x02) are lit only for abilities with an area (Fire, Poison - area 1;
  Stone, Tailwind - area 0 not).
- Weapon-range abilities (flag 1 bit 0x20: Rend Helm) and Aim use the weapon's rules. **Throw: Move, any height.**
- **Jump**: the learned horizontal / vertical; it lands on the bottom of water (the depth not added: from the bridge,
  11 h down to the floor - out of the 8 h Jump).

## Reactions triggered (checked, the action performed)

`fcreact.py` (`react1.txt`, `tests/test_fftwotl_react.das`): Ramza attacks Lezalas and the action is **performed**
(the forecast, then "Perform"); Lezalas has one reaction (its mask bit, +0x14), Brave 100, no shield, C-EV 0; both
records read after the animation and compared with the same action without a reaction.

- Attack calls: Counter (48 back), First Strike (strikes first, the attack is cancelled), **Counter Tackle (8 back -
  it answers Attack, not Rush)**, Dragonheart (Reraise), Bravery Boost (+3), Vanish (Invisible), Regenerate (Regen),
  Fury (PA +1), Magick Boost (MA +1), Auto-Potion (+30), Mana Shield (the damage to MP). Left in Critical: Recover HP
  (full), Recover MP (full), Quick (CT 255), Bonecrusher (KO'd Ramza). Not left in Critical: none of those.
- **Arithmeticks' Fire calls no magick reaction** (Faith Boost, Absorb MP, Magick Counter, Reflect: as without).
  Fire cast the usual way charges, so its reactions were not seen.

## Arithmeticks (checked)

`fcarith.py --sweep` (`arith1.txt`: the first battle, Ramza, every algorithm x number with Fire - fitted; `arith2.txt`:
Gariland, Ganelon, EXP and Height - held out, matches), `tests/test_fftwotl_arith.das`. The menu: Act, Arithmeticks,
the algorithm (CT, Level, EXP, Height), the number (prime, multiple of 5 / 4 / 3), the magick (action flag 3 bit 0x40:
45 of them), then the forecast of the first target and "Perform this action?". **The targeted tiles have byte 5 bit
0x80**.

- Every unit whose value fits, allies and the caster too; the KO'd are lit but take nothing.
- **CT as the screen shows it: at most 100** (104 and the active unit's 4 both count as 100).
- **0 is no multiple** (EXP 0 is not hit).
- **Height with half the slope: a half h fits nothing** (units on slopes of 1 are never hit).
- The damage is the magick's own (Fire: MA x Y x Faith x Faith, the zodiac): every target matches the model.

## The second battle: Gariland (checked)

`fcb2.py` (`forecast10.txt`, `tests/test_fftwotl_battle2.das`), the user's save: Ganelon (Chemist, record 16) at his
turn on Rosa (record 17, of the party, the tile next to him - a record moved next to him is not a target: the game
keeps its own map of where the units stand). 25 forecasts, all as the model: Attack (every facing, PA, zodiac,
Protect, C-EV), Fire, Poison, Toad (62%), Death. **Death shows the target's max HP as the damage** (42) and Toad /
Death work on her. **The 0% on Lezalas: team byte (+0x05) bit 0x04 = immortal** (every enemy of the first battle has
0x94, Gariland's 0x90): `fcgroups.py --immortal` (`forecast11.txt`) - with the bit cleared Death 38% (134 damage
shown), Toad 45%; set again, 0%. The party stands in
records 16..20; +0x2E is set only for the unit at its turn.

## Not found yet

- (found, see "Battle map")
## Forecasts of the game (checked)

The forecast of an action is in the **target's record**: +0x1B6 u16 HP damage, +0x1CA kind (0x82 for Attack),
+0x1DC hit % (PSX +0x190 / +0x1B6, i.e. +0x26). The debugger's input drives the menus but not the target cursor or the
facing choice; real key presses (`ppkeys.py`: SendInput to the PPSSPP window, controls.ini keys W/A/S/D, H cross,
Y circle) do. The help box of the targeting mode closes with cross. `fcprobe.py` / `fcvary.py [--magic]`: from the
test state go to the forecast (Ramza -> Lezalas: Attack; Fire with Black Magicks written as his secondary skillset and
every spell learned), then per case: write bytes of the records, circle + cross, read the forecast; a mark in +0x1DC
shows a lost forecast (then PPSSPP restarts). Results: `forecast1.txt` (81), `forecast2.txt` (31); the model matches
all (`tests/test_fftwotl_forecast.das`). PPSSPP's save-state hotkeys did not react to these key presses.

What the forecasts settled (formulas.md's open points):
- the modifier order of formulas.md 2.2 holds (Protect, Charging, Sleep, Chicken/Toad, Berserk before zodiac; zodiac
  good / bad / best / worst, opposite signs by sex);
- **Defending and the attacker's Blindness double the evades** (44% from 70%), they do not halve the hit;
  Charging / Sleep / Stop / Don't Act: 100%; magic evade: doubled by Defending, none on a charging / sleeping target;
- from the side no class evade, from the back only the accessory; facing 1 = -x and 3 = +x are right (0 and 2 are both "side" here; 0 = -y, 2 = +y: forecast6.txt, the attacker moved onto the y axis);
- the game takes the **shield / accessory evades and strengthen from the equipment**, not from the record (+0x48..0x4A,
  +0x7B); class evade (+0x4B), current PA / MA (+0x3E / +0x3F), Brave, Faith, statuses, elements from the record;
- the forecast of a random weapon (axe, flail, bag) uses **[(PA + 2) / 2]**; a bomb in hand: WP x WP, no modifiers;
- a Toad attacks for [PA x Brave / 100]; a nullified element: 0 damage, 0%;
- magic: [MA' x Y x Fa_c x Fa_t / 10000] with Shell, zodiac on MA, elements (weak x2, Oil x2 with Fire, half) before
  Faith; Faith status = 100, Atheist = 0.

## Probing the game

PPSSPP's WebSocket debugger: `RemoteDebuggerOnStartup = True`, `RemoteDebuggerLocal = True` in
`memstick/PSP/SYSTEM/ppsspp.ini` (edit with PPSSPP closed: it writes the file on exit). The port changes per start.

- `pprun.py state.ppst` — kills running PPSSPP instances, starts PPSSPP with `--state=<file>` and the ISO, returns the
  debugger port.
- `ppdbg.py` — client: `Dbg().read(addr, n)`, `.write(addr, bytes)`, `.call('input.buttons.press', button='cross',
  duration=frames)`; `shot(d, png)` — the window's picture by PrintWindow (works while the window is covered).
- `mips.py ADDR [N]` — disassembly of the RAM dump (capstone); `refs()` finds lui/addiu pairs building an address.
- `ppst.py` — decompress a state; `ram0.bin` — the RAM of the test state (not in git).
- Test state: a copy of slot 1, `C:\rom\psx\PPSSPP\memstick\PSP\PPSSPP_STATE\fftwotl_test_battle1.ppst` — the first
  battle (Orbonne Monastery), Ramza's turn, the cursor on the move range.
