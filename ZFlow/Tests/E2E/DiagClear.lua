local _, ns = ...
-- Core/Diag.lua's one word with no end-to-end test, through its real
-- entry on the whole add-on loaded on a fake client: /zflow diag keeps a
-- snapshot in the account data, /zflow diag clear forgets every snapshot
-- and says so, and a word the slash command does not know says what it
-- can do. Not tested in game.
local tests = {}

local function boot(account)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local CLEARED = ns.id.title .. ": diagnostics cleared."

tests["diag clear: a snapshot is kept, then clear forgets it and says so"] = function(t)
    local c = boot()
    said(c, "diag")
    t.eq(type(c.saved(ns.id.accountDB).diag), "table", "the snapshot is kept")
    t.eq(said(c, "diag clear"), { CLEARED })
    t.eq(c.saved(ns.id.accountDB).diag, nil, "every snapshot forgotten")
end

tests["diag clear: run together as one word it still clears"] = function(t)
    local c = boot()
    said(c, "diag")
    t.eq(said(c, "diagclear"), { CLEARED })
    t.eq(c.saved(ns.id.accountDB).diag, nil)
end

tests["diag clear: saved diagnostics that are not a table are cleared too"] = function(t)
    local c = boot({ diag = "not a table" })
    t.eq(said(c, "diag clear"), { CLEARED })
    t.eq(c.saved(ns.id.accountDB).diag, nil)
end

tests["diag clear: a word the slash command does not know says what it can do"] = function(t)
    local c = boot()
    t.eq(said(c, "nosuchword"), { ns.id.title .. ": running. Type " .. ns.id.slash .. " help for every command, "
        .. ns.id.slash .. " diag for a diagnostic snapshot, or "
        .. ns.id.slash .. " import to see what an import would do." })
end

return tests
