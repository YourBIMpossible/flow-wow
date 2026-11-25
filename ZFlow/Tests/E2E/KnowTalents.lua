local _, ns = ...
-- KNOW lane, slice 3 (C-62), end to end on the whole add-on loaded on a
-- fake client, for each of the nine classes: the talents word opens the
-- Talents window with the class pack's levelling build, a row for each
-- talent in order with the levels its points come at; the pure rows carry
-- each talent's reason as the tooltip. Section 236: the talent ranks
-- arriving late, a ranks read that raises and then recovers, and a reload.
-- Offline: the reads are the fake client's, not the game's. Look-only: no
-- point is spent. Not tested in game.
local tests = {}

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function T() return ns.TalentsWindow or {} end

local function buildOf(class)
    local pack
    if type(ns.Packs) == "table" then pack = ns.Packs[class] end
    local list
    if type(pack) == "table" then list = pack.talentBuilds end
    if type(list) ~= "table" then return nil end
    return list[1]
end

-- The words of the first row, worked out from the pack by hand: the first
-- talent starts at level 10 and takes one level a point.
local function firstRow(class)
    local row = buildOf(class).order[1]
    if row[2] == 1 then return "Level 10: " .. row[1] end
    return "Levels 10 to " .. (9 + row[2]) .. ": " .. row[1] .. ", " .. row[2] .. " points"
end

-- opts: class, level, account (saved ahead), ranks, unspent
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(opts.class or "DRUID"); c.setFaction("Alliance"); c.setLevel(opts.level or 12); c.setCombat(false)
    if opts.ranks then c.setTalentRanks(opts.ranks) end
    if opts.unspent then c.setUnspentTalents(opts.unspent) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count()
end

local function open(c)
    c.slashes[ns.id.slash]("talents")
    return c.kitWindows().talents
end

local function part(rec, key)
    for _, p in ipairs(rec and rec.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

local function textOf(rec, key)
    local p = part(rec, key)
    if p == nil then return nil end
    return p.text
end

for _, class in ipairs(CLASSES) do
    -- Red on 9d4ec302: the word opens nothing (rec is nil).
    tests["know 3: " .. class .. " the talents word opens the levelling build, talent by talent"] = function(t)
        local build = buildOf(class)
        t.ok(type(build) == "table" and type(build.order) == "table" and #build.order > 0, "the pack has a build")
        if type(build) ~= "table" then return end
        local c, addon, base = boot({ class = class })
        local rec = open(c)
        t.ok(rec ~= nil and rec.shown == true, "the window is open")
        t.eq(textOf(rec, "build"), build.name)
        t.eq(textOf(rec, "talent.1"), firstRow(class))
        t.ok(part(rec, "talent." .. #build.order) ~= nil, "a row for the last talent of the build")
        t.eq(part(rec, "talent." .. (#build.order + 1)), nil, "and no more")
        t.eq(part(rec, "empty"), nil, "not the empty line")
        t.eq(addon.problems:count(), base, "no new problem")
    end

    -- The per-talent tooltip: each row carries the pack's own reason.
    tests["know 3: " .. class .. " every talent row has the pack's reason as its tooltip"] = function(t)
        local build = buildOf(class)
        local entries = T().Entries and T().Entries(build) or {}
        t.eq(#entries, type(build) == "table" and #build.order or -1, "one entry for each row of the build")
        local level = 10
        for i, e in ipairs(entries) do
            t.eq(e.why, build.order[i].why, "the reason of row " .. i)
            t.eq(e.from, level, "row " .. i .. " starts at the next free level")
            level = level + e.points
        end
    end
end

tests["know 3: the first row of the druid build reads as written, and the help word has a line"] = function(t)
    local c, addon = boot()
    t.eq(textOf(open(c), "talent.1"), "Levels 10 to 14: Improved Wrath, 5 points")
    t.eq(addon.diag.help.talents, T().HELP)
end

tests["know 3: marks - not known ranks say 'by now' up to your level; known ranks say what you have"] = function(t)
    local e = { name = "A", points = 5, need = 5, from = 10, to = 14 }
    local late = { name = "B", points = 2, need = 2, from = 15, to = 16 }
    t.eq({ T().Mark(e, 12, nil, false) }, { "by now" })
    t.eq({ T().Mark(late, 12, nil, false) }, {})
    t.eq({ T().Mark(e, nil, nil, false) }, {}, "level not known: nothing claimed")
    t.eq({ T().Mark(e, 12, { A = 5 }, false) }, { "5/5", "good" })
    t.eq({ T().Mark(e, 12, { A = 3 }, true) }, { "3/5 next", "warn" })
    t.eq({ T().Mark(late, 12, { A = 3 }, false) }, { "0/2" })
    t.eq(T().Next({ e, late }, { A = 5 }), 2)
    t.eq(T().Next({ e, late }, { A = 5, B = 2 }), nil, "the build is full")
    t.eq(T().Next({ e, late }, nil), nil, "not known")
    -- A talent that comes back later in a build counts on from its first row.
    local again = T().Entries({ order = { { "A", 2 }, { "B", 1 }, { "A", 3 } } })
    t.eq(again[3].need, 5)
    t.eq({ T().Mark(again[3], 20, { A = 3 }, true) }, { "1/3 next", "warn" })
end

tests["know 3: unspent points are said on the page; a class with no pack gets the empty line"] = function(t)
    local c = boot({ unspent = 3 })
    t.eq(textOf(open(c), "unspent"), "You have 3 talent points to spend.")
    local c2 = boot({ unspent = 0 })
    t.eq(part(open(c2), "unspent"), nil, "none to spend: no line")
    local c3 = boot({ class = "NOCLASS" })
    local rec = open(c3)
    t.ok(part(rec, "empty") ~= nil, "the empty line")
    t.eq(part(rec, "talent.1"), nil)
end

-- Section 236: data arriving late, then a read that raises and recovers.
tests["know 3: the open page stays up when the ranks arrive late or the read raises"] = function(t)
    local c, addon, base = boot()
    local rec = open(c)
    t.ok(part(rec, "talent.1") ~= nil, "rows with no ranks known")
    c.setTalentRanks({ ["Improved Wrath"] = 2 })
    c.fire("CHARACTER_POINTS_CHANGED", -1)
    t.ok(part(c.kitWindows().talents, "talent.1") ~= nil, "rows once the ranks are known")
    local real = c.talentRanks
    c.talentRanks = function() error("talent read failed") end
    c.fire("CHARACTER_POINTS_CHANGED", -1)
    t.ok(part(c.kitWindows().talents, "talent.1") ~= nil, "rows while the read raises")
    c.talentRanks = real
    c.fire("PLAYER_LEVEL_UP", 13)
    t.eq(textOf(c.kitWindows().talents, "talent.1"), "Levels 10 to 14: Improved Wrath, 5 points")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Section 236: a reload. Where the window was dragged to is kept.
tests["know 3: the place of the window is kept over a reload"] = function(t)
    local c = boot()
    open(c)
    t.eq(c.kitDrag("talents", { "TOPLEFT", "TOPLEFT", 40, -60 }, 500, 400), true, "dragged")
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB) })
    t.eq(addon2.store:get("account", "layout.talentsWindow"),
        { point = { "TOPLEFT", "TOPLEFT", 40, -60 }, width = 500, height = 400 })
    local rec = open(c2)
    t.ok(rec ~= nil and rec.shown == true, "it opens again")
end

return tests
