local _, ns = ...

-- End to end (G46, lead DISPATCH section 391 item 2): the whole add-on on a
-- fake client. A planned quest route far from the player and a home inn
-- near it: the hearth line, once. The stone on cooldown: when it is ready,
-- once. No home and a seen inn near most stops: talk to an innkeeper, and
-- set your home there, once each. Made-up quests and places; not tested in
-- game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 62, 52 } } } },
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

-- The player stands at the south edge of a 3000-yard map, about 1450 yards
-- (over 3 minutes on foot) from both quests.
local function boot(char, bindName, cooldown)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, char)
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.6, 1.0); c.setFacing(0)
    c.setMapSize(MAP, 3000, 3000); c.setMapCont(MAP, 0)
    c.setBindLocation(bindName); c.setHearthCooldown(cooldown)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(LOG)
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c
end

local function count(c, text)
    local n, line = 0, nil
    for _, l in ipairs(c.printed or {}) do
        if tostring(l):find(text, 1, true) then n, line = n + 1, l end
    end
    return n, line
end

local function home(name, x, y)
    return { learned = { places = { bind = { name = name, map = MAP, x = x, y = y } } } }
end

tests["hearth advice: a far route and a home near it: the hearth line once"] = function(t)
    local c = boot(home("Goldshire", 0.55, 0.5), "Goldshire", 0)
    c.slashes[ns.id.slash]("route")
    c.advance(10, 20)
    local n, line = count(c, "Hearth to Goldshire: it saves about ")
    t.eq(n, 1, "said once, not every look")
    t.ok(line ~= nil and line:find("minutes of walking.", 1, true) ~= nil, tostring(line))
    t.eq((count(c, "Set your home")), 0, "the home is already near the quests")
end

tests["hearth advice: the stone on cooldown, then ready: each said once"] = function(t)
    local c = boot(home("Goldshire", 0.55, 0.5), "Goldshire", 90)
    c.slashes[ns.id.slash]("route")
    c.advance(10, 20)
    t.eq((count(c, "Your hearthstone is ready in 2 minutes")), 1)
    t.eq((count(c, "Hearth to Goldshire")), 0)
    c.setHearthCooldown(0)
    c.advance(10, 20)
    t.eq((count(c, "Hearth to Goldshire: it saves about ")), 1)
end

tests["hearth advice: no home: talk to an innkeeper; a seen inn near the quests: set your home there"] = function(t)
    local c = boot({ learned = { places = { services = {
        ["Creature-0-1-2-3-295-0"] = { name = "Farley", map = MAP, x = 0.61, y = 0.51, kinds = { innkeeper = true } },
    } } } }, nil, 0)
    c.slashes[ns.id.slash]("route")
    c.advance(10, 20)
    t.eq((count(c, "Talk to an innkeeper to set your home")), 1)
    t.eq((count(c, "Set your home at Farley's inn: most of your quests are near it.")), 1)
end

return tests
