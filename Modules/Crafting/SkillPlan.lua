-- Profession skill plans as route stops. For each profession you need to
-- raise (a quest such as "Raise your blacksmithing skill to 20", or a planned
-- profession that's behind your level) it works out, from what you have NOW:
--   what to make     cheapest skill-ups per material at your skill (Guides.lua,
--                    corrected by your real profession window, Recipes.lua)
--   what that needs  materials, minus what's in your bags and your bank
--   how to get them  take them out of the bank, smelt the ore you have, mine
--                    veins / kill mobs on this map, buy from a vendor
-- and hands the route planner the stops: gather, smelt, craft, learn, buy.
-- The planner mixes them with your quests by distance, so you mine the veins
-- that are on the way. Bags change -> plan changes (re-planned live).
-- Stops that can't happen yet (no Mining, no hammer, skill too low) are
-- listed as blocked, with the reason, instead of disappearing.

local _, ns = ...
local SP = {}
ns.skillPlan = SP

local A = ns.api
local MAX_POINTS = 60

local function count(id) return A.Count(id) end

local SIMPLE_WOOD = 4470                                  -- Basic Campfire uses one
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
-- A profession's own icon (its spell), for the arrow when you're at its stop.
local function profIcon(prof)
    local _, icon = A.SpellInfo(prof)
    return icon
end
SP.ProfIcon = profIcon
-- A tool for this profession in your bags or equipped (any version of it).
local function hasTool(prof, id)
    if id and count(id) > 0 then return true end
    return ns.disposition and ns.disposition.HasTool and ns.disposition:HasTool(prof) or false
end
local function src(id) return ns:Get("itemSource", id) end
local function itemName(id)
    local s = src(id)
    return (s and s.name) or (A.ItemInfo and A.ItemInfo(id)) or ("item " .. id)
end

-- Profession name as the guides spell it ("first aid" -> "First Aid").
local function profName(lower)
    for name in ns:Each("profGuide") do
        if name:lower() == lower then return name end
    end
    for _, p in ipairs(A.Professions()) do
        if p.name:lower() == lower then return p.name end
    end
end

-- "Raise your blacksmithing skill to 20" -> "Blacksmithing", 20
function SP.ParseObjective(text)
    if type(text) ~= "string" then return nil end
    local what, n = text:lower():match("raise your ([%a ]-) skill to (%d+)")
    if not what then n, what = text:lower():match("reach (%d+) ([%a ]-) skill") end
    if not what then return nil end
    local name = profName(what)
    if name then return name, tonumber(n) end
end

-------------------------------------------------------------------------------
-- Places
-------------------------------------------------------------------------------

local function here()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function playerPoint()
    local p = ns.nav and ns.nav.PlayerPos and ns.nav:PlayerPos()
    if p then return { map = p.map, x = p.x, y = p.y, cont = p.cont, wx = p.wx, wy = p.wy } end
end

-- Questie spawns -> map points; on this map if any are here, else anywhere.
-- Spread over all the spawns, not the first MAX_POINTS (ns.quests.SpreadPoints).
local function spawnPoints(spawnTables)
    local pts, onMap = ns.quests.SpreadPoints(spawnTables, MAX_POINTS, { map = here(), onlyMap = true })
    return pts, onMap
end

-- names (optional, same order as ids): an object whose Questie name differs
-- is skipped, so a wrong ID never sends you to the wrong thing.
local function objectPoints(ids, names)
    local spawns = {}
    for i, id in ipairs(ids or {}) do
        local o = ns.quests:QuestieGet("GetObject", id)
        if o and o.spawns and not (names and names[i] and o.name ~= names[i]) then spawns[#spawns + 1] = o.spawns end
    end
    return spawnPoints(spawns)
end

-- The gathering nodes Flow knows for a profession (gatherNode, Nearby.lua)
-- that still raise your skill: object IDs and their names.
function SP.NodeObjects(prof, rank, nodes, skillUp)
    local ids, names = {}, {}
    for name, nd in pairs(nodes) do
        if nd.prof == prof and rank >= (nd.skill or 1) and (not skillUp or skillUp(nd.skill or 1, rank)) then
            for _, id in ipairs(nd.objects or {}) do ids[#ids + 1] = id; names[#names + 1] = name end
        end
    end
    return ids, names
end

local function npcPoints(names)
    if ns.quests.NPCsByName then ns.quests:NPCsByName(names) end
    local map, mine, all = here(), {}, {}
    for _, n in ipairs(names or {}) do
        for _, pt in ipairs(ns.places:Points(n)) do
            if pt.map == map then mine[#mine + 1] = pt end
            all[#all + 1] = pt
        end
    end
    return #mine > 0 and mine or all, #mine > 0
end

-- What an item costs at a vendor (copper): the price you last saw there,
-- else the guide's estimate. Buy stops carry it as `cost`, so the route
-- lists them as blocked until you can pay (Nav.lua).
function SP.Price(id)
    local seen = ns.db.prices and ns.db.prices[id]
    if seen then return seen end
    local s = src(id)
    return s and s.price
end

local function recordPrices()
    if not (GetMerchantNumItems and GetMerchantItemInfo) then return end
    ns.db.prices = ns.db.prices or {}
    for i = 1, GetMerchantNumItems() do
        local _, _, price, qty = GetMerchantItemInfo(i)
        local id = GetMerchantItemID and GetMerchantItemID(i)
        if not id and GetMerchantItemLink then
            local link = GetMerchantItemLink(i)
            id = link and tonumber(link:match("item:(%d+)"))
        end
        if id and price and price > 0 then ns.db.prices[id] = math.ceil(price / math.max(qty or 1, 1)) end
    end
end
ns:On("MERCHANT_SHOW", function() C_Timer.After(0.3, function() pcall(recordPrices) end) end)

local function vendorPoints(itemId)
    local item = ns.quests:QuestieGet("GetItem", itemId)
    local spawns, names = {}, {}
    for _, id in ipairs(item and item.vendors or {}) do
        local npc = ns.quests:QuestieGet("GetNPC", id)
        if npc and npc.spawns then spawns[#spawns + 1] = npc.spawns; names[#names + 1] = npc.name end
    end
    local pts, onMap = spawnPoints(spawns)
    return pts, onMap, names
end

-- Cooking fires: you can make one anywhere (Basic Campfire) only with Simple
-- Wood AND Flint and Tinder in your bags; otherwise Flow plans the cooking at
-- a real fire: the cooking trainers cook by one (Tomas in Goldshire's inn).
local FLINT = 4471
function SP.CanCampfire()
    return A.SpellInfo("Basic Campfire") ~= nil and count(SIMPLE_WOOD) > 0 and count(FLINT) > 0
end
-- Anvils and forges stand by the blacksmiths; Flow uses those as the spot.
local function stationPoints(station)
    if station == "fire" then
        if SP.CanCampfire() then return nil end   -- make one where you stand
        return npcPoints(ns.places:TrainersFor("Cooking"))
    end
    if station == "anvil" or station == "forge" then
        return npcPoints(ns.places:TrainersFor("Blacksmithing"))
    end
end

-------------------------------------------------------------------------------
-- Skill-up maths
-------------------------------------------------------------------------------

-- Chance of a skill point per craft at `rank`. The colour your profession
-- window showed wins when Flow saw it at this same skill.
local CHANCE = { optimal = 1, medium = 0.6, easy = 0.2, trivial = 0 }
local function chance(prof, step, rank)
    local known, seenRank = ns.recipes:Known(prof)
    local r = known and known[step.recipe]
    if r and seenRank == math.floor(rank) and CHANCE[r.diff] then return CHANCE[r.diff] end
    if rank < step.learn then return 0 end
    if rank < step.yellow then return 1 end
    if rank < step.green then return 0.6 end
    if rank < step.grey then return 0.2 end
    return 0
end

local function matUnits(step)
    local n = 0
    for _, q in pairs(step.mats or {}) do n = n + q end
    return math.max(n, 1)
end

-- Expected crafts per step to go from rank to target: at each point, the
-- step with the most skill per material. When two are as good (Charred Wolf
-- Meat, Roasted Boar Meat), the one whose materials are in your bags wins, so
-- what you already carry gets used before anything is farmed.
-- `have` (optional): item ID -> count in bags; defaults to your bags.
local simulate
function simulate(prof, steps, rank, target, have)
    local crafts, order = {}, {}
    local left = {}
    local function bag(id)
        if left[id] == nil then left[id] = (have and have[id]) or (not have and count(id)) or 0 end
        return left[id]
    end
    local function canMake(s)
        for id, q in pairs(s.mats or {}) do if bag(id) < q then return false end end
        return true
    end
    local guard = 0
    while rank < target and guard < 600 do
        guard = guard + 1
        local best, bestV, bestC, bestHave
        for _, s in ipairs(steps) do
            local c = chance(prof, s, rank)
            local v = c / matUnits(s)
            local h = canMake(s)
            if c > 0 and (not bestV or v > bestV or (v == bestV and h and not bestHave)) then
                best, bestV, bestC, bestHave = s, v, c, h
            end
        end
        if not best then break end
        if not crafts[best] then crafts[best] = 0; order[#order + 1] = best end
        crafts[best] = crafts[best] + 1
        if bestHave then for id, q in pairs(best.mats or {}) do left[id] = bag(id) - q end end
        rank = rank + bestC
    end
    return crafts, order, rank >= target
end

-- Materials that stand in for `id`: dropped materials of other steps that
-- skill up exactly like the step using `id` (same colours, one material each).
-- `id` itself comes first.
function SP.Alternatives(steps, id)
    local mine
    for _, s in ipairs(steps or {}) do
        if s.mats and s.mats[id] then mine = s break end
    end
    local out = { id }
    if not mine then return out end
    local function single(s)
        local only, n = nil, 0
        for mid in pairs(s.mats or {}) do only = mid; n = n + 1 end
        return n == 1 and only or nil
    end
    if not single(mine) then return out end
    for _, s in ipairs(steps) do
        local other = single(s)
        local os = other and src(other)
        if s ~= mine and other and other ~= id and os and os.drops
            and s.learn == mine.learn and s.yellow == mine.yellow and s.green == mine.green and s.grey == mine.grey then
            out[#out + 1] = other
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- Drop rates: how many kills a dropped material really takes. Starts from the
-- guide's rough rate and moves to yours as you loot those mobs.
-------------------------------------------------------------------------------

local PRIOR_KILLS = 5           -- how much the guide's rate counts, in kills
local DEFAULT_RATE = 0.4

function SP.DropRate(id)
    local s = src(id)
    local prior = (s and s.rate) or DEFAULT_RATE
    local d = ns.db.crafting.drops and ns.db.crafting.drops[id]
    local kills, got = d and d.kills or 0, d and d.got or 0
    return (got + prior * PRIOR_KILLS) / (kills + PRIOR_KILLS), kills
end

-- Looting a mob that's listed as dropping a material: one kill for each such
-- material, and one "got" for each that was in the loot. Once per corpse.
local lastCorpse
function SP.RecordLoot(mob, guid, looted)
    if not mob or (guid and guid == lastCorpse) then return end
    lastCorpse = guid
    ns.db.crafting.drops = ns.db.crafting.drops or {}
    local lower = mob:lower()
    for id, s in ns:Each("itemSource") do
        if type(id) == "number" and s.drops then
            for _, n in ipairs(s.drops) do
                if n:lower() == lower then
                    local d = ns.db.crafting.drops[id] or { kills = 0, got = 0 }
                    ns.db.crafting.drops[id] = d
                    d.kills = d.kills + 1
                    if looted[id] or (s.name and looted[s.name:lower()]) then d.got = d.got + 1 end
                    break
                end
            end
        end
    end
end

ns:On("LOOT_OPENED", function() pcall(function()
    if not (UnitExists("target") and UnitIsDead("target")) then return end
    local looted = {}
    for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then looted[id] = true end
        local _, name = GetLootSlotInfo(slot)
        if name then looted[name:lower()] = true end
    end
    SP.RecordLoot(A.Safe and A.Safe(UnitName("target")) or UnitName("target"), UnitGUID("target"), looted)
end) end)

-------------------------------------------------------------------------------
-- Targets: quests first, then planned professions behind your level.
-------------------------------------------------------------------------------


-- The skill that's right for your level, per profession. Crafting keeps pace
-- with the general curve (75 by level 10, 300 by 60). A profession can give
-- its own `pace` (level -> skill) when the general curve asks too much:
-- Fishing only needs to keep up with the water you'll be fishing in.
function SP.Pace(prof, level)
    local g = prof and ns:Get("profGuide", prof)
    local marks = g and g.pace
    if not marks then return A.ProfessionTarget(level) end
    if level <= marks[1][1] then return marks[1][2] end
    for i = 2, #marks do
        local a, b = marks[i - 1], marks[i]
        if level <= b[1] then
            return math.floor(a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1]))
        end
    end
    return marks[#marks][2]
end
function SP:Targets()
    -- Professions switched off (map list, arrow menu): no profession stops at all,
    -- not even for quests that ask for a skill, nor tools to buy.
    if ns.db.nav.professions == false then return {} end
    local out = {}
    for _, q in ipairs(ns.quests.LogEntries and ns.quests.LogEntries() or {}) do
        for _, o in ipairs(q.objectives or {}) do
            local prof, n = SP.ParseObjective(o.text)
            if prof and not o.finished and (not out[prof] or out[prof].target < n) then
                out[prof] = { target = n, quest = q.title, required = true }
            end
        end
    end
    if ns.db.nav.professions ~= false then
        local level = UnitLevel("player")
        for _, p in ipairs(ns:ProfessionPlan() or {}) do
            local g = ns:Get("profGuide", p.name)
            local rank = A.Skill(p.name)
            local want = SP.Pace(p.name, level)
            -- Gathering behind your level is the errands' optional skill-up stop.
            -- A craft plan starts when you're 10+ behind and then holds until
            -- you reach its target (it used to vanish once you were within
            -- 10, halfway through crafting, so you didn't know when to stop).
            local active = ns.db.crafting.active or {}
            ns.db.crafting.active = active
            if g and g.kind == "craft" and rank and not out[p.name] then
                if rank + 10 < want then
                    out[p.name] = { target = want, optional = true }
                    active[p.name] = want
                elseif active[p.name] and rank < active[p.name] then
                    out[p.name] = { target = active[p.name], optional = true }
                else
                    active[p.name] = nil
                end
            end
        end
    end
    return out
end

-- Professions whose stops come from here (Goals.lua skips its own skill-up).
local handled = {}
function SP:Handles(prof)
    if handled[prof] then return true end
    local ok, t = pcall(SP.Targets, SP)
    return ok and t[prof] ~= nil or false
end

-------------------------------------------------------------------------------
-- Stops
-------------------------------------------------------------------------------

local function why(t, prof, rank)
    if t.quest then return string.format("%s: %s %d -> %d", t.quest, prof, rank, t.target) end
    return string.format("%s %d -> %d (right for your level)", prof, rank, t.target)
end

local watched = {}  -- item IDs whose counts change the plan

-- The tool a profession needs (guide `tool`: Mining Pick, Blacksmith Hammer,
-- Fishing Pole) when you don't have one: a "Buy a X" stop, and X's name so
-- the stops that need it can say "needs a X". Nothing when you have it.
-- Also used for the optional skill-ups in Goals.lua.
function SP:ToolGoal(prof)
    local g = ns:Get("profGuide", prof)
    if not (g and g.tool) or hasTool(prof, g.tool) then return nil, nil end
    local name = itemName(g.tool)
    watched[g.tool] = true
    local pts, _, sellers = vendorPoints(g.tool)
    return {
        key = "buy:" .. g.tool, kind = "merchant", points = pts, npcs = sellers, cost = SP.Price(g.tool),
        title = prof, text = "Buy a " .. name,
        details = { "Needed for " .. prof .. "." },
        blockedBy = #pts == 0 and ("Flow doesn't know who sells a " .. name .. " (try a trade supplies vendor)") or nil,
    }, name
end

-- A lure for a profession that uses one (Fishing: guide `lure`, the Shiny
-- Bauble), when you carry none. Optional and cheap: planned when its vendor
-- is roughly on the way (often the same one that sells the pole).
function SP:LureGoal(prof)
    local g = ns:Get("profGuide", prof)
    if not (g and g.lure) then return nil end
    watched[g.lure] = true
    for _, id in ipairs(ns.actions and ns.actions.LURES or { g.lure }) do
        watched[id] = true
        if count(id) > 0 then return nil end
    end
    local name = itemName(g.lure)
    local pts, _, sellers = vendorPoints(g.lure)
    if #pts == 0 then return nil end   -- nobody known sells it: just the tip
    return {
        key = "buy:" .. g.lure, kind = "merchant", points = pts, npcs = sellers, cost = SP.Price(g.lure),
        title = prof, text = "Buy a " .. name .. " (lure)", optional = true, weight = 1.2,
        details = { g.tip or ("Catches more while your " .. prof .. " skill is low."),
                    "Flow's key puts it on your pole when you're fishing." },
    }
end

-------------------------------------------------------------------------------
-- Chaining professions: fish you'll catch levelling Fishing cook just as well
-- as wolf or boar meat, so they count against the meat Cooking would farm.
-------------------------------------------------------------------------------

local CATCH_PER_POINT = 1   -- low Fishing skill: about one catch per skill point

-- Catches still to come on the way to your Fishing target (0 if Fishing
-- isn't on the plan).
function SP.PlannedCatch(targets)
    local t = targets and targets.Fishing
    local rank = A.Skill("Fishing")
    if not (t and rank) or rank >= t.target then return 0 end
    return math.floor((t.target - rank) * CATCH_PER_POINT)
end

-- A fished material whose step skills up exactly like the step using `id`.
-- Returns the step, the fish's source entry and its item ID.
function SP.FishAlternative(steps, id)
    local mine
    for _, s in ipairs(steps or {}) do
        if s.mats and s.mats[id] then mine = s break end
    end
    if not mine then return nil end
    for _, s in ipairs(steps) do
        for mid in pairs(s.mats or {}) do
            local ms = src(mid)
            if s ~= mine and ms and ms.fished and s.learn == mine.learn and s.yellow == mine.yellow
                and s.green == mine.green and s.grey == mine.grey then
                return s, ms, mid
            end
        end
    end
end

-- "Buy Recipe: X" for a bought recipe you don't have (as far as Flow knows).
local function recipeStop(prof, s, known)
    if not s.recipeItem or (known and known[s.recipe]) then return nil end
    local name = itemName(s.recipeItem)
    watched[s.recipeItem] = true
    if count(s.recipeItem) > 0 then
        return { key = "use:" .. s.recipeItem, kind = "craft", points = { playerPoint() }, anywhere = true,
                 icon = BAG_ICON, useItem = s.recipeItem,   -- in your bags: the arrow shows a bag
                 text = "Learn " .. s.recipe .. ": use the recipe in your bags" }
    end
    local pts, _, sellers = vendorPoints(s.recipeItem)
    return { key = "buy:" .. s.recipeItem, kind = "merchant", points = pts, npcs = sellers,
             cost = SP.Price(s.recipeItem),
             text = "Buy " .. name,
             details = { "So you can cook what you catch (skip it if you already know " .. s.recipe .. ")." },
             blockedBy = #pts == 0 and ("Flow doesn't know who sells " .. name) or nil }
end

-------------------------------------------------------------------------------
-- Gear you can make: recipes you know whose item would be an upgrade for
-- you (the same verdict as your bags: at least +0.5 score for your levelling
-- role, and wearable at your level). Shown beside the skill plan, never
-- instead of it: the fastest way up stays the route either way.
-------------------------------------------------------------------------------

-- Blacksmithing gear is made at an anvil. (Recipes Flow read from your
-- profession window don't say where; the guide's own steps do.)
local PROF_STATION = { Blacksmithing = "anvil" }
local gainCache = {}      -- item ID -> { gain, role, link, slot } or false (not an upgrade)
local pendingItems = {}   -- item IDs the game hadn't loaded: re-plan once it has

-- How much better item `id` is for you than what you wear: gain, role, link,
-- slot; nil when it isn't an upgrade (or you already carry one).
function SP.UpgradeGain(id)
    if not (id and ns.gear) or count(id) > 0 then return nil end
    local c = gainCache[id]
    if c == nil then
        local link = A.ItemInfo and select(2, A.ItemInfo(id))
        if not link then
            pendingItems[id] = true
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            return nil
        end
        c = false
        local cmp = ns.gear:Compare(link)
        local role = ns:LevelingRole() or "dps"
        local gain = cmp and cmp.canUse and cmp.diffs and cmp.diffs[role]
        if gain and gain >= 0.5 and (cmp.item.minLevel or 0) <= UnitLevel("player") then
            c = { gain, role, link, cmp.item.equipLoc }
        end
        gainCache[id] = c
    end
    if c then return c[1], c[2], c[3], c[4] end
end

-- The best upgrade per slot from `cands` ({ recipe, item, reagents, diff,
-- station }), biggest gain first. gainOf(itemID) -> gain, role, link, slot.
function SP.PickUpgrades(cands, gainOf)
    local best = {}
    for _, c in ipairs(cands) do
        local gain, role, link, slot = gainOf(c.item)
        if gain then
            slot = slot or c.item
            if not best[slot] or gain > best[slot].gain then
                best[slot] = { recipe = c.recipe, item = c.item, reagents = c.reagents or {}, diff = c.diff,
                               station = c.station, gain = gain, role = role, link = link, partial = c.partial }
            end
        end
    end
    local out = {}
    for _, u in pairs(best) do out[#out + 1] = u end
    table.sort(out, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.recipe < b.recipe
    end)
    return out
end

-- Upgrades you can make in `prof`, from the recipes your profession window
-- showed. gainOf: SP.UpgradeGain unless given (tests).
function SP.Upgrades(prof, gainOf)
    local known = ns.recipes and ns.recipes:Known(prof)
    if not known then return {} end
    local g = ns:Get("profGuide", prof)
    local stepOf = {}
    for _, s in ipairs(g and g.steps or {}) do stepOf[s.recipe] = s end
    local cands = {}
    for name, r in pairs(known) do
        if type(r) == "table" and r.item then
            cands[#cands + 1] = { recipe = name, item = r.item, reagents = r.reagents, diff = r.diff, partial = r.partial,
                                  station = (stepOf[name] and stepOf[name].station) or PROF_STATION[prof] }
        end
    end
    return SP.PickUpgrades(cands, gainOf or SP.UpgradeGain)
end

-- What you wear or your level changed: every verdict may have.
for _, ev in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED" }) do
    ns:On(ev, function() wipe(gainCache) end)
end
ns:On("GET_ITEM_INFO_RECEIVED", function(id)
    if id and pendingItems[id] then
        pendingItems[id] = nil
        if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect() end
    end
end)

-------------------------------------------------------------------------------
-- Your bank, remembered per character (read while it's open), so the plan
-- takes materials out of it instead of sending you to gather them again.
-------------------------------------------------------------------------------

ns:OnLoad(function(saved) saved.bank = saved.bank or {} end)
ns:PerCharacter("bank")

local bankOpen = false

-- The bank's containers on this client: the main bank, the reagent bank,
-- bank bags, and the newer bank tabs (not the warband bank).
local function bankContainers()
    local ids, seen = {}, {}
    local function add(b) if b and not seen[b] then seen[b] = true; ids[#ids + 1] = b end end
    add(BANK_CONTAINER or -1)
    add(REAGENTBANK_CONTAINER)
    local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do add(b) end
    for k, v in pairs(Enum and Enum.BagIndex or {}) do
        if type(k) == "string" and (k == "Bank" or k == "Reagentbank" or k:find("^CharacterBankTab")) then add(v) end
    end
    return ids
end

local function containerSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function containerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount end
        return nil
    end
    if GetContainerItemInfo then
        local _, n, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
        return id or (link and tonumber(link:match("item:(%d+)"))), n
    end
end

-- Reads the bank while it's open. True when what's in it changed.
function SP.ReadBank()
    if not bankOpen then return false end
    local items = {}
    for _, bag in ipairs(bankContainers()) do
        local okSlots, n = pcall(containerSlots, bag)
        for slot = 1, okSlots and n or 0 do
            local id, c = containerItem(bag, slot)
            if id and c then items[id] = (items[id] or 0) + c end
        end
    end
    local old = ns.db.bank and ns.db.bank.items or {}
    local changed = false
    for id, c in pairs(items) do if old[id] ~= c then changed = true end end
    for id in pairs(old) do if items[id] == nil then changed = true end end
    ns.db.bank = { items = items, seenAt = time() }
    return changed
end

local function rereadBank()
    local ok, changed = pcall(SP.ReadBank)
    if ok and changed and ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect() end
end
ns:On("BANKFRAME_OPENED", function() bankOpen = true; C_Timer.After(0.3, rereadBank) end)
ns:On("BANKFRAME_CLOSED", function() bankOpen = false end)
for _, ev in ipairs({ "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED" }) do
    ns:On(ev, function() if bankOpen then rereadBank() end end)
end

-- How many of an item are in your bank: what Flow saw there, or what the
-- game counts beyond your bags (whichever is more).
function SP.BankCount(id)
    local items = ns.db.bank and ns.db.bank.items
    local n = items and items[id] or 0
    if A.ItemCount then
        local ok, total = pcall(A.ItemCount, id, true)
        if ok and type(total) == "number" then n = math.max(n, total - count(id)) end
    end
    return n
end

-- What's on hand for a plan, shared by its stops so nothing is counted
-- twice: your bags first, then your bank, then bars smelted from the ore in
-- either. bagsOf / bankOf(id) -> count; smeltOf(id) -> { from, n } or nil.
function SP.Stock(bagsOf, bankOf, smeltOf)
    local st = { bags = {}, bank = {} }
    local function left(t, f, id)
        if t[id] == nil then t[id] = f(id) or 0 end
        return t[id]
    end
    -- How many of `id` you could have in hand.
    function st:Avail(id)
        local n = left(self.bags, bagsOf, id) + left(self.bank, bankOf, id)
        local sm = smeltOf(id)
        if sm then n = n + math.floor((left(self.bags, bagsOf, sm.from) + left(self.bank, bankOf, sm.from)) / sm.n) end
        return n
    end
    -- Sets `want` of `id` aside: how many from your bags, your bank, smelted
    -- (and the ore that takes, from bags / bank), and how many are still short.
    function st:Take(id, want)
        local r = { need = want, bags = 0, bank = 0, smelt = 0, oreBags = 0, oreBank = 0, short = 0 }
        r.bags = math.min(want, left(self.bags, bagsOf, id))
        self.bags[id] = self.bags[id] - r.bags
        r.bank = math.min(want - r.bags, left(self.bank, bankOf, id))
        self.bank[id] = self.bank[id] - r.bank
        local rest = want - r.bags - r.bank
        local sm = smeltOf(id)
        if sm and rest > 0 then
            r.from = sm.from
            local lb, lk = left(self.bags, bagsOf, sm.from), left(self.bank, bankOf, sm.from)
            r.smelt = math.min(rest, math.floor((lb + lk) / sm.n))
            local ore = r.smelt * sm.n
            r.oreBags = math.min(ore, lb)
            r.oreBank = ore - r.oreBags
            self.bags[sm.from] = lb - r.oreBags
            self.bank[sm.from] = lk - r.oreBank
            rest = rest - r.smelt
        end
        r.short = rest
        return r
    end
    -- A copy that starts from what's left here (to try something out).
    function st:Fork()
        return SP.Stock(function(id) return left(self.bags, bagsOf, id) end,
                        function(id) return left(self.bank, bankOf, id) end, smeltOf)
    end
    return st
end

-- One line per material: "Copper Bar x8: 2 in your bags, 6 from your bank".
function SP.SourceLine(name, r, oreName)
    local parts = {}
    if r.bags > 0 then parts[#parts + 1] = r.bags .. " in your bags" end
    if r.bank > 0 then parts[#parts + 1] = r.bank .. " from your bank" end
    if r.smelt > 0 then
        local where = (r.oreBags > 0 and r.oreBank > 0) and "bags and bank" or (r.oreBank > 0 and "bank" or "bags")
        parts[#parts + 1] = string.format("smelt %d from %d %s (%s)", r.smelt, r.oreBags + r.oreBank, oreName or "ore", where)
    end
    if r.short > 0 then parts[#parts + 1] = r.short .. " still to get" end
    return string.format("%s x%d: %s", name, r.need, #parts > 0 and table.concat(parts, ", ") or "none needed")
end

-- Where your bank is: bankers you've talked to, else the nearest one Flow
-- knows (Services.lua). Points and names.
function SP.BankerPoints()
    local names = {}
    for name, spot in pairs(ns.db.places or {}) do
        if ns.places.HasRole(spot, "bank") then names[#names + 1] = name end
    end
    table.sort(names)
    if #names > 0 then
        local pts = npcPoints(names)
        if #pts > 0 then return pts, names end
    end
    local b = ns.services and ns.services.Nearest and ns.services:Nearest("bank")
    if b and b.map then return { { map = b.map, x = b.x, y = b.y } }, { b.name } end
    return {}, names
end

local function smeltOf(id)
    local s = src(id)
    return s and s.smelt
end

-- The bank is a trip. Its stock only counts for a plan when the banker is
-- close, or when the material can't be had on this map anyway (no mob here
-- drops it, you can't gather it, nobody here sells it). Otherwise the plan
-- farms it where you are: the wolves around you, not 2 meat from a bank
-- across the zone.
SP.BANK_NEAR = 300   -- yards
-- inBank: how many the bank holds (nil: not known). A big stock is worth the
-- trip whatever the distance: 40 bars in the bank beat mining 40 ore.
SP.BANK_PLENTY = 10
function SP.UseBank(bankYards, farmHere, inBank)
    if bankYards and bankYards <= SP.BANK_NEAR then return true end
    if inBank and inBank >= SP.BANK_PLENTY then return true end
    return not farmHere
end

-- Yards from you to the nearest of these points (nil: unknown / another continent).
function SP.YardsTo(points)
    local p = ns.nav and ns.nav.PlayerPos and ns.nav:PlayerPos()
    if not (p and p.wx) then return nil end
    local best
    for _, pt in ipairs(points or {}) do
        local cont, wx, wy = ns.nav:ToWorld(pt.map, pt.x, pt.y)
        if wx and cont == p.cont then
            local d = math.sqrt((wx - p.wx) ^ 2 + (wy - p.wy) ^ 2)
            if not best or d < best then best = d end
        end
    end
    return best
end

-- Can you get this material on this map without the bank? You can gather
-- or fish it, a mob here drops it, a vendor here sells it, or it smelts
-- from an ore you can get here.
-- env: source(id) -> the item's source entry; skill(name) -> your rank or
-- nil; dropsHere(names) / soldHere(id) -> is one on this map.
function SP.Farmable(id, env, depth)
    local s = env.source(id)
    if not s then return false end
    if s.gather then
        local r = env.skill(s.gather)
        if r and r >= (s.skill or 1) then return true end   -- (too low a skill: you can't gather it)
    end
    if s.fished and env.skill("Fishing") then return true end
    if s.drops and env.dropsHere(s.drops) then return true end
    if s.vendor and env.soldHere(id) then return true end
    local sm = s.smelt
    if sm and sm.from and sm.from ~= id and (depth or 0) < 2 then
        return SP.Farmable(sm.from, env, (depth or 0) + 1)
    end
    return false
end

local hereEnv = {
    source = src,
    skill = function(name) return (A.Skill(name)) end,
    dropsHere = function(names) local _, here = npcPoints(names); return here and true or false end,
    soldHere = function(id) local _, here = vendorPoints(id); return here and true or false end,
}
function SP.FarmableHere(id) return SP.Farmable(id, hereEnv) end

-- How sure Flow is of your bank, for the bank stop: seenAt = when Flow last
-- read it (nil: never). Never read, or read days ago, is said as such: the
-- counts are what Flow last knew, not what is certainly there.
SP.BANK_STALE = 3 * 24 * 3600
function SP.BankNote(seenAt, now)
    if not seenAt then
        return "Flow hasn't seen inside your bank yet: these counts are the game's and may be off. Open your bank once."
    end
    local age = (now or time()) - seenAt
    if age >= SP.BANK_STALE then
        return string.format("Your bank as Flow saw it %d days ago: it may have changed (open it to update).", math.floor(age / 86400))
    end
    return "Your bank as Flow last saw it (open it to update)."
end

local function planProfession(prof, t, out)
    local g = ns:Get("profGuide", prof)
    local rank, max = A.Skill(prof)
    local label = why(t, prof, rank or 0)
    local weight = t.optional and 1.5 or 1.0
    local base = { title = t.quest or prof, optional = t.optional, weight = weight }
    local function add(goal)
        for k, v in pairs(base) do if goal[k] == nil then goal[k] = v end end
        goal.details = goal.details or {}
        table.insert(goal.details, 1, label)
        out[#out + 1] = goal
    end

    if not rank then
        add({ key = "skillplan:" .. prof, kind = "proftrainer", points = { playerPoint() },
              text = prof .. ": learn it at a trainer first",
              blockedBy = "you don't have " .. prof })
        return
    end
    if rank >= t.target then return end
    if max and max > 0 and t.target > max then
        add({ key = "skillplan:cap:" .. prof, kind = "proftrainer", points = { playerPoint() },
              text = string.format("%s is capped at %d: train the next tier", prof, max),
              blockedBy = string.format("%s capped at %d", prof, max) })
    end
    if not g then
        add({ key = "skillplan:" .. prof, kind = "skill", points = { playerPoint() },
              text = string.format("Raise %s to %d", prof, t.target),
              blockedBy = "Flow has no levelling data for " .. prof .. " yet" })
        return
    end
    handled[prof] = true

    -- Fishing, Herbalism: go to the known spots.
    if g.spots then
        local points = {}
        for _, spot in ipairs(ns.places:SpotsFor(prof)) do
            local p = npcPoints(spot.npcs or {})
            for _, pt in ipairs(p) do points[#points + 1] = pt end
            local o = objectPoints((function()
                local ids = {}
                for _, ob in ipairs(spot.objects or {}) do if rank >= (ob.skill or 1) then ids[#ids + 1] = ob.id end end
                return ids
            end)())
            for _, pt in ipairs(o) do points[#points + 1] = pt end
        end
        -- Every node Flow knows for it: Kalimdor's herbs have their own object
        -- IDs, so Mulgore had no Herbalism spot at all ("no known spot").
        local nodes = {}
        for name, nd in ns:Each("gatherNode") do nodes[name] = nd end
        local ids, names = SP.NodeObjects(prof, rank, nodes, ns.nearby and ns.nearby.SkillUp)
        for _, pt in ipairs((objectPoints(ids, names))) do points[#points + 1] = pt end
        local tool, missing = SP:ToolGoal(prof)
        if tool then add(tool) end
        local lure = SP:LureGoal(prof)
        if lure then add(lure) end
        add({ key = "skill:" .. prof, kind = "skill", prof = prof, points = points,
              text = string.format("%s: %d -> %d", prof == "Fishing" and "Fish" or prof, rank, t.target),
              details = g.tip and { g.tip } or nil,
              blockedBy = (missing and ("needs a " .. missing))
                  or (#points == 0 and ("no known " .. prof .. " spot on this map")) or nil })
        return
    end

    -- Tool in your bags?
    local toolGoal, toolMissing = SP:ToolGoal(prof)
    if toolGoal then add(toolGoal) end

    -- Mining also levels from the veins themselves.
    local steps = g.steps or {}
    local crafts, order, reaches = simulate(prof, steps, rank, t.target)

    -- One stock for the whole plan: bags, then bank, then smelting. What it
    -- takes from the bank becomes a bank stop, what it smelts a smelt stop;
    -- the crafts that need them come after (deps).
    local bankPts, bankNames = SP.BankerPoints()
    local bankYards = SP.YardsTo(bankPts)
    local function bankOf(id)
        local inBank = SP.BankCount(id)
        if SP.UseBank(bankYards, SP.FarmableHere(id), inBank) then return inBank end
        return 0
    end
    local stock = SP.Stock(count, bankOf, smeltOf)
    local bankPull, smeltWant, smeltBankOre = {}, {}, {}
    local bankNeeded, smeltNeeded = false, {}   -- false: only an optional upgrade wants it
    local function pull(r, id, optional)
        if r.bank > 0 then
            bankPull[id] = (bankPull[id] or 0) + r.bank
            bankNeeded = bankNeeded or not optional
        end
        if r.smelt > 0 then
            smeltWant[id] = (smeltWant[id] or 0) + r.smelt
            smeltNeeded[id] = smeltNeeded[id] or not optional
            if r.oreBank > 0 then
                bankPull[r.from] = (bankPull[r.from] or 0) + r.oreBank
                smeltBankOre[id] = true
                bankNeeded = bankNeeded or not optional
            end
        end
    end
    local bankBlocked = #bankPts == 0 and "no known banker" or nil
    local function smeltBlocked(id)
        local sm = smeltOf(id)
        local mining = A.Skill("Mining")
        if not mining then return "needs Mining to smelt" end
        if mining < (sm.skill or 1) then return string.format("needs Mining %d to smelt", sm.skill) end
        if #(stationPoints("forge") or {}) == 0 then return "no known forge" end
    end
    -- What has to happen before a craft: the bank, the smelting (and why
    -- it can't, if it can't).
    local function before(takes)
        local deps, seenDep, blocked = {}, {}, nil
        local function dep(k) if not seenDep[k] then seenDep[k] = true; deps[#deps + 1] = k end end
        for _, tk in ipairs(takes) do
            local r = tk.r
            if r.bank > 0 or r.oreBank > 0 then
                dep("bank:" .. prof)
                blocked = blocked or (bankBlocked and ("get " .. itemName(tk.id) .. " from your bank first: " .. bankBlocked))
            end
            if r.smelt > 0 then
                dep("smelt:" .. prof .. ":" .. tk.id)
                local why = smeltBlocked(tk.id)
                blocked = blocked or (why and ("smelt " .. itemName(tk.id) .. " first: " .. why))
            end
        end
        return #deps > 0 and deps or nil, blocked
    end
    local function sourceLines(takes)
        local lines = {}
        for _, tk in ipairs(takes) do
            lines[#lines + 1] = SP.SourceLine(itemName(tk.id), tk.r, tk.r.from and itemName(tk.r.from))
        end
        return lines
    end
    local function sortedIds(mats)
        local ids = {}
        for id in pairs(mats or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end
    local raw = {}

    -- Learn recipes the plan uses that your profession window doesn't list.
    local known = ns.recipes:Known(prof)
    for _, s in ipairs(order) do
        if s.recipeItem then
            -- Bought, not trained (Recipe: Brilliant Smallfish).
            local r = recipeStop(prof, s, known)
            if r then add(r) end
        elseif known and not known[s.recipe] and s.learn <= rank then
            local pts = npcPoints(ns.places:TrainersFor(prof))
            add({ key = "learn:" .. prof .. ":" .. s.recipe, kind = "proftrainer", points = pts, npcs = ns.places:TrainersFor(prof),
                  text = string.format("Learn %s (%s trainer)", s.recipe, prof),
                  blockedBy = #pts == 0 and ("no known " .. prof .. " trainer") or nil })
        end
    end

    -- Craft what you can now (bags, bank, smelting); the rest is gathered.
    for _, s in ipairs(order) do
        local planned = math.ceil(crafts[s])
        local n = planned
        local ids = sortedIds(s.mats)
        for _, id in ipairs(ids) do
            watched[id] = true
            local sm = smeltOf(id)
            if sm then watched[sm.from] = true end
            n = math.min(n, math.floor(stock:Avail(id) / s.mats[id]))
        end
        local takes = {}
        if n > 0 then
            for _, id in ipairs(ids) do
                local r = stock:Take(id, n * s.mats[id])
                pull(r, id)
                takes[#takes + 1] = { id = id, r = r }
            end
        end
        -- The crafts that wait for more: set aside what you have for them,
        -- gather the rest (ore for what smelts).
        if planned > n then
            for _, id in ipairs(ids) do
                local r = stock:Take(id, (planned - n) * s.mats[id])
                if r.short > 0 then
                    local sm = smeltOf(id)
                    if sm then raw[sm.from] = (raw[sm.from] or 0) + r.short * sm.n
                    else raw[id] = (raw[id] or 0) + r.short end
                end
            end
        end
        if n > 0 then
            local deps, depBlocked = before(takes)
            local pts, anywhere = stationPoints(s.station), false
            if not pts or #pts == 0 then pts, anywhere = { playerPoint() }, true end
            local blocked = toolMissing and ("needs a " .. toolMissing)
                or (known and not known[s.recipe] and (s.recipeItem and (count(s.recipeItem) > 0 and "use the recipe in your bags first" or ("buy " .. itemName(s.recipeItem) .. " first"))
                    or ("learn " .. s.recipe .. " first")))
            blocked = blocked or depBlocked
            -- The count is the point: exactly what reaches your target, so
            -- it's highlighted, and the details say why that many.
            local num = "|cffffd100" .. n .. "|r"
            local c = chance(prof, s, rank)
            local details = {
                string.format("%d takes %s %d -> %d: %s.", planned, prof, rank, t.target,
                    c >= 1 and "each one gives a skill point while it's yellow"
                    or "it's green now, so only some give a point (Flow counted on that)"),
                "More than that won't raise the skill further for now, so it'd be wasted materials.",
            }
            if n < planned then
                details[#details + 1] = string.format("You have materials for %d now; the rest comes after you gather more.", n)
            end
            for _, line in ipairs(sourceLines(takes)) do details[#details + 1] = line end
            details[#details + 1] = (anywhere and not deps) and "You have the materials: do it now, wherever you are."
                or (anywhere and "Then make them wherever you are.")
                or (s.station == "fire" and "At the fire by the cooking trainer (a campfire needs Simple Wood and Flint and Tinder)."
                    or ("At the " .. s.station .. " (by the blacksmith)."))
            -- Cooking: where you stand only if you can make a campfire (Simple
            -- Wood and Flint and Tinder); then Flow's key makes it, opens
            -- Cooking and makes them. Otherwise it's planned at a real fire
            -- (stationPoints), and with no known fire it waits (blocked).
            if s.station == "fire" then
                watched[SIMPLE_WOOD] = true; watched[FLINT] = true
                if anywhere and SP.CanCampfire() then
                    details[#details + 1] = "No fire nearby: Flow's key makes a campfire (Basic Campfire, uses 1 Simple Wood), opens Cooking, then makes them."
                elseif anywhere then
                    blocked = blocked or "needs a cooking fire (none known nearby; a campfire needs Simple Wood and Flint and Tinder)"
                end
            end
            add({ key = "craft:" .. prof .. ":" .. s.recipe, kind = "craft", points = pts, anywhere = anywhere,
                  weight = 0.5, deps = deps, reagents = s.mats,
                  -- The arrow shows the profession's icon (bouncing) when you're there.
                  icon = profIcon(prof), station = s.station,
                  -- For the profession window hint (CraftHint.lua).
                  prof = prof, recipe = s.recipe, makeCount = n, planned = planned, rank = rank, target = t.target,
                  text = s.recipe:find("^Smelt ") and string.format("%s x%s at a forge", s.recipe, num)
                      or string.format("Make %s x %s", num, s.recipe),
                  details = details,
                  blockedBy = blocked or nil })
        end
    end

    -- Gear you can make that's an upgrade for you. When the plan already
    -- makes it, its craft stop says so. Otherwise, with everything it needs
    -- on hand (bags, bank, smelting), it's an extra, optional stop: the route
    -- takes it only when it's on the way and it never changes what the plan
    -- makes. Missing materials: not a stop at all, only listed in the
    -- profession window (SP.lastUpgrades), so it never steers you.
    local lacking = {}
    SP.lastUpgrades = SP.lastUpgrades or {}
    SP.lastUpgrades[prof] = lacking
    for _, u in ipairs(SP.Upgrades(prof)) do
        watched[u.item] = true
        local tag = string.format("+%d %s", math.floor(u.gain + 0.5), ns.ROLE_LABEL[u.role] or u.role)
        local onPlan
        for _, goal in ipairs(out) do
            if goal.key == "craft:" .. prof .. ":" .. u.recipe then onPlan = goal end
        end
        if onPlan then
            onPlan.text = onPlan.text .. " (an upgrade for you)"
            onPlan.upgrade = u.link
            onPlan.details[#onPlan.details + 1] = string.format("One of them is an upgrade for you (%s): equip it.", tag)
        else
            local try, takes, missing = stock:Fork(), {}, {}
            for _, id in ipairs(sortedIds(u.reagents)) do
                watched[id] = true
                local sm = smeltOf(id)
                if sm then watched[sm.from] = true end
                local r = try:Take(id, u.reagents[id])
                takes[#takes + 1] = { id = id, r = r }
                if r.short > 0 then missing[#missing + 1] = string.format("%d %s", r.short, itemName(id)) end
            end
            local unread = u.partial or next(u.reagents) == nil
            if #missing > 0 or unread then
                lacking[#lacking + 1] = { recipe = u.recipe, link = u.link, tag = tag, missing = missing,
                                          unread = unread or nil, reagents = u.reagents }
            else
                local deps, depBlocked = before(takes)
                local anywhere = not u.station
                local pts = u.station and stationPoints(u.station) or (anywhere and { playerPoint() }) or nil
                local details = {
                    string.format("%s is an upgrade for you (%s). Equip it once it's made.", u.link or u.recipe, tag),
                    string.format("Not needed for %s %d: the fastest way there is planned without it, so skip it if you like.",
                        prof, t.target),
                }
                if u.diff and u.diff ~= "trivial" then
                    details[#details + 1] = "It also gives skill while the recipe isn't grey."
                end
                for _, line in ipairs(sourceLines(takes)) do details[#details + 1] = line end
                local blocked = (toolMissing and ("needs a " .. toolMissing))
                    or ((not pts or #pts == 0) and ("no known " .. (u.station or "spot"))) or depBlocked
                -- Only a stop you can actually make sets its materials aside.
                if not blocked then
                    for _, tk in ipairs(takes) do pull(stock:Take(tk.id, tk.r.need), tk.id, true) end
                end
                add({ key = "upgrade:" .. prof .. ":" .. u.recipe, kind = "craft", points = pts or {}, anywhere = anywhere,
                      optional = true, weight = 1.5, upgrade = u.link, extra = "upgrade", deps = deps, reagents = u.reagents,
                      icon = profIcon(prof), station = u.station,
                      prof = prof, recipe = u.recipe, makeCount = 1, planned = 1, rank = rank,
                      text = string.format("Make |cffffd1001|r x %s: an upgrade for you (%s)", u.recipe, tag),
                      details = details,
                      blockedBy = blocked })
            end
        end
    end

    -- Smelt stops: bars from the ore you have (bags or bank), at a forge,
    -- before the crafts that use them.
    for _, id in ipairs(sortedIds(smeltWant)) do
        local sm, n = smeltOf(id), smeltWant[id]
        local pts = stationPoints("forge") or {}
        local bar = itemName(id)
        add({ key = "smelt:" .. prof .. ":" .. id, kind = "craft", points = pts, extra = "smelt",
              optional = not smeltNeeded[id] or nil, weight = smeltNeeded[id] and 0.5 or 1.5,
              deps = smeltBankOre[id] and { "bank:" .. prof } or nil,
              icon = profIcon("Mining"), station = "forge",
              -- Done in the Mining (smelting) window: the hint shows it there.
              prof = "Mining", serves = prof, recipe = "Smelt " .. bar:gsub(" Bar$", ""),
              makeCount = n, planned = n, reagents = { [sm.from] = sm.n },
              text = string.format("Smelt |cffffd100%d|r %s at a forge", n, bar),
              details = { string.format("%d %s for your %s crafts, from %d %s%s.", n, bar, prof, n * sm.n,
                              itemName(sm.from), smeltBankOre[id] and " (some from your bank)" or ""),
                          "Forges stand by the blacksmiths." },
              blockedBy = smeltBlocked(id) })
    end

    -- Bank stop: what the plan takes out of your bank, first.
    local fromBank = {}
    for _, id in ipairs(sortedIds(bankPull)) do
        local n = math.min(bankPull[id], SP.BankCount(id))
        if n > 0 then fromBank[#fromBank + 1] = string.format("%d %s", n, itemName(id)) end
    end
    if #fromBank > 0 then
        local seen = ns.db.bank and ns.db.bank.seenAt
        add({ key = "bank:" .. prof, kind = "merchant", points = bankPts, npcs = bankNames,   -- (a town errand, not an item drop: near first and the buff steps read "collect" as killing)
              optional = not bankNeeded or nil, weight = bankNeeded and 0.5 or 1.5,
              text = "Get from your bank: " .. table.concat(fromBank, ", "),
              details = { string.format("For your %s crafts. Take them out at the banker.", prof),
                          SP.BankNote(seen) },
              blockedBy = bankBlocked })
    end

    -- Still short: group by where it comes from: one stop per node type / mob group.
    local nodes = {}
    for id, n in pairs(raw) do
        watched[id] = true
        local s = src(id)
        local name = itemName(id)
        if s and s.gather then
            local key = s.node or s.gather
            local nd = nodes[key] or { src = s, items = {}, count = 0 }
            nodes[key] = nd
            nd.items[#nd.items + 1] = string.format("%d %s", n, name)
            nd.count = math.max(nd.count, math.ceil(n / (s.yield or 1)))
        elseif s and s.fished then
            -- Comes from your Fishing stop; nothing to farm for it.
            watched[id] = true
        elseif s and s.drops then
            -- Fish you'll catch levelling Fishing anyway cook just as well:
            -- they come off the meat to farm (and the recipe goes on the route).
            local fishStep, fishSrc, fishId = SP.FishAlternative(steps, id)
            local fromFish = 0
            if fishStep then
                fromFish = math.min(n, math.floor(SP.PlannedCatch(SP.lastTargets) * (fishSrc.share or 0.7)))
                if fromFish > 0 then
                    watched[fishId] = true
                    local r = recipeStop(prof, fishStep, known)
                    if r then add(r) end
                end
            end
            n = n - fromFish
            SP.lastFromFish = fromFish  -- (for /flow prof plan and tests)
            if n > 0 then
            -- Other materials that level the same (wolf meat or boar meat): any of them will
            -- do, so their mobs count too.
            local ids = SP.Alternatives(steps, id)
            local names, mobs, rates = {}, {}, 0
            for _, aid in ipairs(ids) do
                local as = src(aid)
                names[#names + 1] = itemName(aid)
                for _, m in ipairs(as.drops) do mobs[#mobs + 1] = m end
                rates = rates + SP.DropRate(aid)
            end
            local rate = rates / #ids
            local kills = math.ceil(n / math.max(rate, 0.05))
            local _, seenKills = SP.DropRate(id)
            local pts = npcPoints(mobs)
            local details = {
                string.format("About %d kills: roughly 1 in %d drops one%s.", kills, math.floor(1 / rate + 0.5),
                    seenKills >= 5 and " (from your own loot)" or ""),
                "Drops from: " .. table.concat(mobs, ", ") .. ".",
            }
            if t.optional then
                table.insert(details, 1, prof .. " isn't needed for a quest: loot these as you quest. No need to stop just for this.")
            end
            if fromFish > 0 then
                details[#details + 1] = string.format("%d fewer than without fishing: about %d %s from your Fishing stop cook just as well.",
                    fromFish, fromFish, itemName(fishId))
            end
            add({ key = "farm:" .. id, kind = "kill", points = pts, npcs = mobs, area = true,
                  -- Optional (no quest needs it): never a stop of its own; loot the
                  -- mobs your quests and travel bring you to (Nav.lua: alongGoals).
                  along = t.optional or nil,
                  -- Progress like a quest objective: what you carry / what the plan uses.
                  text = (function()
                      local have = 0
                      for _, aid in ipairs(ids) do watched[aid] = true; have = have + count(aid) end
                      return string.format("Loot %s %s (~%d kills)", table.concat(names, " or "), ns.Progress(have, have + n), kills)
                  end)(),
                  details = details,
                  blockedBy = #pts == 0 and ("no known " .. name .. " drops nearby") or nil })
            end
        elseif s and s.vendor then
            local pts, _, sellers = vendorPoints(id)
            add({ key = "buy:" .. id, kind = "merchant", points = pts, npcs = sellers,
                  cost = SP.Price(id) and SP.Price(id) * n or nil,
                  text = string.format("Buy %d %s", n, name),
                  blockedBy = #pts == 0 and ("Flow doesn't know who sells " .. name) or nil })
        else
            add({ key = "need:" .. id, kind = "collect", points = { playerPoint() },
                  text = string.format("Get %d %s", n, name),
                  blockedBy = "Flow doesn't know where " .. name .. " comes from (Auction House?)" })
        end
    end
    for node, nd in pairs(nodes) do
        local s = nd.src
        local gr = A.Skill(s.gather)
        local pts, onMap = objectPoints(s.objects)
        local blocked
        if not gr then blocked = "needs " .. s.gather .. " (or buy them)"
        elseif gr < (s.skill or 1) then blocked = string.format("needs %s %d", s.gather, s.skill)
        elseif #pts == 0 then blocked = "no known " .. node .. " in Flow's data"
        end
        if s.gather == "Mining" and not hasTool("Mining", 2901) and not blocked then blocked = "needs a Mining Pick" end
        handled[s.gather] = true
        add({ key = "gather:" .. node, kind = "gather", prof = s.gather, points = pts,
              text = string.format("%s %s (about %d) for %s", s.gather == "Mining" and "Mine" or "Gather",
                  node, nd.count, table.concat(nd.items, ", ")),
              details = { onMap and "Nearest ones on this map; the route picks the ones on your way."
                              or "None on this map: these are elsewhere." },
              blockedBy = blocked })
    end

    -- Gathering profession with nodes (Mining): the veins themselves skill up.
    if g.nodes then
        local best
        for _, nd in ipairs(g.nodes) do
            if rank >= nd.learn and rank < nd.grey then best = nd end
        end
        if best and not nodes[src(best.item).node] then
            local s = src(best.item)
            local c = rank < best.yellow and 1 or (rank < best.green and 0.6 or 0.2)
            local pts = objectPoints(s.objects)
            add({ key = "gather:" .. s.node, kind = "gather", prof = "Mining", points = pts,
                  text = string.format("Mine %s (about %d) for skill", s.node, math.ceil((t.target - rank) / c)),
                  details = { "Smelting the ore at a forge raises Mining too." },
                  blockedBy = (not hasTool("Mining", 2901) and "needs a Mining Pick")
                      or (#pts == 0 and ("no known " .. s.node .. " in Flow's data")) or nil })
        end
    end

    if not reaches then
        add({ key = "skillplan:more:" .. prof, kind = "skill", points = { playerPoint() },
              text = string.format("%s past %d: open the %s window so Flow learns your recipes", prof, rank, prof),
              blockedBy = "Flow's guide data runs out here" })
    end
end

ns:Register("navGoal", "skillplan", {
    collect = function()
        wipe(handled)
        wipe(watched)
        local out = {}
        SP.lastTargets = SP:Targets()   -- (fishing feeds cooking: SP.PlannedCatch)
        SP.lastFromFish = 0
        SP.lastUpgrades = {}
        for prof, t in pairs(SP.lastTargets) do
            local ok, err = pcall(planProfession, prof, t, out)
            if not ok then ns:Log("skillplan", prof .. ": " .. tostring(err)) end
        end
        -- Drop stops with no place at all, unless blocked (those are listed, not routed).
        local kept, seen = {}, {}
        for _, g in ipairs(out) do
            g.points = g.points or {}
            if seen[g.key] then
                -- Two professions want the same stop (e.g. Copper Veins): one stop, both reasons.
                for _, d in ipairs(g.details or {}) do table.insert(seen[g.key].details, d) end
            elseif #g.points > 0 or g.blockedBy then
                kept[#kept + 1] = g; seen[g.key] = g
            end
        end
        SP.lastStops = kept
        return kept
    end,
})

-- Re-plan when an item the plan counts changes (ore mined, bar smelted...).
local lastCounts = {}
ns:On("BAG_UPDATE_DELAYED", function()
    local changed = false
    for id in pairs(watched) do
        local c = count(id)
        if lastCounts[id] ~= c then lastCounts[id] = c; changed = true end
    end
    if changed and ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect() end
    -- Moving things in or out of the bank: read it again.
    if bankOpen then rereadBank() end
end)
ns:On("SKILL_LINES_CHANGED", function() if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect() end end)

-- /flow prof plan: what the planner thinks, profession by profession.
function SP:Explain()
    local any = false
    for prof, t in pairs(SP:Targets()) do
        any = true
        local rank = A.Skill(prof)
        ns:Print(string.format("%s %s -> %d%s", prof, tostring(rank), t.target, t.quest and (" (" .. t.quest .. ")") or ""))
        local g = ns:Get("profGuide", prof)
        if g and g.steps and rank then
            local crafts, order = simulate(prof, g.steps, rank, t.target)
            for _, s in ipairs(order) do
                local mats = {}
                for id, q in pairs(s.mats or {}) do
                    mats[#mats + 1] = string.format("%d %s (have %d)", math.ceil(crafts[s]) * q, itemName(id), count(id))
                end
                print(string.format("  %d x %s: %s", math.ceil(crafts[s]), s.recipe, table.concat(mats, ", ")))
            end
        end
    end
    if not any then ns:Print("no profession needs raising right now.") end
    for _, g in ipairs(SP.lastStops or {}) do
        print(string.format("  stop: %s%s", g.text or g.key, g.blockedBy and ("  [blocked: " .. g.blockedBy .. "]") or ""))
    end
end

SP._simulate = simulate  -- for /flow test
