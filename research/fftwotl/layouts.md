# FFT: The War of the Lions (PSP, ULUS10297) — data table layouts in BOOT.BIN

Source: FFTPatcher (Glain) readers (`PatcherLib/ISOPatching/PspIso.cs`, `Datatypes/**`), re-described.
`RAM = BOOT offset + 0x08803FAC`. Every table below was compared byte-for-byte between `BOOT.BIN` and `ram0.bin`
(battle dump): **all identical** (tables are static, never patched at runtime). Entries were spot-checked with
names from RAM text (see the end). "✓" = sanity-checked against known game values; "unverified" = taken from
FFTPatcher only.

Conventions: little-endian; bit names are listed MSB first (`0x80` … `0x01`). FFTPatcher shows several bits
inverted in its UI; below the **raw** meaning (bit set = …) is given.

## Overview

| Table | RAM | BOOT | Entry | Count | Index |
|---|---|---|---|---|---|
| Ability common | 0x08A754C0 | 0x271514 | 8 | 512 | ability id 0..0x1FF |
| Ability action (attributes) | 0x08A764C0 | 0x272514 | 14 | 0x170 | ability id 0..0x16F |
| Item-ability item | 0x08A778E0 | 0x273934 | 1 | 14 | ability 0x170..0x17D |
| Throw item type | 0x08A778F0 | 0x273944 | 1 | 12 | ability 0x17E..0x189 |
| Jump | 0x08A778FC | 0x273950 | 2 | 12 | ability 0x18A..0x195 |
| Charge | 0x08A77914 | 0x273968 | 2 | 8 | ability 0x196..0x19D |
| Arithmetick | 0x08A77924 | 0x273978 | 1 | 8 | ability 0x19E..0x1A5 |
| Other (R/S/M) id | 0x08A7792C | 0x273980 | 1 | 90 | ability 0x1A6..0x1FF |
| Ability effect id | 0x08B1B760 | 0x3177B4 | 2 | 0x1C6 | ability id 0..0x1C5 |
| Ability animation | 0x08B278F8 | 0x32394C | 3 | 0x1C6 | ability id 0..0x1C5 |
| Items, old (primary) | 0x08B29288 | 0x3252DC | 12 | 256 | item 0..0xFF |
| Weapons, old | 0x08B29E88 | 0x325EDC | 8 | 128 | item 0x00..0x7F |
| Shields, old | 0x08B2A288 | 0x3262DC | 2 | 16 | item 0x80..0x8F |
| Head+Body, old | 0x08B2A2A8 | 0x3262FC | 2 | 64 | item 0x90..0xCF |
| Accessories, old | 0x08B2A328 | 0x32637C | 2 | 32 | item 0xD0..0xEF |
| Chemist items | 0x08B2A368 | 0x3263BC | 3 | 14 | item 0xF0..0xFD |
| Inflict status | 0x08B2A394 | 0x3263E8 | 6 | 128 | inflict id 0..0x7F |
| Item attributes, old | 0x08B2A694 | 0x3266E8 | 25 | 0x50 | attr id 0..0x4F |
| Items, new (primary) | 0x08A5ADAC | 0x256E00 | 12 | 60 | item 0x100..0x13B |
| Weapons, new | 0x08A5B07C | 0x2570D0 | 8 | 32 | item 0x100..0x11F |
| Shields, new | 0x08A5B17C | 0x2571D0 | 2 | 4 | item 0x120..0x123 |
| Head+Body, new | 0x08A5B184 | 0x2571D8 | 2 | 16 | item 0x124..0x133 |
| Accessories, new | 0x08A5B1A4 | 0x2571F8 | 2 | 8 | item 0x134..0x13B |
| Item attributes, new | 0x08A5B1B8 | 0x25720C | 25 | 0x15 | attr id 0x50..0x64 |
| Jobs | 0x08A77988 | 0x2739DC | 49 | 0xA9 | job id 0..0xA8 |
| Skillsets | 0x08A799E4 | 0x275A38 | 25 | 179 | skillset 0..0xAF, then 0xE0..0xE2 |
| Monster skillsets | 0x08A7AB60 | 0x276BB4 | 5 | 48 | skillset 0xB0..0xDF |
| Status attributes | 0x08A7AD50 | 0x276DA4 | 16 | 40 | status bit index 0..39 |
| Poach probabilities | 0x08A7AFD0 | 0x277024 | — | 0x60 B | (not described) |
| Job levels / JP | 0x08A7B030 | 0x277084 | — | 280 B | see below |

## Shared bit sets

**Elements (1 byte):** 0x80 Fire, 0x40 Lightning, 0x20 Ice, 0x10 Wind, 0x08 Earth, 0x04 Water, 0x02 Holy,
0x01 Dark. ✓ (Glacial Gun 0x20, Chaosbringer 0x01, Sage's Ring absorb/strong 0xFF)

**Statuses (5 bytes; status bit index n = byte n/8, mask 0x80 >> n%8; same order as the 40 status attribute
entries and the status-name list):**

| Byte | 0x80 | 0x40 | 0x20 | 0x10 | 0x08 | 0x04 | 0x02 | 0x01 |
|---|---|---|---|---|---|---|---|---|
| 0 | (none/unused) | Crystal | Dead (KO) | Undead | Charging | Jump | Defending | Performing |
| 1 | Petrify (Stone) | Invite (Traitor) | Darkness (Blind) | Confusion | Silence | Blood Suck (Vampire) | (unused, "Cursed") | Treasure |
| 2 | Oil | Float | Reraise | Transparent (Invisible) | Berserk | Chicken | Frog (Toad) | Critical |
| 3 | Poison | Regen | Protect | Shell | Haste | Slow | Stop | Wall |
| 4 | Faith | Innocent (Atheist) | Charm | Sleep | Don't Move (Immobilize) | Don't Act (Disable) | Reflect | Death Sentence (Doom) |

✓ (Lordly Robe permanent `00 00 00 30 00` = Protect+Shell; Haste cancels `.. 04 ..` = Slow.)

**Item / equip type (1 byte, item primary byte 5; also the bit index into job equip flags):**
0 none, 1 Knife, 2 Ninja Blade, 3 Sword, 4 Knight's Sword, 5 Katana, 6 Axe, 7 Rod, 8 Staff, 9 Flail, 10 Gun,
11 Crossbow, 12 Bow, 13 Instrument, 14 Book, 15 Polearm, 16 Pole, 17 Bag, 18 Cloth, 19 Shield, 20 Helmet,
21 Hat, 22 Hair Adornment, 23 Armor, 24 Clothing, 25 Robe, 26 Shoes, 27 Armguard, 28 Ring, 29 Armlet,
30 Cloak, 31 Perfume, 32 Throwing (shuriken), 33 Bomb, 34 Chemist item, 35 Fell Sword, 36 Lip Rouge. ✓

## Abilities

Ability id ranges (type = low nibble of common byte 3; ✓ on every range):

| Ids | Kind | Type | Extra data |
|---|---|---|---|
| 0x000 | empty | 0 | — |
| 0x001..0x16F | normal action | 1 | 14 B action data |
| 0x170..0x17D | Items (Chemist) | 2 | 1 B: item id (0xF0..0xFD) |
| 0x17E..0x189 | Throw | 3 | 1 B: item type thrown (32,1,3,9,5,2,6,15,16,4,14,33) |
| 0x18A..0x195 | Jump | 4 | 2 B: horizontal, vertical (0x18A..0x18F horiz 2,3,4,5,8; 0x190..0x195 vert 2..8) |
| 0x196..0x19D | Charge (Aim) | 5 | 2 B: CT, power bonus (4/1, 5/2, 6/3, 8/4, 10/5, 14/7, 20/10, 35/20) |
| 0x19E..0x1A5 | Arithmetick predicate | 6 | 1 B: mask 0x80 CT, 0x40 Level, 0x20 EXP, 0x10 Height, 0x08 Prime, 0x04 ×5, 0x02 ×4, 0x01 ×3 |
| 0x1A6..0x1C5 | Reaction | 7 | 1 B: "other id" = ability − 0x1A6 |
| 0x1C6..0x1E5 | Support | 8 | same |
| 0x1E6..0x1FD | Movement | 9 | same (0x1FE, 0x1FF blank, type 0) |

Extra-data block layout (offsets from 0x08A754C0): action data at +0x1000 (0x170 × 14 = 0x1420), item +0x2420 (14 B,
+2 pad), throw +0x2430, jump +0x243C, charge +0x2454, arith +0x2464, other +0x246C (90 B); total 0x24C6.

### Ability common data (8 B × 512, RAM 0x08A754C0)

| Off | Size | Field |
|---|---|---|
| 0 | u16 | JP cost |
| 2 | u8 | learn chance (%) |
| 3 | u8 | 0x80 cannot be learned with JP (FFTPatcher: inverted "Learn with JP"), 0x40 display ability name, 0x20 learn on hit, 0x10 unused; low nibble = ability type (table above) |
| 4..6 | 3 B | AI flags (below) |
| 7 | u8 | 0x80 used by AI, 0x40 AI: only hits allies/self, 0x20 AI: only hits enemies, 0x10 ?, 0x08 requires monster skill, 0x04 use weapon range, 0x02 ?, 0x01 evade with motion |

AI flags (brief; names from FFTPatcher): byte 4 — 0x80 affect HP, 0x40 affect MP, 0x20 cancel status, 0x10 add
status, 0x08 affect stats, 0x04 unequip, 0x02 target enemies, 0x01 target allies. Byte 5 — 0x80 target map,
0x40 reflectable, 0x20 undead reverse, 0x10 check CT/target, 0x08 random hits, 0x04 affected by Faith,
0x02 evadeable, 0x01 blocked by Silence (FFTPatcher shows inverted "Ignore Silence"). Byte 6 — 0x80 longbow
attack, 0x40 stop at obstacle, 0x20 linear, 0x10 spear-targetable (inverted "Non Spear-Target"), 0x08 3-dir
melee, 0x04 3-dir ranged, 0x02 magical, 0x01 physical.
✓ Cure `jp 50, 90%, 41, 81 75 00, 80`; Fire AI byte 6 = 0x02, Steal Gil = 0x01.

### Ability action data (14 B × 0x170, RAM 0x08A764C0 = 0x08A754C0 + 0x1000)

| Off | Field |
|---|---|
| 0 | range (horizontal) |
| 1 | effect area (AoE radius; 0 = single) |
| 2 | vertical |
| 3 | flags 1: 0x80 force self-target, 0x40 unused, 0x20 weapon range, 0x10 vertical fixed ("linear range"), 0x08 vertical tolerance, 0x04 weapon strike, 0x02 auto, 0x01 cannot target self |
| 4 | flags 2: 0x80 cannot hit enemies, 0x40 cannot hit allies, 0x20 top-down target, 0x10 does not follow target, 0x08 random fire, 0x04 linear AoE, 0x02 3 directions, 0x01 cannot hit caster |
| 5 | flags 3: 0x80 reflectable, 0x40 usable by Arithmetick, 0x20 blocked by Silence, 0x10 cannot be mimicked, 0x08 "normal attack?", 0x04 persevere (not cancelled), 0x02 show quote, 0x01 animate on miss |
| 6 | flags 4: 0x80 Nature's Wrath (counter flood), 0x40 counter magic, 0x20 direct, 0x10 blade grasp (Shirahadori) applies, 0x08 requires sword, 0x04 requires Materia Blade, 0x02 evadeable, 0x01 no targeting |
| 7 | element (bit set) |
| 8 | formula id |
| 9 | X |
| 10 | Y |
| 11 | inflict status id (index into inflict-status table) |
| 12 | CT (charge ticks) |
| 13 | MP cost |

FFTPatcher inverts (shows as positive) these raw bits: byte 3 0x01; byte 4 0x80, 0x40, 0x10, 0x01; byte 5 0x20, 0x10;
byte 6 0x01. Raw meanings of byte 5 0x20 (set on Cure/Fire/Wall, clear on Steal Gil/Northswain's Strike) and of
byte 6 0x02 (set on Fire = magic evadable in WotL, clear on Cure) are inferred from the dump.
✓ Cure `4 1 1 | 00 00 e2 00 | 00 | f 0x0C X 0 Y 14 | inf 0 | CT 4 | MP 6`; Fire element 0x80;
Steal Gil formula 0x27 X 200; Northswain's Strike flags-4 0x08 (requires sword), inflict 0x77.

### Ability effect / animation (one line)

Effect: u16 per ability 0..0x1C5 at 0x08B1B760 (index into effect/animation list; for 0x170..0x189 the value carries
flag 0x0800, 0xFFFF = none). Animation: 3 B per ability 0..0x1C5 at 0x08B278F8. Not needed for damage math.

## Items

Item ids 0..0x13B (316). Primary data: ids 0..0xFF → old table `0x08B29288 + 12·id`; ids 0x100..0x13B → new table
`0x08A5ADAC + 12·(id − 0x100)`. Old ids 0xFE, 0xFF are dummy (bytes 0xBE8..0xBFF of the old block, FFTPatcher keeps
them raw). New ids 0x116..0x11F, 0x122..0x123, 0x128..0x12B, 0x132..0x133, 0x13A..0x13B are unused dummies.

Category ranges and secondary tables (secondary index = id − first id of its range; this is how FFTPatcher reads
them and it matches the data):

| Category | Old ids | Old secondary | New ids | New secondary |
|---|---|---|---|---|
| Weapon (incl. throwing, bombs) | 0x00..0x7F (0 = empty) | 0x08B29E88, 8 B | 0x100..0x11F | 0x08A5B07C, 8 B |
| Shield | 0x80..0x8F | 0x08B2A288, 2 B | 0x120..0x123 | 0x08A5B17C, 2 B |
| Head + Body | 0x90..0xCF | 0x08B2A2A8, 2 B | 0x124..0x133 | 0x08A5B184, 2 B |
| Accessory | 0xD0..0xEF | 0x08B2A328, 2 B | 0x134..0x13B | 0x08A5B1A4, 2 B |
| Chemist item | 0xF0..0xFD | 0x08B2A368, 3 B | — | — |

Primary byte 4 ("second table id") equals that index for old weapons/shields/armor/accessories, but not for
chemist items (Elixir = 13) and is 0 for all new items — **do not use it as an index**.

### Item primary (12 B)

| Off | Field |
|---|---|
| 0 | palette |
| 1 | graphic (icon) |
| 2 | enemy level (min level for enemies to carry it) |
| 3 | flags: 0x80 weapon, 0x40 shield, 0x20 head, 0x10 body, 0x08 accessory, 0x04 unused, 0x02 "rare" (FFTPatcher name; also set on all chemist items, all new items and dummies — meaning unconfirmed), 0x01 unused |
| 4 | second table id (see above) |
| 5 | item type (enum above) |
| 6 | unknown (0 in all 316) |
| 7 | item attribute id (0 = none) |
| 8 | u16 price |
| 10 | shop availability (0 = never, 1..15 progress steps, 20 = not sold) |
| 11 | unknown (0 in all) |

✓ Dagger `0 1 1 80 01 1 0 00 100 1`; Lordly Robe flags 0x12, attr 0x29; Phoenix Down type 34.

### Weapon secondary (8 B)

| Off | Field |
|---|---|
| 0 | range |
| 1 | attack flags: 0x80 striking, 0x40 lunging, 0x20 direct, 0x10 arc, 0x08 dual-wieldable (Two Swords), 0x04 two-handable (Two Hands), 0x02 throwable, 0x01 forced two hands |
| 2 | formula id |
| 3 | unknown (0xFF in all weapons) |
| 4 | weapon power (WP) |
| 5 | weapon evade % |
| 6 | element |
| 7 | inflict status id / for formula 2 an ability id cast on hit (FFTPatcher) |

✓ Materia Blade `1 8e f1 .. WP10 ev10`; Romandan Pistol flags 0x20 f3; Glacial Gun f4 Ice; Gungnir 0x46 range 2;
Chaosbringer 0x85, Dark, inflict 9.

### Shield (2 B): physical block %, magic block %. ✓ Escutcheon 10/3, Escutcheon (0x8F) 75/50, Onion Shield 80/75.
### Head/Body (2 B): HP bonus, MP bonus. ✓ Leather Helm 10/0, Lordly Robe 100/80, Onion Armor 250/0.
### Accessory (2 B): physical evade %, magic evade %. ✓ cloaks only (Shoulder Cape 10/10, Featherweave 40/30); 0/0 elsewhere.
### Chemist item (3 B): formula id, X, inflict status id. ✓ Potion 0x48/3/0 (×10 = 30 HP), X-Potion X 15, Ether 0x49/2, Elixir 0x4A, Antidote 0x38/0/1, Phoenix Down 0x4B/20/8.

### Item attributes (25 B; id from primary byte 7)

Id 0..0x4F → `0x08B2A694 + 25·id`; id 0x50..0x64 → `0x08A5B1B8 + 25·(id − 0x50)`. (Highest id used = 0x64.)

| Off | Field |
|---|---|
| 0 | PA bonus |
| 1 | MA bonus |
| 2 | Speed bonus |
| 3 | Move bonus |
| 4 | Jump bonus |
| 5..9 | permanent (always-on) statuses |
| 10..14 | status immunity |
| 15..19 | starting statuses |
| 20 | absorb elements |
| 21 | cancel (null) elements |
| 22 | halve elements |
| 23 | weak elements |
| 24 | strengthen elements |

✓ Runeblade MA+2; Battle Boots Move+1; Gaius Caligae Move+2; Moonblade permanent `00 00 00 08 00` = Haste;
Sage's Ring absorb 0xFF, strengthen 0xFF.

### Inflict status (6 B × 128, RAM 0x08B2A394)

| Off | Field |
|---|---|
| 0 | 0x80 all-or-nothing, 0x40 random (one of the set), 0x20 separate (each rolled), 0x10 cancel (remove instead of add), low nibble unused |
| 1..5 | statuses |

✓ id 1 `10 | 00 00 00 80 00` = cancel Poison (Antidote); id 2 cancel Darkness (Eye Drops).

## Jobs (49 B × 0xA9, RAM 0x08A77988)

PSP entry is 49 B (PSX 48): the equip field grew to 5 bytes. Job ids: 0 none, 0x01..0x49 story/special jobs,
0x4A..0x5D generic (Squire..Mime), 0x5E..0x8D monsters (48), 0x8E..0x9F misc, 0xA0 Dark Knight, 0xA1 Onion Knight,
0xA2..0xA8 WotL extras (to Dark Dragon 0xA8).

| Off | Size | Field |
|---|---|---|
| 0 | u8 | skillset id |
| 1 | u16 | innate ability 1 (ability id) |
| 3 | u16 | innate ability 2 |
| 5 | u16 | innate ability 3 |
| 7 | u16 | innate ability 4 |
| 9 | 5 B | equippable item types (below) |
| 14 | u8 | HP growth constant (C) |
| 15 | u8 | HP multiplier (M) |
| 16 | u8 | MP growth |
| 17 | u8 | MP multiplier |
| 18 | u8 | Speed growth |
| 19 | u8 | Speed multiplier |
| 20 | u8 | PA growth |
| 21 | u8 | PA multiplier |
| 22 | u8 | MA growth |
| 23 | u8 | MA multiplier |
| 24 | u8 | Move |
| 25 | u8 | Jump (some large monsters have 0x83/0x84 — bit 0x80 meaning unverified) |
| 26 | u8 | class evade (C-EV %) |
| 27..31 | 5 B | innate (permanent) statuses |
| 32..36 | 5 B | status immunity |
| 37..41 | 5 B | starting statuses |
| 42 | u8 | absorb elements |
| 43 | u8 | cancel elements |
| 44 | u8 | halve elements |
| 45 | u8 | weak elements |
| 46 | u8 | monster portrait |
| 47 | u8 | monster palette |
| 48 | u8 | monster graphic |

Equip flags: item type t ↔ byte 9 + t/8, mask 0x80 >> (t % 8). Byte 9: 0x80 type 0 (bare-hand bit, set on
almost all jobs), Knife, Ninja Blade, Sword, Knight's Sword, Katana, Axe, Rod; byte 10: Staff, Flail, Gun, Crossbow,
Bow, Instrument, Book, Polearm; byte 11: Pole, Bag, Cloth, Shield, Helmet, Hat, Hair Adornment, Armor;
byte 12: Clothing, Robe, Shoes, Armguard, Ring, Armlet, Cloak, Perfume; byte 13: 0x80 Throwing, 0x40 Bomb,
0x20 Chemist item (FFTPatcher "unknown"), 0x10 Fell Sword, 0x08 Lip Rouge, rest unused.
✓ Squire (0x4A): Fundaments, HP 11/100, MP 15/75, SP 100/100, PA 60/90, MA 50/80, Mv 4, Jp 3, C-EV 5;
Chemist innate Throw Items; Monk innate Brawler, C-EV 20; Dark Knight equip byte 13 = 0x10; Onion Knight
`ff ff ff ff 18`, skillset 0; Tiamat (0x8D) skillset 0xDF, weak 0x30, monster `95 02 10`.

## Skillsets (25 B × 179, RAM 0x08A799E4)

Entries 0..175 = skillsets 0x00..0xAF; entries 176..178 = skillsets 0xE0..0xE2 (Darkness, Piracy, Huntcraft).
Skillsets 0xB0..0xDF are monster skillsets (separate table). 0 = none, 1..4 = Attack/Defend/Reequip/Flee,
5 = Fundaments (generic Squire), 0x19 = Mettle (Ramza), 0x18 Mimic (empty).

| Off | Field |
|---|---|
| 0 | high bit (+0x100) for actions 0..7 (0x80 = action 0) |
| 1 | high bit for actions 8..15 |
| 2 | high bit for R/S/M 0..5 (0x80 = slot 0 … 0x04 = slot 5), low 2 bits unused |
| 3..18 | 16 action ability ids (low byte; 0 = empty) |
| 19..24 | 6 reaction/support/movement ability ids (low byte) |

Ability id = byte + 0x100·highbit. ✓ Items `ff fc f8` → Potion..Phoenix Down + Auto-Potion, Throw Items, Safeguard,
Reequip, Treasure Hunter; White Magicks `00 00 c0` → Cure..Holy + Regenerate, Arcane Defense.

**Monster skillsets (5 B × 48, RAM 0x08A7AB60)**, skillset 0xB0 + n: byte 0 high bits (0x80 slot 0, 0x40 slot 1,
0x20 slot 2, 0x10 slot 3 = Beastmaster skill), bytes 1..4 ability low bytes. ✓ 0xB0 Choco Beak, Choco Cure,
—, Choco Esuna (Beastmaster).

## Job levels / JP (280 B, RAM 0x08A7B030)

- 22 × 12 B unlock requirements, for jobs in order Chemist, Knight, Archer, Monk, White Mage, Black Mage, Time Mage,
  Summoner, Thief, Orator, Mystic, Geomancer, Dragoon, Samurai, Ninja, Arithmetician, Bard, Dancer, Mime,
  Dark Knight, Onion Knight, (unused). Each row = 24 nibbles (high nibble first): required level of Squire,
  Chemist, Knight, Archer, Monk, White Mage, Black Mage, Time Mage, Summoner, Thief, Orator, Mystic, Geomancer,
  Dragoon, Samurai, Ninja, Arithmetician, Bard, Dancer, Mime, Dark Knight, Onion Knight, ?, ?.
  ✓ Knight `20 00 …` = Squire 2.
- then 8 × u16 at +264 (0x08A7B138): JP totals 100, 200, 400, 700, 1100, 1600, 2200, 3000. FFTPatcher calls them
  Level1..Level8; values 2..8 match the known JP for job levels 2..8, so entry 0 (100) is likely level-1-related /
  unused (unverified).

## Status attributes (16 B × 40, RAM 0x08A7AD50)

Index = status bit index (order of the 5-byte status table).

| Off | Field |
|---|---|
| 0, 1 | unused (0) |
| 2 | order (processing/display priority) |
| 3 | CT (duration in clock ticks; 0 = permanent until removed) |
| 4 | 0x80 freeze CT, 0x40..0x02 unknown, 0x01 counts as KO |
| 5 | 0x80 cannot react (FFTPatcher inverted "Can React"), 0x40 unused, 0x20 ignore attacks, 0x10 ignored if mounted, 0x08/0x04 unknown, 0x02 cancelled by Immortal, 0x01 lower target priority |
| 6..10 | statuses cancelled when this one is added |
| 11..15 | statuses that block this one ("can't stack on") |

✓ CT: Haste 32, Protect 32, Slow 24, Stop 20, Sleep 60, Doom 3; Haste cancels Slow, Slow cancels Haste;
Stop/Sleep/Disable have byte 5 bit 0x80.

## Text in RAM (names) and counts

Strings use the FFT single-byte encoding (`fftext.py`), separated by 0xFE; entry 0 of each list is listed (often an
empty string). All lists sit in one static text block in BOOT (RAM 0x08A92xxx..0x08A97xxx; copies elsewhere in the
dump also exist).

| List | Entry 0 at (RAM) | Count | Notes |
|---|---|---|---|
| Job names | 0x08A92FF4 | 0xA9 | 0 empty, 1 Squire (Ramza), 0x4A Squire, 0xA0 Dark Knight, 0xA8 Dark Dragon; item list follows directly |
| Item names | 0x08A935FD | 316 (0..0x13B) | 0 empty; dummies named `{92}{94}{b6}{d1}0NNN` |
| Ability names | 0x08A95399 | 512 | 0 empty; 0x1FE..0x200 empty, then help texts |
| Status names | 0x08A96AC8 | 40 | bit order; 0 and 14 are placeholder strings; "KO", "Stone", "Traitor", "Toad", "Atheist", "Doom" |
| Skillset names | 0x08A9775D | 0xE3 (used) | 0 empty, 1 Attack, 5 Fundaments, 0xB0..0xDF empty (monsters), 0xE0 Darkness..0xE2 Huntcraft; the list continues past 0xE2 |

FFTPatcher name lists (`PSPResources.Lists`, from embedded XML: `Abilities.xml`, `Items.xml`, `Jobs.xml`,
`SkillSets.xml`, `StatusNames.xml`): abilities 512, items 316, jobs 0xAA, skillsets 0xE3, statuses 40.
