local _, ns = ...

-- P-FOOD remainder (BASELINE-RECONCILE-2026-11-23 N6, N9, N10, N11), advice
-- only. Pure: no client call, and every suggestion is look = true, so
-- Rotation/Cast.lua never puts it on the key. Ported in spirit from Flow's
-- Modules/Rotation/BuffItems.lua (pre-fight items, recovery order, camps)
-- and Display.lua status icons. First guesses, not seen in game on 16001:
--   FoodAdvice.CAMP_BUFF     the camp buff's name
--   snapshot fields read: inCombat, killStep, enemyNear, weaponEdged,
--   weaponBuffed, buffs, preFight, healthLow, manaLow, have, fireNear,
--   campObjects, durabilityLow
-- Left out on purpose: using the item, placing the camp object, sitting.

local FA = {}
ns.FoodAdvice = FA

FA.CAMP_BUFF = "Campfire Rest"
FA.RECOVER_STEPS = { "bandage", "food", "heal", "drink" }

local function outOfFight(s) return type(s) == "table" and s.inCombat == false end

-- N6: the first pre-fight item worth offering, once per item (seen keeps
-- what was offered). A stone or oil needs an edged weapon with nothing on
-- it; an elixir, flask or scroll needs its buff off you.
function FA.PreFight(s, seen)
    if not outOfFight(s) then return nil end
    if s.killStep ~= true and s.enemyNear ~= true then return nil end
    local buffs = type(s.buffs) == "table" and s.buffs or {}
    seen = type(seen) == "table" and seen or {}
    for _, it in ipairs(type(s.preFight) == "table" and s.preFight or {}) do
        if type(it) == "table" and type(it.name) == "string" and not seen[it.name] then
            local fits
            if it.kind == "stone" or it.kind == "oil" then
                fits = s.weaponEdged == true and s.weaponBuffed ~= true
            else
                fits = type(it.buff) == "string" and not buffs[it.buff]
            end
            if fits then
                seen[it.name] = true
                return { item = it.name, itemId = it.item, kind = it.kind, look = true,
                         reason = "Before the fight: " .. it.name }
            end
        end
    end
    return nil
end

-- N9: the saved order with steps switched off left out; the default order
-- when nothing is saved. A step the saved order does not name is added at
-- the end, so none is lost.
function FA.RecoverOrder(saved)
    local order = type(saved) == "table" and type(saved.order) == "table" and saved.order or FA.RECOVER_STEPS
    local off = type(saved) == "table" and type(saved.off) == "table" and saved.off or {}
    local out, have = {}, {}
    local function add(step)
        if type(step) == "string" and not have[step] and not off[step] then
            have[step] = true
            out[#out + 1] = step
        end
    end
    for _, step in ipairs(order) do add(step) end
    for _, step in ipairs(FA.RECOVER_STEPS) do add(step) end
    return out
end

-- N9: the first step in the saved order that is needed and that you have.
-- Drink is for low mana only; the others for low health.
function FA.Recover(s, saved)
    if not outOfFight(s) then return nil end
    local have = type(s.have) == "table" and s.have or {}
    for _, step in ipairs(FA.RecoverOrder(saved)) do
        local need
        if step == "drink" then need = s.manaLow == true else need = s.healthLow == true end
        if need and type(have[step]) == "string" then
            return { step = step, item = have[step], look = true,
                     reason = "After the fight: " .. have[step] }
        end
    end
    return nil
end

-- N10: near a lit fire without the camp buff: place your camp objects, then
-- sit. The party camp list waits on the party-message investigation (G48).
function FA.Camp(s)
    if not outOfFight(s) or s.fireNear ~= true then return nil end
    local buffs = type(s.buffs) == "table" and s.buffs or {}
    if buffs[FA.CAMP_BUFF] then return nil end
    local steps = {}
    for _, o in ipairs(type(s.campObjects) == "table" and s.campObjects or {}) do
        if type(o) == "string" then steps[#steps + 1] = "place " .. o end
    end
    steps[#steps + 1] = "sit"
    return { steps = steps, look = true, reason = "By the fire: " .. table.concat(steps, ", then ") }
end

-- N11: status icons above the key, in the order registered.
local status = {}
function FA.RegisterStatus(name, shows)
    if type(name) ~= "string" or type(shows) ~= "function" then return end
    FA.UnregisterStatus(name)
    status[#status + 1] = { name = name, shows = shows }
end
function FA.UnregisterStatus(name)
    for i = #status, 1, -1 do
        if status[i].name == name then table.remove(status, i) end
    end
end
function FA.StatusIcons(s)
    local out = {}
    if type(s) ~= "table" then return out end
    for _, e in ipairs(status) do
        if e.shows(s) == true then out[#out + 1] = { name = e.name } end
    end
    return out
end

FA.RegisterStatus("repair", function(s) return s.durabilityLow == true end)
FA.RegisterStatus("camp", function(s)
    return s.fireNear == true and not (type(s.buffs) == "table" and s.buffs[FA.CAMP_BUFF])
end)
