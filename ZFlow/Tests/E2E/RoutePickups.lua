local _, ns = ...

-- End to end (lead section 375 item 7, TN-1): the quest route adds quests
-- the player can pick up whose giver stands on this map, kept only when on
-- the way. The whole add-on on a fake client with a made-up Questie. Made-up
-- quests and places; not tested in game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
        [403] = { ObjectiveData = {}, Finisher = { NPC = { 9103 } } },
        [601] = { Id = 601, name = "Lost Pages", level = 17, requiredLevel = 12, Starts = { NPC = { 9201 } } },
        [602] = { Id = 602, name = "Hermit Tea", level = 18, requiredLevel = 12, Starts = { NPC = { 9202 } } },
        [603] = { Id = 603, name = "Wrong Race", level = 18, requiredLevel = 12, requiredRaces = 2,
                  Starts = { NPC = { 9201 } } },
        [605] = { Id = 605, name = "Second Part", level = 18, requiredLevel = 12, preQuestSingle = { 699 },
                  Starts = { NPC = { 9201 } } },
        [607] = { Id = 607, name = "Old Oath", level = 10, requiredLevel = 10, requiredClasses = 1,
                  Starts = { NPC = { 9201 } } },
        [608] = { Id = 608, name = "Holy Oath", level = 10, requiredLevel = 10, requiredClasses = 2,
                  Starts = { NPC = { 9201 } } },
        [609] = { Id = 609, name = "Later Oath", level = 10, requiredLevel = 10, requiredClasses = 1,
                  preQuestSingle = { 699 }, Starts = { NPC = { 9201 } } },
        [610] = { Id = 610, name = "Gulch Duty", level = 18, requiredLevel = 12, zoneOrSort = 3277,
                  Starts = { NPC = { 9203 } } },
        [606] = { Id = 606, name = "Too High", level = 26, requiredLevel = 25, Starts = { NPC = { 9201 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 20, 50 } } } },
        [9103] = { name = "Smith", spawns = { [40] = { { 55, 50 } } } },
        [9201] = { name = "Marshal", friendlyToFaction = "AH", spawns = { [40] = { { 40, 52 } } } },
        [9203] = { name = "Herald", friendlyToFaction = "AH", spawns = { [40] = { { 45, 50 } } } },
        [9202] = { name = "Hermit", friendlyToFaction = "AH", spawns = { [40] = { { 50, 95 } } } },
    }
    local db = { QuestPointers = {} }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local LOG = {
    { id = 401, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } },
    { id = 402, title = "Herbs", objectives = { { text = "Herbs: 0/5" } } },
    { id = 403, title = "Bandages", complete = true, objectives = { { text = "Linen: 4/4", done = true } } },
}

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setQuestDone(699, false)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    if opts.questie ~= false then
        local db, zones = questie()
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    c.setQuestLog(opts.log or LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return line end
    end
    return nil
end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

tests["route pickups: a giver on the way is a stop, one far off is listed as skipped"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.ok(said(c, "1. Bandages") ~= nil, "the quest stops come first as before")
    local kept = said(c, ". Pick up: Lost Pages (Marshal)")
    -- Section 645.5: hub-first (the default) brings the close pick-up (102 yd) up behind the turn-in.
    t.ok(kept ~= nil and kept:find("2. ", 1, true) ~= nil, tostring(kept))
    local skipped = said(c, "Pick up: Hermit Tea (Hermit)")
    t.ok(skipped ~= nil and skipped:find(ns.Nav.RoutePickups.SKIPPED, 1, true) ~= nil, tostring(skipped))
    t.ok(said(c, "Wrong Race") == nil, "another race's quest is not offered")
    t.ok(said(c, "Second Part") == nil, "a quest whose earlier part is not done is not offered")
    t.ok(said(c, "Too High") == nil, "a quest above the player is not offered")
end

tests["route pickups: a pick-up stop drops out once the quest is in the log"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("route")
    -- Section 645.5: hub-first makes the pick-up the second stop, so one skip reaches it.
    c.slashes[ns.id.slash]("route skip")
    c.advance(1, 5)
    t.eq(first(c), "Pick up: Lost Pages (Marshal)")
    c.setQuestLog({ LOG[1], LOG[2], LOG[3],
                    { id = 601, title = "Lost Pages", objectives = { { text = "Pages: 0/3" } } } })
    c.advance(5, 60)
    t.ok(first(c) ~= "Pick up: Lost Pages (Marshal)", tostring(first(c)))
end

tests["route pickups: switched off, no pick-ups"] = function(t)
    local c, addon = boot()
    addon.settings:set(ns.Nav.TripRoute.PICKUP_SETTING, false)
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.ok(said(c, "1. Bandages") ~= nil, "the route itself")
    t.ok(said(c, "Pick up:") == nil, "no pick-up")
end

tests["route pickups: without Questie, one line says why"] = function(t)
    local log = { { id = 501, title = "Rats", objectives = { { text = "Rats slain: 0/5" } } } }
    local c = boot({ questie = false, log = log })
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.ok(said(c, ns.Nav.RoutePickups.WHY_NO_QUESTIE) ~= nil, "the why line")
end

tests["route pickups: the setting row is there"] = function(t)
    local _, addon = boot()
    local row = addon.settings:row(ns.Nav.TripRoute.PICKUP_SETTING)
    t.eq(row and row.group, "travel.route")
    t.eq(row and row.default, true)
end

tests["route pickups: the player's class quest below the window is offered, others' are not"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.ok(said(c, "Pick up your class quest: Old Oath (Marshal)") ~= nil, "the class quest")
    t.ok(said(c, "Holy Oath") == nil, "another class's quest is not offered")
    t.ok(said(c, "Later Oath") == nil, "a class quest waiting on an earlier quest is not offered")
end

tests["route pickups: battleground quests stay off until the setting is on"] = function(t)
    local c, addon = boot()
    local row = addon.settings:row(ns.Nav.BattlegroundQuests.SETTING)
    t.eq(row and row.group, "travel.route")
    t.eq(row and row.default, false)
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.ok(said(c, "Pick up: Lost Pages (Marshal)") ~= nil, "the ordinary pick-up")
    t.ok(said(c, "Gulch Duty") == nil, "the battleground quest is left out")
    addon.settings:set(ns.Nav.BattlegroundQuests.SETTING, true)
    c.slashes[ns.id.slash]("route new")
    c.advance(1, 5)
    t.ok(said(c, "Pick up: Gulch Duty (Herald)") ~= nil, "on: the battleground quest is offered")
end

-- Row A2-03 (lead section 667): after /route, the pick-ups the route left
-- off are offered as candidate next steps for the arrow, nearest first.
tests["route pickups: pick-ups off the planned route become next steps"] = function(t)
    local c, addon = boot()
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local view = addon.use(ns.Nav.TripRoute.NAME).View()
    t.ok(view ~= nil, "a route is planned")
    local here = { map = MAP, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }
    local log = {}
    for _, row in ipairs(LOG) do log[row.id] = true end
    local RP = ns.Nav.RoutePickups
    local steps = RP.NextSteps(view, RP.Read(c, here, log), here)
    local labels = {}
    for _, s in ipairs(steps) do labels[s.label] = true end
    t.ok(labels["Pick up: Hermit Tea (Hermit)"] == true, "the skipped giver is a next step")
    t.ok(labels["Pick up: Lost Pages (Marshal)"] == nil, "a pick-up on the route is not repeated")
    t.eq(steps[1] and steps[1].kind, "next")
end

return tests
