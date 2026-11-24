# Flow (WoW addon) architecture

Flow for WoW, not Flow Engine. The design rule is **open for extension, closed for modification**:
new classes, specs, fight types, metrics, advisors and gear considerations are added by
*registering* them from new files. The core and feature modules don't change.

## Words

Three words, each with one meaning, in the code's comments and in everything a player reads:

| Word | Means | Example |
|---|---|---|
| **step** | One thing your route has you do, usually at one place (it was "stop" until 0.35.251; code names such as `StopKind` still say so). Flow's own word, and the one to use for anything Flow plans, lists, counts or draws. | "Turn in: Plainstrider Menace", "Learn the flight path: Devrak", "Train 5 spells" |
| **objective** | The game's word: one line of a quest. Only ever said of a quest. An unfinished objective becomes a step; so do turn-ins, pickups, trainers and vendors, which are not objectives. | "0/7 Plainstrider Beak" |
| **waypoint** | A spot you set yourself. The arrow goes there first, and it isn't part of the planned route. | Ctrl + click on the map, `/flow way 52 30` |

So: "Steps", "Next step only", "All steps in this area", "30 steps"; never "objectives"
for those. In code a step is a *goal* (`navGoal` providers return goals; the planner puts them in
order): "goal" stays out of player-facing text.

## Registries

`Core.lua` provides three calls:

```lua
ns:Register(kind, key, value)   -- add an extension (keys are unique per kind)
ns:Get(kind, key)               -- look one up
for key, value in ns:Each(kind) do ... end   -- all of a kind, in load order
```

| Kind | Key | Value | Used by |
|---|---|---|---|
| `class` | class token, e.g. `PALADIN` | `{ specs, leveling, weights, weaponSpeed, proficiency }` | Spec advice, gear scoring |
| `classSpells` | class token | list of `{ level, spell, improves, note, needs, quest, questName }` | Advisor: "go train X"; `needs` = a spell it waits for (not counted as "to train" until you know it); `quest` = the class quest that teaches it |
| `rotation` | class token | `{ heals, priority, priorities = { [fightType] = list }, pullLock = fn(s, engine) -> spell, fightKeys = fn(engine) -> { ctrl = { spells }, alt = { spells } }, nextSwing = { spells }, shapeshifts = bool }` | Rotation engine. `nextSwing`: spells that wait for your next swing (Maul): the target button blinks red while one does (`E.UpdateQueued`, Display.lua). `shapeshifts`: Flow learns which spells take you out of a form and says so in their tooltips (`Modules/Rotation/FormSpells.lua`). `pullLock`: the spell the key holds for a fight. `fightKeys`: what Ctrl + key and Alt + key cast in a fight (the first you know, never the key's own; without it Ctrl takes the next attack in `priority`). They feed the target button's queue (`Modules/Rotation/Queue.lua`: `Q.Slots` decides the four slots, `Cast.lua` sets them on the secure button's "ctrl" / "heal" / "emerg" buttons with the `*` attribute prefix, `Display.lua` draws them) |
| `fightType` | e.g. `boss`, `aoe`, `elite`, `normal` | `{ order, label, match = fn(info) }` | Rotation (per-type lists), profiler |
| `metric` | e.g. `dps`, `hps`, `tps`, `dtps` | `{ label, role, higherBetter, value = fn(fight) }` | Profiler: what a "good fight" means per role |
| `fightProbe` | any | `{ start, tick, finish, events = { EVENT = fn(fight, ...) } }` | Profiler: what gets recorded per fight. `choices` (`Modules/Fight/Choices.lua`) sets each cast beside the target button's advice at that moment (`advice` / `key` / `own`), with the situation as tags (`C.Tags`) and the choice kept on its fight (`fight.own`), so `/flow choices` (and the diagnostics) show what you do differently, when, and what it did to kill speed (`C.Outcome`). Rotation rules are changed from that report, reason first |
| `advisor` | any | `{ check = fn() -> { {importance, text, improves}, ... } }` | Advice button, `/flow advice` |
| `gearAnalyzer` | any | `fn(item) -> bonus{dps,heal,tank}, notes` | Gear scores, quest reward badges |
| `profGuide` | profession name | `{ kind = "craft"|"gather", tool, steps = { {recipe, item, learn, yellow, green, grey, mats, station} }, nodes }` | Skill planner (`Modules/Crafting/SkillPlan.lua`) |
| `itemSource` | item ID | `{ name, gather, objects, node, skill, yield }` or `{ smelt = {from, n, skill} }` or `{ drops = {npc names} }` or `{ vendor = true }` | Skill planner: where materials come from |
| (perf) | `ns.perf.Wrap(name, fn)` | timed function | `/flow perf`, diagnostics snapshot |
| `weaponMaster` | NPC name | `{ skills = { [itemSubclassID] = true } }` | Weapon master steps when an upgrade needs a weapon skill (`Modules/Gear/WeaponSkills.lua`) |
| `routeObjective` | e.g. `xp`, `distance` | `{ label, tip, color, weigh = fn(goal, ctx) -> multiplier, keep = fn(goal, ctx) -> bool }` | What the route optimises (`Modules/Nav/XpValue.lua`); `/flow nav sort <key>` |
| `test` | "area: what it checks" | `fn(t)` with `t:ok`, `t:eq`, `t:near` | `/flow test`, diagnostics snapshot |
| `charData` | a path in `ns.db`: `"trainer"` or `"quests.notOffered"` | `{ adopt = fn(old, ctx) -> value, later = bool }`; register with `ns:PerCharacter(path, def)` | Per-character saved data (`Core.lua`): kept in `FlowCharDB`, at its usual place in `ns.db` while you play. `adopt` sorts data saved before the split (shared by all characters); `later` runs it at login as `adopt(old, ctx, current)`, `false` = try next login |
| `migration` | a name never reused or renamed, e.g. `0.36-nav-arrows` | `{ order, run = fn(db) }` | A change to the shape of saved data (`ns:RunMigrations`, `Core.lua`). Each runs once per account, in `order` then key, on `FlowDB` as saved, before any module's `OnLoad`; `FlowDB.migrations[key]` marks it done and `FlowDB.version` is the highest `order` applied. One that errors is logged, not marked, and tried again at the next load. A fresh install marks them all done without running any. None is registered today. |
| `mount` | race token, e.g. `Human` | `{ trainer, vendor, what }` NPC names | Mount milestone (`Modules/Nav/Mounts.lua`) |
| `sharedPlaces` | `community` | `{ npcs = { [name] = { id, map, x, y, roles = "vendor,repair", f = "H" | "A" | "AH" } }, mailboxes = { {map, x, y} } }` | NPC spots Flow players shared (`Learned/Places.lua`, written by `tools/share-places.ps1`; docs/SHARE-PLACES.md): route points and "Nearest ..." where you haven't been yourself |
| `mountRule` | `default` | `{ level, ridingCost, mountCost, saveFrom, classMount = { CLASS = spell } }` | Mount milestone: when to save, learn and buy |
| `action` | any | `{ order, get = fn(ctx) -> { type = "spell" or "item" or "interact" or "sit" or "wait", spell, item, targetSlot, icon, label, urgent, before } }` | Flow Actions: what the key does out of combat (`Modules/Rotation/Actions.lua`, `BuffItems.lua`). `urgent` shows ahead of the rotation's own suggestion |
| `status` | any | `{ order, get = fn() -> { icon, text, color, tip } or nil }` | Status icons in a row above the Flow key, between fights (`Modules/Rotation/Display.lua`): things to sort out, instead of chat lines. Turned off from the key's right-click menu |
| `navGoal` | any | `{ collect = fn() -> { {key, points, text, kind, weight, optional, cost, blockedBy, anywhere, milestone, along, area, npcs, deps, needs, provides}, ... } }` | Route: `cost` (copper) or `blockedBy` (text) keeps a step off the route but listed with its reason. `deps` (keys) must come first. `needs` / `provides` (tokens like `"spell:Bear Form"`, see `need`) are turned into `deps`, `after` or `blockedBy` before each plan (`Modules/Nav/Needs.lua`) |
| `routeKind` | any | `{ order, label, short, tip, default, match = fn(goal, yourLevel) -> bool }` | A kind of step you can tick in the route menu's "Route includes" (`Modules/Nav/Goals.lua` registers `quests`, `newQuests`, `lowQuests`, `training`, `professions`, `town`). A step takes the first kind that matches (lowest `order`); one no kind claims is always on the route. `N:Includes(key)`, `N:SetKind(key, on)`, `N.KindOf(goal)` in `Modules/Nav/Nav.lua`; a new `navGoal` source registers its own kind to get a tick |
| `activity` | lane name (`"quest"`, `"professions"`) | `{ order, label, owns = fn(goal, ctx), exists = fn(ctx), options = fn(travel) }` | Route (`Modules/Nav/Activities.lua`): whose step each route step is. Asked lowest `order` first; a step goes to the first activity that has a lane (`exists`, absent = always) and owns it; `"quest"` is asked last and owns the rest. `N:Collect` sets `goal.owner` (by definition) and `goal.activity` (the lane it is in) |
| `talentBuild` | class token (`DRUID`) | `{ name, role, trees = { names, left to right }, order = { { "Talent name", points, why = "..." }, ... } }` | Flow Talents (`Modules/Talents.lua`, `/flow talents`): the levelling build laid over the trees the game shows (`T.Read`), one point a level from 10. Talents go by their name in the game; `T.Check(build, nodes)` says what doesn't fit (a self-test runs it against the druid trees). Write a class's build from `/flow talents dump` (in the diagnostics: each talent's place, ranks, text and what it leads to) |
| `gameButton` | any | `{ order, frames = { "PlayerSpellsFrame.TalentsFrame", ... }, label = "Flow Talents", tip, click = fn, isOpen = fn, x, y }` | A small Flow button in the title bar of one of the game's own windows that opens the Flow view that goes with it (`Modules/GameButtons.lua`: talents, spellbook, professions, character). `frames`: the first that exists; dots walk into a window's parts, so a button can sit on one tab only. The button is a child of that frame (the game shows and hides it); Flow never touches the window itself. `/flow buttons` lists them and the windows they found; "Flow buttons on WoW's windows" in Flow Settings turns them off |
| `noAutoAttack` | an enemy's name | `{ why }` | An enemy the pull's "Start attacking" press is left out for (`E:EngageStep`, `Modules/Rotation/Engine.lua`): a boss whose shield hurts whoever hits it, one you mustn't wake. Everyone else: the first press at a new enemy, before the fight, turns auto attack on (the game's Start Attack), unless "Start auto attack at the pull" is off |
| `walledMap` | uiMapID | `{ why, lift = true }` | A map you can't walk into in a straight line: a city on a mesa or behind walls (`Modules/Nav/Gates.lua` registers the six capitals). A spot on it is its own region; into or out of it the arrow, the planner and the map's path go by a gate. A gate into one is learned only on the way in; with `lift = true` (Thunder Bluff) only when a lift carried you (you stood still as the map changed), not when the map flipped as you walked its rim |
| `navGate` | any | `{ cont, wx, wy, a = uiMapID, b = uiMapID }` | A way between two regions (a lift, a city gate, a pass between zones) shipped with Flow. The ones you walk through yourself are learned and saved (`ns.db.nav.gates`); `G.Via(a, b)` answers with the gates between two spots, the planner's `walk` option and `N.LegVia` use it. `/flow gates` |
| `travelSpell` | spell name | `{ map = uiMapID, class = "DRUID", from = "where you learn it" }` | A spell that takes you to a far zone (`Modules/Nav/TravelSpells.lua`: a druid's Teleport: Moonglade). A step on that map, while you're elsewhere and know the spell, is one cast away: the planner's `port` option counts it so, the arrow says "cast ...". One way only |
| `ride` | NPC name | `{ from = uiMapID, to = uiMapID, land = { x, y }, toName, class, faction, how = "he flies druids to Thunder Bluff, free" }` | Someone who carries you out of a far zone (`Modules/Nav/Rides.lua`: the druids' flight masters in Moonglade). While you're in `from` and the step is outside it, the leg costs: to the NPC, the flight, on from `land` (the planner's `ride` option), and the arrow leads to the NPC and names them. Where the NPC stands is looked up like any NPC's (`ns.places:Points`). `/flow rides`. |
| `innkeeper` | any | `{ name, id, town, inn, zone = GetZoneText(), city = true, also = { "a city's district" } }` | An inn for the route's "Set hearthstone" step (`Modules/Hearth.lua`). `H.Offer(here, home, yards)` decides: a city beats a village, a village near your city home isn't offered back. `H.BeforeTrips` makes a step that's a travel spell away wait for it. The game's own name for a home is learned when you set it at a listed innkeeper. |
| `bagMark` | any | `{ group = "action" or "kind", order, build = fn(parent) -> region, wants = fn(ctx) -> bool, paint = fn(region, ctx), x, y }` | A mark on a bag slot (`Modules/Items/BagIcons.lua`). The group decides the corner (`B.CORNER`): `action`, what Flow will do with the item (use it for your step, bank, sell, auction house, disenchant), top left; `kind`, what it is (a quest item, a profession's material), top right. In each corner the first mark (lowest `order`) whose `wants` is true shows. `ctx = { v = D:Decide's answer, id, focus, bank }` |
| `classReagent` | item name | `{ MAGE = true, PRIEST = true }` | A spell reagent and the classes whose spells use it (`Modules/Items/Disposition.lua`). In the bags of any other class it's sold (rule `otherClassReagent`, after the profession rules, so a reagent one of your recipes uses stays) |
| `need` | a token kind: `spell`, `level`, `quest`, `item` | `{ met = fn(arg) -> bool, label = fn(arg) -> text }` | Whether you meet a need like `"spell:Bear Form"` or `"level:20"`, and how to name it (`Modules/Nav/Needs.lua`). A step's unmet need goes after a step that `provides` it, or blocks it (hard) / only orders it (`{ token, soft = true }`) when nothing does |
| `needProvider` | any | `{ provides = fn(goal) -> { tokens } }` | What a step provides without saying so itself: `classQuest` says a class quest's turn-in teaches its spell (classSpells `quest = { ids }`, `questName`: Bear Form from "Body and Heart") |
| `questNeed` | quest ID | `{ where = "deep in Palemane Rock", note, tool = "Fishing", item = id }` | What's worth knowing before walking to a quest's giver, which Questie doesn't say (`Modules/Quests/QuestNeeds.lua`): `where` and `note` go on its pickup step; `tool`/`item` (what the giver wants you to carry first) keep the pickup waiting, with that reason, until you have it. Escort quests get their own note from Questie's data, no entry needed |

Events: `ns:On(event, fn)`. Saved data ready: `ns:OnLoad(fn(db))`. Slash subcommands:
`ns.commands.name = fn(args)` gives `/flow name`.

## Adding a class

1. Create `Classes/<Class>/` with:
   - `Data.lua`: `ns:Register("class", "<TOKEN>", {...})` with specs, levelling recommendation,
     stat weights per role, weapon speed preference, armor/weapon proficiency.
   - `Spells.lua`: `ns:Register("classSpells", "<TOKEN>", {...})`.
   - `Rotation.lua`: `ns:Register("rotation", "<TOKEN>", {...})`.
2. List the files in `Flow.toc` under "Classes".

The TOC listing is the only shared file a new class touches. WoW loads only the files the
TOC lists, so that one line is unavoidable.

## How the pieces connect

```
Tracker (damage taken, target TTD, heal sizes)        FightTypes (boss/aoe/elite/normal)
        \                                                   |
         Rotation Engine --- picks next spell <-------------+
            | E.current                                      |
            v                                                v
         Display (icon + button glow)              Profiler (records fights via probes,
                                                    compares best vs worst, learns "bias")
                                                            |
            Engine uses bias to order `adaptive` rules <----+
                                                            |
Advisor <--- trainer data, class spells, bags, skills, talents, profiler insights
```

### Route weights

The planner (`Modules/Nav/Planner.lua`) minimises sum(distance x weight). A step's weight is
set when the route is collected: by the step itself (`navGoal`) and by the route objective
(`routeObjective`, `Modules/Nav/XpValue.lua`). `Modules/Nav/NearFirst.lua` adds a weight that
depends on where you stand, so it is applied on every plan, not at collect: steps beyond 300 yd
get up to 3x heavier, item drops not within 150 yd 1.5x more, milestones are left alone. The
goals get their own weights back after each plan. `/flow nearfirst on|off`. Not on the
"Shortest" objective (or with low-level quests ticked, which plans by distance): that stays the
shortest path.

### Route refresh

A refresh reads one `navGoal` source per frame, then plans in the next (`collectSpread` in
`Modules/Nav/Nav.lua`), so no frame does all of it. The new steps replace the old in one step at
the end. A change that arrives while it gathers, or a direct `N:Collect()`, makes it go once more.

### Dungeon runs

`Modules/Nav/Dungeons.lua` (needs Questie, read at runtime: nothing is copied into the repo)
indexes each dungeon's quests in the background, a few per frame and never in combat. `D:Runs()`
cuts them into runs (one wing, your level, one trip) and compares each with your questing XP per
hour; it's timed in `/flow perf` as "dungeon runs". A prepared run is a `navGoal` source
("dungeon"): its pickups and lead-ins (only those you can take now, `ns.quests:Available`), then
the entrance. Inside, `D:FilterInside` keeps only that dungeon's quests, your waypoint and the
party route. A gold key badge atop your quest list (Questie's tracker, else the Flow Tracker) suggests the best run (`D.KeyStatus`).

### UI helpers

- `ns:MakeMovable(frame, save)` (`Core.lua`): Ctrl-drag for ordinary panels (`ns.MoveKeyDown`: the one place that says which key moves things).
- `ns:MoveHandle(button, opts)` (`Modules/MoveHandle.lua`): for secure buttons (the Flow key),
  which can't be dragged themselves or moved in a fight: a handle over the button while Ctrl is
  held, out of combat; drag to move, mouse wheel to resize. `ns.RestorePlace` puts it back.
- `ns.copyBox:Show(title, lines)` (`Modules/CopyBox.lua`): the Flow Copy window, text selected
  for Ctrl+C. Everything `ns:Print` says is kept for `/flow copy`.

### Rotation adaptation (and its limits)

- Rules marked `adaptive = true` that sit next to each other form a group of roughly equal
  options. The engine picks the ready one with the highest learned bias for the current fight
  type. Ties keep the written order.
- Bias comes from comparing casts per minute in the best third and worst third of comparable
  fights. "Comparable" means the same fight type and role, at least 6 seconds long, and within
  3 levels of you. Learning starts after 6 such fights.
- This is correlation, not proof. That's why it only reorders options the rotation author
  marked as interchangeable; it never adds spells or overrides heals and buffs.
- Each role has its own "good fight" metric: DPS for dps, HPS for heal, threat per second for
  tank (if the client exposes threat).

## Quest data

`Modules/Quests/QuestData.lua`, registry kind `questSource`

`Modules/Gear/KeepSets.lua` (`ns.keepSets`): the "Keep set for" row on the bag windows. `K.Keeps(role)`
(per character, `ns.db.gear.keepSet`) is asked by the `inSet` and `laterOrOtherRole` disposition rules and the
item tooltip; `K:Build(role)` makes the game's equipment set for a role (puts on what's better from the bags,
saves, switches back).

`Modules/Items/Trader.lua` (`ns.trader`, the Flow Trader view): Auction.lua's full read hands it every listing
(`T.ReadStart` / `T.ReadListing` / `T.ReadDone`); `T.Listing` and `T.Deals` (pure) find listings under the vendor's
price or at half the item's usual price (`T.Usual`, from the price history). A purchase is a job of clicks:
search, `T.Pick` (what's still within the limit and the budget), then the game's own purchase calls.

`Modules/Gear/SetRecipes.lua` (`ns.setRecipes`, registry `gearSet`): `{ name, icon, what, offer(), wants() }`, a gear set
Flow can build: `SR.Build(key)` puts the wanted links on, saves the game's equipment set under that name and icon, and
switches back. `SR.IconFor(name, game)` is the picture a set shows (yours, the default, the game's). `SR.DefaultFor(name)` is the
default for sets of that name: the one the player set (`ns.db.gear.setDefault`, shared), its recipe's, its spec's;
`SR.SetDefault` / `SR.Reset` are the menu's "Make this the default" / "Reset to the default".
`Modules/Gear/SetIcons.lua` draws the sets on the bag window; `Modules/Gear/KeepSets.lua` builds the specs' sets.

`Modules/Nav/Crossings.lua` (`ns.crossings`, registry `crossing`): `{ how, faction, a = { name, place, map, x, y }, b = ... }`,
a zeppelin or boat between two continents. Its `navGoal` gives one step a continent where steps of yours wait
(`C.Waiting`, `C.Best`: shortest from you to the boarding place plus from the landing to the nearest of them);
`C.Learn` corrects both ends from a real trip (`ns.db.nav.crossingEnds`).

A `routeKind` may say what it does on a custom route (`custom`): `"lines"` for the quest kinds (the picked lines stand in
for them), `false` for a kind that starts unticked there (professions), nothing for an errand that starts ticked. While a
custom route is on, `N:Includes` / `N:SetKind` / `N:SetAllKinds` read and write the custom route's own ticks
(`ns.db.nav.focusKinds`, `F.KindOn`) for the other kinds, and `F.Filter` keeps those steps beside the lines' (`F.Errand`).

`Modules/Nav/Focus.lua` (`ns.focus`): a custom route's quest lines (`ns.db.nav.focus`, per character). `F.Line`
(pure) turns a picked quest into its chain: what's undone before it, what the data chains after it, and on to the
quest that teaches a class spell. `F.Filter` (called as Nav gathers steps) keeps only the lines' steps and adds the
line's next pickup. `N:Select` is wrapped to add a line; `F.MenuItems(goal)` gives the remove entries.

`Modules/Nav/Legs.lua` (`ns.legs`): times each trip between two steps (`L.Look`, pure, a look a second) and
keeps the quickest by pair of 40-yard squares (`ns.db.nav.legs`, shared by your characters). The planner's
`legs` option (`L.Yards`) answers "exact" (the cost) or "area" (stretches the straight line).
[FLOW-GRAPH.md](FLOW-GRAPH.md) is the plan for sharing them and for a whole-game order.

`Modules/Quests/QuestBags.lua` (`ns.questBags`): sorts every quest thing in the bags into hand in / sell /
bank / finish / stuck (`QG.Plan`, pure). `QG.MarkTurnIn` (called from Goals.lua) sets `goal.frees`, and with
nearly full bags `goal.keep` (the planner never cuts it as too far) and a low weight. `QG.Waits()` and
`QG.NeededHere(id)` tell Flow Banker what to put away and what to take back out.

`Modules/Quests/QuestBuy.lua` (`ns.questBuy`, navGoal `questbuy`): an optional "buy" step at an
auctioneer for each item objective in your log that Flow has an auction price for (`qbuy:<quest>:<objective>`,
with `cost`); the price is the test that the item can be bought. Setting `ns.db.nav.questBuy`.

(`{ order, label, available, get, allIds, doable }`).

- **native** (always): the game API, for completed quests and your quest log.
- **questie** (optional): reads Questie + QuestieDB at runtime if you have them installed.
  They support Forever's classic content. **Never copy their data into this repo:** they have
  no clean licence (treat as all rights reserved). Reading them at runtime as an optional
  dependency is fine, and other guide addons such as Guidelime do the same.
- **LibQuestDB-1.0** (MIT, covers some Forever-only quests): placeholder until its API is
  confirmed in game.
- Route files from RestedXP (CC BY-NC-SA), Guidelime (all rights reserved) and similar guides
  can't be bundled either. They're for reference only, or for reading at runtime if you have
  that addon installed.
- **Boss loot table** (lead DISPATCH 426): `ZFlow/Nav/BossLootData.lua` is the one shipped table made
  from someone else's work. It holds which items each dungeon and raid boss can drop, as ids only
  (instance, area, encounter, creature, item), made by `tools/zflow-boss-loot.ps1` from a local
  checkout of AllTheThings (MIT). The MIT notice is in `THIRD_PARTY.md`; the checkout is never
  committed. `ZFlow/Nav/DungeonRead.lua` `R.Loot` reads the table first, then the client's dungeon
  journal if it answers, then Questie; your own kills only mark a drop as seen.
- Flow is licensed under the GPLv3 (`LICENSE`). The repo holds no third-party quest, route or
  recipe data and no route text; the only third-party data is the MIT-licensed id table above,
  listed in `THIRD_PARTY.md`. Anything added later must have a licence that allows it and a notice
  there.

Missed quests today: doable quests in zones you've already completed quests in, that you
haven't done and aren't on. **Next step:** route steps (quest ID, NPC, coordinates) so it can
say "you passed this step without picking up X". Also a "learn" mode that records quest
givers from `QUEST_ACCEPTED`, for Forever-only quests that no database covers yet.

## Placeholders to grow into

- `gearAnalyzer`s: sockets, set bonuses, equip effects, enchants, armor type, resistances,
  unique, combos, and valuing weapon speed (see `docs/GEAR_PLAN.md`).
- Per-fight-type rotation lists for boss/elite once there's data showing they should differ.
