-- Import from Flow: a deliberate, versioned, non-destructive copy of what a
-- player chose and what their client observed in Flow, into Z-Flow's shape.
-- Pure: two plain tables in, new plain tables out. It reads no global, no
-- saved variable and no clock, and never changes what it is given. Nothing
-- here runs unless a caller hands it Flow's tables on purpose.
--
--   Import.FromFlow(flowDb, flowCharDb) -> result
--     result.ok        true, or false with result.reason (nothing imported)
--     result.account   data in the account shape (schema, settings, layout,
--                      learned = places/flights/prices/facts/fights, imports)
--     result.char      data in the character shape (schema, settings,
--                      layout, learned, state)
--     result.dropped   list of { key, why, reason }, sorted by key. why is
--                      "dropped" (on purpose), "unknown" (no row in MAP),
--                      "malformed" or "superseded". Nothing is lost silently.
--     result.adjusted  list of { key, from, to, reason }, sorted by key: a
--                      value that was kept, but not as Flow had it (a frame
--                      size outside the limits, stored at the nearest limit).
--                      record.counts.adjusted is its length.
--     result.record    the import record: source, sourceVersion, importer,
--                      counts per category, vendor choices found. The caller
--                      stamps the date (a pure function has no clock).
--                      record.sameAsFlowDefault[key] = true marks a value
--                      equal to the one Flow writes by itself at load: it
--                      was found, but it does not prove the player chose it.
--     result.vendorToConfirm   list of { key, to, sameAsFlowDefault }, sorted
--                      by key: every vendor automation Flow had on. None of
--                      them is on in result.account. The import screen shows
--                      this list and the player confirms each one.
--
--   Import.Merge(account, char, result [, defaults [, confirmed [, model]]])
--       -> account, char, report
--     New tables: the player's existing data plus whatever of the import it
--     does not already have. An existing value is never replaced, unless it
--     is absent, an empty table, or equal to the default given for its path
--     in defaults = { account = {...}, char = {...} }.
--     Settings follow the stricter rule the settings model's adopt uses: a
--     stored setting is the player's choice and is kept, also when it equals
--     the default, so defaults are not read for settings. Only a stored
--     setting that does not fit does not count as a choice and gives way.
--     What fits is the settings model's own check (model:check, the one
--     its adopt runs): the wrong type, and also a number outside the row's
--     bounds. model is the settings model to ask; left out, the shipped one
--     is used (looked up when Merge is called). The import's value replaces
--     a stored one that does not fit only when it fits itself. An account
--     setting the model has no row for, every character setting, and every
--     setting when no model is loaded fall back to comparing types: text
--     where a yes-or-no belongs gives way.
--     The record added to account.imports is a copy fit to be saved (no
--     functions, no table that holds itself, no number that is not finite)
--     and carries copies of result.dropped and result.adjusted
--     (record.dropped, record.adjusted).
--     confirmed = { ["sell.autoRepair"] = true, ... }: the vendor automations
--     the player confirmed, by Flow key. Only a true counts. An automation
--     the import found on and the player did not confirm stays off, however
--     it reached the result. A confirmed one still never replaces a choice
--     the player already has.
--     report = { ok, reason, added, kept, skipped, counts, vendorConfirmed,
--     vendorLeftOff }; the last two are sorted lists of Flow keys.
--
-- Where each Flow key was read from (Flow source, file:line):
--   saved-data layout, per-character split   Core.lua:182-232
--   version, migrations                      Core.lua:251-276
--   actions      Modules/Rotation/Actions.lua:1280
--   advisor      Modules/Advisor/Advisor.lua:318, :323
--   ah           Modules/Items/Auction.lua:454, Modules/Items/Posting.lua:37
--   api          Compat.lua:264
--   audit        Modules/Rotation/Audit.lua:136, :140
--   autopush     Modules/AutoPush.lua:76-81
--   bags         Modules/Items/BagIcons.lua:298
--   bank         Modules/Crafting/SkillPlan.lua:1214-1215
--   banker       Modules/Items/Banker.lua:1184, Modules/Quests/QuestBags.lua:430
--   bonus        Modules/Bonus.lua:121
--   buffButton   Modules/Rotation/BuffButton.lua:32-34, :573, :997-998,
--                Modules/Rotation/CareKeys.lua:47-59, Modules/MoveHandle.lua:126-127
--   camera       Modules/Camera.lua:41
--   cast         Modules/Rotation/Cast.lua:757
--   chat         Modules/AskClaude.lua:492, Modules/Chat.lua:22
--   choices      Modules/Fight/Choices.lua:260, :264
--   colorblind   Theme.lua:128
--   crafting     Modules/Crafting/Recipes.lua:105-108, SkillPlan.lua:585
--   deathReports, deathNext   Modules/Rotation/Engine.lua:1811-1812
--   deaths       Modules/Deaths.lua:425
--   diag         Diag.lua:194
--   facts        Modules/Facts.lua:38, Modules/FormSpells.lua:30
--   flightNone, flightTalked  Modules/Nav/FlightPaths.lua:122-150
--   flights, flightTimes, flightRate   Modules/Nav/Nav.lua:2709-2712, :2921
--   gear         Modules/Gear/KeepSets.lua:343, Score.lua:482,
--                SetRecipes.lua:314, Sets.lua:144
--   hearth       Modules/Hearth.lua:349
--   invites      Modules/Invites.lua:91
--   learnedSpots Modules/Quests/LearnedSpots.lua:36
--   log          Modules/CombatLogFile.lua:27
--   loot         Modules/Items/LootFilter.lua:187
--   mailboxes, places, placesNot, share   Modules/Nav/Places.lua:142, :257,
--                :369-370, :493
--   meters       Modules/Meters.lua:46
--   nav          Modules/Nav/Nav.lua:939, :3659, :4175, :4399, :4962-4983,
--                Arrows.lua:94, :161-164, Crossings.lua:343-351, Gates.lua:177,
--                Legs.lua:238, :319, Focus.lua:532, :558, ZoneNotice.lua:220,
--                :223, Dungeons.lua:840-845, Waypoint.lua:90
--   nearFirst    Modules/Nav/NearFirst.lua:32
--   paladin*     Classes/Paladin/Rotation.lua:124-125, :239-240
--   perf         Perf.lua:183
--   plateCombo   Modules/PlateCombo.lua:45
--   plateThreat  Modules/PlateThreat.lua:30
--   prices       Modules/Crafting/SkillPlan.lua:274-282
--   prof         Modules/Professions.lua:151-152
--   profiler     Modules/Fight/Profiler.lua:409-418
--   quests       Modules/QuestMarks.lua:383, Modules/Quests/QuestData.lua:580, :588
--   reagents     Modules/Items/Reagents.lua:66-69
--   rotation     Modules/Rotation/Tracker.lua:235-243, Engine.lua:1531
--   sell         Modules/Items/Disposition.lua:257-272, :499,
--                Vendor.lua:272, :734-738, Repair.lua:55, :110
--   settings     Settings.lua:1060, Core.lua:317-318
--   setup        Setup.lua:402
--   sound        Sound.lua
--   spec         Modules/Spec.lua:241-242
--   spellbar     Modules/NewSpell.lua:518, :521
--   splash       Splash.lua:185
--   tracker      Modules/Nav/RouteTracker.lua:581
--   trader       Modules/Items/Trader.lua:571
--   trainer      Modules/Trainer.lua:101-104
local _, ns = ...

-- 2: what is stored is made safe on the way in. Frame sizes are held within
--    the limits, a position keeps only anchors a frame has, and the companion
--    button's switches and keys are checked by type. Version 1 stored all of
--    those as Flow had them and left the checking to the readers.
-- 3: the stored record carries its own copies of what was left behind and
--    what was adjusted (record.dropped, record.adjusted), and a merge keeps a
--    setting the player has stored even when it equals the default.
local IMPORTER_VERSION = 3
-- The highest Flow data version this importer understands. Flow's version is
-- the highest migration it has run (Core.lua:251-276) and Flow registers no
-- migration, so every known Flow data set is at 0 (or carries no version).
local KNOWN_FLOW_VERSION = 0
local SCHEMA = 1

-- Reasons used by more than one row.
local BOOKKEEPING = "Flow's own bookkeeping; means nothing outside Flow"
local CACHE = "a cache; rebuilt from the game as you play"
local ONCE = "a one-time notice flag"
local DIAGNOSTIC = "diagnostic output, not player data"
local SESSION = "state of one play session; stale once imported"
local OLD = "an old Flow setting that Flow itself no longer reads"
-- legacyShared (Core.lua:182-208): the shared values Flow parked when it began
-- keeping them per character, by path. Each character takes its share by
-- rules each Flow module owns, when it next logs in.
local PARKED_EMPTY = "Flow's parking place for data from before it kept things per character; nothing is parked in it"
local PARKED_TAKEN = "shared data from before Flow kept this per character; this character already took its share,"
    .. " and that share is imported from the character's own data"
local PARKED_WAITING = "shared data from before Flow kept this per character; Flow hands each character its share by"
    .. " its own rules when that character next logs in, and the importer does not copy those rules,"
    .. " so nothing was imported from here"
-- nav.mode and nav.professions: Flow still reads and writes both. They are
-- the older saved names of the choice in nav.kinds, kept in step with it
-- (Modules/Nav/Nav.lua:1372, :1386, :1445-1446), and the only record of it
-- when nav.kinds is absent (Nav.lua:4983).
local OLDER_NAME = "the older saved name of the choice Flow keeps in nav.kinds; Flow writes both together,"
    .. " and nav.kinds is imported"
local OLDER_NAME_ALONE = "the older saved name of the choice Flow now keeps in nav.kinds; this data has no nav.kinds,"
    .. " and the importer does not rebuild one from the old name, so this choice was not carried over"

-- THE MAPPING. One row per Flow key: "section" or "section.key".
--   to    the path it lands on (in the account data, or the character's
--         when char = true)
--   as    how the value is checked and copied (see KIND below). When absent:
--         learned data is "tree" (a table, copied with bad parts left out),
--         anything else is "any" (a plain value, or such a table)
--   drop  it is left behind on purpose, and why
--   beside, dropAlone   the reason is dropAlone instead when Flow's data has
--         no value at the path named by beside
--   yield it gives way when an earlier row already put a value where it lands
--   vendor      a vendor automation: off unless the player confirms it
--   flowDefault Flow itself writes this value at load, so finding it does
--               not prove the player chose it
--   parked      Flow's parking place for data from before it kept things per
--               character: dropped, one entry per parked path
-- A "section" row beside "section.key" rows takes the keys no row names.
-- A key under a section that has rows but no row for it is "unknown".
local MAP = {
    -- Flow bookkeeping
    { "version", meta = "read as the source version on the import record" },
    { "migrations", drop = BOOKKEEPING },
    { "charSplit", drop = BOOKKEEPING },
    { "legacyShared", drop = PARKED_WAITING, parked = true },

    -- Learned: places
    { "places", to = "learned.places.npcs", as = "places" },
    { "placesNot", to = "learned.places.notRoles" },
    { "mailboxes", to = "learned.places.mailboxes", as = "spots" },
    { "learnedSpots", to = "learned.places.questSpots", as = "questSpots" },
    { "hearth.binds", to = "learned.places.innBinds" },
    { "nav.graphs", to = "learned.places.trails" },
    { "nav.entrances", to = "learned.places.entrances", as = "worldList" },
    { "nav.gates", to = "learned.places.gates", as = "worldList" },
    { "nav.legs", to = "learned.places.legs" },
    { "nav.crossingEnds", to = "learned.places.crossings" },
    { "share", drop = "an export built from the places above; derived" },

    -- Learned: flights
    { "flights", to = "learned.flights.nodes", as = "flights", char = true },
    { "flightTalked", to = "learned.flights.talked", char = true },
    { "flightNone", to = "learned.flights.none", char = true },
    { "flightTimes", to = "learned.flights.times", as = "times" },
    { "flightRate", to = "learned.flights.rate", as = "positive" },

    -- Learned: prices
    { "prices", to = "learned.prices.vendor", as = "prices" },
    { "ah.prices", to = "learned.prices.auction" },

    -- Learned: facts
    { "facts.spells", to = "learned.facts.spells" },
    { "facts.lacks", to = "learned.facts.lacks" },
    { "facts.first", to = "learned.facts.first" },
    { "facts.firstAt", to = "learned.facts.firstAt" },
    { "facts.forms", to = "learned.facts.forms" },
    { "quests.drops", to = "learned.facts.questDrops" },
    { "quests.notOffered", to = "learned.facts.notOffered", char = true },
    { "crafting", to = "learned.facts.recipes", char = true },
    { "crafting.drops", to = "learned.facts.craftDrops", char = true },
    { "crafting.active", to = "state.crafting.active", char = true },
    { "reagents", to = "learned.facts.reagents", char = true },
    { "trainer", to = "learned.facts.trainer", char = true },
    { "prof.tierSeen", to = "learned.facts.tierSeen", char = true },
    { "nav.dungeonTimes", to = "learned.facts.dungeonTimes", char = true },
    { "nav.xpSamples", to = "learned.facts.xpSamples", char = true },

    -- Learned: fights
    { "profiler.fights", to = "learned.fights.records", char = true },
    { "profiler.bias", to = "learned.fights.bias", char = true },
    { "profiler.report", drop = "a report built from the fight records; derived" },
    { "choices", to = "learned.fights.choices", char = true },
    { "rotation.mobs", to = "learned.fights.mobs", char = true },
    { "rotation.heals", to = "learned.fights.heals", char = true },
    { "deathReports", to = "learned.fights.deaths" },
    { "deathNext", drop = BOOKKEEPING },

    -- Arrows (per account) and other window positions
    -- Flow keeps the quest arrow's place in nav.point and only the other
    -- arrows' places in nav.arrows.points (Modules/Nav/Arrows.lua:387-391).
    -- Z-Flow reads every place from layout.arrows.points (Nav/ArrowLayout.lua).
    { "nav.point", to = "layout.arrows.points.quest", as = "point" },
    { "nav.arrows", to = "layout.arrows", as = "arrows" },
    { "nav.cardPoint", to = "layout.nav.card", as = "point" },
    { "nav.drawerPoint", to = "layout.nav.drawer", as = "point" },
    { "nav.zoneNoteSpot", to = "layout.nav.zoneNote" },
    { "nav.panelPoint", drop = OLD },
    { "advisor.point", to = "layout.advisor.frame", as = "point" },
    { "advisor.panelPoint", to = "layout.advisor.panel", as = "point" },
    { "ah.postPoint", to = "layout.auction.post", as = "point" },
    { "ah.chartPoint", to = "layout.auction.chart", as = "point" },
    -- The Flow button's small companion (Modules/MoveHandle.lua:126-127 saves
    -- point and scale together; BuffButton.lua:573 the docked size).
    { "buffButton.point", to = "layout.buffButton.frame", as = "point" },
    { "buffButton.scale", to = "layout.buffButton.scale", as = "size" },
    { "buffButton.dockScale", to = "layout.buffButton.dockScale", as = "size" },
    { "banker.point", to = "layout.banker.frame", as = "point" },
    { "deaths.point", to = "layout.deaths.frame", as = "point" },
    { "meters.point", to = "layout.meters.frame", as = "point" },
    { "rotation.point", to = "layout.rotation.frame", as = "point" },
    { "rotation.scale", to = "layout.rotation.scale", as = "size" },
    -- The professions window: per character, as the whole prof section is
    -- (Modules/Professions.lua:50, :152).
    { "prof.point", to = "layout.prof.frame", as = "point", char = true },
    { "tracker.point", to = "layout.tracker.frame", as = "point" },
    { "trader.point", to = "layout.trader.frame", as = "point" },

    -- Vendor automations: off in Z-Flow. One that Flow had on is listed in
    -- result.vendorToConfirm and written nowhere; Merge switches it on only
    -- when the player confirmed that one.
    { "sell.autoJunk", to = "settings.sell.autoJunk", as = "bool", vendor = true, flowDefault = true },
    { "sell.autoAll", to = "settings.sell.autoAll", as = "bool", vendor = true, flowDefault = false },
    { "sell.autoRepair", to = "settings.sell.autoRepair", as = "bool", vendor = true, flowDefault = true },
    { "sell.autoCleanup", to = "settings.sell.autoCleanup", as = "bool", vendor = true },
    { "sell.vendorUnpriced", to = "settings.sell.vendorUnpriced", as = "bool", vendor = true },
    -- The rest of selling
    -- Flow writes both as true at load when unset (Modules/Items/Vendor.lua:733-739).
    { "sell.enabled", to = "settings.sell.enabled", as = "bool", flowDefault = true },
    { "sell.junkAll", to = "settings.sell.junkAll", as = "bool", flowDefault = true },
    { "sell.repairWarn", to = "settings.sell.repairWarn" },
    { "sell.repairStop", to = "settings.sell.repairStop" },
    { "sell.never", to = "settings.sell.never", char = true },
    { "sell.mine", to = "settings.sell.mine", char = true },

    -- Navigation choices
    { "nav.enabled", to = "settings.nav.enabled" },
    { "nav.arrowStyle", to = "settings.nav.arrowStyle" },
    { "nav.arrowColor", to = "settings.nav.arrowColor" },
    { "nav.arrowPaths", to = "settings.nav.arrowPaths" },
    { "nav.arrowTurn", to = "settings.nav.arrowTurn" },
    { "nav.profArrow", to = "settings.nav.profArrow" },
    -- The profession arrow's text. In Flow nav.arrows.text.professions wins
    -- when it is set (Modules/Nav/Arrows.lua:243-245); so it does here.
    { "nav.profArrowText", to = "layout.arrows.text.prof", as = "bool", yield = true },
    { "nav.kinds", to = "settings.nav.kinds" },
    { "nav.sorter", to = "settings.nav.sorter" },
    { "nav.baseSorter", to = "settings.nav.baseSorter" },
    { "nav.learn", to = "settings.nav.learn" },
    { "nav.learnLegs", to = "settings.nav.learnLegs" },
    { "nav.crossings", to = "settings.nav.crossings" },
    { "nav.areaFirst", to = "settings.nav.areaFirst" },
    { "nav.areaHop", to = "settings.nav.areaHop" },
    { "nav.zoneFirst", to = "settings.nav.zoneFirst" },
    { "nav.zonesFirst", to = "settings.nav.zonesFirst" },
    { "nav.zonesOff", to = "settings.nav.zonesOff" },
    { "nav.zoneNotice", to = "settings.nav.zoneNotice" },
    { "nav.mapFlights", to = "settings.nav.mapFlights" },
    { "nav.mapLines", to = "settings.nav.mapLines" },
    { "nav.mapRoute", to = "settings.nav.mapRoute" },
    { "nav.mapListCollapsed", to = "settings.nav.mapListCollapsed" },
    { "nav.mapWaypointOnly", to = "settings.nav.mapWaypointOnly" },
    { "nav.mapZoneHere", to = "settings.nav.mapZoneHere" },
    { "nav.mapZoneLevels", to = "settings.nav.mapZoneLevels" },
    { "nav.minimapAreas", to = "settings.nav.minimapAreas" },
    { "nav.minimapPin", to = "settings.nav.minimapPin" },
    { "nav.nearbyNodes", to = "settings.nav.nearbyNodes" },
    { "nav.northUp", to = "settings.nav.northUp" },
    { "nav.pathAlpha", to = "settings.nav.pathAlpha" },
    { "nav.pathMotion", to = "settings.nav.pathMotion" },
    { "nav.questBuy", to = "settings.nav.questBuy" },
    { "nav.showHidden", to = "settings.nav.showHidden" },
    { "nav.taxiMark", to = "settings.nav.taxiMark" },
    { "nav.groupVisits", to = "settings.nav.groupVisits" },
    { "nav.holdHard", to = "settings.nav.holdHard" },
    { "nav.dungeonPrep", to = "settings.nav.dungeonPrep" },
    { "nav.dungeonSuggest", to = "settings.nav.dungeonSuggest" },
    { "nav.drawerOpen", to = "settings.nav.drawerOpen" },
    { "nav.focusKinds", to = "settings.nav.focusKinds" },
    { "nav.waypoint", to = "settings.nav.waypoint", as = "spot" },
    { "nav.waypointNote", to = "settings.nav.waypointNote" },
    { "nav.hidden", to = "settings.nav.hidden", char = true },
    { "nav.zonesOn", to = "settings.nav.zonesOn", char = true },
    { "nav.zoneNo", to = "settings.nav.zoneNo", char = true },
    { "nav.dungeonLong", to = "settings.nav.dungeonLong", char = true },
    { "nav.dungeonOnly", to = "settings.nav.dungeonOnly", char = true },
    { "nav.selectedKey", to = "state.nav.selectedKey", char = true },
    { "nav.focus", to = "state.nav.focus", char = true },
    { "nav.stopsShown", to = "state.nav.stopsShown", char = true },
    { "nav.stopsArea", to = "state.nav.stopsArea", char = true },
    { "nav.arrowModern", drop = BOOKKEEPING },
    { "nav.gatesRule", drop = BOOKKEEPING },
    { "nav.mode", drop = OLDER_NAME, beside = "nav.kinds", dropAlone = OLDER_NAME_ALONE },
    { "nav.professions", drop = OLDER_NAME, beside = "nav.kinds", dropAlone = OLDER_NAME_ALONE },
    { "nav.taxiTrip", drop = SESSION },
    { "nav.deferred", drop = SESSION },
    { "nav.dungeonRun", drop = SESSION },
    { "nav.dungeonIn", drop = SESSION },
    { "nav.wayTips", drop = ONCE },
    { "nearFirst", to = "settings.nav.nearFirst" },

    -- Other choices, kept under the name of the Flow section they came from
    { "actions.enabled", to = "settings.actions.enabled" },
    { "actions.loot", to = "settings.actions.loot" },
    { "actions.questItem", to = "settings.actions.questItem" },
    { "actions.res", to = "settings.actions.res" },
    { "actions.skin", to = "settings.actions.skin" },
    { "actions.stations", to = "settings.actions.stations" },
    { "actions.travel", to = "settings.actions.travel" },
    { "actions.weapons", to = "settings.actions.weapons" },
    { "actions.dryAt", drop = CACHE },
    { "actions.fishedAt", drop = CACHE },
    { "actions.friendPlatesByFlow", drop = BOOKKEEPING },
    { "advisor.enabled", to = "settings.advisor.enabled" },
    { "advisor.hidden", to = "settings.advisor.hidden", char = true },
    { "ah.duration", to = "settings.auction.duration" },
    { "ah.postOff", to = "settings.auction.postOff" },
    { "ah.watch", to = "settings.auction.watch" },
    { "ah.chartClick", to = "settings.auction.chartClick", as = "bool" },
    { "ah.posts", drop = CACHE },
    { "ah.lastFull", drop = CACHE },
    { "ah.lastScan", drop = CACHE },
    { "bags.enabled", to = "settings.bags.enabled" },
    { "banker.rules", to = "settings.banker.rules" },
    { "banker.autoCleanup", to = "settings.banker.autoCleanup" },
    { "banker.off", to = "settings.banker.off" },
    { "banker.parked", to = "state.banker.parked", char = true },
    { "buffButton.enabled", to = "settings.buffButton.enabled", as = "bool" },
    { "buffButton.key", to = "settings.buffButton.key", as = "key" },
    { "buffButton.key2", to = "settings.buffButton.key2", as = "key" },
    { "buffButton.dock", to = "settings.buffButton.dock", as = "bool" },
    { "buffButton.always", to = "settings.buffButton.always", as = "bool" },
    { "buffButton.care", to = "settings.buffButton.care", as = "bool" },
    { "buffButton.keepOnMain", to = "settings.buffButton.keepOnMain", as = "bool" },
    { "bonus.enabled", to = "settings.bonus.enabled" },
    -- The speech toggle (Modules/Bonus.lua): a choice, not a notice flag.
    { "bonus.spoken", to = "settings.bonus.spoken" },
    { "camera.maxZoom", to = "settings.camera.maxZoom" },
    { "cast.key", to = "settings.cast.key" },
    { "cast.key2", to = "settings.cast.key2" },
    { "cast.altItem", to = "settings.cast.altItem" },
    { "cast.ctrlTarget", to = "settings.cast.ctrlTarget" },
    { "cast.shiftHeal", to = "settings.cast.shiftHeal" },
    { "cast.formKey", to = "settings.cast.formKey" },
    { "cast.clickSlots", to = "settings.cast.clickSlots" },
    { "cast.healTipShown", drop = ONCE },
    { "colorblind", to = "settings.general.colorblind" },
    { "gear.enabled", to = "settings.gear.enabled" },
    { "gear.keepBar", to = "settings.gear.keepBar" },
    { "gear.keepOffspec", to = "settings.gear.keepOffspec" },
    { "gear.rollHints", to = "settings.gear.rollHints" },
    { "gear.setDefault", to = "settings.gear.setDefault" },
    { "gear.setIconSize", to = "settings.gear.setIconSize" },
    { "gear.setIcons", to = "settings.gear.setIcons" },
    { "gear.mySets", to = "settings.gear.mySets" },
    { "gear.keepSet", to = "settings.gear.keepSet", char = true },
    { "gear.setIcon", to = "settings.gear.setIcon", char = true },
    { "gear.setRoles", to = "settings.gear.setRoles", char = true },
    { "hearth.off", to = "settings.hearth.off" },
    { "invites.friends", to = "settings.invites.friends" },
    { "log.auto", to = "settings.log.auto" },
    { "loot.auto", to = "settings.loot.auto" },
    { "loot.skipJunk", to = "settings.loot.skipJunk" },
    { "loot.skinWarned", drop = ONCE },
    { "meters.always", to = "settings.meters.always" },
    { "meters.decimals", to = "settings.meters.decimals" },
    { "meters.mode", to = "settings.meters.mode" },
    { "meters.off", to = "settings.meters.off" },
    { "meters.rows", to = "settings.meters.rows" },
    { "meters.span", to = "settings.meters.span" },
    { "meters.when", to = "settings.meters.when" },
    { "meters.whenBefore", to = "settings.meters.whenBefore" },
    { "paladinSeal", to = "settings.paladin.seal", char = true },
    { "paladinSealCast", to = "settings.paladin.sealCast", char = true },
    { "paladinBlessing", to = "settings.paladin.blessing", char = true },
    { "paladinBlessingCast", to = "settings.paladin.blessingCast", char = true },
    { "perf.lite", to = "settings.perf.lite" },
    { "plateCombo.off", to = "settings.plateCombo.off" },
    { "plateThreat.always", to = "settings.plateThreat.always" },
    { "plateThreat.off", to = "settings.plateThreat.off" },
    { "prof.chosen", to = "settings.prof.chosen", char = true },
    { "prof.plan", to = "settings.prof.plan", char = true },
    { "prof.remind", to = "settings.prof.remind", char = true },
    { "prof.snoozeLevel", to = "settings.prof.snoozeLevel", char = true },
    { "prof.lastKey", drop = BOOKKEEPING },
    { "prof.suggestKey", drop = BOOKKEEPING },
    { "quests.enabled", to = "settings.quests.enabled" },
    { "quests.autoAccept", to = "settings.quests.autoAccept" },
    { "quests.autoTurnIn", to = "settings.quests.autoTurnIn" },
    { "quests.share", to = "settings.quests.share" },
    { "rotation.enabled", to = "settings.rotation.enabled" },
    { "rotation.locked", to = "settings.rotation.locked" },
    { "rotation.overheal", to = "settings.rotation.overheal" },
    { "rotation.panicPct", to = "settings.rotation.panicPct" },
    { "rotation.autoAttack", to = "settings.rotation.autoAttack" },
    { "rotation.campKits", to = "settings.rotation.campKits" },
    { "rotation.campSit", to = "settings.rotation.campSit" },
    { "rotation.friendTarget", to = "settings.rotation.friendTarget" },
    { "rotation.groupBuffs", to = "settings.rotation.groupBuffs" },
    { "rotation.recoverCannibalize", to = "settings.rotation.recoverCannibalize" },
    { "rotation.recoverSmart", to = "settings.rotation.recoverSmart" },
    { "rotation.recoverDrink", to = "settings.rotation.recoverDrink" },
    { "rotation.recoverOrder", to = "settings.rotation.recoverOrder" },
    -- Modules/BuffItems.lua:1140-1152, Modules/Rotation/Engine.lua:669-673
    { "rotation.recoverBandage", to = "settings.rotation.recoverBandage" },
    { "rotation.recoverFood", to = "settings.rotation.recoverFood" },
    { "rotation.recoverBuffFood", to = "settings.rotation.recoverBuffFood" },
    { "rotation.recoverHeal", to = "settings.rotation.recoverHeal" },
    { "rotation.bandageRank", to = "settings.rotation.bandageRank" },
    { "rotation.emergencyItems", to = "settings.rotation.emergencyItems" },
    { "rotation.statusIcons", to = "settings.rotation.statusIcons" },
    { "rotation.deck", to = "settings.rotation.deck" },
    { "rotation.debug", drop = DIAGNOSTIC },
    { "settings.gameButtons", to = "settings.general.gameButtons" },
    { "settings.groupTip", to = "settings.general.groupTip" },
    { "settings.haveCount", to = "settings.general.haveCount" },
    { "settings.moveGuides", to = "settings.general.moveGuides" },
    { "settings.tipsBeside", to = "settings.general.tipsBeside" },
    { "sound.auto", to = "settings.sound.auto" },
    { "spec.role", to = "settings.spec.role", char = true },
    { "spellbar.offer", to = "settings.spellbar.offer" },
    { "spellbar.upgradeRanks", to = "settings.spellbar.upgradeRanks" },
    { "spellbar.muted", to = "settings.spellbar.muted", char = true },
    { "splash.enabled", to = "settings.splash.enabled" },
    { "splash.short", to = "settings.splash.short" },
    { "tracker.enabled", to = "settings.tracker.enabled" },
    { "tracker.dock", to = "settings.tracker.dock" },
    { "tracker.gameTracker", to = "settings.tracker.gameTracker" },
    { "tracker.open", to = "settings.tracker.open" },
    { "tracker.hereInit", drop = ONCE },
    { "tracker.init", drop = ONCE },
    { "tracker.questieSeen", drop = ONCE },
    { "trader.off", to = "settings.trader.off" },
    { "trader.quiet", to = "settings.trader.quiet" },
    { "trader.share", to = "settings.trader.share" },

    -- Whole sections left behind
    { "api", drop = "what the game client can do; found again at every login" },
    { "audit", drop = DIAGNOSTIC },
    { "autopush", drop = "a record of Flow's own action bar moves; means nothing without Flow" },
    { "bank", drop = CACHE },
    { "chat", drop = "the chat bridge's queue and session state; no successor" },
    { "diag", drop = DIAGNOSTIC },
    { "reveal", drop = "Flow's feature-reveal progress; no successor" },
    { "setup", drop = "Flow's first-run progress and its window; no successor" },
}

local ROW, HAS_KEYS = {}, {}
for i = 1, #MAP do
    local row = MAP[i]
    ROW[row[1]] = row
    local section = row[1]:match("^(.-)%.")
    if section then HAS_KEYS[section] = true end
end

--------------------------------------------------------------------------------
-- Small pure helpers
--------------------------------------------------------------------------------
local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

-- A copy fit to be saved: finite numbers, text, true/false and tables of
-- those. Anything else is left out (a number that is not a number, and
-- either infinity, too), and so is a table that holds itself.
local function plain(v, seen)
    local kind = type(v)
    if kind == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return v
    end
    if kind == "string" or kind == "boolean" then return v end
    if kind ~= "table" then return nil end
    seen = seen or {}
    if seen[v] then return nil end
    seen[v] = true
    local out = {}
    for key, value in pairs(v) do
        local keyKind = type(key)
        if keyKind == "number" or keyKind == "string" then out[key] = plain(value, seen) end
    end
    seen[v] = nil
    return out
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function split(path)
    local parts = {}
    for seg in (path .. "."):gmatch("(.-)%.") do parts[#parts + 1] = seg end
    return parts
end

local function getPath(root, path)
    local at = root
    for _, seg in ipairs(split(path)) do
        if type(at) ~= "table" then return nil end
        at = at[seg]
    end
    return at
end

local function mergeInto(dst, src)
    for key, value in pairs(src) do
        if type(value) == "table" and type(dst[key]) == "table" then
            mergeInto(dst[key], value)
        else
            dst[key] = value
        end
    end
end

-- Two rows may land in one table (nav.point and nav.arrows): tables merge.
local function put(root, path, value)
    local parts = split(path)
    local at = root
    for i = 1, #parts - 1 do
        if type(at[parts[i]]) ~= "table" then at[parts[i]] = {} end
        at = at[parts[i]]
    end
    local last = parts[#parts]
    if type(value) == "table" and type(at[last]) == "table" then
        mergeInto(at[last], value)
    else
        at[last] = value
    end
end

--------------------------------------------------------------------------------
-- KIND: how a value is checked and copied. Each is
--   fn(value, label, note) -> the clean copy, or nil and a reason
-- A kind that keeps a value but not as it was found also returns, third, why
-- it changed it; that goes on result.adjusted.
-- note(label, reason [, why]) records a part that was left out of an
-- otherwise good value; why is "malformed" unless given. Nothing here keeps
-- a reference to the input.
--------------------------------------------------------------------------------
local KIND = {}

local function clean(v, label, note, seen)
    local kind = type(v)
    if kind == "boolean" or kind == "string" then return v end
    if kind == "number" then
        if finite(v) then return v end
        return nil, "not a finite number"
    end
    if kind ~= "table" then return nil, "a " .. kind .. " cannot be saved data" end
    if seen[v] then return nil, "a table that contains itself" end
    seen[v] = true
    local out = {}
    for _, key in ipairs(sortedKeys(v)) do
        local at = label .. "." .. tostring(key)
        if type(key) == "string" or finite(key) then
            local value, why = clean(v[key], at, note, seen)
            if value == nil then note(at, why) else out[key] = value end
        else
            note(at, "a key that is not a name or a number")
        end
    end
    seen[v] = nil
    return out
end

function KIND.any(v, label, note)
    return clean(v, label, note, {})
end

-- Learned data is always a table of entries; a lone value there is damage.
function KIND.tree(v, label, note)
    if type(v) ~= "table" then return nil, "expected a table, found a " .. type(v) end
    return clean(v, label, note, {})
end

function KIND.bool(v)
    if type(v) == "boolean" then return v end
    return nil, "expected true or false, found a " .. type(v)
end

function KIND.positive(v)
    if finite(v) and v > 0 then return v end
    return nil, "expected a number above zero"
end

-- A frame size. The limits are the ones the readers hold a size to
-- (Import/Stored.lua, from Flow's Modules/MoveHandle.lua:11-19); a size
-- outside them is stored at the nearest limit and reported as changed. A size
-- within them is stored exactly as found: rounding stays with the reader.
local SIZE_MIN, SIZE_MAX = 0.5, 2
local SIZE_CHANGED = "outside the sizes a frame can take (" .. SIZE_MIN .. " to " .. SIZE_MAX
    .. "); the nearest one was kept"

function KIND.size(v)
    if not finite(v) or v <= 0 then return nil, "expected a number above zero" end
    if v < SIZE_MIN then return SIZE_MIN, nil, SIZE_CHANGED end
    if v > SIZE_MAX then return SIZE_MAX, nil, SIZE_CHANGED end
    return v
end

-- A key binding: a string with something in it.
function KIND.key(v)
    if type(v) == "string" and v ~= "" then return v end
    if type(v) == "string" then return nil, "an empty key binding" end
    return nil, "expected a key binding, found a " .. type(v)
end

-- The nine places on a frame a position can hang from.
local ANCHOR = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- A frame position: { anchor, relative anchor, x, y }. Offsets may be negative.
function KIND.point(v)
    if type(v) ~= "table" then return nil, "expected a position, found a " .. type(v) end
    if type(v[1]) ~= "string" or type(v[2]) ~= "string" then return nil, "a position without its two anchors" end
    if not ANCHOR[v[1]] or not ANCHOR[v[2]] then return nil, "a position with an anchor no frame has" end
    if not finite(v[3]) or not finite(v[4]) then return nil, "a position whose offsets are not numbers" end
    return { v[1], v[2], v[3], v[4] }
end

-- A spot on a map: map id plus x, y as fractions of the map (0 to 1).
local function spotProblem(v)
    if type(v) ~= "table" then return "expected a spot, found a " .. type(v) end
    if not finite(v.map) then return "a spot without a map" end
    if not finite(v.x) or not finite(v.y) then return "a spot whose coordinates are not numbers" end
    if v.x < 0 or v.x > 1 or v.y < 0 or v.y > 1 then return "a coordinate outside the map (0 to 1)" end
    return nil
end

function KIND.spot(v, label, note)
    local problem = spotProblem(v)
    if problem then return nil, problem end
    return clean(v, label, note, {})
end

-- A spot in the world: continent plus world x, y (either sign).
local function worldSpot(v, label, note)
    if type(v) ~= "table" then return nil, "expected a world spot, found a " .. type(v) end
    if not finite(v.wx) or not finite(v.wy) then return nil, "a world spot whose coordinates are not numbers" end
    if v.cont ~= nil and not finite(v.cont) then return nil, "a world spot whose continent is not a number" end
    return clean(v, label, note, {})
end

-- A table of entries: each key checked by keyOk, each value by one(...).
local function map(v, label, note, keyOk, keyWhy, one)
    if type(v) ~= "table" then return nil, "expected a table, found a " .. type(v) end
    local out = {}
    for _, key in ipairs(sortedKeys(v)) do
        local at = label .. "." .. tostring(key)
        if keyOk(key) then
            local value, why = one(v[key], at, note)
            if value == nil then note(at, why) else out[key] = value end
        else
            note(at, keyWhy)
        end
    end
    return out
end

-- A list: entries kept in order, bad ones left out, no holes.
local function list(v, label, note, one)
    if type(v) ~= "table" then return nil, "expected a list, found a " .. type(v) end
    local out = {}
    for _, key in ipairs(sortedKeys(v)) do
        local at = label .. "." .. tostring(key)
        if finite(key) then
            local value, why = one(v[key], at, note)
            if value == nil then note(at, why) else out[#out + 1] = value end
        else
            note(at, "a name in a list")
        end
    end
    return out
end

local function isName(key) return type(key) == "string" and key ~= "" end
local function isId(key) return finite(key) and key > 0 end

function KIND.places(v, label, note)
    return map(v, label, note, isName, "a place without a name", KIND.spot)
end

function KIND.spots(v, label, note)
    return list(v, label, note, KIND.spot)
end

function KIND.worldList(v, label, note)
    return list(v, label, note, worldSpot)
end

-- [quest id][objective index] = list of spots
function KIND.questSpots(v, label, note)
    return map(v, label, note, isId, "a quest key that is not an id", function(quest, questLabel)
        return map(quest, questLabel, note, finite, "an objective key that is not a number", function(spots, at)
            return list(spots, at, note, KIND.spot)
        end)
    end)
end

function KIND.flights(v, label, note)
    return map(v, label, note, isName, "a flight point without a name", worldSpot)
end

function KIND.times(v, label, note)
    return map(v, label, note, isName, "a flight without its two ends", function(seconds)
        if finite(seconds) and seconds > 0 then return seconds end
        return nil, "a flight time that is not above zero"
    end)
end

function KIND.prices(v, label, note)
    return map(v, label, note, isId, "a price key that is not an item id", function(copper)
        if finite(copper) and copper >= 0 then return copper end
        return nil, "a price that is not zero or more"
    end)
end

local ARROW_MODES = { stacked = true, separate = true }

-- Flow's name for each arrow, and Z-Flow's (Nav/ArrowLayout.lua ARROW_KEYS).
local ARROW_NAMES = { quest = "quest", professions = "prof" }
local NOT_AN_ARROW = "not an arrow this importer carries over; left behind"
local QUEST_PLACE = "Flow keeps the quest arrow's place in nav.point and never reads this one;"
    .. " nav.point is what is imported"

-- One part of the arrow layout (places, hidden or text), keyed by Z-Flow's
-- arrow names. Empty when nothing in it could be kept.
local function arrowPart(v, at, note, one, isPlaces)
    local checked, why = map(v, at, note, isName, "an arrow without a name", one)
    if checked == nil then return nil, why end
    local out = {}
    for _, name in ipairs(sortedKeys(checked)) do
        local label = at .. "." .. name
        if not ARROW_NAMES[name] then
            note(label, NOT_AN_ARROW, "dropped")
        elseif isPlaces and name == "quest" then
            note(label, QUEST_PLACE, "dropped")
        else
            out[ARROW_NAMES[name]] = checked[name]
        end
    end
    return out
end

function KIND.arrows(v, label, note)
    if type(v) ~= "table" then return nil, "expected a table, found a " .. type(v) end
    local out = {}
    for _, key in ipairs(sortedKeys(v)) do
        local value, at = v[key], label .. "." .. tostring(key)
        if key == "mode" then
            if ARROW_MODES[value] then out.mode = value else note(at, "not an arrow layout this importer knows") end
        elseif key == "points" or key == "hidden" or key == "text" then
            local part, why = arrowPart(value, at, note, key == "points" and KIND.point or KIND.bool, key == "points")
            if part == nil then note(at, why) elseif next(part) ~= nil then out[key] = part end
        else
            note(at, "not a part of the arrow layout this importer knows")
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- FromFlow
--------------------------------------------------------------------------------
local CATEGORIES = { "places", "flights", "prices", "facts", "fights", "settings", "layout", "state" }

local function categoryOf(path)
    local first, second = path:match("^([^.]+)%.?([^.]*)")
    if first == "learned" then return second end
    return first
end

local function size(v)
    if type(v) ~= "table" then return 1 end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    return n
end

local function skeleton(scope)
    if scope == "account" then
        return {
            schema = SCHEMA, settings = {}, layout = {}, imports = {},
            learned = { places = {}, flights = {}, prices = {}, facts = {}, fights = {} },
        }
    end
    return { schema = SCHEMA, settings = {}, layout = {}, learned = {}, state = {} }
end

local function newRecord(sourceVersion)
    local counts = { dropped = 0, unknown = 0, malformed = 0, superseded = 0, adjusted = 0 }
    for _, name in ipairs(CATEGORIES) do counts[name] = 0 end
    return {
        source = "Flow",
        sourceVersion = sourceVersion,
        importer = IMPORTER_VERSION,
        schema = SCHEMA,
        counts = counts,
        vendorChoices = {},
        vendorSameAsFlowDefault = {},
        sameAsFlowDefault = {},
    }
end

local function refuse(reason, sourceVersion)
    local record = newRecord(sourceVersion)
    record.refused = reason
    return { ok = false, reason = reason, dropped = {}, adjusted = {}, record = record }
end

local function FromFlow(flowDb, flowCharDb)
    if flowDb ~= nil and type(flowDb) ~= "table" then
        return refuse("Flow's account data is a " .. type(flowDb) .. ", not a table; nothing was imported")
    end
    flowDb = flowDb or {}
    local version = flowDb.version
    if version == nil then version = 0 end
    if not finite(version) or version < 0 or version % 1 ~= 0 then
        return refuse("Flow's data version is not a version number (" .. tostring(version) .. "); nothing was imported")
    end
    if version > KNOWN_FLOW_VERSION then
        return refuse("Flow's data is at version " .. version .. " and this importer (version " .. IMPORTER_VERSION
            .. ") knows Flow data up to version " .. KNOWN_FLOW_VERSION
            .. "; nothing was imported, so nothing could be imported wrongly", version)
    end

    local out = { account = skeleton("account"), char = skeleton("char") }
    local record = newRecord(version)
    local dropped = {}

    local function leave(why, label, reason)
        dropped[#dropped + 1] = { key = label, why = why, reason = reason }
        record.counts[why] = record.counts[why] + 1
    end
    local function note(label, reason, why) leave(why or "malformed", label, reason) end
    local adjusted = {}
    local vendorToConfirm = {}

    local adopted = type(flowCharDb) == "table" and flowCharDb.adopted
    local taken = type(adopted) == "table" and adopted or {}

    local function apply(row, value, label)
        if row.meta then return end
        if row.parked then
            if type(value) ~= "table" then
                return leave("malformed", label, "expected a table, found a " .. type(value))
            end
            if next(value) == nil then return leave("dropped", label, PARKED_EMPTY) end
            for _, path in ipairs(sortedKeys(value)) do
                leave("dropped", label .. "." .. tostring(path), taken[path] == true and PARKED_TAKEN or PARKED_WAITING)
            end
            return
        end
        if row.drop then
            local alone = row.beside and getPath(flowDb, row.beside) == nil
            return leave("dropped", label, alone and row.dropAlone or row.drop)
        end
        local cleaned, why, changed = KIND[row.as or (row.to:find("^learned%.") and "tree" or "any")](value, label, note)
        if cleaned == nil then return leave("malformed", label, why) end
        if changed then
            -- Only a plain value is ever changed, so from holds no table of Flow's.
            adjusted[#adjusted + 1] = { key = label, from = value, to = cleaned, reason = changed }
            record.counts.adjusted = record.counts.adjusted + 1
        end
        if type(cleaned) == "table" and next(cleaned) == nil then return end
        local root = row.char and out.char or out.account
        if row.yield and getPath(root, row.to) ~= nil then
            return leave("superseded", label, "a newer Flow key holds this same choice; that one was used")
        end
        local sameAsDefault = row.flowDefault ~= nil and cleaned == row.flowDefault
        if sameAsDefault then record.sameAsFlowDefault[row[1]] = true end
        if row.vendor then
            record.vendorChoices[row[1]] = cleaned
            if sameAsDefault then record.vendorSameAsFlowDefault[row[1]] = true end
            if cleaned == true then
                -- Found on: listed for the player to confirm, written nowhere.
                vendorToConfirm[#vendorToConfirm + 1] = { key = row[1], to = row.to, sameAsFlowDefault = sameAsDefault }
                return
            end
        end
        put(root, row.to, cleaned)
        local category = categoryOf(row.to)
        record.counts[category] = record.counts[category] + size(cleaned)
    end

    -- One Flow path ("section" or "section.key") and the value found there.
    local function take(path, value, label)
        local row = ROW[path]
        if not HAS_KEYS[path] then
            if row then return apply(row, value, label) end
            return leave("unknown", label, "no row for this key in the mapping; left behind untouched")
        end
        if type(value) ~= "table" then
            return leave("malformed", label, "expected a table, found a " .. type(value))
        end
        local rest
        for _, key in ipairs(sortedKeys(value)) do
            local keyRow = type(key) == "string" and ROW[path .. "." .. key] or nil
            if keyRow then
                apply(keyRow, value[key], label .. "." .. key)
            elseif row then
                rest = rest or {}
                rest[key] = value[key]
            else
                leave("unknown", label .. "." .. tostring(key), "no row for this key in the mapping; left behind untouched")
            end
        end
        if rest then apply(row, rest, label) end
    end

    for _, key in ipairs(sortedKeys(flowDb)) do
        if type(key) == "string" and not key:find(".", 1, true) then
            take(key, flowDb[key], key)
        elseif type(key) == "string" then
            leave("unknown", key, "no row for this key in the mapping; left behind untouched")
        else
            leave("unknown", tostring(key), "a key that is not a name")
        end
    end

    -- The character's own values. While Flow is loaded they sit at their
    -- path in the account table; at logout Flow parks them under
    -- FlowCharDB.data[path] (Core.lua:182-232). A live value wins.
    if flowCharDb ~= nil and type(flowCharDb) ~= "table" then
        leave("malformed", "FlowCharDB", "expected a table, found a " .. type(flowCharDb))
    elseif flowCharDb then
        for _, key in ipairs(sortedKeys(flowCharDb)) do
            local label = "FlowCharDB." .. tostring(key)
            local value = flowCharDb[key]
            if key == "adopted" then
                leave("dropped", label, BOOKKEEPING)
            elseif key ~= "data" then
                leave("unknown", label, "no row for this key in the mapping; left behind untouched")
            elseif type(value) ~= "table" then
                leave("malformed", label, "expected a table, found a " .. type(value))
            else
                for _, path in ipairs(sortedKeys(value)) do
                    local at = label .. "." .. tostring(path)
                    if type(path) ~= "string" then
                        leave("unknown", at, "a key that is not a name")
                    elseif getPath(flowDb, path) ~= nil then
                        leave("superseded", at, "the account table holds a live value at this path; that one was used")
                    elseif ROW[path] or HAS_KEYS[path] then
                        take(path, value[path], at)
                    else
                        -- One field of a section that is left behind whole
                        -- (Flow parks autopush.seen, not autopush).
                        local whole = ROW[path:match("^([^.]+)%.") or ""]
                        if whole and whole.drop and not whole.parked then
                            leave("dropped", at, whole.drop)
                        else
                            leave("unknown", at, "no row for this key in the mapping; left behind untouched")
                        end
                    end
                end
            end
        end
    end

    table.sort(dropped, function(a, b)
        if a.key ~= b.key then return a.key < b.key end
        if a.why ~= b.why then return a.why < b.why end
        return a.reason < b.reason
    end)
    table.sort(vendorToConfirm, function(a, b) return a.key < b.key end)
    table.sort(adjusted, function(a, b) return a.key < b.key end)
    -- The record keeps its own copies of both lists, so what an import left
    -- behind or changed can still be read after the result is gone.
    record.dropped = plain(dropped)
    record.adjusted = plain(adjusted)
    out.account.imports[1] = copy(record)
    return {
        ok = true, account = out.account, char = out.char, dropped = dropped, adjusted = adjusted, record = record,
        vendorToConfirm = vendorToConfirm,
    }
end

--------------------------------------------------------------------------------
-- Merge
--------------------------------------------------------------------------------
local MERGED = {
    account = { "settings", "layout", "learned" },
    char = { "settings", "layout", "learned", "state" },
}

-- A table of named or numbered entries merges entry by entry; a list (a
-- position, a list of spots) is one value and is kept or added whole.
local function isList(t)
    return t[1] ~= nil
end

-- True when the stored setting at path `at` is no choice of the player's and
-- the import's value may take its place. choice = { model, prefix }: the
-- settings model to ask and the part of the path before its keys; a choice
-- with no model, or a key the model has no row for, compares types.
local function givesWay(choice, at, have, value)
    local model = choice.model
    if model and choice.prefix and at:sub(1, #choice.prefix) == choice.prefix then
        local key = at:sub(#choice.prefix + 1)
        if model:row(key) ~= nil then
            if model:check(key, have) == true then return false end
            return model:check(key, value) == true
        end
    end
    return type(have) ~= type(value)
end

local REFUSED = "the settings model refuses this value; it was not added"

-- What may be added at `at` where nothing is stored: a copy of the import's
-- value without anything the settings model refuses. Each refused value is
-- reported as skipped. nil when nothing is left to add.
local function fitting(choice, at, value, report, seen)
    local model = choice.model
    if not (model and choice.prefix and at:sub(1, #choice.prefix) == choice.prefix) then return copy(value) end
    local key = at:sub(#choice.prefix + 1)
    if model:row(key) ~= nil then
        if model:check(key, value) == true then return copy(value) end
        report.skipped[#report.skipped + 1] = { path = at, reason = REFUSED }
        return nil
    end
    if type(value) ~= "table" or isList(value) or next(value) == nil then return copy(value) end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local out = {}
    for _, name in ipairs(sortedKeys(value)) do
        out[name] = fitting(choice, at .. "." .. tostring(name), value[name], report, seen)
    end
    seen[value] = nil
    if next(out) == nil then return nil end
    return out
end

-- choice: a table for settings (see givesWay), nil otherwise. A stored
-- setting is the player's choice and is kept even when it equals the
-- default; one that does not fit is no choice and gives way. Where nothing
-- is stored the model is asked too: a value it refuses is not added.
local function fill(dst, src, defaults, path, report, choice)
    for _, key in ipairs(sortedKeys(src)) do
        local value, have = src[key], dst[key]
        local at = path .. "." .. tostring(key)
        local default
        if type(defaults) == "table" then default = defaults[key] end
        if have == nil or (type(have) == "table" and next(have) == nil and type(value) == "table") then
            local fit
            if choice then fit = fitting(choice, at, value, report) else fit = copy(value) end
            if fit ~= nil then
                dst[key] = fit
                report.added[#report.added + 1] = at
            end
        elseif type(have) == "table" and type(value) == "table" and not isList(have) and not isList(value) then
            fill(have, value, default, at, report, choice)
        elseif same(have, value) then
            report.skipped[#report.skipped + 1] = { path = at, reason = "the same value is already there" }
        elseif choice and givesWay(choice, at, have, value) then
            dst[key] = copy(value)
            report.added[#report.added + 1] = at
        elseif not choice and default ~= nil and same(have, default) then
            dst[key] = copy(value)
            report.added[#report.added + 1] = at
        else
            report.kept[#report.kept + 1] = at
            report.skipped[#report.skipped + 1] = { path = at, reason = "the player already has a value here; it was kept" }
        end
    end
end

local function shapeProblem(db, scope)
    if db == nil then return nil end
    if type(db) ~= "table" then return "the existing " .. scope .. " data is not a table" end
    if db.schema ~= nil and db.schema ~= SCHEMA then
        return "the existing " .. scope .. " data is at schema " .. tostring(db.schema)
            .. " and this importer writes schema " .. SCHEMA
    end
    for _, name in ipairs(MERGED[scope]) do
        if db[name] ~= nil and type(db[name]) ~= "table" then
            return "the existing " .. scope .. " data has a " .. name .. " that is not a table"
        end
    end
    if scope == "account" and db.imports ~= nil and type(db.imports) ~= "table" then
        return "the existing account data has an imports entry that is not a table"
    end
    return nil
end

local NOT_CONFIRMED = "a vendor automation Flow had on; the player did not confirm it, so it stays off"

-- The vendor gate. There is one: the merge below and Stored.Adopt
-- (Import/Stored.lua) both go through it.
--   Import.VendorGate(account, listed, confirmed) -> account, on, off
--     account    the import's account data ({ settings = { ... }, ... })
--     listed     the import's vendorToConfirm list, or nil
--     confirmed  { ["sell.autoRepair"] = true, ... }: the vendor automations
--                the player confirmed, by Flow key. Only a true counts.
--   Returns a copy of the account data in which a vendor automation is on
--   only where the player confirmed that one, and two lists of
--   { key = Flow key, to = where it sits }, each sorted by key: the ones
--   switched on and the ones left off. An on counts as found whether it is
--   in the list FromFlow made or was written into the settings some other
--   way. Any value at a vendor path that is not an off counts as an on: a
--   true, and a value of another type that a reader might take for one.
--   What it is given is not changed.
local function vendorGate(account, listed, confirmed)
    account = type(account) == "table" and copy(account) or {}
    local found = {}
    if type(listed) == "table" then
        for _, entry in ipairs(listed) do
            if type(entry) == "table" and type(entry.key) == "string" then found[entry.key] = true end
        end
    end
    for i = 1, #MAP do
        local row = MAP[i]
        if row.vendor then
            local parts = split(row.to)
            local chain, at = {}, account
            for depth = 1, #parts - 1 do
                at = type(at) == "table" and at[parts[depth]] or nil
                chain[depth] = at
            end
            local value
            if type(at) == "table" then value = at[parts[#parts]] end
            if value ~= nil and value ~= false then
                found[row[1]] = true
                at[parts[#parts]] = nil
                -- Leave no empty table behind, below the section itself.
                for depth = #parts - 1, 2, -1 do
                    if next(chain[depth]) ~= nil then break end
                    chain[depth - 1][parts[depth]] = nil
                end
            end
        end
    end
    local on, off = {}, {}
    for _, key in ipairs(sortedKeys(found)) do
        local row = ROW[key]
        if row and row.vendor then
            if type(confirmed) == "table" and confirmed[key] == true then
                put(account, row.to, true)
                on[#on + 1] = { key = key, to = row.to }
            else
                off[#off + 1] = { key = key, to = row.to }
            end
        end
    end
    return account, on, off
end

local NOT_CONFIRMED_OWN = "a vendor automation Flow had on; the player did not confirm it."
    .. " The player's own stored on was kept"
local SCOPES = { "account", "char" }

-- The settings model's key for a gate entry: where it sits, below settings.
local function modelKey(entry)
    return entry.to:match("^settings%.(.+)$") or entry.key
end

local function entries(list)
    local out = {}
    if type(list) == "table" then
        for _, entry in ipairs(list) do
            if type(entry) == "table" and type(entry.key) == "string" and type(entry.to) == "string" then
                out[#out + 1] = entry
            end
        end
    end
    return out
end

-- Both scopes go through the gate: the character's settings like the
-- account's. The list FromFlow made names account settings only.
local function gateScopes(gate, imported, confirmed)
    local source, on, off = {}, {}, {}
    for _, scope in ipairs(SCOPES) do
        local listed
        if scope == "account" then listed = imported.vendorToConfirm end
        local data, switched, left = gate(imported[scope], listed, confirmed)
        source[scope] = type(data) == "table" and data or {}
        on[scope], off[scope] = entries(switched), entries(left)
    end
    return source, on, off
end

local function switchedOn(db, to)
    local value = getPath(db, to)
    return value ~= nil and value ~= false
end

-- The gate as the merge reports it, written once the merge is done so it
-- says what ended up stored.
--   vendorConfirmed   Flow keys: a confirmed on that this merge stored. One
--                     the player's own stored value held back is in kept.
--   vendorLeftOff     model keys: found on, not confirmed, and off now.
--   vendorAlreadyOn   model keys: found on, not confirmed, and on all the
--                     same because the player's own data has it on.
-- Returns the confirmed ones for the saved record.
local function reportVendor(report, on, off, before, result)
    local landed, left, already = {}, {}, {}
    for _, scope in ipairs(SCOPES) do
        for _, entry in ipairs(on[scope]) do
            if getPath(before[scope], entry.to) ~= true and getPath(result[scope], entry.to) == true then
                landed[entry.key] = true
            end
        end
    end
    for _, scope in ipairs(SCOPES) do
        for _, entry in ipairs(off[scope]) do
            local own = switchedOn(result.account, entry.to) or switchedOn(result.char, entry.to)
            if own then already[modelKey(entry)] = true else left[modelKey(entry)] = true end
            report.skipped[#report.skipped + 1] = {
                path = scope .. "." .. entry.to, reason = own and NOT_CONFIRMED_OWN or NOT_CONFIRMED,
            }
        end
    end
    report.vendorConfirmed = sortedKeys(landed)
    report.vendorLeftOff = sortedKeys(left)
    report.vendorAlreadyOn = sortedKeys(already)
    return landed
end

local function Merge(existingAccount, existingChar, imported, defaults, confirmed, model)
    local report = {
        ok = true, added = {}, kept = {}, skipped = {}, counts = { added = 0, kept = 0, skipped = 0 },
        vendorConfirmed = {}, vendorLeftOff = {}, vendorAlreadyOn = {},
    }
    local problem
    if type(imported) ~= "table" then
        problem = "there is no import result to merge"
    elseif imported.ok ~= true or type(imported.account) ~= "table" or type(imported.char) ~= "table" then
        problem = "the import did not succeed: " .. tostring(imported.reason or "no reason given")
    else
        problem = shapeProblem(existingAccount, "account") or shapeProblem(existingChar, "char")
    end
    -- Looked up when called: the gate Stored.Adopt asks, not a copy of it.
    -- With no gate nothing is merged.
    local gate = ns.Import and ns.Import.VendorGate
    if not problem and type(gate) ~= "function" then problem = "the vendor gate is not loaded" end
    if problem then
        report.ok, report.reason = false, problem .. "; nothing was merged"
        return copy(existingAccount), copy(existingChar), report
    end

    -- The settings model loads after this file, so the shipped one is looked
    -- up here. Only a table that can be asked counts as a model.
    if model == nil then
        local Model = ns.Settings and ns.Settings.Model
        if Model and type(Model.Default) == "function" then model = Model.Default() end
    end
    if type(model) ~= "table" or type(model.row) ~= "function" or type(model.check) ~= "function" then
        model = nil
    end

    local source, on, off = gateScopes(gate, imported, confirmed)
    local result = { account = copy(existingAccount) or {}, char = copy(existingChar) or {} }
    for _, scope in ipairs({ "account", "char" }) do
        local db, base = result[scope], skeleton(scope)
        for key, value in pairs(base) do
            if db[key] == nil then db[key] = value end
        end
        local scopeDefaults = type(defaults) == "table" and defaults[scope] or nil
        for _, name in ipairs(MERGED[scope]) do
            local from = source[scope][name]
            if type(from) == "table" then
                local sectionDefaults
                if type(scopeDefaults) == "table" then sectionDefaults = scopeDefaults[name] end
                local choice
                if name == "settings" then
                    choice = {}
                    if scope == "account" then choice.model, choice.prefix = model, "account.settings." end
                end
                fill(db[name], from, sectionDefaults, scope .. "." .. name, report, choice)
            end
        end
    end
    local vendorConfirmed = reportVendor(report, on, off,
        { account = existingAccount, char = existingChar }, result)
    report.counts.added = #report.added
    report.counts.kept = #report.kept
    report.counts.skipped = #report.skipped

    -- plain, not copy: what the caller hands in may hold itself or a function.
    local record = plain(imported.record)
    if type(record) ~= "table" then record = {} end
    if type(record.dropped) ~= "table" then record.dropped = plain(imported.dropped) end
    if type(record.adjusted) ~= "table" then record.adjusted = plain(imported.adjusted) end
    record.merge = copy(report.counts)
    record.vendorConfirmed = vendorConfirmed
    local imports = result.account.imports
    imports[#imports + 1] = record
    return result.account, result.char, report
end

ns.Import = ns.Import or {}
ns.Import.FromFlow = FromFlow
ns.Import.Merge = Merge
ns.Import.VendorGate = vendorGate
ns.Import.flowMap = MAP
ns.Import.flowImporterVersion = IMPORTER_VERSION
ns.Import.flowKnownVersion = KNOWN_FLOW_VERSION
