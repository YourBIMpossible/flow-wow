local _, ns = ...

-- The name-free summary of a capture's feature run (lead section 196):
-- per feature, whether its words ran, the problems and unknowns counted,
-- and each line it showed with only the add-on's own words and numbers
-- printed (lead section 199, MyBuddy's review: S1-S4). White writes it from
-- the real capture to ZFLOW_SUMMARY, outside the repo.
-- Every capture and name here is MADE UP. Offline only; not tested in game.

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

-- A made-up capture holding made-up names where the game puts real ones.
local function made()
    return {
        format = 1,
        account = {
            layout = { arrowIntroSeen = true },
            learned = { prices = { auctionHistory = { ["Moss Vale-Horde"] = { [2589] = { h = { 1700000000, 30 } } } } } },
            diag = {
                names = { build = "1.16.1 (9999)", names = { GetBuildInfo = "function", UnitClass = "function" } },
                snaps = { {
                    why = "settled", at = 13,
                    timing = { order = {}, character = "Aldwynne", realm = "Moss Vale" },
                    reads = { money = 5000, position = { map = 1411, x = 0.5, y = 0.5 }, zone = { cont = 1, zone = 1411 },
                        mapSize = { w = 1000, h = 500 } },
                    shapes = {
                        build = row("1.16.1", "9999", "Nov 1 2026", 16001),
                        class = row("Paladin", "PALADIN", 2),
                        level = row(12),
                        faction = row("Horde", "Horde"),
                        facing = row(0),
                        form = row(0),
                        realm = row("Moss Vale"),
                        fullName = row("Aldwynne", "MossVale"),
                    },
                } },
            },
        },
    }
end

-- Names ---------------------------------------------------------------------

tests["capture names: the names a capture holds, in every spelling"] = function(t)
    local names = Capture.Names(made())
    local have = {}
    for _, n in ipairs(names) do have[n] = true end
    t.ok(have.Aldwynne, "the character")
    t.ok(have["Moss Vale"] and have.MossVale and have["Moss-Vale"], "the realm, with and without its space")
    t.eq(have[ns.id.title], nil, "not the add-on's own title")
    for i = 2, #names do
        t.ok(#names[i - 1] >= #names[i], "longest first")
    end
    t.eq(Capture.Names({ format = 1, account = {} }), {})
end

-- Masking: only the add-on's own words and numbers are printed ---------------
-- S1: lower-case free text (a typed waypoint label) was kept. Now a word is
-- printed only when the add-on's own source has it; every other word is
-- counted, not printed.

local OWN = { auction = true, prices = true, ["for"] = true, item = true, s = true, on = true, from = true,
    search = true, es = true, way = true, meet = true, here = true, sell = true, says = true, build = true,
    talk = true, to = true, ["then"] = true }

tests["capture mask: only the add-on's own words and numbers are printed; the rest is counted"] = function(t)
    local title = ns.id.title .. ": "
    local names = { "Moss Vale", "MossVale", "Aldwynne" }
    t.eq({ Capture.Mask(title .. "auction: prices for 12 item(s) on Moss Vale-Horde, from 3 search(es)", names, OWN) },
        { title .. "auction: prices for # item(s) on _-_, from # search(es)", 2 })
    t.eq({ Capture.Mask("way: meet fenwick here", {}, OWN) }, { "way: meet _ here", 1 },
        "S1: a lower-case word typed by the player is not printed")
    t.eq({ Capture.Mask("met aldwynne at 3:15", names, OWN) }, { "_ _ _ #:#", 3 }, "a known name, and words not own")
    t.eq({ Capture.Mask("Then: Talk to Brannoch", {}, OWN) }, { "Then: Talk to _", 1 }, "own words in any case")
    t.eq({ Capture.Mask("sell [Linen Cloth] x4", {}, OWN) }, { "sell [_] _#", 2 })
    t.eq({ Capture.Mask("|cffff0000Kestrelle|r says", {}, OWN) }, { "_ says", 1 }, "colour codes dropped")
    t.eq({ Capture.Mask("from zo\195\171 here", {}, OWN) }, { "from _ here", 1 }, "a byte past ASCII")
    t.eq({ Capture.Mask("build 1.16.1", {}, OWN) }, { "build #.#.#", 0 })
    t.eq({ Capture.Mask(42, {}, OWN) }, { "#", 0 }, "not text: said as text")
    t.eq({ Capture.Mask("way here", {}, nil) }, { "_ _", 2 }, "no word list: nothing printed")
end

tests["capture own words: the add-on's own source gives the word list"] = function(t)
    local own = ns.offline.ownWords()
    t.ok(type(own) == "table", "a word list")
    if type(own) ~= "table" then return end
    t.ok(own.waypoint and own.auction and own.prices, "words the add-on says")
    t.eq(own.fenwick, nil, "not a made-up name")
    t.eq(own.aldwynne, nil)
end

-- Settings: S2, a text value was shown --------------------------------------------

local function boot(cap)
    local c, report = Capture.Client(cap)
    c.setScreen(1024, 768)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon, report
end

tests["capture settings: each row is its key and kind; a value only when it is a declared choice"] = function(t)
    local _, addon = boot(made())
    local rows = {
        { key = "made.text", type = "string" }, { key = "made.pick", type = "choice", choices = { "low", "high" } },
        { key = "made.odd", type = "choice", choices = { "low", "high" } }, { key = "made.flag", type = "bool" },
        { key = "made.count", type = "number" },
    }
    local values = { ["made.text"] = "meet fenwick", ["made.pick"] = "high", ["made.odd"] = "fenwick",
        ["made.flag"] = true, ["made.count"] = 7 }
    local fake = {
        each = function()
            local i = 0
            return function() i = i + 1 return rows[i] end
        end,
        get = function(_, key) return values[key] end,
    }
    t.eq(Capture.SettingsLines(fake), {
        "setting made.text: text", "setting made.pick: choice = high", "setting made.odd: choice",
        "setting made.flag: on or off = true", "setting made.count: number",
    })
    t.ok(#Capture.SettingsLines(addon.settings) > 0, "the add-on's own rows")
end

-- The summary -----------------------------------------------------------------

tests["capture summary: one row per feature, counts and masked lines"] = function(t)
    local cap = made()
    local c, addon, report = boot(cap)
    local rows = Capture.Summarize(c, addon, report, cap, ns.offline.ownWords())
    t.eq(#rows, #Capture.FEATURES)
    for i, r in ipairs(rows) do
        t.eq(r.feature, Capture.FEATURES[i].name)
        t.eq(r.ran, true, r.feature .. " ran")
        t.eq(r.problems, 0, r.feature .. " problems")
        t.eq(r.unknowns, 0, r.feature .. " unknowns")
        t.ok(#r.lines > 0, r.feature .. " said something")
    end
    local text = Capture.SummaryText(rows)
    t.ok(text:find("\nfeature rotation: words ran yes, problems 0, unknown 0, hidden ", 1, true) ~= nil,
        "the rotation row")
    t.eq(text:find(Capture.SUMMARY_HEAD, 1, true), 1, "it starts with its heading")
    local digits = 0
    for _, r in ipairs(rows) do
        for _, line in ipairs(r.lines) do
            if line:find("%d") then digits = digits + 1 end
        end
    end
    t.eq(digits, 0, "lines with a digit left in them")
end

-- Lead section 206: the verdict is CaptureEvidence's. Rotation on this
-- made-up capture runs with no Lua problem but has no target, no known
-- spells and the setting off: that is "not exercised", never a pass.
tests["capture summary: a feature that only ran clean is not a pass"] = function(t)
    local cap = made()
    local c, addon, report = boot(cap)
    local rows = Capture.Summarize(c, addon, report, cap, ns.offline.ownWords())
    local rotation = rows[1]
    t.eq({ rotation.feature, rotation.ran, rotation.problems }, { "rotation", true, 0 }, "it ran clean")
    t.ok(type(rotation.verdict) == "table", "it has a verdict")
    if type(rotation.verdict) ~= "table" then return end
    t.eq(rotation.verdict.result, ns.CaptureEvidence.NOT_EXERCISED, "ran clean, not verified")
    t.eq(rotation.verdict.verified, false)
    local text = Capture.SummaryText(rows)
    t.ok(text:find("\nrotation: NOT exercised; missing ", 1, true) ~= nil, "the summary says so")
    t.eq(text:find("\nrotation: verified", 1, true), nil, "and never calls it verified")
    for _, line in ipairs(ns.CaptureEvidence.Text({ rotation.verdict })) do
        t.ok(text:find(line, 1, true) ~= nil, "the evidence line, as CaptureEvidence words it")
    end
    local n = ns.CaptureEvidence.Count((function()
        local v = {}
        for _, r in ipairs(rows) do v[#v + 1] = r.verdict end
        return v
    end)())
    t.ok(text:find(("not exercised %d"):format(n.notExercised), 1, true) ~= nil, "the count of runs not exercised")
end

tests["capture summary: a row with no verdict is said to be not verified"] = function(t)
    local text = Capture.SummaryText({ { feature = "made", ran = true, problems = 0, unknowns = 0, hidden = 0, lines = {} } })
    t.ok(text:find("\nmade: no verdict; not verified", 1, true) ~= nil, text)
end

-- S4: the name-absent check could not fail, since no name was ever shown. A
-- name is planted where the player sees it (a waypoint label), the raw lines
-- are checked to hold it, and only then the summary to leave it out.
tests["capture summary: a planted name the player sees is not in the summary"] = function(t)
    local cap = made()
    local c, addon, report = boot(cap)
    local plant = { name = "way", words = { "way 45 60 meet Fenwick and aldwynne here" } }
    local raw = table.concat((Capture.RunFeature(c, addon, plant)), "\n")
    t.ok(raw:find("Fenwick", 1, true) and raw:find("aldwynne", 1, true), "the planted names are shown to the player")
    local features = { plant, { name = "arrow", words = { "arrow why" } } }
    local rows = Capture.Summarize(c, addon, report, cap, ns.offline.ownWords(), features)
    local text = Capture.SummaryText(rows):lower()
    for _, name in ipairs({ "fenwick", "aldwynne", "moss vale", "mossvale", "moss-vale" }) do
        t.eq(text:find(name, 1, true), nil, "no planted or held name in the summary: " .. name:sub(1, 1))
    end
    t.ok(rows[1].hidden > 0, "the words left out are counted")
    t.ok(Capture.SummaryText(rows):find("hidden " .. rows[1].hidden, 1, true) ~= nil, "and the count is said")
end

tests["capture summary: a word that raises is ran no"] = function(t)
    local rows = Capture.Summarize({ slashes = { [ns.id.slash] = function() error("made-up boom") end },
        printed = {}, advance = function() end }, { problems = { list = function() return {} end } },
        { set = {} }, {}, {})
    t.eq(rows[1].ran, false)
    t.eq(Capture.SummaryText({ rows[1] }):find("ran no", 1, true) ~= nil, true)
    t.eq(Capture.SummaryText({ rows[1] }):find("boom", 1, true), nil, "the error text is not in it")
end

-- Writing it: S3, never over a saved file ------------------------------------------

tests["capture summary file: never inside the repo, a game folder, over an input or an existing file"] = function(t)
    t.eq({ ns.offline.writeSummary("summary.txt", "x") }, { nil, "inside the repo" }, "a relative path")
    t.eq({ ns.offline.writeSummary(nil, "x") }, { nil, "no path given" })
    t.eq({ ns.offline.writeSummary("C:/Games/World of Warcraft/_classic_/WTF/Account/X/summary.txt", "x") },
        { nil, "inside a game folder" })
    t.eq({ ns.offline.writeSummary("D:\\Wow\\Interface\\AddOns\\ZFlow\\summary.txt", "x") },
        { nil, "inside a game folder" })
    t.eq({ ns.offline.writeSummary("D:/x/SavedVariables/out.txt", "x") }, { nil, "inside a game folder" })
    t.eq({ ns.offline.writeSummary("D:/made/up/ZFlow.lua", "x", { "d:\\made\\up\\zflow.lua" }) },
        { nil, "the same file as an input" })
    local dir = os.getenv("TEMP") or os.getenv("TMPDIR") or os.getenv("TMP")
    if not dir or ns.offline.inRepo(dir) then
        t.skip("no temp folder to make an existing file in")
        return
    end
    local path = dir .. "/zflow-summary-exists-" .. tostring(os.time()) .. ".txt"
    local fh = io.open(path, "wb")
    t.ok(fh ~= nil, "a made-up file to stand in for one that is there")
    if not fh then return end
    fh:write("made up")
    fh:close()
    t.eq({ ns.offline.writeSummary(path, "x") }, { nil, "the file is already there" })
    local back = io.open(path, "rb")
    t.eq(back and back:read("*a"), "made up", "it was not written over")
    if back then back:close() end
    os.remove(path)
end

tests["capture real summary: the real run's summary goes to ZFLOW_SUMMARY (skipped without both)"] = function(t)
    local path, out = ns.offline.capturePath(), ns.offline.summaryPath()
    if not path or not out then
        t.skip("no real capture or no summary path: set ZFLOW_CAPTURE and ZFLOW_SUMMARY, both outside the repo")
        return
    end
    t.ok(not ns.offline.inRepo(path) and not ns.offline.inRepo(out), "both are outside the repo")
    if ns.offline.inRepo(path) or ns.offline.inRepo(out) then return end
    local charPath = ns.offline.captureCharPath()
    local vars = ns.offline.readSaved(path, charPath)
    local cap = vars and Capture.FromSaved(vars)
    t.ok(cap ~= nil, "a capture")
    if not cap then return end
    local c, addon, report = boot(cap)
    local text = Capture.SummaryText(Capture.Summarize(c, addon, report, cap, ns.offline.ownWords()))
    local ok, why = ns.offline.writeSummary(out, text, { path, charPath })
    t.eq({ ok, why }, { true }, "the summary is written")
end

return tests
