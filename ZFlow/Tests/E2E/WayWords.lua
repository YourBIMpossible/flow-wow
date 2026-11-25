local _, ns = ...

-- Lead section 460, parity rows A1-39, A1-41, A1-42: the waypoint words
-- past "x y". The player types the line with the addon's own command (as
-- /way does when no other addon holds it) and reads the answer in chat:
--   A1-39  "way Far Fields 40 60 Camp" from another zone: a waypoint there.
--   A1-41  "way repair": a waypoint at the nearest repair vendor seen.
--   A1-42  "way Zed": a waypoint where the party member Zed stands now;
--          the arrow menu's row "Waypoint at Zed" does the same.
-- Whole add-on loaded the way the game loads it (ns.offline.addon) on a
-- fake client; made-up zones, places and names. Not tested in game.
-- The command lower-cases what follows it, so the label is "camp".
-- Fails before: each of these words is turned down ("x is not a number").

local tests = {}

local MAP, FAR = 1411, 1413

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { places = { services = {
        s = { name = "Near Smith", map = MAP, x = 0.6, y = 0.5, kinds = { repair = true }, seen = 10, n = 1 },
        v = { name = "Near Trader", map = MAP, x = 0.3, y = 0.5, kinds = { vendor = true }, seen = 10, n = 1 },
    } } } })
    c.setScreen(1024, 768)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 500); c.setMapCont(MAP, 1); c.setMapCont(FAR, 1)
    c.setMapName(MAP, "Home Vale"); c.setMapName(FAR, "Far Fields")
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setParty({ { unit = "party1", name = "Zed" } })
    c.setUnitPosition("party1", MAP, 0.25, 0.75)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function slash(c, rest) c.slashes[ns.id.slash](rest) end

local function waypoint(addon)
    local W = ns.Nav.Waypoint
    local slot = addon.store:get(W.SCOPE, W.PATH)
    local wp = type(slot) == "table" and slot.waypoint or nil
    if type(wp) ~= "table" then return nil end
    return { map = wp.map, x = wp.x, y = wp.y, label = wp.label }
end

local function last(c) return c.printed[#c.printed] end

tests["way words: a zone you are not in, by its name"] = function(t)
    local c, addon = boot()
    slash(c, "way Far Fields 40 60 Camp")
    t.eq(waypoint(addon), { map = FAR, x = 0.4, y = 0.6, label = "camp" })
    t.ok(tostring(last(c)):find("waypoint set: 40.0, 60.0 camp", 1, true) ~= nil, tostring(last(c)))
end

tests["way words: a zone no map is named: turned down, nothing set"] = function(t)
    local c, addon = boot()
    slash(c, "way Nowhere Land 40 60")
    t.eq(waypoint(addon), nil)
    t.ok(tostring(last(c)):find("no zone named", 1, true) ~= nil, tostring(last(c)))
end

tests["way words: repair points at the nearest repair vendor seen"] = function(t)
    local c, addon = boot()
    slash(c, "way repair")
    local wp = waypoint(addon)
    t.eq(wp and wp.map, MAP)
    t.eq(wp and wp.x, 0.6)
    t.ok(wp and wp.label and wp.label:find("Near Smith", 1, true) ~= nil, tostring(wp and wp.label))
end

tests["way words: a place word with none seen says so"] = function(t)
    local c, addon = boot()
    slash(c, "way mail")
    t.eq(waypoint(addon), nil)
    -- Which kind, and how one comes to be known (lead section 595 item 3):
    -- the line is the module's own (WW.NONE) with the kind's name in it.
    local WW = ns.Nav.WayWords
    local want = type(WW.NONE) == "string" and type(WW.NAMES) == "table" and WW.NONE:format(WW.NAMES.mail) or nil
    t.ok(want ~= nil, "the module has its no-place line and the kinds' names")
    t.ok(want ~= nil and tostring(last(c)):find(want, 1, true) ~= nil, tostring(last(c)))
end

-- Flow's other words for the same places (its Modules/Nav/Waypoint.lua
-- ALIAS): sell, taxi, fly, flightmaster, innkeeper, hearth, banker, ah,
-- auctioneer, mailbox. Fails before: none of them is taken.
tests["way words: Flow's other words for a place mean the same place"] = function(t)
    local WW = ns.Nav.WayWords
    t.ok(type(WW.Word) == "function", "WW.Word names the kind a word means")
    if type(WW.Word) ~= "function" then return end
    local want = { sell = "vendor", taxi = "flight", fly = "flight", flightmaster = "flight",
        innkeeper = "inn", hearth = "inn", banker = "bank", ah = "auction", auctioneer = "auction",
        mailbox = "mail", repair = "repair", vendor = "vendor", mail = "mail" }
    for word, kind in pairs(want) do
        t.eq(WW.Word(word), kind, word)
    end
    t.eq(WW.Word("SELL"), "vendor", "any case")
    t.eq(WW.Word("zed"), nil, "a word that is no place")
    t.eq(WW.Word(nil), nil)
end

tests["way words: sell points at the nearest vendor seen, as vendor does"] = function(t)
    local c, addon = boot()
    slash(c, "way sell")
    local wp = waypoint(addon)
    t.eq(wp and wp.map, MAP)
    t.eq(wp and wp.x, 0.3)
end

tests["way words: a party member's name sets a waypoint where they stand"] = function(t)
    local c, addon = boot()
    slash(c, "way zed")
    t.eq(waypoint(addon), { map = MAP, x = 0.25, y = 0.75, label = "Zed" })
end

tests["way words: the arrow menu's Waypoint at Zed does the same"] = function(t)
    local c, addon = boot()
    local a = c.arrows[1]
    a.click("right")
    t.eq(a.enter("follow"), true, "the party level")
    t.eq(a.pickRow("wayat.party1"), true, "Waypoint at Zed")
    t.eq(waypoint(addon), { map = MAP, x = 0.25, y = 0.75, label = "Zed" })
end

return tests
