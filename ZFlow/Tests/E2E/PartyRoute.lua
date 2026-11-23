local _, ns = ...

-- End to end (G48, P-TRIP): two fake clients, each running the whole
-- add-on, joined by the fake's add-on message link (a message sent on the
-- party channel reaches the linked client's CHAT_MSG_ADDON listeners). A
-- route planned and shared by one is offered to and taken by the other; a
-- refused send says "not shared" and changes nothing; a late joiner asks
-- and gets it; a malformed message is ignored with one problem line.
-- Made-up quests, places and names. The two-client game test stays an
-- owner item; not tested in game.

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
    local db = {}
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

local function boot(name, log)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(log or LOG)
    c.setGrouped(true)
    c.setAddonName(name)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    addon.settings:set(ns.Nav.PartyRoute.SETTING, true)
    return c, addon
end

local function count(c, text)
    local n = 0
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then n = n + 1 end
    end
    return n
end

local function said(c, text) return count(c, text) > 0 end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

local function slash(c, text)
    c.slashes[ns.id.slash](text)
    c.advance(1, 5)
end

local function pair()
    local a = boot("Anna")
    local b = boot("Bert", {})
    a.linkAddon(b); b.linkAddon(a)
    return a, b
end

tests["party route: a route shared by one client is offered to and taken by the other"] = function(t)
    local a, b = pair()
    slash(a, "route")
    slash(a, "route share")
    t.ok(said(a, "shared with your party"), "the sharer is told")
    t.ok(#a.addonSent >= 1, "sent")
    for _, m in ipairs(a.addonSent) do
        t.eq(m.channel, "PARTY", "party channel only")
        t.eq(m.prefix, ns.id.commPrefix)
        t.ok(#m.text <= 255, "fits")
    end
    t.ok(said(b, "Anna") and said(b, "route take"), "a one-line offer on the other client")
    t.eq(count(b, "route take"), 1, "one offer line")
    t.eq(count(a, "route take"), 0, "the sharer is not offered its own route")
    slash(b, "route take")
    t.eq(first(b), "Boars", "the taken route's first stop is on the other client's arrow")
end

tests["party route: a refused send says not shared and nothing else changes"] = function(t)
    local a, b = pair()
    slash(a, "route")
    a.setAddonRefuse("throttled")
    slash(a, "route share")
    t.ok(said(a, "not shared"), "not shared")
    t.eq(said(a, "shared with your party"), false)
    t.eq(said(b, "route take"), false, "nothing reached the other")
    slash(b, "route take")
    t.ok(said(b, "No party route"), "nothing to take")
    t.ok(first(a) ~= nil, "the sharer's own route still walks")
end

tests["party route: outside a party nothing is sent"] = function(t)
    local a = boot("Anna")
    a.setGrouped(false)
    slash(a, "route")
    slash(a, "route share")
    t.ok(said(a, "not shared"))
    t.eq(#a.addonSent, 0)
end

tests["party route: the share setting off sends nothing"] = function(t)
    local a, addon = boot("Anna")
    addon.settings:set(ns.Nav.PartyRoute.SETTING, false)
    slash(a, "route")
    slash(a, "route share")
    t.ok(said(a, "not shared"))
    t.eq(#a.addonSent, 0)
end

tests["party route: a late joiner asks and the sharer answers once"] = function(t)
    local a = boot("Anna")
    slash(a, "route")
    slash(a, "route share")
    local b = boot("Bert", {})
    a.linkAddon(b); b.linkAddon(a)
    t.eq(said(b, "route take"), false, "joined after the share")
    local before = #a.addonSent
    slash(b, "route ask")
    t.ok(#a.addonSent > before, "the sharer answered")
    t.eq(count(b, "route take"), 1, "offered once")
    local again = #a.addonSent
    slash(b, "route ask")
    t.eq(#a.addonSent, again, "a second ask at once is not answered")
    slash(b, "route take")
    t.eq(first(b), "Boars")
end

tests["party route: a lost chunk says the route is incomplete"] = function(t)
    local b = boot("Bert", {})
    local P = ns.Nav.PartyRoute
    local stops = {}
    for i = 1, P.MAX_STOPS do
        stops[i] = { label = "A long made-up quest name " .. i, detail = "Things done: 0/10",
                     place = { map = MAP, x = i / 100, y = 0.5 } }
    end
    local msgs = P.Chunks("zz", P.Encode({ kind = "quests", label = "x", stops = stops }), ns.id.commVersion)
    t.ok(type(msgs) == "table" and #msgs >= 2, "chunked")
    b.fire("CHAT_MSG_ADDON", ns.id.commPrefix, msgs and msgs[2], "PARTY", "Anna")
    b.advance(1, 5)
    t.ok(said(b, "incomplete"), "route incomplete; ask again")
    t.eq(said(b, "route take"), false)
end

tests["party route: a malformed message is ignored with one problem line"] = function(t)
    local b, addon = boot("Bert", {})
    local NAME = ns.Nav.PartyRoute.NAME
    local before = #addon.problems:list(NAME)
    b.fire("CHAT_MSG_ADDON", ns.id.commPrefix, "nonsense|||", "PARTY", "Anna")
    b.fire("CHAT_MSG_ADDON", ns.id.commPrefix, "nonsense|||", "PARTY", "Anna")
    b.advance(1, 5)
    t.eq(#addon.problems:list(NAME) - before, 1, "one problem line")
    b.fire("CHAT_MSG_ADDON", ns.id.commPrefix, "9|Q|x", "PARTY", "Anna")
    t.eq(#addon.problems:list(NAME) - before, 2, "an unknown version: one more line")
    t.eq(said(b, "route take"), false, "nothing offered")
    b.fire("CHAT_MSG_ADDON", "OtherAddon", "nonsense", "PARTY", "Anna")
    t.eq(#addon.problems:list(NAME) - before, 2, "another add-on's prefix is not looked at")
end

tests["party route: the setting row is off by default"] = function(t)
    local _, addon = boot("Anna")
    local row = addon.settings:row(ns.Nav.PartyRoute.SETTING)
    t.eq(row and row.default, false)
    t.eq(row and row.group, "travel.route")
end

return tests
