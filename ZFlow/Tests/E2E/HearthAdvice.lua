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
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
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

-- FLOW-PARITY B-35: the player in another zone of the same continent; the
-- walk and the home are measured in world yards from the maps' corners.
local OTHER = 1437

local function apart(c)
    c.setMapCorners(MAP, { cont = 0, ox = 0, oy = 0, ex = 3000, ey = 0, sx = 0, sy = 3000 })
    c.setMapCorners(OTHER, { cont = 0, ox = 6000, oy = 0, ex = 9000, ey = 0, sx = 6000, sy = 3000 })
    c.setMapSize(OTHER, 3000, 3000); c.setMapCont(OTHER, 0)
end

tests["hearth advice: the player in another zone, home near the route: the hearth line once"] = function(t)
    local c = boot(home("Goldshire", 0.55, 0.5), "Goldshire", 0)
    apart(c)
    c.slashes[ns.id.slash]("route")
    c.setZone(1, OTHER); c.setPosition(OTHER, 0.5, 0.5)
    c.advance(10, 20)
    local n, line = count(c, "Hearth to Goldshire: it saves about ")
    t.eq(n, 1, "said once across zones: " .. tostring(line))
end

tests["hearth advice: another zone with no corners known, or another continent: nothing claimed"] = function(t)
    local c = boot(home("Goldshire", 0.55, 0.5), "Goldshire", 0)
    c.slashes[ns.id.slash]("route")
    c.setZone(1, OTHER); c.setPosition(OTHER, 0.5, 0.5)
    c.advance(10, 20)
    t.eq((count(c, "Hearth to Goldshire")), 0, "no corners: not measured")
    local H = ns.Nav.HearthAdvice
    local corners = function(map)
        if map == MAP then return { cont = 0, ox = 0, oy = 0, ex = 3000, ey = 0, sx = 0, sy = 3000 } end
        return { cont = 1, ox = 0, oy = 0, ex = 3000, ey = 0, sx = 0, sy = 3000 }
    end
    local _, why = H.Hearth({ bind = { name = "Goldshire", map = MAP, x = 0.55, y = 0.5 }, cooldown = 0,
        here = { map = OTHER, x = 0.5, y = 0.5 }, target = { map = MAP, x = 0.6, y = 0.5 }, corners = corners })
    t.eq(why, "far unknown", "another continent")
end

-- FLOW-PARITY B-34 (section 456): a "Set hearthstone" step only from what
-- the client shows: an innkeeper the player spoke to and the map's name.
local function farley()
    return { learned = { places = { services = {
        ["Creature-0-1-2-3-295-0"] = { name = "Farley", map = MAP, x = 0.61, y = 0.51, kinds = { innkeeper = true } },
    } } } }
end

local function step(addon)
    local m = addon.use("hearthAdvice")
    return m and m.Step and m.Step() or nil
end

tests["hearth advice: a spoken-to inn near the quests: a Set hearthstone step there"] = function(t)
    local c, addon = boot(farley(), nil, 0)
    c.setMapName(MAP, "Elwynn Forest")
    c.slashes[ns.id.slash]("route")
    c.advance(10, 20)
    local s = step(addon)
    t.ok(s ~= nil, "a step is offered")
    t.eq(s and s.label, "Set hearthstone: Farley (Elwynn Forest)")
    t.eq(s and s.place, { map = MAP, x = 0.61, y = 0.51 })
end

tests["hearth advice: the Set hearthstone step is on the arrow before the route"] = function(t)
    local c = boot(farley(), nil, 0)
    c.setMapName(MAP, "Elwynn Forest")
    c.slashes[ns.id.slash]("route")
    c.advance(10, 20)
    local a = c.arrows[1]
    t.eq(a and a.lines and a.lines[1], "Set hearthstone: Farley (Elwynn Forest)", "the arrow names the inn")
end

tests["hearth advice: no inn spoken to, or the home already there: no Set hearthstone step"] = function(t)
    local c, addon = boot({}, nil, 0)
    c.slashes[ns.id.slash]("route"); c.advance(10, 20)
    t.eq(step(addon), nil, "no inn seen: nothing from a table")
    local char = farley()
    char.learned.places.bind = { name = "Farley", map = MAP, x = 0.61, y = 0.51 }
    c, addon = boot(char, "Farley", 0)
    c.slashes[ns.id.slash]("route"); c.advance(10, 20)
    t.eq(step(addon), nil, "the home is already that inn")
end

tests["hearth advice: the step label without a town or inn name"] = function(t)
    local H = ns.Nav.HearthAdvice
    t.eq(H.SetStep({ name = "Farley", map = MAP, x = 0.5, y = 0.5 }, nil).label, "Set hearthstone: Farley")
    t.eq(H.SetStep({ map = MAP, x = 0.5, y = 0.5 }, "Goldshire").label, "Set hearthstone: innkeeper (Goldshire)")
    t.eq(H.SetStep({ name = "Farley" }, "Goldshire"), nil, "no place: no step")
end

return tests
