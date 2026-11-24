local _, ns = ...

-- End to end (S32): the whole add-on on a fake client. The player waits
-- three minutes on the Menethil Harbor dock, rides to Auberdine and back,
-- and later has a quest over the sea: the quest arrow names the dock, the
-- landing and the wait, all from the player's own trips. Made-up maps and
-- quest. Offline only: not tested in game.

local tests = {}

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Far Crab", spawns = { [40] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = 1439 })[area] end
    return db, zones
end

local function crabs() return { id = 303, title = "Crabs", objectives = { { text = "Crabs slain: 0/4" } } } end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setZone(0, 1437); c.setPosition(1437, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1437, 1000, 500); c.setMapCont(1437, 0)
    c.setMapSize(1439, 1000, 1000); c.setMapCont(1439, 1)
    c.setClass("WARRIOR"); c.setFaction("Alliance")
    c.setOnTaxi(false)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ crabs() })
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c
end

local function shown(c)
    local a = c.arrows[1]
    if not a.shown then return nil end
    return a.lines
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do if l == text then return true end end
    return false
end

-- Three minutes still on the dock, a step onto the boat, the boat moves
-- off, then Auberdine; a few seconds there and back the same way.
local function rideThereAndBack(c)
    c.setPlaceText("Wetlands", "Menethil Harbor"); c.setPosition(1437, 0.1, 0.5)
    c.advance(180, 360)
    c.setPosition(1437, 0.1, 0.52); c.advance(1, 2)
    c.setPosition(1437, 0.1, 0.56); c.advance(1, 2)
    c.setPlaceText("Darkshore", "Auberdine"); c.setZone(1, 1439); c.setPosition(1439, 0.3, 0.4)
    c.advance(2, 4)
    c.setPosition(1439, 0.3, 0.42); c.advance(1, 2)
    c.setPlaceText("Wetlands", "Menethil Harbor"); c.setZone(0, 1437); c.setPosition(1437, 0.1, 0.5)
    c.advance(2, 4)
    c.setPlaceText("Wetlands", nil); c.setPosition(1437, 0.5, 0.5)
    c.advance(2, 4)
end

local HINT = "Take the boat or zeppelin at Menethil Harbor to Auberdine."
    .. " It leaves about every 3 minutes: wait where you board."

tests["boat docks: the arrow names the dock, the landing and the wait from the player's trips"] = function(t)
    local c = start()
    t.ok(not has(shown(c), HINT), "nothing said before any trip")
    rideThereAndBack(c)
    local l = shown(c)
    t.ok(type(l) == "table", "the arrow shows")
    t.eq(l and l[1], "Crossing to Auberdine")
    t.eq(l and l[2], "Then: Crabs")
    t.eq(l and l[3], HINT)
end

tests["boat docks: trips with no place words say no dock and no wait"] = function(t)
    local c = start()
    local function dock() c.setZone(0, 1437); c.setPosition(1437, 0.1, 0.5); c.advance(1, 4) end
    local function over() c.setZone(1, 1439); c.setPosition(1439, 0.3, 0.4); c.advance(1, 4) end
    dock(); over(); dock(); over(); dock()
    c.setPosition(1437, 0.5, 0.5); c.advance(1, 4)
    local l = shown(c)
    t.eq(l and l[1], "Crossing to another continent")
    t.eq(l and l[2], "Then: Crabs")
    for _, line in ipairs(l or {}) do
        t.ok(not line:find("Take the", 1, true), "no take line: " .. line)
    end
end

-- FLOW-PARITY B-03: quick trips leave no wait known. Back at the dock the
-- hint says to wait there and that when it leaves is not known: no minutes
-- are made up. Away from the dock it says nothing about waiting.
tests["boat docks: at the dock with no wait known, wait here; the time stays unknown"] = function(t)
    local c = start()
    local function dock()
        c.setPlaceText("Wetlands", "Menethil Harbor"); c.setZone(0, 1437); c.setPosition(1437, 0.1, 0.5); c.advance(1, 4)
    end
    local function over()
        c.setPlaceText("Darkshore", "Auberdine"); c.setZone(1, 1439); c.setPosition(1439, 0.3, 0.4); c.advance(1, 4)
    end
    dock(); over(); dock(); over(); dock()
    c.setPlaceText("Wetlands", nil); c.setPosition(1437, 0.5, 0.5); c.advance(2, 4)
    local away = shown(c)
    t.eq(away and away[1], "Crossing to Auberdine")
    t.eq(away and away[3], "Take the boat or zeppelin at Menethil Harbor to Auberdine.", "away: no wait words")

    c.setPlaceText("Wetlands", "Menethil Harbor"); c.setPosition(1437, 0.1, 0.5); c.advance(2, 4)
    local at = shown(c)
    t.eq(at and at[3], "Take the boat or zeppelin at Menethil Harbor to Auberdine. " .. ns.Nav.CROSSING_WAIT_UNKNOWN)
    t.eq(ns.Nav.CROSSING_WAIT_UNKNOWN, "Wait here for it: when it leaves is not known yet.")
    for _, line in ipairs(at or {}) do
        t.ok(not line:find("minute", 1, true), "no made-up minutes: " .. line)
    end
end

tests["boat docks: the wait words are pure and never guess a time"] = function(t)
    local N = ns.Nav
    t.eq(N.CrossingHint(nil, "Menethil Harbor", "Auberdine", nil, true),
        "Take the boat or zeppelin at Menethil Harbor to Auberdine. " .. N.CROSSING_WAIT_UNKNOWN)
    t.eq(N.CrossingHint(nil, nil, nil, nil, true), N.CROSSING_WAIT_UNKNOWN, "no names: the wait words alone")
    t.eq(N.CrossingHint(nil, nil, nil, nil, false), nil)
    t.eq(N.CrossingHint("boat", "Menethil Harbor", "Auberdine", 180, true),
        "Take the boat at Menethil Harbor's dock to Auberdine. The boat leaves about every 3 minutes: wait on the dock.",
        "a wait learned wins over the unknown words")
end

return tests
