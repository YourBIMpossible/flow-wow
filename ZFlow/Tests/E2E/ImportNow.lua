local _, ns = ...
-- A10: the import word's "now", on the whole add-on loaded on a fake
-- client. Every Flow table below is made up. Offline: the saved tables are
-- the fake client's. Not tested in game.
local tests = {}

local A = ns.Import.Apply
local T = ns.id.title .. ": "
local FLOW = ns.id.predecessor
local WORD = ns.id.slash .. " import now"

local function flowDb()
    return {
        sell = { autoJunk = true, autoRepair = true, autoAll = false },
        ah = { chartClick = true },
        buffButton = { enabled = true, dock = false, scale = 1.1 },
        rotation = { scale = 1.2 },
    }
end

-- flow: the earlier add-on's table, there before this add-on loads (so the
-- load is paused, as in the game). own: this add-on's account table.
local function start(flow, own)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, own or {})
    c.setSaved(ns.id.charDB, {})
    if flow then c.setSaved(ns.id.predecessorDB, flow) end
    c.setClass("MAGE")
    c.setLevel(20)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local copy = ns.make.deepCopy

tests["import now: the dry run still writes nothing, and names the word"] = function(t)
    local c = start(flowDb())
    local own0, char0 = copy(c.saved(ns.id.accountDB)), copy(c.saved(ns.id.charDB))
    local lines = said(c, "import")
    local expected = ns.Diag.ImportReport(ns.Import.FromFlow(flowDb(), nil))
    t.eq(#lines, #expected + 1)
    t.eq(lines[1], T .. expected[1])
    t.eq(lines[#lines], T .. "to copy it in, type " .. WORD .. ".")
    t.eq(c.saved(ns.id.accountDB), own0)
    t.eq(c.saved(ns.id.charDB), char0)
end

tests["import now: the values land, vendor automations stay off, and the line says so"] = function(t)
    local c = start(flowDb())
    local account = c.saved(ns.id.accountDB)
    local expectedAccount, _, report = ns.Import.Merge(copy(account), copy(c.saved(ns.id.charDB)),
        ns.Import.FromFlow(flowDb(), nil), nil, {})
    t.ok(report.ok and report.counts.added > 0, "the fixture did not reach the merge")
    t.eq(#report.vendorLeftOff, 2, "the fixture has two automations on")
    local lines = said(c, "import now")
    t.eq(lines, { T .. "copied 8 saved values from " .. FLOW .. "; "
        .. report.counts.kept .. " of your own were kept. 2 vendor automation(s) " .. FLOW
        .. " had on stay off here; turn them on in the options if you want them. Now turn "
        .. FLOW .. " off and reload." })
    t.ok(c.saved(ns.id.accountDB) == account, "the saved table is the same table")
    t.eq(account, expectedAccount, "what was saved is what the merge gave")
    t.ok(math.abs(ns.Import.Stored.RotationScale(account.layout) - 1.2) < 1e-9, "the size Flow had is read back")
    local sell = account.settings.sell or {}
    t.ok(sell.autoJunk ~= true and sell.autoRepair ~= true, "no vendor automation was switched on")
    t.eq(#account.imports, 1)
    t.eq(c.saved(ns.id.predecessorDB), flowDb(), "the earlier add-on's table is as it was")
end

tests["import now: a choice the player already made is kept"] = function(t)
    local c = start(flowDb(), { schema = 1, layout = { rotation = { scale = 0.7 } } })
    said(c, "import now")
    t.eq(c.saved(ns.id.accountDB).layout.rotation.scale, 0.7)
end

tests["import now: typed again it copies nothing new and keeps one record"] = function(t)
    local c = start(flowDb())
    said(c, "import now")
    local after = copy(c.saved(ns.id.accountDB))
    local lines = said(c, "import now")
    t.ok(lines[1]:find(T .. "everything " .. FLOW .. " had is already here; nothing new was copied.", 1, true) == 1,
        lines[1])
    local again = copy(c.saved(ns.id.accountDB))
    t.eq(#again.imports, 1)
    after.imports, again.imports = nil, nil
    t.eq(again, after)
end

tests["import now: with no earlier data a line says what to do, and nothing is made"] = function(t)
    local c = start(nil)
    local own0 = copy(c.saved(ns.id.accountDB))
    t.eq(said(c, "import now"), { T .. "no " .. FLOW .. " data is loaded. Turn " .. FLOW
        .. " on beside this add-on, reload, then type " .. WORD .. "." })
    t.eq(c.saved(ns.id.accountDB), own0)
    t.eq(c.savedExists(ns.id.predecessorDB), false)
    t.eq(#said(c, "import"), 1, "the dry run adds no hint when there is nothing to copy")
end

tests["import now: saved data the importer cannot merge into is left alone"] = function(t)
    local c = start(flowDb(), { schema = 99, mine = true })
    local own0 = copy(c.saved(ns.id.accountDB))
    local lines = said(c, "import now")
    t.ok(lines[1]:find(T .. "nothing was copied: ", 1, true) == 1, lines[1])
    t.eq(c.saved(ns.id.accountDB), own0)
end

tests["import now: Sync changes a table in place and removes what is gone"] = function(t)
    local inner = { a = 1, gone = true }
    local live = { inner = inner, list = { 1, 2, 3 }, x = "old" }
    t.eq(A.Sync(live, { inner = { a = 1, b = 2 }, list = { 1 }, x = { y = 1 }, empty = {} }), 5)
    t.eq(live.empty, {})
    live.empty = nil
    t.ok(live.inner == inner, "the inner table is kept")
    t.eq(live, { inner = { a = 1, b = 2 }, list = { 1 }, x = { y = 1 } })
end

tests["import now: the help says it"] = function(t)
    local _, addon = start(nil)
    t.ok(addon.diag.help.import:find(A.HELP, 1, true) ~= nil, addon.diag.help.import)
end

return tests
