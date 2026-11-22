-- Setting rows whose places would overlap, rows that name a whole section,
-- and table defaults (LEDGER 54: T1 and T3).
local _, ns = ...

local function kernel()
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    k.store:open()
    return k, c
end

local n = 0
local function row(path, scope)
    n = n + 1
    return { key = "guard.row" .. n, scope = scope or "account", type = "table", label = "Row", path = path }
end

return {
    -- T1
    ["path guard: a whole section and a place inside it are refused in either order"] = function(t)
        local k = kernel()
        t.ok(k:Setting(row("layout.arrows")) ~= nil, "the place inside is taken")
        t.eq(k:Setting(row("layout")), nil, "then the section is refused")
        t.eq(k.problems:count("setting"), 1)

        k = kernel()
        t.eq(k:Setting(row("layout")), nil, "the section first is refused too")
        t.eq(k.problems:count("setting"), 1)
        t.eq(k.settings:reset("all"), 0, "and no row holds it")
    end,

    ["path guard: a place above or below one already taken is refused, in either order"] = function(t)
        local k = kernel()
        t.ok(k:Setting(row("layout.arrows")) ~= nil)
        t.eq(k:Setting(row("layout.arrows.points")), nil, "below a taken place")
        t.eq(k.problems:count("setting"), 1)
        t.ok(k:Setting(row("layout.arrowsize")) ~= nil, "a name that only starts the same is another place")
        t.ok(k:Setting(row("layout.arrows", "char")) ~= nil, "and so is the same path in the other scope")

        k = kernel()
        t.ok(k:Setting(row("layout.arrows.points")) ~= nil)
        t.eq(k:Setting(row("layout.arrows")), nil, "above a taken place")
        t.eq(k.problems:count("setting"), 1)
    end,

    ["path guard: rows kept under settings cannot overlap either"] = function(t)
        local k = kernel()
        local function plain(key)
            return { key = key, scope = "char", type = "bool", default = false, label = "Row" }
        end
        t.ok(k:Setting(plain("sell.autoJunk")) ~= nil)
        t.ok(k:Setting(plain("sell.autoRepair")) ~= nil, "a sibling is fine")
        t.eq(k:Setting(plain("sell")), nil, "above")
        t.eq(k:Setting(plain("sell.autoJunk.grey")), nil, "below")
        t.eq(k:Setting(row("settings.sell", "char")), nil, "a named path above them")
        t.eq(k.problems:count("setting"), 3)
    end,

    ["path guard: a one-part path is refused"] = function(t)
        local k = kernel()
        t.eq(k:Setting(row("learned")), nil)
        t.eq(k:Setting(row("anything")), nil)
        t.eq(k.problems:count("setting"), 2)
        local key = { key = "onepart", scope = "account", type = "bool", default = true, label = "Row" }
        t.ok(k:Setting(key) ~= nil, "a one-part key is still fine: it is kept under settings")
    end,

    ["path guard: reset all leaves learned and imports as they were"] = function(t)
        local k, c = kernel()
        local saved = c.saved(ns.id.accountDB)
        local learned, imports = { seal = { 20154 } }, { { from = "old", count = 3 } }
        saved.learned, saved.imports = learned, imports
        t.eq(k:Setting(row("learned")), nil)
        t.eq(k:Setting(row("imports")), nil)
        t.ok(k:Setting(row("layout.arrows")) ~= nil)
        t.eq(k.settings:set("guard.row" .. n, { mode = "stacked" }), true)
        t.eq(k.settings:reset("all"), 1, "only the row that was taken")
        t.ok(saved.learned == learned, "learned is the same table")
        t.eq(saved.learned, { seal = { 20154 } })
        t.ok(saved.imports == imports, "imports is the same table")
        t.eq(saved.imports, { { from = "old", count = 3 } })
        t.eq(saved.layout.arrows, nil, "the row's own place was reset")
    end,

    -- T3
    ["table default: get hands out a copy, so a caller cannot change the default"] = function(t)
        local k = kernel()
        local default = { mode = "separate", points = { quest = { "TOP", 0 } } }
        local r = row("layout.styles")
        r.default = default
        t.ok(k:Setting(r) ~= nil)
        local a = k.settings:get(r.key)
        t.eq(a, { mode = "separate", points = { quest = { "TOP", 0 } } })
        t.ok(a ~= default, "not the default itself")
        t.ok(a.points ~= default.points, "nor a table inside it")
        a.mode = "stacked"
        a.points.quest[1] = "BOTTOM"
        t.eq(k.settings:get(r.key), { mode = "separate", points = { quest = { "TOP", 0 } } },
            "the next caller gets the default as it was declared")
        t.ok(k.settings:get(r.key) ~= k.settings:get(r.key), "each caller its own")
    end,
}
