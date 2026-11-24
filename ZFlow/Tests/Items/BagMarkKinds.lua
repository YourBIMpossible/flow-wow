local _, ns = ...

-- Tests for the bag mark kinds of parity row E-01 (ZFlow/Items/BagMarks.lua):
-- "step" (your steps hold it), "bank" (the bank list would bank it) and
-- "auction" (the auctions word would list it), beside the four kinds there
-- already were. The pure choice only: which kind a slot gets, and the order
-- when several apply. Look only. Made-up items; not tested in game.
--
-- Red before the code: B.ORDER and B.Facts are absent, KindOf takes no
-- second argument and Marks knows nothing of holds, the bank or prices.

local tests = {}

local function B() return ns.BagMarks end

local NEW = { "step", "bank", "auction" }
local ORDER = { "step", "quest", "upgrade", "bank", "sell", "auction", "material" }

local PLANK, NAIL, TRINKET, BAUBLE, SHARD, ORE = 3001, 3002, 3003, 3004, 3005, 3006
local INFO = {
    [PLANK] = { name = "Rough Plank", quality = 1, sellPrice = 10, classID = 7 },
    [NAIL] = { name = "Bent Nail", quality = 1, sellPrice = 10, classID = 7 },
    [TRINKET] = { name = "Odd Trinket", quality = 1, sellPrice = 100, classID = 15 },
    [BAUBLE] = { name = "Dull Bauble", quality = 1, sellPrice = 100, classID = 15 },
    [SHARD] = { name = "Chipped Shard", quality = 0, sellPrice = 5, classID = 15 },
    [ORE] = { name = "Grey Ore", quality = 1, sellPrice = 10, classID = 7 },
}
local function read(item) return INFO[item] end

-- What the goals hold in the bags, as Reservations.HeldIn gives it.
local function grants(held)
    return { Held = function(_, key) return held[key] or 0 end }
end

-- The latest price seen, as Items/Posting.lua asks it.
local function seen(prices)
    return function(key)
        if prices[key] == nil then return nil end
        return { price = prices[key], at = 1000 }
    end
end

local SLOTS = {
    { bag = 0, slot = 1, item = PLANK, count = 4 },
    { bag = 0, slot = 2, item = NAIL, count = 5 },
    { bag = 0, slot = 3, item = TRINKET, count = 1 },
    { bag = 0, slot = 4, item = BAUBLE, count = 1 },
    { bag = 1, slot = 1, item = SHARD, count = 2 },
    { bag = 1, slot = 2, item = ORE, count = 3 },
}

tests["bag mark kinds: the order when several apply"] = function(t)
    t.eq(B().ORDER, ORDER)
end

tests["bag mark kinds: each new kind has its own game texture and a word"] = function(t)
    local seenPath = {}
    for _, kind in ipairs(ORDER) do
        local path = B().TEXTURE[kind]
        t.ok(type(path) == "string" and path:sub(1, 10) == "Interface\\", kind .. " texture")
        t.ok(path == nil or not seenPath[path], kind .. ": a texture of its own")
        if path ~= nil then seenPath[path] = true end
        t.ok(type(B().WORD[kind]) == "string", kind .. " word")
    end
    t.eq(B().TEXTURE.disenchant, nil, "no disenchant mark: nothing decides it")
end

tests["bag mark kinds: a plain keep takes the mark the lists give it"] = function(t)
    local keep = { action = "keep", rule = nil, basis = "unknown" }
    for _, kind in ipairs(NEW) do
        t.eq(B().KindOf(keep, { [kind] = true }), kind, kind)
    end
    t.eq(B().KindOf(keep, {}), nil, "nothing said: no mark")
    t.eq(B().KindOf(keep, { bank = false, auction = false }), nil)
    t.eq(B().KindOf(keep, { bank = "yes" }), nil, "only true is a yes")
    t.eq(B().KindOf(nil, { bank = true }), nil, "no decision: no mark")
end

tests["bag mark kinds: the order between a decision's kind and the lists'"] = function(t)
    local all = { step = true, bank = true, auction = true }
    t.eq(B().KindOf({ action = "sell", rule = "junk" }, all), "step", "your steps hold it: first")
    t.eq(B().KindOf({ action = "keep", rule = "questNeeds" }, { bank = true, auction = true }), "quest")
    t.eq(B().KindOf({ action = "equip", rule = "upgrade" }, { bank = true, auction = true }), "upgrade")
    t.eq(B().KindOf({ action = "sell", rule = "junk" }, { bank = true, auction = true }), "bank")
    t.eq(B().KindOf({ action = "sell", rule = "junk" }, { auction = true }), "sell", "the coin before the auctioneer")
    t.eq(B().KindOf({ action = "keep", rule = "professionMaterial" }, { auction = true }), "auction")
    t.eq(B().KindOf({ action = "keep", rule = "professionMaterial" }, { bank = true }), "bank")
    t.eq(B().KindOf({ action = "keep", rule = "professionMaterial" }, nil), "material", "as before")
end

tests["bag mark kinds: a decision to disenchant or auction is still no mark"] = function(t)
    t.eq(B().KindOf({ action = "disenchant", rule = "x" }), nil)
    t.eq(B().KindOf({ action = "auction", rule = "x" }), nil)
end

tests["bag mark kinds: the facts of the whole bag, from the bank list and the auctions word"] = function(t)
    local bag = ns.Bank.Entries(SLOTS, read)
    local facts = B().Facts(bag, { grants = grants({ [NAIL] = 5 }),
        auctionSeen = seen({ [TRINKET] = 5000, [SHARD] = 5000 }) })
    t.eq(facts.step, { [NAIL] = true }, "what a step holds")
    t.eq(facts.bank, { [PLANK] = true, [ORE] = true }, "trade goods nothing holds")
    t.eq(facts.auction[TRINKET], true, "a price seen, worth more than the vendor")
    t.eq(facts.auction[SHARD], true)
    t.eq(facts.auction[BAUBLE], nil, "no price seen: not listed")
    t.eq(facts.auction[NAIL], nil, "held: never offered")
end

tests["bag mark kinds: holds not known - no step, bank or auction fact"] = function(t)
    local bag = ns.Bank.Entries(SLOTS, read)
    local none = { step = {}, bank = {}, auction = {} }
    t.eq(B().Facts(bag, { auctionSeen = seen({ [TRINKET] = 5000 }) }), none, "no grants")
    t.eq(B().Facts(bag, { grants = {} }), none, "grants that answer nothing")
    t.eq(B().Facts(nil, { grants = grants({}) }), none, "bags not read")
    t.eq(B().Facts(bag, nil), none)
    t.eq(B().Facts(bag, { grants = grants({}) }).auction, {}, "no prices: no auction fact")
end

tests["bag mark kinds: Marks puts each new mark on its slot"] = function(t)
    local context = { grants = grants({ [NAIL] = 5 }), auctionSeen = seen({ [TRINKET] = 5000, [SHARD] = 5000 }) }
    local marks, n = B().Marks(SLOTS, read, context)
    t.eq(marks, {
        [0] = { [1] = "bank", [2] = "step", [3] = "auction" },
        [1] = { [1] = "sell", [2] = "bank" },
    })
    t.eq(n, 5)
end

tests["bag mark kinds: Marks with holds not known draws none of the new marks"] = function(t)
    local marks, n = B().Marks(SLOTS, read, { auctionSeen = seen({ [TRINKET] = 5000, [SHARD] = 5000 }) })
    t.eq(marks, { [1] = { [1] = "sell" } }, "the junk only, as before")
    t.eq(n, 1)
end

tests["bag mark kinds: every stack of a held item carries the step mark, a quest item its own"] = function(t)
    local info = { [NAIL] = INFO[NAIL], [3010] = { name = "Sealed Order", quality = 1, sellPrice = 0, classID = 12 } }
    local slots = {
        { bag = 0, slot = 1, item = NAIL, count = 5 },
        { bag = 2, slot = 7, item = NAIL, count = 20 },
        { bag = 2, slot = 8, item = 3010, count = 1 },
    }
    local marks = B().Marks(slots, function(item) return info[item] end, { grants = grants({ [NAIL] = 8 }) })
    t.eq(marks, { [0] = { [1] = "step" }, [2] = { [7] = "step", [8] = "quest" } })
end

tests["bag mark kinds: a price read that raises leaves the other marks"] = function(t)
    local context = { grants = grants({}), auctionSeen = function() error("boom") end }
    local marks = B().Marks(SLOTS, read, context)
    t.eq(marks[0], { [1] = "bank", [2] = "bank" })
    t.eq(marks[1], { [1] = "sell", [2] = "bank" })
end

return tests
