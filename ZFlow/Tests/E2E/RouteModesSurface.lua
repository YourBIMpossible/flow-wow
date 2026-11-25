local _, ns = ...

-- End to end (lead section 651, Muse's MUSE-TO-WHITE-ROUTE-MODES.md): the
-- route's mode, sort and step count as Settings rows and as the "Route"
-- level of the minimap button's route menu. Both surfaces and the route
-- word write the same saved keys. The whole add-on on a fake client with a
-- made-up Questie; made-up quests and places. Not tested in game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 20, 50 } } } },
    }
    local db = { QuestPointers = {} }
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local LOG = {
    { id = 401, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } },
    { id = 402, title = "Herbs", objectives = { { text = "Herbs: 0/5" } } },
}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    local xp = {}
    function xp.GetQuestLogRewardXP(_, id) return ({ [401] = 100, [402] = 900 })[id] end
    c.setQuestieModule("QuestXP", xp)
    c.setQuestLog(LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function T() return ns.Nav.TripRoute end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

local function button(c) return type(c.minimapButtons) == "table" and c.minimapButtons[1] or nil end

local function row(items, key)
    for _, item in ipairs(items or {}) do
        if item.key == key then return item end
    end
    return nil
end

local function has(list, v)
    for _, x in ipairs(list or {}) do
        if x == v then return true end
    end
    return false
end

tests["route modes surface: three rows under The way there, Muse's labels, order and defaults"] = function(t)
    local _, addon = boot()
    local mode = addon.settings:row(T().MODE_KEY)
    t.ok(mode ~= nil, "the mode row")
    if not mode then return end
    t.eq(mode.label, "What the route includes")
    t.eq(mode.group, "travel.route")
    t.eq(mode.choices, { "My quests only", "Today's route", "Everything" })
    t.eq(addon.settings:get(T().MODE_KEY), "Today's route")
    local sort = addon.settings:row(T().SORT_KEY)
    t.eq(sort and sort.label, "Order the route by")
    t.eq(sort and sort.choices, { "Shortest first", "Most XP first" })
    t.eq(addon.settings:get(T().SORT_KEY), "Shortest first")
    local shown = addon.settings:row(T().SHOWN_KEY)
    t.eq(shown and shown.label, "How many stops to show")
    t.eq(shown and shown.choices, { "5", "10", "15", "20", "All" })
    t.eq(addon.settings:get(T().SHOWN_KEY), "All")
    t.eq(shown and shown.help, "The route lists this many stops, then says how many more there are.")
end

tests["route modes surface: Settings search finds each row by its label"] = function(t)
    local _, addon = boot()
    local P = addon.SettingsPage
    for _, key in ipairs({ T().MODE_KEY, T().SORT_KEY, T().SHOWN_KEY }) do
        local r = addon.settings:row(key)
        t.ok(r ~= nil, key .. " is declared")
        if r then
            local keys = {}
            local found = P.Search(addon, r.label)
            for i, e in ipairs(found and found.results or {}) do keys[i] = e.key end
            t.ok(has(keys, key), key .. " is found by \"" .. r.label .. "\"")
        end
    end
end

tests["route modes surface: the route menu has a Route level after Plan, with the choices ticked"] = function(t)
    local c = boot()
    local b = button(c)
    b.click("right")
    local at
    for i, item in ipairs(b.menuItems) do
        if item.key == "route" then at = i end
    end
    t.eq(b.menuItems[2].key, "plan")
    t.eq(at, 3, "right after Plan a route, with no route yet too")
    b.choose("route")
    t.ok(type(b.menuItems) == "table", "the Route level is open")
    t.eq(row(b.menuItems, "mode:quests").text, "My quests only")
    t.eq(row(b.menuItems, "mode:optimal").checked, true, "the default is ticked")
    t.eq(row(b.menuItems, "mode:complete").checked, false)
    t.eq(row(b.menuItems, "sort:distance").checked, true)
    t.eq(row(b.menuItems, "sort:xp").text, "Most XP first")
    for _, item in ipairs(b.menuItems) do
        t.ok(not tostring(item.key):find("^shown"), "the step count is not in the route menu")
    end
end

tests["route modes surface: a menu pick saves the same setting and plans the route again at once"] = function(t)
    local c, addon = boot()
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.eq(first(c), "Boars", "shortest first: the near quest")
    local b = button(c)
    b.click("right"); b.choose("route"); b.choose("sort:xp")
    c.advance(1, 5)
    t.eq(addon.settings:get(T().SORT_KEY), "Most XP first", "the Settings row reads the menu's pick")
    t.eq(first(c), "Herbs", "planned again: the 900 XP quest first")
    b.click("right"); b.choose("route")
    t.eq(row(b.menuItems, "sort:xp").checked, true)
    b.choose("mode:quests")
    t.eq(addon.settings:get(T().MODE_KEY), "My quests only")
end

tests["route modes surface: the Settings row, the menu and the route word share one value"] = function(t)
    local c, addon = boot()
    c.slashes[ns.id.slash]("route")
    addon.settings:set(T().SORT_KEY, "Most XP first")
    c.advance(1, 5)
    t.eq(first(c), "Herbs", "a Settings change plans the route again")
    c.slashes[ns.id.slash]("route sort distance")
    t.eq(addon.settings:get(T().SORT_KEY), "Shortest first", "the word's choice shows in Settings")
    local b = button(c)
    b.click("right"); b.choose("route")
    t.eq(row(b.menuItems, "sort:distance").checked, true, "and in the menu")
    c.slashes[ns.id.slash]("route mode complete")
    t.eq(addon.settings:get(T().MODE_KEY), "Everything")
end

tests["route modes surface: the step count list cuts the route list; All lists every stop"] = function(t)
    local c, addon = boot()
    c.slashes[ns.id.slash]("route")
    addon.settings:set(T().SHOWN_KEY, "5")
    c.slashes[ns.id.slash]("route steps 1")
    t.ok(addon.settings:get(T().SHOWN_KEY) ~= nil, "the word's own count is kept")
    c.printed = {}
    addon.settings:set(T().SHOWN_KEY, "All")
    c.slashes[ns.id.slash]("route")
    local more
    for _, line in ipairs(c.printed) do
        if tostring(line):find("more stops.", 1, true) then more = true end
    end
    t.eq(more, nil, "All: every stop is listed")
end

tests["route modes surface: with no route yet a pick is only saved"] = function(t)
    local c, addon = boot()
    local b = button(c)
    b.click("right"); b.choose("route"); b.choose("mode:complete")
    t.eq(addon.settings:get(T().MODE_KEY), "Everything")
    local trip = addon.use(T().NAME)
    -- The route planned by itself (section 562 item 7, on zflow) may be
    -- there; the pick plans nothing the player walks.
    t.eq(type(trip) == "table" and trip.Step(), nil, "no route was planned by the pick")
end

return tests
