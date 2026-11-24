local _, ns = ...

-- End to end (S35, lead dispatch section 395 item 3): a trip stop on top of
-- Thunder Bluff, reached through the lift the player rode (a learned gate
-- in the account DB). The whole add-on on a fake client; "trip" lists the
-- stop with the lift line. With no gate learned the line says nothing of
-- a lift. Made-up spots; not tested in game.

local tests = {}

local MULGORE, TB = 1412, 1456

local function lift()
    return { a = MULGORE, b = TB, ax = 0.40, ay = 0.30, bx = 0.30, by = 0.70, cont = 1, wx = -1000, wy = 100 }
end

local function start(gates)
    local c = ns.make.fakeClient()
    local saved = {}
    if gates then saved = { learned = { places = { gates = gates } } } end
    c.setSaved(ns.id.accountDB, saved)
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, MULGORE); c.setPosition(MULGORE, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MULGORE, 1000, 1000); c.setMapCont(MULGORE, 1)
    c.setMapSize(TB, 300, 300); c.setMapCont(TB, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setOnTaxi(false)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
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

-- A bank stop on top of Thunder Bluff, then back to Mulgore. The jump is
-- made with no world position, so the gate watcher learns nothing new.
local function bankStop(c)
    c.setZone(1, TB); c.setPosition(TB, 0.5, 0.5)
    c.advance(1, 5)
    slash(c, "trip add here bank")
    c.setZone(1, MULGORE); c.setPosition(MULGORE, 0.5, 0.5)
    c.advance(1, 5)
end

tests["trip gates e2e: a stop up on Thunder Bluff says take the lift up"] = function(t)
    local c = start({ lift() })
    bankStop(c)
    slash(c, "trip")
    local line = said(c, "1. bank")
    t.ok(line ~= nil and line:find("Take the lift up to Thunder Bluff.", 1, true) ~= nil, tostring(line))
end

tests["trip gates e2e: no gate learned says nothing of a lift"] = function(t)
    local c = start(nil)
    bankStop(c)
    slash(c, "trip")
    local line = said(c, "1. bank")
    t.ok(line ~= nil, "the stop is listed")
    t.ok(line ~= nil and line:find("lift", 1, true) == nil, tostring(line))
    t.ok(line ~= nil and line:find("through", 1, true) == nil, tostring(line))
end

return tests
