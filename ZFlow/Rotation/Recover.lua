local _, ns = ...

-- D-14: bandage or food after a fight, as legacy Flow (Modules/Rotation/
-- BuffItems.lua HealKind, BandageStep, FoodStep, PickFood; Engine.lua
-- E:Recover). It only reads: nothing is used here. The chooser's step
-- "recover" (Rotation/Choose.lua) puts the pick on the rotation key, as
-- Flow's key did out of a fight.
--
--   RC.Kind(info, lines) -> "bandage", "food", "drink" or nil
--       "Bandage" in the name, or class 0 subclass RC.BANDAGE_SUB: a
--       bandage. Food and drink (class 0, subclass 5) by the tooltip: a
--       line with "health" is food, one restoring mana is drink. Food or
--       drink without its tooltip is not known (nil). The second return:
--       true for food that also makes you Well Fed.
--   RC.Read(client) -> pick, partial
--       pick = { bandage, bandageName, food, foodName, drink, drinkName }:
--       the best of each by rank (Rotation/HealItems.lua HI.Rank); plain
--       food before Well Fed food (Flow's PickFood); nil when the bags were
--       not read. partial: true when some item's info or tooltip was not
--       read yet, so the pick may change when it arrives.
-- Flow's bandage size match (the one that fills your missing health) needs
-- your health amount, which this client hides (R.FROM_AMOUNT): the best
-- bandage is picked. Drink needs your mana amount, hidden too: read, not
-- suggested. First guesses on this client, not seen in game.
local RC = {}
ns.Recover = RC

RC.BANDAGE_SUB = 7
RC.FOOD_SUB = 5
RC.RECENTLY_BANDAGED = "Recently Bandaged"

local function has(s, word) return string.find(s, word, 1, true) ~= nil end

function RC.Kind(info, lines)
    if type(info) ~= "table" or type(info.name) ~= "string" then return nil end
    if has(info.name, "Bandage") or (info.classID == 0 and info.subclassID == RC.BANDAGE_SUB) then
        return "bandage"
    end
    if info.classID ~= 0 or info.subclassID ~= RC.FOOD_SUB or type(lines) ~= "table" then return nil end
    local mana = false
    for _, l in ipairs(lines) do
        local low = type(l) == "string" and string.lower(l) or ""
        if has(low, "health") then
            return "food", ns.BuffFood.IsBuffFood(lines) and true or false
        end
        if has(low, "mana") and (has(low, "restore") or has(low, "regenerat")) then mana = true end
    end
    if mana then return "drink", false end
    return nil
end

local function better(b, rank, id)
    return not b or rank > b.rank or (rank == b.rank and id < b.id)
end

function RC.Read(client)
    if type(client) ~= "table" or type(client.bagItems) ~= "function"
        or type(client.itemInfo) ~= "function" then
        return nil, false
    end
    local ok, stacks = pcall(client.bagItems)
    if not ok or type(stacks) ~= "table" then return nil, false end
    local best, seen, partial = {}, {}, false
    for _, st in ipairs(stacks) do
        local id = type(st) == "table" and ns.Items.Id(st.item) or nil
        local count = type(st) == "table" and st.count or nil
        local some = count == nil or (type(count) == "number" and count > 0)
        if id and some and not seen[id] then
            seen[id] = true
            local okI, info = pcall(client.itemInfo, id)
            if not okI or type(info) ~= "table" or type(info.name) ~= "string" then
                partial = true
            else
                local lines
                if info.classID == 0 and info.subclassID == RC.FOOD_SUB then
                    local okL, l = false, nil
                    if type(client.itemLines) == "function" then okL, l = pcall(client.itemLines, id) end
                    if okL and type(l) == "table" and next(l) ~= nil then lines = l else partial = true end
                end
                local kind, wellFed = RC.Kind(info, lines)
                if kind == "food" and wellFed then kind = "wellFedFood" end
                if kind then
                    local rank = ns.HealItems.Rank(info)
                    if better(best[kind], rank, id) then best[kind] = { id = id, name = info.name, rank = rank } end
                end
            end
        end
    end
    local pick = {}
    local food = best.food or best.wellFedFood
    if best.bandage then pick.bandage, pick.bandageName = best.bandage.id, best.bandage.name end
    if food then pick.food, pick.foodName = food.id, food.name end
    if best.drink then pick.drink, pick.drinkName = best.drink.id, best.drink.name end
    return pick, partial
end
