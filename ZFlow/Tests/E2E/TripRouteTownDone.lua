local _, ns = ...
-- A town stop is done when the thing is done, not when you walk up to it
-- (Twin's plan, lead sections 545 and 552, note 1). The sell stop goes when
-- the bags have room, the repair stop when the gear is mended, the
-- set-hearthstone stop when that inn is your home. A stop reached but not
-- done stays first in the route; walking away from it lets it go, so no
-- stop sticks for ever. When it cannot be told, reaching it is enough, as
-- before. Whole add-on on a fake client; made-up quests and places. Look
-- only: nothing is sold, repaired or set. Not tested in game.
-- Red on 55d86dac: there is no T.TownDone, and each stop is gone as soon as
-- you stand at it.
local tests = {}

local MAP = 1436
local SELL, HOME, MEND = "Bags full: sell at Bread Seller", "Set hearthstone: Inn Keeper", "Repair: Test Smith"

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
        [403] = { ObjectiveData = {}, Finisher = { NPC = { 9103 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 20, 50 } } } },
        [9103] = { name = "Smith", spawns = { [40] = { { 55, 50 } } } },
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
    { id = 403, title = "Bandages", complete = true, objectives = { { text = "Linen: 4/4", done = true } } },
}

local function services(list)
    return { learned = { places = { services = list } } }
end
local VENDOR = { name = "Bread Seller", map = MAP, x = 0.52, y = 0.5, kinds = { vendor = true } }
local INN = { name = "Inn Keeper", map = MAP, x = 0.4, y = 0.5, kinds = { innkeeper = true } }
local SMITH = { name = "Test Smith", map = MAP, x = 0.48, y = 0.5, kinds = { repair = true }, seen = 10, n = 1 }
local FULL, ROOM = { { bag = 0, free = 0, total = 16 } }, { { bag = 0, free = 10, total = 16 } }
local LOW, FINE = { [5] = { cur = 5, max = 100 } }, { [5] = { cur = 100, max = 100 } }

-- opts: char, bags, durability
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, opts.char or {})
    if opts.bags then c.setBags(opts.bags) end
    if opts.durability then c.setDurability(opts.durability) end
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    return c, addon, addon.problems:count()
end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

local function at(c, x)
    c.setPosition(MAP, x, 0.5)
    c.advance(2, 5)
end

-- Is that stop still one the route walks to?
local function onRoute(addon, label)
    local trip = addon.use(ns.Nav.TripRoute.NAME)
    local view = type(trip) == "table" and trip.View() or nil
    for _, s in ipairs(type(view) == "table" and view.stops or {}) do
        if s.label == label then return true end
    end
    return false
end

-- Red on 55d86dac: at the vendor with the bags still full the stop is gone.
tests["town stop done: the sell stop stays at the vendor until the bags have room"] = function(t)
    local c, addon, base = boot({ char = services({ v = VENDOR }), bags = FULL })
    t.eq(first(c), SELL, "the sell stop is first")
    at(c, 0.52)
    t.eq(first(c), SELL, "at the vendor, bags still full: the stop stays first")
    t.eq(onRoute(addon, SELL), true)
    c.setBags(ROOM)
    c.advance(2, 5)
    t.eq(onRoute(addon, SELL), false, "sold: the stop is done")
    t.ok(first(c) ~= SELL, "and the arrow goes on: " .. tostring(first(c)))
    t.eq(addon.problems:count(), base, "no new problem")
end

-- No stop sticks for ever. Red on 55d86dac only in its first check (the
-- stop was gone at the vendor already).
tests["town stop done: walking away from a stop reached but not done lets it go"] = function(t)
    local c, addon, base = boot({ char = services({ v = VENDOR }), bags = FULL })
    at(c, 0.52)
    t.eq(onRoute(addon, SELL), true, "reached, not sold: still there")
    at(c, 0.7)
    t.eq(onRoute(addon, SELL), false, "walked away without selling: let go")
    at(c, 0.52)
    t.eq(onRoute(addon, SELL), false, "and it does not come back")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on 55d86dac: at the smith with the gear still worn the stop is gone.
tests["town stop done: the repair stop stays until the gear is mended"] = function(t)
    local c, addon, base = boot({ char = services({ s = SMITH }), durability = LOW })
    t.eq(onRoute(addon, MEND), true, "the repair stop is on the route")
    at(c, 0.48)
    t.eq(onRoute(addon, MEND), true, "at the smith, gear still worn: the stop stays")
    c.setDurability(FINE)
    c.fire("UPDATE_INVENTORY_DURABILITY")
    c.advance(12, 12)
    t.eq(onRoute(addon, MEND), false, "repaired: the stop is done")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on 55d86dac: at the inn with another home the stop is gone.
tests["town stop done: the set-hearthstone stop stays until that inn is your home"] = function(t)
    local c, addon, base = boot({ char = services({ i = INN }) })
    t.eq(onRoute(addon, HOME), true, "the set-hearthstone stop is on the route")
    at(c, 0.4)
    t.eq(onRoute(addon, HOME), true, "at the inn, home not set: the stop stays")
    c.setBindLocation("Inn Keeper")
    c.advance(2, 5)
    t.eq(onRoute(addon, HOME), false, "home set there: the stop is done")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Section 236: a read that gives nothing (then answers). When it cannot be
-- told, reaching the stop is enough, as before.
tests["town stop done: bags that cannot be read at the vendor - reaching it is enough"] = function(t)
    local c, addon, base = boot({ char = services({ v = VENDOR }), bags = FULL })
    c.setBags(nil)
    at(c, 0.52)
    t.eq(onRoute(addon, SELL), false, "not known whether you sold: gone on reaching it, as before")
    t.eq(addon.problems:count(), base, "no new problem")
    local c2, addon2 = boot({ char = services({ v = VENDOR }), bags = FULL })
    local real = c2.bags
    c2.bags = function() error("no bags (test)") end
    at(c2, 0.52)
    t.eq(onRoute(addon2, SELL), false, "a bags read that raises: the same")
    c2.bags = real
    c2.advance(2, 5)
    t.eq(onRoute(addon2, SELL), false, "and it does not come back when the read answers")
end

tests["town stop done: the rule, pure"] = function(t)
    local T = ns.Nav.TripRoute
    t.eq(T.TownDone({ kind = "sell" }, { free = T.SELL_NEAR + 1 }), true, "room in the bags")
    t.eq(T.TownDone({ kind = "sell" }, { free = T.SELL_NEAR }), false, "still nearly full")
    t.eq(T.TownDone({ kind = "sell" }, { free = 0 }), false)
    t.eq(T.TownDone({ kind = "sell" }, {}), nil, "bags not read: cannot tell")
    t.eq(T.TownDone({ kind = "repair" }, { repair = false }), true, "no repair due any more")
    t.eq(T.TownDone({ kind = "repair" }, { repair = true }), false)
    t.eq(T.TownDone({ kind = "repair" }, {}), nil)
    t.eq(T.TownDone({ kind = "riding" }, { riding = false }), true, "riding learned")
    t.eq(T.TownDone({ kind = "riding" }, { riding = true }), false)
    t.eq(T.TownDone({ kind = "riding" }, {}), nil)
    t.eq(T.TownDone({ kind = "hearth", inn = "Inn Keeper" }, { bind = "Inn Keeper" }), true, "that inn is home")
    t.eq(T.TownDone({ kind = "hearth", inn = "Inn Keeper" }, { bind = "Other Inn" }), false)
    t.eq(T.TownDone({ kind = "hearth", inn = "Inn Keeper" }, {}), nil, "home not read")
    t.eq(T.TownDone({ kind = "hearth" }, { bind = "Inn Keeper" }), nil, "an inn with no name")
    t.eq(T.TownDone({ kind = "pickup" }, { free = 9 }), nil, "not a town stop")
    t.eq(T.TownDone(nil, nil), nil)
end

return tests
