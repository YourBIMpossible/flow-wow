local _, ns = ...

-- Bank fetch (FLOW-PARITY E-61, lead section 831.3): the skill plan's step
-- to take a recipe or materials out of the bank. Flow's step is
-- Modules/Crafting/SkillPlan.lua:1022-1025 ("Bank: take out <recipe>").
--
-- What the bank holds comes only from the bank this character last saw
-- (char "learned.bankCounts" = { at, counts }, kept by Items/HaveTip.lua from
-- the client's own bank read, section 611). Never guessed: a bank not seen
-- gives no step and the reason "bank not seen", never "none in bank".
-- Read-only: nothing is withdrawn or clicked; the player takes it out.
--
--   step, why = BankFetch.Steps(needs, bank)        pure
--     needs = { { item, name, count, recipe }, ... }  count = how many are
--             short in the bags (a recipe not known and not held: 1)
--     bank  = the saved { at, counts } record, or nil
--   step = { kind = "bank", items = { { key, name, count, recipe } },
--            label = "Take from your bank: 5 Copper Bar", seenAt = bank.at }
--   why  = "bank not seen", "nothing short" or "none in bank" (no step)

ns.BankFetch = {}
local BF = ns.BankFetch

BF.LABEL = "Take from your bank: %s"
BF.NOT_SEEN = "bank not seen"
BF.NOTHING_SHORT = "nothing short"
BF.NONE = "none in bank"

local function keyOf(item)
    local Items = ns.Items
    if type(Items) == "table" and type(Items.Key) == "function" then return Items.Key(item) end
    return item
end

local function whole(n)
    return type(n) == "number" and n == n and n > 0 and n < math.huge and n == math.floor(n)
end

-- The bank's counts by item key (two spellings of one item are summed), or
-- nil when the bank was never seen.
local function bankByKey(bank)
    if type(bank) ~= "table" or type(bank.counts) ~= "table" then return nil end
    local out = {}
    for k, n in pairs(bank.counts) do
        local key = keyOf(k)
        if key ~= nil and whole(n) then out[key] = (out[key] or 0) + n end
    end
    return out
end

local function words(row)
    if row.recipe == true and row.count == 1 then return row.name end
    return string.format("%d %s", row.count, row.name)
end

function BF.Steps(needs, bank)
    local short = {}
    for _, need in ipairs(type(needs) == "table" and needs or {}) do
        if type(need) == "table" and whole(need.count) then
            local key = keyOf(need.item)
            if key ~= nil then short[#short + 1] = { need = need, key = key } end
        end
    end
    if #short == 0 then return nil, BF.NOTHING_SHORT end
    local held = bankByKey(bank)
    if not held then return nil, BF.NOT_SEEN end
    local items, said = {}, {}
    for _, s in ipairs(short) do
        local n = math.min(s.need.count, held[s.key] or 0)
        if n > 0 then
            local name = s.need.name
            if type(name) ~= "string" or name == "" then name = tostring(s.key) end
            local row = { key = s.key, name = name, count = n }
            if s.need.recipe == true then row.recipe = true end
            items[#items + 1] = row
            said[#said + 1] = words(row)
            held[s.key] = held[s.key] - n
        end
    end
    if #items == 0 then return nil, BF.NONE end
    return { kind = "bank", items = items, label = string.format(BF.LABEL, table.concat(said, ", ")),
        seenAt = bank.at }
end
