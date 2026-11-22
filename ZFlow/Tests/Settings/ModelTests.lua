-- The settings model: rows, defaults, validation, get, set, reset and taking
-- an import in. Every table below is made up.
local _, ns = ...

local Model = ns.Settings.Model

local VENDOR = { "sell.autoJunk", "sell.autoAll", "sell.autoRepair", "sell.autoCleanup", "sell.vendorUnpriced" }

local function sample()
    return (Model.New({
        { key = "sell.autoJunk", type = "bool", default = false, vendor = true },
        { key = "sell.autoRepair", type = "bool", default = false, vendor = true },
        { key = "frame.size", type = "number", default = 1, bounds = { min = 0.5, max = 2 } },
        { key = "frame.name", type = "string", default = "main" },
        { key = "chart.click", type = "bool", default = true },
    }))
end

local function problemFor(problems, key)
    for _, entry in ipairs(problems) do
        if entry.key == key then return entry.problem end
    end
    return nil
end

local function has(list, key)
    for _, one in ipairs(list) do
        if one == key then return true end
    end
    return false
end

-- check, set, reset and adopt hand back more than one value; these keep the first.
local function fits(model, key, value) return (model:check(key, value)) end
local function adopted(model, values, imported) return (model:adopt(values, imported)) end

return {
    -- ------------------------------------------------------------ the rows
    ["settings model: the shipped rows all load"] = function(t)
        local model, problems = Model.New(Model.ROWS)
        t.eq(problems, {})
        t.eq(#model:keys(), #Model.ROWS)
    end,

    ["settings model: a row holds its key, type, default and bounds"] = function(t)
        local row = sample():row("frame.size")
        t.eq(row.key, "frame.size")
        t.eq(row.type, "number")
        t.eq(row.default, 1)
        t.eq(row.bounds, { min = 0.5, max = 2 })
        t.eq(sample():row("no.such"), nil)
    end,

    ["settings model: keys come back in the order of the rows"] = function(t)
        t.eq(sample():keys(), { "sell.autoJunk", "sell.autoRepair", "frame.size", "frame.name", "chart.click" })
    end,

    ["settings model: a row handed out is a copy"] = function(t)
        local model = sample()
        local row = model:row("frame.size")
        row.default, row.bounds.max = 9, 99
        local keys = model:keys()
        keys[1] = "changed"
        t.eq(model:default("frame.size"), 1)
        t.eq(model:row("frame.size").bounds.max, 2)
        t.eq(model:keys()[1], "sell.autoJunk")
        t.eq(fits(model, "frame.size", 50), false)
    end,

    ["settings model: a bad row is left out and reported"] = function(t)
        local model, problems = Model.New({
            { key = "good.one", type = "bool", default = true },
            { key = "", type = "bool", default = true },
            { key = "bad.type", type = "colour", default = 1 },
            { key = "bad.default", type = "number", default = "three" },
            { key = "bad.range", type = "number", default = 5, bounds = { min = 1, max = 3 } },
            { key = "bad.bounds", type = "number", default = 1, bounds = { min = 4, max = 2 } },
            { key = "bad.boundsOnBool", type = "bool", default = true, bounds = { min = 0 } },
            { key = "no.default", type = "bool" },
            { key = "good.one", type = "bool", default = false },
            { key = "good.one.inner", type = "bool", default = false },
            { key = "good", type = "bool", default = false },
            "not a row",
        })
        t.eq(model:keys(), { "good.one" })
        t.eq(model:default("good.one"), true)
        t.eq(#problems, 11)
        for _, key in ipairs({ "", "bad.type", "bad.default", "bad.range", "bad.bounds", "bad.boundsOnBool",
                               "no.default", "good.one", "good.one.inner", "good", "?" }) do
            t.ok(problemFor(problems, key) ~= nil, "[" .. key .. "] was not reported")
        end
    end,

    ["settings model: rows that are not a table give an empty model and a problem"] = function(t)
        local model, problems = Model.New(nil)
        t.eq(model:keys(), {})
        t.eq(#problems, 1)
    end,

    -- ------------------------------------------------- vendor automations
    ["settings model: every vendor automation has its own row"] = function(t)
        local model = Model.Default()
        for _, key in ipairs(VENDOR) do
            local row = model:row(key)
            t.ok(row ~= nil, key .. " has no row")
            if row then
                t.eq(row.type, "bool", key)
                t.eq(row.vendor, true, key)
            end
        end
    end,

    ["settings model: every vendor automation is off on a new install"] = function(t)
        local model = Model.Default()
        for _, key in ipairs(VENDOR) do
            t.eq(model:default(key), false, key)
            t.eq(model:get(nil, key), false, key)
            t.eq(model:get({}, key), false, key)
            t.eq(model:explicit({}, key), false, key)
        end
    end,

    ["settings model: every row marked vendor defaults to off"] = function(t)
        local model = Model.Default()
        for _, key in ipairs(model:keys()) do
            local row = model:row(key)
            if row.vendor then t.eq(row.default, false, key) end
        end
    end,

    ["settings model: turning one vendor automation on leaves the others off"] = function(t)
        local model = Model.Default()
        for _, on in ipairs(VENDOR) do
            local values = model:set({}, on, true)
            for _, key in ipairs(VENDOR) do
                t.eq(model:get(values, key), key == on, on .. " on, reading " .. key)
            end
        end
    end,

    ["settings model: a vendor automation cannot be given a default of on"] = function(t)
        local model, problems = Model.New({
            { key = "sell.autoJunk", type = "bool", default = true, vendor = true },
            { key = "sell.count", type = "number", default = 0, vendor = true },
        })
        t.eq(model:keys(), {})
        t.ok(problemFor(problems, "sell.autoJunk") ~= nil, "a vendor row defaulting to on was accepted")
        t.ok(problemFor(problems, "sell.count") ~= nil, "a vendor row that is a number was accepted")
    end,

    -- ---------------------------------------------------------- defaults
    ["settings model: defaults come back as a settings table"] = function(t)
        t.eq(sample():defaults(), {
            sell = { autoJunk = false, autoRepair = false },
            frame = { size = 1, name = "main" },
            chart = { click = true },
        })
    end,

    ["settings model: the default of an unknown key is nil"] = function(t)
        t.eq(sample():default("no.such"), nil)
    end,

    -- ------------------------------------------------------------- check
    ["settings model: check accepts a value of the right type within bounds"] = function(t)
        local model = sample()
        t.eq(fits(model, "sell.autoJunk", true), true)
        t.eq(fits(model, "sell.autoJunk", false), true)
        t.eq(fits(model, "frame.size", 0.5), true)
        t.eq(fits(model, "frame.size", 2), true)
        t.eq(fits(model, "frame.name", ""), true)
    end,

    ["settings model: check refuses the wrong type, out of bounds and unknown keys, with a reason"] = function(t)
        local model = sample()
        local cases = {
            { "sell.autoJunk", 1 }, { "sell.autoJunk", "true" },
            { "frame.size", "1" }, { "frame.size", 0.49 }, { "frame.size", 2.01 },
            { "frame.size", 0 / 0 }, { "frame.size", math.huge },
            { "frame.name", 7 }, { "frame.name", {} },
            { "no.such", true }, { "frame.size" },
        }
        for i, case in ipairs(cases) do
            local ok, why = model:check(case[1], case[2])
            t.eq(ok, false, "case " .. i)
            t.ok(type(why) == "string" and why ~= "", "case " .. i .. " gave no reason")
        end
    end,

    ["settings model: a number with one bound is held to that bound only"] = function(t)
        local model = Model.New({
            { key = "a.low", type = "number", default = 3, bounds = { min = 1 } },
            { key = "a.high", type = "number", default = 3, bounds = { max = 5 } },
            { key = "a.free", type = "number", default = 0 },
        })
        t.eq(fits(model, "a.low", 1000), true)
        t.eq(fits(model, "a.low", 0), false)
        t.eq(fits(model, "a.high", -1000), true)
        t.eq(fits(model, "a.high", 6), false)
        t.eq(fits(model, "a.free", -1e9), true)
    end,

    -- --------------------------------------------------------------- get
    ["settings model: get reads the stored value"] = function(t)
        local model = sample()
        local values = { sell = { autoJunk = true }, frame = { size = 1.5, name = "side" }, chart = { click = false } }
        t.eq(model:get(values, "sell.autoJunk"), true)
        t.eq(model:get(values, "frame.size"), 1.5)
        t.eq(model:get(values, "frame.name"), "side")
        t.eq(model:get(values, "chart.click"), false)
    end,

    ["settings model: get reads the default when nothing is stored"] = function(t)
        local model = sample()
        for _, values in ipairs({ {}, { sell = {} }, { frame = {} } }) do
            t.eq(model:get(values, "sell.autoJunk"), false)
            t.eq(model:get(values, "frame.size"), 1)
            t.eq(model:get(values, "chart.click"), true)
        end
        t.eq(model:get(nil, "frame.name"), "main")
        t.eq(model:get("not a table", "frame.name"), "main")
    end,

    ["settings model: get reads the default when what is stored does not fit"] = function(t)
        local model = sample()
        local values = { sell = { autoJunk = "yes" }, frame = { size = 40, name = 3 }, chart = "broken" }
        t.eq(model:get(values, "sell.autoJunk"), false)
        t.eq(model:get(values, "frame.size"), 1)
        t.eq(model:get(values, "frame.name"), "main")
        t.eq(model:get(values, "chart.click"), true)
    end,

    ["settings model: get of an unknown key is nil and a reason"] = function(t)
        local value, why = sample():get({}, "no.such")
        t.eq(value, nil)
        t.ok(type(why) == "string" and why ~= "", "no reason given")
    end,

    ["settings model: get stores nothing"] = function(t)
        local model = sample()
        local values = {}
        model:get(values, "frame.size")
        model:explicit(values, "frame.size")
        t.eq(values, {})
    end,

    -- --------------------------------------------------------------- set
    ["settings model: set returns a new table holding the value"] = function(t)
        local model = sample()
        local before = { frame = { name = "side" } }
        local after = model:set(before, "frame.size", 1.25)
        t.eq(after, { frame = { name = "side", size = 1.25 } })
        t.eq(before, { frame = { name = "side" } })
        t.ok(after ~= before and after.frame ~= before.frame, "the table given was reused")
    end,

    ["settings model: set works from nothing"] = function(t)
        local model = sample()
        t.eq(model:set(nil, "sell.autoJunk", true), { sell = { autoJunk = true } })
        t.eq(model:set("not a table", "chart.click", false), { chart = { click = false } })
    end,

    ["settings model: set refuses a value that does not fit and gives the reason"] = function(t)
        local model = sample()
        local before = { frame = { size = 1.5 } }
        local cases = {
            { "frame.size", 3 }, { "frame.size", "big" }, { "sell.autoJunk", 1 },
            { "frame.name", false }, { "no.such", 1 }, { "frame.size" },
        }
        for i, case in ipairs(cases) do
            local after, why = model:set(before, case[1], case[2])
            t.eq(after, nil, "case " .. i)
            t.ok(type(why) == "string" and why ~= "", "case " .. i .. " gave no reason")
        end
        t.eq(before, { frame = { size = 1.5 } })
    end,

    ["settings model: set replaces something stored that is not a table on the way"] = function(t)
        local after = sample():set({ chart = "broken" }, "chart.click", false)
        t.eq(after, { chart = { click = false } })
    end,

    ["settings model: a value set to its default counts as chosen"] = function(t)
        local model = sample()
        local values = model:set({}, "sell.autoJunk", false)
        t.eq(values, { sell = { autoJunk = false } })
        t.eq(model:explicit(values, "sell.autoJunk"), true)
        t.eq(model:explicit(values, "sell.autoRepair"), false)
    end,

    ["settings model: a stored value that does not fit is not a choice"] = function(t)
        local model = sample()
        t.eq(model:explicit({ frame = { size = 40 } }, "frame.size"), false)
        t.eq(model:explicit({ frame = { size = 1.5 } }, "frame.size"), true)
        t.eq(model:explicit({}, "no.such"), false)
        t.eq(model:explicit(nil, "frame.size"), false)
    end,

    -- ------------------------------------------------------------- reset
    ["settings model: reset puts one key back to its default and leaves the rest"] = function(t)
        local model = sample()
        local before = { sell = { autoJunk = true, autoRepair = true }, frame = { size = 1.5 } }
        local after = model:reset(before, "sell.autoJunk")
        t.eq(after, { sell = { autoRepair = true }, frame = { size = 1.5 } })
        t.eq(model:get(after, "sell.autoJunk"), false)
        t.eq(model:explicit(after, "sell.autoJunk"), false)
        t.eq(model:get(after, "sell.autoRepair"), true)
        t.eq(before, { sell = { autoJunk = true, autoRepair = true }, frame = { size = 1.5 } })
    end,

    ["settings model: reset removes a section it leaves empty"] = function(t)
        local after = sample():reset({ frame = { size = 1.5 }, chart = { click = false } }, "frame.size")
        t.eq(after, { chart = { click = false } })
    end,

    ["settings model: reset keeps what the model has no row for"] = function(t)
        local after = sample():reset({ frame = { size = 1.5, other = "kept" }, extra = { 1, 2 } }, "frame.size")
        t.eq(after, { frame = { other = "kept" }, extra = { 1, 2 } })
    end,

    ["settings model: reset of a key that is not stored changes nothing"] = function(t)
        local model = sample()
        t.eq(model:reset({ chart = { click = false } }, "frame.size"), { chart = { click = false } })
        t.eq(model:reset(nil, "frame.size"), {})
        t.eq(model:reset({ frame = "broken" }, "frame.size"), { frame = "broken" })
    end,

    ["settings model: reset clears a stored value that does not fit"] = function(t)
        t.eq(sample():reset({ frame = { size = "huge" } }, "frame.size"), {})
    end,

    ["settings model: reset of an unknown key is nil and a reason"] = function(t)
        local after, why = sample():reset({}, "no.such")
        t.eq(after, nil)
        t.ok(type(why) == "string" and why ~= "", "no reason given")
    end,

    -- ------------------------------------------------------------ import
    ["settings model: an import fills what the player has not chosen"] = function(t)
        local model = sample()
        local after, report = model:adopt({}, { sell = { autoRepair = true }, frame = { size = 1.75 } })
        t.eq(after, { sell = { autoRepair = true }, frame = { size = 1.75 } })
        t.eq(report.taken, { "sell.autoRepair", "frame.size" })
        t.eq(report.kept, {})
        t.eq(report.refused, {})
    end,

    ["settings model: an import never replaces a choice the player made"] = function(t)
        local model = sample()
        local mine = { sell = { autoJunk = false }, frame = { size = 0.75 }, chart = { click = false } }
        local after, report = model:adopt(mine, {
            sell = { autoJunk = true }, frame = { size = 2 }, chart = { click = true },
        })
        t.eq(after, mine)
        t.eq(report.taken, {})
        t.eq(report.kept, { "sell.autoJunk", "frame.size", "chart.click" })
        t.eq(model:get(after, "sell.autoJunk"), false)
    end,

    ["settings model: an explicit off in the import is kept as a choice"] = function(t)
        local model = sample()
        local after = adopted(model, {}, { sell = { autoJunk = false }, chart = { click = true } })
        t.eq(after, { sell = { autoJunk = false }, chart = { click = true } })
        t.eq(model:explicit(after, "sell.autoJunk"), true)
        t.eq(model:explicit(after, "chart.click"), true)
        -- A later import cannot turn it on.
        local again = adopted(model, after, { sell = { autoJunk = true } })
        t.eq(model:get(again, "sell.autoJunk"), false)
    end,

    ["settings model: a vendor automation the import does not hold stays off and unchosen"] = function(t)
        local model = Model.Default()
        local after = adopted(model, {}, { sell = { autoRepair = true } })
        for _, key in ipairs(VENDOR) do
            t.eq(model:get(after, key), key == "sell.autoRepair", key)
            t.eq(model:explicit(after, key), key == "sell.autoRepair", key)
        end
    end,

    ["settings model: an import value that does not fit is refused and reported"] = function(t)
        local model = sample()
        local after, report = model:adopt({ frame = { name = "side" } }, {
            sell = { autoJunk = "yes" }, frame = { size = 40, name = "other" },
        })
        t.eq(after, { frame = { name = "side" } })
        t.eq(report.taken, {})
        t.eq(report.kept, { "frame.name" })
        t.eq(#report.refused, 2)
        t.eq(report.refused[1].key, "sell.autoJunk")
        t.eq(report.refused[2].key, "frame.size")
        t.ok(type(report.refused[1].reason) == "string" and report.refused[1].reason ~= "", "no reason given")
    end,

    ["settings model: an import replaces a stored value that does not fit"] = function(t)
        local model = sample()
        local after, report = model:adopt({ frame = { size = "huge" } }, { frame = { size = 1.5 } })
        t.eq(after, { frame = { size = 1.5 } })
        t.ok(has(report.taken, "frame.size"), "frame.size was not taken")
    end,

    ["settings model: an import leaves alone what the model has no row for"] = function(t)
        local model = sample()
        local after, report = model:adopt({ other = { a = 1 } }, { unknown = { b = 2 }, frame = { extra = true } })
        t.eq(after, { other = { a = 1 } })
        t.eq(report, { taken = {}, kept = {}, refused = {} })
    end,

    ["settings model: adopt changes neither table it is given"] = function(t)
        local model = sample()
        local mine, theirs = { frame = { name = "side" } }, { frame = { size = 1.5 }, sell = { autoJunk = true } }
        local after = adopted(model, mine, theirs)
        t.eq(mine, { frame = { name = "side" } })
        t.eq(theirs, { frame = { size = 1.5 }, sell = { autoJunk = true } })
        t.ok(after ~= mine and after.frame ~= mine.frame, "the table given was reused")
    end,

    ["settings model: adopt with nothing to import or nothing stored"] = function(t)
        local model = sample()
        t.eq(adopted(model, { chart = { click = false } }, nil), { chart = { click = false } })
        t.eq(adopted(model, nil, nil), {})
        t.eq(adopted(model, nil, "not a table"), {})
        t.eq(adopted(model, nil, { chart = { click = false } }), { chart = { click = false } })
    end,
}
