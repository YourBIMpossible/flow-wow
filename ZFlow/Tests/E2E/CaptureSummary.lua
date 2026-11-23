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
        -- A real capture has the character file too.
        char = {},
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
    Talk = true, to = true, Then = true, talk = true, ["then"] = true }

tests["capture mask: only the add-on's own words and numbers are printed; the rest is counted"] = function(t)
    local title = ns.id.title .. ": "
    local names = { "Moss Vale", "MossVale", "Aldwynne" }
    t.eq({ Capture.Mask(title .. "auction: prices for 12 item(s) on Moss Vale-Horde, from 3 search(es)", names, OWN) },
        { title .. "auction: prices for # item(s) on _-_, from # search(es)", 2 })
    t.eq({ Capture.Mask("way: meet fenwick here", {}, OWN) }, { "way: meet _ here", 1 },
        "S1: a lower-case word typed by the player is not printed")
    t.eq({ Capture.Mask("met aldwynne at 3:15", names, OWN) }, { "_ _ _ #:#", 3 }, "a known name, and words not own")
    -- CM-1 (lead sections 237, 238): after a colon is not a sentence's start,
    -- so a capitalised own word there is left out too ("guild: Way" must not
    -- print a name spelt "Way"); at the line's start it prints.
    t.eq({ Capture.Mask("Then: Talk to Brannoch", {}, OWN) }, { "Then: _ to _", 2 },
        "own words as written, capitalised ones only at the start of a sentence")
    t.eq({ Capture.Mask("Talk to Brannoch. Then talk", {}, OWN) }, { "Talk to _. Then talk", 1 },
        "at the line's start and after a full stop they print")
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
    -- The way word echoes "waypoint set: <x>, <y> <label>." The slash command
    -- lower-cases everything typed after it (Core/Diag.lua, the slash), so
    -- the label the player sees is "meet fenwick and aldwynne here" (lead
    -- section 208: the test looked for "Fenwick" and failed on White).
    t.ok(raw:find("waypoint set: ", 1, true) ~= nil, "the way word set the waypoint and said so")
    t.ok(raw:find("fenwick", 1, true) and raw:find("aldwynne", 1, true), "the planted names are shown to the player")
    local features = { plant, { name = "arrow", words = { "arrow why" } } }
    local rows = Capture.Summarize(c, addon, report, cap, ns.offline.ownWords(), features)
    local text = Capture.SummaryText(rows):lower()
    for _, name in ipairs({ "fenwick", "aldwynne", "moss vale", "mossvale", "moss-vale" }) do
        t.eq(text:find(name, 1, true), nil, "no planted or held name in the summary: " .. name:sub(1, 1))
    end
    t.ok(rows[1].hidden > 0, "the words left out are counted")
    t.ok(Capture.SummaryText(rows):find("hidden " .. rows[1].hidden, 1, true) ~= nil, "and the count is said")
end

-- MyBuddy CS-2 (lead section 214): this test said only "ran no"; it now
-- also says the verdict is not a pass.
tests["capture summary: a word that raises is ran no, and not verified"] = function(t)
    local rows = Capture.Summarize({ slashes = { [ns.id.slash] = function() error("made-up boom") end },
        printed = {}, advance = function() end }, { problems = { list = function() return {} end } },
        { set = {} }, {}, {})
    t.eq(rows[1].ran, false)
    t.ok(type(rows[1].verdict) == "table" and rows[1].verdict.verified == false, "not verified")
    t.eq(type(rows[1].verdict) == "table" and rows[1].verdict.result, ns.CaptureEvidence.ERROR,
        "a word that raised is a Lua problem")
    t.eq(Capture.SummaryText({ rows[1] }):find("words ran no", 1, true) ~= nil, true)
    t.eq(Capture.SummaryText({ rows[1] }):find("boom", 1, true), nil, "the error text is not in it")
end

-- MyBuddy CS-1 (lead section 214): RunFeature sets ran = false when a word
-- raises, but the verdict was judged on the lines alone. Settings is proved
-- from the saved settings, not from the lines, so a run whose word raised
-- came out "verified on captured inputs". A raise is now a Lua problem.
tests["capture summary: a feature whose word raised is never verified, even when its proof holds"] = function(t)
    local cap = made()
    cap.account.settings = { items = { priceChart = false } }
    local c, addon, report = boot(cap)
    local word = c.slashes[ns.id.slash]
    c.slashes[ns.id.slash] = function(words)
        word(words)
        error("made-up boom")
    end
    local features = { { name = "settings", words = { "settings" }, fromRows = true } }
    local rows = Capture.Summarize(c, addon, report, cap, ns.offline.ownWords(), features)
    c.slashes[ns.id.slash] = word
    local check = ns.CaptureEvidence.Judge("settings", { cap = cap, report = report, lines = { "x" },
        problems = 0, addon = addon })
    t.eq(check.verified, true, "with no raise the settings proof holds: the test can fail")
    t.eq(rows[1].ran, false)
    t.ok(type(rows[1].verdict) == "table" and rows[1].verdict.verified == false, "a raise: not verified")
    local text = Capture.SummaryText(rows)
    t.ok(text:find("\nsettings: Lua problem while it ran; not verified", 1, true) ~= nil, text)
    t.eq(text:find("\nsettings: verified", 1, true), nil)
end

-- MyBuddy CS-3: one Judge that raises must not stop the whole summary.
tests["capture summary: a verdict that raises leaves that row with no verdict, and the rest go on"] = function(t)
    local cap = made()
    local c, addon, report = boot(cap)
    local judge = ns.CaptureEvidence.Judge
    ns.CaptureEvidence.Judge = function() error("made-up boom") end
    local ok, rows = pcall(Capture.Summarize, c, addon, report, cap, ns.offline.ownWords())
    ns.CaptureEvidence.Judge = judge
    t.ok(ok, "the summary did not stop")
    if not ok then return end
    t.eq(#rows, #Capture.FEATURES, "every feature has its row")
    local text = Capture.SummaryText(rows)
    t.ok(text:find("\nrotation: no verdict; not verified", 1, true) ~= nil, "said not verified")
    t.eq(text:find("boom", 1, true), nil, "the error text is not in it")
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
    -- A made-up file outside the repo stands in for one that is there. The
    -- runner makes, reads and removes it (lead section 208: a test file
    -- names no file or system call itself).
    local path, why = ns.offline.tempFile("made up")
    if not path then
        t.skip("no temp folder to make an existing file in: " .. tostring(why))
        return
    end
    t.eq({ ns.offline.writeSummary(path, "x") }, { nil, "the file is already there" })
    t.eq(ns.offline.readFile(path), "made up", "it was not written over")
    t.eq(ns.offline.removeFile(path), true, "the made-up file is removed")
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
    local text = Capture.SummaryText(Capture.Summarize(c, addon, report, cap, ns.offline.ownWords()), report)
    local ok, why = ns.offline.writeSummary(out, text, { path, charPath })
    t.eq({ ok, why }, { true }, "the summary is written")
end

-- Lead section 220, MyBuddy CS2-1 to CS2-3 on f1aea21, and the older CS-4
-- and CS-5. Every name here is made up.

-- A summary from a stand-in client and add-on, for the guard tests.
local function standIn(word, opts)
    opts = opts or {}
    local c = { slashes = { [ns.id.slash] = word or function() end }, printed = {}, advance = function() end }
    if opts.noPrinted then c.printed = nil end
    local addon = { problems = { list = function() return {} end }, settings = opts.settings }
    return c, addon
end

tests["capture summary CS2-1: a raised word's row says one problem"] = function(t)
    local c, addon = standIn(function() error("made-up boom") end)
    local rows = Capture.Summarize(c, addon, { set = {} }, {}, {})
    t.eq(rows[1].problems, 1, "the raise counts")
    t.ok(Capture.SummaryText({ rows[1] }):find("words ran no, problems 1,", 1, true) ~= nil, "and is said")
end

tests["capture summary CS2-2: a row with no verdict is counted, and the counts add up"] = function(t)
    local rows = {
        { feature = "made", ran = true, problems = 0, unknowns = 0, hidden = 0, lines = {} },
        { feature = "other", ran = true, problems = 0, unknowns = 0, hidden = 0, lines = {},
          verdict = { feature = "other", result = ns.CaptureEvidence.NOT_EXERCISED, missing = { "x" }, synthetic = {},
            smoke = true } },
    }
    local text = Capture.SummaryText(rows)
    t.ok(text:find("not exercised 1, Lua problem 0, no verdict 1, of 2", 1, true) ~= nil, text)
    local none = Capture.SummaryText({ rows[1] })
    t.ok(none:find("no verdict 1, of 1", 1, true) ~= nil, "counted with no verdict at all: " .. none)
end

tests["capture summary CS2-3: a raise in the run, the mask, the settings or the unknowns leaves the rest going"] = function(t)
    local function noBoom(text, why) t.eq(tostring(text):find("boom", 1, true), nil, why .. ": no error text") end
    -- The run itself raises (the client has no printed list).
    local c, addon = standIn(nil, { noPrinted = true })
    local ok, rows = pcall(Capture.Summarize, c, addon, { set = {} }, {}, {})
    t.ok(ok and #rows == #Capture.FEATURES, "the run raised: every row still made")
    if ok then
        t.eq(rows[1].ran, false, "said as not run")
        noBoom(Capture.SummaryText(rows), "run")
    end
    -- The mask raises (a word list that raises when asked).
    c, addon = standIn(function() c.printed[#c.printed + 1] = "made up line" end)
    local own = setmetatable({}, { __index = function() error("made-up boom") end })
    ok, rows = pcall(Capture.Summarize, c, addon, { set = {} }, {}, own)
    t.ok(ok and #rows == #Capture.FEATURES, "the mask raised: every row still made")
    if ok then
        t.eq(rows[1].lines, { "_" }, "the line it could not mask is left out")
        noBoom(Capture.SummaryText(rows), "mask")
    end
    -- The settings rows raise.
    c, addon = standIn(nil, { settings = { each = function() error("made-up boom") end } })
    ok, rows = pcall(Capture.Summarize, c, addon, { set = {} }, {}, {})
    t.ok(ok and #rows == #Capture.FEATURES, "the settings raised: every row still made")
    if ok then
        t.eq(rows[#rows].lines, {}, "no settings lines")
        t.ok(rows[#rows].problems >= 1, "counted as a problem")
    end
    -- The unknowns raise (a report that raises when read).
    c, addon = standIn()
    local report = setmetatable({}, { __index = function() error("made-up boom") end })
    ok, rows = pcall(Capture.Summarize, c, addon, report, {}, {})
    t.ok(ok and #rows == #Capture.FEATURES, "the unknowns raised: every row still made")
    if ok then
        t.ok(rows[1].problems >= 1, "counted as a problem")
        noBoom(Capture.SummaryText(rows), "unknowns")
    end
end

tests["capture summary CS-4: an own word is kept only as the add-on writes it"] = function(t)
    t.eq({ Capture.Mask("Way way WAY", {}, { way = true }) }, { "_ way _", 2 },
        "a name spelt like a lower-case word of the add-on is not printed")
    local own = ns.offline.ownWords()
    t.ok(own.waypoint == true, "the add-on writes waypoint")
    t.eq(own.WAYPOINT, nil, "as written, not in every case")
    -- MyBuddy ZCS3-1: a word the add-on writes only capitalised must be in
    -- the list as written and not in lower case. If the word list were
    -- lower-cased again there would be no such word, and this fails.
    local only = nil
    for word in pairs(own) do
        if word:find("^%u%l") and own[word:lower()] == nil then
            only = word
            break
        end
    end
    t.ok(only ~= nil, "some word is written only capitalised, and kept so")
end

tests["capture summary CS-5: the temp folder is looked for in more places"] = function(t)
    local env, fallback = {}, {}
    for _, name in ipairs(ns.offline.TEMP_ENV or {}) do env[name] = true end
    for _, dir in ipairs(ns.offline.TEMP_FALLBACK or {}) do fallback[dir] = true end
    t.ok(env.TEMP and env.TMP and env.TMPDIR and env.TEMPDIR, "the usual names")
    t.ok(fallback["/tmp"] and fallback["/var/tmp"], "and the usual folders when none is set")
end

-- MyBuddy ZCS3-2 / C3-3: tempFile reads the two lists when it runs. With
-- both empty it finds no folder; with only a fallback that is not there
-- it finds none either. Fails if tempFile stops reading the lists.
tests["capture summary CS-5: tempFile follows the lists it is given"] = function(t)
    -- MyBuddy CS4-2: the lists are put back even when tempFile raises.
    local env, fallback = ns.offline.TEMP_ENV, ns.offline.TEMP_FALLBACK
    local none, missing
    local ok = pcall(function()
        ns.offline.TEMP_ENV, ns.offline.TEMP_FALLBACK = {}, {}
        none = { ns.offline.tempFile("x") }
        ns.offline.TEMP_FALLBACK = { "/zz-made-up-folder-that-is-not-there" }
        missing = { ns.offline.tempFile("x") }
    end)
    ns.offline.TEMP_ENV, ns.offline.TEMP_FALLBACK = env, fallback
    t.ok(ok, "tempFile did not raise")
    t.eq(none, { nil, "no temp folder" }, "no name and no folder: none")
    t.eq(missing, { nil, "the file did not open" }, "a folder that is not there: none")
end

-- MyBuddy C3-1: a word that adds problems before RunFeature raises (here
-- the client's advance) keeps those problems on the row, plus the raise.
tests["capture summary C3-1: problems added before a raise in the run are kept"] = function(t)
    local list = {}
    local addon = { problems = { list = function() return list end } }
    local c = { printed = {}, advance = function() error("made-up boom") end, slashes = {
        [ns.id.slash] = function()
            list[#list + 1] = { kind = "made", owner = "up", count = 1 }
            list[#list + 1] = { kind = "made", owner = "up2", count = 1 }
        end } }
    local rows = Capture.Summarize(c, addon, { set = {} }, {}, {}, { { name = "rotation", words = { "x" } } })
    t.eq(rows[1].ran, false)
    t.eq(rows[1].problems, 3, "two added by the word, one for the raise")
end

-- MyBuddy C3-2 and CS4-1 (lead section 228): own words come from every
-- quoted text of the add-on, data names too. A capitalised own word is
-- printed only when the add-on also writes it in lower case ("Then" and
-- "then"); a name it holds only capitalised is left out wherever it stands:
-- inside a line, at its start, or after ": . ! ?".
tests["capture summary C3-2: a capitalised own word the add-on never writes in lower case is not printed"] = function(t)
    local own = { you = true, met = true, Brannoch = true, here = true, guild = true, Then = true, ["then"] = true }
    t.eq({ Capture.Mask("you met Brannoch here", {}, own) }, { "you met _ here", 1 }, "inside a line")
    t.eq({ Capture.Mask("Brannoch: here", {}, own) }, { "_: here", 1 }, "at the start of a line")
    t.eq({ Capture.Mask("here. Brannoch met you", {}, own) }, { "here. _ met you", 1 }, "after a full stop")
    t.eq({ Capture.Mask("guild: Brannoch", {}, own) }, { "guild: _", 1 }, "CS4-1: after a colon")
    t.eq({ Capture.Mask("Then: you met", {}, own) }, { "Then: you met", 0 },
        "a word the add-on writes in lower case too is printed, so the test can fail the other way")
end

-- MyBuddy CM-1 (lead sections 237, 238): a made-up name spelt like a word
-- the add-on writes both capitalised and in lower case ("Hunter" and
-- "hunter", "Way" and "way") is not printed where it stands inside a line or
-- after a colon. Such a word is printed capitalised only where the add-on's
-- own text would capitalise it: at a line's start, or after ". ! ?" and a
-- blank. A name in that place, spelt like such a word, still prints: the
-- one case the mask cannot tell from the add-on's own sentence.
tests["capture summary CM-1: a capitalised word the add-on also writes in lower case is masked inside a line"] = function(t)
    local own = { you = true, met = true, here = true, guild = true, by = true,
                  Hunter = true, hunter = true, Way = true, way = true, Then = true, ["then"] = true }
    t.eq({ Capture.Mask("you met Hunter here", {}, own) }, { "you met _ here", 1 }, "inside a line")
    t.eq({ Capture.Mask("guild: Way", {}, own) }, { "guild: _", 1 }, "after a colon")
    t.eq({ Capture.Mask("met by Way, here", {}, own) }, { "met by _, here", 1 }, "before a comma")
    t.eq({ Capture.Mask("you met hunter here", {}, own) }, { "you met hunter here", 0 }, "the lower-case word prints")
    t.eq({ Capture.Mask("Then you met", {}, own) }, { "Then you met", 0 }, "at a line's start it prints")
    t.eq({ Capture.Mask("here. Then you met", {}, own) }, { "here. Then you met", 0 }, "after a full stop it prints")
    t.eq({ Capture.Mask("here! Hunter met you", {}, own) }, { "here! Hunter met you", 0 },
        "after ! it prints: the residual case, stated")
    -- With the add-on's real word list: a capitalised "Way" or "Hunter" inside
    -- a line is masked whether or not the list holds the capitalised form.
    local real = ns.offline.ownWords()
    local line, n = Capture.Mask("you met Way here", {}, real)
    t.ok(not line:find("Way", 1, true), "real list: Way is not printed inside a line: " .. line)
    t.ok(n >= 1, "counted as hidden")
    line = Capture.Mask("you met Hunter here", {}, real)
    t.ok(not line:find("Hunter", 1, true), "real list: Hunter is not printed inside a line: " .. line)
end


-- Lead section 225 EB-2, product half (zflow-evidence-ask): a call the
-- capture does not hold is asked, and the product says so. Capture.Env
-- counts each ask of a Capture.CALLS name the replay does not hold, by API
-- name only: a look-up of a name the capture lacks (it stays absent, unknown
-- stays unknown), a call of a stand-in the capture names with no answer, and
-- a look-up of an absent namespace under the namespace name. Every capture
-- here is made up.

local function asks(rows, name)
    for _, a in ipairs(rows or {}) do
        if a.name == name then return a.n end
    end
    return nil
end

tests["capture asks: a call the capture lacks is counted when asked, and stays absent"] = function(t)
    local cap = made()
    cap.account.diag.names.names.GetLocale = "function"
    cap.account.diag.names.names["C_QuestLog.GetInfo"] = "function"
    local env, replay, notHeld = Capture.Env(cap)
    t.ok(type(notHeld) == "table", "Env gives the asks not held")
    if type(notHeld) ~= "table" then return end
    local c = ns.make.fakeClient({ env = env })
    t.eq(c.typeOf("UnitHealth"), "nil", "a name the capture lacks stays absent")
    t.eq({ c.raw("UnitHealth", "player") }, { false, "not a function" }, "and answers nothing")
    t.eq(notHeld.UnitHealth, 2, "each look-up of it is one ask")
    t.eq({ c.raw("GetLocale") }, { true }, "a named call with no recorded answer is a stand-in")
    t.eq(notHeld.GetLocale, 1, "and its call is one ask")
    t.eq(c.typeOf("C_Map.GetBestMapForUnit"), "nil", "an absent namespace stays absent")
    t.eq(notHeld.C_Map, 1, "and is counted under the namespace name")
    t.eq(c.raw("C_QuestLog.GetNumQuestLogEntries"), false, "a member the capture lacks in a namespace it holds")
    t.eq(notHeld["C_QuestLog.GetNumQuestLogEntries"], 1, "is counted under its own name")
    t.eq({ c.raw("UnitClass", "player") }, { true, "Paladin", "PALADIN", 2 }, "a held call answers")
    t.eq(notHeld.UnitClass, nil, "and is not counted here")
    t.eq(replay.UnitClass.answered, 1, "it is counted as answered")
    t.eq(replay.UnitHealth, nil, "the replay holds no count for a call it lacks")
    c.raw("GetMoney")
    t.eq(notHeld.GetMoney, nil, "a name outside the recorded calls is not counted")
    t.eq(c.globalNames("^UnitHealth$"), {}, "the env lists no name it lacks")
end

tests["capture asks: the loaded client reports the asks through the diag word"] = function(t)
    local c, addon, report = boot(made())
    t.ok(type(report.notHeld) == "table", "the report holds the asks not held")
    if type(report.notHeld) ~= "table" then return end
    local before = report.notHeld.UnitHealth or 0
    c.slashes[ns.id.slash]("diag")
    t.ok((report.notHeld.UnitHealth or 0) > before, "diag asked UnitHealth, which the capture lacks")
    t.eq(report.notHeld.UnitClass, nil, "a held call is not counted")
    t.ok(addon ~= nil, "the whole add-on booted")
end

tests["capture asks: the summary says which calls each feature asked that the capture lacks"] = function(t)
    local cap = made()
    local c, addon, report = boot(cap)
    local rows = Capture.Summarize(c, addon, report, cap, ns.offline.ownWords())
    t.eq(rows[1].feature, "rotation")
    t.ok((asks(rows[1].notHeld, "UnitHealth") or 0) > 0, "the rotation row (diag) asked UnitHealth")
    t.eq(asks(rows[1].notHeld, "UnitClass"), nil, "a held call is not listed")
    local text = Capture.SummaryText(rows, report)
    local line = text:match("\nfeature rotation asked calls the capture does not hold: ([^\n]*)")
    t.ok(line ~= nil and line:find("UnitHealth %d") ~= nil, "the row says UnitHealth and its count")
    local total = text:match("\ncalls asked that the capture does not hold: ([^\n]*)")
    t.ok(total ~= nil and total:find("UnitHealth %d") ~= nil, "the whole run says UnitHealth and its count")
end

tests["capture asks: a capture that holds the call says no ask for it"] = function(t)
    local cap = made()
    cap.account.diag.names.names.UnitHealth = "function"
    cap.account.diag.snaps[1].shapes.health = row(240)
    local c, addon, report = boot(cap)
    local rows = Capture.Summarize(c, addon, report, cap, ns.offline.ownWords())
    t.eq(asks(rows[1].notHeld, "UnitHealth"), nil, "UnitHealth held: not listed")
    t.ok(not Capture.SummaryText(rows, report):find("[ ,:]UnitHealth %d"), "and never said (UnitHealthMax is another call)")
end

tests["capture asks: no ask said is said as none, and an old row with no asks still prints"] = function(t)
    local text = Capture.SummaryText({ { feature = "made", ran = true, problems = 0, unknowns = 0, hidden = 0, lines = {} } },
        { notHeld = {} })
    t.ok(text:find("\ncalls asked that the capture does not hold: none\n", 1, true) ~= nil, "none is said")
    t.ok(not text:find("feature made asked", 1, true), "a row with no asks says no ask line")
    t.ok(not Capture.SummaryText({}):find("calls asked", 1, true), "no report: the line is left out, not guessed")
    local raises = setmetatable({}, { __index = function() error("made-up boom") end })
    t.ok(not Capture.SummaryText({}, raises):find("calls asked", 1, true), "a report that raises: left out, not guessed")
end

tests["capture asks: a row counts only the asks made during its own run"] = function(t)
    local cap = made()
    local c, addon, report = boot(cap)
    report.notHeld.UnitHealth = (report.notHeld.UnitHealth or 0) + 1000
    report.notHeld.MadeUpCall = 3
    local before = report.notHeld.UnitHealth
    local rows = Capture.Summarize(c, addon, report, cap, ns.offline.ownWords())
    local during = report.notHeld.UnitHealth - before
    t.ok(during > 0, "the rotation run asked UnitHealth")
    t.eq(asks(rows[1].notHeld, "UnitHealth"), during, "the row holds the run asks, not the asks before it")
    t.eq(asks(rows[1].notHeld, "MadeUpCall"), nil, "a call asked only before the run is not listed")
end

return tests
