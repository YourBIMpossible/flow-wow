local _, ns = ...

-- Services this player met (G37, Nav/ServiceSeen.lua), on the whole add-on
-- loaded on a fake client. The real entry: the game's MERCHANT_SHOW and
-- MAIL_SHOW events. A repair vendor learned at its window is the one the
-- arrow's repair stop points at once gear runs low; a mailbox is saved by
-- its place. Nothing is printed, opened or talked to. Made-up places and
-- names. Not tested in game.
--
-- Map 1411 is 1000 x 1000 yards. The smith's window is opened at
-- (0.2, 0.5); the player then walks to (0.1, 0.5), 100 yards west.

local tests = {}
local SS, RS = ns.ServiceSeen, ns.RepairStep

local MAP, GUID, SMITH = 1411, "Creature-0-1-2-3-4-5", "Test Smith"

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

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, MAP); c.setPosition(MAP, 0.2, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setDurability({ [5] = { cur = 100, max = 100 } })
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function places(addon)
    local v = addon.store:get("char", SS.PLACES)
    return type(v) == "table" and v or {}
end

local function lines(c)
    local a = c.arrows[1]
    return a and a.lines or {}
end

local function size(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

tests["service seen: a repair vendor's window saves it, and low gear points there"] = function(t)
    local c, addon = boot()
    c.setServiceNpc(GUID, SMITH)
    c.setMerchantRepairs(true)
    c.fire("MERCHANT_SHOW")
    local e = places(addon)[GUID]
    t.eq(e and e.name, SMITH, "saved by its GUID")
    t.eq(e and e.map, MAP)
    t.eq(e and e.kinds and e.kinds.vendor, true, "a vendor")
    t.eq(e and e.kinds and e.kinds.repair, true, "that repairs")
    t.eq(e and e.n, 1, "seen once")
    -- Walk away, then the gear runs low: the arrow points back at the smith.
    c.setPosition(MAP, 0.1, 0.5)
    c.setDurability({ [5] = { cur = 5, max = 100 } })
    c.fire("UPDATE_INVENTORY_DURABILITY")
    c.advance(10, 40)
    t.eq(lines(c)[1], RS.LABEL .. ": " .. SMITH)
end

tests["service seen: a vendor that does not repair is no repair stop"] = function(t)
    local c, addon = boot()
    c.setServiceNpc(GUID, "Bread Seller")
    c.setMerchantRepairs(false)
    c.fire("MERCHANT_SHOW")
    local e = places(addon)[GUID]
    t.eq(e and e.kinds and e.kinds.vendor, true)
    t.eq(e and e.kinds and e.kinds.repair, nil, "no repair mark")
    c.setDurability({ [5] = { cur = 5, max = 100 } })
    c.fire("UPDATE_INVENTORY_DURABILITY")
    c.advance(10, 40)
    t.eq(lines(c)[1], "Wolves")
end

tests["service seen: a mailbox is saved by its place, once"] = function(t)
    local c, addon = boot()
    c.fire("MAIL_SHOW")
    c.fire("MAIL_SHOW")
    local key = "mailbox:" .. MAP .. ":20:50"
    local e = places(addon)[key]
    t.eq(e and e.kinds and e.kinds.mailbox, true, "a mailbox")
    t.eq(e and e.x, 0.2)
    t.eq(e and e.name, nil, "no name made up")
    t.eq(e and e.n, 2, "the same box twice is one entry")
    t.eq(size(places(addon)), 1)
end

tests["service seen: unknown data saves nothing"] = function(t)
    -- The position not known: nothing is written.
    local c, addon = boot()
    c.setServiceNpc(GUID, SMITH)
    c.setMerchantRepairs(true)
    c.setPosition(nil)
    c.fire("MERCHANT_SHOW")
    c.fire("MAIL_SHOW")
    t.eq(size(places(addon)), 0, "no position: no place")
    local last = addon.use(SS.NAME).Last()
    t.eq(last and last.reason, "the position is not known")
    -- The npc not known: nothing is written.
    c, addon = boot()
    c.fire("MERCHANT_SHOW")
    t.eq(size(places(addon)), 0, "no npc: no place")
    -- Whether it repairs not known: a vendor, never taken as a smith.
    c, addon = boot()
    c.setServiceNpc(GUID, SMITH)
    c.fire("MERCHANT_SHOW")
    local e = places(addon)[GUID]
    t.eq(e and e.kinds and e.kinds.vendor, true)
    t.eq(e and e.kinds and e.kinds.repair, nil, "repairs unknown: no mark")
end

return tests
