-- Buff items on the Flow key: elixirs, scrolls and flasks you carry, a
-- sharpening stone / weightstone / oil for your weapon, and food that makes
-- you Well Fed. All of them only when you're about to kill a lot: at a kill
-- or loot stop (quest mobs, farming meat or cloth), or right after a fight,
-- and only when that buff isn't on you already (a stone or oil: when your
-- weapon has none). Always out of combat and not in inns or cities.
-- Also WoW: Forever's campfires: near one without its buffs, sit (below),
-- and place the camp objects you carry. And the healing items: a healthstone
-- or potion at low health in a fight, bandages and food after one (the
-- rotation asks for those: Engine.lua, E:Emergency and E:Recover).
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

-- An item's tooltip text, read once per item: nil until the game has the
-- tooltip, {} on a client that can't read tooltips.
local tips = {}
local function tipLines(id)
    if tips[id] then return tips[id] end
    local T = C_TooltipInfo
    if not (T and T.GetItemByID) then return {} end
    local ok, data = pcall(T.GetItemByID, id)
    if not (ok and data and data.lines and #data.lines > 0) then return nil end
    local lines = {}
    for _, l in ipairs(data.lines) do lines[#lines + 1] = l.leftText end
    tips[id] = lines
    return lines
end

-- Is this food the Well Fed kind? (nil until the game has the tooltip)
local function isBuffFood(id)
    local lines = tipLines(id)
    if lines == nil then return nil end
    return BI.IsBuffFood(lines)
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

-- A buff item (stone, oil, elixir, Well Fed food) goes before the rotation's
-- out-of-combat suggestion (a paladin's seal, an aura), or it would only show
-- when the rotation has nothing at all, which for most classes is almost
-- never. Not when an enemy is targeted (the opener first) or you're under
-- half health (the heal first). Health the client hides (a secret value:
-- any comparison errors, and the error kept every buff item off the icon)
-- counts as fine. Order 2.5: before bag:learn (3), which isn't urgent and,
-- coming first, would keep this step off the icon.
function BI.WeaponFirst(enemy, health, maxHealth)
    if enemy then return false end
    health, maxHealth = A.Safe(health), A.Safe(maxHealth)
    if not (health and maxHealth and maxHealth > 0) then return true end
    return health > 0.5 * maxHealth
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
             urgent = BI.WeaponFirst(enemyTargeted(), UnitHealth("player"), UnitHealthMax("player")),
             label = (weapon and "Put on your weapon: " or food and "Eat: " or "Use: ") .. (it.name or "buff item"),
             reason = weapon and "You're killing here and your weapon has no stone or oil on it"
                 or food and "You're killing here and you aren't Well Fed"
                 or "You're killing here and that buff isn't on" }
end })

-------------------------------------------------------------------------------
-- Bag helpers (camp objects and healing items)
-------------------------------------------------------------------------------

local function eachBagItem(fn)
    local C = C_Container
    local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
    local itemAt = (C and C.GetContainerItemID) or GetContainerItemID
    if not (slots and itemAt) then return end
    local seen = {}
    for bag = 0, 4 do
        for slot = 1, (slots(bag) or 0) do
            local id = itemAt(bag, slot)
            if id and not seen[id] then seen[id] = true; fn(id) end
        end
    end
end

-- Usable now and off its cooldown.
local function itemReady(id)
    if A.IsUsableItem and not A.IsUsableItem(id) then return false end
    local cd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if cd then
        local ok, start, dur = pcall(cd, id)
        start, dur = ok and A.Safe(start), ok and A.Safe(dur)
        if start and dur and start > 0 and dur > 1.5 then return false end
    end
    return true
end

local function itemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
end

-- Your bag items by name (cleared when your bags change).
local bagNames
local function bagByName()
    if bagNames then return bagNames end
    local out, complete = {}, true
    eachBagItem(function(id)
        local n = nameOf(id)
        if n then out[n] = id else complete = false end
    end)
    if complete then bagNames = out end
    return out
end

-------------------------------------------------------------------------------
-- Campfires
-------------------------------------------------------------------------------

-- WoW: Forever's camps. Near a lit campfire (yours or another player's) you
-- get "Campfire Nearby"; sit there for a minute ("Welcoming Campfire" counts
-- it down) and the camp's buffs land as "Camp Benefits". Camp objects (a
-- tent, a lute, a mana well...) placed by the fire add to those buffs.
-- So, near a fire: while the minute runs, wait (a press would stand you
-- up); else place a camp object you carry that's ready; then, without the
-- buffs (or right after placing one, so the buffs include it), sit.
-- nearby, benefits, timer: are those auras on you; kit: an object to place;
-- fresh: you just placed one.
local CAMP_NEARBY, CAMP_BENEFITS, CAMP_TIMER = "Campfire Nearby", "Camp Benefits", "Welcoming Campfire"
local CAMP_ICON = "Interface\\Icons\\Spell_Fire_Fire"
function BI.CampStep(nearby, benefits, timer, kit, fresh)
    if not nearby then return nil end
    if timer then return "wait" end
    if kit then return "place" end
    if benefits and not fresh then return nil end
    return "sit"
end

-- WoW: Forever's camp objects, by name: a spell you know or an item you carry.
BI.CAMP_KITS = { "Camp Tent", "Mana Well", "Sharpening Wheel", "Enchanted Lute", "First Aid Kit",
                 "Fish Bowl", "Incense Candle", "Lodestone", "Camp Chair", "Faction Banner", "Cookie's Feast" }
local KIT_AGAIN = 3600     -- one placed counts as out for an hour (it stays up a while)
local PARTY_FRESH = 120    -- a party member's list counts for 2 minutes
local placed = {}          -- kit name -> GetTime() you placed it
local castNames = {}       -- the spell an item casts -> its kit name
local fresh, freshTimer    -- GetTime() you last placed one; its minute seen
local isKit = {}
for _, k in ipairs(BI.CAMP_KITS) do isKit[k] = true end

-- The camp objects you could place now: { name, spell } or { name, item, id }.
function BI.CampKits(now)
    now = now or GetTime()
    local out, bag = {}, nil
    for _, kit in ipairs(BI.CAMP_KITS) do
        if not (placed[kit] and now - placed[kit] < KIT_AGAIN) then
            if ns.rotation and ns.rotation:Ready(kit) then
                out[#out + 1] = { name = kit, spell = kit }
            else
                bag = bag or bagByName()
                local id = bag[kit]
                if id and itemReady(id) then
                    castNames[itemSpell(id) or kit] = kit
                    out[#out + 1] = { name = kit, item = "item:" .. id, id = id }
                end
            end
        end
    end
    return out
end

-- What your party can add, from the lists their Flow sends:
-- entries = { [sender] = { kits = {names}, at = time } }. "Mia: Camp Tent; ..."
function BI.PartyKitText(entries, now)
    local who = {}
    for name, e in pairs(entries or {}) do
        if e.at and now - e.at < PARTY_FRESH and e.kits and #e.kits > 0 then who[#who + 1] = name end
    end
    if #who == 0 then return nil end
    table.sort(who)
    local parts = {}
    for _, name in ipairs(who) do
        parts[#parts + 1] = (name:gsub("%-.*$", "")) .. ": " .. table.concat(entries[name].kits, ", ")
    end
    return table.concat(parts, "; ")
end

-- Party members running Flow: each tells the group which camp objects it
-- could place (only while by a fire, at most every 30 s unless it changed).
local partyKits = {}
local lastShare, lastShareText = -999, nil
local function shareKits(kits, now)
    local P = ns.party
    if not (P and P.Send and P.InGroup and P:InGroup()) then return end
    local names = {}
    for _, k in ipairs(kits) do names[#names + 1] = k.name end
    local text = table.concat(names, ",")
    if text == lastShareText and now - lastShare < 30 then return end
    lastShare, lastShareText = now, text
    P.Send("K|" .. text)
end

ns:On("BAG_UPDATE_DELAYED", function() bagNames = nil end)

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if not name then return end
    if name == "First Aid" then BI.bandagedAt = GetTime() end   -- (a bandage)
    local kit = castNames[name] or (isKit[name] and name)
    if kit then
        placed[kit], fresh, freshTimer = GetTime(), GetTime(), nil
        lastShareText = nil   -- tell the group at once
    end
end)

ns:OnLoad(function()
    local P = ns.party
    if not (P and P.handlers) then return end
    P.handlers.K = function(sender, rest)
        local short = (Ambiguate and Ambiguate(sender, "short")) or sender
        if short == UnitName("player") then return end
        local kits = {}
        for n in tostring(rest or ""):gmatch("[^,]+") do kits[#kits + 1] = n end
        local text = table.concat(kits, ", ")
        partyKits[short] = { kits = kits, at = GetTime(), text = text }
    end
end)

-- By a fire: a status icon above Flow's key when your group could add camp
-- objects (hover: who has what).
function BI.PartyKitStatus(entries, now)
    local text = BI.PartyKitText(entries, now)
    if not text then return nil end
    local n = 0
    for _, e in pairs(entries) do
        if e.at and now - e.at < PARTY_FRESH and e.kits then n = n + #e.kits end
    end
    return { icon = CAMP_ICON, text = tostring(n), color = { 0.35, 0.75, 1.0 },
             tip = "Your group can add to this camp: " .. text }
end
ns:Register("status", "camp", { order = 30, get = function()
    if not A.Buff("player", CAMP_NEARBY) then return nil end
    return BI.PartyKitStatus(partyKits, GetTime())
end })

-- At a campfire: place your camp objects, then sit for the buffs (after the
-- buff items: eating sits you down too, and an elixir would stand you up).
-- The key is bound to the game's Sit/Stand while sitting is the step.
ns:Register("action", "buff:camp", { order = 2.6, get = function(ctx)
    if UnitIsDeadOrGhost("player") or UnitAffectingCombat("player") then return nil end
    if (ctx and ctx.fishing) or (IsMounted and IsMounted()) then return nil end
    if not A.Buff("player", CAMP_NEARBY) then return nil end
    local now = GetTime()
    local timer = A.Buff("player", CAMP_TIMER)
    -- Just placed one: sit again for its buffs, until that minute is over.
    if fresh then
        if timer then freshTimer = true
        elseif freshTimer or now - fresh > PARTY_FRESH then fresh, freshTimer = nil, nil end
    end
    local kits = ns.db.rotation.campKits ~= false and BI.CampKits(now) or {}
    shareKits(kits, now)
    local step = BI.CampStep(true, A.Buff("player", CAMP_BENEFITS), timer, kits[1], fresh)
    if not step then return nil end
    local others = BI.PartyKitText(partyKits, now)
    local group = others and (". Your group can add: " .. others) or ""
    if step == "wait" then
        return { type = "wait", icon = CAMP_ICON, label = "Stay sitting: the camp buffs come after a minute",
                 reason = "You're by a campfire and its minute is counting down" .. group }
    end
    if step == "place" then
        local k = kits[1]
        local a = { label = "Place your " .. k.name .. " at the camp",
                    reason = "You're by a campfire: your " .. k.name .. " adds to its buffs" .. group }
        if k.spell then
            a.type, a.spell, a.unit = "spell", k.spell, "player"
            a.icon = select(2, A.SpellInfo(k.spell)) or CAMP_ICON
        else
            a.type, a.item, a.icon = "item", k.item, itemIcon(k.id) or CAMP_ICON
        end
        return a
    end
    return { type = "sit", icon = CAMP_ICON, label = "Sit by the campfire (1 min) for the camp buffs",
             reason = (fresh and "You placed a camp object: sit again so the buffs include it"
                 or "You're by a campfire and don't have its buffs") .. group }
end })

-------------------------------------------------------------------------------
-- Healing items: healthstones, healing potions, bandages, food
-------------------------------------------------------------------------------

local POTION_SUB, BANDAGE_SUB = 1, 7
BI.RECENTLY_BANDAGED = "Recently Bandaged"
local BANDAGE_DEBUFF = 60

-- What a bag item is for healing: "healthstone", "potion", "bandage",
-- "food" or nil. lines = its tooltip text (food: only the kind that heals;
-- Well Fed food is left for the buff step above).
function BI.HealKind(name, classID, subID, lines)
    name = name or ""
    if name:find("Healthstone") then return "healthstone" end
    if name:find("Healing Potion") or (classID == 0 and subID == POTION_SUB and name:find("Healing")) then return "potion" end
    if name:find("Bandage") or (classID == 0 and subID == BANDAGE_SUB) then return "bandage" end
    if classID == 0 and subID == FOOD_SUB and lines and not BI.IsBuffFood(lines) then
        for _, l in ipairs(lines) do
            if type(l) == "string" and l:lower():find("health", 1, true) then return "food" end
        end
    end
    return nil
end

-- Higher rank = a bigger heal: item level, then the level it needs.
local function rankOf(id)
    if not A.ItemInfo then return 0 end
    local ok, _, _, _, ilvl, req = pcall(A.ItemInfo, id)
    if not ok then return 0 end
    return (tonumber(ilvl) or 0) + (tonumber(req) or 0) / 1000
end

-- The healing items in your bags: { id, kind, name, rank } (cleared when
-- your bags change; not kept while the game is still loading a name).
local healCache
local function healItems()
    if healCache then return healCache end
    local out, complete = {}, true
    eachBagItem(function(id)
        local _, _, _, _, _, classID, subID = instant(id)
        if classID ~= 0 then return end
        local name = nameOf(id)
        if not name then complete = false return end
        local lines
        if subID == FOOD_SUB then
            lines = tipLines(id)
            if lines == nil then complete = false end
        end
        local kind = BI.HealKind(name, classID, subID, lines)
        if kind then out[#out + 1] = { id = id, kind = kind, name = name, rank = rankOf(id) } end
    end)
    if complete then healCache = out end
    return out
end
ns:On("BAG_UPDATE_DELAYED", function() healCache = nil end)
ns:On("GET_ITEM_INFO_RECEIVED", function() healCache, bagNames = nil, nil end)

-- The item of this kind to use: the highest rank, or the lowest with
-- lowFirst. ready(id) -> bool (nil: all count).
function BI.PickKind(items, kind, lowFirst, ready)
    local best
    for _, it in ipairs(items or {}) do
        if it.kind == kind and (not ready or ready(it.id)) then
            if not best or (lowFirst and it.rank < best.rank) or (not lowFirst and it.rank > best.rank) then best = it end
        end
    end
    return best
end

-- In a fight: a healthstone first (it costs nothing), then a potion.
function BI.PickEmergency(items, ready)
    return BI.PickKind(items, "healthstone", false, ready) or BI.PickKind(items, "potion", false, ready)
end

-- After a fight: your order of recovery steps. str = "bandage,food,heal"
-- (Saved in ns.db.rotation.recoverOrder); unknown words dropped, missing
-- steps added at the end.
BI.RECOVER_STEPS = { "bandage", "food", "heal" }
BI.RECOVER_NAMES = { bandage = "Bandage", food = "Food", heal = "Heal spell" }
function BI.Order(str)
    local out, seen = {}, {}
    for w in tostring(str or ""):gmatch("[^,%s]+") do
        if BI.RECOVER_NAMES[w] and not seen[w] then seen[w] = true; out[#out + 1] = w end
    end
    for _, w in ipairs(BI.RECOVER_STEPS) do
        if not seen[w] then out[#out + 1] = w end
    end
    return out
end

-- "Recently Bandaged" on you: no bandage for a minute.
local function bandaged()
    if BI.bandagedAt and GetTime() - BI.bandagedAt < BANDAGE_DEBUFF then return true end
    local U = C_UnitAuras
    if not (U and U.GetAuraDataByIndex) then return false end
    for i = 1, 40 do
        local ok, a = pcall(U.GetAuraDataByIndex, "player", i, "HARMFUL")
        if not (ok and a) then break end
        if A.Safe(a.name) == BI.RECENTLY_BANDAGED then return true end
    end
    return false
end

local function useStep(it, kind, label, reason, unit)
    return { type = "item", item = "item:" .. it.id, icon = itemIcon(it.id), kind = kind,
             unit = unit, label = label, reason = reason }
end

function BI.EmergencyStep()
    local it = BI.PickEmergency(healItems(), itemReady)
    if not it then return nil end
    return useStep(it, "emergency", it.kind == "healthstone" and "Healthstone!" or "Healing potion!",
        "Low health: use your " .. it.name .. " now (press it on your bar: the key is locked in a fight)")
end

function BI.BandageStep(lowFirst)
    if bandaged() then return nil end
    local it = BI.PickKind(healItems(), "bandage", lowFirst, itemReady)
    if not it then return nil end
    return useStep(it, "heal", "Bandage: " .. it.name,
        "Hurt after your fight: bandage up (stand still while it heals)", "player")
end

function BI.FoodStep()
    local it = BI.PickKind(healItems(), "food", false, itemReady)
    if not it then return nil end
    return useStep(it, "heal", "Eat: " .. it.name, "Hurt after your fight: eat to heal up")
end

-- Right-click on the Flow key: what it does after a fight, and when to use
-- items. Saved in ns.db.rotation; everything on unless turned off.
local ORDERS = {
    { "bandage", "food", "heal" }, { "bandage", "heal", "food" }, { "food", "bandage", "heal" },
    { "food", "heal", "bandage" }, { "heal", "bandage", "food" }, { "heal", "food", "bandage" },
}
function BI:OpenMenu()
    if not ns.menu then return end
    local r = ns.db.rotation
    local cur = table.concat(BI.Order(r.recoverOrder), ",")
    local items = { { title = true, text = "Flow key: after a fight" } }
    for _, o in ipairs(ORDERS) do
        local key = table.concat(o, ",")
        local names = {}
        for i, w in ipairs(o) do names[i] = BI.RECOVER_NAMES[w] end
        items[#items + 1] = { text = table.concat(names, " > "), radio = true, checked = key == cur,
                              func = function() r.recoverOrder = key end }
    end
    local function toggle(text, key)
        return { text = text, checked = r[key] ~= false, func = function() r[key] = (r[key] == false) end }
    end
    items[#items + 1] = toggle("Use bandages", "recoverBandage")
    items[#items + 1] = toggle("Eat food", "recoverFood")
    items[#items + 1] = toggle("Cast heals", "recoverHeal")
    items[#items + 1] = { sep = true }
    items[#items + 1] = { title = true, text = "Bandages" }
    items[#items + 1] = { text = "Best bandage first", radio = true, checked = r.bandageRank ~= "low",
                          func = function() r.bandageRank = "high" end }
    items[#items + 1] = { text = "Lowest bandage first", radio = true, checked = r.bandageRank == "low",
                          func = function() r.bandageRank = "low" end }
    items[#items + 1] = { sep = true }
    items[#items + 1] = toggle("In a fight: Healthstone, then potion", "emergencyItems")
    items[#items + 1] = toggle("Place my camp objects at campfires", "campKits")
    items[#items + 1] = toggle("Status icons above the key", "statusIcons")
    ns.menu:Open(items)
end
