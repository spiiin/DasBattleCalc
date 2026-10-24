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
`tests/test_ffta2_battle.das` (Unit Info of Luso and Moricad).

Open:
- facing: object +0x0E taken as FFTA's numbering (0 +y, 1 -x, 2 -y, 3 +x);
  the screen positions agree (+x goes down-right, +y down-left), the facings
  of this battle fit it, but no probe turned a unit yet;
- Klesta (Crushatrice, job 135) gets Move 0 / Jump 0 from the job table:
  bosses / monsters may take Move elsewhere;
- map heights (MapData PANL, or the battle grid in RAM): the field is flat.
