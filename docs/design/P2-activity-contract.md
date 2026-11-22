# P2: the shared activity contract (design)

Status: design only, no code. Written for WOW-2 on base `program-integ` a529eea (Flow 0.35.377).
File and line references are to that commit. The ones under "Checked by hand" in section 1.6
were re-read line by line; the rest come from a read-only mapping pass over the listed files
and should be re-checked by whoever builds each PR.

## 0. What this is for

Today the route has one list of steps, one plan and one chosen step, with a second, optional
lane bolted on for professions (the faint profession arrow). The goal of P2:

- A quest activity and a profession activity each keep **their own goal** and **their own
  selected step**. Picking a step in one never changes the other.
- They share **one reservation model** for items, bag slots and money, so nothing is counted
  twice: 12 Light Leather can't be "enough" for both a quest that wants 8 and a craft that
  wants 10.
- There is **no single global "current step"**. Anything that asks "what is the player doing
  here?" asks an activity, or asks which activity's step the player is standing at.

P5 (one arrow per activity, WOW-3) draws what this contract exposes: one selected step per
activity. P2 does not design frames.

Words: in player text a route entry is a *step*; in code it is a *goal* table
(docs/ARCHITECTURE.md "Words"). To keep the two apart, this document calls what an activity
is trying to reach its **aim** ("Leatherworking to 150", "the quests on your route") and
keeps *goal* for the code's step table.

## 1. Current state

### 1.1 Collect, split, plan, choose (Modules/Nav)

```
ns:Each("navGoal") sources                      (17 providers; Nav.lua N:Collect, gatherFrom)
   questie / pickups / errands / native  (Goals.lua)      skillplan (SkillPlan.lua:2136)
   merchant, banker, repair, hearth, mount, dungeon, party, partyhelp, questbuy, ...
        |
        v
N:Collect  ->  F.Filter (custom route)  ->  N.ResolveNeeds (Needs.lua:94)
        ->  money: N.CommitCosts(list, GetMoney())            (Nav.lua:577-609, Needs.lua:167)
        ->  N.FilterKinds (routeKind ticks)  ->  N.HoldCrafts
        ->  N.SplitProfessions(shown, profArrow on and no custom route)   (Nav.lua:719, 1278)
               |                                   |
          goals (file local, Nav.lua:458)     N.profGoals
               |                                   |
          choose(p): ns.planner:Plan(p, goals,     chooseProf(p): ns.planner.Plan(p, N.profGoals,
            N:Options())  -> N.plan                  N.TravelOptions()) -> N.profPlan  (Nav.lua:3577)
               |                                   |
          current / N.current (Nav.lua:459, 739)   N.profChoice (Nav.lua:4675)
```

- A step is a goal table: `key, points, text, kind, weight, optional, cost, blockedBy,
  anywhere, milestone, along, area, npcs, deps, needs, provides` (docs/ARCHITECTURE.md
  `navGoal` row) plus fields providers add (`provider`, `routeKind`, `prof`, `reagents`,
  `fetch`, `forQuest`, `keep`, `frees`, ...). Nothing on a goal says which activity it
  belongs to; `N.IsProfessionStop` (Nav.lua:729) decides from `provider` and `key`.
- The planner (Planner.lua) is already activity-neutral: `Plan(p, list, options)` is called
  once per lane with a different list and options.

### 1.2 State that is "the one current thing"

| State | Where | Written by | Read by |
|---|---|---|---|
| `goals` | Nav.lua:458, file local | end of `N:Collect` (:722) | `N:Goals()`, `choose`, `N:Options`, `PickupKeys` |
| `current`, `N.current` | Nav.lua:459, :739-740 | `update()` each tick from `choose(p)`, a followed party member or your own waypoint | Actions.lua:261 and :1110, BagIcons.lua:27, AreaHop.lua:190, MapFlights.lua:164 and :330, TaxiMark.lua:163 |
| `N.plan` | Nav.lua:3553 | `choose()` | the panel, Focus.lua:299, RouteTracker.lua:474, Menu.lua:628, Professions.lua:279, CraftHint.lua:220, Nearby.lua:196, SkillPlan.lua:694 |
| `N.selection = { first, tour }` | Nav.lua:3092-3102, :3197 | `N:Select`, cleared in `N:Options` | `N:Options`, Focus.lua:415 |
| `ns.db.nav.selectedKey` | per character (Nav.lua:4999) | `N:Select` (:3198) | restored on load (:5025) |
| `ns.db.nav.sorter` | shared | `N:Select` sets `"custom"` (:3202) | `update()` |
| `pinnedKey` | Nav.lua:460 | only ever set to nil (:3208, :3530) | :3528. Dead state. |
| `N.profGoals`, `N.profPlan`, `N.profChoice`, `N.profDirty`, `N.profPos` | Nav.lua:720, :3576-3597, :4675 | `N:Collect`, `chooseProf` | Actions.lua:265, CraftHint.lua:482, MapOverlay.lua:2036 |
| `N.moneyCommitted`, `ns.db.nav.deferred` | Nav.lua:584, :4998 | money block of `N:Collect` | `PLAYER_MONEY` handler (:4984) |

What the second lane lacks today:

- **No selection.** `N:Select` only knows the quest lane. `chooseProf` always takes
  `profPlan[1]`.
- **It is conditional.** It exists only while `nav.profArrow == true` and the `professions`
  kind is ticked (Nav.lua:739-742), not on a custom route (:719), and not when no quest step
  would be left (:1284). Otherwise profession steps sit in the quest lane and `N.current`
  can be a profession step.
- **"Standing at" is patched in one caller.** Actions.lua:259-268 swaps `N.profChoice` in
  for `N.current` when you stand at the profession step and not at the quest step. Every
  other reader of `N.current` sees only the quest lane.

### 1.3 Profession aims and "selected" state (Modules/Crafting, Professions.lua)

- Which professions: `ns:ProfessionPlan()` = `ns.db.prof.plan` or the class suggestion
  (Professions.lua:25-29), saved by the picker (:105-119).
- The aim per profession is derived on every collect: `SP:Targets()` (SkillPlan.lua:656-726)
  -> `{ [prof] = { target, quest, required, optional, zone, ahead } }`, kept in
  `SP.lastTargets`. Sources: a quest objective that names a skill, the pace for your level,
  the zone's gathering need. Craft professions hold a target with hysteresis in
  `ns.db.crafting.active[prof]` (:681, :713-721). The player cannot set a target or pick a
  recipe.
- `planProfession(prof, t, out)` (:1536) runs once per profession (:2150-2152) and emits
  steps keyed `train:`, `buy:`, `craft:<prof>:<recipe>`, `smelt:`, `bank:<prof>`, `farm:<id>`,
  `need:<id>`, `gather:<node>`, ... There is no aim object in the output; each step repeats
  `prof`, `target`, `rank`.
- Derived "what am I making" state, none of it saved: CraftHint `panel.goal` =
  `H.Pick(stops, N.profChoice, N.profPlan, N.plan)` (CraftHint.lua:56-68, :482), `made`,
  `announced`; CraftBar `batch`; `SP.lastStops`, `SP.lastWaiting`, `SP.lastUpgrades`,
  `SP.buyLater`.

### 1.4 Items, bag slots, money: who counts what

| Resource | Consumer | How it counts today |
|---|---|---|
| Items | Quest objectives | the quest log's own `have`/`need` (Goals.lua:206, :287); `Q.StillToGet(itemId, ns.api.Count(id))` (Goals.lua:337) |
| Items | One profession's plan | `SP.Stock(count, bankOf, smeltOf)` (SkillPlan.lua:1339-1382), created per profession (:1687). `Take` draws bags, then bank, then smeltable ore. "Shared by its steps so nothing is counted twice" holds inside that one plan only. |
| Items | A second profession's plan | its own `SP.Stock`, seeded again from the raw bag and bank counts. Two plans that emit the same key are merged, first one's counts kept (:2160-2162). |
| Items | CraftHint | a fresh `SP.Stock` (CraftHint.lua:90) |
| Items | The `need` kind `item` | presence only: `ns.api.Count(id) > 0` (Needs.lua:214) |
| Items | Keep or sell (`disposition` rules, Disposition.lua) | all-or-nothing per item ID: `questNeeds` (:390-397), `professionMaterial` (:414-469). No counts. Vendor, Banker and Posting act on whole stacks. `B.NeededBy` turns reagent counts into `true` (Banker.lua:102-116). |
| Bag slots | Vendor | its own `freeBagSlots()` (Vendor.lua:793-802): general bags only |
| Bag slots | Banker, QuestBags, Export | `X.BagsFree()` (Export.lua:94-103): all bags 0-4 |
| Bag slots | Profession steps (buy, bank fetch, farm, gather, craft) | not checked at all |
| Money | Steps with `goal.cost` | one pool: `N.CommitCosts(list, money)` (Needs.lua:167-184): milestones first, then cheapest, then key. It runs before the profession split, so both lanes already share it. |
| Money | Class training | its own `GetMoney` fit loop (Goals.lua:817-821); carries `cost` only when nothing fits (:848) |
| Money | Auto repair | `V.RepairDecision` on `GetMoney()` (Vendor.lua:549-583), blind to committed route money |
| Money | Trader | `T.Budget(GetMoney, share 0.25)` (Trader.lua:206, :288), blind to it too |
| Money | Mount | `cost` on its step; "save" advice only, nothing reserved |

So: money has a partial shared ledger, items have a private ledger per profession plan, and
bag slots have none. Mail is not counted anywhere.

### 1.5 Saved data (Core.lua)

- `FlowDB` (account) and `FlowCharDB` (character). `ns:PerCharacter(path, def)` registers
  `charData` (Core.lua:158); `SplitCharacterData` (:182-208) moves a path's value into
  `FlowCharDB.data[path]` and exposes it at `ns.db.<path>` while you play.
- `ns:Register("migration", key, { order, run = fn(db) })` exists (Core.lua:235-277):
  once per **account** (`FlowDB.migrations[key]`), after the per-character split, before
  any `OnLoad`. **Nothing registers one yet.** Shapes are upgraded today by `adopt`
  functions on `charData` and by ad hoc code in `OnLoad` (Nav.lua:5006-5025).
- Sections this design touches: `nav.selectedKey`, `nav.deferred`, `nav.focus` (per
  character); `nav.profArrow`, `nav.sorter`, `nav.kinds` (shared); `prof` (`plan`, `chosen`,
  `tierSeen`), `crafting` (`active`, recipes, `drops`), `bank` (all per character);
  `sell`, `banker`, `trader` (shared settings).

### 1.6 Checked by hand

Nav.lua:456-461, 714-724, 729-742, 1276-1292, 3092-3104, 3194-3208, 3576-3597, 4672-4677,
4995-5000, 575-586; Needs.lua:160-185; SkillPlan.lua:1336-1345, 1685-1688, 2146-2164;
Core.lua:235-277; Actions.lua:259-269; Goals.lua:838-850; the `pinnedKey` uses; that no
`Register("migration"` exists outside the Core.lua comment.

## 2. The contract

Three parts: an activity registry, per-activity lane state, and one reservation ledger.
Everything is a registration or a pure function, so it can be tested offline
(`tools/run-tests.ps1`).

### 2.1 `activity` registry

```lua
ns:Register("activity", "quest", {
    order = 100,                 -- lower claims a step first; "quest" is the catch-all, last
    label = "Quests",            -- the lane's name in player text
    owns = function(goal) return true end,
    aim = function() return nil end,
    options = function(travel) return ns.nav:Options() end,   -- first / tour / here / away
    selectable = true,
})

ns:Register("activity", "professions", {
    order = 50,
    label = "Professions",
    owns = function(goal) return ns.nav.IsProfessionStop(goal) end,
    -- What the activity is trying to reach, for its arrow, panel and "why".
    aim = function() return ns.skillPlan.Aims() end,
    options = function(travel) return travel end,            -- travel only, as chooseProf today
    -- Whether it has a lane of its own right now. False: its steps fall through to the
    -- next activity that owns them (today's "arrow off" behaviour).
    shown = function() return ns.nav:ProfPointerOn() end,
    selectable = true,
})
```

| Field | Type | Meaning |
|---|---|---|
| `order` | number | A step goes to the first activity, lowest `order`, whose `owns(goal)` is true and whose `shown()` is not false. |
| `label` | text | Player-facing name. |
| `owns` | `fn(goal) -> bool` | Pure. Must not read lane state. |
| `aim` | `fn() -> { { key, text, have, want, required } }` or nil | The activity's aims. Derived or saved; the activity decides. |
| `options` | `fn(travel) -> planner options` | What `Plan` gets besides the steps. |
| `shown` | `fn() -> bool`, default true | Has its own lane now. |
| `selectable` | bool | "Go here next" is offered on its steps. |
| `priority` | number, default = `order` | Its place when two activities claim the same resource (2.3). |

The contract allows any number of activities. P2 ships two, `quest` and `professions`,
because that is exactly today's split and keeps the first PRs free of behaviour change.
One activity per profession is open question Q1; the contract does not change if the
answer is yes, only the registrations do.

A step gets `goal.activity = <key>` when it is assigned, once per collect. Providers do not
set it and do not change.

### 2.2 Lane state: `ns.activities`

A new module (`Modules/Nav/Activities.lua`, listed in `Flow.toc` before `Nav.lua`'s users).

```lua
-- Pure
A.Of(goal, defs)            -> activity key
A.Split(list, defs)         -> { [key] = { goals } }, in one pass, order kept
-- Lane state, one table per activity, never shared
A:State(key) -> {
    goals,                  -- this activity's steps from the last collect
    plan, planAt, pos, dirty, version,
    choice,                 -- { goal, point, d } or nil: the step its arrow points at
    selection,              -- { first = step key, tour = { [key] = true } } or nil
}
A:Plan(key, p)              -- replans when dirty or moved (the rule chooseProf has today)
A:Choice(key)               -- its chosen step
A:Select(key, stepKey)      -- the player's pick, saved per character; nil clears
A:Each()                    -- activities that have steps, in order
A:At(p, near)               -- the choice the player is standing at, or nil
```

Rules:

1. **No global current step.** `N.current`, `N.plan`, `N.profPlan`, `N.profChoice` and
   `N.selection` stay for one release as read-only views (`N.current = A:Choice("quest")`
   and so on) so the 20-odd readers keep working, then callers move and the views go.
2. **A selection belongs to one activity.** `A:Select("professions", key)` never touches the
   quest lane's selection, sorter or custom route. `N:Select(key)` becomes
   `A:Select(A.Of(goal), key)` for callers that have only a key.
3. **Selecting never moves a step between activities.** Ownership comes from `owns`, not
   from what the player picked. (Today a profession step picked on a custom route joins the
   main arrow, Nav.lua:718. That special case goes: the pick lands in its own lane.)
4. **One answer to "which step am I at?"**: `A:At(p, near)` returns the choice whose step is
   within `near`; if several are, the one the player selected, then the nearest, then
   activity order. Actions.lua:259-268 becomes one call, and the bag marks, the craft hint
   and the taxi mark ask the same function instead of `N.current`.
5. **Follow and waypoint are overlays on the quest lane only**, as now (`ns.follow.Choice`,
   `N.WaypointChoice`). They are not activities: they have no steps to plan.
6. **Each activity plans its own steps only.** `deps` that point into another activity are
   kept as `after` information for display ("after: Buy Coarse Thread") but do not force the
   other lane's order. Cross-lane hard dependencies are listed in the other lane's "why".
7. **Empty lanes are skipped, not hidden steps.** If `shown()` is false, the steps fall
   through to the next owner. The rule "no quest step left: everything stays on the main
   arrow" (Nav.lua:1284) is kept as: a lane is only split off while the catch-all still has
   a step.

### 2.3 Reservations: `ns.reserve`

One ledger, rebuilt on every collect, pure: `R.Resolve(snapshot, claims, defs) -> grants`.

```lua
snapshot = {
    bags = fn(id) -> n,  bank = fn(id) -> n,     -- ns.api.Count, SP.BankCount
    money = copper,
    slots = freeGeneralSlots,
}
claim = {
    activity = "professions", step = "craft:Leatherworking:Light Armor Kit",
    res = "item", id = 2318, n = 10,
    bank = true,            -- may draw from the bank (SP.UseBank said so)
    required = true,        -- false: an optional upgrade; yields to every required claim
}
claim = { activity = "quest", step = "train:class", res = "money", n = 8000, milestone = true }
claim = { activity = "professions", step = "buy:2320", res = "slots", n = 1 }

grant = { claim = claim, got = 4, short = 6, from = { bags = 4, bank = 0 } }
```

Where claims come from:

- **From steps**, by a default reader, so providers need not change at first:
  `goal.cost` -> money; `goal.reagents` (craft, smelt) -> items; `goal.fetch` (bank) ->
  items from the bank plus slots; quest objective steps -> `min(have, need)` of their item;
  `buy:` / `need:` / `farm:` / `gather:` -> slots (one per item ID that has no partial stack
  in the bags). A step may carry `goal.claims` to say it exactly.
- **From things that are not steps**: `ns:Register("reserveSource", key, { claims =
  fn(snapshot) -> { claims } })`. First users: auto repair (the repair bill), the trader's
  share, the mount's "save from level" amount.

Resolution order, the same for all three resources, total and deterministic:

1. Claims of the step the player selected in its activity.
2. `required` before optional; for money, `milestone` first (keeps `CommitCosts` as it is).
3. Activity `priority`. Default: `quest` before `professions`. A quest turn-in can't be
   done with fewer, a craft can be made later.
4. For money only: cheaper first (again `CommitCosts`).
5. Step key, as the last tie-break.

Rules:

- **A unit is granted once.** `sum(got)` over all claims on an item never exceeds bags plus
  the bank share claimants may use; the same for copper and slots.
- **A short claim is a fact, not a failure.** The claimant plans for `short`: SkillPlan
  farms or buys 6, not 0. The quest objective keeps reading the game's own count, which is
  why quest claims go first: the game will take those items at turn-in whatever Flow thinks.
- **`SP.Stock` becomes a view of the ledger.** Its interface stays (`Avail`, `Take`, `Fork`).
  It is seeded with `R.BagsFor(activity)` / `R.BankFor(activity)` = the snapshot minus what
  earlier claimants hold, and all professions in one collect draw from one ledger, so
  `planProfession` calls no longer start from the full bags each. CraftHint.lua:90 reads
  the same view.
- **Money: one number for "free to spend".** `R.MoneyFree(activity)` = money minus grants
  that outrank the asker. `N.moneyCommitted` becomes `R.Committed("money")`.
  `V.RepairDecision` and `T.Budget` read it instead of `GetMoney()`.
- **Slots: one reader.** `R.FreeSlots()` replaces Vendor's `freeBagSlots()` and
  `X.BagsFree()` (they disagree today: general bags vs all bags). When slot claims exceed
  `free - ns.BAGS_NEARLY_FULL`, the sell or bank step stops being optional and the claiming
  steps get it as a dependency inside their own lane. Nothing is blocked on slots in P2.
- **Keep rules get counts last.** `R.Held(id)` is the total granted for an item. Until a
  product decision (Q4), `disposition` verdicts stay all-or-nothing and only *read* the
  ledger for their reason text ("8 for your quest, 4 for Leatherworking").
- **The ledger is never saved.** It is a function of the bags, the bank snapshot, money and
  the steps. `ns.db.nav.deferred` (steps waiting for money) stays as it is.

## 3. Saved data

Nothing a player has is dropped or rewritten in place.

| Today | After | How |
|---|---|---|
| `nav.selectedKey` (per character) | `activity.quest.selectedKey` | copied once per character; the old key is left, written through for one release, then removed by a later migration |
| `nav.profArrow` (shared setting) | unchanged; it is the `professions` activity's `shown()` | no migration |
| `nav.sorter`, `nav.focus`, `nav.focusKinds`, `nav.kinds` | unchanged, quest lane only | none |
| `crafting.active[prof]` | unchanged; read through `ns.skillPlan.Aims()` | none |
| `prof.plan`, `prof.chosen`, `prof.tierSeen`, `bank`, `nav.deferred` | unchanged | none |
| (new) `activity = { [key] = { selectedKey, aim } }` | per character: `ns:PerCharacter("activity")` | default `{}` |

`activity.<key>.aim` is reserved for a player-set target (Q3); nothing writes it in P2.

**Finding:** the migration registry runs once per account (`FlowDB.migrations`), but
`nav.selectedKey` is per character, so an account-scoped migration would convert only the
character that logs in first. Two ways:

- **Recommended:** add a character scope to the registry: `ns:Register("migration", key,
  { order, scope = "character", run = fn(db) })`, tracked in `FlowCharDB.migrations`, run
  by the same `ns:RunMigrations` (it already takes `db`, `fresh` and a list, so it stays
  pure and testable). This is the first real migration, so it also proves the registry.
- Quick alternative, named so it can be rejected: an `if db.activity.quest == nil then ...`
  in an `OnLoad`. That is the ad hoc pattern the comment at Core.lua:236 asks to stop.

A selected key whose step no longer exists is dropped at the next collect, as
`nav.selectedKey` is today.

## 4. Build order (small PRs, each behaviour-neutral unless it says otherwise)

| # | PR | Changes | Player sees |
|---|---|---|---|
| 1 | Character-scoped migrations | `Core.lua` `RunMigrations` scope; tests | nothing |
| 2 | `activity` registry | `Modules/Nav/Activities.lua`: `A.Of`, `A.Split`; register `quest`, `professions`; `N.SplitProfessions` delegates; ARCHITECTURE.md row | nothing |
| 3 | Lane state | `goals` / `plan` / `choice` / dirty flags move into `A:State`; `choose` and `chooseProf` become one function; `N.current` and friends become views; remove dead `pinnedKey` | nothing |
| 4 | `A:At` | Actions.lua:259-268, BagIcons.lua:27, CraftHint `H.Pick`, TaxiMark, MapFlights, AreaHop ask `A:At` or a named activity | the Flow key and bag marks agree when two steps are close |
| 5 | Per-activity selection | `A:Select`, `activity` saved section, the migration from PR 1, "Go here next" on profession steps, rule 3 of 2.2 | a profession step can be picked without changing the quest route |
| 6 | Ledger, pure | `Modules/Reserve.lua`: snapshot, default claim reader, `R.Resolve`; no callers | nothing |
| 7 | Money through the ledger | `N.CommitCosts` becomes the money pass (golden test: same `over` and `total` for the existing cases); `reserveSource` for repair and trader | auto repair and trades no longer spend money a route step was promised |
| 8 | Items through the ledger | `SP.Stock` seeded from the ledger; quest item claims; one ledger across professions; merged same-key steps sum their counts | "have enough" is right when a quest and a craft, or two professions, want the same item |
| 9 | Bag slots | `R.FreeSlots`; slot claims; sell or bank step ordered before steps that need room | a sell stop comes before a buy that wouldn't fit |
| 10 | Counts in keep rules | `disposition` reasons with counts; Vendor / Banker / Posting act on the surplus | only after Q4 is decided |

PRs 1-3 and 6 can be built in parallel. P5 (arrows) needs PR 3 for one choice per activity
and PR 5 for per-arrow selection; it does not need the ledger.

Each PR: tests as in section 5, lint at 0 warnings, CHANGELOG under `## Unreleased`, and
ARCHITECTURE.md when it adds a registry kind (`activity`, `reserveSource`).

## 5. Test obligations

Pure, so they must pass offline (`tools/run-tests.ps1`) as well as in game:

- `activity: a step goes to the first activity that owns it`; `...falls through when the
  lane is not shown`; `...the catch-all keeps every step no one claims`; `...nothing is
  split off when no quest step would be left`.
- `activity: selecting in one lane leaves the other lane's selection, plan and sorter alone`.
- `activity: At picks the selected step, then the nearest, then by order`.
- `activity: a pick whose step is gone is dropped`.
- `migration: a character-scoped migration runs once per character and never on a fresh
  install`; `migration: nav.selectedKey becomes the quest activity's pick`.
- `reserve: a unit is granted once` (property style: random claims, `sum(got) <= stock`
  for items, copper and slots).
- `reserve: quest 8 + craft 10 with 12 in the bags -> craft is 6 short`.
- `reserve: two professions wanting the same bars share one stock`.
- `reserve: the selected step's claims come first`; `...required before optional`.
- `reserve: money keeps CommitCosts' order` (the existing CommitCosts tests, unchanged
  expectations, run against the ledger).
- `reserve: repair is refused money a milestone step holds`.
- `reserve: bank stock is only granted to claims that may use the bank`.
- `reserve: free slots are counted the same for the vendor and the banker`.

Need the game (reported SKIP offline):

- `click:` tests for "Go here next" on a profession step and for clearing it.
- That the views (`N.current`, `N.plan`) still feed the panel, tracker and map (existing
  route tests, unchanged).
- No taint: tests stand in for Flow's own functions (the snapshot), never `GetMoney` or
  the bag API.

Performance: `R.Resolve` runs once per collect; add it to `/flow perf` as "reserve" and
keep it under the collect's per-frame budget (`collectSpread`).

## 6. Open product questions

1. **One profession activity or one per profession?** Per profession gives each its own
   selected step and, in P5, its own arrow (up to five lanes with the secondary
   professions). One for all is today's faint arrow. The contract supports both;
   recommended: start with one, split later if players ask.
2. **Who wins a shared item by default?** Recommended: quests, then professions, with the
   player's selected step above both. Should a player be able to flip it per item
   ("keep my leather for Leatherworking")?
3. **Can the player set a profession's target** (skill level or a recipe), or does it stay
   derived from pace and quests? A set target needs UI in Flow Professions and uses
   `activity.<key>.aim`.
4. **Counts in keep rules.** May Flow sell or bank the surplus of an item a quest or a
   craft needs some of? Today it keeps every stack.
5. **Does repair outrank route steps for money?** Recommended: repair first when gear is
   red, otherwise after milestone steps.
6. **Should the trader's share and the mount's saving reserve money**, or only advise, as
   now?
7. **With no quest step left**, do profession steps move to the main arrow (today), or
   does the quest lane stay empty and the profession arrow carry on?
8. **Mail.** Items in the mailbox are not counted anywhere. In scope for the ledger later?
9. **Party and dungeon routes** filter the quest lane only. Should a party's shared route
   ever carry profession steps?

## 7. Out of scope here, noted for the foreman

- docs/ARCHITECTURE.md's registry table lacks kinds the code uses: `disposition`,
  `migration`, `skillBooster`, `itemTip`, `setupItem`, `help`.
- CLAUDE.md says "there is no Lua interpreter"; docs/TESTING.md describes the offline
  runner.
