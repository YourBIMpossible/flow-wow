local _, ns = ...

-- End to end (P-TRIP slice 1): the trip list on the whole add-on with a
-- fake client. Stops from places the player has seen (services, trainers),
-- a quest in the log (its hand-in, placed by a made-up Questie), a dungeon's
-- entrance and where the player stands; the trip handed to the route, which
-- the quest arrow walks. Made-up places; not tested in game.

local tests = {}

local MAP = 1436
local DM = 1581

local function questie()
    local quests = {
        [403] = { ObjectiveData = {}, Finisher = { NPC = { 9103 } } },
    }
    local npcs = { [9103] = { name = "Smith", spawns = { [40] = { { 50, 20 } } } } }
    local db = { QuestPointers = { [403] = true } }
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    function zones:GetDungeons()
        return { [DM] = { "The Deadmines", {}, nil, { { 40, 50, 90 } } } }
    end
    return db, zones
end

local LOG = {
    { id = 403, title = "Bandages", complete = true, objectives = { { text = "Linen: 4/4", done = true } } },
}

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    if opts.questie ~= false then
        local db, zones = questie()
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    c.setQuestLog(opts.log or {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    if opts.seen ~= false then
        addon.store:set("char", ns.Nav.SERVICES, {
            ["svc:1"] = { name = "Bob", map = MAP, x = 0.8, y = 0.5, kinds = { vendor = true, repair = true } },
            ["svc:2"] = { name = "Inna", map = MAP, x = 0.5, y = 0.6, kinds = { innkeeper = true } },
        })
        addon.store:set("account", ns.Errand.NPCS, {
            Thane = { map = MAP, x = 0.3, y = 0.5, roles = { trainer = true } },
        })
    end
    return c, addon
end

local function slash(c, text)
    c.slashes[ns.id.slash](text)
    c.advance(1, 5)
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

local function saved(addon)
    local v = addon.store:get("char", ns.Nav.Trip.PATH)
    return type(v) == "table" and v.stops or {}
end

tests["trip list e2e: stops from seen places are listed with distances and saved per character"] = function(t)
    local c, addon = boot()
    slash(c, "trip add vendor")
    slash(c, "trip add trainer")
    slash(c, "trip add inn")
    t.eq(#saved(addon), 3)
    slash(c, "trip")
    local one = said(c, "1. Vendor: Bob")
    t.ok(one ~= nil and one:find("300 yd", 1, true) ~= nil, tostring(one))
    local two = said(c, "2. Trainer: Thane")
    t.ok(two ~= nil and two:find("200 yd", 1, true) ~= nil, tostring(two))
    t.ok(said(c, "3. Inn: Inna") ~= nil, "the inn third")
    t.eq(saved(addon)[1].place, { map = MAP, x = 0.8, y = 0.5 })
end

tests["trip list e2e: a place not known says why and is not added"] = function(t)
    local c, addon = boot({ seen = false })
    slash(c, "trip add bank")
    t.eq(#saved(addon), 0)
    t.ok(said(c, "not added") ~= nil, "one line saying why")
    slash(c, "trip add giver Nothing Such")
    t.eq(#saved(addon), 0)
    slash(c, "trip add dungeon Nowhere Keep")
    t.eq(#saved(addon), 0)
end

tests["trip list e2e: here, a quest's giver and a dungeon entrance"] = function(t)
    local c, addon = boot({ log = LOG })
    c.setPosition(MAP, 0.2, 0.2)
    c.advance(1, 5)
    slash(c, "trip add here my camp")
    c.setPosition(MAP, 0.5, 0.5)
    c.advance(1, 5)
    slash(c, "trip add giver bandages")
    slash(c, "trip add dungeon dead")
    local list = saved(addon)
    t.eq(#list, 3)
    t.eq(list[1] and list[1].place, { map = MAP, x = 0.2, y = 0.2 })
    t.ok(list[1] and tostring(list[1].label):find("my camp", 1, true) ~= nil, list[1] and list[1].label)
    t.eq(list[2] and list[2].place, { map = MAP, x = 0.5, y = 0.2 })
    t.ok(list[2] and tostring(list[2].label):find("Bandages", 1, true) ~= nil, list[2] and list[2].label)
    t.eq(list[3] and list[3].place, { map = MAP, x = 0.5, y = 0.9 })
    t.ok(list[3] and tostring(list[3].label):find("Deadmines", 1, true) ~= nil, list[3] and list[3].label)
end

tests["trip list e2e: go hands the planned order to the route and the arrow walks it"] = function(t)
    local c = boot()
    slash(c, "trip add vendor")
    slash(c, "trip add trainer")
    slash(c, "trip add inn")
    slash(c, "trip go")
    -- From 0.5, 0.5: the inn (100 yd), then the trainer, then the vendor.
    t.eq(first(c), "Inn: Inna", "the arrow points at the nearest stop first")
    c.setPosition(MAP, 0.5, 0.6)
    c.advance(2, 20)
    t.eq(first(c), "Trainer: Thane", "at the inn: on to the trainer")
    c.setPosition(MAP, 0.3, 0.5)
    c.advance(2, 20)
    t.eq(first(c), "Vendor: Bob")
end

tests["trip list e2e: remove and clear"] = function(t)
    local c, addon = boot()
    slash(c, "trip add vendor")
    slash(c, "trip add trainer")
    slash(c, "trip remove 1")
    t.eq(#saved(addon), 1)
    t.eq(saved(addon)[1].label, "Trainer: Thane")
    slash(c, "trip remove 9")
    t.eq(#saved(addon), 1)
    slash(c, "trip clear")
    t.eq(#saved(addon), 0)
end

tests["trip list e2e: the trip is still there after a reload"] = function(t)
    local char = {}
    local c = boot({ char = char })
    slash(c, "trip add vendor")
    t.ok(next(char) ~= nil, "the character's saved table was written")
    local again = boot({ char = char, seen = false })
    slash(again, "trip")
    t.ok(said(again, "1. Vendor: Bob") ~= nil, "listed after the reload")
end

return tests
