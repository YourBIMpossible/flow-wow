local _, ns = ...

-- End to end (FLOW-PARITY B-31, lead section 470): the quest route counts
-- a step in Moonglade as one cast when the druid knows Teleport: Moonglade.
-- The step joins the route (it was "not on this map") before the first leg
-- longer than the cast, and the arrow says to cast. The player casts;
-- nothing casts for them. Made-up quests and places; not tested in game.

local tests = {}
local T = ns.Nav.TripRoute

local HERE, MOONGLADE = 1411, 1450
local SPELL, SPELL_ID = "Teleport: Moonglade", 18960
local CAST = "Cast " .. SPELL

local function questie()
    local quests = {
        [501] = { ObjectiveData = { { Type = "monster", Id = 9201 } } },
        [502] = { ObjectiveData = { { Type = "monster", Id = 9202 } } },
    }
    local npcs = {
        [9201] = { name = "Far Thing", spawns = { [14] = { { 90, 50 } } } },
        [9202] = { name = "Lake Thing", spawns = { [493] = { { 50, 50 } } } },
    }
    local db = {}
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [14] = HERE, [493] = MOONGLADE })[area] end
    return db, zones
end

local LOG = {
    { id = 501, title = "Far Things", objectives = { { text = "Far things: 0/1" } } },
    { id = 502, title = "Lake Things", objectives = { { text = "Lake things: 0/1" } } },
}

local function boot(known)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } }); c.setSaved(ns.id.charDB, {})
    c.setZone(1, HERE); c.setPosition(HERE, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(HERE, 1000, 1000); c.setMapCont(HERE, 1)
    c.setMapSize(MOONGLADE, 1000, 1000); c.setMapCont(MOONGLADE, 1)
    c.setMapName(MOONGLADE, "Moonglade")
    c.setClass("DRUID"); c.setFaction("Horde"); c.setLevel(20)
    c.setSpellId(SPELL, SPELL_ID); c.setSpell(SPELL_ID, { known = known })
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function first(c)
    local a = c.arrows[1]
    if a and a.shown and a.lines then return a.lines[1] end
    return nil
end

tests["trip route cast: a known spell puts the Moonglade step on the route first, and the arrow says to cast"] = function(t)
    local c = boot(true)
    c.slashes[ns.id.slash]("route"); c.advance(2, 20)
    t.eq(first(c), CAST, "one cast beats a 400 yd walk")
end

tests["trip route cast: the spell not known, the Moonglade step stays off the route"] = function(t)
    local c = boot(false)
    c.slashes[ns.id.slash]("route"); c.advance(2, 20)
    t.eq(first(c), "Far Things")
end

tests["trip route cast: pure plan, a nearer stop stays before the cast"] = function(t)
    local rows = {
        { id = 1, title = "Near", objectives = { { text = "a: 0/1" } } },
        { id = 2, title = "Far", objectives = { { text = "b: 0/1" } } },
        { id = 3, title = "Lake", objectives = { { text = "c: 0/1" } } },
    }
    local function at(map, x) return { objectives = { { points = { { map = map, x = x, y = 0.5 } } } } } end
    local places = { [1] = at(HERE, 0.55), [2] = at(HERE, 0.9),
                     [3] = { objectives = { { points = {}, away = { map = MOONGLADE, x = 0.5, y = 0.5 } } } } }
    local here = { map = HERE, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }
    local function labels(r)
        local out = {}
        for i, s in ipairs(r and r.stops or {}) do out[i] = s.label end
        return out
    end
    local r = T.Plan(rows, places, here)
    t.eq(labels(r), { "Near", "Far" }, "no cast known: the Moonglade step is a line")
    t.eq(r.left[1] and r.left[1].why, T.NOT_HERE)
    here.casts = { [MOONGLADE] = true }
    r = T.Plan(rows, places, here)
    t.eq(labels(r), { "Near", "Lake", "Far" }, "50 yd first, then the cast, then the 350 yd leg")
    t.eq(r.stops[2].cast, true)
end

-- Lead section 474: a Moonglade point behind a lower map (Teldrassil
-- 1438 here) is still found.
tests["trip route cast: a Moonglade spawn is found behind a lower other map"] = function(t)
    local c = boot(true)
    local db, zones = questie()
    local npc = db.GetNPC(9202)
    npc.spawns[141] = { { 20, 20 } }
    local area = zones.GetUiMapIdByAreaId
    function zones.GetUiMapIdByAreaId(a) if a == 141 then return 1438 end return area(a) end
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.slashes[ns.id.slash]("route"); c.advance(2, 20)
    t.eq(first(c), CAST, "Moonglade (1450) is kept beside Teldrassil (1438)")
end

return tests
