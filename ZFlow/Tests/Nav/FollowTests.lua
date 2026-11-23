-- Tests for Nav/Follow.lua (G47): the arrow points at a chosen party
-- member, from the game's own unit position read only, until stopped or
-- they leave; position not known: one line and the normal step. Nothing
-- follows, targets or moves. Fake client; made-up names. Not tested in game.
local _, ns = ...

local N = ns.Nav
local A = ns.Arrow
local tests = {}

local MAP = 1411

local function has(t)
    local F = N.Follow
    local ok = type(F) == "table" and type(F.Declare) == "function"
    t.ok(ok, "Nav/Follow.lua is loaded")
    return ok
end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setZone(1, MAP)
    c.setFacing(0)
    c.setPosition(MAP, 0.5, 0.5)
    c.setMapSize(MAP, 1000, 500)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    c.setWaypoint(MAP, 0.1, 0.1)
    c.setParty({ { unit = "party1", name = "Ann" }, { unit = "party2", name = "Bob" } })
    c.setUnitPosition("party2", MAP, 0.7, 0.2)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    N.Follow.Declare(k, d)
    local a = A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, a
end

local function said(c, text)
    for _, line in ipairs(c.printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function settle(c) c.advance(A.RELAYOUT * 2, 2) end

local PIN = { cont = 1, map = MAP, x = 0.1, y = 0.1 }

tests["follow: the word picks a party member and the arrow points at them"] = function(t)
    if not has(t) then return end
    local _, c, a = start()
    settle(c)
    t.eq(a.heading(), PIN, "the map pin before")
    c.slashes[ns.id.slash]("follow")
    t.ok(said(c, "Bob"), "the word with nothing lists the party")
    c.slashes[ns.id.slash]("follow bob")
    settle(c)
    t.eq(a.heading(), { cont = 1, map = MAP, x = 0.7, y = 0.2 })
    c.slashes[ns.id.slash]("follow stop")
    settle(c)
    t.eq(a.heading(), PIN, "stopped: the pin again")
end

tests["follow: by number too"] = function(t)
    if not has(t) then return end
    local _, c, a = start()
    c.slashes[ns.id.slash]("follow 2")
    settle(c)
    t.eq(a.heading(), { cont = 1, map = MAP, x = 0.7, y = 0.2 })
end

tests["follow: a position not known says so once and falls back to the normal step"] = function(t)
    if not has(t) then return end
    local _, c, a = start()
    c.slashes[ns.id.slash]("follow bob")
    settle(c)
    c.setUnitPosition("party2", nil)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    settle(c)
    settle(c)
    t.eq(a.heading(), PIN)
    local n = 0
    for _, line in ipairs(c.printed) do
        if line:find("not known", 1, true) then n = n + 1 end
    end
    t.eq(n, 1, "said once")
    c.setUnitPosition("party2", MAP, 0.6, 0.6)
    settle(c)
    t.eq(a.heading(), { cont = 1, map = MAP, x = 0.6, y = 0.6 }, "known again: followed again")
end

tests["follow: a member who leaves the group ends it"] = function(t)
    if not has(t) then return end
    local _, c, a = start()
    c.slashes[ns.id.slash]("follow bob")
    settle(c)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    c.setParty({ { unit = "party1", name = "Ann" } })
    settle(c)
    t.ok(said(c, "Bob"), "it is said")
    t.eq(a.heading(), PIN)
    c.setParty({ { unit = "party1", name = "Ann" }, { unit = "party2", name = "Bob" } })
    settle(c)
    t.eq(a.heading(), PIN, "back in the group: not followed again by itself")
end

tests["follow: the arrow menu has a row per party member while in a group"] = function(t)
    if not has(t) then return end
    local k, c, a = start()
    local row
    for _, r in ipairs(a.menu()) do
        if r.key == "follow" then row = r end
    end
    t.ok(type(row) == "table" and type(row.children) == "table", "a follow row with the members")
    if type(row) ~= "table" or type(row.children) ~= "table" then return end
    local keys = {}
    for i, r in ipairs(row.children) do keys[i] = r.key end
    t.eq(keys, { "follow.party1", "follow.party2", "follow.stop" })
    t.eq(ns.ArrowMenu.Action("follow.party2", {}), { follow = "party2" })
    t.eq(ns.ArrowMenu.Action("follow", {}), { open = "follow" })
    k.use("follow").Pick("party2")
    settle(c)
    t.eq(a.heading(), { cont = 1, map = MAP, x = 0.7, y = 0.2 })
    c.setParty({})
    local none = true
    for _, r in ipairs(a.menu()) do
        if r.key == "follow" then none = false end
    end
    t.ok(none, "alone: no follow row")
end

tests["follow: the client read is there and its fake answers"] = function(t)
    local c = ns.make.fakeClient()
    t.ok(type(c.unitPosition) == "function" and type(c.setUnitPosition) == "function", "fake read and setter")
    if type(c.setUnitPosition) ~= "function" then return end
    c.setUnitPosition("party1", MAP, 0.25, 0.75)
    t.eq(c.unitPosition("party1"), { map = MAP, x = 0.25, y = 0.75 })
    t.eq(c.unitPosition("party3"), nil)
    local real = ns.make.client({})
    t.ok(type(real.unitPosition) == "function", "the real client has the read")
    if type(real.unitPosition) == "function" then t.eq(real.unitPosition("party1"), nil, "no game: no answer") end
end

return tests
