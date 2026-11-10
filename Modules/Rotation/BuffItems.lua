-- Buff items on the Flow key: elixirs, scrolls and flasks you carry, a
-- sharpening stone / weightstone / oil for your weapon, and food that makes
-- you Well Fed. All of them only when you're about to kill a lot: at a kill
-- or loot stop (quest mobs, farming meat or cloth), or right after a fight,
-- and only when that buff isn't on you already (a stone or oil: when your
-- weapon has none). Always out of combat and not in inns or cities.
-- Also WoW: Forever's campfires: near one without its buffs, sit (below).
-- One press uses it (a Flow Action: Rotation/Actions.lua).

local _, ns = ...
local A = ns.api
local BI = {}
ns.buffItems = BI

local RECENT_FIGHT = 45   -- seconds after a fight that still count as "killing here"
local lastFight = -999
ns:On("PLAYER_REGEN_ENABLED", function() lastFight = GetTime() end)

-- Consumable (class 0) kinds that are buffs: 2 elixir, 3 flask, 4 scroll,
-- 5 food and drink (only the kinds that make you Well Fed), 6 item
-- enhancement (stones and oils, on your weapon).
local BUFF_SUB = { [2] = true, [3] = true, [4] = true }
local FOOD_SUB = 5
local ENHANCE_SUB = 6
local WELL_FED = "Well Fed"
BI.WELL_FED = WELL_FED

-- Food that makes you Well Fed says so on its tooltip ("...you will become
-- well fed..."); plain food and drink only heal. lines = the tooltip's text.
function BI.IsBuffFood(lines)
    for _, l in ipairs(lines or {}) do
        if type(l) == "string" and l:lower():find("well fed", 1, true) then return true end
    end
    return false
end

-- Stones and oils by name too, in case the client files one as something
-- other than an item enhancement (item data on Forever can differ from
-- classic). Only real weapon oils: "Oily Blackmouth", "Fire Oil" and "Oil of
-- Immolation" are not.
local OILS = { "Wizard Oil", "Mana Oil", "^Frost Oil$", "^Shadow Oil$" }
function BI.IsWeaponBuff(name)
    if type(name) ~= "string" then return false end
    if name:find("Sharpening Stone") or name:find("Weightstone") then return true end
    for _, o in ipairs(OILS) do
        if name:find(o) then return true end
    end
    return false
end

-- What a weapon enhancement goes on: sharpening stones on edged weapons,
-- weightstones on blunt ones, oils on anything but a fishing pole.
local EDGED = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [13] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true }
local FISHING_POLE = 20
function BI.FitsWeapon(itemName, weaponSub)
    if not weaponSub or weaponSub == FISHING_POLE then return false end
    itemName = itemName or ""
    if itemName:find("Sharpening Stone") then return EDGED[weaponSub] == true end
    if itemName:find("Weightstone") then return BLUNT[weaponSub] == true end
    return itemName:find("Oil") ~= nil
end

-- The item to use now, or nil. items = { { id, sub, name, spell } },
-- active(spell) -> bool, weaponSub (main-hand subclass), enchanted (it has one),
-- killing (about to kill a lot: nothing otherwise). Quick ones first: the
-- elixir, then the stone, then food last (you sit for ten seconds).
function BI.Pick(items, active, weaponSub, enchanted, killing)
    if not killing then return nil end
    for _, it in ipairs(items) do
        if BUFF_SUB[it.sub] and it.spell and not active(it.spell) then return it end
    end
    if not enchanted then
        for _, it in ipairs(items) do
            if it.sub == ENHANCE_SUB and BI.FitsWeapon(it.name, weaponSub) then return it end
        end
    end
    if not active(WELL_FED) then
        for _, it in ipairs(items) do
            if it.sub == FOOD_SUB then return it end
        end
    end
end

local function instant(id)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end

local function itemSpell(id)
    local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not get then return nil end
    local ok, name = pcall(get, id)
    return ok and name or nil
end

-- Is this food the Well Fed kind? Read from its tooltip once per item (nil
-- until the game has the tooltip).
local buffFood = {}
local function isBuffFood(id)
    if buffFood[id] ~= nil then return buffFood[id] end
    local T = C_TooltipInfo
    if not (T and T.GetItemByID) then return false end
    local ok, data = pcall(T.GetItemByID, id)
    if not (ok and data and data.lines and #data.lines > 0) then return nil end
    local lines = {}
    for _, l in ipairs(data.lines) do lines[#lines + 1] = l.leftText end
    buffFood[id] = BI.IsBuffFood(lines)
    return buffFood[id]
end

-- Item names never change: look each one up once (nil until the game has it).
local names = {}
local function nameOf(id)
    local n = names[id]
    if n == nil and A.ItemInfo then
        n = A.ItemInfo(id)
        if n then names[id] = n end
    end
    return n
end

-- Buff items in your bags (usable now). A stone or oil found by its name counts
-- as an item enhancement, whatever the game files it as. Food only when it
-- makes you Well Fed.
local function carried()
    local out, seen = {}, {}
    local C = C_Container
    local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
    local itemAt = (C and C.GetContainerItemID) or GetContainerItemID
    if not (slots and itemAt) then return out end
    for bag = 0, 4 do
        for slot = 1, (slots(bag) or 0) do
            local id = itemAt(bag, slot)
            if id and not seen[id] then
                seen[id] = true
                local _, _, _, _, _, classID, subID = instant(id)
                local name = nameOf(id)
                local sub = (classID == 0 and (BUFF_SUB[subID] or subID == ENHANCE_SUB)) and subID
                    or (BI.IsWeaponBuff(name) and ENHANCE_SUB)
                    or (classID == 0 and subID == FOOD_SUB and isBuffFood(id) and FOOD_SUB) or nil
                if sub and (not A.IsUsableItem or A.IsUsableItem(id)) then
                    out[#out + 1] = { id = id, sub = sub, name = name, spell = itemSpell(id) }
                end
            end
        end
    end
    return out
end

-- About to kill a lot: at a kill / loot stop, or just after a fight.
function BI.Killing(ctx, now)
    if IsResting and IsResting() then return false end
    local g = ctx and ctx.goal
    local kind = g and (g.kind or (ns.nav and ns.nav:StopKind(g)))
    if ctx and ctx.at and (kind == "kill" or kind == "collect") then return true end
    return (now or GetTime()) - lastFight < RECENT_FIGHT
end

local function mainHand()
    local id = GetInventoryItemID and GetInventoryItemID("player", 16)
    if not id then return nil end
    local _, _, _, _, _, classID, subID = instant(id)
    return classID == 2 and subID or nil
end

-- A weapon enhancement goes before the rotation's out-of-combat suggestion
-- (a paladin's seal, an aura), or it would only show when the rotation has
-- nothing at all. Not when an enemy is targeted (the opener first) or you're
-- under half health (the heal first). Order 2.5: before bag:learn (3), which
-- isn't urgent and, coming first, would keep this step off the icon.
function BI.WeaponFirst(enemy, health, maxHealth)
    return not enemy and (health or 0) > 0.5 * (maxHealth or 1)
end

-- WoW: Forever's camps. Near a lit campfire (yours or another player's) you
-- get "Campfire Nearby"; sit there for a minute ("Welcoming Campfire" counts
-- it down) and the camp's buffs land as "Camp Benefits". So: near a fire
-- without the buffs, sit; while the minute runs, wait (a press would stand
-- you up). nearby, benefits, timer: are those auras on you.
local CAMP_NEARBY, CAMP_BENEFITS, CAMP_TIMER = "Campfire Nearby", "Camp Benefits", "Welcoming Campfire"
function BI.CampStep(nearby, benefits, timer)
    if not nearby or benefits then return nil end
    return timer and "wait" or "sit"
end

local function enemyTargeted()
    return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") or false
end

ns:Register("action", "buff:item", { order = 2.5, get = function(ctx)
    if UnitIsDeadOrGhost("player") or (IsResting and IsResting()) then return nil end
    if ctx and ctx.fishing then return nil end
    local items = carried()
    if #items == 0 then return nil end
    local enchanted = GetWeaponEnchantInfo and GetWeaponEnchantInfo() and true or false
    local killing = BI.Killing(ctx)
    local it = BI.Pick(items, function(spell) return (A.Buff("player", spell)) end, mainHand(), enchanted, killing)
    if not it then return nil end
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)) or (GetItemIcon and GetItemIcon(it.id))
    local weapon, food = it.sub == ENHANCE_SUB, it.sub == FOOD_SUB
    return { type = "item", item = "item:" .. it.id, icon = icon,
             targetSlot = weapon and 16 or nil,
             urgent = weapon and BI.WeaponFirst(enemyTargeted(), UnitHealth("player"), UnitHealthMax("player")) or nil,
             label = (weapon and "Put on your weapon: " or food and "Eat: " or "Use: ") .. (it.name or "buff item"),
             reason = weapon and "You're killing here and your weapon has no stone or oil on it"
                 or food and "You're killing here and you aren't Well Fed"
                 or "You're killing here and that buff isn't on" }
end })

-- Sit by a campfire for its buffs (after the buff items: eating sits you
-- down too, and an elixir would stand you up). The key is bound to the
-- game's Sit/Stand while it's the step.
ns:Register("action", "buff:camp", { order = 2.6, get = function(ctx)
    if UnitIsDeadOrGhost("player") or UnitAffectingCombat("player") then return nil end
    if (ctx and ctx.fishing) or (IsMounted and IsMounted()) then return nil end
    local step = BI.CampStep(A.Buff("player", CAMP_NEARBY), A.Buff("player", CAMP_BENEFITS), A.Buff("player", CAMP_TIMER))
    if not step then return nil end
    if step == "wait" then
        return { type = "wait", icon = "Interface\\Icons\\Spell_Fire_Fire", label = "Stay sitting: the camp buffs come after a minute",
                 reason = "You're by a campfire and its minute is counting down" }
    end
    return { type = "sit", icon = "Interface\\Icons\\Spell_Fire_Fire", label = "Sit by the campfire (1 min) for the camp buffs",
             reason = "You're by a campfire and don't have its buffs" }
end })
