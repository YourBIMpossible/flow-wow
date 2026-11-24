local _, ns = ...

-- End to end (G37, lead section 395 item 8): the whole add-on loaded the
-- way the game loads it (ns.offline.addon), on a fake client. The player
-- opens a vendor's window, meets the same vendor again across town, then
-- uses a mailbox twice from two sides. The saved places follow the vendor
-- (one entry, the new spot) and keep the one mailbox. Made-up npc and
-- places; not tested in game. Look only: nothing is bought or sent.

local tests = {}

local VENDOR = { guid = "Creature-0-1-2-3-77-0", name = "Tharn Ledgerkeep" }

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClock(5000)
    c.setZone(1, 1411); c.setPosition(1411, 0.4, 0.4); c.setFacing(0)
    c.setClass("WARRIOR"); c.setFaction("Horde")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function places(c)
    local root = c.saved(ns.id.charDB)
    root = type(root) == "table" and root.learned or nil
    root = type(root) == "table" and root.places or nil
    return type(root) == "table" and root.services or nil
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

tests["places moved: a vendor met again far away moves; a mailbox from two sides stays one"] = function(t)
    local c = start()
    t.eq(places(c), nil, "nothing before any window")

    c.setServiceNpc(VENDOR.guid, VENDOR.name)
    c.fire("MERCHANT_SHOW"); c.fire("MERCHANT_CLOSED")
    c.advance(1, 4)
    local e = places(c)[VENDOR.guid]
    t.eq(e and { e.map, e.x, e.y, e.n }, { 1411, 0.4, 0.4, 1 }, "first visit learned")

    c.setPosition(1411, 0.402, 0.403)
    c.fire("MERCHANT_SHOW"); c.fire("MERCHANT_CLOSED")
    c.advance(1, 4)
    e = places(c)[VENDOR.guid]
    t.eq({ e.x, e.y, e.n }, { 0.4, 0.4, 2 }, "a small step is not a move")

    c.setPosition(1411, 0.7, 0.2)
    c.fire("MERCHANT_SHOW"); c.fire("MERCHANT_CLOSED")
    c.advance(1, 4)
    e = places(c)[VENDOR.guid]
    t.eq({ e.x, e.y, e.n }, { 0.7, 0.2, 3 }, "moved to where it was met")
    t.eq(count(places(c)), 1, "one entry for the vendor")

    c.setServiceNpc(nil)
    c.setPosition(nil)
    c.fire("MAIL_SHOW"); c.fire("MAIL_CLOSED")
    c.advance(1, 4)
    t.eq(count(places(c)), 1, "no place, no mailbox saved")

    c.setPosition(1411, 0.604, 0.5)
    c.fire("MAIL_SHOW"); c.fire("MAIL_CLOSED")
    c.setPosition(1411, 0.607, 0.502)
    c.fire("MAIL_SHOW"); c.fire("MAIL_CLOSED")
    c.advance(1, 4)
    local box = places(c)["mailbox:1411:60:50"]
    t.eq(box and box.n, 2, "the same box twice")
    t.eq(count(places(c)), 2, "the vendor and one mailbox")
end

return tests
