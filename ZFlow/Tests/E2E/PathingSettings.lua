local _, ns = ...
-- Pathing settings end to end (lead sections 519, 532 and 543, slice 2,
-- audit S3-05), on the whole add-on loaded on a fake client. The words are
-- the design spec, word for word (from-muse
-- MUSE-TO-CLAUDE-SLICE-2-SETTINGS.md): the help of the route row says it
-- hides the map trail too; the minimap pin of the waypoint has a row, in
-- the map and minimap group; the row of the profession arrow names every
-- step it covers. The route marker key has no row yet (lead section 560). The row for the map trail itself belongs to slice
-- 3, not here. Both new rows are on at first, so a saved account with
-- neither key plays as before.
-- Look only: nothing is moved, targeted or clicked. Made-up places. Not
-- tested in game.
--
-- Red before the code: no row "nav.waypointPin";
-- the help of the route row says nothing of the trail; the row of the
-- profession arrow names the trainer only.
local tests = {}

local PANEL = "nav.routePanel"
local MARKER = "nav.minimapPin"
local PIN = "nav.waypointPin"
local PROF = "nav.profArrow"

local MAP = 1411
local BOX = { shown = true, right = 400, top = 700, height = 450 }
local ROUND = { size = 140, radius = 100, rotates = false }

-- account: the account saved table to start from. The quest log and the
-- world map are open and the waypoint is set (the green line on the map
-- and the minimap pin both come from it).
local function boot(account)
    local c = ns.make.fakeClient()
    account = account or {}
    account.layout = account.layout or {}
    if account.layout.arrowIntroSeen == nil then account.layout.arrowIntroSeen = true end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setMinimap(ROUND)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    c.setQuestLogFrame(BOX)
    c.setWorldMap(MAP)
    c.setWaypoint(MAP, 0.7, 0.4)
    c.slashes[ns.id.slash]("way 52 47")
    c.advance(2, 20)
    return c, addon
end

local function step(c) c.advance(2, 20) end

-- Is any line drawn on the world map now.
local function linesShown(c)
    for _, set in ipairs(type(c.routeLineSets) == "table" and c.routeLineSets or {}) do
        if set.shown == true then return true end
    end
    return false
end

local function listShown(c)
    local w = c.kitWindows()[ns.RouteList.ID]
    return type(w) == "table" and w.shown == true
end

-- The minimap pin of the waypoint: the one made with its name.
local function pinShown(c)
    local name = tostring(ns.id.addon) .. "MinimapPin"
    for _, h in ipairs(c.minimapPins or {}) do
        if type(h.spec) == "table" and h.spec.name == name then return h.shown == true end
    end
    return false
end

local function holds(text, word)
    return type(text) == "string" and text:lower():find(word, 1, true) ~= nil
end

local function rowOf(addon, key)
    local row = addon.settings:row(key)
    if type(row) ~= "table" then return nil end
    return row
end

local function declaredTimes(addon, key)
    local n = 0
    for r in addon.settings:each() do
        if r.key == key then n = n + 1 end
    end
    return n
end

local PANEL_HELP = 'Shows the stops of your route in order beside the quest log while it is open, and numbers '
    .. 'them on the world map with a card for the zone. Turning it off hides the list, the map pins, the zone '
    .. 'card and the map trail together. To hide only the trail, turn off "Show route lines on the map" instead.'
local PIN_LABEL = "Show your waypoint on the minimap"
local PIN_HELP = "Puts a green dot on the minimap for a waypoint you set yourself, so you can see it without "
    .. "opening the map."
local PROF_LABEL = "Profession arrow"
local PROF_HELP = "Shows a second, purple arrow for your profession steps: gathering in an area, smelting or "
    .. "crafting at a station, learning at a trainer, or buying from a vendor."

tests["pathing settings: the waypoint minimap pin has a row, on at first, in the spec's words"] = function(t)
    local _, addon = boot()
    local row = rowOf(addon, PIN)
    t.ok(row ~= nil, PIN .. " is a declared row")
    if not row then return end
    t.eq(row.scope, "account")
    t.eq(row.type, "bool")
    t.eq(row.default, true, "on at first, as before there was a row")
    t.eq(addon.settings:get(PIN), true, "read as on with nothing saved")
    t.eq(row.label, PIN_LABEL)
    t.eq(row.help, PIN_HELP)
    t.eq(row.group, "travel.map", "filed with the map and minimap")
    t.ok(addon.Settings.Topics.Find(row.group) ~= nil, "it names a topic of the one list: " .. tostring(row.group))
    t.eq(declaredTimes(addon, PIN), 1, "declared once")
    -- Lead section 560: the route marker's row waits for the slice that
    -- draws the dot; its key has no row yet.
    t.eq(rowOf(addon, MARKER), nil, "no row for " .. MARKER .. " yet")
    t.eq(ns.MinimapPin.SETTING, PIN, "the pin module names its own setting")
end

tests["pathing settings: a saved account with neither new key shows the list, the lines and the pin"] = function(t)
    local c, addon = boot()
    t.eq(addon.settings:get(PANEL), true)
    t.eq(listShown(c), true, "the route list")
    t.eq(linesShown(c), true, "the lines on the world map")
    t.eq(pinShown(c), true, "the minimap pin of the waypoint")
end

tests["pathing settings: the route setting off hides the list and the map trail together"] = function(t)
    local c, addon = boot()
    local before = addon.problems:count()
    t.ok(addon.settings:set(PANEL, false), "the row can be switched off")
    step(c)
    t.eq(listShown(c), false, "off: the list goes")
    t.eq(linesShown(c), false, "off: the map trail goes with it")
    t.eq(pinShown(c), true, "off: the minimap pin of the waypoint stays")
    addon.settings:set(PANEL, true)
    step(c)
    t.eq(listShown(c), true, "on again: the list is back")
    t.eq(linesShown(c), true, "on again: the trail is back")
    t.eq(addon.problems:count(), before, "no problem was counted")
end

tests["pathing settings: the help of the route row is the spec's and says the trail goes too"] = function(t)
    local _, addon = boot()
    local row = rowOf(addon, PANEL)
    t.ok(row ~= nil, PANEL .. " is a declared row")
    if not row then return end
    t.eq(row.default, true, "still on at first")
    t.eq(row.scope, "account", "still saved for the account")
    t.eq(row.label, "Show the route beside the quest log and on the map", "the label is as it was")
    t.eq(row.help, PANEL_HELP)
    t.ok(holds(row.help, "map trail"), "it mentions the trail")
end

tests["pathing settings: the minimap pin off hides only that pin; on shows it again"] = function(t)
    local c, addon = boot()
    local before = addon.problems:count()
    t.eq(pinShown(c), true, "on: the pin is shown")
    t.ok(addon.settings:set(PIN, false), "the row can be switched off")
    step(c)
    t.eq(pinShown(c), false, "off: the pin is hidden")
    t.eq(linesShown(c), true, "off: the lines on the world map stay")
    t.eq(listShown(c), true, "off: the route list stays")
    local last = addon.use(ns.MinimapPin.NAME).Last()
    t.eq(type(last) == "table" and last.shown, false, "the module says it is not shown")
    addon.settings:set(PIN, true)
    step(c)
    t.eq(pinShown(c), true, "on again: the pin is back")
    t.eq(addon.problems:count(), before, "no problem was counted")
end

tests["pathing settings: the minimap pin saved off makes no pin"] = function(t)
    local c, addon = boot({ settings = { nav = { waypointPin = false } } })
    t.eq(addon.settings:get(PIN), false, "the saved choice is read")
    t.eq(pinShown(c), false, "no pin on the minimap")
    t.eq(linesShown(c), true, "the lines are drawn")
end

tests["pathing settings: the row of the profession arrow is the spec's and names every step it covers"] = function(t)
    local _, addon = boot()
    local row = rowOf(addon, PROF)
    t.ok(row ~= nil, PROF .. " is a declared row")
    if not row then return end
    t.eq(row.default, true, "still on at first")
    t.eq(row.scope, "account", "still saved for the account")
    t.eq(row.group, "travel.arrow", "still filed with the arrow")
    t.eq(row.label, PROF_LABEL)
    t.eq(row.help, PROF_HELP)
    -- The sentence about sitting behind and sliding out comes with the echo.
    t.ok(not holds(row.help, "slides"), "no word of the slide yet")
    local said = {}
    for _, word in ipairs(type(row.synonyms) == "table" and row.synonyms or {}) do said[word] = true end
    for _, word in ipairs({ "profession", "trainer", "arrow", "gather", "craft", "buy", "smelt", "skill cap" }) do
        t.ok(said[word] == true, "a synonym: " .. word)
    end
    t.ok(said["needle"] ~= true, "the needle is gone")
end

return tests
