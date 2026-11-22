-- Setting rows that name their own store path, and rows that hold a table
-- (WOW-SETTINGS-TABLE-ROWS).
local _, ns = ...

local function kernel()
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    k.store:open()
    return k, c
end

return {
    ["settings path: a row with a path reads and writes there, not under settings"] = function(t)
        local k, c = kernel()
        local row = k:Setting({ key = "arrow.seen", scope = "account", type = "bool", default = false,
                                label = "Seen", path = "layout.seen" })
        t.ok(row ~= nil, "the row is taken")
        if not row then return end
        t.eq(k.settings:get("arrow.seen"), false)
        t.eq(k.store:get("account", "layout.seen"), nil, "the default is not written")
        t.eq(k.store:set("account", "layout.seen", true), true)
        t.eq(k.settings:get("arrow.seen"), true, "read from the path")
        t.eq(k.settings:set("arrow.seen", false), true)
        t.eq(c.saved("ZFlowDB").layout.seen, false, "written at the path")
        t.eq(k.store:get("account", "settings.arrow"), nil, "and nothing under settings")
        t.eq(k.store:get("char", "layout.seen"), nil, "in the row's scope only")
        c.saved("ZFlowDB").layout.seen = "yes"
        t.eq(k.settings:get("arrow.seen"), false, "a stored value that does not fit: the default")
        t.eq(k.problems:count(), 0)
    end,

    ["settings path: a row without a path is where it always was"] = function(t)
        local k, c = kernel()
        k:Setting({ key = "sell.autoJunk", scope = "char", type = "bool", default = false, label = "Sell junk" })
        t.eq(k.settings:set("sell.autoJunk", true), true)
        t.eq(c.saved("ZFlowCharDB").settings.sell.autoJunk, true)
        t.eq(k.settings:set("sell.autoJunk", nil), false, "nil is still no value for it")
        t.eq(k.settings:get("sell.autoJunk"), true)
    end,

    ["settings path: a table row holds a table, as it is stored"] = function(t)
        local k, c = kernel()
        local row = k:Setting({ key = "arrow.layout", scope = "account", type = "table",
                                label = "Arrows", path = "layout.arrows" })
        t.ok(row ~= nil, "a table row needs no default")
        if not row then return end
        t.eq(k.settings:get("arrow.layout"), nil, "nothing stored and no default: nil")
        local value = { mode = "separate", points = { quest = { "TOP", "TOP", 0, -40 } } }
        t.eq(k.settings:set("arrow.layout", value), true)
        t.ok(c.saved("ZFlowDB").layout.arrows == value, "the table itself is stored at the path")
        t.ok(k.settings:get("arrow.layout") == value, "and read back")
        t.ok(k.settings:get("arrow.layout") == k.store:get("account", "layout.arrows"), "the same as a direct read")
        for _, bad in ipairs({ 1, "x", true }) do
            local ok, why = k.settings:set("arrow.layout", bad)
            t.eq({ ok, why }, { false, "not a valid table" })
        end
        t.ok(c.saved("ZFlowDB").layout.arrows == value, "a refused value changes nothing")
        c.saved("ZFlowDB").layout.arrows = "junk"
        t.eq(k.settings:get("arrow.layout"), nil, "a stored value that is no table: the default")
        t.eq(k.problems:count(), 0)
    end,

    ["settings path: nil clears a row that has no default, and reset clears the path"] = function(t)
        local k = kernel()
        local function stored() return k.store:get("account", "layout.arrows") end
        k:Setting({ key = "arrow.layout", scope = "account", type = "table", label = "Arrows",
                    path = "layout.arrows", group = "Arrows", keepOnResetAll = true })
        t.eq(k.settings:set("arrow.layout", { mode = "separate" }), true)
        t.eq(k.settings:set("arrow.layout", nil), true)
        t.eq({ stored(), k.settings:get("arrow.layout") }, { nil, nil })
        k.settings:set("arrow.layout", { mode = "separate" })
        t.eq(k.settings:reset("arrow.layout"), 1)
        t.eq(stored(), nil, "reset by key")
        k.settings:set("arrow.layout", { mode = "separate" })
        t.eq(k.settings:reset("Arrows"), 1)
        t.eq(stored(), nil, "reset by group")
        k.settings:set("arrow.layout", { mode = "separate" })
        t.eq(k.settings:reset("all"), 0)
        t.eq(stored(), { mode = "separate" }, "a reset of all keeps the arrow layout (owner decision 6, T4)")
        t.eq(k.store:get("account", "settings.arrow"), nil, "nothing was ever under settings")
    end,

    -- Owner decision 6 (T4): a reset of everything keeps the arrow layout.
    ["settings path D6: a row marked keepOnResetAll is kept by a reset of all"] = function(t)
        local k = kernel()
        local function stored() return k.store:get("account", "layout.arrows") end
        local row = k:Setting({ key = "arrow.layout", scope = "account", type = "table", label = "Arrows",
                                path = "layout.arrows", group = "Arrows", keepOnResetAll = true })
        t.ok(row ~= nil, "the row is taken")
        k:Setting({ key = "v.one", scope = "account", type = "bool", default = false, label = "One" })
        k.settings:set("arrow.layout", { mode = "separate" })
        k.settings:set("v.one", true)
        t.eq(k.settings:reset("all"), 1, "one row was reset: the other is not counted")
        t.eq(stored(), { mode = "separate" }, "the layout is kept")
        t.eq(k.settings:get("v.one"), false, "the other row went back to its default")
        t.eq(k.problems:count(), 0)
    end,

    ["settings path D6: a group or a key named all does not pass for a reset of all"] = function(t)
        local k = kernel()
        k:Setting({ key = "kept", scope = "account", type = "bool", default = false, label = "Kept",
                    group = "all", keepOnResetAll = true })
        k.settings:set("kept", true)
        t.eq(k.settings:reset("all"), 0)
        t.eq(k.settings:get("kept"), true, "all means everything, and this row is kept from that")
    end,

    ["settings path D6: keepOnResetAll must be true or false"] = function(t)
        local k = kernel()
        t.eq(k:Setting({ key = "a", scope = "account", type = "bool", default = false, label = "A",
                         keepOnResetAll = "yes" }), nil)
        t.eq(k.problems:count("setting"), 1)
        t.ok(k:Setting({ key = "b", scope = "account", type = "bool", default = false, label = "B",
                         keepOnResetAll = false }) ~= nil, "false is the same as not said")
        k.settings:set("b", true)
        t.eq(k.settings:reset("all"), 1)
        t.eq(k.settings:get("b"), false)
    end,

    ["settings path: a table row may give a default table"] = function(t)
        local k = kernel()
        local default = { mode = "stacked" }
        t.ok(k:Setting({ key = "a", scope = "char", type = "table", default = default, label = "A" }) ~= nil)
        t.eq(k.settings:get("a"), { mode = "stacked" }, "the row's default")
        t.ok(k.settings:get("a") ~= default, "as a copy (LEDGER 54, T3)")
        t.eq(k.settings:set("a", nil), false, "a row with a default is not cleared by nil")
        t.eq(k.settings:set("a", { mode = "separate" }), true)
        t.eq(k.store:get("char", "settings.a"), { mode = "separate" }, "no path: under settings")
        t.eq(k:Setting({ key = "b", scope = "char", type = "table", default = 3, label = "B" }), nil)
        t.eq(k.problems:count("setting"), 1, "a default that is no table is refused")
    end,

    ["settings path: only a table row may go without a default"] = function(t)
        local k = kernel()
        t.eq(k:Setting({ key = "a", scope = "char", type = "bool", label = "A", path = "layout.a" }), nil)
        t.eq(k:Setting({ key = "b", scope = "char", type = "number", label = "B" }), nil)
        local p = k.problems:list("setting")
        t.eq({ #p, p[1] and p[1].text, p[2] and p[2].text }, { 2, "no default", "no default" })
    end,

    ["settings path: a bad path is refused"] = function(t)
        local k = kernel()
        local bad = { "", ".a", "a.", "a..b", 7, true, {} }
        for i, path in ipairs(bad) do
            t.eq(k:Setting({ key = "k" .. i, scope = "account", type = "bool", default = false,
                             label = "K", path = path }), nil, "path " .. tostring(i))
            t.eq(k.settings:row("k" .. i), nil)
        end
        local p = k.problems:list("setting")
        t.eq(#p, #bad)
        for i = 1, #p do t.eq(p[i].text, "bad path") end
    end,

    ["settings path: two rows cannot share one place in one scope"] = function(t)
        local k = kernel()
        local function row(key, scope, path)
            return k:Setting({ key = key, scope = scope, type = "bool", default = false, label = key, path = path })
        end
        t.ok(row("one", "account", "layout.x") ~= nil)
        t.eq(row("two", "account", "layout.x"), nil, "the same path")
        t.ok(row("three", "char", "layout.x") ~= nil, "another scope is another place")
        t.ok(row("plain", "account") ~= nil)
        t.eq(row("four", "account", "settings.plain"), nil, "the place of a row without a path")
        t.ok(row("five", "account", "settings.later") ~= nil)
        t.eq(row("later", "account"), nil, "and the other way round")
        local p = k.problems:list("setting")
        t.eq(#p, 3)
        for i = 1, #p do t.eq(p[i].text, "duplicate path") end
        t.eq(k.settings:row("two"), nil)
    end,
}
