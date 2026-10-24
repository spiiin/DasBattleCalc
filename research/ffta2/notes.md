# FFTA2 (NDS, USA, A6FE): research notes

ROM: `Final Fantasy Tactics A2 - Grimoire of the Rift (USA) (En,Fr,Es).zip`
(one `.nds` inside, 128 MB, header title `FFTA2-NA`, code `A6FE`). Saves:
BizHawk 2.11, melonDS core, `NDS/State/*.MelonDS.QuickSave1.State`; test copy
`ffta2_test_battle1.State` (a battle). Probes: `dump.lua` (memory domains:
Main RAM 4 MB, Shared WRAM, ARM7 WRAM, ITCM, DTCM, ...).

## Reading the main RAM from a state (2026-10-24)

The `.State` is the same zip as for GBA (`Core.bin.zst` = zstd), but the core
runs in BizHawk's waterbox, and `Core.bin` (13.7 MB here) is the waterbox
host state (`waterbox/waterboxhost/src/host.rs`, `memory_block/mod.rs`):

- `"ActivatedWaterboxHost_v1"`, the file system (`"FileSystem"` ...
  `"FileSystemEnd"`), program break, ELF state, then the memory block:
  `"ActivatedMemoryBlock"` at 0xC8 here, a 32-byte hash, u64 start
  (0x36F00000000), u64 size (0x25550000 = 152912 pages of 4 KB), one status
  byte per page, one dirty byte per page, 32 more bytes, then the contents
  of every page that is dirty and not "invisible", in address order.
- Pages not dirty since the core was sealed are not in the state (their
  content is the sealed snapshot, e.g. the ARM9 binary loaded at boot:
  main RAM pages 0..282 here). Invisible pages (big host buffers; here a run
  of 45056 pages at page 42319 and a few small runs) are dirty but not saved.
- Main RAM starts at guest page 143532 (this BizHawk / melonDS build): 417
  pages of a `Main RAM` dump (dump.lua) match the saved pages in that order.
  Robust anchor for a reader: main RAM page 1023 holds the cartridge header
  copy at 0x027FFE00 (+0xE00 in the page); count the dirty pages back from it.

So a calculator can read the battle (dirty pages) from the state; static
game tables must come from the ROM (NitroFS), not from the state.

## Tools

BizHawk memory callbacks work with the melonDS core: `event.on_bus_exec`,
`on_bus_read`, `on_bus_write` on ARM9 addresses; registers `"ARM9 r0"` ..
`"ARM9 r15"` (`hooks_check.lua`). Probes: `dump.lua` (domains, Main RAM),
`hud_writes.lua` (input plan + write log + screenshots), `move_diff.lua`
(Main RAM before / after an input plan).

## Battle units in RAM (first battle, "Defeat Klesta!")

Two structures (found with HP / MP of the bottom panel, a Move diff, and
pointers between them; `move_diff.lua`, `hud_writes.lua`):

**Character records**, 0x11C bytes, an array: the battle's other units first
(0x02129FB4 Klesta, 0x0212A0D0 Sasarr, 0x0212A1EC Kaveisl, 0x0212A308 Cid),
then the clan roster (0x0212B120 Luso, 0x0212B23C Moricad, 0x0212B358 the
viera, three members not in the battle). The clan name ("Gully") and the
leader's name precede the roster (0x0212B0B8, 0x0212B0CC).

| offset | field |
|---|---|
| +0x00 | u32: its battle object, 0 when not in the battle |
| +0x06 / +0x07 | job (sysdata file 1, JD_message 1) / race |
| +0x0C | u16 name: JD_message table 0 index, 0x8000 = a story character (Luso 0x8001, Cid 0x8002, Klesta 0x82A7) |
| +0x0E | low byte: the second job? |
| +0x10 | u16 1001..1045 (an id) |
| +0x1A | u16 level |
| +0x1C | u8 Speed (as shown, before items: Luso 57, Moricad 56) |
| +0x34 / +0x36 | HP / max HP |
| +0x38 / +0x3A | MP / max MP (MP starts low and grows each turn) |
| +0x3C .. +0x42 | u16 raw Attack, Defense, Magick, Resistance |
| +0x44 | u16 x 5?: equipment item ids (Luso Shortsword, Bronze Shield, Plumed Hat, Linen Cuirass) |

Shown stat = raw / 4 (floor) + the items' bonus: Luso Attack 88/4 + 22 = 44,
Defense 84/4 + 30 = 51, Magick 60/4 + 0 = 15, Resistance 72/4 + 9 = 27;
Moricad 65/4 + 18 = 34, 74/4 + 17 = 35, 104/4 + 2 = 28, 106/4 + 32 = 58
(Unit Info screens). Evasion = items (Luso 5: Bronze Shield). A level-1
record holds the job's base values (Soldier 88 84 60 72, HP 90, MP 14).

**Battle objects**, 0x48 bytes, an array from 0x02129AA0 (7 here: Klesta,
Sasarr, Kaveisl, Cid, the viera, Moricad, Luso):

| offset | field |
|---|---|
| +0x04 | u32: its character record |
| +0x08 | u16 HP; +0x0A u16 (MP?) |
| +0x0C / +0x0D | x / y (Luso 8, 7 -> 7, 7 after Move + Wait) |
| +0x0E | facing (changed by Wait) |
| +0x13 | ? (3 / 4) |
| +0x14 | u16 Speed (Luso 57) |
| +0x16 | u16 CT (Luso 144 -> 64 after his turn) |

The position is written at the end of the turn (after Move alone the
object still had the old tile).

## ROM tables (ffta2_rom.py, ffta2_text.py)

- NitroFS: `master/pc.idx`, `master/pc.bin` (ndstool puts them in
  `data/master`), the archive: `system/rom/sysdata_rom.idx` + `sysdata.pak`
  (46 files), `system/rom/JD_message_rom_0.idx` + `JD_message_0.pak`.
- Strings: JD_message tables 0 names (779: Luso, Cid, ..., Moricad 232,
  Klesta 679), 1 jobs (Soldier 1, Black Mage 25 nu mou, White Mage 35 viera,
  Warrior 14, Cockatrice 89, Crushatrice 135), 3 abilities, 11 items.
- sysdata 1: jobs, 72 bytes: +17 Move, +18 Jump, +19/+20 HP base / growth,
  +21/+22 MP, +23/+24 Speed?, +25..+32 Attack, Defense, Magick, Resistance
  (base, growth).
- sysdata 16: equipment, 40 bytes, by item id: +0 u16 type, +19 Attack,
  Defense, Magick, Resistance, Speed, Evasion, Move, Jump (bytes).

## Game data in the ROM

[Rurusachi/ffta2-editor](https://github.com/Rurusachi/ffta2-editor) (Java,
MIT) reads and writes the tables: `arm9.bin` (+ overlays 8, 11), the NitroFS
archive `data/master/pc.bin` / `pc.idx`, idx + pak pairs (`system/rom/
sysdata_rom.idx` + `sysdata.pak`: jobs = file 1, ...; `char/rom/pak/UnitSst.pak`
sprites, `UnitCg.pak`, `menu/face_rom` portraits, `map/rom/MapData` ...),
an LZSS and the FFTA2 charset. Models: JobData, ActiveAbilityData, AbilityData,
EquipmentData, CharacterData, FormationData, MapData, SpriteData.

## In the calculator (2026-10-24)

`scripts/games/ffta2/ffta2_battle.das` reads the battle: the scan of main RAM
for a word p (a record) at address a with `record[+0x00] == a` - the record
points at its object's +0x04 (so the object array starts 4 bytes before the
first match) - filtered by level 1..99, HP 1..999, team byte 0x8x / 0x9x.
Races: menu text table 9, entries 92..98 (Hume, Bangaa, Nu Mou, Viera,
Moogle, Seeq, Gria; record +0x07 = 1..7, monsters 20). Test:
`tests/test_ffta2_battle.das` (Unit Info of Luso and Moricad). Klesta
(Crushatrice, job 135) gets Move 0 / Jump 0 from the job table, and that is
right: the boss stays in place.

Open:

## Fight (2026-10-24)

Reached in game with `plan_probe.lua` (input plan, screenshots, RAM dumps,
write / exec logs with registers): Luso moves to (9, 8) next to Sasarr
(10, 8) - Move, Right, Down, A; Action, Attack, Right, A. The target
screen shows 17 damage, 99 % (`ffta2_test_attack.State`: the target
cursor, a test copy in `NDS/State`).

Code (ARM, `arm.py` - a small disassembler for the dumps): 0x02072FFC
fills the forecast (u16 damage, u16 hit), 0x02070ACC runs the action into
a result array (0x2C per target: +4 hit, +8 damage), and the numbers come
from 0x02070478: arguments by a "%d%d..." format into a **script VM**
(0x0203A788 / 0x0203A838 / 0x0203A9C4; VM at 0x0223B900). The scripts are
whole files of the pc.bin archive (hash 897: damage, 93 KB; 784: hit),
bytecode, not reversed. After the script: damage x [+0x14] (4.12 fixed
point, 1.0 here), at most 999.

So the formula was fitted, not read: `vary_probe.lua` edits Main RAM
(records, the equipment table at 0x022F8C40 = 40 bytes x item, jobs at
0x022F5E40 = 72 x job), confirms the target (A), reads the forecast,
goes back (B). 148 forecasts (`grid1.txt`, `weapons1.txt`, `hit1.txt`,
`hit2.txt`, `elem1.txt`, `elem2.txt`, `min1.txt`; all in
`tests/test_ffta2_attack.das`). In raw units (shown stat = raw / 4):

- base = (2 Atk4 - Def4) / 16, rounded down; Atk4 = raw Attack + 4 x the
  weapon's Attack (no weapon: job +48, Soldier 18); Def4 = target's raw
  Defense + 4 x its equipment's Defense. All 20 weapon kinds alike; the
  jobs and races of either unit, the level do not matter.
- side: the target's facing (object +0x0E: **0 +y, 1 -x, 2 +x, 3 -y** -
  not FFTA's order): side x1.5, back x2, rounded down.
- then the weapon's element (equipment +4: 1 Fire, 2 Wind, 3 Earth,
  4 Water, 5 Ice, 6 Lightning, 7 Holy, 8 Dark) by the target's affinity
  (job +33 + element - 1: 0 weak x1.5, 1 normal, 2 half, 3 immune -> 0,
  4 absorb -> minus, 5 / 6 normal), rounded down.
- at least 1 at the end (not for immune / absorb).
- hit = 100 - target Evasion, 1..99; the side does not change it.

Not checked yet: Attack of non-weapon equipment (none in the tests has
any), statuses, supports and laws, height, criticals, the real hit roll;
reach (weapon range +6, heights).

## Script VM (2026-10-24)

The formulas live in compiled scripts (whole files of pc.bin, loaded to
the heap; per call 0x02070478: 0x0203A788 sets the script, 0x0203A838
pushes the arguments by a "%d%d.." format, 0x0203A9C4 finds the function
by id - a binary tree of 8-byte entries from +0x10: u16 id, u16 code
offset / 16, u16 / u16 links - and runs 0x0203AAB4).

Context: +0x2C4 script, +0x2CC value stack (u32), +0x200 its index, +0x202
frame base, +0x216 expression stack index (8-byte cells at +0: type byte,
value at +4), +0x204 loop counter, +0x208 / +0x20C int / float return,
+0x210 pc, +0x21C the game's native handler (0x02070224 here).

Instruction: i8 opcode, u8 length, operands (0x22 switch: (n - 1) x 8 + 12).
Jump table 0x0203AAE4 (opcode + 1). 0..5 push a literal (the type is the
opcode: 0 int, 1 float, 2..5 variable references: 2 with high half 1 =
frame slot, negative = argument), 6..25 binary ops through ITCM helpers
(0x01FF8678..: 6 + 7 - 8 * 9 / 10 | 11 & 12 ^ 13 << 14 >> 15 float op
(pow?) 16 % 17 == 18 >= 19 > 20 <= 21 < 22 != 24 && 25 ||; 23 !), 26
assign, 27 end of statement, 28 frame += n, 29 / 30 save / restore frame,
31 jz, 32 jnz, 33 jmp, 34 switch, 35..38 loop counter, 39 / 40 call frame
enter / leave, 41 / 42 return value int / float, 43 / 44 push it, 45
return, 46 / 47 to int / float, 48 call (relative), 49 native call #id,
50 store argument, 51 / 52 references, 53 string literal.

Tools: `vmdis.py` (listing), `vmdec.py` (C-like text with gotos:
`python vmdec.py plan_420.bin 0x02269400 1 @67E0`). The decompiled scripts
are not kept in the repository (game code): regenerate from a dump.

Fight (forecast, ability 0 / "Fight" = a4): damage script hash 598, F1 ->
sub_67E0; hit script hash 784, F1; F1 of hash 897 applies the damage (HP,
KO). sub_67E0, physical branch:
- v0 = native_1561(attacker) x 10 (raw Attack), x1.2 / x1.5 / x0.8 / x1.8
  by supports (native_1570: 851, 869 at full HP, 855 ...) and statuses
  (native_1568: 10, 16, 36, 37 ...), at least 1;
- v3 = native_1562(target) x 10 (raw Defense), modifiers alike;
- v1 = (weapon power native_2317, bare hands native_2858) + sub_9B30
  (equipment), x 10; v4 = target's sub_9B30(.., 1) x 10;
- v6 = v0 x 25 / 100 + v1 - (v3 x 25 / 100 + v4) / 2, then x (100 + law
  bonus) / 100 (native_50(369) = the law: +-5..25 %), / 10, / 2;
- then a support (855) x1.5, x2 vs some targets, the side (sub_A2B0:
  front x1, side x1.5, back x2), element (sub_AA10: weak x1.5, half / 2,
  immune 0, absorb), clamp 1..999 (-999..-1 when absorbed).
The same rational as the fitted (2 Atk4 - Def4) / 16, but rounded at each
step: the fitted formula can be 1 off. Next: the natives' meanings
(handler 0x02070224), sub_9B30 / sub_A2B0 / sub_AA10, the hit script.

## Natives and the exact Attack (2026-10-24)

`natives.py` runs the game's native switch (0x020CCEB8, then 0x020CBC98,
0x0203C0E4 for other ranges) for an id and prints its case. The getters:

- unit (character record) 0x020B4E18(unit, k): 5 +0x07 race, 6 +0x06 job,
  8 +0x0A flags (natives 1571 = bit 0 enemy, 1572 = bit 2 guest; neither:
  clan member), 0x1D / 0x1E HP / max HP (+0x34 / +0x36), 0x21..0x24 raw
  Attack, Defense, Magick, Resistance, 0x25 equipment (+0x44), 0x28 +0x4E
  reaction, 0x29 +0x50 support ability. Natives 1539, 1540, 1557, 1558,
  1561..1564, 1566 (item in slot), 1569, 1570.
- status (1568): bit n & 7 of record +0x28 + (n >> 3); names: JD_message
  12 (KO 1, Stone 9, Berserk 10, Blind 13, Shield 15, Focus 16, Evasion 0
  17, Stop 24, Shell 25, Protect 26, Sleep 27, Bulwark 34, Attack up / down
  36 / 37, Defense up / down 40 / 41, Oil 46, Combustion 49, Precision 52,
  Accuracy up 54, Evasion up 57, ...).
- job 0x020B59A8 (k - 0x4C = job byte; story characters read some other
  bytes from their own table): 2843..2850 affinities (job +33..+40), 2851
  hit base (+41, 100), 2858 bare hands (+48), 2860 (+50: 2 - hit from the
  side always).
- item 0x020CB3BC (sysdata 16, 40 bytes): 2304 kind, 2306 element (+4),
  2316 property code (+0x12), 2317..2322 Attack .. Evasion (+0x13..+0x18),
  2330 +0x24 bit 2.
- ability 0x020CB068 (sysdata 4, 0x34 bytes, 822; names JD_message 3):
  2561 element (+2), 2562 (+3), 2564 power (+6), 2579 magick (+0x20 bit 3),
  2594 (bit 18), 2599 by side (bit 28). Attack = ability 799.
- support abilities: 851 Attack up, 852 Defense up, 855 Turbo MP, 856
  Geomancy, 859 Doublehand, 865 Concentration, 869 Unscarred, 876
  Vigilance, 877 Pugilist, 879 Destroyer, 881 Elusion.

Translated into `ffta2_attack.das` (physical Attack; the forecast,
a5 = 1): Attack x10 (Attack up / Pugilist / Destroyer x1.2, Unscarred at
full HP x1.5, Berserk / Attack up x1.2, Attack down x0.8, Focus or
Combustion with a hand cannon x1.8); target Defense x10 (Defense up /
Pugilist / Destroyer x1.2, Unscarred x1.5, Shield x1.2, Protect x1.3,
Defense up x1.2, down x0.8); weapon power (+ other items' Attack, ids >
288; Doublehand x1.2 with one two-handed weapon) x10; armour (all items'
Defense) x10; base = A x 25/100 + P - (D x 25/100 + E) / 2; x (100 +
privilege) / 100 / 10 / 2; side (job +50 == 2, jobs 137 / 138: always
side; Vigilance: front); element (job affinity, the equipment's code
if not normal - the stronger -, Oil + Fire weak, Geomancy one step
weaker), absorb / immune; 1..999; target Bulwark -> 0.
Hit: job +41 - equipment Evasion (+ privilege, Concentration +5, Blind
-30, Accuracy up +30, target Evasion up -20), 1..99; target 0 HP / Stone /
Sleep / Stop / Evasion 0 / Bulwark -> 100; Elusion: 0 beyond reach.

The real hit (a5 = 0, sub_92A0, not in the model yet): a critical with
5 % (privilege 16..20: 6..8 %, target Critical up / Death Strike +3)
doubles the damage, then damage + (rand(3) - 1) x rand(damage / 5 + 1).

Checked: 175 forecasts (`status1.txt`..`status3.txt` added: statuses,
supports, Flame Shield / Blaze Robe absorb, Dragon Mail half, Geomancy,
Vigilance, Elusion, Crushatrice). Berserk on the acting unit breaks the
probe's menu (cases after it are wrong).

## The real attack (2026-10-24)

`exec_probe.lua` executes the Attack many times from the target-cursor
state with chosen generator seeds and reads the target's record HP
(+0x34; the object's HP updates later). Waiting frames does not move
anything: the game's randomness is all in seeded generators.

- Generators: LCG seed = seed x 0x5D588B65 + 0x269EC3, the value is the
  seed's high half (16 bits). The battle's (0x0206F264, the scripts'
  native 4) at [[0x02129A74] + 0xC944]; one per unit (0x0205E950):
  structures of 0xF8 bytes, +0x0C the unit's record, +0x10 seed, +0x14 /
  +0x18 the constants. Fallback 0x0201EB88: the SDK's 64-bit MATH_Rand
  (0x02126004).
- The hit: 0x0206F204(unit, hit%) on the TARGET's generator - >= 100 hits
  and <= 0 misses without a roll, else v % 10000 <= hit x 100. Real hit
  chance = (6 k + min(k, 5536)) / 65536, k = 100 hit + 1: 99 -> 99.1 %,
  80 -> 81.7 %.
- The damage (sub_92A0, on the battle's generator, rolled even on a
  miss): critical if (v % 10000) / 100 < crit (5 % -> 5.34 %): x2; then
  + (rand(3) - 1) x rand(|d| / 5 + 1), rand(n) = (v % (100 n)) / 100;
  |d| / 5 == 0: + rand(3) - 1; clamp 1..999.
- 100 attacks with battle seeds (`exec_seeds1.txt`: 45 x 17, 14..20,
  crits 28..40) and 100 at 80 % with target seeds (`exec_hit80.txt`) are
  predicted exactly (`roll_attack`; `tests/test_ffta2_attack.das`).

## Abilities (2026-10-24)

`vary_probe.lua` cases with `ab=<id>` set r1 of the forecast call
(0x02072FFC) - the game forecasts any ability from the Attack cursor.
`abil1.txt`: 245 abilities, `magic1.txt`: Fire / Cure with modifiers.

An ability (sysdata 4, 0x34 bytes) has up to four effects at +0x10, four
bytes each: type, apply, hit, amount. 0x02070ACC runs each effect: the
type is a function of the condition script (pc.bin hash 332, list 'b';
mode 2), then the hit (784, function = hit byte), the amount (598,
function = amount byte), the application (897, function = apply byte:
1 damage, 17 healing, ...). Attack and the damage spells: 0F 01 01 01;
Cure 21 11 09 01 (+ 25 01 01 13: damage to flying targets); Sidewinder
23 01 01 01 (humanoids) + 27 01 01 02 (monsters: x2).

- Conditions (script 332): F15 any target (not KO / 0 HP; not Invisible
  without Reveal 866), F24 the other team (record +0x0A bit 0), F33 not
  flying, F35 humanoid jobs (< 62, 141..146, > 156), F37 flying, F39
  monsters (62..139). Flying: job +66 bit 3 (native 2875: the job getter
  maps k 0x8B there - not k - 0x4C beyond +0x3E).
- Amounts (598): F1 = sub_67E0 (physical: Attack vs Defense; magick, flag
  bit 3: Magick vs Resistance, the ability's power + the equipment's
  Magick, target Shell x1.3, Magick / Resistance up / down, Turbo MP
  x1.5 + x1.5; not by side: x1.5 always); healing (apply 17): F1 without
  the target's equipment; F2 / F3 / F4 = F1 x2 / x3 / 2. 244 Natural
  Selection is special (a race chosen by the game).
- Hits (784): F1 job +41 - Evasion (magick too: Evasion up lowers Fire
  to 80 %), F2 the same + 20, F3 the same / 2, F9 100 (Elusion aside).
- The real use (sub_92A0): the spread for all, the critical only for
  Attack (no roll otherwise).

236 of 245 forecasts agree (`tests/test_ffta2_abilities.das`); 9 use
conditions or amounts not translated. The first battle's clan members
have no learned abilities (record +0x60.. zero): the Attack tab offers
every ability the model computes.

## The VM in the calculator (2026-10-24)

`scripts/games/ffta2/ffta2_vm.das` runs the game's scripts as they are,
read from the ROM (`nds_arc_entry(hash, char)`: pc.bin entries by name
hash; condition 332 'b', hit 784, amount 598 'c'). Cells: type + 32-bit
value (0 int, 1 float, 2 frame variable, 3 global, 4 / 5 via a pointer:
s16 index, s16 type; 0x36 / 0x37 an address); frame words, arguments
below the frame base (a2 = the first; a native's i-th argument is word
sp - i); assignment converts to the variable's type (0x01FF90F4); binary
operators turn float if either side is (0x01FF8FBC).

`ffta2_forecast.das`: the host's natives read the unit model (handles 1
attacker, 2 target; items as the units carry them, else the ROM) and
vm_forecast runs an ability as 0x02070ACC: per effect the condition,
then the hit and the amount of the first damaging / healing effect. Hit
0 means "no effect" (the game shows 10001). Natives added on the way:
1543 level (unit parameter 0x0E, +0x1A), 1581 flags +0x0A bit 10, 1717
a game flag (0 here). Assumed: 1699 (status immunities) allows all,
native 18 (5, ..) battle flags and game variables but 369 are 0.

All 245 abilities of `abil1.txt` and the 195 edited cases of
`tests/test_ffta2_attack.das` agree (`tests/test_ffta2_vm.das`). The
Attack tab shows the VM's forecast; the translated formula stays as the
step-by-step explanation (a difference is shown).

## Turn order (2026-10-24)

`ct_probe.lua` logs the battle objects' CT (+0x16), HP and tile each
frame while an input plan plays (the clan Waits each turn); `ct1.txt`:
17 turns from the first battle's state.

- 0x020611B8 builds a list of 12-byte entries (0x02060C90: +0 the unit,
  +4 CT, +6 Haste / +7 Slow / +8 Stop - the statuses' durations, +9
  Quicken, +0x0A the unit forced to act) and 0x020610D4 sorts it
  (qsort, comparator 0x02060DC4: +0x0A, then +9 first, then higher CT,
  then the lower unit record address) - the first acts when its CT >=
  100 (0x02060EE4) or a flag is set; otherwise every entry gets a tick
  (0x02061098) and the list is sorted again.
- A tick (0x02060F18): + speed (object parameter 0x33 = +0x14), x2 with
  Haste, / 2 with Slow or status 35 (Speed down); clan members (flags
  bits 0, 2 clear, ...) + 2 / 4 / 6 / 8 / 10 with clan privileges 11..15
  (game variable 0x171 = 369).
- The turn's cost is subtracted by a native of the turn-end script
  (0x020693DC, clamped at 0): seen 50 for Wait, 80 Move + Wait, 70 Act
  without moving, 100 Move + Act.

`scripts/games/ffta2/ffta2_turns.das` predicts the next turns (each
unit ends its turns as its Assumed turn); `tests/test_ffta2_turns.das`:
the 17 recorded turns (order, CT, ticks). Editing a status bit alone
(Haste / Slow in the record) does not change ticks in the game: the
durations count; the model takes the bits.

## Map and reach (2026-10-24)

The battle map is a "PANL" block (the name of its file in the data):
u32 magic, u32 size = 12 + w x h x 12, u8 w, u8 h at +8, then 12-byte
tiles row by row from +0x0C: +0 the height, +4 flags (bit 31: no tile;
0x40 / 0x100 / 0x80: terrain kinds read by 0x020902EC), +8.. ?. The
battle's map: [[0x0212EEA8] + 0xF4] (0x0208B124(map, x, y) returns the
tile). `height_probe.lua` frees the cursor (B), walks it over all tiles
and logs the cursor (u16 x, y at 0x0212F01A) and the height the game
shows ("h 3.0": [0x02129A74] + 0xC938, x 16): `heights1.txt`, all 144
tiles = byte +0. (A first screenshot read 3.5 on a 4 tile: the label was
still moving.)

Reach (the records; the targeting highlight is not in PANL and was not
found yet): ability +0x0B = 7 - the weapon's range (equipment +5: swords
1, spears 2, bows 5..7, guns 7..8, cards 8), 8 - the user only; else
+0x0C tiles (Fire 4, Holy 3, Air Render 3); +0x0E the area's radius.
Distance |dx| + |dy|; heights not checked yet.
