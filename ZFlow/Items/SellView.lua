local _, ns = ...

-- SellView: what the vendor sell list (L6-A) shows, from plain reads.
--
--   bag  = SellView.Bag(stacks, itemInfo)   bag entries for ItemSell.List
--   kept = SellView.Kept(bag, context)      what a rule keeps, with why
--
-- It only reads what it is handed and words nothing (ItemPresent words
-- it). Nothing here sells, buys, moves, deletes or picks anything up, and
-- nothing reads the game: the stacks and the item read are passed in.
--
-- stacks: what client.bagItems() gives, { { item = link or ID, count }, ... },
--   or nil when the bags were not read (then Bag gives nil, never {}).
-- itemInfo: the client's item read, fn(item) -> { name, quality, sellPrice,
--   classID } or nil (CLIENT NEED: client.itemInfo). nil when the client has
--   none. A fact it does not give, or gives in the wrong shape, is left out:
--   never 0, never a guess.
--
-- kept = {
--   ok    false when the bags were not read (then rows is empty)
--   rows  one per item a rule keeps, in the order first met:
--         { key, name (nil when not read), count (how many are kept; nil
--           when not known), reason, basis, rule }
-- }
-- "Kept" means a rule spoke for it: the player's keep or never-sell
-- choice, a fact (can't be sold, a quest item, held for a step) or a
-- recommendation. An item no rule speaks for is not listed: that is not a
-- reason to keep it, only no reason to sell it.

local SellView = {}
ns.SellView = SellView

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function isWhole(n)
    return isCount(n) and n == math.floor(n)
end

-- The item's facts, as far as the read gives them in the right shape.
local function facts(entry, itemInfo, item)
    if type(itemInfo) ~= "function" then return end
    local ok, info = pcall(itemInfo, item)
    if not ok or type(info) ~= "table" then return end
    if type(info.name) == "string" and info.name ~= "" then entry.name = info.name end
    if isWhole(info.quality) then entry.quality = info.quality end
    if isCount(info.sellPrice) then entry.sellPrice = info.sellPrice end
    if isWhole(info.classID) then entry.classID = info.classID end
end

function SellView.Bag(stacks, itemInfo)
    if type(stacks) ~= "table" then return nil end
    local out = {}
    for i = 1, #stacks do
        local s = stacks[i]
        local key = type(s) == "table" and ns.Items.Key(s.item) or nil
        local entry = {}
        if key ~= nil then
            entry.key = key
            if isCount(s.count) then entry.count = s.count end
            facts(entry, itemInfo, s.item)
        end
        out[i] = entry
    end
    return out
end

-- The first part of a decision (or of its rest) that a rule keeps.
local function keptPart(decision)
    local d = decision
    while type(d) == "table" do
        if d.action == "keep" and d.rule ~= nil then return d end
        d = d.rest
    end
    return nil
end

function SellView.Kept(bag, context)
    if type(bag) ~= "table" then return { ok = false, rows = {} } end
    context = type(context) == "table" and context or {}
    local D = ns.Disposition
    local items = ns.ItemSell.Gather(bag)
    local rows = {}
    for idx = 1, #items do
        local item = items[idx]
        local decision = D.Decide(item, context)
        local part = keptPart(decision)
        if part then
            rows[#rows + 1] = {
                key = item.key,
                name = type(item.name) == "string" and item.name ~= "" and item.name or nil,
                count = D.CountOf(decision, "keep"), quality = item.quality,
                reason = part.reason, basis = part.basis, rule = part.rule,
            }
        end
    end
    return { ok = true, rows = rows }
end
