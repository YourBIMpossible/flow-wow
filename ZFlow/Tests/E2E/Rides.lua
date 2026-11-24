local _, ns = ...

-- Rides (S33, Nav/Rides.lua) on the quest arrow, on the whole add-on loaded
-- on a fake client. The real entry: the arrow's quest step goes through
-- Travel's Via, which asks N.RideStep with the client's class, faction and
-- position and the saved npc places. A Horde druid in Moonglade whose quest
-- is on another map is told "Talk to Bunthen Plainswind" and how the ride
-- goes. Nothing talks to anyone. Made-up quests, places and names. Not
-- tested in game.
--
-- Moonglade (1450) is 1000 x 1000 yards; the player at (0.5, 0.5). The
-- wolves are on map 1420, the same continent.

local tests = {}
local N = ns.Nav

local MOONGLADE, WOLVES = 1450, 1420
local RIDE = N.RIDES[1]

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Far Wolf", spawns = { [40] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = WOLVES })[area] end
    return db, zones
end

-- opts.class / opts.faction (false: not known); opts.account: the account table.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account or {}
    account.layout = { arrowIntroSeen = true }
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, MOONGLADE); c.setPosition(MOONGLADE, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MOONGLADE, 1000, 1000); c.setMapCont(MOONGLADE, 1)
    c.setMapSize(WOLVES, 1000, 1000); c.setMapCont(WOLVES, 1)
    if opts.class ~= false then c.setClass(opts.class or "DRUID") end
    if opts.faction ~= false then c.setFaction(opts.faction or "Horde") end
    c.setLevel(20)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function lines(c)
    local a = c.arrows[1]
    return a and a.lines or {}
end

local function hasPrefix(list, prefix)
    for _, l in ipairs(list) do
        if type(l) == "string" and l:sub(1, #prefix) == prefix then return true end
    end
    return false
end

tests["rides: a Horde druid in Moonglade is told to talk to the flight master"] = function(t)
    local c = boot()
    t.eq(c.arrows[1] and c.arrows[1].shown, true, "the quest arrow is shown")
    t.eq(lines(c)[1], "Talk to " .. RIDE.name)
    t.eq(lines(c)[2], RIDE.how)
end

tests["rides: the master's saved place is pointed at, with its distance"] = function(t)
    local account = { learned = { places = { npcs = { [RIDE.name] = { map = MOONGLADE, x = 0.45, y = 0.5 } } } } }
    local c = boot({ account = account })
    t.eq(lines(c)[1], "Talk to " .. RIDE.name)
    t.ok(hasPrefix(lines(c), "50 yd"), "50 yards to the master")
end

tests["rides: walk skips the ride and says so"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("walk")
    c.advance(10, 40)
    t.ok(not hasPrefix(lines(c), "Talk to"), "no ride line")
    c.slashes[ns.id.slash]("walk")
    c.advance(10, 40)
    t.eq(lines(c)[1], "Talk to " .. RIDE.name, "the ride is back")
end

tests["rides: another class or faction gets no druid ride"] = function(t)
    local c = boot({ class = "WARRIOR" })
    t.ok(not hasPrefix(lines(c), "Talk to"), "a warrior")
    c = boot({ faction = "Alliance" })
    t.eq(lines(c)[1], "Talk to " .. N.RIDES[2].name, "the Alliance druid's own master")
end

tests["rides: unknown data says nothing wrong"] = function(t)
    -- The faction not known: no ride is guessed.
    local c = boot({ faction = false })
    t.ok(not hasPrefix(lines(c), "Talk to"), "faction unknown")
    -- The class not known.
    c = boot({ class = false })
    t.ok(not hasPrefix(lines(c), "Talk to"), "class unknown")
    -- The master's saved place on another map: words only, no distance made up.
    local account = { learned = { places = { npcs = { [RIDE.name] = { map = WOLVES, x = 0.45, y = 0.5 } } } } }
    c = boot({ account = account })
    t.eq(lines(c)[1], "Talk to " .. RIDE.name)
    t.ok(not hasPrefix(lines(c), "50 yd"), "no distance")
end

return tests
