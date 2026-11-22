# Measuring Flow's performance

How to take a baseline of Flow's CPU and memory in the game, and where its regular work runs.
This page records **no numbers**: there is no measured baseline yet. Numbers in code comments
(for example "each rebuild is ~20-40 ms" in Modules/Nav/Nav.lua) are old observations, not a
baseline. Every figure has to come from a run in the game, recorded as below.

## The tools

- **`/flow perf`** (Modules/Perf.lua:139). This reports Flow's own work since the last reset:
  - `lite mode: on (<why>)` or `off`, and the after-login long-frame line.
  - `over N s: Flow used X ms per second (Y% of one CPU core), memory A MB (B MB kept after
    clean-up)`. Memory here is what Flow holds; "kept" is measured after a full garbage
    collection.
  - One row per timed function, costliest first:
    `name  ms/s  avg ms  worst ms  makes KB/s  (calls)`. A function's time is its own: when a
    timed function calls another, the inner one's time counts only for the inner one, so the
    rows add up to the total (`P.Wrap`, Modules/Perf.lua:16).
  - A `most in:` line under a row, naming its costliest parts (`P.AddPart`). For the route,
    it is each cause of a refresh, how often it came, and what it cost.
  - `! name once took N ms (a visible hitch)` for anything near one frame (~16 ms at 60 fps).
- **`/flow perf reset`** (Modules/Perf.lua:86) zeroes the counters and starts the clock again.
- **`/flow perf quick`**: the same report without the full garbage collection, so taking it
  doesn't cause a hitch. The after-login snapshot uses it.
- **Long frames after login** (Modules/Perf.lua:210, watcher at :226). For the first 40 s
  after login it notes every frame of 150 ms or more, skipping the first 1.5 s, and keeps the
  5 longest. They go into the log: `after login: N long frame(s) in the first 40 s; the
  longest: ...`. These frames are anyone's, not only Flow's; `/flow perf`'s "once took"
  lines say which are Flow's own.
- **The diagnostics snapshot** (Modules/Diag.lua:58). The `--- perf` section is `/flow perf`,
  in full at logout and quick after login. Each check's heading carries its own time, and a
  snapshot over 50 ms is logged: `snapshot (<reason>) took N ms, slowest <check> N ms`.
  `/flow dump` takes one by hand. Read it with `tools\read-diag.ps1` after a `/reload`.
- **The fight profiler** (Modules/Fight/Profiler.lua, `/flow fights`) is not a CPU tool. It
  records gameplay (damage, healing, threat, what you cast) so the rotation can learn. It
  appears below only because its tick runs during fights.

## Taking a baseline

1. Use a release-like install, or note that it is a developer install. A developer install
   (`## X-Flow-Dev: 1`) runs the self-tests at `/reload` and logout, and turns on the taint
   log. Neither runs during play, but say which install it was.
2. `/reload`, then wait out the first 40 s. Note the `after login:` log line
   (`tools\read-diag.ps1`, or `/flow perf`).
3. `/flow perf reset`. Then play one fixed scene for a fixed time (5 minutes is enough), with
   nothing else changed:
   - **A. Questing out of a fight:** route on, arrow and minimap on, Flow Tracker open.
   - **B. Fights:** the same, pulling mobs one after another.
   - **C. Bags:** a vendor visit or loot, with the bag icons on (BAG_UPDATE_DELAYED bursts).
   - **D. Lite mode:** in a dungeon or a raid group (`lite mode: on`).
4. `/flow perf` (the full report). Copy it out with `/flow copy`, or `/reload` and read the
   `--- perf` section with `tools\read-diag.ps1`.
5. Record these:
   - Flow version, or git SHA, plus install kind, class, level, zone and scene.
   - The length of the run (`over N s`).
   - Total `ms per second` and `% of one CPU core`.
   - Memory and "kept after clean-up".
   - For the top 5 rows: ms/s, avg, worst, KB/s and calls.
   - Every `!` hitch line.
   - The `after login` long-frame line.
   - Your frame rate, if you know it, from the game's own display.
6. Do each scene twice. If two runs differ by more than the change you're measuring, the
   scene isn't fixed enough to measure that change.

Compare a change only against a baseline from the same scene, class and level. The figures
come from `debugprofilestop` and `collectgarbage("count")` inside the game, and vary with the
machine and with other add-ons.

## Where Flow works regularly (hot paths)

The name in quotes is the row `/flow perf` shows.

**Every frame or every tick (OnUpdate).** There are 47 `SetScript("OnUpdate", ...)` sites
outside the tests. Most are throttled by an accumulated `dt`, or run only while something is
shown. The ones that run all the time:

- Modules/Nav/Nav.lua:4997, :4999: "arrow + minimap (10/s)". It runs 10 times a second, or 2
  in lite mode. The same driver starts the quiet route refresh every 30 s (:5005).
- Modules/Rotation/Display.lua:1220: "rotation: showing it (10/s)". Inside it are "rotation:
  choosing the spell" (:943) and "flow actions" (:944). Status icons, once a second: "status
  icons (1/s)" (:1215).
- Modules/Rotation/Cast.lua:766 (driver), :630 ("target button: queue"), and :1206 (sampler).
- Modules/Rotation/CareKeys.lua:442, Modules/Rotation/CastEdge.lua:65,
  Modules/Rotation/BuffButton.lua:912.
- Modules/Meters.lua:548 (meters), Modules/Pulse.lua:36, Modules/Nav/Follow.lua:198,
  Modules/Items/BagIcons.lua:301, Modules/Crafting/CraftBar.lua:173.
- While the world map is open: Modules/Nav/MapOverlay.lua:2238. Its rows are "world map
  (keeping up with you)" (:2165), "world map (full redraw)" (:2288) and "world map (route
  dots)" (:410). Also "world map (flight masters)" (Modules/Nav/MapFlights.lua:707, driver
  :720) and "world map (zone info)" (Modules/Nav/MapZoneLevels.lua:322, :331).
- While it's shown: Modules/Nav/RouteTracker.lua:604, "Flow Tracker" (:641).
- During a fight: Modules/Fight/Profiler.lua:450, probe ticks every 0.25 s.
- Others: "minimap areas" (Modules/Nav/MinimapPin.lua:372), "legs" (Modules/Nav/Legs.lua:288),
  and "dungeon runs" (Modules/Nav/Dungeons.lua:937, driver :1883).

**Bag changes.** Flow listens to `BAG_UPDATE_DELAYED`, once per burst of bag changes; nothing
listens to `BAG_UPDATE` itself. There are 16 handlers. The ones that do work rather than clear
a cache:

- Modules/Items/BagIcons.lua:320: the bag icons.
- Modules/Items/Disposition.lua:235: what to keep, sell or use.
- Modules/Items/Vendor.lua:679.
- Modules/Crafting/SkillPlan.lua:2102.
- Modules/Rotation/Actions.lua:768.
- Modules/Rotation/Cast.lua:666: the emergency item, after 0.2 s.
- Modules/QuestMarks.lua:435.
- Modules/Quests/QuestNeeds.lua:118.
- Modules/Advisor/Advisor.lua:326 and Modules/Gear/Sets.lua:134, among other events.

Cache-clearing only: Modules/Nav/QuestItems.lua:260, Modules/Quests/QuestBags.lua:296,
Modules/Rotation/Actions.lua:609, Modules/Rotation/BuffButton.lua:935,
Modules/Rotation/BuffItems.lua:732 and :916.

**Route refresh.**

- Triggers:
  - The events at Modules/Nav/Nav.lua:5018-5023: entering the world, quest accepted or turned
    in, zone, level, skills, trainer, spells learned.
  - `QUEST_LOG_UPDATE` when the log really changed (:5047, :5049).
  - Money (:4955, :4958).
  - `N.RequestCollect` from other modules (:4948).
  - The quiet refresh every 30 s (:5005).
- `collectSoon` (:4929) waits 1 s, so a burst of events gives one refresh. In lite mode it
  holds back (`N.LiteGather`).
- `collectSpread` (:4895) reads one step source a frame. Each source is a row "gather:
  <source>" (:506). Then it plans: "route: gather steps" (`N.Collect`, :5227) and "route:
  order steps" (`ns.planner.Plan`, Modules/Nav/Planner.lua:684). A change that comes in while
  it gathers gives one more refresh after this one (:4893).
- The route row's `most in:` line in `/flow perf` lists the refreshes by cause, which shows
  what keeps asking.

**Lite mode** (Modules/Perf.lua:159 `ns.LiteWhy`, :169 `ns.Lite`). It is on inside a
dungeon or raid, in a raid group, a battleground or an arena, or during a boss fight:

- The route is gathered at most every 20 s.
- The arrow and minimap run 2 times a second.
- The map and tracker refresh every 2 s, and the meters once a second.
- Trips aren't timed, and the self-tests don't start after login. (On a developer install
  they still run at every `/reload` and at logout, lite mode or not: about 3 s of work, so
  don't take "scene D" figures across a `/reload`.)

The rotation, both buttons and the bags run as normal. Scene D above measures it.
