local _, ns = ...

-- Tests for ZFlow/Items/Plan.lua. Pure: recipes, prices, sources and the
-- snapshot are all made up here. The item and recipe names are invented.

local P, R, Prices = ns.ItemPlan, ns.Resources, ns.Prices
local tests = {}

-- kit: 2 hide + 1 thread. hide: gathered. thread: sold by a merchant.
-- plate: 2 bar. bar: 2 ore (a craft of its own), yield 1. ore: gathered.
-- bolt: 1 bar -> 5 bolts. gear: 3 bolt + 1 plate.
local function recipes()
    return {
        ["make:kit"] = { makes = "kit", mats = { hide = 2, thread = 1 } },
        ["make:plate"] = { makes = "plate", mats = { bar = 2 } },
        ["make:bar"] = { makes = "bar", mats = { ore = 2 } },
        ["make:bolt"] = { makes = "bolt", yield = 5, mats = { bar = 1 } },
        ["make:gear"] = { makes = "gear", mats = { bolt = 3, plate = 1 } },
    }
end
local function sources()
    return { hide = { gather = "Skinning" }, ore = { gather = "Mining" }, thread = { vendor = true } }
end
local function rowsByKey(plan)
    local by = {}
    for _, r in ipairs(plan.rows) do by[r.key] = r end
    return by
end
local function from(row, where)
    for _, s in ipairs(row.sources) do if s.from == where then return s end end
    return nil
end
local function build(goal, snapshot, book, extra)
    local c = { recipes = recipes(), sources = sources(), snapshot = snapshot, book = book or {} }
    for k, v in pairs(extra or {}) do c[k] = v end
    return P.Build(goal, c)
end

tests["plan: everything in the bags"] = function(t)
    local plan = build({ recipe = "make:kit", count = 2 }, R.Fake({ bags = { hide = 10, thread = 5 }, money = 0 }))
    local by = rowsByKey(plan)
    t.eq(plan.ok, true, "the goal is read")
    t.eq(#plan.rows, 2, "two materials")
    t.eq(by.hide.need, 4, "2 kits need 4 hide")
    t.eq(by.hide.have.bags, 4, "all four from the bags")
    t.eq(by.hide.missing, 0, "none missing")
    t.eq(from(by.hide, "bags").count, 4, "the source says bags")
    t.eq(#by.hide.sources, 1, "and only bags")
    t.eq(by.thread.need, 2, "and 2 thread")
    t.eq(plan.ready, true, "it can be made now")
    t.eq(plan.afford, true, "nothing to buy: affordable with no money")
    t.eq(plan.cost.known, 0, "no cost")
    t.eq(#plan.crafts, 1, "one craft")
    t.ok(plan.crafts[1].recipe == "make:kit" and plan.crafts[1].times == 2 and plan.crafts[1].extra == 0, "the kit, twice")
    t.eq(#plan.problems, 0, "no problems")
end

tests["plan: bags, then the bank, then where the rest comes from"] = function(t)
    local shot = R.Fake({ bags = { hide = 3 }, bank = { hide = 2, thread = 1 }, money = 1000 })
    local book = {}
    Prices.Record(book, "thread", "vendor", 10)
    local plan = build({ recipe = "make:kit", count = 4 }, shot, book)
    local by = rowsByKey(plan)
    t.eq(by.hide.need, 8, "8 hide needed")
    t.ok(by.hide.have.bags == 3 and by.hide.have.bank == 2, "3 from the bags, 2 from the bank")
    t.eq(by.hide.missing, 3, "3 missing")
    t.ok(from(by.hide, "gather").count == 3 and from(by.hide, "gather").what == "Skinning", "to be gathered, and how")
    t.ok(by.thread.have.bags == 0 and by.thread.have.bank == 1 and by.thread.missing == 3, "thread: 1 in the bank, 3 missing")
    local v = from(by.thread, "vendor")
    t.eq(v.count, 3, "3 from a merchant")
    t.eq(v.basis, "observed", "at an observed price")
    t.eq(v.cost, 30, "3 x 10 copper")
    t.eq(v.text, "10c", "the price as the player reads it")
    t.eq(plan.cost.known, 30, "30 copper in all")
    t.eq(plan.afford, true, "observed price and enough money: yes")
    t.eq(plan.ready, false, "but it can't be made yet")
    -- The bank left out on request.
    local noBank = rowsByKey(build({ recipe = "make:kit", count = 4 }, shot, book, { useBank = false }))
    t.ok(noBank.hide.have.bank == 0 and noBank.hide.missing == 5, "useBank = false: the bank is not counted")
    t.eq(noBank.hide.bankUnseen, nil, "and that is not 'unseen'")
    -- The snapshot is not written to.
    t.ok(shot.bags.hide == 3 and shot.bank.hide == 2, "the snapshot is as it was")
end

tests["plan: an observed price can say no, an estimate can't say yes"] = function(t)
    local goal = { recipe = "make:kit", count = 5 }
    local seen = {}
    Prices.Record(seen, "thread", "vendor", 100)
    t.eq(build(goal, R.Fake({ bags = { hide = 10 }, money = 500 }), seen).afford, true, "500 for 5 x 100: yes")
    t.eq(build(goal, R.Fake({ bags = { hide = 10 }, money = 499 }), seen).afford, false, "one copper short: no")
    t.eq(build(goal, R.Fake({ bags = { hide = 10 } }), seen).afford, "unknown", "money not read: unknown")
    -- An estimate with a recorded source: shown, labelled, never a yes.
    local guess = {}
    Prices.Record(guess, "thread", "vendor", 100, { basis = "estimated", source = "price at another merchant" })
    local plan = build(goal, R.Fake({ bags = { hide = 10 }, money = 99999 }), guess)
    local v = from(rowsByKey(plan).thread, "vendor")
    t.eq(v.basis, "estimated", "the row says it is an estimate")
    t.eq(v.cost, nil, "an estimate is not a cost")
    t.eq(v.estimate, 500, "it is carried as an estimate")
    t.eq(v.text, "about 1s (estimate)", "and labelled in the text")
    t.eq(plan.cost.known, 0, "nothing is added to the known cost")
    t.eq(plan.cost.estimated, 500, "it is added up apart")
    t.eq(plan.afford, "unknown", "plenty of money and an estimate: unknown, never yes")
    t.eq(build(goal, R.Fake({ bags = { hide = 10 }, money = 0 }), guess).afford, "unknown", "no money and an estimate: not a no either")
    -- An estimate with no recorded source is not used at all.
    local bare = {}
    Prices.Record(bare, "thread", "vendor", 100, { basis = "estimated" })
    local bp = build(goal, R.Fake({ bags = { hide = 10 }, money = 99999 }), bare)
    local bv = from(rowsByKey(bp).thread, "vendor")
    t.eq(bv.basis, "unknown", "no source recorded: treated as no price")
    t.eq(bv.text, "price unknown—check vendor", "and it reads as unknown")
    t.eq(bp.cost.estimated, 0, "not added up as an estimate")
    t.eq(bp.cost.unknown, 1, "counted as a row with no price")
    t.eq(bp.afford, "unknown", "so affordability is unknown")
    -- No price at all.
    local np = build(goal, R.Fake({ bags = { hide = 10 }, money = 99999 }), {})
    t.eq(from(rowsByKey(np).thread, "vendor").text, "price unknown—check vendor", "no price: unknown")
    t.eq(np.afford, "unknown", "unknown price: unknown")
    -- Part observed and already too dear: that is a certain no.
    local mixed = { recipes = { r = { makes = "x", mats = { a = 1, b = 1 } } }, sources = { a = { vendor = true }, b = { vendor = true } },
                    snapshot = R.Fake({ bags = {}, money = 50 }), book = {} }
    Prices.Record(mixed.book, "a", "vendor", 80)
    local mp = P.Build({ recipe = "r", count = 1 }, mixed)
    t.eq(mp.cost.unknown, 1, "b has no price")
    t.eq(mp.afford, false, "a alone costs more than the money: no, whatever b costs")
end

tests["plan: nested crafts are planned inner first"] = function(t)
    -- gear = 3 bolt + 1 plate; bolt comes 5 to a craft from 1 bar; plate = 2 bar; bar = 2 ore.
    local plan = build({ recipe = "make:gear", count = 1 }, R.Fake({ bags = { ore = 4 }, bank = {}, money = 0 }))
    local by = rowsByKey(plan)
    t.eq(by.bolt.need, 3, "3 bolts")
    t.ok(from(by.bolt, "craft").times == 1 and from(by.bolt, "craft").recipe == "make:bolt", "one craft makes 5")
    t.eq(by.plate.need, 1, "1 plate")
    t.eq(by.bar.need, 3, "bars: 1 for the bolts, 2 for the plate, on one row")
    t.eq(from(by.bar, "craft").times, 3, "three bar crafts")
    t.eq(by.ore.need, 6, "6 ore for 3 bars")
    t.ok(by.ore.have.bags == 4 and by.ore.missing == 2, "4 in the bags, 2 missing")
    t.eq(from(by.ore, "gather").count, 2, "to be mined")
    local order = {}
    for _, c in ipairs(plan.crafts) do order[#order + 1] = c.recipe .. "x" .. c.times end
    t.eq(table.concat(order, " "), "make:barx3 make:boltx1 make:platex1 make:gearx1", "bars first, the gear last")
    local bolt
    for _, c in ipairs(plan.crafts) do if c.recipe == "make:bolt" then bolt = c end end
    t.eq(bolt.extra, 2, "two bolts more than needed are made")
    t.eq(plan.ready, false, "ore is missing")
    -- With everything in the bags it is ready, through three levels.
    t.eq(build({ recipe = "make:gear", count = 1 }, R.Fake({ bags = { ore = 6 } })).ready, true, "6 ore: ready")
    -- A part already made is used before it is crafted.
    local some = rowsByKey(build({ recipe = "make:gear", count = 1 }, R.Fake({ bags = { bar = 2, bolt = 3 } })))
    t.eq(some.bolt.have.bags, 3, "bolts in the bags are used")
    t.eq(from(some.bolt, "craft"), nil, "so none are crafted")
    t.ok(some.bar.have.bags == 2 and some.bar.missing == 0, "and the bars cover the plate")
    t.eq(some.ore, nil, "no ore is needed at all")
end

tests["plan: what a craft makes beyond the need is used later"] = function(t)
    local c = {
        recipes = {
            top = { makes = "thing", mats = { bolt = 3, widget = 1 } },
            widget = { makes = "widget", mats = { bolt = 2 } },
            bolt = { makes = "bolt", yield = 5, mats = { rod = 1 } },
        },
        sources = { rod = { gather = "Mining" } },
        snapshot = R.Fake({ bags = {} }), book = {},
    }
    local plan = P.Build({ recipe = "top", count = 1 }, c)
    local by = rowsByKey(plan)
    t.eq(by.bolt.need, 5, "3 for the thing and 2 for the widget")
    t.eq(by.rod.need, 1, "one rod: the first craft's two spare bolts cover the widget")
    t.eq(from(by.bolt, "craft").times, 1, "one bolt craft, not two")
end

tests["plan: a cycle is reported, not followed"] = function(t)
    local c = {
        recipes = { a = { makes = "alpha", mats = { beta = 1 } }, b = { makes = "beta", mats = { alpha = 1 } } },
        sources = {}, snapshot = R.Fake({ bags = {}, bank = {} }), book = {},
    }
    local plan = P.Build({ recipe = "a", count = 1 }, c)
    local by = rowsByKey(plan)
    t.eq(plan.ok, true, "the plan is still made")
    t.eq(from(by.beta, "craft").times, 1, "beta is planned as a craft")
    t.eq(by.alpha.cycle, true, "alpha, needed to make itself, is marked")
    t.eq(from(by.alpha, "craft"), nil, "and not planned as a craft again")
    t.eq(from(by.alpha, "unknown").count, 1, "its source is unknown")
    t.eq(#plan.problems, 1, "one problem is listed")
    t.eq(plan.ready, false, "it can't be made")
    -- A recipe that needs its own product.
    local self = P.Build({ recipe = "s", count = 1 }, { recipes = { s = { makes = "yeast", mats = { yeast = 1 } } },
        snapshot = R.Fake({ bags = {} }) })
    t.eq(rowsByKey(self).yeast.cycle, true, "needing its own product is a cycle too")
    -- With one in the bags the same recipe is fine.
    local started = P.Build({ recipe = "s", count = 1 }, { recipes = { s = { makes = "yeast", mats = { yeast = 1 } } },
        snapshot = R.Fake({ bags = { yeast = 1 } }) })
    t.ok(started.ready == true and #started.problems == 0, "one in the bags: no cycle is met")
    -- Depth is limited.
    local deep = { recipes = {}, snapshot = R.Fake({ bags = {} }) }
    for i = 1, 30 do deep.recipes["r" .. i] = { makes = "i" .. i, mats = { ["i" .. (i + 1)] = 1 } } end
    local dp = P.Build({ recipe = "r1", count = 1 }, deep)
    t.ok(dp.ok and #dp.problems == 1 and #dp.crafts <= P.MAX_DEPTH + 1, "a chain of 30 stops at the depth limit, with a problem")
end

tests["plan: bank unseen and bags unread stay unknown"] = function(t)
    local goal = { recipe = "make:kit", count = 2 }
    -- Bank never seen: what is missing might be there.
    local unseen = build(goal, R.Fake({ bags = { hide = 1, thread = 2 } }))
    local by = rowsByKey(unseen)
    t.eq(by.hide.missing, 3, "3 hide are not in the bags")
    t.eq(by.hide.bankUnseen, true, "and the row says the bank was never seen")
    t.eq(by.thread.bankUnseen, nil, "a row that is covered needs no such note")
    t.eq(from(by.hide, "gather").count, 3, "where to get them is still listed")
    t.eq(unseen.ready, "unknown", "missing with the bank unseen: not a certain no")
    t.eq(build(goal, R.Fake({ bags = { hide = 4, thread = 2 } })).ready, true, "all in the bags: ready, bank or not")
    t.eq(build(goal, R.Fake({ bags = { hide = 1, thread = 2 }, bank = {} })).ready, false, "bank seen and empty: a certain no")
    t.eq(build(goal, R.Fake({ bags = { hide = 1, thread = 2 }, bank = { hide = 9 }, bankKnown = false })).ready, "unknown",
        "a bank count marked unseen is not used")
    -- Bags not read at all.
    local blind = build(goal, R.Fake({ money = 100 }))
    local bb = rowsByKey(blind)
    t.eq(blind.unknown, "bags", "the plan says the bags weren't read")
    t.eq(bb.hide.have, nil, "no 'have'")
    t.eq(bb.hide.missing, nil, "no 'missing'")
    t.eq(bb.hide.atMost, 4, "only how many it could be at most")
    t.eq(bb.hide.unknown, "bags", "and why")
    t.eq(blind.ready, "unknown", "ready: unknown")
    t.eq(blind.afford, "unknown", "affordable: unknown, even with money read")
    t.eq(#P.Claims(blind, "craft:kit", "profession:x"), 1, "it claims no items; only a money claim with no amount")
    t.eq(P.Claims(blind, "craft:kit", "profession:x")[1].amount, nil, "price unknown")
end

tests["plan: what other claims hold is not the plan's to use"] = function(t)
    local shot = R.Fake({ bags = { hide = 12, thread = 5 }, bank = { hide = 4 } })
    local grants = R.Resolve(shot, { { owner = "quest:8", kind = "item", key = "hide", amount = 8 } })
    local with = rowsByKey(build({ recipe = "make:kit", count = 5 }, shot, {}, { grants = grants }))
    t.ok(with.hide.have.bags == 4 and with.hide.have.bank == 4, "8 of 12 are the quest's: 4 from the bags, 4 from the bank")
    t.eq(with.hide.missing, 2, "2 missing")
    local without = rowsByKey(build({ recipe = "make:kit", count = 5 }, shot, {}))
    t.ok(without.hide.have.bags == 10 and without.hide.missing == 0, "without the quest's claim all 10 come from the bags")
    -- More held than the bags have: the rest comes off the bank.
    local big = R.Resolve(shot, { { owner = "quest:14", kind = "item", key = "hide", amount = 14, bank = true } })
    local tight = rowsByKey(build({ recipe = "make:kit", count = 5 }, shot, {}, { grants = big }))
    t.ok(tight.hide.have.bags == 0 and tight.hide.have.bank == 2 and tight.hide.missing == 8, "14 held of 16: 2 left, in the bank")
end

tests["plan: a goal that can't be read is refused, not guessed"] = function(t)
    local function why(goal, c) local p = P.Build(goal, c); return p.ok and "ok" or p.problem end
    local c = { recipes = recipes(), snapshot = R.Fake({ bags = {} }) }
    t.eq(why({ recipe = "make:kit", count = 1 }, c), "ok", "a good goal")
    t.eq(why({ recipe = "make:nothing", count = 1 }, c), "no recipe that can be read for this goal", "no such recipe")
    t.eq(why(nil, c), "no recipe that can be read for this goal", "no goal")
    t.eq(why({ recipe = "make:kit" }, c), "the count is not a number of 1 or more", "no count")
    t.eq(why({ recipe = "make:kit", count = 0 }, c), "the count is not a number of 1 or more", "a count of 0")
    t.eq(why({ recipe = "make:kit", count = -2 }, c), "the count is not a number of 1 or more", "a negative count")
    t.eq(why({ recipe = "make:kit", count = 1 }, nil), "no recipe that can be read for this goal", "no context: no recipes")
    local bad = P.Build({ recipe = "x", count = 1 }, { recipes = { x = { makes = "x", mats = { a = -1 } } } })
    t.ok(bad.ok == false and bad.afford == "unknown" and bad.ready == "unknown", "a recipe with a broken amount is not planned")
    t.eq(P.Build({ recipe = "x", count = 1 }, { recipes = { x = { makes = "x", mats = {} } } }).ok, false, "nor one with no materials")
    t.eq(P.Build({ recipe = "x", count = 1 }, { recipes = { x = { makes = "x", yield = 0, mats = { a = 1 } } } }).ok, false, "nor a yield of 0")
    -- Nothing known about a missing material: its source is "unknown".
    local lost = P.Build({ recipe = "x", count = 2 }, { recipes = { x = { makes = "x", mats = { dust = 1 } } }, snapshot = R.Fake({ bags = {} }) })
    t.eq(from(rowsByKey(lost).dust, "unknown").count, 2, "no merchant, no gathering, no recipe: unknown, not assumed")
    t.eq(#P.Claims(bad, "o", "a"), 0, "a refused plan claims nothing")
end

tests["plan: the claims it makes, and they resolve"] = function(t)
    local shot = R.Fake({ bags = { hide = 3 }, bank = { hide = 2 }, money = 100 })
    local book = {}
    Prices.Record(book, "thread", "vendor", 10)
    local plan = build({ recipe = "make:kit", count = 3 }, shot, book)
    local claims = P.Claims(plan, "craft:kit", "profession:x")
    t.eq(#claims, 2, "an item claim and a money claim")
    t.ok(claims[1].kind == "item" and claims[1].key == "hide" and claims[1].amount == 5 and claims[1].bank == true,
        "5 hide, the bank allowed since 2 come from it")
    t.ok(claims[2].kind == "money" and claims[2].amount == 30, "30 copper for 3 thread at an observed price")
    t.ok(claims[1].owner == "craft:kit" and claims[1].activity == "profession:x", "with the owner and activity given")
    local g = R.Resolve(shot, claims)
    t.ok(g[1].got == 30 and g[2].got == 5, "both are granted in full against the same snapshot")
    -- An estimated price: the money claim has no amount, the figure rides as an estimate.
    local guess = {}
    Prices.Record(guess, "thread", "vendor", 10, { basis = "estimated", source = "price at another merchant" })
    local ec = P.Claims(build({ recipe = "make:kit", count = 3 }, shot, guess), "craft:kit", "profession:x")
    t.ok(ec[2].amount == nil and ec[2].estimate == 30, "estimated: no amount, 30 as the estimate")
    -- No price: neither.
    local nc = P.Claims(build({ recipe = "make:kit", count = 3 }, shot, {}), "craft:kit", "profession:x")
    t.ok(nc[2].amount == nil and nc[2].estimate == nil, "unknown price: no amount and no estimate")
    -- Nothing to buy: no money claim.
    local free = P.Claims(build({ recipe = "make:kit", count = 1 }, R.Fake({ bags = { hide = 2, thread = 1 } })), "o", "a")
    t.ok(#free == 2 and free[1].kind == "item" and free[2].kind == "item", "two item claims, no money claim")
    t.eq(free[1].bank, nil, "and no bank flag when nothing comes from the bank")
end

tests["plan: a bank never seen is claimed for what is missing, and resolves as unknown"] = function(t)
    local shot = R.Fake({ bags = { hide = 1, thread = 2 } })
    local plan = build({ recipe = "make:kit", count = 2 }, shot)
    local claims = P.Claims(plan, "craft:kit", "profession:x")
    local hide
    for _, c in ipairs(claims) do if c.key == "hide" then hide = c end end
    t.ok(hide ~= nil, "a hide claim")
    t.eq(hide.amount, 4, "the 1 in the bags and the 3 that may be in the bank")
    t.eq(hide.bank, true, "from the bank too")
    local g = R.Resolve(shot, { hide })
    t.eq(g[1].got, 1, "the bags give 1")
    t.eq(g[1].unknown, "bank", "the rest is not known, not short")
    t.eq(g[1].short, nil)
end

tests["plan: a merchant's stack is paid for whole"] = function(t)
    local shot = R.Fake({ bags = {}, bank = {}, money = 1000 })
    local book = {}
    -- A stack of 5 thread for 1c: a fifth of a copper for one.
    Prices.Record(book, "thread", "vendor", 0.2, { per = 5 })
    local one = build({ recipe = "make:kit", count = 1 }, shot, book)
    local v = from(rowsByKey(one).thread, "vendor")
    t.eq(v.count, 1, "1 needed")
    t.eq(v.cost, 1, "one whole stack: 1c, not a fifth of one")
    t.eq(v.text, "under 1c", "the price of one is never shown as 0c")
    t.eq(one.cost.known, 1)
    local six = build({ recipe = "make:kit", count = 6 }, shot, book)
    t.eq(from(rowsByKey(six).thread, "vendor").cost, 2, "6 needed: two stacks, 2c")
    t.eq(six.cost.known, 2)
    local five = build({ recipe = "make:kit", count = 5 }, shot, book)
    t.eq(five.cost.known, 1, "5 needed: the one stack")
    -- An estimate is counted the same way, and stays an estimate.
    local guess = {}
    Prices.Record(guess, "thread", "vendor", 0.2, { basis = "estimated", source = "price at another merchant", per = 5 })
    local est = build({ recipe = "make:kit", count = 6 }, shot, guess)
    t.eq(from(rowsByKey(est).thread, "vendor").estimate, 2)
    t.eq(from(rowsByKey(est).thread, "vendor").cost, nil, "an estimate is no known cost")
    t.eq(est.cost.estimated, 2)
    t.eq(est.cost.known, 0)
end

return tests
