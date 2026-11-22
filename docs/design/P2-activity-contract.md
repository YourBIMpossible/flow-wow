# P2: the shared activity contract (design)

Status: design only, no code. Written for WOW-2 on base `program-integ` a529eea (Flow 0.35.377)
and revised for WOW-5 after the lead review (findings P2-1 to P2-12; section 9 says where each
one landed). File and line references are to a529eea. The ones under "Checked by hand" in
section 1.7 were re-read line by line; the rest come from a read-only mapping pass over the
listed files and should be re-checked by whoever builds each PR. Nothing here is tested in
game.

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

P5 (one arrow per activity, stacked or separated, WOW-3) draws what this contract exposes.
Section 6 lists what P5 needs from it. P2 does not design frames.

Words: in player text a route entry is a *step*; in code it is a *goal* table
(docs/ARCHITECTURE.md "Words"). To keep the two apart, this document calls what an activity
is trying to reach its **aim** ("Leatherworking to 150", "the quests on your route") and
keeps *goal* for the code's step table. A **lane** is one activity's steps, plan and choice.

## 1. Current state

### 1.1 Gather, collect, split, plan, choose (Modules/Nav)

```
collectSpread (Nav.lua:4927-4950): one navGoal source per frame, in ns:Each("navGoal") order
   questie / pickups / errands / native  (Goals.lua)      skillplan (SkillPlan.lua:2136)
   merchant, banker, repair, hearth, mount, dungeon, party, partyhelp, questbuy, ...
   (17 providers. Each provider's collect() runs here, BEFORE N:Collect: SkillPlan has
    already decided its steps, and read its stock, by the time the list is collected.)
        |
        v
N:Collect(list), in this order:
   N.FilterKinds (routeKind ticks)                         Nav.lua:549
   ns.dungeons:FilterOnly ("only the dungeon run")          :556
   ns.focus.Filter (custom route)                           :558-562
   N.ResolveNeeds (Needs.lua:94)                            :565-567
   money: N.CommitCosts(list, GetMoney())                   :577-609  -> N.blockedGoals (:610)
   hidden steps set apart                                   :622-625  -> N.hiddenGoals
   "along the way" steps set apart                          :698-702  -> N.alongGoals
   ns.xpValue.Apply (route objective)                       :708
   N.HoldCrafts                                             :714
   N.SplitProfessions(shown, profArrow on and not (custom route active and not idle))  :719
               |                                   |
          goals (file local, Nav.lua:458)     N.profGoals (:720)
               |                                   |
          choose(p) (:3522): ns.planner:Plan(p,     chooseProf(p) (:3577): ns.planner.Plan(p,
            goals, N:Options()), or the party's       N.profGoals, N.TravelOptions())
            shared plan (:3542-3545) -> N.plan        -> N.profPlan
               |                                   |
          update(): choose(p), then a followed     N.profChoice (:4675)
          party member, then your waypoint
          -> current / N.current (:4736-4740)
```

- A step is a goal table: `key, points, text, kind, weight, optional, cost, blockedBy,
  anywhere, milestone, along, area, npcs, deps, needs, provides` (docs/ARCHITECTURE.md
  `navGoal` row) plus fields providers add (`provider`, `routeKind`, `prof`, `reagents`,
  `fetch`, `forQuest`, `keep`, `frees`, ...). Nothing on a goal says which activity it
  belongs to; `N.IsProfessionStop` (Nav.lua:729-733) decides from `provider` and `key`.
- `N.blockedGoals`, `N.hiddenGoals` and `N.alongGoals` are set apart before the split, so
  they belong to no lane.
- The planner (Planner.lua) is already activity-neutral: `Plan(p, list, options)` is called
  once per lane with a different list and options.
- `choose` carries more than a plan: the party's shared plan and its publishing
  (:3542-3548), a fallback to the nearest step with a sticky rule when there is no plan
  (:3558-3570), and the dead `pinnedKey` branch (:3528-3531). `update()` then lays the follow
  and waypoint overlays over its answer (:4738), and a corpse run replaces the arrow and
  hides the profession arrow (:4731-4734).

### 1.2 State that is "the one current thing"

| State | Where | Written by | Read by |
|---|---|---|---|
| `goals` | Nav.lua:458, file local | end of `N:Collect` (:722) | `choose`, `N:Options`, `PickupKeys`, and through `N:Goals()` (:1436) the ten outside readers in 1.3 |
| `current`, `N.current` | Nav.lua:459, :4739-4740 | `update()` each tick: `choose(p)`, overridden by a followed party member or your own waypoint (:4738) | Actions.lua:261 and :1110, BagIcons.lua:27, AreaHop.lua:190, MapFlights.lua:164 and :330, TaxiMark.lua:163 |
| `N.plan` | Nav.lua:3553 | `choose()` | 26 read sites outside Nav.lua in 17 files (1.3) |
| `N.selection = { first, tour }` | Nav.lua:3092-3102, :3197 | `N:Select`, cleared in `N:Options` | `N:Options`, Focus.lua:415, MapOverlay.lua:435 |
| `ns.db.nav.selectedKey` | per character (Nav.lua:4999) | `N:Select` (:3198) | restored on load (:5025) |
| `ns.db.nav.sorter` | shared | `N:Select` sets `"custom"` (:3202); `F.AddKey` too (Focus.lua:331) | `update()` |
| `pinnedKey` | Nav.lua:460 | only ever set to nil (:3208, :3530) | :3528. Dead state. |
| `N.profGoals`, `N.profPlan`, `N.profChoice`, `N.profDirty`, `N.profPos` | Nav.lua:720, :3576-3597, :4675 | `N:Collect`, `chooseProf` | Actions.lua:265, CraftHint.lua:56-61 and :482, MapOverlay.lua:1028-1063 and :2036 |
| `N.planVersion` | Nav.lua:3104, :3551 | `choose()` on each new plan | polled by Nav.lua:3461 and RouteTracker.lua:608. There is no profession-lane counterpart. |
| `route` (the travel path the arrow follows) | Nav.lua:461, :3750 | the leg builder, for the main arrow's step only | Nav.lua |
| `N.moneyCommitted`, `ns.db.nav.deferred` | Nav.lua:584, :4998 | money block of `N:Collect` | `PLAYER_MONEY` handler (:4984) |

What the second lane lacks today:

- **No selection.** `N:Select` only knows the quest lane. `chooseProf` always takes
  `profPlan[1]`.
- **A pick would destroy it.** Focus.lua:536-554 wraps `N:Select`: every pick (except while
  following a party, and `cross:` keys) calls `F.AddKey` (:319-331), which adds a custom
  route line and sets `nav.sorter = "custom"`. A custom route that is active and not idle
  turns the split off (Nav.lua:719). So a profession step picked through `N:Select` today
  deletes its own lane.
- **It is conditional.** It exists only while `nav.profArrow == true` and the `professions`
  kind is ticked (Nav.lua:739-742), not on an active custom route (:719), and not when no
  quest step would be left (:1284). Otherwise profession steps sit in the quest lane and
  `N.current` can be a profession step. Lane existence and arrow display are one setting.
- **"Standing at" is patched in one caller.** Actions.lua:259-268 swaps `N.profChoice` in
  for `N.current` when you stand at the profession step and not at the quest step. Every
  other reader of `N.current` sees only the main arrow's target.

### 1.3 Who reads the step list and the plan from outside Nav.lua

`N:Goals()` returns the quest lane only once the arrow is on. Its outside readers:

| Reader | What it does with the list | Sees the profession lane today (arrow on)? |
|---|---|---|
| Banker.lua:123 (`B.NeededBy`; also reads blocked and hidden) | which items steps need, so the bank keeps or hands them out | no |
| Banker.lua:240 (`B.FetchBy`) | what to take out of the bank for a step's `fetch` | no; the `bank:<prof>` step is a profession step |
| Trader.lua:171 (`T.RouteNeeds`) | what the route needs, to buy from a trade | no |
| Professions.lua:282 | the profession panel's steps | no |
| QuestBags.lua:309 (also blocked and hidden) | bag advice for steps | no |
| Advisor.lua:388 (`Adv.FindGoal`, also blocked and hidden) | find a step by key | no |
| Export.lua:183 | the diagnostics export | no |
| Crossings.lua:208 (also blocked and custom-route lines) | which steps need a crossing | no |
| Party.lua:269 | the shared party route | no (wanted: quest lane only) |
| MapOverlay.lua:1102 (`ns.dungeons.AwayGoals`) | steps away from a dungeon run | no (wanted: quest lane only) |

`N.plan` is read at 26 sites outside Nav.lua: MapOverlay.lua (6), CraftHint.lua (2),
Export.lua (2), AreaHop.lua (2), Leaving.lua (2), and one each in Nearby.lua, SkillPlan.lua,
Menu.lua, Focus.lua, Legs.lua, MapFlights.lua, PartyHelp.lua, RouteTracker.lua,
Professions.lua, QuestMarks.lua, Actions.lua and Splash.lua.

### 1.4 Profession aims and "selected" state (Modules/Crafting, Professions.lua)

- Which professions: `ns:ProfessionPlan()` = `ns.db.prof.plan` or the class suggestion
  (Professions.lua:25-29), saved by the picker (:105-119).
- The aim per profession is derived on every collect: `SP:Targets()` (SkillPlan.lua:656-726)
  -> `{ [prof] = { target, quest, required, optional, zone, ahead } }`, kept in
  `SP.lastTargets`. Sources: a quest objective that names a skill (`required = true`,
  :663-668), the pace for your level, the zone's gathering need. Craft professions hold a
  target with hysteresis in `ns.db.crafting.active[prof]` (:681, :713-721). The player
  cannot set a target or pick a recipe.
- A skill a quest asks for keeps its step with Professions off, names the quest
  (`forQuest`) and counts under the "quests" route kind (SkillPlan.lua:657-660,
  Goals.lua:956). But `N.IsProfessionStop` (Nav.lua:729-733) does not look at `forQuest`,
  so with the arrow on that step still goes to the profession lane.
- `planProfession(prof, t, out)` (:1536) runs once per profession, in `pairs` order
  (:2150-2152), which is not fixed. It emits steps keyed `train:`, `buy:`,
  `craft:<prof>:<recipe>`, `smelt:`, `bank:<prof>`, `farm:<id>`, `need:<id>`,
  `gather:<node>`, ... There is no aim object in the output; each step repeats `prof`,
  `target`, `rank`.
- Derived "what am I making" state, none of it saved: CraftHint `panel.goal` =
  `H.Pick(stops, N.profChoice, N.profPlan, N.plan)` (CraftHint.lua:56-68, :482), `made`,
  `announced`; CraftBar `batch`; `SP.lastStops`, `SP.lastWaiting`, `SP.lastUpgrades`,
  `SP.buyLater`.

### 1.5 Items, bag slots, money: who counts what

| Resource | Consumer | How it counts today |
|---|---|---|
| Items | Quest objectives | the quest log's own `have`/`need` (Goals.lua:206, :287); `Q.StillToGet(itemId, ns.api.Count(id))` (Goals.lua:337) |
| Items | One profession's plan | `SP.Stock(count, bankOf, smeltOf)` (SkillPlan.lua:1339-1382), created per profession (:1687), inside the provider. `Take` draws bags, then bank, then smeltable ore. "Shared by its steps so nothing is counted twice" holds inside that one plan only. |
| Items | A second profession's plan | its own `SP.Stock`, seeded again from the raw bag and bank counts. Two plans that emit the same key are merged, first one's counts kept (:2160-2162). |
| Items | CraftHint | a fresh `SP.Stock` (CraftHint.lua:90) |
| Items | The `need` kind `item` | presence only: `ns.api.Count(id) > 0` (Needs.lua:214) |
| Items | Keep or sell (`disposition` rules, Disposition.lua) | all-or-nothing per item ID: `questNeeds` (:390-397), `professionMaterial` (:433-469). No counts. Vendor, Banker and Posting act on whole stacks. `B.NeededBy` turns reagent counts into `true` (Banker.lua:102-116). |
| Bag slots | Vendor | `freeBagSlots()` (Vendor.lua:793-802): bags 0-4 whose bag type is 0 (general); 99 when the API is missing |
| Bag slots | Banker, QuestBags, Export | `X.BagsFree()` (Export.lua:94-103): every bag 0-4, whatever its type; nil when the API is missing |
| Bag slots | Flow Actions | `freeSlots()` (Actions.lua:678-685): every bag 0-4; 99 when the API is missing |
| Bag slots | Profession steps (buy, bank fetch, farm, gather, craft) | not checked at all |
| Money | Steps with `goal.cost` | one pool: `N.CommitCosts(list, money)` (Needs.lua:167-184): milestones first, then cheapest, then key. It runs before the profession split, so both lanes already share it. |
| Money | Class training | its own `GetMoney` fit loop (Goals.lua:817-821); carries `cost` only when nothing fits (:848) |
| Money | Auto repair | `V.RepairDecision` on `GetMoney()` (Vendor.lua:549-583), blind to committed route money |
| Money | Trader | `T.Budget(GetMoney, share 0.25)` (Trader.lua:206, :288), blind to it too |
| Money | Mount | `cost` on its step; "save" advice only, nothing reserved |

So: money has a partial shared ledger, items have a private ledger per profession plan, and
bag slots have none (three readers, two meanings). Mail is not counted anywhere.

### 1.6 Saved data (Core.lua)

- `FlowDB` (account) and `FlowCharDB` (character). `ns:PerCharacter(path, def)` registers
  `charData` (Core.lua:158-160). `def` is a definition, `{ adopt, later, once }`, not a
  default value; the default comes from the module's own `ns:OnLoad`.
  `SplitCharacterData` (:182-208) moves a path's value into `FlowCharDB.data[path]` and
  exposes it at `ns.db.<path>` while you play.
- `ns:Register("migration", key, { order, run = fn(db) })` exists (Core.lua:235-277):
  once per **account** (`FlowDB.migrations[key]`), after the per-character split, before
  any `OnLoad`; "fresh" is account-level too (`ns.freshInstall`, :287). **Nothing registers
  one yet.** Shapes are upgraded today by `adopt` functions on `charData` and by ad hoc
  code in `OnLoad` (Nav.lua:5006-5025).
- Sections this design touches: `nav.selectedKey`, `nav.deferred`, `nav.focus` (per
  character); `nav.profArrow`, `nav.sorter`, `nav.kinds`, `nav.point` (shared); `prof`
  (`plan`, `chosen`, `tierSeen`), `crafting` (`active`, recipes, `drops`), `bank` (all per
  character); `sell`, `banker`, `trader` (shared settings).

### 1.7 Checked by hand

For WOW-2: Nav.lua:456-461, 575-586, 714-724, 729-742, 1276-1292, 3092-3104, 3194-3208,
3576-3597, 4672-4677, 4995-5000; Needs.lua:160-185; SkillPlan.lua:1336-1345, 1685-1688,
2146-2164; Core.lua:235-277; Actions.lua:259-269; Goals.lua:838-850; the `pinnedKey` uses;
that no `Register("migration"` exists outside the Core.lua comment.

For WOW-5 (each line the review cites): Nav.lua:545-568, 606-612, 622-626, 698-712,
1434-1438, 3520-3572, 4730-4742, 4920-4950; Focus.lua:316-332, 534-556; Core.lua:156-160,
284-296; SkillPlan.lua:655-668; Actions.lua:674-688; Disposition.lua:431-436;
Vendor.lua:793-802; Export.lua:94-103; Goals.lua:956; every `N:Goals()` call and every
`N.plan` / `N.selection` / `N.prof*` read outside Nav.lua (by grep, tests left out).

## 2. The contract

Three parts: an activity registry, per-activity lane state, and one reservation ledger.
Everything is a registration or a pure function, so it can be tested offline
(`tools/run-tests.ps1`).

### 2.1 `activity` registry

```lua
ns:Register("activity", "quest", {
    order = 100,                 -- lower claims a step first; "quest" is the catch-all, last
    label = "Quests",            -- the lane's name in player text
    owns = function(goal, ctx) return true end,
    aim = function() return nil end,
    options = function(travel) return ns.nav:Options() end,   -- first / tour / here / away
    selectable = true,
})

ns:Register("activity", "professions", {
    order = 50,
    label = "Professions",
    -- ctx.customKeys: the step keys that are lines of the custom route (they stay with it)
    owns = function(goal, ctx)
        return ns.nav.IsProfessionStop(goal) and not ctx.customKeys[goal.key]
    end,
    aim = function() return ns.skillPlan.Aims() end,
    options = function(travel) return travel end,            -- travel only, as chooseProf today
    -- Whether this activity has a lane of its own right now. False: its steps fall
    -- through to the next activity that owns them. NOT whether an arrow is drawn (6.1).
    exists = function(ctx) return ns.nav:ProfLaneOn() end,
    selectable = true,
})
```

| Field | Type | Meaning |
|---|---|---|
| `order` | number | A step goes to the first activity, lowest `order`, whose `exists(ctx)` is not false and whose `owns(goal, ctx)` is true. |
| `label` | text | Player-facing name. |
| `owns` | `fn(goal, ctx) -> bool` | Pure: decides from the goal and `ctx` only. Must not read lane state. |
| `aim` | `fn() -> { { key, text, have, want, required } }` or nil | The activity's aims. Derived or saved; the activity decides. |
| `options` | `fn(travel) -> planner options` | What `Plan` gets besides the steps. |
| `exists` | `fn(ctx) -> bool`, default true | The activity has a lane now. Separate from display. |
| `selectable` | bool | "Go here next" is offered on its steps. |
| `priority` | number, default = `order` | Its place when two activities claim the same resource (2.4). |

`ctx` is built once per collect: `{ customKeys, level, includes = fn(kind) }`.

The contract allows any number of activities. P2 ships two, `quest` and `professions`,
because that is exactly today's split and keeps the first PRs free of behaviour change.
One activity per profession is open question Q1; the contract does not change if the
answer is yes, only the registrations do.

**When a step is assigned.** `goal.activity = <key>` is set once per collect, right after
`N.FilterKinds` (Nav.lua:549), before the blocked, hidden and along steps are set apart.
So `N.blockedGoals`, `N.hiddenGoals` and `N.alongGoals` stay single lists, but every step
in them says which lane it belongs to. Providers do not set it and do not change.

**The split condition, redefined (Nav.lua:719).** Today: arrow on, and not on an active
custom route. New: the `professions` lane exists whenever `exists(ctx)` says so, custom
route or not. A profession step that *is* a custom-route line (picked through `N:Select`
before this change, or by a quest line) stays with the custom route, through `owns` and
`ctx.customKeys`. Every other profession step keeps its own lane while a custom route is
active. The rule "no quest step left: everything stays on the main arrow" (Nav.lua:1284)
is kept until Q7 is decided.

### 2.2 Lane state: `ns.activities`

A new module (`Modules/Nav/Activities.lua`, listed in `Flow.toc` before `Nav.lua`'s users).

```lua
-- Pure
A.Of(goal, defs, ctx)       -> activity key
A.Split(list, defs, ctx)    -> { [key] = { goals } }, in one pass, order kept
-- Lane state, one table per activity, never shared
A:State(key) -> {
    goals,                  -- this activity's routed steps from the last collect
    plan, planAt, pos, dirty,
    version,                -- goes up when its plan, choice or selection changes (6.3)
    choice,                 -- { goal, point, d } or nil: its planned step, no overlays
    selection,              -- { first = step key, tour = { [key] = true } } or nil
    route,                  -- the travel path to its choice (6.4)
}
A:Plan(key, p)              -- replans when dirty or moved (the rule both choosers have today)
A:Choice(key)               -- its planned step, never an overlay
A:Target(key)               -- what its arrow points at: an overlay if it carries one, else Choice
A:Select(key, stepKey)      -- the player's pick, saved per character; nil clears
A:Goals(key)                -- its routed steps
A:AllGoals()                -- the routed steps of every lane, each with goal.activity
A:Each()                    -- activities that have steps, in order
A:At(p, near)               -- the choice the player is standing at, or nil
```

Rules:

1. **No global current step.** Each lane has a `Choice` (planned) and a `Target` (what its
   arrow shows). `N.current` stays, with its meaning made exact: it is
   `A:Target("quest")`, the main arrow's target *including* the follow and waypoint
   overlays, as today. `N.plan`, `N.profPlan`, `N.profChoice` and `N.selection` stay as
   read-only views of lane state until their readers move.
2. **Selection for the quest lane goes through `N:Select`, unchanged.** That keeps the
   Focus hook (custom route line, custom sorter), the pickups tour and `nav.selectedKey`
   exactly as they are.
3. **Selection for every other lane bypasses the Focus hook.** `A:Select(key, stepKey)`
   for a non-quest lane sets that lane's `selection` and its saved pick and marks that
   lane dirty. It never calls `N:Select`, never adds a custom route line, never changes
   `nav.sorter`. The click handlers ("Go here next", the `^` in the Flow Router) route by
   `goal.activity`: quest -> `N:Select(key)`, anything else -> `A:Select(activity, key)`.
   `A:Select("quest", key)` is `N:Select(key)`.
4. **Selecting never moves a step between activities.** Ownership comes from `owns`. The
   one case where a profession step is on the quest lane's custom route is an existing
   custom-route line (2.1).
5. **"Which step am I at?" is `A:At(p, near)`, for two readers only.** It returns the
   choice whose step is within `near`; if several are, the one the player selected, then
   the nearest, then activity order. Users: Flow Actions (Actions.lua:259-268, which has
   this patched in today) and the bag marks (BagIcons.lua:27).
   **TaxiMark.lua:163, MapFlights.lua:164 and :330 and AreaHop.lua:190 keep reading the
   main arrow's target** (`N.current`): they answer "where is the main arrow taking me",
   and a flight or an area hop toward a profession step would be wrong for them.
   Actions.lua:1110 (`X.HealGoal`) also stays on `N.current`.
6. **Follow, waypoint and corpse are overlays, not activities**: they have no steps to
   plan. Which arrow carries them is in 6.5. `A:Choice` never returns one.
7. **Each activity plans its own steps only.** `deps` that point into another activity are
   kept as `after` information for display ("after: Buy Coarse Thread") but do not force
   the other lane's order.
8. **A lane that does not exist hides nothing.** Its steps fall through to the next owner.
9. **The quest lane's chooser keeps its extras as lane options, not as shared code**: the
   party's shared plan and its publishing (Nav.lua:3542-3548), and the sticky
   nearest-step fallback when there is no plan (:3558-3570). Other lanes get neither
   (`chooseProf` has neither today).

### 2.3 Who reads which list (finding P2-3)

`N:Goals()` keeps meaning "the quest lane's routed steps". `A:AllGoals()` is new.

| Reader | Uses | Why |
|---|---|---|
| Banker.lua:123 `B.NeededBy`, :240 `B.FetchBy` | all lanes | the bank must hold and hand out what profession steps need too; `bank:<prof>` is a profession step |
| Trader.lua:171 `T.RouteNeeds` | all lanes | a trade can supply a craft's material |
| QuestBags.lua:309 | all lanes | bag advice counts every step that will add or free items |
| Advisor.lua:388 `Adv.FindGoal` | all lanes | finds a step by key, whichever lane has it |
| Export.lua:183 | all lanes, each step tagged with its lane | diagnostics and `tools/route-check.ps1` |
| Crossings.lua:208 | all lanes | a profession step across a crossing needs it as well; the crossing step joins the lane of the step that needs it |
| Professions.lua:282 | `A:Goals("professions")` plus profession steps on the quest lane | the profession panel lists profession steps wherever they are |
| Party.lua:269 | quest lane | the shared party route is the quest route (Q9, deferred) |
| MapOverlay.lua:1102 `ns.dungeons.AwayGoals` | quest lane | a dungeon run is a quest-lane notion |

Readers that also walk `N.blockedGoals` / `N.hiddenGoals` keep doing so: those lists hold
every lane's steps, each carrying `goal.activity`. For Banker, Trader and QuestBags this
is a behaviour change with the arrow on (they start seeing profession steps), and a fix:
today the bank fetch for a profession step is invisible to `B.FetchBy` while the arrow
is on.

### 2.4 Reservations: `ns.reserve`

One ledger, pure: `R.Resolve(snapshot, claims, defs) -> grants`. It runs in **two phases**
per refresh, because SkillPlan needs to know its stock while it is still deciding its
steps, inside its provider, before `N:Collect` has any steps to read claims from
(SkillPlan.lua:1687, :2150-2152; Nav.lua:4927-4946).

```lua
snapshot = {
    bags = fn(id) -> n,  bank = fn(id) -> n,     -- ns.api.Count, SP.BankCount
    money = copper,
    slots = { general = n, all = n },            -- 2.5
}
claim = {
    activity = "professions", step = "craft:Leatherworking:Light Armor Kit",
    res = "item", id = 2318, n = 10,
    bank = true,            -- may draw from the bank (SP.UseBank said so)
    required = true,        -- false: an optional upgrade; yields to every required claim
    priority = nil,         -- overrides the activity's priority (quest-required skill steps)
}
claim = { activity = "quest", step = "train:class", res = "money", n = 8000, milestone = true }
claim = { activity = "professions", step = "buy:2320", res = "slots", n = 1 }

grant = { claim = claim, got = 4, short = 6, from = { bags = 4, bank = 0 } }
```

**Phase 1, before any provider runs** (at the start of `collectSpread`, and of a direct
`N:Collect()` gather): `R.Begin(snapshot)`.

- It takes the snapshot once. Bags changing while the sources are gathered, a frame at a
  time, do not change it; the existing `again` flag (Nav.lua:4921-4926) runs the refresh
  once more.
- It resolves the claims that do not depend on any provider's output: **quest item
  claims, read straight from the quest log** (`ns.quests.LogEntries()` objectives:
  `min(have, need)` of each objective's item), not from quest steps.
- It hands out `R.Stock()`: one stock object with `SP.Stock`'s interface (`Avail`, `Take`,
  `Fork`), seeded with the snapshot minus phase 1's grants.

**Inside the skillplan provider.** `planProfession` no longer builds its own stock
(SkillPlan.lua:1687): every profession takes from the one `R.Stock()`. Because taking is
order-dependent, the professions run in a **fixed order**, replacing `pairs`
(:2150): targets with `required` (a quest asks for the skill) first, then the order of
`ns:ProfessionPlan()`, then by name. Each `Take` records an item claim (activity, step,
`required`), so the ledger knows who holds what. Smelting stays inside the stock: taking
bars may draw ore, and the claim records both.

**Phase 2, in `N:Collect`** where `N.CommitCosts` is today (Nav.lua:577): `R.Finish(list)`.

- Money: every step's `goal.cost`, resolved in `CommitCosts`' order.
- Slots: slot claims from steps (2.5).
- Items: nothing new is granted. It checks that the item claims recorded in phase 1 and in
  the provider add up to no more than the snapshot (a test, and a `/flow perf` counter in
  the field), and drops the claims of steps that the filters removed, so `R.Held(id)` and
  the reason texts match the steps that are actually listed.

Where claims come from, in full:

- **Quest objectives**: phase 1, from the quest log.
- **Profession steps**: recorded by `Take` in the provider. A step may also carry
  `goal.claims` to say it exactly.
- **Other steps**, by a default reader in phase 2, so providers need not change at first:
  `goal.cost` -> money; `goal.fetch` (bank) -> slots; `buy:` / `need:` / `farm:` /
  `gather:` -> slots.
- **Things that are not steps**: `ns:Register("reserveSource", key, { claims =
  fn(snapshot) -> { claims } })`. The only candidate user is auto repair, and only if the
  owner decides Q5 that way. The trader's share and the mount's saving do **not** reserve
  (Q6, settled: advise only).

Resolution order, the same for all three resources, total and deterministic:

1. Claims of the step the player selected in its activity.
2. `required` before optional; for money, `milestone` first (keeps `CommitCosts` as it is).
3. Priority: the claim's own `priority`, else its activity's. Default: `quest` before
   `professions` (settled by the foreman; the per-item flip is Q2, owner decision). A quest
   turn-in can't be done with fewer, a craft can be made later.
4. For money only: cheaper first (again `CommitCosts`).
5. Step key, as the last tie-break.

**A skill a quest asks for ranks with the quest (finding P2-8).** Its steps live in the
profession lane (`N.IsProfessionStop` does not look at `forQuest`), which would give them
the lower priority. So: a step with `forQuest` or `forQuests`, and every `Take` made for
a target with `required = true` (SkillPlan.lua:663-668), produces claims with
`required = true` and `priority` = the quest activity's. The step stays in the profession
lane; only its claims move up.

Rules:

- **A unit is granted once.** `sum(got)` over all claims on an item never exceeds bags plus
  the bank share claimants may use; the same for copper and slots.
- **A short claim is a fact, not a failure.** The claimant plans for `short`: SkillPlan
  farms or buys 6, not 0. The quest objective keeps reading the game's own count, which is
  why quest claims are resolved first, in phase 1: the game will take those items at
  turn-in whatever Flow thinks.
- **The same grants whatever the order of registration.** With the fixed profession order
  and phase 1 before all providers, two professions give the same grants whichever is
  registered or saved first.
- **CraftHint reads the last finished ledger** (`R.StockView()`), not a fresh `SP.Stock`
  (CraftHint.lua:90), so its "have 4 of 10" agrees with the route.
- **Money: one number for "free to spend".** `R.MoneyFree(activity)` = money minus grants
  that outrank the asker. `N.moneyCommitted` becomes `R.Committed("money")`. In P2 only
  the route reads it. Whether `V.RepairDecision` reads it is Q5.
- **Keep rules get counts last.** `R.Held(id)` is the total granted for an item. Until the
  owner decides Q4, `disposition` verdicts stay all-or-nothing and only *read* the ledger
  for their reason text ("8 for your quest, 4 for Leatherworking").
- **The ledger is never saved.** It is a function of the bags, the bank snapshot, money,
  the quest log and the steps. `ns.db.nav.deferred` (steps waiting for money) stays as it
  is.

### 2.5 Bag slots (finding P2-11)

There are three free-slot readers with two meanings (1.5), and a general-bags-only count
would change what Banker and QuestBags do today. So P2 does **not** change any existing
reader's meaning:

- `R.FreeSlots()` returns `{ general = n, all = n }`, read once per snapshot from the bag
  API: `general` as Vendor counts (bag type 0), `all` as `X.BagsFree` and Flow Actions
  count. Vendor's `freeBagSlots()`, `X.BagsFree()` and Actions' `freeSlots()` become thin
  callers of it and keep the number each uses now, including what each returns when the
  API is missing (99, nil, 99).
- A slot claim is granted against `general`: one per item ID a step will add that has no
  partial stack in the bags.
- **Profession bags** (a herb bag, a mining sack) hold only their item family. Counting an
  herb as fitting an herb bag needs the item's family and the bag's type. That is left out
  of P2: slot claims use `general` only, which errs toward sending the player to sell a
  little early. Whether `GetContainerNumFreeSlots` returns the bag type on interface 16001
  has to be read in the client first.
- When slot claims exceed `general - ns.BAGS_NEARLY_FULL`, the sell or bank step stops
  being optional and the claiming steps get it as a dependency inside their own lane.
  Nothing is blocked on slots in P2.

## 3. Saved data (findings P2-4, P2-9, P2-10)

Nothing a player has is dropped, moved or rewritten. There is **no migration**.

| Today | After | How |
|---|---|---|
| `nav.selectedKey` (per character) | unchanged, for good: it is the quest lane's pick | none |
| `nav.profArrow` (shared setting) | unchanged in P2: the profession lane exists while it is on (6.1 for what P5 changes) | none |
| `nav.sorter`, `nav.focus`, `nav.focusKinds`, `nav.kinds`, `nav.point` | unchanged, quest lane only | none |
| `crafting.active[prof]` | unchanged; read through `ns.skillPlan.Aims()` | none |
| `prof.plan`, `prof.chosen`, `prof.tierSeen`, `bank`, `nav.deferred` | unchanged | none |
| (new) `activity = { [key] = { selectedKey, aim } }` | per character, for lanes other than `quest` only | `ns:OnLoad(function(db) db.activity = db.activity or {} end)` gives the default; `ns:PerCharacter("activity")` beside it makes it per character (its argument is a definition, and none is needed: there is no older shared value to adopt) |

- `activity.<key>.aim` is reserved for a player-set target (Q3); nothing writes it in P2.
- **Why the quest pick stays where it is.** The first draft copied it to
  `activity.quest.selectedKey` with a write-through and a migration. That loses the newer
  pick on a downgrade followed by an upgrade (the old version writes only the old key, and
  the migration is already marked done), and it needs a character-scoped migration, which
  the registry does not have (`FlowDB.migrations` and "fresh" are account-level,
  Core.lua:251-277, :287). I re-read `N:Select` (Nav.lua:3194-3208), the restore
  (:5025) and the Focus hook, and found no case where keeping the quest pick in
  `nav.selectedKey` fails: the quest lane's selection has one writer and one reader either
  way. So the character-scoped migration and its PR are dropped.
- **Downgrade.** An older Flow ignores `activity` and leaves it in `FlowCharDB`. A
  profession pick made before the downgrade is still there after the upgrade; if its step
  is gone it is dropped at the next collect, as `nav.selectedKey` is today.
- No learned data (places, trails, recipes, facts) is touched by any PR in section 4.

## 4. Build order (small PRs, each behaviour-neutral unless it says otherwise)

| # | PR | Changes | Player sees | Was |
|---|---|---|---|---|
| 1 | `activity` registry | `Modules/Nav/Activities.lua`: `A.Of`, `A.Split`; register `quest`, `professions`; `N.SplitProfessions` delegates; `goal.activity` set after `FilterKinds`; ARCHITECTURE.md row | nothing | 2 |
| 2 | Lane state, moved | the quest lane's `goals` / `plan` / dirty / pos and the `N.prof*` fields move into `A:State`, same writers, same readers; `N.plan` and friends become views. **No chooser logic changes.** Remove dead `pinnedKey`. | nothing | 3 (first half) |
| 3 | One chooser | `choose` and `chooseProf` become one function over a lane; the shared party plan and the sticky fallback become quest-lane options (2.2 rule 9); `A:Choice` / `A:Target` split from the overlays. Gate: the golden plan-order test (section 5) passes before and after. | nothing | 3 (second half) |
| 4 | All-lanes readers | `A:AllGoals()`; the readers in 2.3 move to the list the table names | with the arrow on, the bank and trades take profession steps into account | new (P2-3) |
| 5 | `A:At` | Actions.lua:259-268 and BagIcons.lua:27 only | the Flow key and bag marks agree when two steps are close | 4 |
| 6 | Per-activity selection | `A:Select` for non-quest lanes (bypassing the Focus hook), the `activity` saved section, "Go here next" on profession steps, the new split condition (2.1) | a profession step can be picked without changing the quest route, and a custom route no longer swallows the profession lane | 5 |
| 7 | Ledger, pure | `Modules/Reserve.lua`: snapshot, `R.Begin`, `R.Finish`, `R.Resolve`; no callers | nothing | 6 |
| 8 | Money through the ledger | `N.CommitCosts` becomes phase 2's money pass. Golden test: same `over` and `total` for the existing cases. | nothing | 7 (first half) |
| 9 | Items through the ledger | phase 1 quest claims; one `R.Stock()` for all professions, fixed order; `forQuest` priority; merged same-key steps sum their counts; CraftHint reads the view | "have enough" is right when a quest and a craft, or two professions, want the same item | 8 |
| 10 | Bag slots | `R.FreeSlots` with both counts; slot claims; sell or bank step ordered before steps that need room | a sell stop comes before a buy that wouldn't fit | 9 |
| 11 | Repair and the ledger | `reserveSource` for auto repair; `V.RepairDecision` reads `R.MoneyFree` | player-visible. **Waits for the owner's decision on Q5.** | 7 (second half) |
| 12 | Counts in keep rules | `disposition` reasons with counts; Vendor / Banker / Posting act on the surplus | **Waits for the owner's decision on Q4.** | 10 |

- The old PR 1 (character-scoped migrations) is dropped (section 3).
- PRs 1 and 7 can be built now and in parallel (the review's "PR 2 and PR 6").
- P5 needs PRs 2, 3 and 6, plus the additions in section 6. It does not need the ledger.

Each PR: tests as in section 5, lint at 0 warnings, CHANGELOG under `## Unreleased`, and
ARCHITECTURE.md when it adds a registry kind (`activity`, `reserveSource`).

## 5. Test obligations

**Where they go.** New tests go in new files under `Modules/Tests/`
(`Modules/Tests/Activities.lua`, `Modules/Tests/Reserve.lua`), each listed in `Flow.toc`,
as docs/TESTING.md asks for new lane work; not in `Modules/Tests.lua`. Names are unique
(`tools/check-structure.ps1`).

Pure, so they must pass offline (`tools/run-tests.ps1`) as well as in game:

- `activity: a step goes to the first activity that owns it`; `...falls through when the
  lane does not exist`; `...the catch-all keeps every step no one claims`; `...nothing is
  split off when no quest step would be left`.
- `activity: blocked, hidden and along steps carry their lane`.
- `activity: selecting in one lane leaves the other lane's selection, plan and sorter alone`.
- `activity: a profession pick adds no custom route line and keeps its lane` (the Focus
  hook, finding P2-2: with the hook installed, `A:Select("professions", key)` leaves
  `nav.focus` and `nav.sorter` as they were, and the next split still has the lane).
- `activity: a profession step that is a custom-route line stays on the custom route`.
- `activity: Select while following a party` (the quest pick is saved and adds no line, as
  Focus.lua:540-542 does today; a profession pick is unaffected by following).
- `activity: At picks the selected step, then the nearest, then by order`.
- `activity: Choice never returns a follow or waypoint overlay; Target does for the lane
  that carries it`.
- `activity: a pick whose step is gone is dropped`.
- `activity: a downgrade round trip keeps both picks` (saved data with `activity` present,
  loaded by a stand-in for the old shape that only touches `nav.selectedKey`, then loaded
  again: the quest pick is the newer one, the profession pick is intact).
- `activity: Banker and Trader see both lanes` (`B.NeededBy`, `B.FetchBy` and
  `T.RouteNeeds` get a `bank:<prof>` step and a craft's reagents with the lane split on).
- `route: golden plan order` (a fixed set of goals, position and options gives the same
  plan keys in the same order before and after PRs 2 and 3, for the quest lane with a
  pick, with a tour, with a shared party plan, with no planner, and for the profession
  lane).
- `reserve: a unit is granted once` (property style: random claims, `sum(got) <= stock`
  for items, copper and slots).
- `reserve: quest 8 + craft 10 with 12 in the bags -> craft is 6 short`.
- `reserve: two professions wanting the same bars share one stock`.
- `reserve: two professions in either order give the same grants` (the targets table built
  in both insertion orders).
- `reserve: smelting through the ledger` (bars wanted, only ore held: the grant draws ore
  at the smelt ratio, the ore is then not available to a second claim, and bars plus ore
  never grant more than the ore allows).
- `reserve: a skill a quest asks for outranks an ordinary craft for the same item`.
- `reserve: the selected step's claims come first`; `...required before optional`.
- `reserve: money keeps CommitCosts' order` (the existing CommitCosts tests, unchanged
  expectations, run against the ledger).
- `reserve: bank stock is only granted to claims that may use the bank`.
- `reserve: phase 2 grants no item phase 1 and the provider did not`; `...drops the claims
  of filtered steps`.
- `reserve: each free-slot reader keeps its number` (general, all, and the missing-API
  values 99 / nil / 99).

Need the game (reported SKIP offline):

- `click:` tests for "Go here next" on a profession step and for clearing it.
- That the views (`N.current`, `N.plan`) still feed the panel, tracker and map (existing
  route tests, unchanged).
- A refresh spread over frames with the bags changing mid-gather ends with a ledger that
  matches the bags (the `again` path).
- The per-character round trip of `activity` across `/reload` and a second character.
- What `GetContainerNumFreeSlots` returns for the bag type on interface 16001.
- No taint: tests stand in for Flow's own functions (the snapshot), never `GetMoney` or
  the bag API.

Performance: `R.Begin` and `R.Finish` run once per refresh; add them to `/flow perf` as
"reserve" and keep them under the refresh's per-frame budget (`collectSpread`).

## 6. What P5 needs from this contract

P5's acceptance requirement is one arrow per activity, **stacked by default, separable and
stackable again**, with positions and state kept across `/reload`. The first draft gave one
choice per activity only while the lane was shown, tied to `nav.profArrow`. That is not
enough. P2 provides the following; the frames and controls are P5's.

### 6.1 Lane existence is separate from arrow display

- **Exists**: the activity plans its own steps and has its own choice and selection
  (`exists(ctx)`, 2.1). Setting: `ns.nav:ProfLaneOn()`.
- **Displayed**: an arrow is drawn for it, and where. That is P5's, and reads only
  `A:Each()`, `A:Target(key)` and `A:State(key).version`.

In P2, `ProfLaneOn()` is `nav.profArrow == true and Includes("professions")`, exactly
today's `ProfPointerOn()`, so nothing changes for players. `nav.profArrow` thereby stops
meaning "draw the faint arrow" and means "professions have their own lane"; P5 adds the
display settings below. Whether the lane should exist by default once P5's arrows are in
(today it is off by default, Nav.lua:735-738, because with it on the Flow key stopped
doing profession steps at the main arrow's step; `A:At` in PR 5 removes that reason) is
an owner decision, with Q1 and Q7.

A lane can exist with no arrow drawn (the player hid that arrow): its steps are still
planned apart, the Flow Tracker and map still list them, and `A:At` still finds its step.

### 6.2 A saved display mode and per-activity arrow positions

Reserved keys, written by P5, shared like `nav.point` (the arrow's place is a screen
layout, not a character's progress):

```lua
ns.db.nav.arrows = {
    mode = "stacked",                      -- or "separate"; default "stacked"
    points = { [activity] = { a, r, x, y } },   -- each arrow's own place when separate
    hidden = { [activity] = true },        -- an arrow the player turned off; the lane stays
}
```

- `nav.point` (Nav.lua:4366, :4419) stays the place of the stack, and of the quest arrow
  when separate. No migration: `nav.arrows` absent means stacked at `nav.point`.
- Separating copies nothing: an arrow with no saved point starts beside the stack.
  Stacking again keeps `points`, so separating once more puts each arrow back.
- Stack order is the activities' `order`, the lane carrying an overlay first (6.5).

### 6.3 A per-lane change signal

Today the only signal is `N.planVersion` (Nav.lua:3104, :3551), polled by the Flow Router
preview (:3461) and the tracker (RouteTracker.lua:608); the profession lane has none.
Core has no custom event bus beyond game events, so the contract keeps the polled-counter
pattern:

- `A:State(key).version` goes up when that lane's plan, choice, selection or existence
  changes. A lane's version never changes because another lane replanned.
- `A.version` goes up when the set of lanes changes (a lane appears or goes).
- `N.planVersion` stays, equal to the quest lane's version.

### 6.4 A per-lane travel route and minimap pin

- The travel path the arrow follows is one file local today (`route`, Nav.lua:461, built
  at :3750 for the main arrow's step). It becomes `A:State(key).route`, built per lane by
  the same leg builder with that lane's `Target`. Flight, area-hop and taxi helpers
  (TaxiMark, MapFlights, AreaHop) stay on the quest lane's route (2.2 rule 5).
- The minimap pin has two hard-wired entry points today, `P:Update` and `P:UpdateProf`
  (MinimapPin.lua:415). The contract gives P5 one call per lane:
  `ns.minimapPin:UpdateLane(key, p, point, goal)`; `Update` and `UpdateProf` become calls
  of it for `quest` and `professions`.
- The world map's profession route (MapOverlay.lua:1028-1063) reads
  `A:State("professions").plan` instead of `N.profPlan`; drawing more lanes is P5's.

### 6.5 Which arrow carries follow, waypoint and corpse

- **Follow** (a party member you follow) and **your own waypoint** are carried by the
  **quest arrow**: `A:Target("quest")` returns the overlay, as `N.current` does today
  (Nav.lua:4738). Other lanes' arrows keep pointing at their own steps.
- **Stacked**: the stack shows the carrying lane's target on top, so a waypoint or a
  followed member is what the stack points at, as now.
- **Corpse**: while dead, one arrow (the stack, or the quest arrow when separate) turns
  red and points at the corpse; every other lane's arrow hides until you are alive, as
  the profession arrow does today (Nav.lua:4731-4734). No lane replans while dead.
- A lane other than `quest` never carries an overlay. If the quest lane has no steps and
  no overlay, its arrow hides and the others stay.
- `A:At` ignores overlays: standing at your waypoint is not standing at a step.

### 6.6 Per-arrow controls

P5's controls call only: `A:Select(key, stepKey)` (pick and clear), `A:State(key)`
(plan, choice, version), `ns.nav:SetKind` / the lane's `exists` setting (turn a lane
off), and `nav.arrows` (mode, place, hide). Each control gets a click test (P5).

## 7. Open product questions

| # | Question | Status |
|---|---|---|
| Q1 | One profession activity, or one per profession? Per profession gives each its own selected step and, in P5, its own arrow (up to five lanes with the secondary professions). The contract supports both. Shapes P5. | **Owner decision** |
| Q2 | Who wins a shared item by default? | **Settled by the foreman**: quests, then professions, with the player's selected step above both |
| Q2b | May a player flip that per item ("keep my leather for Leatherworking")? | **Owner decision** |
| Q3 | Can the player set a profession's target (skill level or a recipe), or does it stay derived from pace and quests? A set target needs UI in Flow Professions and uses `activity.<key>.aim`. | **Owner decision** |
| Q4 | Counts in keep rules: may Flow sell or bank the surplus of an item a quest or a craft needs some of? Today it keeps every stack. Gates PR 12. | **Owner decision** |
| Q5 | Does repair take part in the money ledger, and does it outrank route steps? Gates PR 11, which is player-visible (finding P2-7). | **Owner decision** |
| Q6 | Should the trader's share and the mount's saving reserve money? | **Settled by the foreman**: no, advise only, as now |
| Q7 | With no quest step left, do profession steps move to the main arrow (today), or does the quest lane stay empty and the profession arrow carry on? Also: does the profession lane exist by default once P5 is in (6.1)? Shapes P5. | **Owner decision** |
| Q8 | Mail: items in the mailbox are not counted anywhere. | **Settled by the foreman**: deferred |
| Q9 | Should a party's shared route ever carry profession steps? | **Settled by the foreman**: deferred; party and dungeon routes stay quest-lane only |

## 8. Out of scope here, noted for the foreman

- docs/ARCHITECTURE.md's registry table lacks kinds the code uses: `disposition`,
  `migration`, `skillBooster`, `itemTip`, `setupItem`, `help`.
- CLAUDE.md says "there is no Lua interpreter"; docs/TESTING.md describes the offline
  runner.
- The migration registry (Core.lua:235-277) is still unused and account-scoped only. P2 no
  longer needs it.

## 9. Review findings and where they landed

| Finding | Re-read in source | Result |
|---|---|---|
| P2-1 two-phase ledger, fixed profession order | SkillPlan.lua:1687, 2150-2152; Nav.lua:4927-4946: confirmed | 2.4 (phases, fixed order), 1.1 |
| P2-2 Focus hook deletes a profession pick's lane | Focus.lua:536-554, 319-331; Nav.lua:719: confirmed | 1.2, 2.1 (split condition), 2.2 rules 2-4 |
| P2-3 ten outside readers of `N:Goals()`; lane-less lists | all eleven call sites and Nav.lua:610, 625, 702: confirmed | 1.3, 2.1 (assignment point), 2.3, PR 4 |
| P2-4 keep the quest pick in `nav.selectedKey` | Core.lua:158-160, 287; Nav.lua:3194-3208, 5025: no failing case found | adopted: section 3; old PR 1 and the migration dropped |
| P2-5 PR 3 is not small; 26 read sites | Nav.lua:3542-3548, 3558-3570, 4738; grep: 26 sites in 17 files: confirmed | 1.1, 1.3, 2.2 rule 9, PRs 2 and 3 |
| P2-6 flight and area-hop readers want the main arrow | TaxiMark.lua:163; MapFlights.lua:164; AreaHop.lua:190: confirmed | 2.2 rules 1, 5 and 6; PR 5 |
| P2-7 repair refused money is player-visible | section 7 | PR 11 split off and gated on Q5 (not a WOW-5 item; recorded because the split follows from P2-5's renumbering) |
| P2-8 quest-required skill steps get the lower priority | SkillPlan.lua:657-668; Nav.lua:729-733; Goals.lua:956: confirmed | 1.4, 2.4 (`priority` on claims) |
| P2-9 `ns:PerCharacter` takes a definition | Core.lua:158-160: confirmed | 1.6, section 3 |
| P2-10 "fresh" is account-level | Core.lua:287: confirmed | moot (P2-4 adopted); noted in 1.6 and section 3 |
| P2-11 three free-slot readers; general-only changes behaviour; bag families | Actions.lua:678-685; Vendor.lua:793-802; Export.lua:94-103: confirmed | 1.5, 2.5 |
| P2-12 wrong or incomplete references; test placement | `N.current` is Nav.lua:4739-4740; pipeline order 549 / 556 / 558 / 565 / 577 / 708 / 714 / 719; `professionMaterial` at Disposition.lua:433: confirmed | 1.1, 1.2, 1.3, 1.5, section 5 |

No finding was rejected.
