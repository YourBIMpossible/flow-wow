-- Store and Settings over the fake client's saved tables.
local _, ns = ...

local function kernel()
    local c = ns.make.fakeClient()
    return ns.Kernel({}, c), c
end

return {
    ["store: open stamps schema 1 and makes the tables of each scope"] = function(t)
        local k, c = kernel()
        t.eq(k.store:open(), true)
        local account, char = c.saved("ZFlowDB"), c.saved("ZFlowCharDB")
        t.eq(account, { schema = 1, settings = {}, layout = {}, learned = {}, imports = {} })
        t.eq(char, { schema = 1, settings = {}, layout = {}, learned = {}, state = {} })
        t.eq(k.problems:count(), 0)
    end,

    ["store: get and set by dotted path, one table per scope"] = function(t)
        local k, c = kernel()
        k.store:open()
        t.eq(k.store:get("account", "settings.sell.autoJunk"), nil)
        t.eq(k.store:set("account", "settings.sell.autoJunk", true), true)
        t.eq(k.store:get("account", "settings.sell.autoJunk"), true)
        t.eq(c.saved("ZFlowDB").settings.sell.autoJunk, true, "written straight into the saved table")
        t.eq(k.store:get("char", "settings.sell.autoJunk"), nil, "the other scope is a different table")
        k.store:set("char", "state.zone", "A")
        t.eq(c.saved("ZFlowCharDB").state.zone, "A")
        t.eq(k.store:get("account", "schema"), 1)
    end,

    ["store: bad scope, bad path, a blocked path and schema are refused"] = function(t)
        local k = kernel()
        k.store:open()
        local ok, why = k.store:set("guild", "a", 1)
        t.eq(ok, false)
        t.ok(why:find("unknown scope", 1, true), why)
        t.eq(k.store:set("account", "", 1), false)
        t.eq(k.store:set("account", "a..b", 1), false)
        t.eq(k.store:set("account", 5, 1), false)
        t.eq(k.store:get("guild", "a"), nil)
        t.eq(k.store:get("account", "a..b"), nil)
        k.store:set("account", "learned.count", 3)
        ok, why = k.store:set("account", "learned.count.deeper", 1)
        t.eq(ok, false)
        t.ok(why:find("blocked at count", 1, true), why)
        t.eq(k.store:get("account", "learned.count"), 3, "the value in the way is kept")
        t.eq(k.store:get("account", "learned.count.deeper"), nil)
        t.eq(k.store:set("account", "schema", 9), false)
        t.eq(k.store:get("account", "schema"), 1)
    end,

    ["store: the saved table is never cached"] = function(t)
        local k, c = kernel()
        k.store:set("account", "learned.a", 1)
        c.setSaved("ZFlowDB", { schema = 1, learned = { a = 2 } })
        t.eq(k.store:get("account", "learned.a"), 2, "the table the client loaded is the one read")
    end,

    ["store: table returns the same table, made once"] = function(t)
        local k = kernel()
        k.store:open()
        local a = k.store:table("char", "learned.vendors")
        a[17] = "x"
        t.ok(k.store:table("char", "learned.vendors") == a)
        t.eq(k.store:get("char", "learned.vendors")[17], "x")
        k.store:set("char", "state.n", 4)
        t.eq(k.store:table("char", "state.n"), nil, "a value that is not a table is not replaced")
        t.eq(k.store:get("char", "state.n"), 4)
        t.eq(k.problems:count("store"), 1)
    end,

    ["store: watch fires on a change, with the new and old value"] = function(t)
        local k = kernel()
        k.store:open()
        local seen = {}
        local stop = k.store:watch("account", "settings.x", function(value, old, scope, path)
            seen[#seen + 1] = { value, old, scope, path }
        end)
        k.store:set("account", "settings.x", 1)
        k.store:set("account", "settings.x", 1)
        k.store:set("account", "settings.x", 2)
        k.store:set("account", "settings.y", 9)
        k.store:set("char", "settings.x", 9)
        t.eq(seen, { { 1, nil, "account", "settings.x" }, { 2, 1, "account", "settings.x" } })
        stop()
        k.store:set("account", "settings.x", 3)
        t.eq(#seen, 2, "nothing after cancel")
    end,

    ["store: a failing watcher is recorded and the others still run"] = function(t)
        local k = kernel()
        k.store:open()
        local ran = 0
        k.store:watch("char", "state.a", function() error("watcher broke") end)
        k.store:watch("char", "state.a", function() ran = ran + 1 end)
        t.eq(k.store:set("char", "state.a", 1), true)
        t.eq(ran, 1)
        t.eq(k.store:get("char", "state.a"), 1)
        local p = k.problems:list("watch")
        t.eq(#p, 1)
        t.eq(p[1].owner, "char:state.a")
        t.ok(p[1].text:find("watcher broke", 1, true), p[1].text)
        k.store:watch("char", "state.a", "not a function")
        t.eq(k.problems:count("store"), 1, "a bad watch is recorded, not raised")
    end,

    ["store: saved data at the current schema is left alone by open"] = function(t)
        local k, c = kernel()
        c.setSaved("ZFlowDB", { schema = 1, learned = { vendors = { [12] = "seen" } }, extra = "kept" })
        t.eq(k.store:open(), true)
        local db = c.saved("ZFlowDB")
        t.eq(db.learned, { vendors = { [12] = "seen" } }, "learned data survives")
        t.eq(db.extra, "kept")
        t.eq(db.schema, 1)
        t.eq(type(db.settings), "table")
    end,

    ["store: the ladder is empty at schema 1"] = function(t)
        local k = kernel()
        t.eq(k.store.schema, 1)
        t.eq(k.store.steps, { account = {}, char = {} })
    end,

    ["store: the ladder runs each step in order (fake steps)"] = function(t)
        local k, c = kernel()
        c.setSaved("ZFlowDB", { schema = 1, oldName = 5, learned = { a = 1 } })
        c.setSaved("ZFlowCharDB", { schema = 3, state = { z = 1 } })
        local order = {}
        k.store.schema = 3
        k.store.steps.account[1] = function(db)
            order[#order + 1] = 1
            db.newName, db.oldName = db.oldName, nil
            return db
        end
        k.store.steps.account[2] = function(db)
            order[#order + 1] = 2
            db.newName = db.newName * 10
            return db
        end
        -- The character scope is already at 3: its steps must not be called.
        local charRan = {}
        k.store.steps.char[1] = function(db) charRan[#charRan + 1] = 1; db.state = "step 1 ran"; return db end
        k.store.steps.char[2] = function(db) charRan[#charRan + 1] = 2; db.state = "step 2 ran"; return db end
        t.eq(k.store:open(), true)
        t.eq(order, { 1, 2 })
        t.eq(charRan, {}, "no step was called for the scope already at the target")
        t.eq(c.saved("ZFlowCharDB").schema, 3, "and it stays at the target")
        local db = c.saved("ZFlowDB")
        t.eq(db.schema, 3)
        t.eq(db.newName, 50)
        t.eq(db.oldName, nil)
        t.eq(db.learned, { a = 1 }, "learned data carried through")
        t.eq(c.saved("ZFlowCharDB").state, { z = 1 }, "a scope already at the target runs no step")
        t.eq(k.problems:count(), 0)
        t.eq(k.store:set("account", "learned.b", 2), true)
    end,

    ["store: a failing step leaves the saved table untouched and blocks writes"] = function(t)
        local k, c = kernel()
        c.setSaved("ZFlowDB", { schema = 1, learned = { a = 1 } })
        k.store.schema = 3
        k.store.steps.account[1] = function(db)
            db.learned.a = "changed"
            db.half = true
            return db
        end
        k.store.steps.account[2] = function() error("step broke") end
        k.store.steps.char[1] = function(db) return db end
        k.store.steps.char[2] = function(db) return db end
        t.eq(k.store:open(), false)
        t.eq(c.saved("ZFlowDB"), { schema = 1, learned = { a = 1 } }, "exactly as it was")
        local ok, why = k.store:set("account", "learned.b", 2)
        t.eq(ok, false, "writes to that scope are refused")
        t.ok(why:find("step broke", 1, true), why)
        t.eq(k.store:get("account", "learned.a"), 1, "reads still work")
        local p = k.problems:list("schema")
        t.eq(#p, 1)
        t.eq(p[1].owner, "account")
        t.ok(p[1].text:find("from schema 2 failed", 1, true), p[1].text)
        t.eq(c.saved("ZFlowCharDB").schema, 3, "the other scope opened")
        t.eq(k.store:set("char", "state.a", 1), true)
    end,

    ["store: a missing step, a newer schema and a bad schema all block, untouched"] = function(t)
        local cases = {
            { saved = { schema = 1, v = 1 }, target = 2, text = "no migration step from schema 1" },
            { saved = { schema = 4, v = 1 }, target = 2, text = "newer than this build" },
            { saved = { schema = "two", v = 1 }, target = 2, text = "not a whole number" },
            { saved = { schema = 1.5, v = 1 }, target = 2, text = "not a whole number" },
            { saved = { schema = 1, v = 1 }, target = 2, text = "returned no table", step = function() return nil end },
        }
        for i, case in ipairs(cases) do
            local k, c = kernel()
            local before = ns.make.deepCopy(case.saved)
            c.setSaved("ZFlowCharDB", case.saved)
            k.store.schema = case.target
            k.store.steps.account[1] = function(db) return db end
            k.store.steps.char[1] = case.step
            t.eq(k.store:open(), false, "case " .. i)
            t.eq(c.saved("ZFlowCharDB"), before, "case " .. i .. " untouched")
            t.eq(k.store:set("char", "state.a", 1), false, "case " .. i .. " blocked")
            local p = k.problems:list("schema")
            t.ok(#p == 1 and p[1].owner == "char" and p[1].text:find(case.text, 1, true), "case " .. i .. " reported")
        end
    end,

    ["settings: the row is the one source of the default"] = function(t)
        local k, c = kernel()
        k.store:open()
        local row = k:Setting({ key = "sell.autoJunk", scope = "char", type = "bool", default = false,
            label = "Sell junk", help = "Sells grey items.", group = "Vendor" })
        t.ok(row, "the row is returned")
        t.eq(k.settings:get("sell.autoJunk"), false)
        t.eq(k.store:get("char", "settings.sell.autoJunk"), nil, "the default is not written to saved data")
        t.eq(k.settings:set("sell.autoJunk", true), true)
        t.eq(k.settings:get("sell.autoJunk"), true)
        t.eq(c.saved("ZFlowCharDB").settings.sell.autoJunk, true, "set goes through the store, in the row's scope")
        t.eq(c.saved("ZFlowDB").settings.sell, nil)
        t.eq(k.settings:row("sell.autoJunk").label, "Sell junk")
        t.eq(k.settings:get("no.such"), nil)
        t.eq(k.settings:set("no.such", 1), false)
    end,

    ["settings: values are validated by type"] = function(t)
        local k = kernel()
        k.store:open()
        k:Setting({ key = "b", scope = "account", type = "bool", default = true, label = "B" })
        k:Setting({ key = "n", scope = "account", type = "number", default = 5, min = 1, max = 10, label = "N" })
        k:Setting({ key = "s", scope = "account", type = "string", default = "x", label = "S" })
        k:Setting({ key = "c", scope = "account", type = "choice", default = "low", choices = { "low", "high" }, label = "C" })
        t.eq(k.settings:set("b", 1), false)
        t.eq(k.settings:set("b", false), true)
        t.eq(k.settings:set("n", "7"), false)
        t.eq(k.settings:set("n", 0), false, "below min")
        t.eq(k.settings:set("n", 11), false, "above max")
        t.eq(k.settings:set("n", 0 / 0), false, "not a number")
        t.eq(k.settings:set("n", 7), true)
        t.eq(k.settings:set("s", 3), false)
        t.eq(k.settings:set("s", "y"), true)
        t.eq(k.settings:set("c", "middle"), false)
        t.eq(k.settings:set("c", "high"), true)
        t.eq({ k.settings:get("b"), k.settings:get("n"), k.settings:get("s"), k.settings:get("c") }, { false, 7, "y", "high" })
        k.store:set("account", "settings.n", "junk")
        t.eq(k.settings:get("n"), 5, "a stored value that no longer fits reads as the default")
    end,

    ["settings: a duplicate key fails that row only, and is recorded"] = function(t)
        local k = kernel()
        k.store:open()
        local first = k:Setting({ key = "dup", scope = "account", type = "number", default = 1, label = "First" })
        local second = k:Setting({ key = "dup", scope = "char", type = "number", default = 2, label = "Second" })
        local third = k:Setting({ key = "after", scope = "account", type = "bool", default = true, label = "After" })
        t.ok(first)
        t.eq(second, nil)
        t.ok(third, "rows after the duplicate still declare")
        t.eq(k.settings:get("dup"), 1, "the first row stands")
        t.eq(k.settings:row("dup").label, "First")
        local p = k.problems:list("setting")
        t.eq(#p, 1)
        t.eq(p[1].owner, "dup")
        t.eq(p[1].text, "duplicate key")
    end,

    ["settings: a bad row is recorded and skipped"] = function(t)
        local k = kernel()
        local bad = {
            "not a table",
            { scope = "account", type = "bool", default = true, label = "No key" },
            { key = "a.", scope = "account", type = "bool", default = true, label = "Bad key" },
            { key = "a", scope = "guild", type = "bool", default = true, label = "Bad scope" },
            { key = "a", scope = "account", type = "colour", default = true, label = "Bad type" },
            { key = "a", scope = "account", type = "bool", default = true },
            { key = "a", scope = "account", type = "bool", label = "No default" },
            { key = "a", scope = "account", type = "number", default = "5", label = "Default does not fit" },
            { key = "a", scope = "account", type = "number", default = 50, max = 10, label = "Default out of range" },
            { key = "a", scope = "account", type = "choice", default = "x", label = "No choices" },
            { key = "a", scope = "account", type = "bool", default = true, label = "Bad requires", requires = "x" },
        }
        for i, row in ipairs(bad) do
            t.eq(k:Setting(row), nil, "row " .. i)
        end
        t.eq(k.settings:row("a"), nil)
        local recorded = 0
        for _, p in ipairs(k.problems:list("setting")) do recorded = recorded + p.count end
        t.eq(recorded, #bad, "one record per bad row (repeats of one problem are counted)")
    end,

    ["settings: reset, groups and requires"] = function(t)
        local k = kernel()
        k.store:open()
        k:Setting({ key = "v.one", scope = "char", type = "number", default = 1, label = "One", group = "Vendor" })
        k:Setting({ key = "v.two", scope = "account", type = "number", default = 2, label = "Two", group = "Vendor" })
        k:Setting({ key = "r.three", scope = "char", type = "number", default = 3, label = "Three", group = "Route",
            requires = function(settings) return settings:get("v.one") > 5 end })
        k:Setting({ key = "r.four", scope = "char", type = "number", default = 4, label = "Four", group = "Route",
            requires = function() error("requires broke") end })
        local function values()
            return { k.settings:get("v.one"), k.settings:get("v.two"), k.settings:get("r.three") }
        end
        local keys = {}
        for row in k.settings:each() do keys[#keys + 1] = row.key end
        t.eq(keys, { "v.one", "v.two", "r.three", "r.four" }, "declaration order")
        keys = {}
        for row in k.settings:each("Route") do keys[#keys + 1] = row.key end
        t.eq(keys, { "r.three", "r.four" })

        t.eq(k.settings:available("v.one"), true)
        t.eq(k.settings:available("r.three"), false)
        k.settings:set("v.one", 10); k.settings:set("v.two", 20); k.settings:set("r.three", 30)
        t.eq(k.settings:available("r.three"), true)
        t.eq(k.settings:available("r.four"), false, "a failing requires is false")
        t.eq(k.problems:count("setting"), 1)
        t.eq(k.settings:available("no.such"), false)

        k.settings:reset("v.one")
        t.eq(values(), { 1, 20, 30 })
        k.settings:set("v.one", 10)
        k.settings:reset("Vendor")
        t.eq(values(), { 1, 2, 30 })
        k.settings:set("v.one", 10)
        k.settings:reset("all")
        t.eq(values(), { 1, 2, 3 })
    end,

    -- CU5: a saved section that is not a table is replaced, and what was
    -- there is kept once under recovered.<key> of the same scope's data.
    ["skeleton: a section that is not a table is replaced, and its old value is kept under recovered"] = function(t)
        local k, c = kernel()
        c.setSaved("ZFlowDB", { learned = "oops", imports = 7 })
        c.setSaved("ZFlowCharDB", { state = false })
        t.eq(k.store:open(), true)
        local account, char = c.saved("ZFlowDB"), c.saved("ZFlowCharDB")
        t.eq(account.learned, {})
        t.eq(account.imports, {})
        t.eq(account.recovered, { learned = "oops", imports = 7 })
        t.eq(char.state, {})
        t.eq(char.recovered, { state = false })
        t.eq(k.store:get("account", "recovered.learned"), "oops", "read through the store")
        local p = k.problems:list("store")
        t.eq(#p, 3)
        local said = {}
        for i = 1, #p do said[p[i].owner .. ":" .. p[i].text] = true end
        t.ok(said["account:learned was a string, not a table; it was replaced with an empty table;"
            .. " the old value is kept under recovered.account.learned"], "learned")
        t.ok(said["account:imports was a number, not a table; it was replaced with an empty table;"
            .. " the old value is kept under recovered.account.imports"], "imports")
        t.ok(said["char:state was a boolean, not a table; it was replaced with an empty table;"
            .. " the old value is kept under recovered.char.state"], "state")
    end,

    ["skeleton: a value already kept under recovered is never overwritten"] = function(t)
        local k, c = kernel()
        c.setSaved("ZFlowDB", { learned = "second", recovered = { learned = "first", imports = false } })
        k.store:open()
        local account = c.saved("ZFlowDB")
        t.eq(account.learned, {})
        t.eq(account.recovered, { learned = "first", imports = false }, "the first kept value stands")
        local p = k.problems:list("store")
        t.eq(#p, 1)
        t.eq(p[1].text, "learned was a string, not a table; it was replaced with an empty table;"
            .. " the old value is lost: recovered.account.learned already holds an older one")
        -- A kept false counts as kept: it is not overwritten either.
        local k2, c2 = kernel()
        c2.setSaved("ZFlowDB", { imports = "later", recovered = { imports = false } })
        k2.store:open()
        t.eq(c2.saved("ZFlowDB").recovered, { imports = false })
    end,

    ["skeleton: a recovered that is not a table is left as it is, and the problem says the value is lost"] = function(t)
        local k, c = kernel()
        c.setSaved("ZFlowDB", { learned = "oops", recovered = "mine" })
        t.eq(k.store:open(), true)
        local account = c.saved("ZFlowDB")
        t.eq(account.learned, {})
        t.eq(account.recovered, "mine")
        local p = k.problems:list("store")
        t.eq(#p, 1)
        t.eq(p[1].text, "learned was a string, not a table; it was replaced with an empty table;"
            .. " the old value is lost: recovered is not a table")
    end,

    ["skeleton: nothing is kept, and no recovered table is made, when nothing was replaced"] = function(t)
        local k, c = kernel()
        c.setSaved("ZFlowDB", { learned = { a = 1 } })
        k.store:open()
        t.eq(c.saved("ZFlowDB").recovered, nil)
        t.eq(c.saved("ZFlowCharDB").recovered, nil)
        t.eq(c.saved("ZFlowDB").learned, { a = 1 })
        t.eq(k.problems:count(), 0)
        -- Opened a second time: what was kept is still there, once.
        local k2, c2 = kernel()
        c2.setSaved("ZFlowDB", { learned = 3 })
        k2.store:open()
        k2.store:open()
        t.eq(c2.saved("ZFlowDB").recovered, { learned = 3 })
        t.eq(k2.problems:count("store"), 1)
    end,
}
