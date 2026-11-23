local _, ns = ...

-- The capture, feature by feature (lead section 191), and the loader's
-- header and runner repairs from MyBuddy's review (lead section 192,
-- L1-L3). Over the whole add-on (ns.offline.addon) on the fake client a
-- capture gives. Every capture here is MADE UP; a real one is read only
-- from ZFLOW_CAPTURE outside the repo, and its test is skipped by name
-- when none is given. Failures say counts, never a line or a value: a line
-- could hold a name from a real capture. Offline only; not tested in game.

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

-- A made-up capture: a level 12 Horde paladin facing north in the middle of
-- map 1411, on continent 1.
local function made()
    return {
        format = 1,
        account = {
            layout = { arrowIntroSeen = true },
            diag = {
                names = { build = "1.16.1 (9999)", names = { GetBuildInfo = "function", UnitClass = "function" } },
                snaps = { {
                    why = "settled", at = 13,
                    reads = { money = 5000, position = { map = 1411, x = 0.5, y = 0.5 }, zone = { cont = 1, zone = 1411 },
                        mapSize = { w = 1000, h = 500 } },
                    shapes = {
                        build = row("1.16.1", "9999", "Nov 1 2026", 16001),
                        class = row("Paladin", "PALADIN", 2),
                        level = row(12),
                        faction = row("Horde", "Horde"),
                        facing = row(0),
                        form = row(0),
                    },
                } },
            },
        },
    }
end

local function boot(cap)
    local c, report = Capture.Client(cap)
    c.setScreen(1024, 768)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon, report
end

-- L2: the timing fields --------------------------------------------------------

tests["capture timing: every timing field the diag writes is in Capture.TIMING"] = function(t)
    t.ok(type(Capture.TIMING) == "table" and type(Capture.TIMING_MARK) == "table", "the lists are there")
    if type(Capture.TIMING) ~= "table" or type(Capture.TIMING_MARK) ~= "table" then return end
    local c = boot(made())
    local snaps = c.saved(ns.id.accountDB).diag.snaps
    local timing = snaps[#snaps].timing
    local listed, marks = {}, {}
    for _, name in ipairs(Capture.TIMING) do listed[name] = true end
    for _, name in ipairs(Capture.TIMING_MARK) do marks[name] = true end
    local events = {}
    for _, event in ipairs(timing.order) do events[event] = true end
    t.ok(next(events) ~= nil, "some event was marked")
    local stray, strayMark = 0, 0
    for key, value in pairs(timing) do
        if events[key] or key == "fileLoad" then
            for field in pairs(value) do
                if not marks[field] then strayMark = strayMark + 1 end
            end
        elseif not listed[key] then
            stray = stray + 1
        end
    end
    t.eq(stray, 0, "timing fields not in Capture.TIMING")
    t.eq(strayMark, 0, "mark fields not in Capture.TIMING_MARK")
end

-- L1: no guild, account, chat or mail text ------------------------------------

tests["capture text: the loader and the sanitizer schema agree no guild, account, chat or mail text is saved"] = function(t)
    t.eq(Capture.NO_TEXT, { "account", "chat", "guild", "mail" })
    local schema = type(ns.offline.schema) == "function" and ns.offline.schema() or nil
    t.ok(type(schema) == "table", "the sanitizer schema reads")
    if type(schema) ~= "table" then return end
    local found, seen = 0, {}
    local kinds = {}
    for _, kind in ipairs(Capture.NO_TEXT or {}) do kinds[kind] = true end
    local function walk(v)
        if type(v) == "string" then
            if kinds[v] then found = found + 1 end
        elseif type(v) == "table" and not seen[v] then
            seen[v] = true
            -- Values only: a field may be named "account"; a kind is a value.
            for _, value in pairs(v) do walk(value) end
        end
    end
    walk(schema)
    t.eq(found, 0, "schema fields of a kind the loader says is never saved")
end

-- L3: a saved file is parsed, never run -----------------------------------------

tests["capture read: a saved file is parsed, not run"] = function(t)
    t.ok(type(ns.offline.parseSaved) == "function", "the runner parses saved files")
    if type(ns.offline.parseSaved) ~= "function" then return end
    t.eq(ns.offline.parseSaved('ZFlowDB = { ["a"] = 1, list = { "x", true } }\nZFlowCharDB = nil\n'),
        { ZFlowDB = { a = 1, list = { "x", true } } })
    local ran = false
    ns.offline.capturedRan = function() ran = true return 5 end
    local vars, why = ns.offline.parseSaved("ZFlowDB = { n = (function() return 5 end)() }")
    t.eq({ vars, why }, { nil, "not saved-variables data" }, "a function in it is refused")
    t.eq({ ns.offline.parseSaved("ZFlowDB = ns.offline.capturedRan()") }, { nil, "not saved-variables data" })
    t.eq(ran, false, "nothing in the file ran")
    ns.offline.capturedRan = nil
    t.eq({ ns.offline.parseSaved("ZFlowDB = {}\nZFlowDB = {}") }, { nil, "a global given twice" })
end

-- Section 191: each feature on the capture ---------------------------------------

tests["capture unknowns: a line saying unknown counts only for a read the capture answers"] = function(t)
    local lines = { "Flow: not known where you are", "facing unknown", "form not read: the row for no form is used.",
        "all fine" }
    t.eq(Capture.Unknowns(lines, { set = { "position", "facing", "form" } }), 3)
    t.eq(Capture.Unknowns(lines, { set = { "facing" } }), 1)
    t.eq(Capture.Unknowns(lines, { set = {} }), 0)
    t.eq(Capture.Unknowns({}, { set = { "position" } }), 0)
end

-- What each feature shows, as lines: what chat said for its words, and the
-- lines of the arrows and panels shown after them. Problems added while it
-- ran are counted.
local function runFeature(c, addon, feature)
    local before = 0
    for _, p in ipairs(addon.problems:list()) do before = before + (p.count or 1) end
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    for _, words in ipairs(feature.words) do c.slashes[ns.id.slash](words) end
    c.advance(2, 8)
    local lines = {}
    for _, line in ipairs(c.printed) do lines[#lines + 1] = line end
    for _, a in ipairs(c.arrows or {}) do
        if a.shown then for _, line in ipairs(a.lines or {}) do lines[#lines + 1] = line end end
    end
    for _, p in ipairs(c.panels or {}) do
        if p.shown then for _, line in ipairs(p.lines or {}) do lines[#lines + 1] = tostring(line) end end
    end
    local after = 0
    for _, p in ipairs(addon.problems:list()) do after = after + (p.count or 1) end
    return lines, after - before
end

local function checkFeatures(t, cap)
    local c, addon, report = boot(cap)
    for _, feature in ipairs(Capture.FEATURES) do
        local lines, added = runFeature(c, addon, feature)
        t.ok(#lines > 0, feature.name .. ": it said something")
        t.eq(added, 0, feature.name .. ": Lua problems while it ran (count)")
        t.eq(Capture.Unknowns(lines, report), 0, feature.name .. ": lines saying unknown for a read the capture answers (count)")
    end
end

tests["capture features: rotation, arrow, flights, banker and settings on a made-up capture"] = function(t)
    t.eq(#Capture.FEATURES, 5)
    local names = {}
    for _, f in ipairs(Capture.FEATURES) do names[#names + 1] = f.name end
    t.eq(names, { "rotation", "arrow", "flights", "banker", "settings" })
    checkFeatures(t, made())
end

tests["capture real features: each feature on a real capture (skipped when none is given)"] = function(t)
    local path = ns.offline.capturePath()
    if not path then
        t.skip("no real capture: set ZFLOW_CAPTURE to a saved file outside the repo")
        return
    end
    t.ok(not ns.offline.inRepo(path), "a real capture is never inside the repo")
    if ns.offline.inRepo(path) then return end
    local vars = ns.offline.readSaved(path, ns.offline.captureCharPath())
    t.ok(vars ~= nil, "the saved file reads")
    if not vars then return end
    local cap = Capture.FromSaved(vars)
    t.ok(cap ~= nil, "a capture")
    if not cap then return end
    checkFeatures(t, cap)
end

return tests
