local _, ns = ...
-- Core/Store.lua and Core/Diag.lua through their real entry, on the whole
-- add-on loaded on a fake client, twice: the second login starts from a
-- copy of what the first one saved, as a reload does. The start count goes
-- up by one, the snapshots /zflow diag kept in the first session are still
-- there, and the look-only tracking record of the first login is kept with
-- the second one's after it. Made-up saved values. Not tested in game.
local tests = {}

local function boot(account, char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, char)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(6, 24)
    return c, addon
end

-- A first session that took one snapshot, then a second login started from
-- a copy of its saved tables.
local function twoLogins()
    local first = boot({}, {})
    first.slashes[ns.id.slash]("diag")
    local copy = ns.make.deepCopy
    local a1, c1 = copy(first.saved(ns.id.accountDB)), copy(first.saved(ns.id.charDB))
    local second = boot(copy(a1), copy(c1))
    return a1, second
end

local function logins(list)
    local n = 0
    for _, rec in ipairs(type(list) == "table" and list or {}) do
        if rec.why == "login" then n = n + 1 end
    end
    return n
end

tests["saved across logins: the start count goes up by exactly one"] = function(t)
    local a1, second = twoLogins()
    local starts1 = a1.diag and a1.diag.starts
    t.ok(type(starts1) == "number" and starts1 >= 1, "the first session counted its start")
    t.eq(second.saved(ns.id.accountDB).diag.starts, starts1 + 1)
end

tests["saved across logins: a snapshot from the first session is still there after the second login"] = function(t)
    local a1, second = twoLogins()
    local before = a1.diag.snaps
    t.ok(type(before) == "table" and #before >= 1, "the first session kept a snapshot")
    -- `second` already carries the second login's own snapshot (boot()'s
    -- PLAYER_ENTERING_WORLD takes one, same as the first session's); this
    -- diag call adds one more on top of that, so two are new since a1.
    second.slashes[ns.id.slash]("diag")
    local d = second.saved(ns.id.accountDB).diag
    t.eq(d.snaps[1], before[1], "the oldest snapshot is unchanged")
    t.eq(#d.snaps, #before + 2, "the login's own snapshot and the asked one are both added after it")
    t.eq(d.count, a1.diag.count + 2, "the snapshot count goes on from the first session")
end

tests["saved across logins: the first login's tracking record is kept and the second one's is added"] = function(t)
    local a1, second = twoLogins()
    local before = a1.diag.trackingList
    t.eq(logins(before), 1, "the first session saved one login record")
    local after = second.saved(ns.id.accountDB).diag.trackingList
    t.eq(after[1], before[1], "the first record is unchanged")
    t.eq(logins(after), 2, "the second login added its own")
end

tests["saved across logins: the settings section saved in the first session opens unchanged"] = function(t)
    local first = boot({ settings = { e2eMade = "up" } }, {})
    local copy = ns.make.deepCopy
    local second = boot(copy(first.saved(ns.id.accountDB)), copy(first.saved(ns.id.charDB)))
    local db = second.saved(ns.id.accountDB)
    t.eq(db.settings.e2eMade, "up", "a saved setting survives the reload")
    t.eq(db.schema, 1, "the schema number written at the first login stands")
    t.eq(db.recovered, nil, "nothing needed recovering")
end

return tests
