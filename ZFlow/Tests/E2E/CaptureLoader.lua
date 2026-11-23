local _, ns = ...

-- The capture loader (Core/Capture.lua, lead sections 187 and 188): a diag
-- capture, what the client wrote to the saved file, put into the fake
-- client, and the whole add-on (ns.offline.addon) started on it. Every
-- capture here is MADE UP, in the real format: no real character, realm,
-- account or chat text. A real capture is read only from a path outside the
-- repo (ZFLOW_CAPTURE) and the test that needs one is skipped, by name, when
-- it is not there. Offline only; not tested in game.

local tests = {}
local Capture = ns.Capture

local function row(...)
    local n = select("#", ...)
    local r = { ok = true, n = n, types = {}, values = {} }
    for i = 1, n do
        local v = select(i, ...)
        r.types[i] = type(v)
        if v ~= nil then r.values["v" .. i] = v end
    end
    return r
end

-- A made-up capture: a Horde warrior in the middle of map 1411.
local function made()
    return {
        format = 1,
        account = {
            layout = { arrowIntroSeen = true },
            diag = {
                starts = 3, count = 2,
                names = { build = "1.16.1 (9999)", names = {
                    GetBuildInfo = "function", UnitClass = "function", UnitHealth = "function",
                    issecretvalue = "function",
                    GetContainerNumSlots = "nil", C_Map = "table",
                    ["C_Map.GetBestMapForUnit"] = "function",
                    ["C_QuestLog.GetNumQuestLogEntries"] = "function",
                } },
                api = { namespaces = { C_Map = { GetBestMapForUnit = "function", GetMapInfo = "function" },
                    C_Bank = false }, globals = {} },
                snaps = {
                    { why = "login", at = 5, reads = { money = 1, position = { map = 1429, x = 0.1, y = 0.1 } },
                      shapes = {} },
                    { why = "settled", at = 13,
                      reads = { money = 123456, bags = { { free = 3, total = 16, family = 0 } },
                          position = { map = 1411, x = 0.5, y = 0.5 }, zone = { cont = 1, zone = 1411 },
                          mapSize = { w = 1000, h = 500 }, predecessorLoaded = false },
                      shapes = {
                          build = row("1.16.1", "9999", "Nov 1 2026", 16001),
                          class = row("Warrior", "WARRIOR", 1),
                          level = row(12),
                          faction = row("Horde", "Horde"),
                          facing = row(0),
                          form = row(0),
                          bestMap = row(1411),
                          health = { ok = true, n = 1, types = { "secret" }, values = {} },
                          questEntries = { ok = false, n = 1, types = { "string" }, values = { v1 = "made-up error" } },
                      } },
                },
                reads = { { at = 13, build = "1.16.1 (9999)",
                    reads = { taxi = { path = "C_TaxiMap.GetAllTaxiNodes", exists = false, ok = false } } } },
            },
        },
        char = { madeUp = true },
    }
end

-- "kind owner" of each problem, sorted: no problem text, which could hold a
-- name from a real capture.
local function problems(addon)
    local out = {}
    for _, p in ipairs(addon.problems:list()) do out[#out + 1] = tostring(p.kind) .. " " .. tostring(p.owner) end
    table.sort(out)
    return out
end

local function has(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

-- Pure ---------------------------------------------------------------------

tests["capture check: only format 1 with an account table is a capture"] = function(t)
    t.eq(Capture.Check(made()), true)
    t.eq({ Capture.Check(nil) }, { nil, "not a table" })
    t.eq({ Capture.Check({ format = 2, account = {} }) }, { nil, "format 2 is not known" })
    t.eq({ Capture.Check({ account = {} }) }, { nil, "format nil is not known" })
    t.eq({ Capture.Check({ format = 1 }) }, { nil, "no account table" })
    t.eq({ Capture.Check({ format = 1, account = {}, char = "x" }) }, { nil, "char is not a table" })
end

tests["capture from saved: a saved file's globals make a capture"] = function(t)
    local a, ch = { diag = {} }, { x = 1 }
    t.eq(Capture.FromSaved({ [ns.id.accountDB] = a, [ns.id.charDB] = ch }), { format = 1, account = a, char = ch })
    t.eq(Capture.FromSaved({ [ns.id.accountDB] = a }), { format = 1, account = a })
    t.eq({ Capture.FromSaved({}) }, { nil, "no account table" })
    t.eq({ Capture.FromSaved(nil) }, { nil, "no account table" })
end

tests["capture newest: the last snapshot, and nil with none"] = function(t)
    t.eq(Capture.Newest(made()).why, "settled")
    t.eq(Capture.Newest({ format = 1, account = {} }), nil)
    t.eq(Capture.Newest({ format = 1, account = { diag = { snaps = {} } } }), nil)
end

-- The fake client ----------------------------------------------------------

tests["capture client: the newest snapshot's reads are the client's answers"] = function(t)
    local c = Capture.Client(made())
    t.eq(c.position(), { map = 1411, x = 0.5, y = 0.5 }, "the newest, not the login one")
    t.eq(c.zone(), { cont = 1, zone = 1411 })
    t.eq(c.mapSize(1411), { w = 1000, h = 500 })
    t.eq(c.mapCont(1411), 1, "the map the player stands on is on the player's continent")
    t.eq(c.money(), 123456)
    t.eq(c.bags(), { { free = 3, total = 16, family = 0 } })
    t.eq(c.class(), "WARRIOR")
    t.eq(c.level(), 12)
    t.eq(c.faction(), "Horde")
    t.eq(c.facing(), 0)
    t.eq(c.form(), 0)
    t.eq(c.addonLoaded(ns.id.predecessor), false)
end

tests["capture client: the names table gives the client's names"] = function(t)
    local c = Capture.Client(made())
    t.eq(c.typeOf("GetBuildInfo"), "function")
    t.eq(c.typeOf("GetContainerNumSlots"), "nil", "recorded as not there")
    t.eq(c.typeOf("C_Map"), "table")
    t.eq(c.typeOf("C_Map.GetBestMapForUnit"), "function")
    t.eq(c.typeOf("C_Map.GetMapInfo"), "function", "a namespace member from diag.api")
    t.eq(c.typeOf("C_Bank"), "nil", "a namespace recorded as not there")
    t.eq(c.typeOf("GetMoney"), "nil", "a name the capture does not have")
end

tests["capture client: a recorded call answers as recorded"] = function(t)
    local c = Capture.Client(made())
    t.eq({ c.raw("GetBuildInfo") }, { true, "1.16.1", "9999", "Nov 1 2026", 16001 })
    t.eq({ c.raw("UnitClass", "player") }, { true, "Warrior", "WARRIOR", 1 })
    t.eq({ c.raw("C_Map.GetBestMapForUnit", "player") }, { true, 1411 })
    t.eq({ c.raw("C_QuestLog.GetNumQuestLogEntries") }, { false, "made-up error" }, "a recorded failure fails")
    local okHealth, health = c.raw("UnitHealth", "player")
    t.ok(okHealth and health ~= nil, "a secret answer: a value is there")
    t.eq({ c.raw("issecretvalue", health) }, { true, true }, "and the client calls it secret")
    t.eq({ c.raw("issecretvalue", 5) }, { true, false }, "a plain value is not secret")
    local cap = made()
    cap.account.diag.names.names.issecretvalue = nil
    t.eq({ Capture.Client(cap).raw("UnitHealth", "player") }, { true }, "no issecretvalue: not known")
    t.eq(select("#", c.raw("C_Map.GetMapInfo", 1411)), 1, "a name with no recorded answer answers nothing")
    t.eq({ c.raw("GetMoney") }, { false, "not a function" })
end

tests["capture client: the saved tables are copies of the capture's"] = function(t)
    local cap = made()
    local c = Capture.Client(cap)
    local db = c.saved(ns.id.accountDB)
    t.eq(db.layout, { arrowIntroSeen = true })
    t.eq(c.saved(ns.id.charDB), { madeUp = true })
    db.layout.arrowIntroSeen = false
    db.diag.snaps[1] = nil
    t.eq(cap.account.layout.arrowIntroSeen, true, "the capture is not changed")
    t.eq(#cap.account.diag.snaps, 2)
    local c2 = Capture.Client({ format = 1, account = {} })
    t.eq(c2.savedExists(ns.id.charDB), false, "no character table: none set")
end

tests["capture client: what the capture does not say stays unknown"] = function(t)
    local c, report = Capture.Client({ format = 1, account = {} })
    t.eq(c.position(), nil)
    t.eq(c.zone(), nil)
    t.eq(c.class(), nil)
    t.eq(c.level(), nil)
    t.eq(c.money(), nil)
    t.eq(c.typeOf("GetBuildInfo"), "nil")
    t.eq(report.set, {})
    t.ok(has(report.unknown, "position") and has(report.unknown, "class"), "said as unknown")
end

tests["capture client: a secret or wrong-kind value is left unknown"] = function(t)
    local cap = made()
    local snap = cap.account.diag.snaps[2]
    snap.shapes.level = { ok = true, n = 1, types = { "secret" }, values = {} }
    snap.shapes.class = { ok = false, n = 1, types = { "string" }, values = { v1 = "made-up error" } }
    snap.reads.position = { map = "x", x = 0.5, y = 0.5 }
    snap.reads.money = "lots"
    local c, report = Capture.Client(cap)
    t.eq(c.level(), nil, "secret")
    t.eq(c.class(), nil, "the read failed")
    t.eq(c.position(), nil, "map not a number")
    t.eq(c.money(), nil)
    t.ok(has(report.unknown, "level") and has(report.unknown, "position"), "said as unknown")
    t.ok(has(report.set, "zone") and has(report.set, "faction"), "the rest still set")
end

tests["capture client: a capture that is not one gives no client"] = function(t)
    t.eq({ Capture.Client({ format = 9, account = {} }) }, { nil, "format 9 is not known" })
end

-- End to end ---------------------------------------------------------------

-- The add-on on the client the capture gives, or (no capture) on a bare
-- fake client: the problems the bare one records are not the capture's.
local function boot(cap)
    local c = cap and Capture.Client(cap) or ns.make.fakeClient()
    if not cap then c.setSaved(ns.id.accountDB, {}) end
    c.setScreen(1024, 768)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

tests["capture e2e: the whole add-on starts on a made-up capture with no problem"] = function(t)
    local c, addon = boot(made())
    local _, bare = boot(nil)
    t.eq(problems(addon), problems(bare), "the capture adds no problem")
    t.eq(addon.phase, "running")
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    c.slashes[ns.id.slash]("diag")
    t.ok(#c.printed > 0, "the diag word answers")
end

tests["capture e2e: the add-on's own diag reads the capture's answers back"] = function(t)
    local cap = made()
    local c = boot(cap)
    local d = c.saved(ns.id.accountDB).diag
    t.eq(d.names.build, "1.16.1 (9999)", "the build key, from the recorded GetBuildInfo")
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for name, kind in pairs(cap.account.diag.names.names) do
        if listed[name] then t.eq(d.names.names[name], kind, name) end
    end
    t.eq(d.api.namespaces.C_Map, { GetBestMapForUnit = "function", GetMapInfo = "function" })
    t.ok(#d.snaps > 2, "new snapshots after the captured ones")
    local newest = d.snaps[#d.snaps]
    t.eq(newest.reads.position, { map = 1411, x = 0.5, y = 0.5 })
    t.eq(newest.shapes.class.values, { v1 = "Warrior", v2 = "WARRIOR", v3 = 1 })
    t.eq(newest.shapes.health.types, { "secret" }, "a secret stays secret")
end

-- A real capture, from outside the repo --------------------------------------

tests["capture real: a real capture loads with no problem (skipped when none is given)"] = function(t)
    local path = ns.offline.capturePath()
    if not path then
        t.skip("no real capture: set ZFLOW_CAPTURE to a saved file outside the repo")
        return
    end
    t.ok(not ns.offline.inRepo(path), "a real capture is never inside the repo")
    if ns.offline.inRepo(path) then return end
    local vars, err = ns.offline.readSaved(path, ns.offline.captureCharPath())
    -- Not the error text: a load error quotes the file, and could quote a name.
    t.ok(vars ~= nil and err == nil, "the saved file reads")
    if not vars then return end
    local cap, why = Capture.FromSaved(vars)
    t.ok(cap ~= nil and Capture.Check(cap) == true, "a capture: " .. tostring(why))
    if not cap then return end
    local _, addon = boot(cap)
    local _, bare = boot(nil)
    t.eq(problems(addon), problems(bare), "the capture adds no problem")
end

return tests
