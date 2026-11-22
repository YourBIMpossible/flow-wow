local _, ns = ...

-- Tests for ZFlow/Items/Present.lua. Pure: plans are built by ItemPlan from
-- made-up recipes, prices and snapshots. The item and recipe names are invented.

local V, P, R, Prices = ns.ItemPresent, ns.ItemPlan, ns.Resources, ns.Prices
local tests = {}

local NAMES = { hide = "Hide", thread = "Thread", bar = "Bar", ore = "Ore", kit = "Kit", plate = "Plate" }

local function recipes()
    return {
        ["make:kit"] = { makes = "kit", mats = { hide = 2, thread = 1 } },
        ["make:plate"] = { makes = "plate", mats = { bar = 2 } },
        ["make:bar"] = { makes = "bar", mats = { ore = 2 } },
        ["make:loop"] = { makes = "loop", mats = { loop = 1 } },
        ["make:odd"] = { makes = "odd", mats = { dust = 1 } },
    }
end
local function sources()
    return { hide = { gather = "Skinning" }, ore = { gather = "Mining" }, thread = { vendor = true } }
end
local function build(goal, snapshot, book)
    return P.Build(goal, { recipes = recipes(), sources = sources(), snapshot = snapshot, book = book or {} })
end
local function view(goal, snapshot, book)
    return V.View(build(goal, snapshot, book), { names = NAMES })
end
local function rowOf(v, key)
    for _, r in ipairs(v.rows) do if r.key == key then return r end end
    return nil
end
local function has(text, part)
    return type(text) == "string" and string.find(text, part, 1, true) ~= nil
end

tests["present: everything in the bags reads as ready, with nothing to buy"] = function(t)
    local v = view({ recipe = "make:kit", count = 2 }, R.Fake({ bags = { hide = 10, thread = 5 }, bank = {}, money = 0 }))
    t.eq(v.ok, true, "ok")
    t.eq(#v.rows, 2, "one row per material")
    t.eq(rowOf(v, "hide").text, "4 x Hide: 4 in your bags", "the hide row")
    t.eq(rowOf(v, "hide").state, "have", "nothing missing")
    t.eq(v.cost, "Nothing to buy", "cost")
    t.eq(v.ready, "Ready to make", "ready")
    t.eq(v.afford, nil, "no line about paying when nothing is bought")
end

tests["present: bags, then bank, then where the rest comes from"] = function(t)
    local v = view({ recipe = "make:kit", count = 3 },
        R.Fake({ bags = { hide = 1, thread = 3 }, bank = { hide = 2 }, money = 0 }))
    local r = rowOf(v, "hide")
    t.eq(r.text, "6 x Hide: 1 in your bags, 2 from your bank, gather 3 (Skinning)", "the row")
    t.eq(r.state, "missing", "something still to get")
    t.eq(r.note, nil, "the bank was seen: no note")
    t.eq(v.ready, "Not ready: something is still to get", "ready")
end

tests["present: an observed price is shown plain, with the total"] = function(t)
    local book = {}
    Prices.Record(book, "thread", "vendor", 120)
    local v = view({ recipe = "make:kit", count = 3 }, R.Fake({ bags = { hide = 6 }, bank = {}, money = 1000 }), book)
    t.eq(rowOf(v, "thread").text, "3 x Thread: buy 3 from a merchant at 1s 20c each (3s 60c)", "the row")
    t.eq(v.cost, "To buy: 3s 60c", "cost")
    t.eq(v.afford, "You have the money for it", "afford")
end

tests["present: an observed price can say there is not enough money"] = function(t)
    local book = {}
    Prices.Record(book, "thread", "vendor", 120)
    local v = view({ recipe = "make:kit", count = 3 }, R.Fake({ bags = { hide = 6 }, bank = {}, money = 100 }), book)
    t.eq(v.afford, "Not enough money for it", "afford")
end

tests["present: an estimate is always labelled, and never says you can pay"] = function(t)
    local book = {}
    Prices.Record(book, "thread", "vendor", 120, { basis = "estimated", source = "price at another merchant" })
    local v = view({ recipe = "make:kit", count = 3 }, R.Fake({ bags = { hide = 6 }, bank = {}, money = 100000 }), book)
    local text = rowOf(v, "thread").text
    t.ok(has(text, "about 1s 20c (estimate) each"), "the price is labelled: " .. text)
    t.ok(has(text, "(about 3s 60c (estimate))"), "and so is the total: " .. text)
    t.eq(v.cost, "To buy: about 3s 60c (estimate)", "cost is labelled")
    t.eq(v.afford, "Can't tell if you have the money: a price is an estimate or unknown", "an estimate does not decide")
end

tests["present: an observed part and an estimated part are never added together"] = function(t)
    local plan = build({ recipe = "make:kit", count = 1 }, R.Fake({ bags = {}, bank = {}, money = 5 }))
    plan.cost = { known = 250, estimated = 120, unknown = 0 }
    t.eq(V.Cost(plan), "To buy: 2s 50c, plus about 1s 20c (estimate)", "two figures")
end

tests["present: an unknown price reads price unknown - check trainer"] = function(t)
    local v = view({ recipe = "make:kit", count = 3 }, R.Fake({ bags = { hide = 6 }, bank = {}, money = 100000 }))
    t.eq(rowOf(v, "thread").text, "3 x Thread: buy 3 from a merchant, price unknown - check trainer", "the row")
    t.eq(v.cost, "To buy: 1 price unknown - check trainer", "cost says so and shows no 0")
    t.ok(not has(v.cost, "0c"), "no zero")
    t.eq(v.afford, "Can't tell if you have the money: a price is an estimate or unknown", "afford")
end

tests["present: an estimate with no recorded source is shown as unknown"] = function(t)
    local book = { vendor = { thread = { value = 120, basis = "estimated" } } }
    local v = view({ recipe = "make:kit", count = 1 }, R.Fake({ bags = { hide = 2 }, bank = {}, money = 0 }), book)
    t.ok(has(rowOf(v, "thread").text, "price unknown - check trainer"), "unknown")
    t.ok(not has(rowOf(v, "thread").text, "1s 20c"), "the figure is not shown")
end

tests["present: bank never seen: the row and the plan say so"] = function(t)
    local v = view({ recipe = "make:kit", count = 3 }, R.Fake({ bags = { hide = 1, thread = 3 }, money = 0 }))
    local r = rowOf(v, "hide")
    t.eq(r.text, "6 x Hide: 1 in your bags, gather 5 (Skinning)", "the row counts only what was seen")
    t.eq(r.note, "bank not seen yet: some may be there", "the note")
    t.eq(rowOf(v, "thread").note, nil, "no note on a row that needs nothing more")
    t.eq(v.ready, "Can't tell if it is ready: the bank has not been seen yet", "ready")
    local found = false
    for _, line in ipairs(v.lines) do if has(line, "bank not seen yet") then found = true end end
    t.ok(found, "the note is in the lines")
end

tests["present: bags not read: no have, no missing, amounts are at most"] = function(t)
    local book = {}
    Prices.Record(book, "thread", "vendor", 120)
    local v = view({ recipe = "make:kit", count = 3 }, { money = 100000 }, book)
    local r = rowOf(v, "hide")
    t.eq(r.state, "unknown", "state")
    t.eq(r.text, "6 x Hide: bags not read yet; at most gather 6 (Skinning)", "the row")
    t.ok(not has(r.text, "in your bags"), "no bag count is made up")
    t.eq(v.ready, "Can't tell if it is ready: the bags have not been read yet", "ready")
    t.eq(v.cost, "To buy: at most 3s 60c", "the cost is an upper figure")
    t.eq(v.afford, "Can't tell if you have the money: the bags have not been read yet", "afford")
end

tests["present: a material nothing is known about is named as unknown"] = function(t)
    local v = view({ recipe = "make:odd", count = 2 }, R.Fake({ bags = {}, bank = {}, money = 0 }))
    t.eq(rowOf(v, "dust").text, "2 x item dust: 2 still to get, source unknown", "no name and no source are made up")
end

tests["present: inner crafts are listed in the order to do them"] = function(t)
    local v = view({ recipe = "make:plate", count = 1 }, R.Fake({ bags = { ore = 4 }, bank = {}, money = 0 }))
    t.eq(rowOf(v, "bar").text, "2 x Bar: make 2", "a made material")
    t.eq(v.crafts, { "Make 2 x Bar", "Make 1 x Plate" }, "inner first")
    t.eq(v.ready, "Ready to make", "ready from what is in the bags")
end

tests["present: a plan that can't be read gives one line and no rows"] = function(t)
    local v = V.View(build({ recipe = "make:none", count = 1 }, R.Fake({ bags = {} })), { names = NAMES })
    t.eq(v.ok, false, "not ok")
    t.eq(v.rows, {}, "no rows")
    t.eq(v.lines, { "Can't plan this: no recipe that can be read for this goal" }, "one line")
    local w = V.View(nil)
    t.eq(w.ok, false, "nil is not a plan")
    t.eq(#w.lines, 1, "one line")
end

tests["present: a recipe that needs itself is said, not hidden"] = function(t)
    local v = view({ recipe = "make:loop", count = 1 }, R.Fake({ bags = {}, bank = {}, money = 0 }))
    t.ok(has(rowOf(v, "loop").note, "can only be made from itself"), "the row note")
    t.eq(#v.problems, 1, "the problem is passed on")
end

tests["present: names come from a table or a function, never from a guess"] = function(t)
    t.eq(V.Name("hide", NAMES), "Hide", "table")
    t.eq(V.Name("hide", function(k) return "The " .. k end), "The hide", "function")
    t.eq(V.Name(2318, nil), "item 2318", "none known")
    t.eq(V.Name("hide", function() error("boom") end), "item hide", "a failing lookup is not a name")
end

tests["present: the view does not change the plan"] = function(t)
    local plan = build({ recipe = "make:kit", count = 3 }, R.Fake({ bags = { hide = 1 }, bank = {}, money = 0 }))
    local before = #plan.rows[1].sources
    V.View(plan, { names = NAMES })
    V.View(plan, { names = NAMES })
    t.eq(#plan.rows[1].sources, before, "sources untouched")
    t.eq(plan.rows[1].text, nil, "nothing written on a row")
end

tests["present: no line spells the product name"] = function(t)
    local v = view({ recipe = "make:kit", count = 3 }, { money = 1 })
    for _, line in ipairs(v.lines) do
        t.ok(not string.find(string.lower(line), "flow", 1, true), line)
    end
end

return tests
