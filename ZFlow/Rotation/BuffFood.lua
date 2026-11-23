local _, ns = ...

-- Well Fed food (section 226, CF-30). Pure: no client call here.
-- Ported from Flow's Modules/Rotation/BuffItems.lua (IsBuffFood,
-- WellFedGain, FoodScore, FoodBefore, BestBuffFood) at c44363b. Flow scores
-- by class data; Z-Flow has no class stat weights, so what a stat is worth
-- comes from the role and from whether the pack uses mana (its resources).
-- First guesses, not seen in game on 16001.
--   BuffFood.WELL_FED                  the buff's name
--   BuffFood.CLASS, BuffFood.SUBCLASS  food and drink: consumable (0), 5
--   BuffFood.IsBuffFood(lines)         true when the tooltip says well fed
--   BuffFood.Gain(lines)               { Stamina = 6, Spirit = 6 }, { mp5 = 3 },
--                                      {} when it says no more than well fed
--   BuffFood.UsesMana(pack)            a resources row named Mana
--   BuffFood.Score(gain, role, mana)   a number (0: nothing for you), nil
--                                      when the tooltip does not say
--   BuffFood.Best(foods)               the best of { id, score } rows, or nil;
--                                      one worth nothing is never picked

local BF = {}
ns.BuffFood = BF

BF.WELL_FED = "Well Fed"
BF.CLASS, BF.SUBCLASS = 0, 5

function BF.IsBuffFood(lines)
    for _, l in ipairs(type(lines) == "table" and lines or {}) do
        if type(l) == "string" and l:lower():find("well fed", 1, true) then return true end
    end
    return false
end

local STATS = { stamina = "Stamina", strength = "Strength", agility = "Agility", intellect = "Intellect",
                spirit = "Spirit", attackpower = "AttackPower", spelldamage = "SpellDamage", healing = "Healing" }
local PHRASES = { { "attack power", "attackpower" }, { "spell damage", "spelldamage" }, { "healing done by spells", "healing" },
                  { "spell power", "spelldamage" }, { "healing spells", "healing" } }
-- Words that can stand between stats sharing one "by N": "your Stamina and Spirit by 12".
local LINK = { ["and"] = true, your = true }
local function byAmount(words, i)
    local j = i + 1
    while words[j] and (LINK[words[j]] or STATS[words[j]]) do j = j + 1 end
    if words[j] ~= "by" then return nil end
    j = j + 1
    if words[j] == "up" and words[j + 1] == "to" then j = j + 2 end
    return tonumber(words[j])
end

function BF.Gain(lines)
    local gain = {}
    for _, l in ipairs(type(lines) == "table" and lines or {}) do
        local low = type(l) == "string" and l:lower() or ""
        local at = low:find("well fed", 1, true)
        if at then
            local rest = low:sub(at + 8):gsub(" for %d+ %a+.*$", "")
            for _, p in ipairs(PHRASES) do rest = rest:gsub(p[1], p[2]) end
            local words = {}
            for w in rest:gmatch("[%a%d]+") do words[#words + 1] = w end
            local amount
            for i, w in ipairs(words) do
                local n = tonumber(w)
                if n then
                    amount = n
                elseif STATS[w] then
                    local v = byAmount(words, i) or amount
                    if v then gain[STATS[w]] = v end
                elseif (w == "mana" or w == "health") and amount
                    and (words[i + 1] == "every" or words[i + 1] == "per") and words[i + 2] == "5" then
                    gain[w == "mana" and "mp5" or "hp5"] = amount
                end
            end
        end
    end
    return gain
end

function BF.UsesMana(pack)
    local rows = type(pack) == "table" and pack.resources or nil
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if type(r) == "table" and type(r.name) == "string" and r.name:lower() == "mana" then return true end
    end
    return false
end

-- How much a point of each stat from food is worth, by role (Flow's
-- weights; a meal is for the fights ahead, so staying up counts most).
-- Intellect, mana every 5 seconds, spell damage and healing count only with
-- mana; with mana a dps is weighed as a caster.
local MANA_ONLY = { Intellect = true, mp5 = true, SpellDamage = true, Healing = true }
function BF.Score(gain, role, mana)
    if type(gain) ~= "table" or next(gain) == nil then return nil end
    local w
    if role == "tank" then
        w = { Stamina = 2, Spirit = 0.25, hp5 = 2, Strength = 1, Agility = 1, Intellect = 0.25, mp5 = 0.5,
              AttackPower = 0.25, SpellDamage = 0, Healing = 0 }
    elseif role == "heal" then
        w = { Stamina = 1, Spirit = 0.25, hp5 = 1, Strength = 0, Agility = 0,
              Intellect = 1, mp5 = 3, AttackPower = 0, SpellDamage = 0.25, Healing = 0.5 }
    else
        w = { Stamina = 1.5, Spirit = 0.5, hp5 = 2, Strength = 1, Agility = 1,
              Intellect = mana and 1 or 0.5, mp5 = mana and 2 or 1,
              AttackPower = 0.5, SpellDamage = mana and 1 or 0.25, Healing = 0 }
    end
    local score = 0
    for stat, n in pairs(gain) do
        if type(n) == "number" and (mana or not MANA_ONLY[stat]) then score = score + n * (w[stat] or 0) end
    end
    return score
end

-- A food whose tooltip does not say counts a little, below any known one.
local UNKNOWN_SCORE = 0.1
local function valueOf(it)
    if it.score == nil then return UNKNOWN_SCORE end
    return it.score
end

-- The higher score first, then the lower item id, so the same bags always
-- give the same pick.
function BF.Before(a, b)
    local sa, sb = valueOf(a), valueOf(b)
    if sa ~= sb then return sa > sb end
    return (a.id or 0) < (b.id or 0)
end

function BF.Best(foods)
    local best
    for _, it in ipairs(type(foods) == "table" and foods or {}) do
        if type(it) == "table" and valueOf(it) > 0 and (not best or BF.Before(it, best)) then best = it end
    end
    return best
end
