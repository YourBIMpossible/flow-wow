# P6: class coverage inventory

- **What this is:** a read-only inventory of what Flow does per class today, and the gaps, ranked by impact on a levelling player.
- **Read from:** source at `program-integ` a529eea. Nothing here was checked in the game.
- **Scope read:** `Classes/*`, `Modules/Rotation/*`, `Modules/Talents.lua`, `Modules/Spec.lua`, and the buff, food, tracking, gear and item modules that branch on class.
- **Paths:** every `file:line` is relative to the repo root at that commit.

## Summary

- Two of the nine classes have a class pack: Paladin and Druid (`Flow.toc:164-171`). Each pack registers `class`, `classSpells` and `rotation`.
- The other seven (Warrior, Hunter, Rogue, Priest, Shaman, Mage, Warlock) have no pack. They get the class-agnostic rotation (`Modules/Rotation/Engine.lua:32-41`), which has no class rules.
- Nothing in `Modules/` is switched on or off by class. Class behaviour comes from what a pack registers, plus a few hard-coded tables that name the other classes.
- So the largest gap is not a missing feature in one class. It is seven classes with no rotation, no role, no gear scoring and no spell advice.

## What a class with no pack gets

- **Rotation:** only help that needs no class spells: breaking free, healthstone and healing potion, bandage, food, drink, racial interrupts (`Modules/Rotation/Engine.lua:32-36`). The player is told so (`Modules/Rotation/Engine.lua:1427-1428`).
- **Care keys:** no heal, HoT or cure slots, because they are built from the pack's `heals`, `hots` and `dispels` (`Modules/Rotation/CareKeys.lua:120-128`).
- **Role:** always "dps" (`Modules/Spec.lua:181-185`). `/flow spec` prints "no spec advice for your class yet" (`Modules/Spec.lua:224`). The "Your role" setting is hidden (`Modules/Settings.lua:598-599`).
- **Talents:** trees are shown as the game has them, with "No levelling build written for your class yet" (`Modules/Talents.lua:456-457`). Tree names are known for Paladin and Druid only (`Modules/Spec.lua:88-91`).
- **Gear:** the class can tell what it may equip (`Modules/Gear/Score.lua:230-240`, used at `:247`), but every score is 0 because weights come only from class data (`Modules/Gear/Score.lua:264`).
- **Food buff choice:** a fallback by class group still works (`Modules/Rotation/BuffItems.lua:118-122`).
- **Group role guess:** `E.UnitKind` knows all nine classes as melee, caster or ranged (`Modules/Rotation/Engine.lua:994-1008`).
- **Trainer spell advice:** none; it needs `classSpells`.

## Coverage table

"none" means no code for it was found. "generic" means the class-agnostic code runs, with no class rule.

| Class | Rotation per spec or role | Buffs and self-buffs | Forms and stances | Pet | Tracking | Consumables | Role mapping |
|---|---|---|---|---|---|---|---|
| Druid | Cat, Bear, Bear AoE and caster damage lists, chosen by current form. No Restoration (healer) list. No Balance or Moonkin list. | Mark of the Wild, Thorns; Mark/Gift and Thorns on the group | Bear, Dire Bear, Cat and Prowl suggested; form keys; form bars. Travel and Aquatic never suggested. | not a pet class | herbs and minerals only | generic, plus food scored by role weights | dps = Feral (Cat), heal = Restoration, tank = Feral (Bear); default dps; talent trees read; one talent build (Cat) |
| Paladin | One single-target list for every role, an AoE list, an execute. No healer list. Protection differs only by seal, blessing and Righteous Fury. | Seal and blessing by role or your own pick; Devotion Aura; Righteous Fury when tank; blessings on the group | Aura read from the stance bar; only Devotion Aura is ever suggested | not a pet class | herbs and minerals only | generic, plus food scored by role weights | dps = Retribution, heal = Holy, tank = Protection; default dps; talent trees read; no talent build |
| Warrior | none (generic) | none; a "Shout" pattern exists but no rule uses it | none: no stance code | not a pet class | herbs and minerals only | generic; sharpening stones and weightstones fit | none: always dps |
| Hunter | none (generic) | none; a "Hunter's Mark" pattern exists but no rule uses it | none: no aspect code | none: no call, feed, revive, mend or happiness | herbs and minerals only; no Track Beasts and the like | generic; ammo is kept, never restocked | none: always dps |
| Rogue | none (generic); the combo-point bar shows | none | none: no Stealth rule | not a pet class | herbs and minerals only | generic; no poisons; Flash Powder is kept | none: always dps |
| Priest | none (generic) | none; a "Shield" pattern exists but no rule uses it | none: no Shadowform | not a pet class | herbs and minerals only | generic; candles and Light Feather are kept | none: always dps |
| Shaman | none (generic) | none; a "Shield" pattern exists but no rule uses it; no totems, no weapon imbues | none: no Ghost Wolf | not a pet class | herbs and minerals only | generic; Ankh is kept | none: always dps |
| Mage | none (generic) | none: no armor, no Arcane Intellect | none | not a pet class | herbs and minerals only | generic; no conjured food, water or mana gems; runes and Arcane Powder are kept | none: always dps |
| Warlock | none (generic) | none: no Demon Skin or Demon Armor | none | none: no summon, no pet rule | herbs and minerals only; no Sense Demons | generic: uses a healthstone if one is in the bags, never makes one; no soul shard handling | none: always dps |

### Evidence for the table

**Druid**
- Pack: `Classes/Druid/Rotation.lua:251` (rotation), `Classes/Druid/Data.lua:9` (class), `Classes/Druid/Spells.lua:18` (classSpells).
- Lists: cat `Classes/Druid/Rotation.lua:86-107`; bear `:109-114`; bear AoE `:116-119`; roots `:139-156`; caster damage `:158-169`.
- Self-buffs: Mark of the Wild `:53`, Thorns `:55`, Bear or Dire Bear when the role is tank `:48` and `:65-70`, Prowl `:71`. Group buffs `:215-221`. Cures `:224-229`.
- Heals on the care keys only: `heals = { Regrowth, Healing Touch, Rejuvenation }` `:258`. Forms: `shapeshifts = true` `:264`, form keys `:234-249` and `:306-310`.
- Roles: `Classes/Druid/Data.lua:10-18`. There is no Balance spec; the Balance tree maps to dps (`Modules/Spec.lua:97-99`). Talent build: `Classes/Druid/Data.lua:105-132`.
- Elsewhere: combo bar in Cat Form `Modules/PlateCombo.lua:50-53`; form bars `Modules/AutoPush.lua:165`; Revive `Modules/Rotation/Actions.lua:1013`; Bash as an interrupt `Modules/Rotation/Engine.lua:738-739`.

**Paladin**
- Pack: `Classes/Paladin/Rotation.lua:494`, `Classes/Paladin/Data.lua:7`, `Classes/Paladin/Spells.lua:20`.
- Seal by role `Classes/Paladin/Rotation.lua:90-95`; blessing by role `:185-191`; buffs `:302-317` (Devotion Aura `:303`, Righteous Fury `:305`).
- Lists: melee `:322-327`; execute `:329-332`; single target `:335-347`; AoE `:349-354`. Boss and elite use the default list `:554-555`.
- Heals on the care keys only `:516`. Cures `:510-513`. Fight keys `:543-546`.
- Roles: `Classes/Paladin/Data.lua:8-16`. Weapon speed `:92-96` (the only class with it).
- Elsewhere: seal and blessing pickers `Modules/Settings.lua:615-638`; Summon Warhorse `Modules/Nav/Mounts.lua:28`; Redemption `Modules/Rotation/Actions.lua:1013`; Hammer of Justice as an interrupt `Modules/Rotation/Engine.lua:740`.

**The other seven**
- No pack: `Flow.toc:164-171` lists only Paladin and Druid files.
- Buff patterns with no rule behind them: `Modules/Rotation/BuffButton.lua:51-52`.
- Resurrection: Priest and Shaman have one; Warrior, Hunter, Rogue, Mage and Warlock have none (`Modules/Rotation/Actions.lua:1013`).
- Interrupts: none of the seven has one in `E.INTERRUPTS` (`Modules/Rotation/Engine.lua:738-742`).
- Ammo kept for Hunter, Warrior, Rogue: `Modules/Items/Disposition.lua:535-536`. Reagents kept: `Modules/Items/Disposition.lua:546-559`.
- Rogue combo bar: `Modules/PlateCombo.lua:50-53`. Warlock Felsteed: `Modules/Nav/Mounts.lua:28`.
- Class quests recognise Ghost Wolf and Stealth as forms worth a quest step (`Modules/Quests/ClassQuests.lua:31-33`), but with no `classSpells` for those classes nothing feeds it.

**All classes**
- Pets: no pet code in `Modules/Rotation/*` or `Classes/*`. A search for `Feed Pet`, `GetPetHappiness`, `Call Pet`, `Revive Pet`, `Summon Imp` and `UNIT_PET` found nothing in the repo.
- Tracking: only Find Minerals and Find Herbs, by profession (`Modules/Rotation/Actions.lua:697-700`). Flow never overrides tracking the player chose (`Modules/Rotation/Actions.lua:717`).
- Consumables: healthstone, healing potion, bandage (`Modules/Rotation/BuffItems.lua:871-873`); drink (`:882-884`); weapon stones and oils by name (`:289-295`). Mana potions are not picked: only names with "Healing" count as a potion (`:872`).

## Gaps, ranked by impact on a levelling player

Ranking rule: how many levelling players are affected, and how much of their play the gap covers.

### 1. Seven classes have no rotation
- **Affected:** Warrior, Hunter, Rogue, Priest, Shaman, Mage, Warlock.
- **Effect:** the main key suggests no class spell in a fight. Flow's central feature is absent.
- **Evidence:** `Flow.toc:164-171`; `Modules/Rotation/Engine.lua:35-41`; `Modules/Rotation/Engine.lua:1427-1428`.

### 2. Seven classes have no class data, so gear is never scored
- **Affected:** the same seven.
- **Effect:** every item scores 0, so there is no upgrade advice. The role is always dps, and the role setting is hidden.
- **Evidence:** `Modules/Gear/Score.lua:264`; `Modules/Spec.lua:181-185`; `Modules/Settings.lua:598-599`.

### 3. Seven classes have no trainer spell list
- **Affected:** the same seven.
- **Effect:** no "go train X" advice and no class-quest steps for Stealth, Ghost Wolf, stances or pets.
- **Evidence:** only `Classes/Druid/Spells.lua:18` and `Classes/Paladin/Spells.lua:20` register `classSpells`; `Modules/Quests/ClassQuests.lua:31-33`.

### 4. No pet handling
- **Affected:** Hunter and Warlock, for the whole levelling range.
- **Effect:** nothing calls, summons, feeds, heals or revives a pet. For a Hunter the pet is most of the solo kit.
- **Evidence:** no match for the pet searches above in the repo; pets appear only as damage and threat sources outside the rotation.

### 5. No healer rotation for Druid or Paladin
- **Affected:** Restoration Druids and Holy Paladins in a group.
- **Effect:** the heal role changes gear weights, seal and blessing, but the priority list is still a damage list. Heals are only on the care keys, for yourself.
- **Evidence:** `Classes/Druid/Rotation.lua:258` and `:317`; `Classes/Paladin/Rotation.lua:516` and `:549`. The addon's own note on combat lockdown explains part of this (`CLAUDE.md:183-184`).

### 6. Talent builds: one of nine classes, one role
- **Affected:** every class but a Cat Druid.
- **Effect:** no point-by-point levelling build. Paladin has trees read but no build; both packs still carry an empty `talentPlan` placeholder.
- **Evidence:** `Classes/Druid/Data.lua:105` is the only `talentBuild`; `Classes/Paladin/Data.lua:25-27`; `Classes/Druid/Data.lua:36-37`; `Modules/Talents.lua:456-457`.

### 7. No forms or stances outside Druid
- **Affected:** Warrior (stances), Rogue (Stealth openers), Priest (Shadowform), Shaman (Ghost Wolf), Hunter (aspects).
- **Effect:** the form-following keys and the stealth state exist but only Druid sets `shapeshifts` and `formKeys`.
- **Evidence:** `Modules/Rotation/FormSpells.lua:39-41`; `Classes/Druid/Rotation.lua:264`; no match for `Battle Stance`, `Defensive Stance` or `Berserker Stance` in `Modules/Rotation/*`.

### 8. Class consumables are missing
- **Affected:** Mage (conjured food, water, mana gems), Warlock (making healthstones, soul shards), Rogue (poisons), Hunter (ammo, pet food), every mana user (mana potions).
- **Effect:** downtime and upkeep that these classes rely on is left to the player.
- **Evidence:** `Modules/Rotation/BuffItems.lua:872` (healing potions only); `Modules/Rotation/BuffItems.lua:289-295` (stones and oils only, no poison); `Modules/Items/Disposition.lua:535-536` (ammo is only kept).

### 9. Druid: no Balance spec and no caster build
- **Affected:** Druids before Cat Form (the pack's own spell list has it at level 20) and Balance Druids.
- **Effect:** the caster list is Moonfire, Wrath and Attack only. Starfire, Faerie Fire, Tiger's Fury and Innervate are in the trainer list but in no rule. Moonkin has no list.
- **Evidence:** `Classes/Druid/Rotation.lua:158-169`; `Classes/Druid/Data.lua:10-14`; `Classes/Druid/Spells.lua:47`, `:53`, `:57`, `:66`.

### 10. Paladin: one aura, and Exorcism only on a modifier
- **Affected:** all Paladins.
- **Effect:** Devotion Aura is the only aura ever suggested, although Retribution and Concentration are in the trainer list. Exorcism is only on Ctrl.
- **Evidence:** `Classes/Paladin/Rotation.lua:303`; `Classes/Paladin/Spells.lua:34` and `:40`; `Classes/Paladin/Rotation.lua:544`.

### 11. No class tracking
- **Affected:** Hunter (Track Beasts and the rest), Warlock (Sense Demons), Paladin (Sense Undead), Druid (Track Humanoids in Cat Form).
- **Effect:** small. Flow turns on only profession tracking, and leaves a player's own choice alone.
- **Evidence:** `Modules/Rotation/Actions.lua:697-700` and `:717`.

### 12. Trainer levels are unverified and stop early
- **Affected:** Druid past 40, Paladin past 50.
- **Effect:** both files say their levels are first guesses, corrected only when a trainer is visited. The Druid list ends at level 40 and the Paladin list at 50.
- **Evidence:** `Classes/Druid/Spells.lua:4-11` and `:65-67`; `Classes/Paladin/Spells.lua:4-16` and `:50`.

### 13. Smaller hard-coded gaps
- Interrupts: only Bash, Hammer of Justice and War Stomp (`Modules/Rotation/Engine.lua:738-742`). No Kick, Pummel, Earth Shock or Counterspell.
- Reagents: none listed for Warlock (soul shards) or Shaman totems (`Modules/Items/Disposition.lua:546-559`).
- Weapon speed advice: Paladin only (`Classes/Paladin/Data.lua:92-96`; `Classes/Druid/Data.lua:87-88`).
- Class trainer names: hard-coded for Paladin and Druid only (`Modules/Nav/Places.lua:26-33`).

## Test coverage by class

Counts are lines in `Modules/Tests.lua` that name the class token. They show where tests exist, not how good they are.

| Class | Lines | Notes |
|---|---|---|
| Druid | 100 | forms, Moonfire, talents, Prowl, Nature's Grasp |
| Paladin | 37 | seals, blessings, Righteous Fury, gear |
| Warrior | 12 | inputs to generic tests only |
| Mage | 9 | inputs only |
| Rogue | 3 | inputs only |
| Hunter | 2 | inputs only |
| Priest | 2 | inputs only |
| Shaman | 1 | inputs only |
| Warlock | 0 | none |

The no-pack fallback itself is tested (`Modules/Tests/Class.lua:16-28`).

## Suggested order for P6

This follows from the ranking; it is a suggestion, not a decision.

1. Add a minimal pack for each missing class (`class` with weights and specs, then `rotation` with a basic priority). This closes gaps 1 and 2 together, and the design already expects it (`Flow.toc:164-165`).
2. Add `classSpells` for each, which closes gap 3.
3. Pet handling for Hunter and Warlock (gap 4). This is new engine work, not only data.
4. Stances and Stealth through the existing form keys (gap 7).
5. Class consumables (gap 8), then the Druid and Paladin depth items (gaps 5, 9, 10).

## Limits of this inventory

- Read from source only. No claim here is about what the game does.
- Spell levels in the class packs are marked unverified by the packs themselves.
- Searches for missing features were by name. A feature under a name not searched for could have been missed.
