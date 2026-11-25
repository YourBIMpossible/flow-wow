local _, ns = ...

-- GearSetRecipes (Flow-parity C-41): set recipes, the data half. Which of
-- your items make a set, per slot, and the swap list to put it on.
--
-- Ported from Flow's Modules/Gear/SetRecipes.lua:290-311 (the built-in
-- Fishing recipe: your fishing pole, the one in your hands, else the first
-- in your bags). Flow knew a pole by a hand-written list of item IDs and
-- names (Modules/Items/Disposition.lua:313-338); here a pole is what the
-- game's own item data says: item class 2 (weapon), subclass 20 (fishing
-- pole), as client.fishingPole() reads the main hand. A name alone never
-- makes a pole; an item whose class is not read is not known.
--
--   recipe       = GearSetRecipes.Get(key)
--                  { key, name, what, skill, slots = { slot ... } }
--   yes          = GearSetRecipes.IsPiece(recipe, slot, info)
--                  true / false, or nil when the item's class is not read
--   set, why     = GearSetRecipes.For(recipe, client)
--     set = { recipe = key, skill = true / false / nil,
--             slots = { [slot] = { item = link, where = "worn" | "bags" } },
--             missing = { slot ... } (no piece, all read),
--             complete = every slot has a piece }
--     or nil and a plain reason when it is not known.
--   swaps, why   = GearSetRecipes.Swaps(recipe, client)
--     swaps = { rows = { { slot, put = link, off = link worn now or nil,
--               where = "bags", reason } ... },
--               wearing = true when every piece is worn already,
--               missing = { slot ... }, lines = { text ... } }
--     or nil and a plain reason when it is not known.
--
-- Reads: client.wornLinks(), client.bagItems(), client.itemInfo(link)
-- (classID, subclassID, name), client.skillRanks(). The bank is not read:
-- Z-Flow keeps no saved bank contents, so where is only "bags".
-- LOOK ONLY. Nothing is equipped, moved or sold; putting a set on stays the
-- player's own click.

local SR = {}
ns.GearSetRecipes = SR

SR.NAME = "setRecipes"
SR.CANT_READ_WORN = "Can't read what you wear right now, so the set is not known."
SR.CANT_READ_BAGS = "Can't read your bags right now, so the set is not known."
SR.NOT_ALL_READ = "Some of your items are not read yet, so the set is not known."
SR.NO_RECIPE = "There is no set recipe by that name."

local WEAPON, FISHING_POLE = 2, 20

-- Each recipe: per slot, the game's item class and subclass a piece has.
local RECIPES = {
    {
        key = "fishing", name = "Fishing", what = "fishing pole", skill = "Fishing",
        slots = { 16 },
        pieces = { [16] = { classID = WEAPON, subclassID = FISHING_POLE } },
    },
}

local function copyRecipe(r)
    local slots = {}
    for i, slot in ipairs(r.slots) do slots[i] = slot end
    return { key = r.key, name = r.name, what = r.what, skill = r.skill, slots = slots }
end

local function find(key)
    for _, r in ipairs(RECIPES) do
        if r.key == key then return r end
    end
    return nil
end

function SR.Get(key)
    local r = find(key)
    if r == nil then return nil end
    return copyRecipe(r)
end

function SR.Keys()
    local out = {}
    for i, r in ipairs(RECIPES) do out[i] = r.key end
    return out
end

function SR.IsPiece(recipe, slot, info)
    local r
    if type(recipe) == "table" then r = find(recipe.key) end
    if r == nil then return false end
    local want = r.pieces[slot]
    if want == nil then return false end
    if type(info) ~= "table" or type(info.classID) ~= "number" or type(info.subclassID) ~= "number" then
        return nil
    end
    return info.classID == want.classID and info.subclassID == want.subclassID
end

local function read(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, value = pcall(client[name], ...)
    if not ok then return nil end
    return value
end

local function hasSkill(client, skill)
    local ranks = read(client, "skillRanks")
    if type(ranks) ~= "table" then return nil end
    return ranks[skill] ~= nil
end

function SR.For(recipe, client)
    local r
    if type(recipe) == "table" then r = find(recipe.key) end
    if r == nil then return nil, SR.NO_RECIPE end
    local worn = read(client, "wornLinks")
    if type(worn) ~= "table" then return nil, SR.CANT_READ_WORN end
    local bags = read(client, "bagItems")
    if type(bags) ~= "table" then return nil, SR.CANT_READ_BAGS end
    local set = { recipe = r.key, skill = hasSkill(client, r.skill), slots = {}, missing = {}, complete = true }
    for _, slot in ipairs(r.slots) do
        local on = worn[slot]
        local wornIs = false
        if type(on) == "string" then
            wornIs = SR.IsPiece(r, slot, read(client, "itemInfo", on))
            if wornIs == nil then return nil, SR.NOT_ALL_READ end
        end
        if wornIs then
            set.slots[slot] = { item = on, where = "worn" }
        else
            local unread = false
            for _, row in ipairs(bags) do
                local item
                if type(row) == "table" then item = row.item end
                if set.slots[slot] == nil and type(item) == "string" then
                    local yes = SR.IsPiece(r, slot, read(client, "itemInfo", item))
                    if yes == nil then
                        unread = true
                    elseif yes then
                        set.slots[slot] = { item = item, where = "bags" }
                    end
                end
            end
            if set.slots[slot] == nil then
                if unread then return nil, SR.NOT_ALL_READ end
                set.missing[#set.missing + 1] = slot
                set.complete = false
            end
        end
    end
    return set
end

local function nameOf(client, item)
    if type(item) ~= "string" then return nil end
    local name = item:match("%[(.-)%]")
    if name and name ~= "" then return name end
    local info = read(client, "itemInfo", item)
    if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
    return "an item"
end

function SR.Swaps(recipe, client)
    local set, why = SR.For(recipe, client)
    if set == nil then return nil, why end
    local r = find(set.recipe)
    local worn = read(client, "wornLinks") or {}
    local out = { rows = {}, wearing = false, missing = set.missing, lines = {} }
    for _, slot in ipairs(r.slots) do
        local pick = set.slots[slot]
        if pick and pick.where ~= "worn" then
            local off = worn[slot]
            if type(off) ~= "string" then off = nil end
            local reason
            if off then
                reason = nameOf(client, pick.item) .. " is in your bags; it goes on in place of " .. nameOf(client, off) .. "."
            else
                reason = nameOf(client, pick.item) .. " is in your bags; it goes on where nothing is worn now."
            end
            out.rows[#out.rows + 1] = { slot = slot, put = pick.item, off = off, where = pick.where, reason = reason }
            out.lines[#out.lines + 1] = reason
        end
    end
    if #set.missing > 0 then
        out.lines[#out.lines + 1] = "You carry no " .. r.what .. ", worn or in your bags."
    elseif #out.rows == 0 then
        out.wearing = true
        out.lines[#out.lines + 1] = "You wear your " .. r.name .. " set already."
    end
    return out
end
