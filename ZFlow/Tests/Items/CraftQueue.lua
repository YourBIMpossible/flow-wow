-- Items/CraftQueue.lua (P-CRAFT, lead section 226: #34 Smelt All, G21 the
-- craft bar, craft controls). Pure: the queue of ticked recipes, what stops
-- the next craft, and the lines the player reads.
local _, ns = ...
local Q = ns.CraftQueue

local tests = {}

local COPPER, TIN = 2840, 3576
local ORE_COPPER, ORE_TIN = 2770, 2771

-- over: reads to change; unset: the name of one read not known (nil),
-- since a nil in over would leave the default in place.
local function reads(over, unset)
    local r = { combat = false, moving = false, free = 4, usable = true,
        reagents = { { item = ORE_COPPER, count = 1 } },
        have = function() return 10 end }
    for k, v in pairs(over or {}) do r[k] = v end
    if unset then r[unset] = nil end
    return r
end

tests["craft queue: only ticked recipes with a whole count of one or more"] = function(t)
    local q = Q.New({ { id = 1, name = "Copper Bar", count = 3 }, { id = 2, name = "Tin Bar", count = 0 },
        { id = 3, count = -1 }, { id = 4, count = 1.5 }, { id = 5, count = "2" }, { id = 6, count = 0 / 0 },
        { name = "no id", count = 2 }, { id = 7, name = "Bronze Bar", count = 2 } })
    t.eq(#q.rows, 2)
    t.eq({ q.rows[1].id, q.rows[1].count, q.rows[1].made }, { 1, 3, 0 })
    t.eq({ q.rows[2].id, q.rows[2].count }, { 7, 2 })
    t.eq(#Q.New({}).rows, 0, "nothing ticked")
    t.eq(#Q.New(nil).rows, 0, "no list")
    t.eq(Q.New({ { id = 1, count = 5000 } }).rows[1].count, Q.MAX, "a count is held to the most")
end

tests["craft queue: crafts run back to back, row after row, then done"] = function(t)
    local q = Q.New({ { id = 1, name = "Copper Bar", count = 2 }, { id = 7, name = "Bronze Bar", count = 1 } })
    t.eq(Q.Current(q).id, 1)
    t.eq(Q.Made(q), false)
    t.eq(Q.Current(q).id, 1, "the same recipe until its count is made")
    t.eq(Q.Made(q), false)
    t.eq(Q.Current(q).id, 7, "then the next ticked recipe")
    t.eq({ Q.Total(q) }, { 2, 3 })
    t.eq(Q.Made(q), true, "all made")
    t.eq(Q.Current(q), nil)
    t.eq({ Q.Total(q) }, { 3, 3 })
    t.eq(Q.Made(q), true, "a craft after the end changes nothing")
    t.eq({ Q.Total(q) }, { 3, 3 })
end

tests["craft queue: nothing stops a craft when every read is fine"] = function(t)
    t.eq(Q.Blocker({ id = 1 }, reads()), nil)
end

tests["craft queue: what stops the next craft"] = function(t)
    local row = { id = 1 }
    t.eq(Q.Blocker(row, reads({ combat = true })), "combat")
    t.eq(Q.Blocker(row, reads(nil, "combat")), "combat", "not known is treated as in combat")
    t.eq(Q.Blocker(row, reads({ moving = true })), "moving")
    t.eq(Q.Blocker(row, reads(nil, "moving")), nil, "moving not known: not a stop (the game stops a cast on a move)")
    t.eq({ Q.Blocker(row, reads({ usable = false, why = "Requires Anvil" })) }, { "station", "Requires Anvil" })
    t.eq({ Q.Blocker(row, reads({ usable = false })) }, { "station" }, "no reason given")
    t.eq(Q.Blocker(row, reads(nil, "usable")), nil, "station not known: not a stop")
    t.eq(Q.Blocker(row, reads({ free = 0 })), "bagsFull")
    t.eq(Q.Blocker(row, reads(nil, "free")), "bagsUnread", "bags not read: never taken as room")
    t.eq(Q.Blocker(row, reads(nil, "reagents")), "reagentsUnread")
    t.eq(Q.Blocker(row, reads({ have = function() return nil end })), "reagentsUnread", "a count not read")
    t.eq({ Q.Blocker(row, reads({ have = function() return 0 end })) }, { "missing", ORE_COPPER })
    local two = reads({ reagents = { { item = COPPER, count = 1 }, { item = TIN, count = 1 } },
        have = function(item) return item == COPPER and 3 or 0 end })
    t.eq({ Q.Blocker(row, two) }, { "missing", TIN }, "the reagent that is short")
    t.eq(Q.Blocker(row, reads({ reagents = { { item = ORE_COPPER, count = 2 } },
        have = function() return 2 end })), nil, "just enough")
    t.eq(Q.Blocker(row, reads({ reagents = {} })), nil, "a recipe with no reagent")
end

tests["craft queue: the order of the stops: combat first, then moving, station, bags, reagents"] = function(t)
    local all = reads({ combat = true, moving = true, usable = false, free = 0 }, "reagents")
    t.eq(Q.Blocker({ id = 1 }, all), "combat")
    all.combat = false
    t.eq(Q.Blocker({ id = 1 }, all), "moving")
    all.moving = false
    t.eq(Q.Blocker({ id = 1 }, all), "station")
    all.usable = true
    t.eq(Q.Blocker({ id = 1 }, all), "bagsFull")
    all.free = 3
    t.eq(Q.Blocker({ id = 1 }, all), "reagentsUnread")
end

tests["craft queue: the lines the player reads"] = function(t)
    local q = Q.New({ { id = 1, name = "Copper Bar", count = 10 } })
    t.eq(Q.Line(q), "Making Copper Bar: 0 of 10")
    Q.Made(q); Q.Made(q); Q.Made(q)
    t.eq(Q.Line(q), "Making Copper Bar: 3 of 10")
    t.eq(Q.StopLine(q, "bagsFull"), "Stopped: your bags are full. Made 3 of 10.")
    t.eq(Q.StopLine(q, "missing", "Copper Ore"), "Stopped: not enough Copper Ore. Made 3 of 10.")
    t.eq(Q.StopLine(q, "station", "Requires Anvil"), "Stopped: Requires Anvil. Made 3 of 10.")
    t.eq(Q.StopLine(q, "station"), "Stopped: this recipe cannot be made here. Made 3 of 10.")
    t.eq(Q.StopLine(q, "click"), "Stopped: you stopped it. Made 3 of 10.")
    local two = Q.New({ { id = 1, name = "Copper Bar", count = 1 }, { id = 7, count = 2 } })
    t.eq(Q.Line(two), "Making Copper Bar: 0 of 1 (recipe 1 of 2)")
    Q.Made(two)
    t.eq(Q.Line(two), "Making recipe 7: 0 of 2 (recipe 2 of 2)", "no name: the recipe number")
    Q.Made(two); Q.Made(two)
    t.eq(Q.DoneLine(two), "Made 1 x Copper Bar, 2 x recipe 7.")
    for why, text in pairs(Q.WHY) do
        t.ok(type(text) == "string" and text ~= "" and not text:find("Flow"), "a plain reason: " .. why)
    end
end

tests["craft queue: make all ticks each learned recipe at what the bags cover"] = function(t)
    local recipes = { { id = 1, name = "Copper Bar", learned = true }, { id = 2, name = "Tin Bar", learned = true },
        { id = 3, name = "Silver Bar", learned = false }, { id = 4, name = "Odd", learned = true },
        { id = 5, name = "Bronze Bar", learned = true } }
    local need = { [1] = { { item = ORE_COPPER, count = 1 } }, [2] = { { item = ORE_TIN, count = 1 } },
        [3] = { { item = ORE_COPPER, count = 1 } }, [4] = nil,
        [5] = { { item = COPPER, count = 1 }, { item = TIN, count = 1 } } }
    local held = { [ORE_COPPER] = 7, [ORE_TIN] = 0, [COPPER] = 2, [TIN] = nil }
    local picks = Q.MakeAll(recipes, function(id) return need[id] end, function(item) return held[item] end)
    t.eq(picks, { { id = 1, name = "Copper Bar", count = 7 } },
        "copper ore: 7; no tin ore; silver not learned; reagents not read; a count not read")
    held[ORE_TIN], held[TIN] = 5, 1
    picks = Q.MakeAll(recipes, function(id) return need[id] end, function(item) return held[item] end)
    t.eq(picks, { { id = 1, name = "Copper Bar", count = 7 }, { id = 2, name = "Tin Bar", count = 5 },
        { id = 5, name = "Bronze Bar", count = 1 } }, "bronze: the scarcer of its two reagents")
    t.eq(Q.MakeAll(nil, function() end, function() end), {})
end

tests["craft queue: smelting is the mining window"] = function(t)
    t.eq(Q.SMELTS[186], true, "Mining")
    t.eq(Q.SMELTS[164], nil, "Blacksmithing")
end

return tests
