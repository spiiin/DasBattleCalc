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
