local _, ns = ...

-- Where this player made a home (G46), on the whole add-on loaded on a
-- fake client. The real entry: HEARTHSTONE_BOUND, read with the bind name
-- the client gives and where the player stands. The place is saved per
-- character (char "learned.places.bind"), kept over a reload, and then
-- lets the quest arrow say "Hearth to <place>". With the name or the
-- position not known nothing is written and nothing is said. Made-up
-- quests, places and names. Not tested in game.

local tests = {}
local HS, Travel = ns.HearthSeen, ns.Nav.Travel

local MAP, INN = 1411, "Test Inn"

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Near Wolf", spawns = { [12] = { { 90, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = MAP })[area] end
    return db, zones
end

-- opts.account, opts.char: saved tables. The player stands at the inn,
-- (0.85, 0.5), 50 yards from the wolves.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setZone(1, MAP); c.setPosition(MAP, 0.85, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setClock(700)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function bind(c)
    local char = c.saved(ns.id.charDB)
    local l = type(char) == "table" and char.learned
    local p = type(l) == "table" and l.places
    return type(p) == "table" and p.bind or nil
end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

tests["hearth seen: making a home saves its name and place, and the arrow then offers it"] = function(t)
    local c, addon = boot()
    c.setBindLocation(INN)
    c.fire(HS.EVENT)
    c.advance(1, 4)
    t.eq(bind(c), { name = INN, map = MAP, x = 0.85, y = 0.5, seen = 700 }, "saved where the player stood")
    local last = addon.use(HS.NAME).Last()
    t.eq(last and last.ok, true)
    t.eq(last and last.name, INN)

    -- Walk away from the inn, the stone ready: the arrow offers it.
    c.setHearthCooldown(0)
    c.setPosition(MAP, 0.1, 0.5)
    c.advance(10, 40)
    t.eq(first(c), "Hearth to " .. INN)
    t.eq(c.arrows[1].lines[2], Travel.THEN:format("Wolves"))
end

tests["hearth seen: the place is kept over a reload, and a new home takes its place whole"] = function(t)
    local c = boot()
    c.setBindLocation(INN)
    c.fire(HS.EVENT)
    c.advance(1, 4)
    local c2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(bind(c2) and bind(c2).name, INN, "kept")
    c2.setPosition(MAP, 0.3, 0.2)
    c2.setBindLocation("Other Inn")
    c2.setClock(nil)
    c2.fire(HS.EVENT)
    c2.advance(1, 4)
    t.eq(bind(c2), { name = "Other Inn", map = MAP, x = 0.3, y = 0.2 }, "the old entry is not kept; no clock, no seen")
end

tests["hearth seen: unknown data says nothing wrong"] = function(t)
    local c, addon = boot()
    local before = #(c.printed or {})
    -- No bind name from the client.
    c.setBindLocation(nil)
    c.fire(HS.EVENT)
    c.advance(1, 4)
    t.eq(bind(c), nil, "no name: nothing written")
    local last = addon.use(HS.NAME).Last()
    t.eq(last and last.ok, false)
    t.eq(last and last.reason, "the bind place is not known")
    -- A name but no position.
    c.setBindLocation(INN)
    c.setPosition(nil)
    c.fire(HS.EVENT)
    c.advance(1, 4)
    t.eq(bind(c), nil, "no position: nothing written")
    last = addon.use(HS.NAME).Last()
    t.eq(last and last.reason, "the position is not known")
    t.eq(#(c.printed or {}), before, "nothing said in chat")
end

return tests
