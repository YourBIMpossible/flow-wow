local _, ns = ...

-- Section 203 (capture-features F2): the words Capture.UNKNOWN looks for are
-- words the add-on really prints. Each test runs a feature on a MADE-UP
-- capture that lacks one read, collects what it shows the way the smoke run
-- does, and expects Capture.Unknowns to count those lines. Failures say
-- counts and read names only, never a line. Offline only; not tested in game.

local tests = {}
local Capture = ns.Capture
local Try = ns.Nav.Try
local Diag = ns.Diag
local D = ns.RotationDriver

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

-- A made-up capture: a level 12 Horde character of the class given, in the
-- middle of map 1411 on continent 1. opts.noPosition leaves the position
-- read out of the snapshot.
local function made(class, token, opts)
    opts = opts or {}
    local reads = { money = 5000, zone = { cont = 1, zone = 1411 }, mapSize = { w = 1000, h = 500 } }
    if not opts.noPosition then reads.position = { map = 1411, x = 0.5, y = 0.5 } end
    return {
        format = 1,
        account = {
            layout = { arrowIntroSeen = true },
            diag = {
                names = { build = "1.16.1 (9999)", names = { GetBuildInfo = "function", UnitClass = "function" } },
                snaps = { {
                    why = "settled", at = 13,
                    reads = reads,
                    shapes = {
                        build = row("1.16.1", "9999", "Nov 1 2026", 16001),
                        class = row(class, token, 2),
                        level = row(12),
                        faction = row("Horde", "Horde"),
                        facing = row(0),
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

-- What the words show, as lines: chat, then the shown arrows and panels.
local function show(c, words)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    for _, w in ipairs(words) do c.slashes[ns.id.slash](w) end
    c.advance(2, 8)
    local lines = {}
    for _, line in ipairs(c.printed) do lines[#lines + 1] = tostring(line) end
    for _, a in ipairs(c.arrows or {}) do
        if a.shown then for _, line in ipairs(a.lines or {}) do lines[#lines + 1] = tostring(line) end end
    end
    for _, p in ipairs(c.panels or {}) do
        if p.shown then for _, line in ipairs(p.lines or {}) do lines[#lines + 1] = tostring(line) end end
    end
    return lines
end

local function has(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

tests["capture unknown words: the add-on's own not-known lines are counted"] = function(t)
    local lines = {
        Try.WHY["position unknown"],
        "no route: where you are is not known.",
        "rotation: nothing to suggest (no enemy targeted; not read: " .. Diag.READ_WORDS.formKnown .. ").",
        "rotation: not read: " .. Diag.READ_WORDS.formKnown .. "; spells that need them are passed by.",
    }
    t.eq(Capture.Unknowns(lines, { set = { "position" } }), 2, "position lines counted")
    t.eq(Capture.Unknowns(lines, { set = { "form" } }), 2, "form lines counted")
    t.eq(Capture.Unknowns(lines, { set = { "facing" } }), 0, "no facing line here")
end

tests["capture unknown words: a flight preview with no position read says so, and it is counted"] = function(t)
    local c, _, report = boot(made("Paladin", "PALADIN", { noPosition = true }))
    t.ok(not has(report.set, "position"), "the made-up capture gave no position")
    t.ok(has(report.set, "zone"), "the zone was given")
    local lines = show(c, { "try flight" })
    show(c, { "try off" })
    t.ok(#lines > 0, "try flight said something")
    local n = Capture.Unknowns(lines, { set = { "position" } })
    t.ok(n > 0, "flight preview lines counted for position: " .. n)
end

tests["capture unknown words: the rotation with the form not read says so, and it is counted"] = function(t)
    t.ok(has(ns.Packs.DRUID.options.reads, "formKnown"), "the druid pack leans on the form read")
    local c, addon, report = boot(made("Druid", "DRUID"))
    t.ok(has(report.set, "class"), "the class was given")
    c.setDead(false)
    local ok = addon.settings:set(D.SETTING, true)
    t.ok(ok, "the rotation is switched on")
    c.advance(1, 5)
    local lines = show(c, { "diag" })
    t.ok(#lines > 0, "diag said something")
    local n = Capture.Unknowns(lines, { set = { "form" } })
    t.ok(n > 0, "rotation lines counted for form: " .. n)
end

tests["capture unknown words: with the reads given, the same features count nothing"] = function(t)
    local c, addon, report = boot(made("Druid", "DRUID"))
    t.ok(has(report.set, "position"), "the position was given")
    local lines = show(c, { "try flight" })
    show(c, { "try off" })
    t.eq(Capture.Unknowns(lines, { set = { "position" } }), 0, "flight preview lines counted for position")
    c.setDead(false); c.setFormName(nil, true)
    addon.settings:set(D.SETTING, true); c.advance(1, 5)
    t.eq(Capture.Unknowns(show(c, { "diag" }), { set = { "form" } }), 0, "rotation lines counted for form")
end

return tests
