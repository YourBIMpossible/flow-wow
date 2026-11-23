local _, ns = ...

-- The name-free summary of a capture's feature run (lead section 196):
-- per feature, whether its words ran, the problems and unknowns counted,
-- and the fixed words of each line it showed, numbers and names replaced.
-- White writes it from the real capture to ZFLOW_SUMMARY, outside the repo.
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

-- Masking -------------------------------------------------------------------

tests["capture mask: numbers and names become placeholders, fixed words stay"] = function(t)
    local title = ns.id.title .. ": "
    local names = { "Moss Vale", "MossVale", "Aldwynne" }
    t.eq(Capture.Mask(title .. "auction: prices for 12 item(s) on Moss Vale-Horde, from 3 search(es)", names),
        title .. "auction: prices for # item(s) on <name>-<Name>, from # search(es)")
    t.eq(Capture.Mask("met aldwynne at 3:15", names), "met <name> at #:#", "a known name in any case")
    t.eq(Capture.Mask("Then: Talk to Brannoch", {}), "Then: Talk to <Name>", "a capitalised word not in the fixed list")
    t.eq(Capture.Mask("sell [Linen Cloth] x4", {}), "sell [<item>] x#")
    t.eq(Capture.Mask("|cffff0000Kestrelle|r says", {}), "<Name> says", "colour codes dropped")
    t.eq(Capture.Mask("from zo\195\171 here", {}), "from <name> here", "a word with a byte past ASCII")
    t.eq(Capture.Mask("build 1.16.1", {}), "build #.#.#")
    t.eq(Capture.Mask(42, {}), "#", "not text: said as text")
end

-- The summary -----------------------------------------------------------------

local function boot(cap)
    local c, report = Capture.Client(cap)
    c.setScreen(1024, 768)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon, report
end

tests["capture summary: one row per feature, counts and masked lines"] = function(t)
    local cap = made()
    local c, addon, report = boot(cap)
    local rows = Capture.Summarize(c, addon, report, Capture.Names(cap))
    t.eq(#rows, #Capture.FEATURES)
    for i, r in ipairs(rows) do
        t.eq(r.feature, Capture.FEATURES[i].name)
        t.eq(r.ran, true, r.feature .. " ran")
        t.eq(r.problems, 0, r.feature .. " problems")
        t.eq(r.unknowns, 0, r.feature .. " unknowns")
        t.ok(#r.lines > 0, r.feature .. " said something")
    end
    local text = Capture.SummaryText(rows)
    t.ok(text:find("\nfeature rotation: ran yes, problems 0, unknown 0, lines ", 1, true) ~= nil, "the rotation row")
    t.eq(text:find(Capture.SUMMARY_HEAD, 1, true), 1, "it starts with its heading")
    local digits = 0
    for _, r in ipairs(rows) do
        for _, line in ipairs(r.lines) do
            if line:find("%d") then digits = digits + 1 end
        end
    end
    t.eq(digits, 0, "lines with a digit left in them")
    for _, name in ipairs({ "aldwynne", "moss vale", "mossvale", "moss-vale" }) do
        t.eq(text:lower():find(name, 1, true), nil, "no made-up name in the summary")
    end
end

tests["capture summary: a word that raises is ran no"] = function(t)
    local rows = Capture.Summarize({ slashes = { [ns.id.slash] = function() error("made-up boom") end },
        printed = {}, advance = function() end }, { problems = { list = function() return {} end } },
        { set = {} }, {})
    t.eq(rows[1].ran, false)
    t.eq(Capture.SummaryText({ rows[1] }):find("ran no", 1, true) ~= nil, true)
    t.eq(Capture.SummaryText({ rows[1] }):find("boom", 1, true), nil, "the error text is not in it")
end

-- Writing it, outside the repo only ------------------------------------------------

tests["capture summary file: never written inside the repo"] = function(t)
    t.eq({ ns.offline.writeSummary("summary.txt", "x") }, { nil, "inside the repo" }, "a relative path")
    t.eq({ ns.offline.writeSummary(nil, "x") }, { nil, "no path given" })
end

tests["capture real summary: the real run's summary goes to ZFLOW_SUMMARY (skipped without both)"] = function(t)
    local path, out = ns.offline.capturePath(), ns.offline.summaryPath()
    if not path or not out then
        t.skip("no real capture or no summary path: set ZFLOW_CAPTURE and ZFLOW_SUMMARY, both outside the repo")
        return
    end
    t.ok(not ns.offline.inRepo(path) and not ns.offline.inRepo(out), "both are outside the repo")
    if ns.offline.inRepo(path) or ns.offline.inRepo(out) then return end
    local vars = ns.offline.readSaved(path, ns.offline.captureCharPath())
    local cap = vars and Capture.FromSaved(vars)
    t.ok(cap ~= nil, "a capture")
    if not cap then return end
    local c, addon, report = boot(cap)
    local ok, why = ns.offline.writeSummary(out, Capture.SummaryText(Capture.Summarize(c, addon, report, Capture.Names(cap))))
    t.eq({ ok, why }, { true }, "the summary is written")
end

return tests
