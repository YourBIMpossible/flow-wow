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
-- killing (about to kill a lot: nothing otherwise). Well Fed food first (it
-- lasts longest and you sit to eat, so do it before the quick ones), then
-- the elixir, then the stone.
function BI.Pick(items, active, weaponSub, enchanted, killing)
    if not killing then return nil end
    if not active(WELL_FED) then
        for _, it in ipairs(items) do
            if it.sub == FOOD_SUB then return it end
        end
    end
    for _, it in ipairs(items) do
        if BUFF_SUB[it.sub] and it.spell and not active(it.spell) then return it end
    end
    if not enchanted then
        for _, it in ipairs(items) do
            if it.sub == ENHANCE_SUB and BI.FitsWeapon(it.name, weaponSub) then return it end
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
-- makes you Well Fed. Kept until your bags change (or an item's details
-- arrive, or you level): the buff steps ask several times a second.
local carriedCache
local function carried()
    if carriedCache then return carriedCache end
    local out, seen = {}, {}
    local C = C_Container
    local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
    local itemAt = (C and C.GetContainerItemID) or GetContainerItemID
    if not (slots and itemAt) then return out end
    carriedCache = out
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
-- never. Not when an enemy is targeted (the opener first) or you're hurt (the
-- heal first). WoW: Forever hides your health, and testing the hidden value
-- errors (the step then never showed): it goes through ns.api.Safe, and
-- unknown health goes by Flow's own estimate of how hurt you are (hurtHigh).
-- Order 2.5: before bag:learn (3), which isn't urgent and, coming first,
-- would keep this step off the icon.
function BI.WeaponFirst(enemy, health, maxHealth, hurtHigh)
    if enemy then return false end
    health, maxHealth = A.Safe(health), A.Safe(maxHealth)
    if health and maxHealth and maxHealth > 0 then return health > 0.5 * maxHealth end
    return not hurtHigh
end

local function enemyTargeted()
    return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") or false
end

-- A fight is near: you're about to kill a lot (BI.Killing) or an enemy is
-- targeted. The buff button lights up its buff only then.
function BI.FightNear(ctx, now)
    return BI.Killing(ctx, now) or enemyTargeted()
end

-- The buff item step. preview: also when no fight is near (the buff button
-- shows the next one, faded, so you can pick your moment); the step then has
-- soon = true. Without preview, nothing until you're about to fight, so the
-- bags aren't read ten times a second for nothing.
function BI.ItemStep(ctx, preview)
    if UnitIsDeadOrGhost("player") or (not preview and IsResting and IsResting()) then return nil end
    if ctx and ctx.fishing then return nil end
    local killing = BI.Killing(ctx)
    if not killing and not preview then return nil end
    local items = carried()
    if #items == 0 then return nil end
    local enchanted = GetWeaponEnchantInfo and GetWeaponEnchantInfo() and true or false
    local it = BI.Pick(items, function(spell) return (A.Buff("player", spell)) end, mainHand(), enchanted, true)
    if not it then return nil end
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)) or (GetItemIcon and GetItemIcon(it.id))
    local weapon, food = it.sub == ENHANCE_SUB, it.sub == FOOD_SUB
    local why = killing and "You're killing here" or "Next time you fight"
    return { type = "item", item = "item:" .. it.id, icon = icon,
             targetSlot = weapon and 16 or nil, soon = not killing or nil, wellFed = food or nil,
             urgent = BI.WeaponFirst(enemyTargeted(), UnitHealth("player"), UnitHealthMax("player"),
                 ns.rotation and (ns.rotation.hurt or 0) >= ns.rotation.HURT.outStart),
             label = (weapon and "Put on your weapon: " or food and "Eat: " or "Use: ") .. (it.name or "buff item"),
             reason = weapon and (why .. ": your weapon has no stone or oil on it")
                 or food and (why .. ": you aren't Well Fed")
                 or (why .. ": that buff isn't on") }
end

ns:Register("action", "buff:item", { order = 2.5, get = function(ctx) return BI.ItemStep(ctx, false) end })

-- The buff items you carry whose buff is on now, each with its time left:
-- { { step, left } }. A stone or oil: the time left on your weapon; food:
-- Well Fed; an elixir, scroll or flask: its buff. The buff button shows the
-- one running out first when nothing is due.
function BI.UpcomingItems()
    if UnitIsDeadOrGhost("player") then return {} end
    local out = {}
    local has, mhExp
    if GetWeaponEnchantInfo then has, mhExp = GetWeaponEnchantInfo() end
    has, mhExp = A.Safe(has), A.Safe(mhExp)
    local sub = mainHand()
    for _, it in ipairs(carried()) do
        local left, weapon, food
        if it.sub == ENHANCE_SUB then
            weapon = true
            if has and mhExp and BI.FitsWeapon(it.name, sub) then left = mhExp / 1000 end
        elseif it.sub == FOOD_SUB then
            food = true
            local on, l = A.Buff("player", WELL_FED)
            if on then left = l end
        elseif it.spell then
            local on, l = A.Buff("player", it.spell)
            if on then left = l end
        end
        if left then
            local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)) or (GetItemIcon and GetItemIcon(it.id))
            out[#out + 1] = { left = left, step = { type = "item", item = "item:" .. it.id, icon = icon,
                targetSlot = weapon and 16 or nil,
                label = (weapon and "Put on your weapon: " or food and "Eat: " or "Use: ") .. (it.name or "buff item"),
                reason = weapon and "Your weapon's stone or oil is still on: renew it when you choose"
                    or food and "Still Well Fed: eat again when you choose"
                    or "That buff is still on: renew it when you choose" } }
        end
    end
    return out
end

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
-- (These names are the ones the camp objects had when this was written; the
-- game gives addons no list of them. /flow log shows what Flow saw by a fire.)
local CAMP_SAME = 60       -- away from the fire this long: the next fire is another camp
local PARTY_FRESH = 120    -- a party member's list counts for 2 minutes
local placed = {}          -- kit name -> the camp visit you placed it in
local visit, lastNear = 0, nil   -- which camp visit this is; GetTime() last by a fire

-- The game doesn't say which camp a fire is, or how long an object stays
-- up. So "placed" means only: you placed it during this visit to a fire.
-- Leave for a minute and it's a new visit; from then on the object's own
-- cooldown (as the game reports it) decides whether it's offered again.
function BI.CampVisit(n, lastNearAt, now)
    if not lastNearAt or now - lastNearAt > CAMP_SAME then return n + 1 end
    return n
end

-- One camp object, for you: "placed" (by you, this visit), "ready" (you
-- have it and can place it now), "notready" (you have it: cooldown or not
-- usable), nil (you don't have it).
function BI.KitState(placedHere, have, ready)
    if not have then return nil end
    if placedHere then return "placed" end
    return ready and "ready" or "notready"
end
local KIT_WORD = { placed = "placed", ready = "ready", notready = "not ready" }
function BI.KitStateText(states)
    local parts = {}
    for _, s in ipairs(states or {}) do parts[#parts + 1] = s.name .. " (" .. (KIT_WORD[s.state] or "?") .. ")" end
    return #parts > 0 and table.concat(parts, ", ") or nil
end
local castNames = {}       -- the spell an item casts -> its kit name
local fresh, freshTimer    -- GetTime() you last placed one; its minute seen
local isKit = {}
for _, k in ipairs(BI.CAMP_KITS) do isKit[k] = true end

-- The camp objects you could place now: { name, spell } or { name, item, id }.
-- Second return: every camp object you have, with its state (KitState).
function BI.CampKits()
    local out, states, bag = {}, {}, nil
    local E = ns.rotation
    for _, kit in ipairs(BI.CAMP_KITS) do
        local here = placed[kit] == visit
        local known = E and E.Knows and E:Knows(kit)
        local ready, entry
        if E and E:Ready(kit) then
            ready, entry = true, { name = kit, spell = kit }
        elseif not known then
            bag = bag or bagByName()
            local id = bag[kit]
            if id then
                known = true
                castNames[itemSpell(id) or kit] = kit
                if itemReady(id) then ready, entry = true, { name = kit, item = "item:" .. id, id = id } end
            end
        end
        local state = BI.KitState(here, known or ready, ready)
        if state then states[#states + 1] = { name = kit, state = state } end
        if state == "ready" then out[#out + 1] = entry end
    end
    return out, states
end

-- What your party can add, from the lists their Flow sends:
-- entries = { [sender] = { kits = {names}, at = time } }. "Mia: Camp Tent; ..."
-- roster (optional) = your party now: { { name, near } }, near = true (in
-- range of you), false (not), nil (the game won't say). With it: people who
-- left are dropped, someone out of range isn't counted for this camp, and
-- the second return lists the rest: "Bob: elsewhere; Cid: unknown" (no fresh
-- list means unknown, not "has nothing").
local function short(name) return (tostring(name):gsub("%-.*$", "")) end
function BI.PartyKitText(entries, now, roster)
    local near, inParty
    if roster then
        near, inParty = {}, {}
        for _, m in ipairs(roster) do inParty[short(m.name)] = true; near[short(m.name)] = m.near end
    end
    local who, far, seen = {}, {}, {}
    for name, e in pairs(entries or {}) do
        local s = short(name)
        if e.at and now - e.at < PARTY_FRESH and e.kits and (not roster or inParty[s]) then
            seen[s] = true
            if roster and near[s] == false then far[#far + 1] = s .. ": elsewhere"
            elseif #e.kits > 0 then who[#who + 1] = name end
        end
    end
    for _, m in ipairs(roster or {}) do
        local s = short(m.name)
        if not seen[s] then far[#far + 1] = s .. ": unknown" end
    end
    table.sort(who); table.sort(far)
    local parts = {}
    for _, name in ipairs(who) do
        local s = short(name)
        parts[#parts + 1] = s .. (roster and near[s] == nil and " (place unknown)" or "") .. ": " .. table.concat(entries[name].kits, ", ")
    end
    return #parts > 0 and table.concat(parts, "; ") or nil, #far > 0 and table.concat(far, "; ") or nil
end

-- Your group now (not you): { { name, near } }. near: the game's own range
-- check on a group member (about 40 yards), nil when it gives no answer. In
-- a raid, every raid member (party1-4 is only your own subgroup), so the
-- camp lists of the others aren't dropped. Values the game hides count as
-- unknown (ns.api.Safe).
function BI.PartyRoster()
    local out = {}
    local raid = IsInRaid and IsInRaid()
    local n = raid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or 4
    for i = 1, n do
        local unit = (raid and "raid" or "party") .. i
        local me = A.Safe(UnitIsUnit and UnitIsUnit(unit, "player"))
        local name = not me and A.Safe(UnitExists and UnitExists(unit)) and A.Safe(UnitName(unit))
        if name then
            local near
            if UnitInRange then
                local ok, inRange, checked = pcall(UnitInRange, unit)
                inRange, checked = ok and A.Safe(inRange), ok and A.Safe(checked)
                if checked then near = inRange and true or false end
            end
            out[#out + 1] = { name = name, near = near }
        end
    end
    return out
end

-- Lists from people no longer in your party are dropped.
function BI.PruneParty(entries, roster)
    local keep = {}
    for _, m in ipairs(roster or {}) do keep[short(m.name)] = true end
    for name in pairs(entries) do
        if not keep[short(name)] then entries[name] = nil end
    end
    return entries
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

ns:On("BAG_UPDATE_DELAYED", function() bagNames, carriedCache = nil, nil end)
ns:On("PLAYER_LEVEL_UP", function() carriedCache = nil end)

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if not name then return end
    local kit = castNames[name] or (isKit[name] and name)
    if kit then
        placed[kit], fresh, freshTimer = visit, GetTime(), nil
        lastShareText = nil   -- tell the group at once
        ns:Log("camp", string.format("placed %s (spell %s, id %s), camp visit %d", kit, name, tostring(A.Safe(spellID)), visit))
    end
end)
ns:On("GROUP_ROSTER_UPDATE", function() BI.PruneParty(partyKits, BI.PartyRoster()) end)

-- A bandage is a channel named "First Aid". The First Aid profession window
-- is opened by a spell of the same name, but that's no channel, so it no
-- longer counts as bandaging (it used to skip the bandage step for a minute).
ns:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if unit ~= "player" then return end
    if ns.rotation.IsBandage(A.SpellInfo(A.Safe(spellID) or 0)) then BI.bandagedAt = GetTime() end
end)

-- A party member's "K|Camp Tent,Enchanted Lute": only camp object names
-- Flow knows are kept (it's shown in your tooltip), each once.
function BI.ParseKits(rest)
    local kits, seen = {}, {}
    for n in tostring(rest or ""):gmatch("[^,]+") do
        n = n:match("^%s*(.-)%s*$")
        if isKit[n] and not seen[n] then seen[n] = true; kits[#kits + 1] = n end
    end
    return kits
end
ns:OnLoad(function()
    local P = ns.party
    if not (P and P.handlers) then return end
    P.handlers.K = function(sender, rest)
        local short = (Ambiguate and Ambiguate(sender, "short")) or sender
        if short == UnitName("player") then return end
        local kits = BI.ParseKits(rest)
        partyKits[short] = { kits = kits, at = GetTime(), text = table.concat(kits, ", ") }
    end
end)

-- By a fire: a status icon above Flow's key when your group could add camp
-- objects (hover: who has what).
-- mine (optional) = your own objects' states (CampKits' second return).
function BI.PartyKitStatus(entries, now, roster, mine)
    local text, rest = BI.PartyKitText(entries, now, roster)
    if not text then return nil end
    local n = 0
    for _ in text:gmatch("[^;,]+") do n = n + 1 end
    local tip = "Near you, your group says it can place: " .. text
    if rest then tip = tip .. "\nNot counted: " .. rest end
    local own = BI.KitStateText(mine)
    if own then tip = tip .. "\nYours: " .. own end
    return { icon = CAMP_ICON, text = tostring(n), color = { 0.35, 0.75, 1.0 }, tip = tip }
end
ns:Register("status", "camp", { order = 30, get = function()
    if not A.Buff("player", CAMP_NEARBY) then return nil end
    local _, mine = BI.CampKits()
    return BI.PartyKitStatus(partyKits, GetTime(), BI.PartyRoster(), mine)
end })

-- At a campfire: place your camp objects, then sit for the buffs (after the
-- buff items: eating sits you down too, and an elixir would stand you up).
-- The key is bound to the game's Sit/Stand while sitting is the step.
ns:Register("action", "buff:camp", { order = 2.6, get = function(ctx)
    if UnitIsDeadOrGhost("player") or UnitAffectingCombat("player") then return nil end
    if (ctx and ctx.fishing) or (IsMounted and IsMounted()) then return nil end
    if not A.Buff("player", CAMP_NEARBY) then return nil end
    local now = GetTime()
    local v = BI.CampVisit(visit, lastNear, now)
    lastNear = now
    local timer = A.Buff("player", CAMP_TIMER)
    if v ~= visit then
        visit = v
        local _, st = BI.CampKits()
        ns:Log("camp", string.format("by a fire (visit %d): benefits %s, minute running %s; yours: %s", visit,
            tostring(A.Buff("player", CAMP_BENEFITS) and true or false), tostring(timer and true or false),
            BI.KitStateText(st) or "no camp objects found by name"))
    end
    -- Just placed one: sit again for its buffs, until that minute is over.
    if fresh then
        if timer then freshTimer = true
        elseif freshTimer or now - fresh > PARTY_FRESH then fresh, freshTimer = nil, nil end
    end
    local kits = ns.db.rotation.campKits ~= false and BI.CampKits() or {}
    shareKits(kits, now)
    local step = BI.CampStep(true, A.Buff("player", CAMP_BENEFITS), timer, kits[1], fresh)
    if not step then return nil end
    local others = BI.PartyKitText(partyKits, now, BI.PartyRoster())
    local group = others and (". Near you, your group says it can place: " .. others) or ""
    -- Sitting and waiting are urgent: otherwise the rotation's own
    -- suggestion (a seal, a bandage) takes the key, and pressing it stands
    -- you up and loses the minute.
    if step == "wait" then
        return { type = "wait", urgent = true, icon = CAMP_ICON, label = "Stay sitting: the camp buffs come after a minute",
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
    return { type = "sit", urgent = true, icon = CAMP_ICON, label = "Sit by the campfire (1 min) for the camp buffs",
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
-- "food" or nil. lines = its tooltip text (food: only the kind that heals).
-- Healing and Well Fed are separate things a food can do: the second return
-- is true for food that also makes you Well Fed (eaten to heal only when
-- there's no plain food, and only if you allow it).
function BI.HealKind(name, classID, subID, lines)
    name = name or ""
    if name:find("Healthstone") then return "healthstone" end
    if name:find("Healing Potion") or (classID == 0 and subID == POTION_SUB and name:find("Healing")) then return "potion" end
    if name:find("Bandage") or (classID == 0 and subID == BANDAGE_SUB) then return "bandage" end
    if classID == 0 and subID == FOOD_SUB and lines then
        local mana = false
        for _, l in ipairs(lines) do
            local low = type(l) == "string" and l:lower() or ""
            if low:find("health", 1, true) then return "food", BI.IsBuffFood(lines) and true or false end
            if low:find("restores %d+ mana") then mana = true end
        end
        -- Water and the like ("Restores 151 mana over 21 sec."): drink.
        if mana then return "drink", false end
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
        local kind, buff = BI.HealKind(name, classID, subID, lines)
        if kind then out[#out + 1] = { id = id, kind = kind, name = name, rank = rankOf(id), buff = buff or nil } end
    end)
    if complete then healCache = out end
    return out
end
ns:On("BAG_UPDATE_DELAYED", function() healCache = nil end)
ns:On("GET_ITEM_INFO_RECEIVED", function() healCache, bagNames, carriedCache = nil, nil, nil end)

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

-- Only one you can press in a fight: on your bars, or the one Alt + your key
-- is set to. (The key itself is locked to its spell, so a healthstone you
-- can't press anywhere is advice you can't act on.)
local function readyToPress(id)
    if not itemReady(id) then return false end
    if not ns.ItemOnBar or ns.ItemOnBar(id) then return true end
    local C = ns.cast
    return C ~= nil and C.EmergencyItem ~= nil and C:EmergencyItem() == "item:" .. id
end

-- The healthstone (else healing potion) you carry, usable right now or not:
-- what Alt + your key is set to before a fight.
function BI.EmergencyCarry() return BI.PickEmergency(healItems()) end

-- How to press it: Alt + your key when that's the item set on it, else from
-- your bar or bag (the key itself can't change in a fight).
function BI.EmergencyHow(item, altItem, altKey)
    if altItem and altKey and item == altItem then return "press " .. altKey end
    return "press it on your bar or in your bag: the key is locked in a fight"
end

function BI.EmergencyStep()
    local it = BI.PickEmergency(healItems(), readyToPress)
    if not it then return nil end
    local C = ns.cast
    local first = C and C.Keys and C:Keys()[1]
    local how = BI.EmergencyHow("item:" .. it.id, C and C.EmergencyItem and C:EmergencyItem(), first and C.ItemKeyFor and C.ItemKeyFor(first))
    return useStep(it, "emergency", it.kind == "healthstone" and "Healthstone!" or "Healing potion!",
        "Low health: use your " .. it.name .. " now (" .. how .. ")")
end

-- How much a bandage heals: its tooltip ("Heals 66 damage over 6 sec."),
-- else the usual amount for its name. nil when Flow can't tell.
BI.BANDAGE_HEALS = {
    ["Linen Bandage"] = 66, ["Heavy Linen Bandage"] = 114, ["Wool Bandage"] = 161,
    ["Heavy Wool Bandage"] = 301, ["Silk Bandage"] = 400, ["Heavy Silk Bandage"] = 640,
    ["Mageweave Bandage"] = 800, ["Heavy Mageweave Bandage"] = 1104,
    ["Runecloth Bandage"] = 1360, ["Heavy Runecloth Bandage"] = 2000,
}
function BI.BandageHeal(name, lines)
    for _, l in ipairs(lines or {}) do
        local n = tostring(l):match("[Hh]eals (%d+) damage")
        if n then return tonumber(n) end
    end
    return name and BI.BANDAGE_HEALS[name] or nil
end

-- The bandage to use. You missing `missing` health (nil: Flow can't tell):
-- the smallest that fills you (a big one on a scratch wastes most of it),
-- else the biggest. lowFirst (your choice, right-click the key): lowest.
function BI.PickBandage(items, missing, lowFirst, ready, healOf)
    if lowFirst or not missing then return BI.PickKind(items, "bandage", lowFirst, ready) end
    local fills, biggest, fillsHeal, bigHeal
    for _, it in ipairs(items or {}) do
        if it.kind == "bandage" and (not ready or ready(it.id)) then
            local h = healOf(it) or 0
            if h >= missing and (not fills or h < fillsHeal) then fills, fillsHeal = it, h end
            if not biggest or h > bigHeal then biggest, bigHeal = it, h end
        end
    end
    return fills or biggest
end

-- Health you're missing: exact when the game shows it; else Flow's estimate
-- of how hurt you are (E.hurt, out of E.HURT.max) of your maximum health;
-- nil when the maximum is hidden too.
function BI.MissingHealth(hp, maxHp, hurt, hurtMax)
    hp, maxHp = A.Safe(hp), A.Safe(maxHp)
    if not (maxHp and maxHp > 0) then return nil end
    if hp then return math.max(0, maxHp - hp) end
    if not (hurt and hurtMax and hurtMax > 0) then return nil end
    return maxHp * math.min(1, math.max(0, hurt) / hurtMax)
end

function BI.BandageStep(lowFirst)
    if bandaged() then return nil end
    local E = ns.rotation
    local missing = BI.MissingHealth(UnitHealth("player"), UnitHealthMax("player"), E and E.hurt, E and E.HURT.max)
    local it = BI.PickBandage(healItems(), missing, lowFirst, itemReady,
        function(x) return BI.BandageHeal(x.name, tipLines(x.id)) end)
    if not it then return nil end
    return useStep(it, "heal", "Bandage: " .. it.name,
        "Hurt after your fight: bandage up (stand still while it heals)"
            .. (missing and not lowFirst and string.format("; the smallest that fills about %d missing health", math.floor(missing + 0.5)) or ""),
        "player")
end

-- The food to heal with: plain food first (best rank); food that also makes
-- you Well Fed only when there's no plain food and buffFood allows it.
-- preferBuff: you're about to fight a lot and aren't Well Fed, so food that
-- heals AND makes you Well Fed comes first: one meal does both.
function BI.PickFood(items, buffFood, ready, preferBuff)
    local plain, buff = {}, {}
    for _, it in ipairs(items or {}) do
        if it.kind == "food" then local t = it.buff and buff or plain; t[#t + 1] = it end
    end
    if buffFood and preferBuff then
        local b = BI.PickKind(buff, "food", false, ready)
        if b then return b end
    end
    return BI.PickKind(plain, "food", false, ready) or (buffFood and BI.PickKind(buff, "food", false, ready)) or nil
end

function BI.FoodStep(buffFood, preferBuff)
    local it = BI.PickFood(healItems(), buffFood, itemReady, preferBuff)
    if not it then return nil end
    return useStep(it, "heal", "Eat: " .. it.name, "Hurt after your fight: eat to heal up"
        .. (it.buff and preferBuff and " (and Well Fed for the fights ahead)" or ""))
end

-- Out of mana after a fight: your best drink (water and the like).
function BI.DrinkStep()
    local it = BI.PickKind(healItems(), "drink", false, itemReady)
    if not it then return nil end
    return useStep(it, "heal", "Drink: " .. it.name, "Low on mana: drink before the next pull (you can eat at the same time)")
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
    items[#items + 1] = toggle("Eat Well Fed food too (first when fights are ahead)", "recoverBuffFood")
    items[#items + 1] = toggle("Drink when low on mana", "recoverDrink")
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
