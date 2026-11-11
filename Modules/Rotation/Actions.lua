-- Flow Actions: what your Flow key does out of combat when there's no spell
-- to suggest, based on the route stop you're at. One press per step:
--
--   at a fishing stop:  equip your Fishing Pole -> put a lure on it ->
--                       cast Fishing -> (while fishing) reel in the bobber
--   at a mining/herb stop: turn on Find Minerals / Find Herbs -> gather
--   after you leave:    put your weapons back (main hand, then off hand)
--
-- Each step is a registration (ns:Register("action", key, { order, get })),
-- so new ones (skinning, a hearthstone at the end of the route...) are new
-- entries. get(ctx) returns nil or a suggestion:
--   { type = "spell"|"item"|"interact", spell = name, item = "item:ID",
--     targetSlot = 16, icon = texture, label = "Equip your Fishing Pole",
--     urgent = true (beats the rotation's buff suggestion) }
--
-- Why one press per step and not one macro: WoW: Forever ignores macro-type
-- secure buttons (see CLAUDE.md), and the game only lets an add-on equip,
-- use or cast from a key press. So the key moves through the steps instead.

local _, ns = ...
local A = ns.api
local X = {}
ns.actions = X

local MAIN, OFF = 16, 17
local NEAR = 45   -- yards from the stop: "you're there"

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

local function instant(id)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end

-- Fishing poles: weapon class 2, subclass 20 (any pole, any client's IDs).
local POLES = { [6256] = true, [6365] = true, [6366] = true, [6367] = true, [12225] = true, [19022] = true, [19970] = true }
function X.IsPole(id)
    if not id then return false end
    if POLES[id] then return true end
    local _, _, _, _, _, classID, subclassID = instant(id)
    return classID == 2 and subclassID == 20
end

-- Lures, best first (fishing bonus): Aquadynamic Fish Attractor, Bright
-- Baubles, Flesh Eating Worm, Nightcrawlers, Aquadynamic Fish Lens, Shiny Bauble.
X.LURES = { 6533, 6532, 7307, 6530, 6811, 6529 }

local function bagItems()
    local out = {}
    local C = C_Container
    local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
    local itemAt = (C and C.GetContainerItemID) or GetContainerItemID
    if not (slots and itemAt) then return out end
    for bag = 0, 4 do
        for slot = 1, (slots(bag) or 0) do
            local id = itemAt(bag, slot)
            if id then out[#out + 1] = id end
        end
    end
    return out
end

local function equipped(slot) return GetInventoryItemID and GetInventoryItemID("player", slot) end

local function count(id) return A.Count(id) end

local function itemIcon(id)
    local _, _, _, _, icon = instant(id)
    return icon or (A.ItemIcon and A.ItemIcon(id))
end

local function usable(id)
    if not A.IsUsableItem then return true end
    local ok, u = pcall(A.IsUsableItem, id)
    return not ok or u ~= false
end

-- A lure on your main hand right now?
local function lured()
    if not GetWeaponEnchantInfo then return false end
    local ok, has = pcall(GetWeaponEnchantInfo)
    return ok and A.Safe(has) and true or false
end

-------------------------------------------------------------------------------
-- Spells, tracking, interact
-------------------------------------------------------------------------------

local function knows(spell) return A.SpellInfo(spell) ~= nil end

local function spellIcon(spell)
    local _, icon = A.SpellInfo(spell)
    return icon
end

-- Is this minimap tracking (Find Minerals, Find Herbs) on? nil = can't tell.
local function tracking(spell)
    local M = C_Minimap
    if M and M.GetNumTrackingTypes and M.GetTrackingInfo then
        for i = 1, (M.GetNumTrackingTypes() or 0) do
            local a, _, c = M.GetTrackingInfo(i)
            local name, active
            if type(a) == "table" then name, active = a.name, a.active else name, active = a, c end
            if name == spell then return active and true or false end
        end
    end
    if GetTrackingTexture then
        local cur = GetTrackingTexture()
        if not cur then return false end            -- nothing tracked
        local icon = spellIcon(spell)
        if icon then return cur == icon end
    end
    return nil
end

-- The game's Interact key reaches the nearest bobber / vein / herb once
-- "soft target interact" is on (a suggested WoW setting).
function X.CanInteract()
    if InCombatLockdown() then return false end
    local ok, v = pcall(GetCVar, "SoftTargetInteract")
    return ok and v ~= nil and tonumber(v) and tonumber(v) > 0 or false
end

-- One press that clears your target: the game's Interact goes to your target
-- when you have one (Lee Brown), not to the bobber or vein in front of you.
-- Only a friendly target (an NPC, a player): an enemy target is your pull.
function X.FriendlyTarget()
    return UnitExists("target") and not UnitCanAttack("player", "target") or false
end
function X.ClearTargetStep(why)
    return { type = "clear", icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", label = "Clear your target (" .. why .. ")", urgent = true }
end

local function channeling(spell)
    if not UnitChannelInfo then return false end
    local name = A.Safe(UnitChannelInfo("player"))
    return name == spell
end

-------------------------------------------------------------------------------
-- Where you are on the route
-------------------------------------------------------------------------------

local function near(goal, p, yards)
    if not (goal and p and ns.nav) then return false end
    for _, pt in ipairs(goal.points or {}) do
        if pt.wx and pt.cont == p.cont then
            local e, s = ns.nav:Offset(p, pt.wx, pt.wy)
            if e and e * e + s * s < yards * yards then return true end
        end
    end
    return false
end

-- Which profession a stop is for. Stops from the skill planner say so
-- (goal.prof); others are recognised by their key ("skill:Fishing") or, for
-- quest stops like "catch 5 fish", by their text.
function X.GoalProf(goal)
    if not goal then return nil end
    if goal.prof then return goal.prof end
    local p = goal.key and goal.key:match("^skill:(.+)$")
    if p then return p end
    -- Quest objectives only ("Catch 5 Raw Brilliant Smallfish"): Flow's own stops
    -- say what they are, and "Learn Brilliant Smallfish" isn't fishing.
    if goal.key and goal.key:find("^%d+:%d+$") and goal.kind ~= "merchant" and type(goal.text) == "string"
        and (goal.text:find("[Ff]ish[^i]") or goal.text:find("[Ff]ish$") or goal.text:find("[Cc]atch ")) then
        return "Fishing"
    end
end

-- Where you last fished. Fishing goes on wherever the pole is on and you've
-- been casting, not just at Flow's own stop (any lake, any fishing quest),
-- until you walk away from it.
local FISH_NEAR, FISH_LEFT = 120, 60
local function dist(p, at)
    if not (p and at and p.cont == at.cont and ns.nav) then return math.huge end
    local e, s = ns.nav:Offset(p, at.wx, at.wy)
    if e then return math.sqrt(e * e + s * s) end
    -- No map to turn it into east/south (a spot saved without one): world
    -- positions are in yards, so the plain distance is the same length.
    if not (p.wx and p.wy and at.wx and at.wy) then return math.huge end
    local dx, dy = at.wx - p.wx, at.wy - p.wy
    return math.sqrt(dx * dx + dy * dy)
end
local function markFishingSpot()
    local p = ns.nav and ns.nav:PlayerPos()
    if p then ns.db.actions.fishedAt = { cont = p.cont, wx = p.wx, wy = p.wy } end
end
X._markFishingSpot = markFishingSpot  -- (tests)

-- Weapons you had before Flow put the pole on (to put back afterwards).
local function saved() return ns.db.actions.weapons end
local function saveWeapons()
    markFishingSpot()
    local mh, oh = equipped(MAIN), equipped(OFF)
    if X.IsPole(mh) then return end
    ns.db.actions.weapons = { main = mh, off = oh }
end

function X:Context()
    local p = ns.nav and ns.nav:PlayerPos()
    local choice = ns.nav and ns.nav.current
    -- With the faint profession arrow on, profession stops have a route of
    -- their own (N.profChoice): standing at that stop, the key does its steps
    -- (make the bars at the forge, fish, gather), as it does on the main route.
    local pc = ns.nav and ns.nav.profChoice
    if pc and pc.goal and near(pc.goal, p, NEAR) and not (choice and choice.goal and near(choice.goal, p, NEAR)) then
        choice = pc
    end
    local goal = choice and choice.goal
    local prof = X.GoalProf(goal)
    local pole = X.IsPole(equipped(MAIN))
    local atFish = prof == "Fishing" and near(goal, p, FISH_NEAR) or false
    local spot = ns.db.actions.fishedAt
    -- The game said "didn't land in fishable water" here: no water in front
    -- of you. Off a fishing stop that means stop offering Fishing (weapons
    -- back instead); at one, it means turn to face the water.
    local dry = ns.db.actions.dryAt
    local noWater = dry and dist(p, dry) < 15 or false
    return {
        p = p, goal = goal, prof = prof, pole = pole,
        at = goal and near(goal, p, NEAR) or false,
        atFish = atFish, noWater = noWater,
        -- Fishing now: at a fishing stop, or the pole is on and you're still
        -- where you put it on / last cast (a pole on with no known spot, away
        -- from a fishing stop, isn't fishing: weapons back instead), and
        -- the last cast here didn't miss the water.
        fishing = atFish or (pole and not noWater and spot and dist(p, spot) < FISH_LEFT) or false,
    }
end

-- Every cast marks the spot (so moving along the shore keeps you fishing).
ns:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if unit ~= "player" then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if name == "Fishing" then markFishingSpot(); ns.db.actions.dryAt = nil end
end)

-- "Your cast didn't land in fishable water": remember where, so the key
-- stops offering a cast there (it repeated this 10 times after a fight).
function X.NoteDry(msg)
    local want = _G.SPELL_FAILED_NOT_FISHABLE
    if type(msg) ~= "string" or not ((want and msg == want) or msg:find("fishable", 1, true)) then return false end
    local p = ns.nav and ns.nav:PlayerPos()
    if p then ns.db.actions.dryAt = { cont = p.cont, wx = p.wx, wy = p.wy } end
    return true
end
ns:On("UI_ERROR_MESSAGE", function(_, msg) X.NoteDry(A.Safe(msg)) end)

-------------------------------------------------------------------------------
-- The steps
-------------------------------------------------------------------------------

-- Fishing: equip the pole, at a fishing stop (Flow key and buff button).
-- before: remember your weapons, so they go back on when you leave.
function X.EquipStep(ctx)
    if not (ctx and ctx.atFish) or ctx.pole then return nil end
    -- Not with an enemy targeted: you're about to fight (weapon stays on).
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then return nil end
    for _, id in ipairs(bagItems()) do
        if X.IsPole(id) then
            return { type = "item", item = "item:" .. id, icon = itemIcon(id), label = "Equip your Fishing Pole",
                     fish = true, reason = "You're at a fishing spot", before = saveWeapons }
        end
    end
end
ns:Register("action", "fish:equip", { order = 10, get = X.EquipStep })

-- The lure to put on: the biggest bonus you carry and can use first, the
-- smallest last (X.LURES order). has(id) -> count; canUse(id) -> bool.
function X.BestLure(has, canUse)
    for _, id in ipairs(X.LURES) do
        if (has(id) or 0) > 0 and canUse(id) then return id end
    end
end

-- A lure step for a pole that's on with no lure (nil otherwise). The buff
-- button shows it whenever the pole is on; the Flow key at a fishing spot.
function X.LureStep(ctx)
    if not (ctx and ctx.pole) or lured() or channeling("Fishing") then return nil end
    local id = X.BestLure(count, usable)
    if not id then return nil end
    local name = (A.ItemInfo and A.ItemInfo(id)) or "a lure"
    return { type = "item", item = "item:" .. id, targetSlot = MAIN, icon = itemIcon(id), fish = true,
             label = "Put " .. name .. " on your pole",
             reason = "Your fishing pole has no lure on it" }
end

-- Fishing: a lure on the pole (best one you carry that you can use).
ns:Register("action", "fish:lure", { order = 20, get = function(ctx)
    if not ctx.fishing then return nil end
    return X.LureStep(ctx)
end })

-- Fishing: reel in. While the line is out, the key presses Interact, which
-- clicks your bobber (press when it splashes). Flow key and buff button.
function X.ReelStep(ctx)
    if not (ctx and ctx.pole and channeling("Fishing") and X.CanInteract()) then return nil end
    if X.FriendlyTarget() then
        local s = X.ClearTargetStep("so the key reels in, not talks to your target")
        s.fish = true
        return s
    end
    return { type = "interact", icon = spellIcon("Fishing"), label = "Press when the bobber splashes", urgent = true,
             fish = true, reason = "Your line is out: press when the bobber splashes" }
end
ns:Register("action", "fish:reel", { order = 30, get = X.ReelStep })

-- Fishing: cast. Flow key and buff button.
function X.CastStep(ctx)
    if not (ctx and ctx.fishing and ctx.pole) or channeling("Fishing") then return nil end
    if not knows("Fishing") then return nil end
    return { type = "spell", spell = "Fishing", unit = "player", icon = spellIcon("Fishing"), fish = true,
             label = ctx.noWater and "Face the water, then cast" or "Cast your line",
             reason = ctx.noWater and "Your last cast missed the water" or "Your pole is on and you're at the water" }
end
ns:Register("action", "fish:cast", { order = 40, get = X.CastStep })

-- Crafting where you stand (a "Make 4 x Roasted Boar Meat" stop that follows
-- you): the key makes a campfire if the recipe needs one, opens the
-- profession, then presses Flow's "Make N" button for exactly the right amount.
local fireAt   -- where and when your last Basic Campfire went up
local FIRE_YARDS, FIRE_SECS = 8, 55
function X.FireNear()
    if not fireAt then return false end
    local p = ns.nav and ns.nav:PlayerPos()
    return GetTime() - fireAt.t < FIRE_SECS and dist(p, fireAt) < FIRE_YARDS
end
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    if A.SpellInfo(A.Safe(spellID) or 0) == "Basic Campfire" then
        local p = ns.nav and ns.nav:PlayerPos()
        if p then fireAt = { cont = p.cont, wx = p.wx, wy = p.wy, t = GetTime() } end
    end
end)
local function professionOpen()
    return (TradeSkillFrame and TradeSkillFrame:IsShown()) or (ProfessionsFrame and ProfessionsFrame:IsShown()) or false
end
local function craftHere(ctx)
    local g = ctx.goal
    return g and g.recipe and (g.anywhere or ctx.at) and not g.blockedBy and g
end

ns:Register("action", "craft:fire", { order = 44, get = function(ctx)
    local g = craftHere(ctx)
    if not (g and g.station == "fire" and g.anywhere) or X.FireNear() or professionOpen() then return nil end
    if not (ns.skillPlan and ns.skillPlan.CanCampfire()) then return nil end   -- needs Simple Wood and Flint and Tinder
    return { type = "spell", spell = "Basic Campfire", unit = "player", icon = spellIcon("Basic Campfire"),
             label = "Make a campfire" }
end })

ns:Register("action", "craft:open", { order = 46, get = function(ctx)
    local g = craftHere(ctx)
    if not g or professionOpen() or not knows(g.prof) then return nil end
    if g.station == "fire" and g.anywhere and not X.FireNear() then return nil end   -- (at a real fire: open now)
    return { type = "spell", spell = g.prof, unit = "player", icon = spellIcon(g.prof), label = "Open " .. g.prof }
end })

-- The window is open and Flow's goal box beside it says how many: the key
-- presses that box's "Make N" button.
ns:Register("action", "craft:make", { order = 47, get = function(ctx)
    local g = craftHere(ctx)
    local hint = _G.FlowCraftGoal
    if not (g and professionOpen() and hint and hint:IsShown() and hint.btn and hint.btn:IsEnabled()) then return nil end
    return { type = "click", button = hint.btn, icon = g.icon or spellIcon(g.prof),
             label = (hint.btn:GetText() or "Make") .. " x " .. g.recipe }
end })

-- Standing by a cooking fire, an anvil or a forge (out of combat, not on a
-- mount), the key opens the profession you'd use there: Cooking at a fire,
-- Blacksmithing at an anvil, Smelting at a forge (when you carry ore, or
-- don't smith). The game doesn't say where its anvils are, so Flow learns
-- them: each time your profession window shows a recipe's "Requires Anvil"
-- (or Forge, or Cooking Fire) as met, the spot where you stand is kept.
-- Until it knows the real one in a town it guesses: blacksmith trainers
-- work by an anvil and a forge, cooking trainers by a fire.
X.STATION_YARDS = 8     -- from a spot where the station worked
X.TRAINER_YARDS = 15    -- from a trainer (the guess)
local STATION_MAX = 200
-- Ores you can smelt (Copper to Dark Iron).
X.ORES = { 2770, 2771, 2775, 2772, 2776, 3858, 7911, 10620, 11370 }

-- "Anvil", "Forge", "Cooking Fire" (what a recipe requires) -> the station.
function X.StationKind(name)
    name = tostring(name or ""):lower()
    if name:find("anvil") then return "anvil" end
    if name:find("forge") then return "forge" end
    if name:find("fire") then return "fire" end
end

local function toolsMet(met, ...)
    for j = 1, select("#", ...), 2 do
        local name, has = select(j, ...)
        local k = X.StationKind(name)
        if k and has then met[k] = true end
    end
end
-- The stations the open profession window says you're at: { anvil = true, ... }.
function X.StationsMet()
    local met = {}
    if GetNumTradeSkills and GetTradeSkillTools then
        local ok, n = pcall(GetNumTradeSkills)
        for i = 1, (ok and n or 0) do pcall(function() toolsMet(met, GetTradeSkillTools(i)) end) end
    end
    local T = C_TradeSkillUI
    if T and T.GetAllRecipeIDs and T.GetRecipeRequirements then
        local ok, ids = pcall(T.GetAllRecipeIDs)
        for _, id in ipairs(ok and ids or {}) do
            local ok2, reqs = pcall(T.GetRecipeRequirements, id)
            for _, r in ipairs(ok2 and reqs or {}) do
                local k = X.StationKind(r.name)
                if k and r.met then met[k] = true end
            end
        end
    end
    return met
end

-- Keeps a spot where `kind` worked (one per few yards; the oldest go first).
function X.LearnStation(list, kind, p)
    if not (list and kind and p and p.cont) then return nil end
    for _, s in ipairs(list) do
        if s.kind == kind and dist(p, s) < X.STATION_YARDS then return s end
    end
    -- (map/x/y too, so the map can show it; older spots have only world yards)
    local s = { kind = kind, cont = p.cont, wx = p.wx, wy = p.wy, map = p.map, x = p.x, y = p.y }
    list[#list + 1] = s
    while #list > STATION_MAX do table.remove(list, 1) end
    return s
end
local learnPending = false
local function learnStations()
    learnPending = false
    local p = ns.nav and ns.nav:PlayerPos()
    if not p then return end
    for kind in pairs(X.StationsMet()) do
        if not (kind == "fire" and X.FireNear()) then   -- (your own campfire burns out)
            X.LearnStation(ns.db.actions.stations, kind, p)
        end
    end
end
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE" }) do
    ns:On(ev, function()
        if learnPending then return end
        learnPending = true
        if C_Timer and C_Timer.After then C_Timer.After(0.5, learnStations) else learnStations() end
    end)
end

-- Where the blacksmith and cooking trainers stand (world spots), kept 30 s.
local trainerCache = { t = -math.huge, anvil = {}, fire = {} }
local function trainerSpots()
    if GetTime() - trainerCache.t < 30 then return trainerCache end
    local out = { t = GetTime(), anvil = {}, fire = {} }
    for kind, prof in pairs({ anvil = "Blacksmithing", fire = "Cooking" }) do
        for _, name in ipairs(ns.places:TrainersFor(prof)) do
            for _, pt in ipairs(ns.places:Points(name)) do
                -- (pcall: one odd spot mustn't stop the step for every trainer)
                local ok, cont, wx, wy = pcall(ns.nav.ToWorld, ns.nav, pt.map, pt.x, pt.y)
                if ok and cont then out[kind][#out[kind] + 1] = { cont = cont, wx = wx, wy = wy } end
            end
        end
    end
    trainerCache = out
    return out
end

-- Which stations you're by: { anvil = true, forge = true, fire = true }.
-- A trainer's guess only counts where Flow hasn't learned the real one close by.
function X.StationsNear(p, learned, trainers)
    local near, known = {}, {}
    if not p then return near end
    for _, s in ipairs(learned or {}) do
        local d = dist(p, s)
        if d < X.STATION_YARDS then near[s.kind] = true end
        if d < 40 then known[s.kind] = true end
    end
    for _, pt in ipairs(trainers and trainers.anvil or {}) do
        if dist(p, pt) < X.TRAINER_YARDS then
            near.anvil = near.anvil or not known.anvil
            near.forge = near.forge or not known.forge
        end
    end
    for _, pt in ipairs(trainers and trainers.fire or {}) do
        if dist(p, pt) < X.TRAINER_YARDS then near.fire = near.fire or not known.fire end
    end
    return near
end

-- The profession to open at these stations, and the station: Smelting at a
-- forge when you carry ore (or don't smith), else Blacksmithing at an anvil
-- or forge, else Cooking at a fire. nil when you know none of them, or (with
-- canMakeFn) when you have nothing to make in it: opening Cooking by every
-- cooking trainer you walk past, with nothing to cook, would only nag.
function X.StationProf(near, knowsFn, hasOre, canMakeFn)
    local function can(prof) return knowsFn(prof) and (not canMakeFn or canMakeFn(prof)) end
    local smelt = near.forge and can("Smelting")
    local smith = (near.anvil or near.forge) and can("Blacksmithing")
    if smelt and (hasOre or not smith) then return "Smelting", "forge" end
    if smith then return "Blacksmithing", near.anvil and "anvil" or "forge" end
    if near.fire and can("Cooking") then return "Cooking", "fire" end
end

local function hasOre()
    for _, id in ipairs(X.ORES) do if count(id) > 0 then return true end end
    return false
end

-- Could you make anything? A recipe Flow saw in that profession's window
-- ({ [name] = { reagents = { [itemID] = n } } }) with every reagent in your bags.
function X.CanMakeWith(recipes, countFn)
    for _, r in pairs(recipes or {}) do
        local ok = r.reagents ~= nil and next(r.reagents) ~= nil
        for id, n in pairs(r.reagents or {}) do
            if (countFn(id) or 0) < n then ok = false; break end
        end
        if ok then return true end
    end
    return false
end
local function canMake(prof)
    if prof == "Smelting" and hasOre() then return true end
    return X.CanMakeWith(ns.recipes and ns.recipes:Known(prof), count)
end
ns:Register("action", "craft:station", { order = 49, get = function(ctx)
    if professionOpen() or (IsMounted and IsMounted()) then return nil end
    if not (knows("Cooking") or knows("Blacksmithing") or knows("Smelting")) then return nil end
    local near = X.StationsNear(ctx.p, ns.db.actions.stations, trainerSpots())
    near.fire = near.fire or X.FireNear()
    if not (near.anvil or near.forge or near.fire) then return nil end
    local prof, station = X.StationProf(near, knows, hasOre(), canMake)
    if not prof then return nil end
    return { type = "spell", spell = prof, unit = "player", icon = spellIcon(prof),
             label = string.format("Open %s (at the %s)", prof, station) }
end })

-- A recipe (or other item) to use from your bags: the key uses it.
ns:Register("action", "bag:use", { order = 48, get = function(ctx)
    local g = ctx.goal
    if not (g and g.useItem) or count(g.useItem) == 0 then return nil end
    return { type = "item", item = "item:" .. g.useItem, icon = itemIcon(g.useItem), label = g.text }
end })

-- Anything in your bags you can learn right now (a recipe, a scroll or book
-- that "Teaches you..."), not already known: the key learns it. First when
-- your bags are full (learning frees the slot), otherwise when there's
-- nothing else to press. Read from each item's tooltip, refreshed when your
-- bags change.
local learnables, learnDirty = {}, true
ns:On("BAG_UPDATE_DELAYED", function() learnDirty = true end)
ns:On("LEARNED_SPELL_IN_TAB", function() learnDirty = true end)
ns:On("LEARNED_SPELL_IN_SKILL_LINE", function() learnDirty = true end)   -- (its name on newer clients, Forever too)
ns:On("NEW_RECIPE_LEARNED", function() learnDirty = true end)
local function tooltipLines(bag, slot)
    local T = C_TooltipInfo
    if not (T and T.GetBagItem) then return nil end
    local ok, data = pcall(T.GetBagItem, bag, slot)
    if not (ok and data and data.lines) then return nil end
    local out, red = {}, {}
    for i, l in ipairs(data.lines) do
        out[i] = l.leftText or ""
        local c = l.leftColor
        red[i] = type(c) == "table" and (c.r or 0) > 0.9 and (c.g or 1) < 0.25 and (c.b or 1) < 0.25 or false
    end
    return out, red
end

-- A recipe you can't learn yet: its "Requires Tailoring (50)" line names a
-- profession you don't have or haven't trained that far, or the game shows
-- a "Requires" line in red. lines/red come from the tooltip; skill(name)
-- gives your rank in a profession (nil: you don't have it).
-- ("Requires %s (%d)" -> "^Requires (.-) %((%d+)%)$")
local MIN_SKILL = "^" .. (ITEM_MIN_SKILL or "Requires %s (%d)"):gsub("[%(%)%.%-%+%[%]%?%*]", "%%%0")
    :gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)") .. "$"
local REQUIRES = (ITEM_REQ_SKILL or "Requires %s"):match("^(.-)%%s") or "Requires "
function X.RecipeBlocked(lines, red, skill)
    for i, t in ipairs(lines or {}) do
        local prof, need = t:match(MIN_SKILL)
        if prof then
            local rank = skill(prof)
            if not rank or rank < (tonumber(need) or 0) then return true end
        end
        if red and red[i] and t:find(REQUIRES, 1, true) == 1 then return true end
    end
    return false
end
X._MIN_SKILL = MIN_SKILL
function X.Learnables()
    if not learnDirty then return learnables end
    learnDirty = false
    wipe(learnables)
    local C = C_Container
    local slots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
    local itemAt = (C and C.GetContainerItemID) or GetContainerItemID
    if not (slots and itemAt) then return learnables end
    local known = ITEM_SPELL_KNOWN or "Already known"
    for bag = 0, 4 do
        for slot = 1, (slots(bag) or 0) do
            local id = itemAt(bag, slot)
            if id and usable(id) then
                local _, _, _, _, _, classID = instant(id)
                local lines, red = tooltipLines(bag, slot)
                local teaches, isKnown = classID == 9, false
                if X.RecipeBlocked(lines, red, A.Skill) then teaches = false; lines = nil end
                for _, t in ipairs(lines or {}) do
                    if t:find(known, 1, true) then isKnown = true end
                    if t:find("Teaches", 1, true) or t:find("teaches you", 1, true) then teaches = true end
                end
                if teaches and not isKnown then
                    local name = (A.ItemInfo and A.ItemInfo(id)) or "it"
                    learnables[#learnables + 1] = { id = id, name = name }
                end
            end
        end
    end
    return learnables
end

local function freeSlots()
    local C = C_Container
    local free = (C and C.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if not free then return 99 end
    local n = 0
    for bag = 0, 4 do n = n + (select(1, free(bag)) or 0) end
    return n
end
X._freeSlots = freeSlots

ns:Register("action", "bag:learn", { order = 3, get = function(ctx)
    local l = X.Learnables()[1]
    if not l then return nil end
    local full = freeSlots() <= 1
    return { type = "item", item = "item:" .. l.id, icon = itemIcon(l.id), urgent = full,
             label = (full and "Bags full: learn " or "Learn: ") .. l.name }
end })

-- Mining / Herbalism: tracking on, then the key gathers (Interact).
local FIND = { Mining = "Find Minerals", Herbalism = "Find Herbs" }
ns:Register("action", "gather:find", { order = 50, get = function(ctx)
    local spell = ctx.goal and ctx.goal.kind ~= "merchant" and FIND[ctx.prof]
    if not spell or not knows(spell) or tracking(spell) ~= false then return nil end
    return { type = "spell", spell = spell, unit = "player", icon = spellIcon(spell), label = "Turn on " .. spell }
end })
ns:Register("action", "gather:interact", { order = 60, get = function(ctx)
    if not (ctx.at and FIND[ctx.prof] and ctx.goal.kind ~= "merchant" and X.CanInteract()) then return nil end
    local verb = ctx.prof == "Mining" and "Mine" or "Gather"
    if X.FriendlyTarget() then return X.ClearTargetStep("so the key gathers, not talks to your target") end
    return { type = "interact", icon = spellIcon(ctx.prof == "Mining" and "Mining" or "Herb Gathering")
                 or "Interface\\Icons\\Trade_Mining",
             label = verb .. " (stand next to it and press)" }
end })

-- Upgrades in your bags: what Flow's gear check says to wear now for your
-- levelling spec (the bag marks' green arrow), only gear you can use and
-- are high enough level for. Best first. { id, link, diff, equipLoc, name }
local WEAPON = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
                 INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
X.WEAPON_SLOTS = WEAPON
local upgradeCache, upgradeAt = {}, {}
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
    ns:On(ev, function() wipe(upgradeAt) end)
end
function X.Upgrades(weaponsOnly)
    -- Asked ten times a second: reuse the answer until bags or gear change (or 2 s).
    local k = weaponsOnly and "w" or "all"
    if upgradeAt[k] and GetTime() - upgradeAt[k] < 2 then return upgradeCache[k] end
    local list = X.FindUpgrades(weaponsOnly)
    upgradeCache[k], upgradeAt[k] = list, GetTime()
    return list
end
function X.FindUpgrades(weaponsOnly)
    local D, G = ns.disposition, ns.gear
    if not (D and G and D.EachBagItem) then return {} end
    local role = ns:LevelingRole()
    local out = {}
    D:EachBagItem(function(bag, slot, link)
        local ok, v = pcall(D.Decide, D, bag, slot, link)
        if not (ok and v and v.action == "equip") then return end
        local g = G:Compare(link)
        local loc = g and g.item and g.item.equipLoc
        if not (g and g.canUse) or (weaponsOnly and not WEAPON[loc]) then return end
        local id = tonumber(link:match("item:(%d+)"))
        if id and not X.IsPole(id) then
            out[#out + 1] = { id = id, link = link, diff = g.diffs[role] or 0, equipLoc = loc,
                              name = link:match("%[(.-)%]") or "it" }
        end
    end)
    table.sort(out, function(a, b) return a.diff > b.diff end)
    return out
end

local function enemyTargeted()
    return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
end

-- The next press that puts your weapons back (main hand, then off hand), or
-- nil when they're on. `urgent`: before anything else, rotation included.
-- No note of what you had (you put the pole on yourself): your best weapon
-- from the gear check (never something you can't use, like a gun).
local function restoreStep(urgent, label)
    local w = saved() or {}
    local mh, oh = equipped(MAIN), equipped(OFF)
    local main = w.main
    if not main and X.IsPole(mh) then
        local best = X.Upgrades(true)[1]
        main = best and best.id
    end
    if main and mh ~= main and count(main) > 0 then
        return { type = "item", item = "item:" .. main, icon = itemIcon(main), label = label or "Put your weapon back", urgent = urgent }
    end
    if w.off and oh ~= w.off and count(w.off) > 0 then
        return { type = "item", item = "item:" .. w.off, icon = itemIcon(w.off), label = "Put your off-hand back", urgent = urgent }
    end
    -- All back (or gone from your bags): done.
    if not X.IsPole(mh) then ns.db.actions.weapons = nil; ns.db.actions.fishedAt = nil end
end
X._restoreStep = restoreStep  -- (tests)

-- An enemy targeted with the pole still on: weapons back first, before the
-- pull, even at the fishing spot (you're about to fight with a fishing pole).
ns:Register("action", "arm:enemy", { order = 1, get = function(ctx)
    if not ctx.pole or not enemyTargeted() then return nil end
    return restoreStep(true, "Weapon on before the fight")
end })

-- After a kill: the key loots the corpse you have targeted (the game's
-- Interact with your target). WoW never lets an add-on open a corpse by
-- itself, so it's one press; Auto Loot (Flow Setup) then takes everything
-- without the loot window. A corpse Flow saw you open isn't offered again
-- (junk left behind, or a client that can't say what's on it).
local looted, lootedCount = {}, 0
X._looted = looted  -- (tests)

-- What the game says about your target, for the loot step: nil (none),
-- or { dead, player, guid, name, hasLoot (nil: can't tell), tapDenied }.
function X.TargetLootInfo()
    if not UnitExists("target") then return nil end
    local info = { dead = A.Safe(UnitIsDead("target")) and true or false,
                   player = UnitIsPlayer("target") and true or false }
    if not info.dead or info.player then return info end
    info.guid, info.name = A.Safe(UnitGUID("target")), A.Safe(UnitName("target"))
    info.tapDenied = UnitIsTapDenied and A.Safe(UnitIsTapDenied("target")) and true or false
    if info.guid and CanLootUnit then
        local ok, has = pcall(CanLootUnit, info.guid)
        if ok then info.hasLoot = A.Safe(has) and true or false end
    end
    return info
end

-- Loot it? A dead mob (not a player) you haven't opened yet, with loot on
-- it (on a client that can't say: your own kill, not someone else's tag).
-- Takes values, not the game: tests must never swap the game's functions
-- (0.35.102's test did, and tainted every press of the key).
function X.ShouldLoot(info)
    if not (info and info.dead) or info.player or not info.guid or looted[info.guid] then return false end
    if info.hasLoot ~= nil then return info.hasLoot end
    return not info.tapDenied
end

ns:On("LOOT_OPENED", function()
    local guid = UnitExists("target") and A.Safe(UnitIsDead("target")) and A.Safe(UnitGUID("target"))
    if not guid then return end
    if lootedCount > 200 then wipe(looted); lootedCount = 0 end
    looted[guid], lootedCount = true, lootedCount + 1
end)
-- ctx.lootTarget: the target as the tests describe it (else the game's).
ns:Register("action", "loot:corpse", { order = 0, get = function(ctx)
    if ns.db.actions.loot == false then return nil end
    local info = (ctx and ctx.lootTarget) or X.TargetLootInfo()
    if not X.ShouldLoot(info) then return nil end
    return { type = "interact", icon = "Interface\\Icons\\INV_Misc_Bag_10", urgent = true,
             label = "Loot " .. (info.name or "it") .. " (walk up and press)" }
end })

-------------------------------------------------------------------------------
-- Quest NPCs to heal ("Injured Deathguard healed: 0/5", Yang couldn't find
-- them): around such a stop the key targets the next one you can see (its
-- nameplate), then casts your heal on it, and again until the objective is
-- done; ones you've healed are skipped. Friendly nameplates come on while
-- you're at such a stop (Flow's marker sits on nameplates) and go back as
-- they were when you leave.
-------------------------------------------------------------------------------

-- A stop whose objective is healing NPCs (names in goal.npcs).
function X.HealGoal(goal)
    if not (goal and type(goal.npcs) == "table" and #goal.npcs > 0 and type(goal.text) == "string") then return false end
    local t = goal.text
    return (t:find("[Hh]ealed") or t:find("^[Hh]eal ")) ~= nil
end

-- The heal-NPC stop around you (the current stop or one right by it), or nil.
function X.HealGoalHere()
    local N = ns.nav
    if not N then return nil end
    if N.current and X.HealGoal(N.current.goal) then return N.current.goal end
    local plan = N.plan
    if not plan then return nil end
    for _, i in ipairs(N.HereStops(plan, N:PlayerPos())) do
        if X.HealGoal(plan[i].goal) then return plan[i].goal end
    end
end

-- Your first known heal (the class's list, best first for this: the one
-- that lands most).
function X.HealSpell()
    local E = ns.rotation
    local def = E and E:Definition()
    for _, sp in ipairs(def and def.heals or {}) do
        if E:Knows(sp) then return sp end
    end
end

-- NPCs you've healed (their GUIDs): not targeted again.
local healedNpcs = {}
X._healedNpcs = healedNpcs  -- (tests)
local function isHeal(name)
    local def = ns.rotation and ns.rotation:Definition()
    for _, sp in ipairs(def and def.heals or {}) do if sp == name then return true end end
    return false
end
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or InCombatLockdown() then return end
    local name = A.SpellInfo(A.Safe(spellID) or 0)
    if not (name and isHeal(name)) or not UnitExists("target") or UnitIsPlayer("target") then return end
    local guid = A.Safe(UnitGUID("target"))
    if guid then healedNpcs[guid] = true end
end)

-- What a unit is, for the heal step: { token, name, guid, dead, assist }.
local function unitInfo(token)
    if not UnitExists(token) then return nil end
    return { token = token, name = A.Safe(UnitName(token)), guid = A.Safe(UnitGUID(token)),
             dead = UnitIsDead(token) and true or false,
             assist = (UnitCanAssist("player", token) and not UnitIsPlayer(token)) and true or false }
end
-- The next step (pure: the tests pass the units in): heal your target if
-- it's one of them, else target one you can see, else nothing.
function X.HealStep(goal, spell, target, plates, healed)
    if not (goal and spell) then return nil end
    local names = {}
    for _, n in ipairs(goal.npcs) do names[n:lower()] = true end
    local function wanted(u)
        return u and u.name and names[u.name:lower()] and u.assist and not u.dead and not (u.guid and healed[u.guid])
    end
    if wanted(target) then
        return { type = "spell", spell = spell, unit = "target", icon = spellIcon(spell), urgent = true,
                 label = "Heal " .. target.name .. " (quest)" }
    end
    for _, u in ipairs(plates or {}) do
        if wanted(u) then
            return { type = "target", unit = u.token, icon = "Interface\\Icons\\Ability_Hunter_SniperShot", urgent = true,
                     label = "Target " .. u.name .. " (quest), then heal it" }
        end
    end
end

-- Friendly nameplates on while a heal-NPC stop is around you; back off when
-- it isn't (only if Flow turned them on). Out of combat only.
function X.FriendPlates(needed)
    if InCombatLockdown() or type(GetCVar) ~= "function" then return end
    local d = ns.db.actions
    local on = GetCVar("nameplateShowFriends") == "1"
    if needed and not on then
        d.friendPlatesByFlow = true
        pcall(SetCVar, "nameplateShowFriends", "1")
        ns:Print("friendly nameplates on while you're at this quest, so Flow can mark the NPCs (off again after).")
    elseif not needed and d.friendPlatesByFlow then
        d.friendPlatesByFlow = nil
        if on then pcall(SetCVar, "nameplateShowFriends", "0") end
    end
end

ns:Register("action", "quest:heal", { order = 0.5, get = function()
    local goal = X.HealGoalHere()
    pcall(X.FriendPlates, goal ~= nil)
    if not goal then return nil end
    local plates = {}
    for i = 1, 40 do
        local u = unitInfo("nameplate" .. i)
        if u then plates[#plates + 1] = u end
    end
    return X.HealStep(goal, X.HealSpell(), unitInfo("target"), plates, healedNpcs)
end })

-- An upgrade (or something for an empty slot) in your bags: put it on. Before
-- a fight (enemy targeted) it comes first; otherwise when there's nothing
-- else to press. Not weapons while you're fishing (the pole stays on).
ns:Register("action", "gear:upgrade", { order = 2, get = function(ctx)
    if UnitIsDeadOrGhost("player") then return nil end
    for _, u in ipairs(X.Upgrades()) do
        if not (ctx.fishing and WEAPON[u.equipLoc]) then
            local enemy = enemyTargeted()
            return { type = "item", item = "item:" .. u.id, icon = itemIcon(u.id), urgent = enemy,
                     label = (enemy and "Before the fight: equip " or "Equip ") .. u.name
                         .. string.format(" (upgrade +%d)", math.floor(u.diff + 0.5)) }
        end
    end
end })

-- Left the fishing spot with the pole still on: weapons back, main hand first.
ns:Register("action", "fish:restore", { order = 70, get = function(ctx)
    if not (saved() or ctx.pole) or ctx.fishing or channeling("Fishing") then return nil end
    return restoreStep(false)
end })

-------------------------------------------------------------------------------

local ordered
local function list()
    if not ordered then
        ordered = {}
        for key, a in ns:Each("action") do ordered[#ordered + 1] = { key = key, a = a } end
        table.sort(ordered, function(x, y) return (x.a.order or 50) < (y.a.order or 50) end)
    end
    return ordered
end

local errors = {}   -- last error per action step (X:Current)
X._errors = errors   -- (tests)

-- The action for right now (out of combat only), or nil.
function X:Current()
    if InCombatLockdown() or UnitIsDeadOrGhost("player") or ns.db.actions.enabled == false then return nil end
    local ctx = self:Context()
    for _, e in ipairs(list()) do
        local ok, s = pcall(e.a.get, ctx)
        -- A step that errors is skipped, but never silently: keep each new
        -- error in the log (one line per step and message, not every tick).
        if not ok then
            local msg = e.key .. ": " .. tostring(s)
            if errors[e.key] ~= msg then errors[e.key] = msg; ns:Log("action", "error in " .. msg) end
            s = nil
        end
        if ok and s then
            s.kind, s.key = "action", e.key
            return s
        end
    end
end

ns:OnLoad(function(saved)
    saved.actions = saved.actions or {}
    saved.actions.stations = saved.actions.stations or {}   -- where anvils, forges and fires worked
end)

ns.commands.action = function(arg)
    arg = (arg or ""):lower()
    local loot = arg:match("^loot%s+(o[nf]f?)$")
    if loot == "on" or loot == "off" then
        ns.db.actions.loot = (loot == "on")
        ns:Print("Flow key loots your kills: " .. loot)
        return
    end
    if arg == "on" or arg == "off" then
        ns.db.actions.enabled = (arg == "on")
        ns:Print("Flow Actions " .. arg)
        return
    end
    local ctx = X:Context()
    local s = X:Current()
    ns:Print(string.format("Flow Action now: %s", s and (s.label .. " [" .. s.key .. "]") or "nothing"))
    print(string.format("  stop %s (%s), at it: %s, fishing here: %s, pole on: %s, interact key reaches objects: %s",
        tostring(ctx.goal and ctx.goal.key), tostring(ctx.prof), tostring(ctx.at), tostring(ctx.fishing), tostring(ctx.pole), tostring(X.CanInteract())))

    print("  /flow action on|off   /flow action loot on|off (the key loots your kills)")
end
