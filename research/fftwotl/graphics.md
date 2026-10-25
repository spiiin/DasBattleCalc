# FFT: The War of the Lions (PSP, ULUS10297) — graphics

How to get unit sprites, item icons and the battle map mesh out of the ISO. The scripts are in [gfx/](gfx/)
(Python 3 + Pillow + numpy). They only read the ISO. Their output goes to `gfx/out/`, which is git-ignored.
Sources: FFTPatcher / Shishi (`ext/FFTPatcher`, PSP code paths), checked against the ISO and `ram0.bin`.
Everything marked ✓ was rendered and checked by eye.

| script | what |
|---|---|
| `gfx/fftpack.py` | ISO / fftpack.bin / BOOT.BIN access, file names (`python fftpack.py` prints a few files) |
| `gfx/sprites.py` | sheet lookup, SPR decoding, SHP frames, SEQ animations (`python sprites.py` lists all 170 sheets) |
| `gfx/units.py` | standing frames of the 11 units of `ram0.bin` -> `out/units_standing.png` |
| `gfx/items.py` | all item icons with names -> `out/item_icons.png` |
| `gfx/maps.py N` | GNS index of map N, texture sheet and 4 isometric renders of the mesh -> `out/mapNNN_*.png` |

## 1. fftpack.bin ✓

ISO9660, 2048-byte sectors. `PSP_GAME/USRDIR/fftpack.bin` is at LBA 0x5840 (220,930,048 bytes), and
`PSP_GAME/SYSDIR/BOOT.BIN` is at LBA 0x1FDB0. The BOOT.BIN on the disc is a plain ELF (not encrypted), and
RAM address = BOOT.BIN offset + 0x08803FAC.

- Header: `u32 count` (= 3968 on this disc; FFTPatcher assumes 3970), `u32 0x10`. Then `u32 start[count]` at offset 8:
  **file i (1-based) starts at `start[i-1]`** (offset from the start of fftpack.bin) and ends at `start[i]`
  (the last file ends at the end of fftpack.bin). Files are padded to 2048 bytes. 916 entries have size 0.
- The pack itself has no compression. Some file formats compress internally (the lower part of the sprite sheets).
- Names: `ext/FFTPatcher/PatcherLib/Resources/FFTPackFiles.xml` (`entry` = i). They match the contents, for example
  51 `BATTLE/TYPE1.SHP`, 58 `BATTLE/TYPE1.SEQ`, 33 `EVENT/ITEM.BIN`, 78.. `BATTLE/*.SPR`, 2143.. `MAP/*`.
- The game addresses files by fake PSX "sectors". The table at BOOT.BIN 0x252F34 holds `u32 sector` of fftpack file i
  at `0x252F34 + 4*(i-3)` (i >= 3). The sprite table below uses these sector numbers.

## 2. Unit sprites ✓

### Which sheet

- The unit battle record (0x1E8 B, at 0x092E5CB4) has **+0x181 = sprite sheet id** (PSX Battle Stats +0x15F, shifted
  +0x22 like the name). **+0x04 = palette** (0 for the player and guests, 2 for the enemies in the first battle;
  +0x182 is 0 for every unit and is not the palette). +0x00 is the "base class": 0x80 generic male, 0x81 generic female,
  otherwise the story character's sheet id.
  In the dump: Ramza 0x02 (RAMUZA2, "Ramza ch. 2/3": the prologue happens after chapter 1), Agrias 0x34 (AGURI,
  "Agrias guest"), Gaffgarion 0x17 (H61), Alicia/Lavian 0x65 (KNIGHT_W, shared), Lezalas 0x64 (KNIGHT_M), archers 0x66
  (YUMI_M), Chemist 0x62 (ITEM_M), Ladd 0x60 (MINA_M).
- Sheet id s -> file: BOOT.BIN **0x32481C + 8*s**: `u32 sector, u32 size` (170 entries, s = 0..0xA9). The sector maps
  to an fftpack file through the 0x252F34 table. Only the first `size` bytes of that file belong to the sheet. Several
  ids share a file (for example 0x94 and 0x98 = DORA1). Ids 0, 0x9B..0x9E have no sheet.
- Sheet id s -> shape: BOOT.BIN **0x324284 + 4*s**: `u8 SHP type, u8 SEQ type, u8 flying, u8 height`. The types are
  0 TYPE1, 1 TYPE2, 2 CYOKO, 3 MON, 4 OTHER, 5 RUKA, 6 ARUTE, 7 KANZEN. The SHP/SEQ files are fftpack 51..57 (`TYPEn.SHP`,
  …) and 58..67 (`*.SEQ`). RUKA uses MON.SHP. Humans are TYPE1, except Chemist / Orator / Mime-like jobs, which are TYPE2.
- Names of the ids: `ext/FFTPatcher/PatcherLib.Resources/Resources/PSP/SpriteFiles.xml`. Generic jobs are 0x60..0x85
  (male / female pairs, Squire .. Mime). WotL additions are at 0x9F..0xA9 (Dark Knight, Onion Knight, Balthier, Luso,
  …). `gfx/out/sheets.txt` (from `python sprites.py`) lists every id with its file, types and size.

### SPR (sheet) format

- 0x000: **16 palettes x 16 colours, BGR555** (u16, bits 0-4 R, 5-9 G, 10-14 B). Colour 0 is transparent. Palettes
  0..7 are unit colours (selected by record +0x04), and 8..15 are portrait palettes.
- 0x200: **4bpp pixels, 256 px wide, low nibble = left pixel**. The first 36,864 bytes are rows 0..287: rows 0..255 hold
  the sprite pieces and rows 256..287 the portrait (48x32 at x = 80). The rest of the file is the **compressed lower
  part** (FFTPatcher shows 200 more rows): a nibble stream where a non-zero nibble is a pixel and 0 starts a zero run
  (`0 n` gives n zeros; `0 0 n`; `0 7 lo hi`; `0 8 lo mid hi`), and after decoding, each pair of pixels is swapped
  (`sprites.decompress_lower`). The standing frames only use rows 0..255, so a renderer can skip the decompression.

### SHP (frames)

- `u32` offset of the second frame table (8 or less means none), `u16` first "second half" frame index. The frame
  pointers are `u32` at 0x0C, 0-terminated, and frame 0 is implied at offset 0. Frame data is at pointer + 0x40A.
  A second table, if present, holds pointers at jump + 4, and its frame data is at pointer + jump + 0x402.
- Frame: `u16` (number of pieces - 1), then 4 bytes per piece: `s8 x, s8 y` (offset from the unit's foot point; for
  humans x ≈ -17, y ≈ -35 for a 32x40 piece), and a `u16` with: bits 0-4 sheet x / 8, bits 5-9 sheet y / 8,
  bits 10-13 size index into (8x8, 16x8, 16x16, 16x24, 24x8, 24x16, 24x24, 32x8, 32x16, 32x24, 32x32, 32x40, 48x16, 40x32,
  48x48, 56x56), bit 14 flip x, bit 15 flip y. Pieces are listed front to back, so draw them in reverse order.
- Frames at index >= the "second half" value read from the lower (decompressed) area. With the raw layout above
  (portrait rows kept at 256..287), add **288** to their sheet y. Adding 256 gives garbage, which was checked visually.

### SEQ (animations)

- 4-byte header, then up to 0x100 `u32` offsets at offset 4 (0xFFFFFFFF ends the list). Animation bytes are at
  0x406 + offset. They are pairs `(frame, delay)`. `0xFF op` is an opcode with 1..3 more bytes
  (`sprites.SEQ_JUMPS`, from FFTPatcher).
- Animations 0..5 are single poses from the 8-direction set (SHP frames 1..8: side, 3/4 front, front, mirrored, back, …).
  **The battle idle is the walk-in-place cycle: animation 6 (towards the camera) and 7 (away).** Units on the field are
  drawn mid-step, as in the screenshots.
  - **Standing frame = first frame of SEQ animation 6 (front) / 7 (back)**: TYPE1 and TYPE2 use SHP frames **11 / 16**,
    MON 2 / 4, CYOKO 9 / 14.
  - The front frame faces **screen lower-left** and the back frame faces **screen upper-left**. Mirror both horizontally
    for lower-right / upper-right. Mapping the record's facing (+0x51 low 2 bits: 0 south +y, 1 west, 2 north, 3 east) to
    these four depends on the calculator's camera: if map +x goes to screen lower-right and +y to screen lower-left,
    then 0 = front, 3 = front mirrored, 2 = back mirrored, 1 = back (superseded: see "In the calculator").

✓ `out/units_standing.png`: all 11 units of the dump in 4 poses (front, front mirrored, back, back mirrored) with
record palettes. Ramza (purple, ch. 2 outfit), Agrias (blue skirt, braid), Gaffgarion (brown), Alicia/Lavian (blue
dress, white cape: the same sheet), Lezalas (male knight, enemy palette: red-trimmed cape), the archers (enemy palette:
green trousers, as in `shots/a0.png`), the Chemist (green cap) and Ladd (Squire). All look right.

## 3. Item icons ✓

- **`EVENT/ITEM.BIN` = fftpack file 33** (34,816 B). 0x0000..0x7FFF: a 256x256 4bpp image (low nibble = left pixel).
  **0x8000: palettes of 16 BGR555 colours, 32 B each; 33 are used (0..32)**. The 0x800-byte area has room for 64.
  FFTPatcher only shows 16, but the WotL items use palettes up to 22.
- **Icon of graphic g = item byte 1: 16x16 at x = 16·(g mod 15), y = 32 + 16·(g div 15)**. There are 15 icons per row
  and the last 16 px column is empty. Rows 0..31 hold small glyphs, and g = 0 is the blank slot. Below the icons are
  big digits (not icons). Palette = **item byte 0** (colour 0 transparent). Item tables (12 B): RAM 0x08B29288
  (0..255) and 0x08A5ADAC (256..315), see [layouts.md](layouts.md). All 316 items use g <= 177, so every icon is in
  ITEM.BIN, including the new WotL items.
- ✓ `out/item_icons.png`: 293 items (all with a graphic), icon + id + name. Every icon matches its item (daggers,
  swords, rods, bows, shields, hats, armor, rings, potions, new items such as Chaosbringer, Onion Shield, Tynar Rouge)
  and the palette variants differ as expected. A first attempt with 16 icons per row gave blanks and wrong icons from
  graphic 15 on.

## 4. Battle map (first battle: Orbonne Monastery) ✓ (rough render)

- **Map 56 = MAP056** (name "Orbonne Monastery"; map 62 has the same name but is a different map). Its terrain
  (10 x 14) equals the RAM tile array at 0x092E8530 byte for byte, except run-time flag bits. GNS = fftpack 2995.
  The map's files are fftpack 2976..2994.
- **GNS**: 20-byte records. +2 arrangement, +3 situation (high nibble: time / weather; 0 = default), +5 resource type
  (0x17 texture, 0x2E primary mesh, 0x30 alternate mesh per situation, 0x31 ?, >= 0x80 other / end), +12 resource index
  k -> **fftpack file = first file of MAPnnn + k**. On PSP the old sector field is a constant placeholder
  (`34 33 cc ba ed fe`). MAP056: primary mesh **2994** (38,912 B), default texture **2993** (131,072 B), and textures +
  alternate meshes for situations 0x10..0xC0.
- **Mesh file**: `u32` pointers at 0x40..: 0x40 primary mesh (0xC4), 0x44 texture palettes, 0x68 terrain
  (`u8 x size, u8 z size`, then 8-byte tiles in the format of [notes.md](notes.md) "Battle map"), and others (lights,
  animations; not parsed).
- **Primary mesh**: `u16` counts of textured tris, textured quads, untextured tris, untextured quads (MAP056: 63, 372,
  27, 45 → 870 triangles). Then `s16 x, y, z` per vertex for all four groups in that order (y is negative upwards;
  a tile is 28 units, so x 0..280 / z 0..392 = 10 x 14 tiles). Then `s16` normals of the textured vertices. Then the
  texture info: 10 B per textured tri (`u,v` a; `palette` (low 4 bits); ?; `u,v` b; `page` (bits 0-1); ?; `u,v` c)
  and 12 B per quad (+ `u,v` d; triangles (a,b,c) and (b,d,c)). Then 4 B per untextured polygon and 2 B per textured
  polygon (terrain tile link). The parse ends exactly at the palettes (0x6DF2 / 0x6DF4), which confirms the layout.
- **Texture**: 256 x 1024 4bpp (low nibble first), texel at (u, 256·page + v), palette = one of the 16 BGR555 palettes
  at pointer 0x44. Colour 0 is transparent.
- ✓ `out/map056_yaw45.png` (and yaw 135/225/315): a z-buffered orthographic render of the textured mesh. It shows the
  monastery tower with its green roof and spire, the stone bridge, wooden walkways, grass slopes and water, as in the
  game. The untextured polygons (drawn grey) are the map's vertical outer skirt. `out/map056_tex_pal0.png` is the
  texture sheet. Mirrored relative to the game's camera (see "In the calculator"). Not checked: lights and per-situation
  meshes / palettes; texture animation.

## In the calculator

Done (2026-10-25): the ISO in the ROM field (`psx_open_disc` reads a 2048-byte .iso too), `psp_pack_file(i)` (fftpack
files as disc buffers), `psp_find_map()` (the GNS whose bytes are in RAM: 123 GNS-like files on the disc, exactly one
matches - MAP056 = 2995; the first resource file = GNS - 1 - the largest index k), `psp_unit_sprite` /
`psp_sprite_type` / `psp_item_icon` (native/gba_gfx.cpp; the SHP frame assembly is shared with FFT PSX: `shp_frame`,
lower half at row 288 for WotL), `scripts/games/fftwotl/fftwotl_map.das` (the mesh as FieldPolys, the standing frames).
Checked: `tests/test_fftwotl_graphics.das` and screenshots (the monastery, the units in their palettes, equipment
icons in the slots, the item list and the Items tab).

**The game's view is the mirror image of the field's** (checked against `shots/a0.png`): on the bridge (row y = 3,
one height) the feet go *up* the screen with x (Agrias 5 -> Ramza 6 -> Lezalas 7 -> Alicia 8), Gaffgarion (4, 6) is
up-left: +x goes up-right, +y up-left (the shared field draws +x down-right, +y down-left; no rotation turns one into
the other). `FieldMap.mirror` draws tile (x, y) at (h - 1 - y, w - 1 - x): the tower's door then faces the viewer as in
the game. **Facing**: with that view the sprites match the game when 0 = -y, 1 = -x, 2 = +y, 3 = +x - Ramza and Agrias
(0) look down-right, Lezalas, Alicia and the archer (1) down-left; the party on row 3 faces the archers on row 1, the
archers (2) face the bridge. The forecasts had only fixed 1 = -x (front) and 3 = +x (back): 0 and 2 both gave "side",
so the side rule's y direction changed without a test noticing; a forecast with the attacker on the y axis would
check it (not done).

## Notes for the calculator

- At startup, read the ISO once: BOOT.BIN tables (0x32481C, 0x324284, 0x252F34), TYPE1/TYPE2/MON/CYOKO SHP+SEQ, the
  sheets of the units on the field, ITEM.BIN, and the map files. These are all small (a sheet is ≤ 51 KB).
- A unit sprite = 4 cached images per (sheet id, palette): front, front mirrored, back, back mirrored. The anchor is the
  frame's (0,0) at the tile centre (feet). The frames are about 32x40 px.
- The map number of the current battle is not located in RAM yet. For the first battle it is 56 (found through the
  terrain match).
