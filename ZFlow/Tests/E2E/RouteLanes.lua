local _, ns = ...

-- End to end (S38): `lanes` groups the trip's stops into lanes through the
-- real entry: a quest hand-in and a vendor on the trip, herbs the player
-- gathered on the same map. Made-up places; not tested in game.

local tests = {}

local MAP = 1436

local function boot(profs)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setQuestLog({})
    c.setProfessions(profs)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    addon.store:set("char", ns.Nav.Trip.PATH, { stops = {
        { id = 1, kind = "giver", label = "Hand in: Wolves", place = { map = MAP, x = 0.6, y = 0.5 } },
        { id = 2, kind = "vendor", label = "Vendor: Bob", place = { map = MAP, x = 0.8, y = 0.5 } },
        { id = 3, kind = "here", label = "Camp", place = { map = MAP, x = 0.4, y = 0.5 } },
    } })
    addon.store:set("account", ns.Nav.Nodes.PATH, {
        [MAP] = { { x = 0.7, y = 0.5, prof = "Herbalism", n = 1, at = 1 },
                  { x = 0.7, y = 0.6, prof = "Herbalism", n = 1, at = 2 } },
    })
    return c, addon
end

local function said(c)
    local out = {}
    for _, line in ipairs(c.printed or {}) do out[#out + 1] = tostring(line) end
    return out
end

local function has(lines, a)
    for _, line in ipairs(lines) do
        if line:find(a, 1, true) then return line end
    end
    return nil
end

tests["route lanes e2e: lanes says each lane and tags each stop"] = function(t)
    local c = boot({ "Herbalism" })
    c.slashes[ns.id.slash]("lanes")
    c.advance(1, 5)
    local lines = said(c)
    local all = table.concat(lines, " | ")
    local A = ns.Nav.Activities
    t.ok(has(lines, ns.id.title .. ": Questing: 1 stop" .. A.SEP .. "Gathering: 2 Herbalism nodes on the way"
        .. A.SEP .. "Repair and vendor: 1 stop") ~= nil, all)
    t.ok(has(lines, "1. Hand in: Wolves - Questing") ~= nil, all)
    t.ok(has(lines, "2. Vendor: Bob - Repair and vendor") ~= nil, all)
    t.ok(has(lines, "3. Camp") ~= nil and has(lines, "3. Camp -") == nil, all)
end

tests["route lanes e2e: no gathering profession, no gathering lane"] = function(t)
    local c = boot(nil)
    c.slashes[ns.id.slash]("lanes")
    c.advance(1, 5)
    local lines = said(c)
    t.ok(has(lines, "Gathering") == nil, table.concat(lines, " | "))
    t.ok(has(lines, "Questing: 1 stop") ~= nil, table.concat(lines, " | "))
end

return tests
