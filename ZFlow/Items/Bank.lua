local _, ns = ...

-- Bank (L6-D, S1 / A4): what to put in the bank, worked out from plain reads.
--
--   bag  = Bank.Entries(stacks, itemInfo)   bag entries, as SellView.Bag makes them
--   ok, why = Bank.Banks(row, needed, rules, waits)
--   pick = Bank.Pick(bag, context)
--
-- LOOK ONLY. Nothing here deposits, withdraws, moves or picks up anything,
-- and nothing reads the game: the stacks, the item read, the claims and the
-- choices are passed in. Present.BankLines words the result.
--
-- The rule is Flow's banker (Modules/Items/Banker.lua:42-93), ported to
-- Z-Flow's decisions: what Z-Flow keeps for you but nothing on your route
-- uses now goes in (trade goods, profession materials, your never-sell
-- list); what never goes: quest things, consumables, weapons, armor, bags,
-- keys and recipes, and anything a step holds.
--
-- row      { key, action, rule, reason, classID }: an item and its decision
-- needed   { [key] = true }: what a step holds (Resources grants:Held > 0)
-- rules    the player's own: { [key] = "bank" | "carry" } (Flow's
--          banker.rules, imported to account settings.banker.rules)
-- waits    { [key] = quest title }: quest items whose next step is on
--          another continent
--
-- context: what Disposition.Decide takes (grants, choices, ...), plus
--   bankRules = rules, questWaits = waits
--
-- pick = {
--   ok    false when the bags were not read (then both lists are empty)
--   rows  what to bank, biggest count first: { key, name, count, reason }
--   held  what stays with you because a step holds it: { key, name, count }
-- }

local Bank = {}
ns.Bank = Bank

-- Item classes that stay with you whatever the rule says (Flow's `stays`,
-- Banker.lua:44-52, by the game's class number instead of its name).
Bank.STAYS = { [12] = "quest", [0] = "consumable", [2] = "weapon", [4] = "armor", [1] = "bag",
               [13] = "key", [9] = "recipe" }
Bank.TRADE_GOODS = 7
-- The rules that mark something kept for later (Flow's B.LATER_RULES).
Bank.LATER_RULES = { professionMaterial = true, neverSell = true }

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function isWhole(n)
    return isCount(n) and n == math.floor(n)
end

function Bank.Entries(stacks, itemInfo)
    if type(stacks) ~= "table" then return nil end
    local out = {}
    for i = 1, #stacks do
        local s = stacks[i]
        local key = type(s) == "table" and ns.Items.Key(s.item) or nil
        local entry = {}
        if key ~= nil then
            entry.key = key
            if isCount(s.count) then entry.count = s.count end
            if type(itemInfo) == "function" then
                local ok, f = pcall(itemInfo, s.item)
                if ok and type(f) == "table" then
                    if type(f.name) == "string" and f.name ~= "" then entry.name = f.name end
                    if isWhole(f.quality) then entry.quality = f.quality end
                    if isCount(f.sellPrice) then entry.sellPrice = f.sellPrice end
                    if isWhole(f.classID) then entry.classID = f.classID end
                end
            end
        end
        out[i] = entry
    end
    return out
end

function Bank.Banks(row, needed, rules, waits)
    if type(row) ~= "table" or row.action ~= "keep" then return false, "not something Z-Flow keeps" end
    local key = row.key
    local mine = type(rules) == "table" and key ~= nil and rules[key] or nil
    if mine == "carry" then return false, "you chose to carry it" end
    if mine == "bank" then return true, "you chose to bank it" end
    if type(needed) == "table" and key ~= nil and needed[key] then return false, "a step on your route uses it" end
    local wait = type(waits) == "table" and key ~= nil and waits[key] or nil
    if wait then return true, "its quest (" .. tostring(wait) .. ") continues on another continent" end
    if row.rule == "leftover" then return true, "it waits for a quest you don't have yet" end
    if type(row.reason) == "string" and row.reason:find("for your quest", 1, true) then
        return false, "your quest needs it"
    end
    if row.classID ~= nil and Bank.STAYS[row.classID] then return false, "you carry it" end
    if Bank.LATER_RULES[row.rule or ""] then return true, "kept for later" end
    if row.classID == Bank.TRADE_GOODS then return true, "kept for later" end
    return false, "you carry it"
end

-- The bag as one item per key, in the order first met; counts summed, nil
-- when one stack had none. Entries with no key are left out.
local function gather(bag)
    local items, byKey = {}, {}
    for idx = 1, #bag do
        local e = bag[idx]
        if type(e) == "table" and e.key ~= nil then
            local held = byKey[e.key]
            if not held then
                local item = {}
                for k, v in pairs(e) do item[k] = v end
                if not isCount(item.count) then item.count = nil end
                held = { item = item, counted = item.count ~= nil }
                byKey[e.key] = held
                items[#items + 1] = item
            else
                local item = held.item
                if held.counted and isCount(e.count) then
                    item.count = item.count + e.count
                else
                    held.counted, item.count = false, nil
                end
                for k, v in pairs(e) do
                    if k ~= "count" and item[k] == nil then item[k] = v end
                end
            end
        end
    end
    return items
end

local function heldOf(grants, key)
    if type(grants) ~= "table" or type(grants.Held) ~= "function" then return nil end
    local ok, n = pcall(grants.Held, grants, key)
    if not ok or not isCount(n) or n <= 0 then return nil end
    return n
end

function Bank.Pick(bag, context)
    if type(bag) ~= "table" then return { ok = false, rows = {}, held = {} } end
    context = type(context) == "table" and context or {}
    local D = ns.Disposition
    local rows, held, needed = {}, {}, {}
    local items = gather(bag)
    for idx = 1, #items do
        local item = items[idx]
        local n = heldOf(context.grants, item.key)
        if n then
            needed[item.key] = true
            held[#held + 1] = { key = item.key, name = item.name, count = n }
        end
    end
    for idx = 1, #items do
        local item = items[idx]
        local d = D.Decide(item, context)
        local row = { key = item.key, action = d.action, rule = d.rule, reason = d.reason, classID = item.classID }
        local yes, why = Bank.Banks(row, needed, context.bankRules, context.questWaits)
        if yes then
            rows[#rows + 1] = { key = item.key, name = item.name, count = item.count, reason = why }
        end
    end
    table.sort(rows, function(a, b)
        local ca, cb = isCount(a.count) and a.count or -1, isCount(b.count) and b.count or -1
        if ca ~= cb then return ca > cb end
        return tostring(a.name or a.key) < tostring(b.name or b.key)
    end)
    return { ok = true, rows = rows, held = held }
end
