local _, ns = ...

-- Parity row A1-40 (lead sections 862 and 864.3): the waypoint box. As
-- legacy Flow's Modules/Nav/Waypoint.lua:217-231 (Flow's waypoint
-- popup, its only caller the arrow menu's "Set a waypoint..." row,
-- Modules/Menu.lua:575): one line typed or pasted, Accept or Enter sets the
-- waypoint the way the way word does.
--   WW.SetFromText(text) through the module: every text the way word takes
--     (x y, a zone and x y, a place word, a party member) gives the same
--     answer; junk sets nothing.
--   Prompt(): opens the client's input box (c.inputBox); what is typed goes
--     through SetFromText and the answer is said in chat. With no input box
--     it says so and nothing else happens.
-- Whole add-on loaded the way the game loads it, on a fake client; made-up
-- zones, places and names. The menu row is a lead patch (UI/ArrowMenu.lua).
-- Not tested in game. Red before the code: the module has no SetFromText
-- and no Prompt.

local tests = {}

local MAP, FAR = 1411, 1413

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { places = { services = {
        s = { name = "Near Smith", map = MAP, x = 0.6, y = 0.5, kinds = { repair = true }, seen = 10, n = 1 },
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

local function waypoint(addon)
    local W = ns.Nav.Waypoint
    local slot = addon.store:get(W.SCOPE, W.PATH)
    local wp = type(slot) == "table" and slot.waypoint or nil
    if type(wp) ~= "table" then return nil end
    return { map = wp.map, x = wp.x, y = wp.y, label = wp.label }
end

local function api(t, addon)
    local w = addon.use(ns.Nav.WayWords.NAME)
    local ok = type(w) == "table" and type(w.SetFromText) == "function" and type(w.Prompt) == "function"
    t.ok(ok, "the way words give SetFromText and Prompt")
    if not ok then return nil end
    return w
end

tests["way prompt: x and y on the map you are on set the waypoint there"] = function(t)
    local _, addon = boot()
    local w = api(t, addon)
    if not w then return end
    local done, line = w.SetFromText("45.2 61.8 Camp")
    t.eq(done, true)
    t.ok(type(line) == "string" and line ~= "", "a line to say")
    local wp = waypoint(addon)
    t.eq(wp and wp.map, MAP)
    t.ok(wp and math.abs(wp.x - 0.452) < 1e-9 and math.abs(wp.y - 0.618) < 1e-9, "45.2, 61.8")
    t.eq(wp and wp.label, "Camp")
end

tests["way prompt: a zone you are not in, a place word and a party member, as the way word"] = function(t)
    local _, addon = boot()
    local w = api(t, addon)
    if not w then return end
    t.eq((w.SetFromText("Far Fields 40 60")), true)
    t.eq(waypoint(addon) and waypoint(addon).map, FAR, "the zone by its name")
    t.eq((w.SetFromText("repair")), true)
    t.eq(waypoint(addon) and waypoint(addon).x, 0.6, "the repair vendor seen")
    t.eq((w.SetFromText("Zed")), true)
    t.eq(waypoint(addon) and waypoint(addon).y, 0.75, "where Zed stands")
end

tests["way prompt: text that is no waypoint sets nothing and says why"] = function(t)
    local _, addon = boot()
    local w = api(t, addon)
    if not w then return end
    local done, line = w.SetFromText("hello there")
    t.eq(done, false)
    t.ok(type(line) == "string" and line ~= "", "a reason to say")
    t.eq(waypoint(addon), nil, "nothing set")
    t.eq((w.SetFromText("")), false, "nothing typed")
    t.eq((w.SetFromText(nil)), false)
    t.eq(waypoint(addon), nil)
end

tests["way prompt: the box opens, and what is typed sets the waypoint and is said"] = function(t)
    local c, addon = boot()
    local w = api(t, addon)
    if not w then return end
    t.eq(w.Prompt(), true, "the box opened")
    t.eq(waypoint(addon), nil, "nothing set before anything is typed")
    local before = #c.printed
    c.typeInputBox("30 40")
    local wp = waypoint(addon)
    t.eq(wp and wp.map, MAP)
    t.ok(wp and math.abs(wp.x - 0.30) < 1e-9 and math.abs(wp.y - 0.40) < 1e-9, "30, 40")
    t.eq(#c.printed, before + 1, "one line said")
end

tests["way prompt: no input box on the client: it says so, nothing else happens"] = function(t)
    local c, addon = boot()
    local w = api(t, addon)
    if not w then return end
    c.inputBox = nil
    local shown, why = w.Prompt()
    t.eq(shown, false)
    t.eq(why, ns.Nav.WayWords.NO_BOX)
    t.eq(waypoint(addon), nil)
end

return tests
