# P6: class coverage inventory

- **What this is:** a read-only inventory of what Flow does per class today, the gaps ranked by impact on a levelling player, and a build order in which every step names the evidence class of its data.
- **Read from:** source at `program-integ` a529eea. Nothing here was checked in the game.
- **Scope read:** `Classes/*`, `Modules/Rotation/*`, `Modules/Talents.lua`, `Modules/Spec.lua`, `Modules/Advisor/Builtins.lua`, `Modules/Trainer.lua`, `Modules/Nav/*`, and the buff, food, tracking, gear and item modules that branch on class.
- **Paths:** every `file:line` is relative to the repo root at that commit.
- **Revision 2:** applies review findings P6-1 to P6-10 (`WoW\from-white\REVIEW-P2-P6.md`). Each cited line was re-read in source first.
- **Revision 3:** applies round-2 findings P6r-1 to P6r-8 (`WoW\from-white\REVIEW-ROUND2-P2-P5-P6.md`) and replaces the single provenance rule with the three evidence classes of `WoW\from-white\CLASS-DATA-EVIDENCE-POLICY.md`. No data was changed. See "Review findings" at the end.

## Evidence classes (binding)

This section replaces the single provenance rule of revision 2. The rule is `WoW\from-white\CLASS-DATA-EVIDENCE-POLICY.md` (owner instruction, 2026-11-21). F-086 still binds: nothing invented is presented as fact, and no unlicensed list is imported. Commit 56ffc1b already removed guide-reported Paladin rows and profession picks for that reason.

Every piece of class data belongs to exactly one class.

| Class | What it is | Rule |
|---|---|---|
| A. Observed game facts | What the client itself reports: spell names, ranks, costs, cooldowns, cast times, tooltip numbers, trainer lists and the level each spell is offered at, talent tree layout, item stats, form and stance IDs, pet state. | Allowed once a read is recorded: interface number, date, the character's class and level, and how it was read. Not yet read means "unknown". An unread value may stay in code only if the source marks it "first guess" and no player-facing text states it as certain. |
| B. Independently authored recommendation models | Flow's own judgement built on class-A facts: stat weights, rotation priority order, talent point order, a default role, profession suggestions. | Allowed. The team authors these; the owner does not supply each value. Each model carries a provenance note in the file (authored by Flow, date, the class-A facts used, the method in one or two lines), is written without copying a guide, database or another addon's tables, is shown to the player as a recommendation, has tests on its structure, and stays open to correction from class-A observation, including Flow's own fight records. |
| C. Third-party content | Guides, wikis, databases, other addons' data tables, published weights, builds or rotations. | Never imported, copied or closely paraphrased unless compatible redistribution rights are documented. |

- **How Flow reads class A today:** a trainer read saved by Flow (`ns.db.trainer.services`, read at `Modules/Advisor/Builtins.lua:79`; first-taught levels in `Modules/Facts.lua`), the spellbook, and a `/flow talents` dump.
- **A class-B model with no recorded author is "authorship unrecorded", not "blocked".** The fix is to record the note or re-derive the model by the rule. It may keep shipping meanwhile.
- **Unknown stays unknown.** No bonus, level or number is invented to fill a gap.
- **Standing limit:** Flow does not heal, retarget or interrupt for other players in combat (`CLAUDE.md:183-184`). Any plan step that would do so stays out until the owner explicitly changes that rule.
- **Precondition per class:** a class-A read record (trainer read, spellbook, talent dump) exists for that class before any data for it is written.
- **Forever is not Classic.** The Paladin pack already names both Classic spells and later ones and skips what the character does not know (`Classes/Paladin/Rotation.lua:1-3`, `:339-346`, `:533`, `:544`). Each class's kit must be read on Forever, never assumed from Classic.

### Unverified legacy data

Existing data with no recorded read (class A) or no recorded author (class B). Nothing here was changed. Keep, re-read or re-derive is a later decision per item.

| Item | Where | Class | Status |
|---|---|---|---|
| Druid trainer levels | `Classes/Druid/Spells.lua:4-11`, rows `:19-67` | A | first guess, marked so in the source |
| Paladin trainer levels | `Classes/Paladin/Spells.lua:4-16`, rows `:21-50` | A | first guess, marked so in the source |
| Druid class-quest IDs (Bear Form 6001, 6002; Aquatic Form 5061, 31) | `Classes/Druid/Spells.lua:26-30`, `:40-46` | A | no read recorded; the comments say "in Classic" |
| Paladin class-quest item (Linen Cloth for Redemption at 12) | `Classes/Paladin/Data.lua:80-83` | A | no read recorded |
| Form-bar numbers (Cat 1, Bear 3, Dire Bear 3) | `Modules/AutoPush.lua:163-165` | A | first guess ("classic's numbers"); the game's own answer replaces it once in a form |
| Equip table for all nine classes | `Modules/Gear/Score.lua:230-240` | A | no read recorded |
| Druid and Paladin equip lists in the packs | `Classes/Druid/Data.lua:90-96`; `Classes/Paladin/Data.lua:98-105` | A | no read recorded |
| Druid talent tree layout | `Classes/Druid/Data.lua:99-104`, `:109` | A | the comment says read with `/flow talents dump`; no read record (date, character) is cited |
| Druid stat weights | `Classes/Druid/Data.lua:40-83` | B | authorship unrecorded ("tuned for levelling") |
| Paladin stat weights | `Classes/Paladin/Data.lua:30-78` | B | authorship unrecorded ("tuned for levelling") |
| Druid talent point order and reasons | `Classes/Druid/Data.lua:105-131` | B | authorship unrecorded |
| Druid profession picks and reasons | `Classes/Druid/Data.lua:24-29` | B | authorship unrecorded |
| Default role, Druid and Paladin | `Classes/Druid/Data.lua:17-18`; `Classes/Paladin/Data.lua:15-16` | B | authorship unrecorded |
| Default role "dps" for a class with no pack | `Modules/Spec.lua:184` | B | authorship unrecorded |
| Paladin weapon speed preference | `Classes/Paladin/Data.lua:92-96` | B | authorship unrecorded |
| Paladin rules for later-style spells (Holy Strike, Judgment, Crusader Strike, Shield of the Righteous) | `Classes/Paladin/Rotation.lua:339-346` | A for the names, B for the order | no read recorded; skipped when the spell is unknown |
| Rotation list order, Druid and Paladin | `Classes/Druid/Rotation.lua:86-169`; `Classes/Paladin/Rotation.lua:322-354` | B | authorship unrecorded |

## Summary

- Two of the nine classes have a class pack: Paladin and Druid (`Flow.toc:164-171`). Each pack registers `class`, `classSpells` and `rotation`.
- The other seven (Warrior, Hunter, Rogue, Priest, Shaman, Mage, Warlock) have no pack. They get the class-agnostic rotation (`Modules/Rotation/Engine.lua:32-41`), which has no class rules.
- Nothing in `Modules/` is switched on or off by class as a whole. Class behaviour comes from what a pack registers, plus a few hard-coded tables and one hard check for Paladin (`Modules/Settings.lua:615`).
- The largest gap is seven classes with no rotation, no gear scoring and, for Hunter and Warlock, no pet handling.
- A class with no pack is not empty-handed: see the next section.

## Works today without a class pack

Read from source; none of it confirmed in the client.

- **Breaking free with a racial:** Will to Survive, Every Man for Himself, Will of the Forsaken, Escape Artist (`Modules/Rotation/Engine.lua:717-722`).
- **Racial interrupt:** War Stomp (`Modules/Rotation/Engine.lua:738-742`).
- **Cannibalize** after a fight, for Undead of any class (`Modules/Rotation/Engine.lua:585-623`, used at `:645-646`).
- **Recovery order:** healthstone, healing potion, bandage, food, drink (`Modules/Rotation/Engine.lua:32-36`; `Modules/Rotation/BuffItems.lua:871-873`, `:882-884`).
- **Resurrection of a dead friend you target:** Priest and Shaman, with no pack (`Modules/Rotation/Actions.lua:1013`, `:1020`).
- **Trainer advice from the trainer's own list:** "Train X at your class trainer", with rank and cost, for any class once a class trainer has been read (`Modules/Advisor/Builtins.lua:72-118`).
- **Class trainer found by NPC title:** "Warrior Trainer" becomes `class:WARRIOR` for all nine classes (`Modules/Nav/Services.lua:42-48`), which also lets a trainer count as a class trainer when there is no `classSpells` set (`Modules/Trainer.lua:15-26`).
- **Form-bar learning:** Flow notes which action bar the game shows for any form or stance you enter (`Modules/AutoPush.lua:179-189`). Only Druid has bars known in advance (`Modules/AutoPush.lua:163-165`; a first guess, see "Unverified legacy data").
- **Travel-spell registry:** a `travelSpell` kind any class can register into; today only Teleport: Moonglade is in it (`Modules/Nav/TravelSpells.lua:24`).
- **Role by hand:** `/flow spec dps|heal|tank` sets the role for any class (`Modules/Spec.lua:257-261`, resolved at `:181-185`).
- **Food buff choice by class group** (`Modules/Rotation/BuffItems.lua:118-122`), **group role guess** for all nine classes (`Modules/Rotation/Engine.lua:994-1008`), **equip rules** for all nine (`Modules/Gear/Score.lua:230-240`; no read recorded, see "Unverified legacy data"), **kept ammo and reagents** (`Modules/Items/Disposition.lua:535-559`), **Rogue combo bar** (`Modules/PlateCombo.lua:50-53`), **Warlock Felsteed** as a mount (`Modules/Nav/Mounts.lua:28`).

## What a class with no pack does not get

- **Rotation:** no class spell on the main key. The player is told so (`Modules/Rotation/Engine.lua:1427-1428`).
- **Heals in a fight:** none, because the fight heal needs the pack's `heals` (`Modules/Rotation/Engine.lua:815-817`).
- **Care keys:** no heal, HoT or cure slots; they are built from the pack's `heals`, `hots` and `dispels` (`Modules/Rotation/CareKeys.lua:120-128`).
- **Friend-target buffs and heals:** none. Buffs come from the pack's `groupBuffs`, HoTs from its `hots`, and the heal from the pack's `heals` (`Modules/Rotation/Engine.lua:1285`, `:1301`, `:1308`; `Modules/Rotation/Cast.lua:511-512`, `:607`).
- **Role default and names:** the role falls back to "dps" unless set with `/flow spec` (`Modules/Spec.lua:181-185`). `/flow spec` with no argument prints "no spec advice for your class yet" (`Modules/Spec.lua:224`). The "Your role" row in Settings is hidden (`Modules/Settings.lua:598-599`). Tree names are known for Paladin and Druid only (`Modules/Spec.lua:88-91`).
- **Talents:** trees are shown as the game has them, with "No levelling build written for your class yet" (`Modules/Talents.lua:456-457`).
- **Gear:** the weight sum is 0 for every item, because weights come only from class data (`Modules/Gear/Score.lua:264`). Only a bonus from a gear analyzer can add to it (`Modules/Gear/Score.lua:270`). Setting a role by hand does not change that.
- **Trainer advice beyond the trainer's own list:** no "improves" notes, no "waits for another spell" from the class list, and no advice for a spell before the first trainer visit (`Modules/Advisor/Builtins.lua:121-150`). No class-quest steps (`Modules/Quests/ClassQuests.lua:31-33`).

## Coverage table

"none" means no code for it was found. "generic" means the class-agnostic code runs, with no class rule.

| Class | Rotation per spec or role | Buffs and self-buffs | Forms and stances | Pet | Tracking | Consumables | Role mapping |
|---|---|---|---|---|---|---|---|
| Druid | Cat, Bear, Bear AoE and caster damage lists, chosen by current form. Moonkin Form reuses the caster list. No healer priority list. | Mark of the Wild, Thorns; Mark/Gift and Thorns on the group | Bear and Dire Bear suggested only when the role is tank. Prowl suggested once in Cat Form. Cat Form is never suggested as a form to enter. Cat, Bear, Dire Bear and Travel Form are root breakers. Aquatic never suggested. Form keys; form bars. | not a pet class | herbs and minerals only | generic, plus food scored by role weights | dps = Feral (Cat), heal = Restoration, tank = Feral (Bear); default dps; talent trees read; one talent build (Cat), authorship unrecorded |
| Paladin | One single-target list for every role, an AoE list, an execute. No healer priority list. Protection differs only by seal, blessing and Righteous Fury. | Seal and blessing by role or your own pick; Devotion Aura; Righteous Fury when tank; blessings on the group | Aura read from the stance bar; only Devotion Aura is ever suggested | not a pet class | herbs and minerals only | generic, plus food scored by role weights | dps = Retribution, heal = Holy, tank = Protection; default dps; talent trees read; no talent build |
| Warrior | none (generic) | none; a "Shout" pattern exists but no rule uses it | none: no stance code; bar learned when entered | not a pet class | herbs and minerals only | generic; sharpening stones and weightstones fit | no default or names; `/flow spec` sets it |
| Hunter | none (generic) | none; a "Hunter's Mark" pattern exists but no rule uses it | none: no aspect code | none: no call, feed, revive, mend or happiness | herbs and minerals only; no Track Beasts and the like | generic; ammo is kept, never restocked | no default or names; `/flow spec` sets it |
| Rogue | none (generic); the combo-point bar shows | none | none: no Stealth rule | not a pet class | herbs and minerals only | generic; no poisons; Flash Powder is kept | no default or names; `/flow spec` sets it |
| Priest | none (generic); Resurrection on a dead friend | none; a "Shield" pattern exists but no rule uses it | none: no Shadowform | not a pet class | herbs and minerals only | generic; candles and Light Feather are kept | no default or names; `/flow spec` sets it |
| Shaman | none (generic); Ancestral Spirit on a dead friend | none; a "Shield" pattern exists but no rule uses it; no totems, no weapon imbues | none: no Ghost Wolf | not a pet class | herbs and minerals only | generic; Ankh is kept | no default or names; `/flow spec` sets it |
| Mage | none (generic) | none: no armor, no Arcane Intellect | none | not a pet class | herbs and minerals only | generic; no conjured food, water or mana gems; runes and Arcane Powder are kept | no default or names; `/flow spec` sets it |
| Warlock | none (generic) | none: no Demon Skin or Demon Armor | none | none: no summon, no pet rule | herbs and minerals only; no Sense Demons | generic: uses a healthstone if one is in the bags, never makes one; no soul shard handling | no default or names; `/flow spec` sets it |

### Evidence for the table

**Druid**
- Pack: `Classes/Druid/Rotation.lua:251` (rotation), `Classes/Druid/Data.lua:9` (class), `Classes/Druid/Spells.lua:18` (classSpells).
- Lists: cat `Classes/Druid/Rotation.lua:86-107`; bear `:109-114`; bear AoE `:116-119`; roots `:139-156`; caster damage `:158-169`.
- Caster means no form or Moonkin Form (`:16-19`); Moonkin's keys are the caster's (`:246`).
- Self-buffs: Mark of the Wild `:53`, Thorns `:55`. Bear or Dire Bear only when the role is tank (`:47-49`, `:65-70`). Prowl only when already in Cat Form (`:71-72`). No rule in `:52-73` enters Cat Form.
- Root breakers: Travel, Cat, Bear and Dire Bear Form (`Modules/Rotation/Engine.lua:725-728`).
- Tiger's Fury and Dash are on Alt + key in Cat Form (`Classes/Druid/Rotation.lua:241-242`).
- Heals: `heals = { Regrowth, Healing Touch, Rejuvenation }` `:258`. Forms: `shapeshifts = true` `:264`, form keys `:234-249` and `:306-314`.
- Roles: `Classes/Druid/Data.lua:10-18`. There is no Balance spec; the Balance tree maps to dps (`Modules/Spec.lua:97-99`). Talent build: `Classes/Druid/Data.lua:105-132`.
- Elsewhere: combo bar in Cat Form `Modules/PlateCombo.lua:50-53`; form bars `Modules/AutoPush.lua:165`; Revive `Modules/Rotation/Actions.lua:1013`; Bash as an interrupt `Modules/Rotation/Engine.lua:738-739`; Teleport: Moonglade `Modules/Nav/TravelSpells.lua:24`.

**Paladin**
- Pack: `Classes/Paladin/Rotation.lua:494`, `Classes/Paladin/Data.lua:7`, `Classes/Paladin/Spells.lua:20`.
- Seal by role `Classes/Paladin/Rotation.lua:90-95`; blessing by role `:185-191`; buffs `:302-317` (Devotion Aura `:303`, Righteous Fury `:305`).
- Lists: melee `:322-327`; execute `:329-332`; single target `:335-347`; AoE `:349-354`. Boss and elite use the default list `:554-555`.
- Heals `:516`. Cures `:510-513`. Fight keys `:543-546`.
- Roles: `Classes/Paladin/Data.lua:8-12`. Weapon speed `:92-96` (the only class with it).
- Elsewhere: seal and blessing pickers behind a hard `PALADIN` check `Modules/Settings.lua:615-638`; Summon Warhorse `Modules/Nav/Mounts.lua:28`; Redemption `Modules/Rotation/Actions.lua:1013`; Hammer of Justice as an interrupt `Modules/Rotation/Engine.lua:740`; Blessing of Freedom as a root breaker `Modules/Rotation/Engine.lua:723`.

**The other seven**
- No pack: `Flow.toc:164-171` lists only Paladin and Druid files.
- Buff patterns with no rule behind them: `Modules/Rotation/BuffButton.lua:51-52`.
- Resurrection: Priest and Shaman have one; Warrior, Hunter, Rogue, Mage and Warlock have none (`Modules/Rotation/Actions.lua:1013`).
- Interrupts: none of the seven has a class interrupt in `E.INTERRUPTS` (`Modules/Rotation/Engine.lua:738-742`).
- Ammo kept for Hunter, Warrior, Rogue: `Modules/Items/Disposition.lua:535-536`. Reagents kept: `Modules/Items/Disposition.lua:546-559`.
- Class quests recognise Ghost Wolf and Stealth as forms worth a quest step (`Modules/Quests/ClassQuests.lua:31-33`), but with no `classSpells` for those classes nothing feeds it.

**All classes**
- Heals, where a pack has them, run on the main key in a fight (`Modules/Rotation/Engine.lua:813-819`, using `:104` and `:333`) and in the recovery order after it (`:640`). A living friendly player you target is buffed and healed while you are out of a fight (`Modules/Rotation/Engine.lua:1282-1284`; setting at `Modules/Rotation/Actions.lua:1068-1072`). Out of combat lockdown, when the main suggestion is a heal, the queue lists the recovery options (`Modules/Rotation/Queue.lua:240-243`); a friendly target that is not you is detected at `:244-246`.
- Pets: no pet code in `Modules/Rotation/*` or `Classes/*`. A search for `Feed Pet`, `GetPetHappiness`, `Call Pet`, `Revive Pet`, `Summon Imp` and `UNIT_PET` found nothing in the repo.
- Tracking: only Find Minerals and Find Herbs, by profession (`Modules/Rotation/Actions.lua:697-700`). Flow never overrides tracking the player chose (`Modules/Rotation/Actions.lua:717`).
- Consumables: healthstone, healing potion, bandage (`Modules/Rotation/BuffItems.lua:871-873`); drink (`:882-884`); weapon stones and oils by name (`:289-295`). Mana potions are not picked: only names with "Healing" count as a potion (`:872`).

## Gaps, ranked by impact on a levelling player

Ranking rule: how many levelling players are affected, and how much of their play the gap covers.

### 1. Seven classes have no rotation
- **Affected:** Warrior, Hunter, Rogue, Priest, Shaman, Mage, Warlock.
- **Effect:** the main key suggests no class spell in a fight, and no heal. Flow's central feature is absent.
- **Evidence:** `Flow.toc:164-171`; `Modules/Rotation/Engine.lua:35-41`; `Modules/Rotation/Engine.lua:1427-1428`.

### 2. No pet handling
- **Affected:** Hunter and Warlock, for the whole levelling range.
- **Effect:** nothing calls, summons, feeds, heals or revives a pet. For a Hunter the pet is most of the solo kit, so a Hunter rotation without it is not usable.
- **Evidence:** no match for the pet searches above in the repo; pets appear only as damage and threat sources outside the rotation.

### 3. Seven classes have no class data, so gear is never scored
- **Affected:** the same seven.
- **Effect:** the weight sum is 0 for every item (only a gear analyzer bonus can add to it), so there is no stat-based upgrade advice. There is no default role and no spec names; the role can still be set with `/flow spec`, but nothing shows that in Settings.
- **Evidence:** `Modules/Gear/Score.lua:264`, `:270`; `Modules/Spec.lua:181-185`, `:257-261`; `Modules/Settings.lua:598-599`.

### 4. A dps Druid is never told to enter Cat Form
- **Affected:** every Druid levelling as dps (the default role) from the level Cat Form is learned.
- **Effect:** the Cat list, Prowl, the combo bar and the one talent build all need Cat Form, but no rule suggests entering it. Bear is suggested for a tank; there is no matching rule for dps. Cat Form appears only as a root breaker.
- **Evidence:** `Classes/Druid/Rotation.lua:47-49` and `:52-73` (no Cat Form rule; Prowl needs `inCat()`); `Modules/Rotation/Engine.lua:726`; default role `Classes/Druid/Data.lua:17-18`.

### 5. Seven classes have no class spell list
- **Affected:** the same seven.
- **Effect:** "Train X" still comes from the trainer's own list. What is lost: what a spell improves, "waits for another spell", advice before the first trainer visit, and class-quest steps for Stealth, Ghost Wolf, stances or pets.
- **Evidence:** `Modules/Advisor/Builtins.lua:72-118` (works without a list) and `:121-150` (needs one); only `Classes/Druid/Spells.lua:18` and `Classes/Paladin/Spells.lua:20` register `classSpells`; `Modules/Quests/ClassQuests.lua:31-33`.

### 6. No healer priority list in a fight
- **Affected:** Restoration Druids and Holy Paladins in a group; later Priest and Shaman.
- **Effect:** the heal role changes gear weights, seal and blessing, but the fight list is still a damage list. Heals do run on the main key for yourself, and a targeted friend is healed out of a fight; what is missing is a heal-first list during a fight. Under the standing limit, such a list may cover the player's own healing only.
- **Evidence:** `Modules/Rotation/Engine.lua:813-819`, `:1282-1284`; `Classes/Druid/Rotation.lua:258` and `:317`; `Classes/Paladin/Rotation.lua:516` and `:549`. The addon's own note on combat lockdown explains part of this (`CLAUDE.md:183-184`).

### 7. Talent builds: one of nine classes, one role
- **Affected:** every class but a Cat Druid.
- **Effect:** no point-by-point levelling build. Paladin has trees read but no build; both packs still carry an empty `talentPlan` placeholder. The one existing build (Druid) has no recorded author for its point order.
- **Evidence:** `Classes/Druid/Data.lua:105` is the only `talentBuild`; `Classes/Paladin/Data.lua:25-27`; `Classes/Druid/Data.lua:36-37`; `Modules/Talents.lua:456-457`.

### 8. No forms or stances outside Druid
- **Affected:** Warrior (stances), Rogue (Stealth openers), Priest (Shadowform), Shaman (Ghost Wolf), Hunter (aspects).
- **Effect:** the form-following keys and the stealth state exist but only Druid sets `shapeshifts` and `formKeys`. The bar for a stance is learned once entered, with nothing to put on it.
- **Evidence:** `Modules/Rotation/FormSpells.lua:39-41`; `Classes/Druid/Rotation.lua:264`; `Modules/AutoPush.lua:179-189`; no match for `Battle Stance`, `Defensive Stance` or `Berserker Stance` in `Modules/Rotation/*`.

### 9. Class consumables are missing
- **Affected:** Mage (conjured food, water, mana gems), Warlock (making healthstones, soul shards), Rogue (poisons), Hunter (ammo, pet food), every mana user (mana potions).
- **Effect:** downtime and upkeep that these classes rely on is left to the player.
- **Evidence:** `Modules/Rotation/BuffItems.lua:872` (healing potions only); `Modules/Rotation/BuffItems.lua:289-295` (stones and oils only, no poison); `Modules/Items/Disposition.lua:535-536` (ammo is only kept).

### 10. Druid: no Balance spec and a thin caster list
- **Affected:** Druids before Cat Form and Balance Druids.
- **Effect:** the caster list is Moonfire, Wrath and Attack only, and Moonkin Form reuses it. Starfire, Faerie Fire and Innervate are in the class spell list but in no rule. (Tiger's Fury is covered: Alt + key in Cat Form.)
- **Evidence:** `Classes/Druid/Rotation.lua:158-169`, `:16-19`, `:246`, `:242`; `Classes/Druid/Data.lua:10-14`; `Classes/Druid/Spells.lua:47`, `:53`, `:66`.

### 11. Paladin: one aura, and Exorcism only on a modifier
- **Affected:** all Paladins.
- **Effect:** Devotion Aura is the only aura ever suggested, although Retribution and Concentration are in the class spell list. Exorcism is only on Ctrl.
- **Evidence:** `Classes/Paladin/Rotation.lua:303`; `Classes/Paladin/Spells.lua:34` and `:40`; `Classes/Paladin/Rotation.lua:544`.

### 12. No class tracking
- **Affected:** Hunter, Warlock, Paladin, Druid (which tracking spells each has on Forever is not read yet).
- **Effect:** small. Flow turns on only profession tracking, and leaves a player's own choice alone.
- **Evidence:** `Modules/Rotation/Actions.lua:697-700` and `:717`.

### 13. Trainer levels are unverified and stop early
- **Affected:** Druid past 40, Paladin past 50.
- **Effect:** both files say their levels are first guesses, corrected only when a trainer is visited. The Druid list ends at level 40 and the Paladin list at 50.
- **Evidence:** `Classes/Druid/Spells.lua:4-11` and `:65-67`; `Classes/Paladin/Spells.lua:4-16` and `:50`.

### 14. Smaller hard-coded gaps
- Interrupts: only Bash, Hammer of Justice and War Stomp (`Modules/Rotation/Engine.lua:738-742`). No class interrupt for the other seven.
- Reagents: none listed for Warlock (soul shards) or Shaman totems (`Modules/Items/Disposition.lua:546-559`).
- Weapon speed advice: Paladin only (`Classes/Paladin/Data.lua:92-96`; `Classes/Druid/Data.lua:87-88`).
- Class trainer names: hard-coded for Paladin (`Modules/Nav/Places.lua:26-27`) and Druid (`Modules/Nav/Places.lua:32-35`) only. Other classes rely on the NPC title (`Modules/Nav/Services.lua:42-48`).
- Seal and blessing pickers are behind a hard `PALADIN` check (`Modules/Settings.lua:615`), not a pack capability.

## Test coverage by class

Counts are lines that name the class token. They show where tests exist, not how good they are.

| Class | `Modules/Tests.lua` | `Modules/Tests/Class.lua` | `Modules/Tests/Safety.lua` | Notes |
|---|---|---|---|---|
| Druid | 100 | 6 | 2 | forms, Moonfire, talents, Prowl, Nature's Grasp |
| Paladin | 37 | 5 | 5 | seals, blessings, Righteous Fury, gear |
| Warrior | 12 | 0 | 0 | inputs to generic tests only |
| Mage | 9 | 0 | 0 | inputs only |
| Rogue | 3 | 0 | 0 | inputs only |
| Hunter | 2 | 0 | 0 | inputs only |
| Priest | 2 | 0 | 0 | inputs only |
| Shaman | 1 | 0 | 0 | inputs only |
| Warlock | 0 | 0 | 0 | none |

The no-pack fallback itself is tested (`Modules/Tests/Class.lua:16-28`).

## Build order for P6

A suggestion, not a decision. Per class, in this order. Each step names the evidence class of its data and where that data comes from.

| Step | What | Closes gap | Data and evidence class | State today |
|---|---|---|---|---|
| 0 | Record a class-A read for the class: trainer read, spellbook, `/flow talents` dump, with interface number, date, character class and level | precondition | A: the client itself | none recorded for the seven: unknown until read |
| 1 | `rotation`: a basic priority list | 1 | Spell names, costs, cooldowns, cast times and tooltip damage: A, from the spellbook and a trainer read. List order: B, authored by Flow from those numbers (for example damage per second of cast time, then cost), with a provenance note. A remembered or guide rotation is not a source. Afterwards the order is open to correction by Flow's own fight records, which the engine already uses for rules marked adaptive (`Modules/Rotation/Engine.lua:926-937`). | names unknown until read; order can be authored once the read exists |
| 2 | Pet handling (Hunter, Warlock), before any later step for these two | 2 | Pet spell names: A, the spellbook. Whether pet state can be read in a fight: A, a recorded client read. The rules for when to call, feed or heal the pet: B. | unknown until read; new engine work, not only data |
| 3 | `class`: specs, default role, gear weights | 3 | Spec and tree names: A, a `/flow talents` dump. Stat keys: A, item tooltips read in the client. Weight numbers and the default role: B, authored by Flow with a provenance note (for example weights from the attack power and crit formulas the character sheet shows). Until a default role is authored for a class, the pack sets none and the role is the player's choice. | names unknown until read; weights and default role can be authored once the read exists |
| 4 | `classSpells` | 5 | Names, levels and costs: A, a trainer read saved by Flow. A spell on no read is not listed. Class-quest IDs: A, the client's quest log only. The "improves" labels: B. | unknown until read |
| 5 | Heal-first list for the player's own healing in a fight (Druid, Paladin, then Priest, Shaman) | 6 | Heal spell names and costs: A, the spellbook. Order and health thresholds: B. | Druid and Paladin spell names exist in the packs. Scope is settled: own healing only. Healing, retargeting or interrupting for other players in a fight is out until the owner explicitly changes the standing limit. |

Outside the per-class order:

- **Cat Form for a dps Druid (gap 4):** needs no new data; the spell name is already in the pack. The trigger rule is class B. Whether a form change can be suggested from caster form at the pull is class A, to be read in the client. Can be done first, ahead of all new classes.
- **Talent builds (gap 7):** layout is class A, from a `/flow talents` dump. Point order is class B: authored by Flow from the talent tooltips in that dump, with a provenance note. No longer blocked. The existing Druid order needs its note recorded or the order re-derived.
- **Stances and Stealth (gap 8):** stance and form names are class A, from the spellbook and the stance bar; whether they are readable in a fight is class A. Unknown until read.
- **Class consumables (gap 9), tracking (gap 12):** spell and item names are class A, from the spellbook and the bags. Unknown until read.
- **Druid and Paladin depth (gaps 10, 11, 13):** class A from the spellbook and trainer reads for those two classes; first-guess levels are replaced by read ones, not by new guesses.
- **Legacy data:** each row of "Unverified legacy data" is closed by a recorded read (class A) or a recorded provenance note or re-derivation (class B). It keeps shipping meanwhile.

## Needs the game client

- Whether a class with no pack actually gets "Train X" advice after a trainer visit.
- Spell names, trainer levels and talent layout for each class on Forever.
- Whether stance, stealth and pet state are readable in a fight.
- The tracking spells each class has.
- What the gear advisor shows when the weight sum is 0 for every item.

## Review findings

### Round 1 (revision 2)

| Finding | Result |
|---|---|
| P6-1 | Applied: provenance rule, a source on every build step. Superseded in revision 3 by the evidence classes. |
| P6-2 | Applied: trainer advice works without a pack; gap moved from 3 to 5. |
| P6-3 | Applied: new gap 4; table corrected. |
| P6-4 | Applied: role can be set with `/flow spec`; only the default, the names and the Settings row are missing. |
| P6-5 | Applied, with one precision: the targeted friend is healed only while you are out of a fight (`Modules/Rotation/Engine.lua:1284`). Upheld in round 2. |
| P6-6 | Applied: Moonkin reuses the caster list. |
| P6-7 | Applied, except friend-target buffs and heals. For a class with no pack they have nothing to cast: `groupBuffs` and `hots` come from the pack (`Modules/Rotation/Engine.lua:1285`, `:1301`, `:1308`) and the heal from the pack's `heals` (`Modules/Rotation/Cast.lua:511-512`, `:607`). Listed under "does not get". Upheld in round 2. |
| P6-8 | Applied: order is rotation, pet, role and gear weights, classSpells, healer. |
| P6-9 | Applied: Travel Form, Tiger's Fury, Places.lua lines, the Settings.lua:615 check, the extra test files. |
| P6-10 | Applied: now in the evidence classes section. |

### Round 2 (revision 3)

| Finding | Result |
|---|---|
| P6r-1 | Applied: Druid stat weights and Druid talent point order are in "Unverified legacy data" as class B, authorship unrecorded. The Druid build is no longer treated as verified. |
| P6r-2 | Applied: one "Unverified legacy data" list with file and line for every item. No data changed. |
| P6r-3 | Applied: list order is class B, authored from tooltip cost, cooldown and damage with a provenance note, and open to correction by Flow's own fight records. A remembered rotation is not a source. |
| P6r-4 | Applied: a default role is class B. Until one is authored with a note, a new pack sets none. The engine's own "dps" fallback is listed as legacy. |
| P6r-5 | Not a document finding; settled by the dispatch (WOW-10): step 5 covers the player's own healing only. |
| P6r-6 | Applied: "the weight sum is 0", with the analyzer bonus named (`Modules/Gear/Score.lua:264`, `:270`). |
| P6r-7 | Applied: Cannibalize use is `Engine.lua:645-646`; Druid form keys are `Classes/Druid/Rotation.lua:306-314`; the queue lines are `Queue.lua:240-243` and `:244-246`. |
| P6r-8 | Applied by replacement: the allowed-source list is gone; class B of the evidence policy is the route for gear weights. |

## Limits of this inventory

- Read from source only. No claim here is about what the game does.
- Spell levels in the class packs are marked unverified by the packs themselves.
- Searches for missing features were by name. A feature under a name not searched for could have been missed.
