local _, ns = ...

-- ItemPlan: from "make N of this recipe" to a list of what is needed.
--
--   plan = ItemPlan.Build(goal, context)
--
-- For each thing the goal needs it says how many, how many the player has,
-- how many are missing, and where a missing one can come from: the bags, the
-- bank, a merchant, gathering, or a craft of its own (with that craft's needs
-- worked out the same way). It adds up what the merchant part costs.
--
-- A plan never buys, sells, crafts, moves or destroys anything. It returns
-- rows. Nothing here reads the game: the snapshot, the recipes, the price
-- book and what is known about sources are all passed in, and no recipe or
-- price is shipped in this file.
--
-- goal    = { recipe = recipeKey, count = how many of its product are wanted }
-- context = {
--   recipes  = { [recipeKey] = { makes = itemKey, yield = n (1), mats = { [itemKey] = n per craft } } }
--   snapshot = a Resources snapshot (bags, bank, bankKnown, money)
--   grants   = optional: what Resources.Resolve returned for OTHER claims; what
--              they hold of an item is not counted as the player's to use here
--   book     = the price book for Prices
--   sources  = { [itemKey] = { vendor = true, gather = "Mining" } }  what is
--              known about where an item comes from; nothing is assumed
--   useBank  = false to leave the bank out (default: use it when it was seen)
-- }
--
-- plan = {
--   ok       false with `problem` when the goal can't be read (no such recipe)
--   rows     one per item needed, in the order first met:
--     { key, need,
--       have = { bags = n, bank = n },   what the plan takes from each
--       missing = n,                     still to get after bags and bank
--       sources = { { from = "bags" | "bank" | "vendor" | "gather" | "craft" | "unknown",
--                     count = n, ... } },
--       bankUnseen = true,   the bank was never seen: some of `missing` may be there
--       unknown = "bags",    the bags weren't read: have and missing are nil, and
--                            the sources are for `atMost` (the whole need)
--       cycle = true }       it could only be made from itself; not planned as a craft
--     vendor source: price (a Prices price), cost (count x an observed price,
--                    else nil), basis ("observed", "estimated" or "unknown"),
--                    text (for the player)
--     gather source: what (as given in sources)
--     craft source:  recipe, times
--   crafts   every craft in the order to do them (inner ones first):
--            { recipe, makes, times, extra = made beyond what's needed }
--   cost     { known = copper on observed prices,
--              estimated = copper on estimates that have a recorded source (never
--                          added to known),
--              unknown = how many merchant rows have no usable price }
--   afford   true, false or "unknown". True only when every price is observed
--            and the money was read. False only when the observed part alone is
--            already more than the money. Anything resting on an estimate or an
--            unknown price is "unknown".
--   ready    true (everything is in the bags or bank, or made from what is),
--            false, or "unknown" (bags unread, or something missing while the
--            bank is unseen)
--   problems { "text", ... }: cycles, a depth limit, recipes that can't be read
-- }

local ItemPlan = {}
ns.ItemPlan = ItemPlan

ItemPlan.MAX_DEPTH = 20
ItemPlan.VENDOR = "vendor"     -- the price kind a merchant's price is recorded under

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- A recipe that can be planned: a product, a yield of at least 1, and at
-- least one material with a whole, positive amount.
local function readRecipe(r)
    if type(r) ~= "table" or r.makes == nil then return nil end
    local yield = r.yield == nil and 1 or r.yield
    if not isCount(yield) or yield < 1 then return nil end
    if type(r.mats) ~= "table" or next(r.mats) == nil then return nil end
    for _, n in pairs(r.mats) do
        if not isCount(n) or n <= 0 then return nil end
    end
    return { makes = r.makes, yield = yield, mats = r.mats }
end

-- Which recipe makes an item: the first, by recipe key, that can be read.
local function recipeIndex(recipes)
    local by = {}
    if type(recipes) ~= "table" then return by end
    for _, key in ipairs(sortedKeys(recipes)) do
        local r = readRecipe(recipes[key])
        if r and by[r.makes] == nil then by[r.makes] = key end
    end
    return by
end

function ItemPlan.Build(goal, context)
    context = type(context) == "table" and context or {}
    local plan = {
        ok = true, rows = {}, crafts = {}, problems = {},
        cost = { known = 0, estimated = 0, unknown = 0 },
    }
    local recipes = type(context.recipes) == "table" and context.recipes or {}
    local top = type(goal) == "table" and readRecipe(recipes[goal.recipe]) or nil
    if not top then
        plan.ok, plan.problem = false, "no recipe that can be read for this goal"
        plan.afford, plan.ready = "unknown", "unknown"
        return plan
    end
    if not isCount(goal.count) or goal.count < 1 then
        plan.ok, plan.problem = false, "the count is not a number of 1 or more"
        plan.afford, plan.ready = "unknown", "unknown"
        return plan
    end

    local snapshot = type(context.snapshot) == "table" and context.snapshot or {}
    local sources = type(context.sources) == "table" and context.sources or {}
    local makes = recipeIndex(recipes)
    local Prices = ns.Prices
    local grants = type(context.grants) == "table" and type(context.grants.Held) == "function" and context.grants or nil

    -- A working copy of what the player has. The snapshot is not written to.
    local bagsKnown = type(snapshot.bags) == "table"
    local bankSeen = snapshot.bankKnown and type(snapshot.bank) == "table" or false
    local useBank = context.useBank ~= false
    local bags, bank = {}, {}
    local function stock(t, src, key)
        if t[key] == nil then
            local n = type(src) == "table" and isCount(src[key]) and src[key] or 0
            t[key] = n
        end
        return t[key]
    end
    -- What other claims hold comes off the bags first, then the bank.
    local reservedDone = {}
    local function reserve(key)
        if reservedDone[key] or not grants then return end
        reservedDone[key] = true
        local held = grants:Held(key)
        if not isCount(held) or held <= 0 then return end
        local inBags = stock(bags, snapshot.bags, key)
        local off = math.min(held, inBags)
        bags[key] = inBags - off
        if bankSeen then
            local inBank = stock(bank, snapshot.bank, key)
            bank[key] = inBank - math.min(held - off, inBank)
        end
    end

    local rowOf = {}
    local function row(key)
        local r = rowOf[key]
        if not r then
            r = { key = key, need = 0, have = { bags = 0, bank = 0 }, missing = 0, sources = {} }
            if not bagsKnown then r.have, r.missing, r.unknown, r.atMost = nil, nil, "bags", 0 end
            rowOf[key] = r
            plan.rows[#plan.rows + 1] = r
        end
        return r
    end
    local function source(r, from, count, extra)
        for _, s in ipairs(r.sources) do
            if s.from == from and (from ~= "craft" or s.recipe == (extra and extra.recipe)) then
                s.count = s.count + count
                if extra and extra.times then s.times = (s.times or 0) + extra.times end
                return s
            end
        end
        local s = { from = from, count = count }
        if extra then for k, v in pairs(extra) do s[k] = v end end
        r.sources[#r.sources + 1] = s
        return s
    end

    local craftOf = {}
    local need   -- declared before `craft`, which calls it

    -- Plans `times` crafts of a recipe: its materials first, then the craft.
    local function craft(recipeKey, r, times, path, depth)
        for _, mat in ipairs(sortedKeys(r.mats)) do
            need(mat, r.mats[mat] * times, path, depth + 1)
        end
        local c = craftOf[recipeKey]
        if not c then
            c = { recipe = recipeKey, makes = r.makes, times = 0, extra = 0 }
            craftOf[recipeKey] = c
            plan.crafts[#plan.crafts + 1] = c
        end
        c.times = c.times + times
    end

    need = function(key, n, path, depth)
        local r = row(key)
        r.need = r.need + n
        local left = n
        if bagsKnown then
            reserve(key)
            local inBags = stock(bags, snapshot.bags, key)
            local take = math.min(left, inBags)
            if take > 0 then
                bags[key] = inBags - take
                r.have.bags = r.have.bags + take
                source(r, "bags", take)
                left = left - take
            end
            if left > 0 and useBank then
                if bankSeen then
                    local inBank = stock(bank, snapshot.bank, key)
                    local fromBank = math.min(left, inBank)
                    if fromBank > 0 then
                        bank[key] = inBank - fromBank
                        r.have.bank = r.have.bank + fromBank
                        source(r, "bank", fromBank)
                        left = left - fromBank
                    end
                else
                    r.bankUnseen = true
                end
            end
            r.missing = r.missing + left
        else
            r.atMost = r.atMost + left
        end
        if left <= 0 then return end

        local known = type(sources[key]) == "table" and sources[key] or {}
        if known.vendor then
            source(r, "vendor", left)
            return
        end
        if known.gather then
            source(r, "gather", left, { what = known.gather })
            return
        end
        local recipeKey = makes[key]
        if recipeKey ~= nil then
            if path[key] then
                r.cycle = true
                plan.problems[#plan.problems + 1] = "a recipe for " .. tostring(key) .. " needs " .. tostring(key) .. " itself"
            elseif depth >= ItemPlan.MAX_DEPTH then
                plan.problems[#plan.problems + 1] = "the recipes for " .. tostring(key) .. " go too deep to plan"
            else
                local sub = readRecipe(recipes[recipeKey])
                local times = math.ceil(left / sub.yield)
                path[key] = true
                craft(recipeKey, sub, times, path, depth)
                path[key] = nil
                source(r, "craft", left, { recipe = recipeKey, times = times })
                -- What a craft makes beyond the need is there for a later need.
                local extra = times * sub.yield - left
                if extra > 0 then
                    craftOf[recipeKey].extra = craftOf[recipeKey].extra + extra
                    if bagsKnown then bags[key] = stock(bags, snapshot.bags, key) + extra end
                end
                return
            end
        end
        source(r, "unknown", left)
    end

    -- The goal itself is always crafted: the player asked to make it.
    local times = math.ceil(goal.count / top.yield)
    craft(goal.recipe, top, times, { [top.makes] = true }, 0)
    craftOf[goal.recipe].extra = times * top.yield - goal.count

    -- Prices for the merchant part.
    for _, r in ipairs(plan.rows) do
        for _, s in ipairs(r.sources) do
            if s.from == "vendor" then
                local price = Prices and Prices.Get(context.book, r.key, ItemPlan.VENDOR) or { basis = "unknown" }
                -- An estimate counts only with a recorded source; otherwise it
                -- is treated as no price at all.
                if price.basis == "estimated" and price.source == nil then price = { basis = "unknown" } end
                s.price, s.basis = price, price.basis
                -- A merchant's price is an item's price: when nobody saw it,
                -- the text names the vendor (F-085).
                s.text = Prices and Prices.Text(price, ItemPlan.VENDOR) or "price unknown—check vendor"
                -- Counted in whole stacks where the price has a stack size.
                if price.basis == "observed" then
                    s.cost = Prices.Cost(price, s.count)
                    plan.cost.known = plan.cost.known + s.cost
                elseif price.basis == "estimated" then
                    s.estimate = Prices.Cost(price, s.count)
                    plan.cost.estimated = plan.cost.estimated + s.estimate
                else
                    plan.cost.unknown = plan.cost.unknown + 1
                end
            end
        end
    end

    -- Can the player pay for it? Only observed prices can say yes.
    local money = isCount(snapshot.money) and snapshot.money or nil
    local uncertain = plan.cost.unknown > 0 or plan.cost.estimated > 0
    if not bagsKnown then
        -- The amounts are "at most": even the observed part is not certain.
        plan.afford = "unknown"
    elseif money and plan.cost.known > money then
        plan.afford = false
    elseif uncertain then
        plan.afford = "unknown"
    elseif plan.cost.known == 0 then
        plan.afford = true
    elseif money then
        plan.afford = true
    else
        plan.afford = "unknown"
    end

    -- Can it be made right now from what the player has?
    if not bagsKnown then
        plan.ready = "unknown"
    else
        local outside, unseen = false, false
        for _, r in ipairs(plan.rows) do
            for _, s in ipairs(r.sources) do
                if s.from == "vendor" or s.from == "gather" or s.from == "unknown" then
                    outside = true
                    if r.bankUnseen then unseen = true end
                end
            end
        end
        if not outside then plan.ready = true
        elseif unseen then plan.ready = "unknown"
        else plan.ready = false end
    end
    plan.unknown = (not bagsKnown) and "bags" or nil
    return plan
end

-- The claims a plan makes on the player's things, for Resources.Resolve: one
-- item claim for what it takes from bags and bank, and one money claim for
-- the merchant part. The money claim has an amount only when every merchant
-- price is observed; otherwise it has none ("price unknown"), and carries
-- the observed-plus-estimated figure as its estimate when there is one.
function ItemPlan.Claims(plan, owner, activity)
    local claims = {}
    if type(plan) ~= "table" or not plan.ok then return claims end
    for _, r in ipairs(plan.rows) do
        local take = r.have and (r.have.bags + r.have.bank) or 0
        if take > 0 then
            claims[#claims + 1] = { owner = owner, activity = activity, kind = "item", key = r.key, amount = take,
                                    bank = r.have.bank > 0 or nil }
        end
    end
    local c = plan.cost
    if c.known > 0 or c.estimated > 0 or c.unknown > 0 then
        local money = { owner = owner, activity = activity, kind = "money" }
        if c.estimated == 0 and c.unknown == 0 and plan.unknown == nil then
            money.amount = c.known
        elseif c.unknown == 0 then
            money.estimate = c.known + c.estimated
        end
        claims[#claims + 1] = money
    end
    return claims
end
