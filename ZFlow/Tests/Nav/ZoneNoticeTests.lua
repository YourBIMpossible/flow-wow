-- Tests for the zone notice (ZFlow/Nav/ZoneNotice.lua; Flow-parity row
-- A2-24, the data half): after a while in a zone where whereNext lists no
-- quests in the player's level range and none of the player's quests has a
-- step, a notice with the zone, the reason and a zone with more. Data
-- only: no bar. Made-up maps, zones and quests, test only. Not tested in
-- game.
local _, ns = ...

local tests = {}

local function Z() return ns.Nav.ZoneNotice end
local function W() return ns.Nav.WhereNext end

local BARE, OTHER = 1500, 1501          -- zones whereNext does not list
local WOOD, FALL = 1429, 1436           -- zones it lists
local NAMES = { [BARE] = "Bare Hill", [OTHER] = "Far Shore", [WOOD] = "Near Wood", [FALL] = "West Fall" }

local function listed()
    return { { map = WOOD, name = "Near Wood", count = 3 }, { map = FALL, name = "West Fall", count = 2 } }
end

local function facts()
    return { level = 20, doneKnown = true, logKnown = true, raceKnown = true, classKnown = true, noZone = 0 }
end

-- A started kernel over the fake client, the player in opts.zone (BARE
-- when not given). whereNext and zoneLeft are stand-ins: st.list, st.why
-- and st.info are what Zones() answers, st.asks how often it was asked;
-- st.left is what zoneLeft's Left() lists, st.leftUnknown makes it answer
-- nil. st.events are the arguments of every Z.EVENT.
local function start(opts)
    opts = opts or {}
    local st = { list = listed(), info = facts(), asks = 0, left = {}, events = {}, n = 0 }
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setLevel(20)
    local zone = opts.zone or BARE
    if not opts.noZone then
        c.setZone(0, zone)
        c.setPosition(zone, 0.5, 0.5)
    end
    for map, name in pairs(NAMES) do c.setMapName(map, name) end
    local k = ns.Kernel({}, c)
    k:Module({ name = W().NAME, provides = { Zones = function()
        st.asks = st.asks + 1
        if st.list == nil then return nil, st.why end
        return st.list, nil, st.info
    end } })
    if not opts.noLeft then
        k:Module({ name = "zoneLeft", provides = { Left = function()
            if st.leftUnknown then return nil, nil, "not known" end
            return st.left, 0
        end } })
    end
    Z().Declare(k)
    k.bus:on("test", Z().EVENT, function(map)
        st.n = st.n + 1
        st.events[st.n] = map or false
    end)
    k:Boot()
    -- Lead sections 659 and 661: the setting is OFF as made. Every case
    -- below but the ones about the default switches it on first.
    if not opts.asMade then k.settings:set(Z().SETTING, true) end
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, st
end

-- One frame a second.
local function wait(c, seconds) c.advance(seconds, seconds) end

-- Long enough in the zone for the notice to be up, when there is one.
local function settle(c) wait(c, Z().SETTLE + 3 * Z().CHECK) end

local function notice(k) return k.use(Z().NAME).Notice() end

local function enter(c, zone)
    c.setZone(0, zone)
    if zone ~= nil then c.setPosition(zone, 0.5, 0.5) end
    c.fire("ZONE_CHANGED_NEW_AREA")
end

-- ------------------------------------------------------------------ pure

tests["zone notice: Flow's numbers, a look every 2 seconds and 30 seconds in the zone first"] = function(t)
    t.eq(Z().CHECK, 2)
    t.eq(Z().SETTLE, 30)
    t.eq(Z().Settled(29), false)
    t.eq(Z().Settled(30), true)
    t.eq(Z().Settled(45), true)
    t.eq(Z().Settled(nil), false)
    t.eq(Z().Settled(5, 5), true)
end

tests["zone notice: on a flight, in an instance or in a fight is busy; not known is not"] = function(t)
    t.eq(Z().Busy(true, nil, nil), true)
    t.eq(Z().Busy(nil, { inside = true, kind = "party" }, nil), true)
    t.eq(Z().Busy(nil, nil, true), true)
    t.eq(Z().Busy(false, { inside = false, kind = "none" }, false), false)
    t.eq(Z().Busy(nil, nil, nil), false)
end

-- A capital city is no questing zone. The predecessor was silent there
-- (a city never had a row of its own); here whereNext does not list a
-- city either, so without this rule every visit to a capital would raise
-- the notice. Red before: there was no Z.City, and a city was not busy.
tests["zone notice: a capital city is told apart, any other map is not"] = function(t)
    t.ok(type(Z().City) == "function", "Z.City is there")
    if type(Z().City) ~= "function" then return end
    local walled = ns.Nav.GATE_WALLED
    t.ok(type(walled) == "table" and next(walled) ~= nil, "the capitals of Nav/Gates.lua are there")
    if type(walled) ~= "table" then return end
    for map in pairs(walled) do
        t.eq(Z().City(map), true, "a capital: " .. tostring(map))
    end
    t.eq(Z().City(BARE), false, "a zone that is no capital")
    t.eq(Z().City(nil), false)
end

tests["zoneNotice module: in a capital city there is no notice, however long the player stays"] = function(t)
    local city = next(ns.Nav.GATE_WALLED or {})
    t.ok(city ~= nil, "a capital to stand in")
    if city == nil then return end
    local k, c = start({ zone = city })
    settle(c)
    t.eq(notice(k), nil, "no notice in a city")
    wait(c, Z().SETTLE * 3)
    t.eq(notice(k), nil, "nor later")
    t.eq(k.problems:count(), 0)
end

tests["zone notice: a zone is listed when whereNext's answer holds its map"] = function(t)
    local list = listed()
    t.ok(Z().Listed(list, WOOD) == list[1], "the zone's own row")
    t.eq(Z().Listed(list, BARE), nil)
    t.eq(Z().Listed(nil, WOOD), nil)
    t.eq(Z().Listed(list, nil), nil)
end

tests["zone notice: the better zone is the first other zone of whereNext's answer"] = function(t)
    local list = listed()
    local b = Z().Better(list, BARE)
    t.eq(b, { map = WOOD, name = "Near Wood", count = 3 })
    t.ok(b ~= list[1], "a copy, not whereNext's own row")
    t.eq(Z().Better(list, WOOD), { map = FALL, name = "West Fall", count = 2 })
    t.eq(Z().Better({}, BARE), nil)
    t.eq(Z().Better(nil, BARE), nil)
    t.eq(Z().Better({ { map = WOOD, count = 0 }, "x" }, BARE), nil)
end

tests["zone notice: wanted only with every part known and nothing against it"] = function(t)
    local function s(over)
        local out = { zone = BARE, on = true, answered = false, busy = false, settled = true, listed = false, mine = 0 }
        for key, v in pairs(over or {}) do out[key] = v end
        return out
    end
    t.eq(Z().Wanted(s()), true)
    t.eq(Z().Wanted(s({ on = false })), false)
    t.eq(Z().Wanted(s({ answered = true })), false)
    t.eq(Z().Wanted(s({ busy = true })), false)
    t.eq(Z().Wanted(s({ settled = false })), false)
    t.eq(Z().Wanted(s({ listed = true })), false)
    t.eq(Z().Wanted(s({ mine = 2 })), false)
    local unknown = s()
    unknown.listed = nil
    t.eq(Z().Wanted(unknown), false, "whether it is listed is not known")
    unknown = s()
    unknown.mine = nil
    t.eq(Z().Wanted(unknown), false, "your quests here are not known")
    unknown = s()
    unknown.zone = nil
    t.eq(Z().Wanted(unknown), false, "the zone is not known")
    t.eq(Z().Wanted(nil), false)
end

-- ---------------------------------------------------------------- module

-- Lead sections 659 and 661 (Zen's CHANGES-1): the setting is OFF as made,
-- until the bar is drawn and seen in game; and only a plain true is on.
-- Red before: the default was on, and anything but a plain false was on.
tests["zoneNotice module: started, and its setting is off as made, so there is no notice"] = function(t)
    local k, c, st = start({ asMade = true })
    t.eq(Z().NAME, "zoneNotice")
    t.eq((k:ModuleState(Z().NAME)), "started")
    t.eq(k.settings:get(Z().SETTING), false, "off until the player switches it on")
    settle(c)
    t.eq(notice(k), nil, "off as made: no notice in a zone that would have one")
    t.eq(st.asks, 0, "and whereNext is not asked")
    k.settings:set(Z().SETTING, true)
    wait(c, 2 * Z().CHECK)
    t.ok(notice(k) ~= nil, "switched on: the notice")
    t.eq(k.problems:count(), 0)
end

tests["zoneNotice module: a setting that cannot be read is off"] = function(t)
    local k, c, st = start()
    local real = k.settings.get
    k.settings.get = function(self, key, ...)
        if key == Z().SETTING then error("the setting cannot be read") end
        return real(self, key, ...)
    end
    settle(c)
    k.settings.get = real
    t.eq(notice(k), nil, "not readable: off, no notice")
    t.eq(st.asks, 0, "and whereNext is not asked")
end

tests["zoneNotice module: a zone whereNext lists gives no notice"] = function(t)
    local k, c, st = start({ zone = WOOD })
    settle(c)
    t.eq(notice(k), nil)
    t.ok(st.asks >= 1, "whereNext was asked")
    t.eq(st.n, 0)
    t.eq(k.problems:count(), 0)
end

tests["zoneNotice module: a zone it does not list gives the zone, the reason and the best other zone"] = function(t)
    local k, c, st = start()
    settle(c)
    local n = notice(k)
    t.ok(type(n) == "table", "a notice")
    if type(n) ~= "table" then return end
    t.eq(n.zone, { map = BARE, name = "Bare Hill" })
    t.eq(n.reason, Z().WHY_NONE)
    t.eq(n.count, 0)
    t.eq(n.better, { map = WOOD, name = "Near Wood", count = 3 })
    t.eq(n.unplaced, 0)
    t.eq(n.info, facts())
    t.ok(n.info ~= st.info, "the facts are a copy")
    t.eq(k.problems:count(), 0)
end

tests["zoneNotice module: quests whereNext could not place are said in the notice"] = function(t)
    local k, c, st = start()
    st.info.noZone = 4
    settle(c)
    local n = notice(k)
    t.ok(type(n) == "table", "a notice")
    if type(n) ~= "table" then return end
    t.eq(n.unplaced, 4)
end

tests["zoneNotice module: with no other zone listed the notice has no better zone"] = function(t)
    local k, c, st = start()
    st.list = {}
    settle(c)
    local n = notice(k)
    t.ok(type(n) == "table", "a notice")
    if type(n) ~= "table" then return end
    t.eq(n.better, nil)
    t.eq(n.zone.map, BARE)
end

tests["zoneNotice module: a zone the client does not name has no name"] = function(t)
    local k, c = start()
    c.setMapName(BARE, nil)
    settle(c)
    local n = notice(k)
    t.ok(type(n) == "table", "a notice")
    if type(n) ~= "table" then return end
    t.eq(n.zone, { map = BARE })
end

tests["zoneNotice module: nothing before 30 seconds in the zone"] = function(t)
    local k, c, st = start()
    wait(c, Z().SETTLE - Z().CHECK)
    t.eq(notice(k), nil)
    t.eq(st.asks, 0, "whereNext is not asked before then")
    wait(c, 2 * Z().CHECK)
    t.ok(notice(k) ~= nil, "the notice after the wait")
end

tests["zoneNotice module: a break in the zone starts the wait again"] = function(t)
    local k, c = start()
    wait(c, 20)
    enter(c, nil)
    enter(c, BARE)
    wait(c, 20)
    t.eq(notice(k), nil, "20 seconds since coming back")
    wait(c, 14)
    t.ok(notice(k) ~= nil, "the notice 30 seconds after coming back")
end

tests["zoneNotice module: passing through a zone raises nothing"] = function(t)
    local k, c, st = start()
    wait(c, 20)
    enter(c, WOOD)
    settle(c)
    t.eq(notice(k), nil)
    t.eq(st.n, 0)
end

tests["zoneNotice module: a quest of yours with a step here gives no notice"] = function(t)
    local k, c, st = start()
    st.left = { { quest = 9, title = "In The Log", steps = 1, turnIn = false } }
    settle(c)
    t.eq(notice(k), nil)
    st.left = {}
    c.fire("QUEST_LOG_UPDATE")
    wait(c, 2 * Z().CHECK)
    t.ok(notice(k) ~= nil, "the notice once the quest is gone from here")
end

tests["zoneNotice module: your quests here not known gives no notice"] = function(t)
    local k, c, st = start()
    st.leftUnknown = true
    settle(c)
    t.eq(notice(k), nil)
    local k2, c2 = start({ noLeft = true })
    settle(c2)
    t.eq(notice(k2), nil, "no zoneLeft module at all")
    t.eq((k2:ModuleState(Z().NAME)), "started")
end

tests["zoneNotice module: whereNext still reading gives none yet, and one once the read finished"] = function(t)
    local k, c, st = start()
    st.list, st.why = nil, W().WHY_READING
    settle(c)
    t.eq(notice(k), nil)
    t.ok(st.asks >= 1, "asked")
    st.list = listed()
    wait(c, 2 * Z().CHECK)
    local n = notice(k)
    t.ok(type(n) == "table", "a notice")
    if type(n) ~= "table" then return end
    t.eq(n.zone.map, BARE)
    t.eq(n.better.map, WOOD)
end

tests["zoneNotice module: a read that never ends is asked about ASKS times a visit, no more"] = function(t)
    local k, c, st = start()
    st.list, st.why = nil, W().WHY_READING
    t.ok(type(Z().ASKS) == "number" and Z().ASKS >= 1, "ASKS says how often")
    if type(Z().ASKS) ~= "number" then return end
    wait(c, Z().SETTLE + 2 * Z().ASKS * Z().CHECK)
    t.eq(st.asks, Z().ASKS)
    wait(c, 60)
    t.eq(st.asks, Z().ASKS)
    t.eq(notice(k), nil)
    st.list = listed()
    enter(c, OTHER)
    settle(c)
    local n = notice(k)
    t.ok(type(n) == "table", "the next zone is asked about again")
    if type(n) ~= "table" then return end
    t.eq(n.zone.map, OTHER)
end

tests["zoneNotice module: whereNext unable to answer gives no notice"] = function(t)
    for _, why in ipairs({ W().WHY_NO_QUESTIE, W().WHY_NO_LEVEL, W().WHY_NO_DATA, W().WHY_NO_CONT, W().WHY_OFF }) do
        local k, c, st = start()
        st.list, st.why = nil, why
        settle(c)
        wait(c, 60)
        t.eq(notice(k), nil, why)
        t.eq(st.n, 0, why)
    end
end

tests["zoneNotice module: the zone not known gives no notice"] = function(t)
    local k, c, st = start({ noZone = true })
    settle(c)
    t.eq(notice(k), nil)
    t.eq(st.asks, 0)
    c.setZone(0, nil)
    c.fire("ZONE_CHANGED_NEW_AREA")
    settle(c)
    t.eq(notice(k), nil, "a continent and no zone")
end

tests["zoneNotice module: on a flight there is none; after it, there is"] = function(t)
    local k, c, st = start()
    c.setOnTaxi(true)
    settle(c)
    t.eq(notice(k), nil)
    t.eq(st.asks, 0)
    c.setOnTaxi(false)
    wait(c, 2 * Z().CHECK)
    t.ok(notice(k) ~= nil, "the notice after landing")
end

tests["zoneNotice module: in an instance there is none"] = function(t)
    local k, c = start()
    c.setInstance({ inside = true, kind = "party" })
    settle(c)
    t.eq(notice(k), nil)
    c.setInstance({ inside = false, kind = "none" })
    wait(c, 2 * Z().CHECK)
    t.ok(notice(k) ~= nil, "the notice outside")
end

tests["zoneNotice module: a fight puts it away, and it comes back after"] = function(t)
    local k, c, st = start()
    settle(c)
    t.ok(notice(k) ~= nil, "up")
    c.setCombat(true)
    wait(c, 2 * Z().CHECK)
    t.eq(notice(k), nil)
    c.setCombat(false)
    wait(c, 2 * Z().CHECK)
    t.ok(notice(k) ~= nil, "up again")
    t.eq(st.n, 3)
    t.eq(st.events[1], BARE)
    t.eq(st.events[2], false)
    t.eq(st.events[3], BARE)
end

tests["zoneNotice module: the event is sent once when it comes up, not at every look"] = function(t)
    local k, c, st = start()
    settle(c)
    wait(c, 60)
    t.ok(notice(k) ~= nil, "up")
    t.eq(st.n, 1)
    t.eq(st.events[1], BARE)
    enter(c, WOOD)
    t.eq(notice(k), nil)
    t.eq(st.n, 2)
    t.eq(st.events[2], false)
end

tests["zoneNotice module: with the setting off there is none"] = function(t)
    local k, c, st = start()
    k.settings:set(Z().SETTING, false)
    settle(c)
    t.eq(notice(k), nil)
    t.eq(st.asks, 0)
    k.settings:set(Z().SETTING, true)
    wait(c, 2 * Z().CHECK)
    t.ok(notice(k) ~= nil, "on again: the notice")
end

tests["zoneNotice module: No thanks is kept for the character and the zone is not asked about again"] = function(t)
    local k, c, st = start()
    settle(c)
    t.ok(notice(k) ~= nil, "up")
    local api = k.use(Z().NAME)
    t.eq(api.NoThanks(), true)
    t.eq(notice(k), nil)
    t.eq(k.store:get("char", Z().NO), { [BARE] = true })
    t.eq(k.store:get("char", Z().YES), nil)
    t.eq(api.Answer(BARE), "no")
    t.eq(st.events[st.n], false)
    local asked = st.asks
    wait(c, 120)
    enter(c, WOOD)
    enter(c, BARE)
    settle(c)
    t.eq(notice(k), nil)
    t.eq(st.asks, asked, "whereNext is not asked for a zone already answered")
    enter(c, OTHER)
    settle(c)
    local n = notice(k)
    t.ok(type(n) == "table", "another zone is still asked about")
    if type(n) ~= "table" then return end
    t.eq(n.zone.map, OTHER)
end

tests["zoneNotice module: Quest here is kept for the character and the zone is not asked about again"] = function(t)
    local k, c = start()
    settle(c)
    t.ok(notice(k) ~= nil, "up")
    local api = k.use(Z().NAME)
    t.eq(api.QuestHere(), true)
    t.eq(notice(k), nil)
    t.eq(k.store:get("char", Z().YES), { [BARE] = true })
    t.eq(k.store:get("char", Z().NO), nil)
    t.eq(api.Answer(BARE), "yes")
    wait(c, 120)
    enter(c, WOOD)
    enter(c, BARE)
    settle(c)
    t.eq(notice(k), nil)
end

tests["zoneNotice module: an answer with no notice up keeps nothing"] = function(t)
    local k, c = start({ zone = WOOD })
    settle(c)
    local api = k.use(Z().NAME)
    t.eq(api.NoThanks(), false)
    t.eq(api.QuestHere(), false)
    t.eq(k.store:get("char", Z().NO), nil)
    t.eq(k.store:get("char", Z().YES), nil)
    t.eq(api.Answer(WOOD), nil)
end

tests["zoneNotice module: an answer saved before is read at the next login"] = function(t)
    local saved = {}
    local k, c = start({ char = saved })
    settle(c)
    t.eq(k.use(Z().NAME).NoThanks(), true)
    local k2, c2, st2 = start({ char = saved })
    settle(c2)
    t.eq(notice(k2), nil)
    t.eq(st2.asks, 0)
    t.eq(k2.use(Z().NAME).Answer(BARE), "no")
end

tests["zoneNotice module: a zone kept as one of yours, or as No thanks, before this login is not asked about"] = function(t)
    local k, c, st = start()
    k.store:set("char", Z().YES, { [BARE] = true })
    k.store:set("char", Z().NO, { [OTHER] = true })
    local api = k.use(Z().NAME)
    settle(c)
    t.eq(notice(k), nil)
    t.eq(api.Answer(BARE), Z().SAID_YES)
    enter(c, OTHER)
    settle(c)
    t.eq(notice(k), nil)
    t.eq(api.Answer(OTHER), Z().SAID_NO)
    t.eq(st.asks, 0)
    t.eq(st.n, 0)
end

tests["zoneNotice module: Forget drops the zone's answer, and it is asked about again"] = function(t)
    local k, c = start()
    settle(c)
    local api = k.use(Z().NAME)
    api.NoThanks()
    t.eq(api.Forget(BARE), true)
    t.eq(api.Answer(BARE), nil)
    t.eq(k.store:get("char", Z().NO), {})
    wait(c, 2 * Z().CHECK)
    t.ok(notice(k) ~= nil, "the notice again")
    t.eq(api.Forget(OTHER), false)
end

-- ------------------------------------------------- with the real whereNext

local AREAS = { [12] = WOOD, [40] = FALL }

-- The real whereNext over a stand-in Questie of three quests: two in WOOD,
-- one in FALL. count.reads: every quest read made of Questie.
local function real(zone)
    local count = { reads = 0 }
    local list = { [1] = { questLevel = 20, zoneOrSort = 12 }, [2] = { questLevel = 20, zoneOrSort = 12 },
                   [3] = { questLevel = 20, zoneOrSort = 40 } }
    local db = { QuestPointers = { [1] = true, [2] = true, [3] = true } }
    function db.QueryQuestSingle(id, field)
        count.reads = count.reads + 1
        return list[id] and list[id][field]
    end
    function db.QueryNPCSingle() return nil end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return AREAS[area] end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setLevel(20)
    c.setClass("WARRIOR")
    c.setRaceId(1)
    c.setZone(0, zone)
    c.setPosition(zone, 0.5, 0.5)
    for map, name in pairs(NAMES) do
        c.setMapName(map, name)
        c.setMapCont(map, 0)
    end
    c.setQuestLog({})
    for id in pairs(list) do c.setQuestDone(id, false) end
    c.setQuestieModule("QuestieDB", db)
    c.setQuestieModule("ZoneDB", zones)
    local k = ns.Kernel({}, c)
    W().Declare(k)
    k:Module({ name = "zoneLeft", provides = { Left = function() return {}, 0 end } })
    Z().Declare(k)
    k:Boot()
    k.settings:set(Z().SETTING, true)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, count
end

tests["zoneNotice with whereNext: nothing of Questie is read before the wait is over"] = function(t)
    local k, c, count = real(BARE)
    wait(c, Z().SETTLE - Z().CHECK)
    t.eq(count.reads, 0)
    t.eq(notice(k), nil)
end

tests["zoneNotice with whereNext: the notice comes from whereNext's one pass, and no second pass is started"] = function(t)
    local k, c, count = real(BARE)
    settle(c)
    wait(c, 2 * Z().CHECK)
    local n = notice(k)
    t.ok(type(n) == "table", "a notice")
    if type(n) ~= "table" then return end
    t.eq(n.zone, { map = BARE, name = "Bare Hill" })
    t.eq(n.reason, Z().WHY_NONE)
    t.eq(n.count, 0)
    t.eq(n.better, { map = WOOD, name = "Near Wood", count = 2 })
    local reads = count.reads
    t.ok(reads >= 3, "each quest was read: " .. reads)
    wait(c, 300)
    enter(c, OTHER)
    settle(c)
    enter(c, WOOD)
    settle(c)
    t.eq(count.reads, reads, "no read of Questie after the one pass")
    t.eq(k.problems:count(), 0)
end

tests["zoneNotice with whereNext: a zone with quests in your level range gives none"] = function(t)
    local k, c, count = real(WOOD)
    settle(c)
    wait(c, 2 * Z().CHECK)
    t.eq(notice(k), nil)
    t.ok(count.reads >= 3, "whereNext did read: " .. count.reads)
    t.eq(k.problems:count(), 0)
end

return tests
