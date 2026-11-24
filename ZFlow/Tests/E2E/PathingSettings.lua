local _, ns = ...
-- Pathing settings end to end (lead section 519 slice 2, audit S3-05), on
-- the whole add-on loaded on a fake client. One setting used to hide the
-- route list, the numbers and zone card on the map AND the lines on the
-- world map. Now the lines have their own row, the minimap pin of the
-- waypoint has a row, and the words of each row say what it hides. Both
-- new rows are on at first, so a saved account with neither key plays as
-- before.
-- Look only: nothing is moved, targeted or clicked. Made-up places. Not
-- tested in game.
--
-- Red before the code: no row "nav.mapLines" and none "nav.waypointPin";
-- the route setting off also clears the lines; its help says nothing of
-- the lines; the row of the profession arrow names the trainer only.
local tests = {}

local PANEL = "nav.routePanel"
local LINES = "nav.mapLines"
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

tests["pathing settings: the map lines have their own row, on at first, and it says what it hides"] = function(t)
    local _, addon = boot()
    local row = rowOf(addon, LINES)
    t.ok(row ~= nil, LINES .. " is a declared row")
    if not row then return end
    t.eq(row.scope, "account")
    t.eq(row.type, "bool")
    t.eq(row.default, true, "on at first")
    t.eq(addon.settings:get(LINES), true, "read as on with nothing saved")
    t.eq(row.label, "Show route lines on the map")
    t.ok(holds(row.help, "lines"), "the help names the lines: " .. tostring(row.help))
    t.ok(holds(row.help, "world map"), "the help says where: " .. tostring(row.help))
    t.ok(holds(row.help, "list"), "the help says the list stays: " .. tostring(row.help))
    t.ok(addon.Settings.Topics.Find(row.group) ~= nil, "it names a topic of the one list: " .. tostring(row.group))
    t.ok(type(row.synonyms) == "table" and #row.synonyms > 0, "it lists synonyms")
    t.eq(declaredTimes(addon, LINES), 1, "declared once")
    t.eq(ns.MapRouteLines.SETTING, LINES, "the lines module names its own setting")
end

tests["pathing settings: the waypoint minimap pin has a row, on at first, and it says what it hides"] = function(t)
    local _, addon = boot()
    local row = rowOf(addon, PIN)
    t.ok(row ~= nil, PIN .. " is a declared row")
    if not row then return end
    t.eq(row.scope, "account")
    t.eq(row.type, "bool")
    t.eq(row.default, true, "on at first, as before there was a row")
    t.eq(addon.settings:get(PIN), true, "read as on with nothing saved")
    t.ok(holds(row.label, "waypoint"), "the label names the waypoint: " .. tostring(row.label))
    t.ok(holds(row.label, "minimap"), "the label names the minimap: " .. tostring(row.label))
    t.ok(holds(row.help, "pin"), "the help names the pin: " .. tostring(row.help))
    t.ok(holds(row.help, "only"), "the help says only the pin goes: " .. tostring(row.help))
    t.ok(addon.Settings.Topics.Find(row.group) ~= nil, "it names a topic of the one list: " .. tostring(row.group))
    t.ok(type(row.synonyms) == "table" and #row.synonyms > 0, "it lists synonyms")
    t.eq(declaredTimes(addon, PIN), 1, "declared once")
    t.eq(ns.MinimapPin.SETTING, PIN, "the pin module names its own setting")
end

tests["pathing settings: a saved account with neither new key shows the list, the lines and the pin"] = function(t)
    local c, addon = boot({})
    t.eq(listShown(c), true, "the route list is shown beside the quest log")
    t.eq(linesShown(c), true, "the lines are drawn on the world map")
    t.eq(pinShown(c), true, "the waypoint pin is on the minimap")
    t.eq(addon.settings:get(PANEL), true, "the route setting is on, as before")
    t.eq(addon.settings:get(PROF), true, "the profession arrow is on, as before")
end

tests["pathing settings: the map lines off hides the lines and keeps the list and the pin"] = function(t)
    local c, addon = boot()
    local before = addon.problems:count()
    t.eq(linesShown(c), true, "on: the lines are drawn")
    local ok = addon.settings:set(LINES, false)
    t.ok(ok, "the row can be switched off")
    step(c)
    t.eq(linesShown(c), false, "off: no line on the world map")
    t.eq(listShown(c), true, "off: the route list is still shown")
    t.eq(pinShown(c), true, "off: the minimap pin is still shown")
    addon.settings:set(LINES, true)
    step(c)
    t.eq(linesShown(c), true, "on again: the lines are back")
    t.eq(addon.problems:count(), before, "no problem was counted")
end

tests["pathing settings: the map lines saved off draws no line from the start"] = function(t)
    local c, addon = boot({ settings = { nav = { mapLines = false } } })
    t.eq(addon.settings:get(LINES), false, "the saved choice is read")
    t.eq(linesShown(c), false, "no line on the world map")
    t.eq(listShown(c), true, "the route list is shown")
end

tests["pathing settings: the route setting off hides the list and leaves the lines to their own row"] = function(t)
    local c, addon = boot()
    local before = addon.problems:count()
    t.eq(listShown(c), true, "on: the list is shown")
    addon.settings:set(PANEL, false)
    step(c)
    t.eq(listShown(c), false, "off: the route list is hidden")
    t.eq(linesShown(c), true, "off: the lines stay, their own row is on")
    t.eq(pinShown(c), true, "off: the minimap pin stays")
    addon.settings:set(LINES, false)
    step(c)
    t.eq(linesShown(c), false, "both off: no lines either")
    addon.settings:set(PANEL, true)
    step(c)
    t.eq(listShown(c), true, "the list is back")
    t.eq(linesShown(c), false, "and the lines stay off with their own row")
    t.eq(addon.problems:count(), before, "no problem was counted")
end

tests["pathing settings: the route setting saved off still draws the lines"] = function(t)
    local c = boot({ settings = { nav = { routePanel = false } } })
    t.eq(listShown(c), false, "no route list")
    t.eq(linesShown(c), true, "the lines are drawn")
end

tests["pathing settings: the help of the route row says what it hides and where the lines went"] = function(t)
    local _, addon = boot()
    local row = rowOf(addon, PANEL)
    t.ok(row ~= nil, PANEL .. " is a declared row")
    if not row then return end
    t.eq(row.default, true, "still on at first")
    t.eq(row.scope, "account", "still saved for the account")
    t.ok(holds(row.help, "quest log"), "the list beside the quest log: " .. tostring(row.help))
    t.ok(holds(row.help, "card"), "the zone card: " .. tostring(row.help))
    t.ok(holds(row.help, "lines"), "it mentions the lines: " .. tostring(row.help))
    t.ok(holds(row.help, "show route lines on the map"), "it names the row the lines have: " .. tostring(row.help))
end

tests["pathing settings: the minimap pin off hides only that pin; on shows it again"] = function(t)
    local c, addon = boot()
    local before = addon.problems:count()
    t.eq(pinShown(c), true, "on: the pin is shown")
    local ok = addon.settings:set(PIN, false)
    t.ok(ok, "the row can be switched off")
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

tests["pathing settings: the row of the profession arrow names every step it covers"] = function(t)
    local _, addon = boot()
    local row = rowOf(addon, PROF)
    t.ok(row ~= nil, PROF .. " is a declared row")
    if not row then return end
    t.eq(row.default, true, "still on at first")
    t.eq(row.scope, "account", "still saved for the account")
    t.eq(row.group, "travel.arrow", "still filed with the arrow")
    local words = tostring(row.label) .. " " .. tostring(row.help)
    for _, word in ipairs({ "trainer", "gather", "craft", "buy" }) do
        t.ok(holds(words, word), "the row says " .. word .. ": " .. words)
    end
    t.ok(row.label ~= "Profession trainer arrow", "the label is not the trainer alone")
    t.ok(type(row.help) == "string" and row.help ~= "", "the row has help")
end

return tests
