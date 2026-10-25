# Final Fantasy Tactics: battle mechanics reference (PSX + War of the Lions)

A working reference for a battle calculator. It is written in my own words from the sources listed at the end
of each section. **PSX** means the original North American PlayStation release, and **WotL** means the PSP port
*The War of the Lions*. Unless a section says otherwise, WotL is assumed to work like PSX: the PSP battle code
is a port of the PSX code. Items marked **[unverified]** come from a single walkthrough-level source or from my
own inference, and need checking in the running game.

Notation:
- `[a/b]` is integer division that truncates toward zero. That is the PSX behaviour, and it equals floor for
  non-negative values.
- `RU{a/b}` = `[(a+b-1)/b]` (round up).
- `rnd(a..b)` is a random integer, inclusive at both ends.
- The C\_ prefix means the caster's stat and T\_ means the target's: C_Fa = caster Faith, T_Fa = target Faith.
- PA = physical attack, MA = magick attack, Sp = Speed, Br = Brave, Fa = Faith, WP = weapon power.
- XA is the stat-like factor that the modifiers act on. YA is the second multiplicand. The engine stores both
  as 16-bit values (`XA` at 0x801938CE and `YA` at 0x801938D0 in PSX BATTLE.BIN) and finally computes
  `damage = XA * YA`.

WotL renames many things. The PSX name is given first and the WotL name after a slash, for example
Attack UP / Attack Boost.

---

## 1. Clock ticks, CT and turn order

### 1.1 One clock tick

One clock tick runs through these phases in order (from the BMG gameflow appendix):

1. **Status check.** Every timed status counter goes down by 1. Statuses whose counter reaches 0 are removed,
   handling units in unit-list order.
2. **S+ (slow-action charge).** Every pending charged ability (a "slow action") has its CTR go down by 1.
3. **SR (slow-action resolution).** This phase happens only if some CTR reached 0. Each slow action whose CTR is
   0 and whose caster can still act resolves, in unit-list order of the casters. The caster must still have the
   MP: otherwise the game shows "No MP" and the action is aborted. If the ability is blocked by Silence and the
   caster is Silenced, it is also aborted. The targets of each action react, in unit-list order.
4. **C+ (CT charge).** Each unit gains `CT += effective Speed`. CT above 100 is kept, not clipped.
5. **CR (turns).** This phase happens only if some unit has CT >= 100. Every unit with CT >= 100 takes a turn,
   in **unit-list order**. The size of a unit's CT does not affect the order. Fast actions resolve right away,
   and their targets react right away.

Consequences:
- An ability with charge time `CTR = n` resolves in the SR phase of the n-th tick after it is chosen. That is
  **before** any unit gains CT or takes a turn in that tick.
- Two slow actions that finish on the same tick resolve in caster unit-list order.

### 1.2 Unit list (tie-break order)

- Enemy units take indices first, starting at 01, in the order the battle's formation data defines them.
- Player units are numbered from 17 by placement square. The front row comes first, and within each row the
  rightmost square comes first.
- Guests and special units come from the battle's ENTD data.
- When several units reach CT >= 100 on the same tick, the lowest index goes first. **[unverified for WotL]**:
  the rule should be the same, but the WotL index assignment has not been checked.

### 1.3 Effective Speed per tick

| State | CT gain per tick |
|---|---|
| normal | `Sp` |
| Haste | `[Sp * 3 / 2]` |
| Slow | `[Sp / 2]` |
| Stop, Sleep, Petrify (Stone) | 0 |
| Dead (KO) | CT still advances. Each time it would reach a turn, the 3-2-1-0 death counter goes down by one instead. |
| Jumping (in the air) | CT keeps advancing, but the unit's timed-status counters pause. |

- Haste and Slow change only the CT gain. They do **not** change Speed-based damage formulas, Jump's charge time,
  or ability charge times.
- Don't Act (Disable) and Don't Move (Immobilize) do not change CT gain.

### 1.4 CT after a turn

| What the unit did | New CT |
|---|---|
| moved and acted | `min(60, CT - 100)` |
| only moved, or only acted | `min(60, CT - 80)` |
| neither (Wait) | `min(60, CT - 60)` |

- A unit with Don't Move is always treated as having moved. A unit with Don't Act is always treated as having
  acted. A unit with both always loses 100.
- **Quick** sets CT to 100 and gives the unit a "quick flag". The unit takes that turn even outside the CR
  phase.
- Return 2 and Persuade / Stall set CT to 0.

### 1.5 Charge time of abilities (the "CT" / speed field)

- Ability data stores a CT value: the number of ticks until the ability resolves. The in-game "Speed" number of
  an ability is `RU{100/CT}`, and the reverse is `CT = RU{100/Speed}`.
- CT = 0 means the ability is instant (a fast action). An ability with CT > 0 puts the caster into **Charging**
  status until it resolves or the caster picks another action on a later turn. Songs and Dances use
  **Performing** instead and repeat every CT ticks.
- Short Charge / Swiftness: charge time becomes `RU{CT/2}`. It does not apply to Jump, Charge / Aim, Sing or
  Dance. Non-charge makes the remaining abilities instant.
- Jump: `CT = [50 / Sp]`, using base Speed. Haste is ignored, and Short Charge has no effect.
- Charge / Aim +K charge times are fixed: +1:4, +2:5, +3:6, +4:8, +5:10, +7:14, +10:20, +20:35. They are the
  same in WotL.
- PSX: if the archer moves, or the weapon is broken while charging, the Charge is aborted. WotL text
  (QuMarsh) says a charging caster can move without losing the charge. That applies to spells in both versions.
  **[unverified]** whether WotL Aim also survives the caster moving.
- **WotL charge times differ from PSX NA for some abilities.** WotL restored the Japanese PSX values, and NA had
  shortened Summons, some Time Magicks and Mystic's Induration. WotL examples from QuMarsh:
  - Meteor: 20 ticks (NA 15)
  - Graviga / Demi 2: 10 (NA 9)
  - Induration / Petrify: 10 (NA 9)
  - Shiva and Ramuh: 7 (NA 4)

  Always read CT from the WotL ability table (BOOT.BIN) and do not copy BMG numbers.

### 1.6 Status durations (in clock ticks; counted in the status-check phase)

| Status | Duration |
|---|---|
| Charm | 32 |
| Don't Act / Disable | 24 |
| Don't Move / Immobilize | 24 |
| Faith | 32 |
| Innocent / Atheist | 32 |
| Haste | 32 |
| Slow | 24 |
| Stop | 20 |
| Protect | 32 |
| Shell | 32 |
| Reflect | 32 |
| Regen | 36 |
| Poison | 36 |
| Sleep | 60 |

- Regen and Poison change HP by `MaxHP/8` at the end of the unit's turn. **[unverified]** the exact rounding.
- Death Sentence / Doom counts 3 of the unit's own turns.
- Defending lasts until the unit's next turn. Transparent / Invisible ends after the unit acts or takes damage.
- **[unverified, WotL]** QuMarsh lists Silence as 36 ticks. The BMG table has no timed Silence (in PSX it lasts
  until cured).
- The initial counters live in a per-status table. PSX reads it in `Status_CT_Setting`
  (0x8005DB70: `lbu 0x80065DE7 + 16*status`).

Sources:
- AeroStar, BMG v6.5, sections 1.1 and A.1–A.4:
  https://gamefaqs.gamespot.com/ps/197339-final-fantasy-tactics/faqs/3876
- FFHacktics, Status_CT_Setting: https://web.archive.org/web/2024/https://ffhacktics.com/wiki/Status_CT_Setting
- QuMarsh, WotL FAQ v7.02, "Turn Order & Charging Abilities" and the job tables:
  https://gamefaqs.gamespot.com/android/705848-final-fantasy-tactics/faqs/50422
- FF Wiki, version differences: https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_version_differences

---

## 2. Physical damage

### 2.1 Base XA / YA by weapon type (the ATTACK command, formula 01)

In the code (`Base Weapon XA`, PSX 0x80185A9C) the attacker's base PA, MA, Sp and Br are loaded, and the item
type picks a branch. `PAxBr = max(1, [PA*Br/100])` (the code floors it at 1).

| Weapon type (WotL name) | XA (the modified factor) | YA | Notes |
|---|---|---|---|
| Bare hands (Fists) | PA | PAxBr | Damage = PA x [PA x Br/100]; Martial Arts / Brawler applies |
| Knife | [(PA+Sp)/2] | WP | |
| Ninja sword / blade | [(PA+Sp)/2] | WP | |
| Sword | PA | WP | |
| Knight sword | PAxBr | WP | |
| Katana | PAxBr | WP | |
| Fell sword (WotL only) | [PA x (100−Fa)/100] **[unverified exact form]** | WP | Low caster Faith is better; target Faith is ignored |
| Rod | PA | WP | |
| Staff | MA | WP | still a physical attack |
| Pole / Stick | MA | WP | physical; range 2, piercing |
| Spear / Polearm | PA | WP | range 2 |
| Axe, Flail, Bag | rnd(1..PA) | WP | code: `[PA*rand15/32768]+1`; WotL preview shows the average |
| Crossbow | PA | WP | range 3–4 |
| Bow / Longbow | [(PA+Sp)/2] | WP | range 3 to 5 + [(height difference)/2], arcing |
| Gun (physical) | WP | WP | ignores evasion; Two Hands / Doublehand does not apply |
| Instrument / Harp | [(PA+MA)/2] | WP | range 3 |
| Dictionary / Book | [(PA+MA)/2] | WP | range 3 |
| Cloth | [(PA+MA)/2] | WP | range 2 |
| Magic gun (Glacial / Blaze / Blaster Gun) | magical, see 4.3 | | |

- **Two Hands / Doublehand**: WP x 2 for the ATTACK command only, with one-handed melee weapons. The BMG says it
  does not apply to Jump, Battle Skill or sword skills. The BMG also says Charge does not get it. WotL text
  (QuMarsh) says Doublehand boosts "regular attacks and Aim" **[unverified which is right for WotL]**.
- **Two Swords / Dual Wield**: two separate hits, each with its own weapon. If the first hit fails, the target
  turns and the second hit is resolved as if it came from the front.
- **Frog attacker**: damage = [PA x Br/100]. Berserk has no effect on it.

### 2.2 Order of modifiers (physical damage: ATTACK, Charge, Battle Skill fallback, punch arts, sword skills)

The BMG procedure ("MOD 2") is below. Every step truncates.

```
XA0 = base XA (+K for Charge / Aim +K: the code adds K to XA itself, after the weapon formula:
       Charge_Calculation XA = XA + chargePower; BMG instead writes (PA+K) inside the formula)
 1. critical hit:            XA = XA + rnd(0..XA-1)            (see 2.3 for where it really happens)
 2. Strengthen(element of weapon / attack) on caster:  XA = [XA*5/4]
 3. Attack UP / Attack Boost (caster):                XA = [XA*4/3]
 4. Martial Arts / Brawler (caster) and (barehanded or attack not weapon-elemental): XA = [XA*3/2]
 5. Berserk (caster):                                  XA = [XA*3/2]
 6. Defense UP / Defense Boost (target):              XA = [XA*2/3]
 7. Protect (target):                                  XA = [XA*2/3]
 8. target Charging (or Performing [unverified]):      XA = [XA*3/2]
 9. target Sleeping:                                   XA = [XA*3/2]
10. target Chicken and/or Frog (Toad) (applied once):  XA = [XA*3/2]
11. zodiac (caster vs target):  good XA+[XA/4], bad XA-[XA/4], best XA+[XA/2], worst XA-[XA/2]
12. damage = XA * YA     (when the formula uses the same stat twice, only one copy is modified)
13. target Weak to element:    damage = damage*2
    (WotL: Oil + Fire also doubles; in PSX Oil does nothing because of a bug)
14. target Half element:       damage = [damage/2]
15. target Absorb element:     damage = -damage (healing)
    target Null / Cancel element: the attack misses (0%)
16. cap: 999 per hit (the same cap applies to healing)
```

- In the code, the elemental step runs after `XA*YA`. FFHacktics notes that Oil was meant to change XA or YA,
  but by then they are no longer used. That is why Oil did nothing in PSX. WotL fixed Oil ("fire damage x2",
  according to the version-differences page).
- **Code order versus the BMG.** In PSX BATTLE.BIN, `Damage_Calculation` (0x801886A4) calls the routines in
  this order:
  1. Physical XA modifiers (supports, statuses, compatibility)
  2. **then** Critical_Hit_Calculation
  3. then XA*YA

  So the critical bonus is applied to the **already modified** XA, not before the modifiers as BMG step 1 says.
  For an implementation, follow the code: steps 2–11 first, then the critical bonus, then XA*YA. Verify the
  difference in game. **[open]** The exact order of steps 2–11 inside the support/status routine is taken from
  the BMG; the disassembly page for that routine was not archived.
- Jump uses different modifiers (from the BMG):
  - Defense UP, Protect, Charging, Sleep and Chicken/Frog, then a spear bonus of [PA x 3/2], then zodiac.
  - **No** Attack UP and **no** Martial Arts. It cannot be evaded and is non-elemental.
  - Armed: `[PA']*WP`. Barehanded: `PA' * [PA*Br/100]`.
  - This is formula 0x64.
- Throw (Ninja): `damage = Sp' * WP of the thrown item`. It takes the Defense UP, Protect, Charging, Sleep,
  Chicken/Frog and zodiac modifiers. Attack UP and Strengthen do not apply. It uses the thrown weapon's element
  for weak / half / absorb, and can be evaded. This is formula 0x63.
- Physical guns: the modified factor is WP, so `damage = WP' * WP`.

### 2.3 Critical hits

- Chance: the code (PSX 0x801864F8) calls the RNG with arguments (100, 4). FFHacktics describes it as a roll of
  about 4%, while the BMG says about 5%. **[open: 4% or 5%]**
- Bonus: `XA = XA + [XA * r / 32768]` with `r = rand(0..32767)`, which gives a value between 100% and just under
  200% of XA.
- After a critical, the knockback check runs (target pushed one square if the square behind is free). The BMG
  says knockback happens about 50% of the time. **[open]** the exact knockback chance.
- Which attacks can crit:
  - ATTACK, Charge, and formulas 0x31 / 0x32 (Spin Fist / Cyclone, Wave Fist / Aurablast, Earth Slash /
    Shockwave, Repeating Fist / Pummel).
  - Weapon formulas 03, 05 and 06 and sword skills go through the same `Damage_Calculation` routine, so they
    can crit as well.
  - Magic guns cannot crit.

### 2.4 Zodiac compatibility

Compatibility of the caster's sign with the target's sign:

| Relation | Signs | Result |
|---|---|---|
| Same sign | — | neutral |
| 4 apart (trine) | e.g. Aries–Leo, Aries–Sagittarius | Good |
| 3 apart (square) | e.g. Aries–Cancer, Aries–Capricorn | Bad |
| 6 apart (opposite) | Ar–Li, Ta–Sc, Ge–Sg, Cn–Cp, Le–Aq, Vi–Pi | opposite sex: Best; same sex: Worst; either unit a monster: Bad |
| Serpentarius vs anything | — | neutral |
| anything else | — | neutral |

- Each Lucavi has a sex byte. Queklain, Zalera and Hashmalum are male; Velius, Adramelk, Altima and Elidibs
  count as monsters.
- Damage: the XA factor is multiplied by 1 + 1/4 (Good), 1 − 1/4 (Bad), 1 + 1/2 (Best) or 1 − 1/2 (Worst),
  truncating at each step.
- Success-rate formulas (BMG): **both** addends are scaled, and each is truncated separately. For example, with
  Good compatibility `MA + K` becomes `MA + [MA/4] + K + [K/4]`. Zodiac never changes evasion.
  **[open]** The PSX code applies compatibility to XA before `XA + YA` is formed. Whether YA (the constant) is
  also scaled, as the BMG claims, needs a test.
- Zodiac does not apply to:
  - damage based on current or max HP/MP (Demi / Gravity, Blade Beam, and so on)
  - Murasame
  - items (potions)
  - Wish / Chant
- WotL uses the same chart. *The Ivalice Chronicles* (2025) changed same-sex opposite signs from Worst to Best;
  WotL did not.

### 2.5 Other notes

- Undead targets: healing (Cure, potions, Raise) becomes damage of the same size. Drain attacks reverse.
  Phoenix Down kills an undead target.
- Critical status: `CurHP < RU{MaxHP/5}`.
- Weapon-elemental attacks (ATTACK, Charge, Battle Skill / Arts of War, sword skills, Dark / Fell Sword) take
  the element of the weapon in the top hand.
- Weapon "add status" procs: 25% for "Separate" statuses. Weapon spell procs (Ice Brand and similar): about 25%.

Sources:
- BMG sections 1.3, 1.5, 1.6, 1.7, 2.1–2.4, 3.2 and 4.2:
  https://gamefaqs.gamespot.com/ps/197339-final-fantasy-tactics/faqs/3876
- FFHacktics:
  - Damage_Calculation, Critical_Hit_Calculation, XA_*_YA_Calculation, Elemental_XA_*_YA, Charge_Calculation
    and Base_Weapon_XA_Rewrite (Wayback copies of `https://ffhacktics.com/wiki/<page>`):
    https://web.archive.org/web/2024/https://ffhacktics.com/wiki/Damage_Calculation
- QuMarsh WotL FAQ, weapon list (Fell Sword, Doublehand, preview):
  https://gamefaqs.gamespot.com/android/705848-final-fantasy-tactics/faqs/50422
- FF Wiki, version differences (Oil fix, IVC zodiac change):
  https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_version_differences

---

## 3. Hit chance and evasion

### 3.1 Physical evasion

Evade sources on the target:
- **C-EV**: class evade, from the job.
- **S-EV**: shield, separately for each hand.
- **A-EV**: accessory (mantle).
- **W-EV**: weapon parry. It counts only if the target has **Weapon Guard / Parry** set.

Which sources apply depends on where the attacker stands relative to the target's facing:

| Attack from | Evades used |
|---|---|
| front | C-EV, S-EV (both hands), W-EV, A-EV |
| side | S-EV, W-EV, A-EV (no C-EV) |
| back | A-EV only |

- Direction: compare how far the attacker is forward, sideways and behind relative to the target's facing. The
  largest of the three wins, and ties go to the more frontal direction (front over side over back). Height
  difference does not matter.
- `hit% = [base * (100-C)(100-S_R)(100-S_L)(100-W)(100-A) / 100^k]`, where only the evades that apply are
  multiplied in and k is their number.

The engine (PSX `Calculate_Final_Hit_%`, 0x80185814) works like this:
- It keeps four evade slots: accessory, right hand, left hand, class. A hand slot holds the weapon's parry rate
  if that hand has a weapon and Weapon Guard applies, and otherwise the shield's evade.
- If any single slot is >= the base hit%, the attack is shown and treated as 0% (an automatic miss).
- The displayed hit% is the truncated product.
- Resolution rolls each slot **separately**, in the order accessory, RH, LH, class. The first slot that
  succeeds decides the miss message:
  - class evade → "Missed!"
  - shield, weapon or accessory → "Guarded", with the shield or weapon shown
- The overall chance is the same as the product formula.

Modifiers:
- **Evades become 0** if the target is Charging, Performing, Sleep, Stop, Don't Act (Disable) or Confused.
  The Confused case is from the PSX code (`Evasion_Changes_due_to_Statuses`, 0x801853F4). The BMG instead says
  a *Confused attacker* doubles the target's evades. **[open]**
- Vampire / Blood Suck: the BMG says that unit's evades are 0. Petrified and Dead units are not targeted.
- **Defending**: the code halves the base hit% (`hit = [hit/2]`). The BMG describes the same thing as "evades
  doubled".
- **Abandon / Reflexes**: each evade is doubled, so a factor (1 − e) becomes (1 − 2e).
- **Blind / Darkness on the attacker**: the target's evades are doubled. These doublings stack: Abandon +
  Defending + Blind = x8, according to the BMG.
- **Concentrate / Concentration** (attacker): ignores C-EV, S-EV, A-EV and W-EV. Blade Grasp / Shirahadori and
  Arrow Guard / Archer's Bane still apply, and so does magic evasion.
- **Transparent / Invisible** attacker: none of its attacks, physical or magical, can be evaded.
- Attacks that are never evaded:
  - physical guns and magic guns
  - Jump
  - sword skills (Holy Sword, Dark Sword / Fell Sword, Mighty Sword)
  - Draw Out / Iaido
  - Steal Exp, Talk Skill / Speechcraft, Secret Fist / Doom Fist, Stigma Magic / Purification, Earth Slash /
    Shockwave
  - Squire Dash / Rush (EVD −). Throw Stone / Stone is evadable.
- Battle Skill / Arts of War is still evaded when fired from a gun.
- **Blade Grasp / Shirahadori** (reaction, PSX): an extra factor `(100 − Br)/100` on the base hit chance. It
  works against "countergrasp" physical attacks: ATTACK, Charge, Battle Skill, Steal equipment, Throw, Jump and
  most monster melee attacks. It blocks at most one hit of a Dual Wield attack, and it does work against magic
  guns. Counter / First Strike blows are not blocked by it. WotL text says Shirahadori also blocks bows,
  crossbows and guns. **[unverified]** whether it is still a Brave-based extra factor in WotL or a separate roll.
- **Arrow Guard / Archer's Bane**: the same, for bow and crossbow attacks.
- **Finger Guard / Earplug** **[WotL name unverified]**: Talk Skill base becomes `base − Br`.

### 3.2 Magical evasion

- `hit% = [base * (100 − M.SEv)(100 − M.AEv) / 10000]` from any direction. There is no magical class evade:
  every job's M-C-EV is 0.
- It applies only to abilities flagged *evadable*. These are mostly harmful magicks: the elemental Black
  Magicks, Bio, Flare, and harmful status spells.
- The following ignore magical evasion: Cure, Raise, buffs (Protect, Shell, Haste, Regen, Reflect, Float, Wall,
  Reraise, Esuna, Quick), Holy, summons, Death, Demi / Gravity, Meteor, Iaido, Geomancy, Ultima.
- From the BMG table: Fire/Bolt/Ice 1–4, Bio and Flare are evadable; Holy and Meteor are not.
- Evadable status spells: Poison, Frog / Toad, Death, Slow, Stop, Don't Move / Immobilize, Petrify, Silence
  Song, Blind Rage, Confusion Song, Blind / Umbra, Zombie, Sleep / Repose, Paralyze / Hesitation, Foxbird /
  Trepidation, Demi.
- Formula 0x0A has a quirk (FFHacktics): it checks evasion and blocking even when the evadable flag is clear.
  Any ability on 0x0A can therefore be evaded.
- In code: `Magical Evade Calculation` (0x801885B8) runs first. Then the damage or hit chance is computed.

### 3.3 Base hit chance

- ATTACK and other weapon attacks: base 100%, then evasion.
- Status chance from a weapon's add-status: 25% for "Separate" statuses, after the hit itself lands.
- Battle Skill / Arts of War, Steal and similar: their own success formula, then evasion (see section 4).
- Talk Skill fails on Sleeping targets. It also fails on monsters unless the caster has Monster Talk.

Sources:
- BMG sections 1.4, 4.1, 4.2, 5.x and 6.12:
  https://gamefaqs.gamespot.com/ps/197339-final-fantasy-tactics/faqs/3876
- FFHacktics Calculate_Final_Hit_%: https://web.archive.org/web/2024/https://ffhacktics.com/wiki/Calculate_Final_Hit_%25
- FFHacktics Evasion_Changes_due_to_Statuses:
  https://web.archive.org/web/2024/https://ffhacktics.com/wiki/Evasion_Changes_due_to_Statuses
- QuMarsh WotL FAQ, "Evasion Rates" and the reaction tables:
  https://gamefaqs.gamespot.com/android/705848-final-fantasy-tactics/faqs/50422

---

## 4. Formula IDs (ability data "formula" byte)

Each ability's data holds `formula`, two constants **X** and **Y**, an inflict-status index, element flags and
evadable / reflect flags. In FFHacktics notation:
- **F** = `C_Fa * T_Fa / 10000`
- **PE** = physical evade applies, **ME** = magical evade applies, **NE** = no evade applies
- **NS** = the ability cannot inflict status

The PSX table runs from 0x00 to 0x64. WotL has more content (Dark Knight, Fell Swords, new abilities) and
**probably extends the table past 0x64 [unverified]**. Check the formula bytes of Darkness and the other new
abilities in BOOT.BIN.

### 4.1 Magical modifiers (MOD 5 / MOD 6)

**Damage or healing, `MA * Y` with Faith (formulas 08 and 0C).** The code path for 08 is:
1. Magical evade roll
2. MA and Y loaded
3. Elemental Strengthen
4. Magical support, status and compatibility modifiers
5. Elemental `XA*YA` (includes weather and weak / half / absorb / null)
6. Faith
7. Absorb, and the status roll

As pseudocode:

```
MA1 = Strengthen(element) ? [MA*5/4] : MA
MA2 = Magic AttackUP / Arcane Strength (caster) ? [MA1*4/3] : MA1
MA3 = Magic DefendUP / Arcane Defense (target) ? [MA2*2/3] : MA2   -- not for healing / buffs
MA4 = Shell (target) ? [MA3*2/3] : MA3                            -- not for healing / buffs
MA5 = zodiac(MA4)
dmg = MA5 * Y
dmg = weather: snow & Ice x5/4, thunderstorm & Lightning x5/4, thunderstorm & Fire x3/4
dmg = weak x2, half /2 (absorb -> negative, null -> miss); WotL Oil & Fire x2
dmg = dmg * C_Fa * T_Fa / 10000        (Faith status -> treat Fa as 100, Innocent/Atheist -> 0)
cap 999
```

- The BMG writes the whole formula as one fraction: `[(C_Fa*T_Fa*Q*MA5*N)/(10000*D)]`. The code applies
  elements **before** faith, and those are separate routines.
- **[open]** The exact truncation inside the faith step: `[dmg*CFa*TFa/10000]` or `[[dmg*CFa/100]*TFa/100]`.
- Healing (0C, also 4C and 54) uses "Magical XA*YA". That routine applies only Magic AttackUP and
  compatibility: no Shell, no Magic DefendUP, and no negative-status effects. Faith comes after it, and then the
  undead reversal.

**Success rate, `(MA + X)` with Faith (formulas 0A, 0B, 09, 0D, 0E, 0F, 10, 12, 15, 16, 17, 1A, 1B, 61).**

```
MA' = Strengthen -> MAtkUP -> MDefUP -> Shell (MDefUP and Shell only for harmful spells) -> zodiac
hit% = [(MA' + X (+zodiac on X)) * C_Fa * T_Fa / 10000], then magical evade if the ability is evadable
```

PSX code path: Load MA and X → Strengthen → Magical support, status and compatibility → XA+YA → Faith → set hit%.

**Faith-free magical success (MOD 1 or MOD 6 without faith).** `hit = MA' + X`, used by Talk Skill / Speechcraft,
Steal Heart and some monster attacks.

### 4.2 Table

Ability names: the PSX name comes first and the WotL name after a slash. "Ch1" marks skill sets available in
chapter 1.

| ID | Effect / formula | Main users |
|---|---|---|
| 00 | same as 01 | — |
| **01** | Weapon damage (section 2); weapon element; weapon add-status proc; PE; Charge K added | ATTACK; many monster melee attacks |
| 02 | Weapon damage + 25% chance to cast the spell in the status slot | spell-proc weapons |
| 03 | `WP*WP` (NS) | — |
| 04 | Magic gun (see 4.3) | Glacial / Blaze / Blaster Gun |
| 05 | Weapon damage | — |
| 06 | Weapon damage, absorb HP | Blood Sword type |
| 07 | Weapon heal | Healing Staff type |
| **08** | `dmg = MA*Y * F` (MOD 5) | Fire/Bolt/Ice 1–4 (Fire, Fira, Firaga, Firaja; Thunder…; Blizzard…) Y=14/18/24/32; Flare 46; Holy 50; Meteor 60 PSX (**WotL table says 40** [unverified]); summons; Ultima 23; Bio types |
| 09 | `dmg = RU{T_MaxHP*Y/100}`, hit = `(MA+X)*F` | Demi / Gravity (25%, X=190), Demi 2 / Graviga (50%, X=120), Lich |
| **0A** | status, hit = `(MA+X)*F`; harmful; always evadable | Poison 160, Frog / Toad 120, Slow 180, Stop 110, Don't Move / Immobilize 190, Blind / Umbra 200, Pray Faith / Belief 150, Doubt Faith / Disbelief 150, Zombie / Corruption 100, Silence Song / Quiescence 180, Blind Rage / Fervor 120, Confusion Song / Delirium 130, Dispel Magic / Harmony 200, Paralyze / Hesitation 185, Sleep / Repose 170, Petrify / Induration 120 |
| **0B** | buff status, hit = `(MA+X)*F` (not evaded, ignores Shell / MDefUP) | Protect, Shell 200; Protect 2 / Protectja, Shell 2 / Shellja 120; Wall 140; Regen 170; Reraise 140; Esuna 190; Haste 180; Haste 2 / Hasteja 240; Float 140; Reflect 180 |
| **0C** | heal `MA*Y*F` (MAtkUP and zodiac only); undead: damage | Cure 14, Cure 2 / Cura 20, Cure 3 / Curaga 30, Cure 4 / Curaja 40; Moogle; Fairy |
| 0D | revive: heal `RU{T_MaxHP*Y/100}`, hit = `(MA+X)*F`; undead: damage | Raise (50%, X=180), Raise 2 / Arise (100%, X=160) |
| 0E | Dead status + damage = MaxHP, hit = `(MA+X)*F`; undead: healed | Death (X=100) |
| 0F | drain MP `Y%` of T_MaxMP, hit = `(MA+X)*F` | Spell Absorb / Empowerment (33%, X=160), Aspel |
| 10 | drain HP `Y%` of T_MaxHP, hit = `(MA+X)*F` | Life Drain / Invigoration (25%, X=160), Drain |
| 12 | Quick (CT := 100), hit = `(MA+X)*F` | Quick (X=140) |
| 14 | Golem: hit = `[C_Fa*(MA'+X)/100]` | Golem |
| 15 | CT := 0, hit = `(MA+X)*F` | Return 2 |
| 16 | MP damage = T_CurMP, hit = `(MA+X)*F` | Mute |
| 17 | damage = T_CurHP − 1, hit = `(MA+X)*F` | Gravi 2 |
| 1A | stat −X, hit = `(MA+Y)*F` | Speed / Power / Mind Ruin |
| 1B | MP damage `Y%`, hit = `(MA+X)*F` | Magic Ruin |
| 1C / 1D | Song / Dance, `X%` per target | Bard / Dancer |
| 1E | `[(MA+Y)/2]*MA`, rnd(1..X) hits (TRUTH) | Heaven Knight (Rapha): WotL 1–10 hits, PSX 1–6 |
| 1F | `[(100−C_Fa)(100−T_Fa)/10000 * [(MA+Y)/2] * MA]`, multi-hit | Hell Knight (Marach) |
| 20 | `MA*Y` (Draw Out / Iaido, magical, no faith, no evade); katana may break | Asura 8, Koutetsu / Kotetsu 12, … |
| 21 | MP damage `MA*Y` | Bizen Boat / Osafune |
| 22 | 100% status | Kiyomori, Masamune |
| 23 | heal `MA*Y` | Murasame (no zodiac) |
| 24 | `[(PA+Y)/2]*MA`, Y=2 (Elemental / Geomancy; magical; ~25% status) | Geomancer |
| **25** | equipment break, hit = `PA'+WP+X` (MOD 3, PE); if the target lacks that slot, a plain ATTACK instead | Battle Skill / Arts of War: Head Break / Rend Helm 45, Armor 40, Shield 55, Weapon 30 |
| 26 | steal equipment, hit = `Sp'+X` (PE) | Steal |
| 27 | steal gil `C_Lv*C_Sp`, hit = `Sp'+X` | Gil Taking / Mug |
| 28 | steal Exp `min(Sp+Y, T_Exp)`, hit = `Sp'+X` (no evade) | Steal Exp |
| 29 | opposite sex only, hit = `MA+X` | Steal Heart / Allure |
| 2A | Talk Skill, hit = `MA+X` (MOD 1: zodiac only, no evade) | Speechcraft |
| **2B** | stat break, hit = `PA'+X` (MOD 3, PE); PA −3, MA −3, Sp −2 | Power / Mind / Speed Break → Rend Power / Magick / Speed (X=50) |
| **2C** | MP damage `RU{T_MaxMP*Y/100}` (50%), hit = `PA'+X` | Magic Break / Rend MP (X=50) |
| **2D** | `dmg = PA*(WP+Y)` (MOD 2, weapon-elemental, no evade) + status ("Separate", 25%) | Holy Sword: Stasis Sword / Judgment Blade Y=2 (Stop), Split Punch / Cleansing Strike 3 (Doom), Crush Punch / Northswain's Strike 2 (Dead), Lightning Stab / Hallowed Bolt 4 (Silence), Holy Explosion / Divine Ruination 5 (Confuse) |
| 2E | breaks equipment + `PA*WP` damage | Mighty Sword / Unyielding Blade (WotL: damage lands even without the item, unless Safeguard) |
| **2F** | absorb MP `PA*WP` (NS, PE flag) | Dark Sword / Duskblade (Gaffgarion) |
| **30** | absorb HP `PA*WP` (NS, PE flag) | Night Sword / Shadowblade (Gaffgarion) |
| 31 | `[(PA+Y)/2]*PA` (crit possible) | Spin Fist / Cyclone Y=0, Wave Fist / Aurablast Y=2, Earth Slash / Shockwave Y=0 (Earth, no evade) |
| 32 | Repeating Fist / Pummel: BMG `rnd(1..9)*(PA+[PA/2])`; FFHacktics label `rnd(1..X)*(PA*3+Y)` (presumably /2) | WotL QuMarsh says 3 x PA x rnd(1..9) **[open]** |
| 33 | hit = `PA'+X` | Stigma Magic / Purification (X=120) |
| 34 | heal `PA*Y` HP and `[PA*Y/2]` MP (undead are healed too) | Chakra (Y=5) |
| 35 | revive `Y%` MaxHP, hit = `PA'+X` | Revive (20%, X=70) |
| **36** | PA + Y | Accumulate / Focus (+1) |
| **37** | `PA * rnd(1..Y)`, physical, knockback | Dash / Rush (Y=4, not evadable), Throw Stone / Stone (Y=2, evadable) |
| **38** | 100% effect | Heal / Salve (cures Darkness / Blind, Silence, Poison) |
| **39** | Speed + Y | Yell / Tailwind (+1) |
| **3A** | Brave + Y | Cheer Up / Steel (+5) |
| **3B** | Brave + X; PA, MA, Sp + Y | Scream / Shout (+10 / +1) |
| **3C** | heal `RU{C_MaxHP*2/5}` to the target, `RU{C_MaxHP/5}` damage to the caster; ignores zodiac and undead | Wish / Chant (Ramza) |
| 3D | hit = `MA+X` (reduced by MDefUP) | Death Sentence (monster), Blaster |
| 3F | hit = `Sp'+X` | Leg Aim / Arm Aim (Mustadio) |
| 40 | Undead only, hit = `Sp+X` | Seal Evil |
| 41 | hit = `MA+X`; 0% against the same sign | Galaxy Stop |
| 42 | `PA*Y` damage + `PA*Y/X` recoil | Worker 8 / Construct 8 |
| 43 | `C_MaxHP − C_CurHP` | Blade Beam, Shock |
| 45 | `T_MaxHP − T_CurHP` | Climhazzard |
| 47 | absorb HP `Y%` + Vampire | Blood Suck |
| **48** | heal `Z*10` (Z from the item record) | Potion 30, Hi-Potion 70, X-Potion 150; undead: damage |
| **49** | MP heal (item) | Ether 20, Hi-Ether 50 |
| **4A** | Elixir | full HP and MP |
| **4B** | Phoenix Down: revive with a small amount (BMG 1..20 HP); undead: KO | Phoenix Down |
| 4C | heal `MA*Y` | Choco Cure and others |
| 4D | absorb `Y%`, hit = `MA+X` (PE) | Drain Touch and others |
| 4E | `MA*Y` (magical, no faith) | Limit Braver 12, Cross-slash 22, Meteorain 26, …; breath attacks |
| 50 | hit = `MA+X` (PE; reduced by Defense UP) | Secret Fist / Doom Fist (X=50) and monster status touches |
| 53 | `Y%` of MaxHP, hit = `MA+X` | Hurricane |
| 5E / 5F / 60 | `[(MA+Y)/2]*MA` (hydra, Nanoflare) | — |
| 61 | Brave −Y, hit = `(MA+X)*F` | Foxbird / Trepidation (−30, X=140), Chicken |
| 63 | `Sp * WP` (thrown) | Throw (Ninja) |
| **64** | Jump (see 2.2) | Jump (Dragoon / Lancer) |

### 4.3 Magic gun

- Magical, MOD 5, with **WP in place of MA**: `dmg = [C_Fa * T_Fa * Q * WP' / 10000]`.
- Q = 14 with 60% chance, 18 with 30%, 24 with 10% (a level 1, 2 or 3 spell of the gun's element).
- No critical hits, and no evasion. It triggers Counter Magic, Counter Flood, Blade Grasp and Hamedo / First
  Strike, but not Counter.

### 4.4 Chapter 1 skill sets in WotL (names and constants)

- **Squire, Fundaments:**

  | Ability | Formula | Effect |
  |---|---|---|
  | Focus | 36 | PA +1 |
  | Rush | 37, Y=4 | |
  | Stone | 37, Y=2 | |
  | Salve | 38 | |

  Brawler / Martial Arts raises PA for Rush and Stone: `[PA*3/2]` applies whether or not a weapon is equipped,
  because these are not weapon-elemental.

- **Ramza (chapter 1), Mettle:**

  | Ability | Formula | Effect | PSX equivalent |
  |---|---|---|---|
  | Focus, Rush, Stone, Salve | as Squire | | |
  | Tailwind | 39 | Sp +1, 100%, range 3 | Yell |
  | Chant | 3C | 40% of Ramza's MaxHP healed, 20% lost | Wish |
  | Steel (chapter 2 and later) | 3A | Brave +5 | Cheer Up |
  | Shout (chapter 4) | 3B | Brave +10, PA/MA/Sp +1 | Scream |
  | Ultima (chapter 4) | 08 | Y=23 | |

  Each 4 points of Brave gained in battle add 1 permanent point (QuMarsh).

- **Chemist, Items:** potions are fixed amounts and ignore user stats and zodiac. Range is 1, or 4 with Throw
  Items (innate for Chemists). Hit is 100%.
- **Knight, Arts of War:** formula 25 (Rend Helm 45, Rend Armor 40, Rend Shield 55, Rend Weapon 30) and 2B / 2C
  (Rend MP 50 (MP − 50% of max), Rend Speed 50 (−2), Rend Power 50 (−3), Rend Magick 50 (−3)).
  - Breaks: `hit = PA + WP + X`. Stat rends: `hit = PA + X`.
  - All of them use MOD 3 and physical evasion, and use weapon range.
  - Dual Wield fires them twice.
  - For breaks, zodiac scales PA, WP and X separately (BMG).
- **Archer, Aim:** +1, +2, +3, +4, +5, +7, +10, +20. The ATTACK formula is used with K added (see 2.2), with
  physical evasion and weapon element.
- **White Magicks:** formulas 0C, 0D, 0B, and 08 for Holy. Constants are in the table.
- **Black Magicks:** formula 08 for the elemental spells and Flare; 0A for Poison 160 and Toad 120; 0E for
  Death 100.
- **Time Magicks:**
  - Haste 180, Hasteja 240 (0B)
  - Slow 180, Slowja 240, Stop 110, Immobilize 190 (0A)
  - Float 140, Reflect 180 (0B)
  - Quick 140 (12)
  - Gravity 190 (25%) and Graviga 120 (50%) (09)
  - Meteor (08)
- **Mystic / Oracle, Mystic Arts:**
  - Umbra 200, Belief 150, Disbelief 150, Corruption 100, Quiescence 180, Fervor 120, Delirium 130, Harmony 200,
    Hesitation 185, Repose 170, Induration 120 (0A)
  - Empowerment 160 (0F, 33% MP)
  - Invigoration 160 (10, 25% HP)
  - Trepidation 140 (61, Brave −30)
- **Agrias, Holy Sword:** formula 2D (see the table), 100% hit. A sword, knight sword or fell sword must be
  equipped. The attack is weapon-elemental, even though the AI treats it as Holy.
- **Gaffgarion, Fell Sword:** Shadowblade (30, HP drain `PA*WP`) and Duskblade (2F, MP drain). It can drain
  more than the target has.
- **Delita / Argath / Algus:** Squire variants with the Fundaments formulas.
- **Arithmeticks / Math Skill:**
  1. Pick an attribute: CT, Level, Exp or Height.
  2. Pick a divisor: Prime, 5, 4 or 3.
  3. Pick a spell from the CALC-flagged list.

  The spell hits every unit whose attribute value is divisible by the divisor (or is prime), with no MP cost
  and no charge time. Damage and success use the normal formula of that spell, including both units' Faith,
  zodiac and evasion.

Sources:
- FFHacktics Formulas table: https://web.archive.org/web/2024/https://ffhacktics.com/wiki/Formulas
- FFHacktics formula pages 08 / 0A / 0C, Calculate_Accuracy_for_Magical, Magical_XA_*_YA and Elemental_Strengthen
  (Wayback, `https://web.archive.org/web/2024/https://ffhacktics.com/wiki/08_Dmg_F(MA*Y)` and similar)
- BMG sections 2.5, 2.7, 3.2–3.13:
  https://gamefaqs.gamespot.com/ps/197339-final-fantasy-tactics/faqs/3876
- QuMarsh WotL FAQ, job and ability tables (WotL names, PWR and TIC):
  https://gamefaqs.gamespot.com/android/705848-final-fantasy-tactics/faqs/50422

---

## 5. Reactions

- **Trigger chance = the reacting unit's Brave %** (current Brave) for almost every reaction.
- These are not Brave-based:
  - **Weapon Guard / Parry**: enables W-EV. In WotL it is a reaction with no Brave roll, and it does not work
    against attacks from behind.
  - **Abandon / Reflexes**: doubles evades. It is always on.
- No reaction fires while the reacting unit has Berserk, Vampire (Blood Suck), Don't Act / Disable, Sleep,
  Confusion or Stop. Reactions never fire in response to other reactions.
- Damage-triggered reactions fire on any HP damage (including 0) from another unit, with Br% chance:
  - A Save / Fury: PA +1
  - MA Save / Magick Surge
  - Speed Save / Speed Surge
  - Auto Potion / Auto-Potion: uses the weakest potion in stock
  - Caution / Vigilance: Defending
  - Regenerator / Regenerate
  - Damage Split / Soulbind
  - Gilgame Heart / Gil Snapper
  - MP Switch / Mana Shield: damage goes to MP while MP > 0
- Critical-HP reactions fire if the unit is Critical after the hit, with Br% chance:
  - HP Restore / Critical: Recover HP
  - MP Restore / Critical: Recover MP
  - Critical Quick
  - Meatbone Slash / Bonecrusher: counter attack dealing damage equal to the reactor's MaxHP (QuMarsh describes
    the WotL version the same way)
- "Countergrasp" reactions are triggered by physical attacks (ATTACK, Charge, Jump, Throw, Battle Skill, Steal
  equipment and Gil Taking, most monster melee attacks). The attack does not need to hit.
  - **Counter**: the reactor makes an ATTACK if the attacker is within its weapon range. The counter attack
    triggers no further reactions. Counter does not trigger against magic guns.
  - **Blade Grasp / Shirahadori**: see 3.1.
  - **Counter Tackle**: Dash / Rush.
  - **Dragon Spirit / Dragonheart**: gives Reraise.
  - **Brave Up**: Brave +3 **[WotL name unverified]**.
  - **Sunken State**: gives Transparent.
- **Hamedo / First Strike**: against ATTACK, Battle Skill, Throw or Charge, if the attacker is within weapon range
  (PSX). It cancels the incoming action and the reactor ATTACKs first. It works against magic guns but not
  against generic monsters' special attacks. WotL text says "Attack command" only.
  **[unverified]** whether WotL First Strike still covers Arts of War, Aim and Throw.
- **Counter Magic / Magick Counter**: re-casts the spell at the caster, if the reactor has the MP. **Counter
  Flood / Nature's Wrath** **[name unverified]**: answers with Geomancy for the reactor's current tile.
  **Absorb Used MP / Absorb MP**: gains the MP the caster spent. **Face Up**: Faith +3 against Faith-based
  magick. **Catch / Sticky Fingers**: catches thrown items. **Distribute**: spreads excess healing to allies.
  **Arrow Guard / Archer's Bane**: see 3.1.

Sources:
- BMG section 4.1: https://gamefaqs.gamespot.com/ps/197339-final-fantasy-tactics/faqs/3876
- QuMarsh WotL FAQ, reaction tables (BRV column): https://gamefaqs.gamespot.com/android/705848-final-fantasy-tactics/faqs/50422

---

## 6. WotL versus PSX: known differences

Confirmed by at least one solid source:
- Full retranslation, so abilities, statuses and items have new names. For example:
  - Basic Skill → Fundaments; Guts → Mettle; Battle Skill → Arts of War; Charge → Aim
  - Punch Art → Martial Arts; Yin-Yang Magic → Mystic Arts; Math Skill → Arithmeticks; Draw Out → Iaido
  - Hamedo → First Strike; Blade Grasp → Shirahadori; Meatbone Slash → Bonecrusher; Weapon Guard → Parry;
    Abandon → Reflexes
  - Attack UP → Attack Boost; Defense UP → Defense Boost; Magic AttackUP → Arcane Strength;
    Magic DefendUP → Arcane Defense; Martial Arts → Brawler; Two Hands → Doublehand; Two Swords → Dual Wield;
    Short Charge → Swiftness; Concentrate → Concentration; Maintenance → Safeguard
  - Innocent → Atheist; Don't Act → Disable; Don't Move → Immobilize; Darkness → Blind; Frog → Toad;
    Petrify → Stone; Death Sentence → Doom; Transparent → Invisible; Blood Suck → Vampire
- **JP costs, ability charge times, character and enemy stats, and Safeguard on bosses were reset to the
  Japanese PSX values.** NA PSX had changed them. As a result, BMG CTR numbers are wrong for some WotL abilities.
- **Oil works**: fire damage x2. In PSX Oil had no effect because of a bug.
- Game-breaking glitches were fixed: the Quickening (Critical Quick + Mime loops), the JP-scroll glitch, weapon
  duplication, the poach bug and the jump glitches.
- Mighty Sword / Unyielding Blade (Meliadoul, TG Cid, Folmarv) now deal damage even when the target lacks the
  item, so it works on monsters. It still fails against Safeguard.
- TRUTH / UN-TRUTH (Sky Mantra / Nether Mantra) and Holy Breath hit 1–10 times instead of 1–6, and hit more
  reliably.
- New jobs:
  - **Dark Knight**, with Darkness and a sword required (QuMarsh formulas, **[unverified]**):
    - Sanguine Sword (HP) and Infernal Strike (MP): absorb `0.8 * PA * (WP + PWR)`.
    - Crushing Blow: `PA * (WP + PWR)` + Stop, weapon-elemental.
    - Abyssal Blade: cone-shaped area, costs 20% MaxHP. Damage by row:
      - row 1: `PA * BF * (WP + 3)`
      - row 2: `PA * BF * (WP + 1)`
      - row 3: `0.5 * PA * BF * WP`
    - Unholy Sacrifice: `PA * MA * BF + MaxHP/3`, Dark + Slow, costs 30% MaxHP.
    - BF = Br/100 with a knight sword, (100 − Fa)/100 with a fell sword, 1 with a sword.
    - Supports: HP Boost (+20% MaxHP). Vehemence: the user's attacks and healing x1.5, but damage taken is also
      x1.5 **[unverified exact factor and where it applies]**.
  - **Onion Knight**: no action abilities. Its stats grow with the number of mastered jobs. It uses normal
    weapon formulas.
- New weapon type: **fell sword**, `PA * WP * (100 − C_Fa)/100` (QuMarsh). Ramza's special skill set Mettle
  adds Tailwind, Chant, Steel and Shout (see 4.4).
- New characters Balthier and Luso. Luso's Huntcraft: Squire actions + Ultima. Balthier's Piracy: Leg / Arm
  Shot, Seal Evil, Plunder, Barrage (4 hits at half damage).
- Variable-damage weapons (axes, flails, bags) show the **average** in the preview. *(This is from the
  Ivalice Chronicles notes, so it may not be WotL.)*

Uncertain, to verify in the running game:
- Doublehand: whether Aim (Charge) gets the WP x 2 in WotL. The BMG says no for PSX, and QuMarsh says yes for
  WotL.
- Shirahadori: in PSX it is an extra (100 − Br)% factor on hit. WotL text says it blocks bows, crossbows and
  guns. Is it still Brave-scaled, and does it stack with evasion?
- First Strike: does it still trigger against Arts of War, Throw and Aim?
- Pummel / Repeating Fist: 1.5 x PA x rnd(1..9) (BMG) or 3 x PA x rnd(1..9) (QuMarsh text)?
- Meteor: Y = 40 (QuMarsh WotL table) or 60 (BMG PSX)?
- Silence duration: 36 ticks in WotL, or infinite as in PSX?
- Formula IDs above 0x64 for the new abilities; the Fell Sword formula.
- Whether Faith and Brave changes from Steel, Shout and Speechcraft give 1 permanent point per 4 in WotL. That is
  QuMarsh's claim, and PSX did the same.

Sources:
- FF Wiki, version differences: https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_version_differences
- QuMarsh WotL FAQ v7.02 (job, ability and weapon lists):
  https://gamefaqs.gamespot.com/android/705848-final-fantasy-tactics/faqs/50422
- BMG for the PSX baseline: https://gamefaqs.gamespot.com/ps/197339-final-fantasy-tactics/faqs/3876

---

## 7. Implementation checklist (calculator)

1. Pick the attacker's weapon branch to get XA0 and YA, and add the Charge / Aim K to XA.
2. Apply the physical XA modifiers (2.2, steps 2–11), then the critical bonus (code order), then `dmg = XA*YA`.
3. Apply elements: weak x2 (WotL Oil + Fire x2), half /2, absorb negates, null makes it miss. Then cap at 999.
4. Hit%: base, then Defending (`[base/2]`). Zero the evades if the target is charging, asleep, stopped, disabled
   or confused. Apply the directional evade set (3.1). Use the product, truncated, with an automatic miss if any
   single evade is >= base.
5. Magick:
   - Damage: MA', then `x Y`, then weather and elements, then `x CFa x TFa / 10000`, then the 999 cap.
   - Status: `(MA' + X) x CFa x TFa / 10000`, then magical evade if the ability is evadable.
6. Turn order: simulate ticks:
   1. status counters
   2. slow-action CTR and resolution
   3. CT += effective Speed
   4. turns in unit-list order
   5. after each turn, apply the CT rule from 1.4
