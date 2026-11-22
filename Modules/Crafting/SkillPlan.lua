-- Profession skill plans as route steps. For each profession you need to
-- raise (a quest such as "Raise your blacksmithing skill to 20", or a planned
-- profession that's behind your level) it works out, from what you have NOW:
--   what to make     the best skill-up per copper or per material at your
--                    skill (SP.Score), from Guides.lua's recipes and the ones
--                    your profession window showed (Recipes.lua)
--   what that needs  materials, minus what's in your bags and your bank
--   how to get them  take them out of the bank, smelt the ore you have, mine
--                    veins / kill mobs on this map, buy from a vendor
-- and hands the route planner the steps: gather, smelt, craft, learn, buy.
-- The planner mixes them with your quests by distance, so you mine the veins
-- that are on the way. Bags change -> plan changes (re-planned live).
-- Steps that can't happen yet (no Mining, no hammer, skill too low) are
-- listed as blocked, with the reason, instead of disappearing.

local _, ns = ...
local SP = {}
ns.skillPlan = SP

local A = ns.api
local MAX_POINTS = 60

local function count(id) return A.Count(id) end

local SIMPLE_WOOD = 4470                                  -- Basic Campfire uses one
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
-- A profession's own icon (its spell), for the arrow when you're at its step.
local function profIcon(prof)
    local _, icon = A.SpellInfo(prof)
    return icon
end
SP.ProfIcon = profIcon
-- A tool for this profession in your bags or equipped (any version of it).
-- The tool's own profession decides what counts: an engineer's Blacksmith
-- Hammer is any Blacksmith Hammer, not an Arclight Spanner.
local function hasTool(prof, id)
    if id and count(id) > 0 then return true end
    local D = ns.disposition
    if not (D and D.HasTool) then return false end
    return D:HasTool(id and D.ToolProfession and D:ToolProfession(id) or prof)
end
local function src(id) return ns:Get("itemSource", id) end
local function itemName(id)
    local s = src(id)
    return (s and s.name) or (A.ItemInfo and A.ItemInfo(id)) or ("item " .. id)
end

-- Do you carry the tool one step needs (an enchanter's rod, the Gyromatic
-- Micro-Adjustor)? By its item ID, else by its name in your bags: Forever's
-- items can have other IDs than the classic ones (review of pull request 22:
-- by ID alone, every enchant stayed blocked on a client with other IDs).
local function haveStepTool(id)
    if count(id) > 0 then return true end
    local s = src(id)
    local D = ns.disposition
    if not (s and s.name and D and D.EachBagItem) then return false end
    local found = false
    D:EachBagItem(function(_, _, link)
        if link and link:find("[" .. s.name .. "]", 1, true) then found = true end
    end)
    return found
end
SP._haveStepTool = haveStepTool   -- (tests)

-- Profession name as Flow's profession data spells it ("first aid" -> "First Aid").
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

-- What this zone asks of a gathering skill (0.35.252).
-- "I'm running around the Barrens, and there's Mageroyal all over, and I'm
-- missing it because I'm not high enough. One of our aims was to be high
-- enough to do everything in the next zone." The skill-up step was optional
-- (only when on the way) and, on Kalimdor, had no spots at all, so nothing
-- was planned. Now: a node that grows on the map you're on and that you
-- can't gather yet sets a target, and reaching it is a step like any other,
-- at the nodes here that you can gather and that still raise your skill.
-- Pure: the easiest node here that's beyond you ({ name, skill }), or nil.
function SP.ZoneNeed(rank, nodesHere)
    local best
    for _, n in ipairs(nodesHere or {}) do
        if n.skill > rank and (not best or n.skill < best.skill) then best = n end
    end
    return best
end
-- Which ones to pick (0.35.276). "It says my Herbalism is 35 and I need 50,
-- but it doesn't show me what plants to pick up." The step named the skill
-- and the herb you can't pick yet, not the ones you can. Pure: the names of
-- the nodes here that you can gather and that still raise your skill, the
-- hardest (the best for skill) first.
--   nodesHere: { { name, skill } }; raises(nodeSkill, rank) -> bool.
function SP.PickNames(nodesHere, rank, raises)
    local list = {}
    for _, n in ipairs(nodesHere or {}) do
        if n.skill <= rank and (not raises or raises(n.skill, rank)) then list[#list + 1] = n end
    end
    table.sort(list, function(a, b)
        if a.skill ~= b.skill then return a.skill > b.skill end
        return a.name < b.name
    end)
    local out = {}
    for _, n in ipairs(list) do out[#out + 1] = n.name end
    return out
end
-- Pure: "Earthroot, Silverleaf or Peacebloom" (at most `max` named, then "...").
function SP.NameList(names, max)
    max = max or 3
    local n = math.min(#names, max)
    if n == 0 then return nil end
    if n == 1 then return names[1] end
    local head = table.concat(names, ", ", 1, n - 1)
    return head .. " or " .. names[n]
end

-- An object's spots on a given map (as objectPoints, for a map you aren't on).
function SP.ObjectPointsOn(ids, names, map)
    local spawns = {}
    for i, id in ipairs(ids or {}) do
        local o = ns.quests:QuestieGet("GetObject", id)
        if o and o.spawns and not (names and names[i] and o.name ~= names[i]) then spawns[#spawns + 1] = o.spawns end
    end
    return ns.quests.SpreadPoints(spawns, MAX_POINTS, { map = map, onlyMap = true })
end
-- Pure: the first step of a plan that isn't gathering for a skill (those
-- are the steps this very rule adds: looking past them keeps it from
-- flipping on and off).
function SP.NextRealStep(plan)
    for _, s in ipairs(plan or {}) do
        local key = s.goal and s.goal.key or ""
        if not (type(key) == "string" and key:find("^skill:")) then return s end
    end
    return nil
end
-- Before you leave (0.35.283). "One of our aims was to be high enough to do
-- everything in the next zone." When your next step is in another zone, what
-- grows THERE counts too: the easiest herb there that's beyond you sets the
-- skill to reach, and the step is to gather here (what you can) first.
-- Pure: the map your route takes you to next when it's another zone than
-- yours; nil when the next step is in your zone (or unknown).
--   zoneOf(map) -> the zone a map belongs to.
function SP.AheadMap(hereMap, nextMap, zoneOf)
    if not (hereMap and nextMap) then return nil end
    local a, b = zoneOf(hereMap), zoneOf(nextMap)
    if not (a and b) or a == b then return nil end
    return b
end

-- The nodes of a profession that grow on the map you're on: { { name, skill } }.
local nodesHereCache = {}
-- map: another map than the one you're on (the zone you're headed for).
function SP.NodesHere(prof, map)
    local other = map ~= nil and map ~= here()
    map = map or here()
    if not map then return {} end
    local key = prof .. ":" .. map
    if nodesHereCache[key] then return nodesHereCache[key] end
    local out = {}
    for name, nd in ns:Each("gatherNode") do
        if nd.prof == prof then
            local names = {}
            for i = 1, #(nd.objects or {}) do names[i] = name end
            local ok, pts, onMap
            if other then ok, pts, onMap = pcall(SP.ObjectPointsOn, nd.objects, names, map)
            else ok, pts, onMap = pcall(objectPoints, nd.objects, names) end
            if ok and onMap and pts and #pts > 0 then out[#out + 1] = { name = name, skill = nd.skill or 1 } end
        end
    end
    -- (Kept only once Questie's data is there to ask.)
    if ns.quests.QuestieDB and ns.quests.QuestieDB() then nodesHereCache[key] = out end
    return out
end

-- Only the points on the continent you stand on: a trainer or vendor across
-- the sea is no stop while you level here (a flight or boat isn't a detour
-- worth sending you on for a recipe). Unknown continent (no position yet):
-- nothing is dropped.
local function sameContinent(pts)
    local p = playerPoint()
    local mine = p and p.cont
    if not mine then return pts end
    local out = {}
    for _, pt in ipairs(pts or {}) do
        local c = pt.cont
        if not c and pt.map and ns.nav and ns.nav.ToWorld then c = ns.nav:ToWorld(pt.map, pt.x, pt.y) end
        if not c or c == mine then out[#out + 1] = pt end
    end
    return out
end
SP._sameContinent = sameContinent  -- for /flow test

local function npcPoints(names)
    if ns.quests.NPCsByName then ns.quests:NPCsByName(names) end
    local map, mine, all = here(), {}, {}
    for _, n in ipairs(names or {}) do
        for _, pt in ipairs(ns.places:Points(n)) do
            if pt.map == map then mine[#mine + 1] = pt end
            all[#all + 1] = pt
        end
    end
    all = sameContinent(all)
    mine = sameContinent(mine)
    return #mine > 0 and mine or all, #mine > 0, all
end

-- What an item costs at a vendor (copper): the price a vendor's window last
-- showed you (recordPrices below). nil: unknown: Flow lists no prices of its
-- own. Buy steps carry it as `cost`, so the route lists them as blocked
-- until you can pay (Nav.lua); with no cost known, nothing is held back.
function SP.Price(id)
    local seen = ns.db and ns.db.prices and ns.db.prices[id]
    return type(seen) == "number" and seen or nil
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
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    local friendly = ns.places and ns.places.FriendlyTo
    for _, id in ipairs(item and item.vendors or {}) do
        local npc = ns.quests:QuestieGet("GetNPC", id)
        -- Only vendors who'll sell to you: the other faction's would send you
        -- across the world to someone who attacks you.
        if npc and npc.spawns and not (friendly and not friendly(npc.friendlyToFaction, mine)) then
            spawns[#spawns + 1] = npc.spawns; names[#names + 1] = npc.name
        end
    end
    local pts, onMap = spawnPoints(spawns)
    return sameContinent(pts), onMap, names
end

-- Cooking fires: you can make one anywhere (Basic Campfire) only with Simple
-- Wood AND Flint and Tinder in your bags; otherwise Flow plans the cooking at
-- a real fire: the cooking trainers cook by one (Tomas in Goldshire's inn).
local FLINT = 4471
function SP.CanCampfire()
    return A.SpellInfo("Basic Campfire") ~= nil and count(SIMPLE_WOOD) > 0 and count(FLINT) > 0
end
-- Where a station stands: every forge, anvil or fire Flow has seen work
-- for you (Actions.lua learns them when a recipe's "Requires Forge" is met),
-- plus the trainers that work by one (anvils and forges by the
-- blacksmiths, a fire by the cooks). All of them, in every zone: the route
-- picks the one quickest to reach, flights counted (Planner: air), not the
-- nearest of this zone's few.
SP.STATION_KINDS = { forge = { forge = true }, anvil = { anvil = true, forge = true }, fire = { fire = true } }
function SP.LearnedStationPoints(station, learned)
    local kinds, out = SP.STATION_KINDS[station], {}
    if not kinds then return out end
    for _, s in ipairs(learned or {}) do
        if kinds[s.kind] and s.cont and s.wx then
            -- (a copy: the route marks its points; these are saved)
            out[#out + 1] = { cont = s.cont, wx = s.wx, wy = s.wy, map = s.map, x = s.x, y = s.y, learned = true }
        end
    end
    return out
end
local function stationPoints(station)
    local trainers
    if station == "fire" then
        if SP.CanCampfire() then return nil end   -- make one where you stand
        trainers = "Cooking"
    elseif station == "anvil" or station == "forge" then
        trainers = "Blacksmithing"
    else
        return nil
    end
    local learned = ns.db.actions and ns.db.actions.stations
    local pts = SP.LearnedStationPoints(station, learned)
    local _, _, all = npcPoints(ns.places:TrainersFor(trainers))
    for _, pt in ipairs(all) do pts[#pts + 1] = pt end
    return pts
end

-------------------------------------------------------------------------------
-- Skill-up maths
-------------------------------------------------------------------------------

-- Chance of a skill point per craft at `rank`: only from the colour your
-- profession window showed (GetTradeSkillInfo's difficulty, Recipes.lua): at
-- the skill Flow last saw it at, or between two skills it showed the same
-- colour at (Recipes.lua keeps those: R.Observe; a colour only gets easier as
-- skill rises). Flow has no colour thresholds of its own: the game doesn't
-- say at which skill a recipe turns yellow, green or grey, so anywhere else
-- the chance is unknown and the step isn't a choice (0). How likely each
-- colour is to give a point is Flow's own estimate, not a game value.
local CHANCE = { optimal = 1, medium = 0.6, easy = 0.2, trivial = 0 }
local function chance(prof, step, rank)
    local R = ns.recipes
    local known, seenRank = R:Known(prof)
    local r = known and known[step.recipe]
    if not r then return 0 end
    local diff
    if seenRank and seenRank == math.floor(rank) then
        diff = r.diff
    elseif R.ColourAt and R.History then
        diff = R.ColourAt(R:History(prof), step.recipe, rank)
    end
    return CHANCE[diff] or 0
end

-- The skill a recipe is learned at: what a trainer's window asked for it
-- (Trainer.lua keeps it), else the "Requires <profession> (N)" line of the
-- recipe item's own tooltip. nil: unknown. Flow lists none of its own.
-- Pure: lines = { { left = .. } }, pattern = Actions.lua's _MIN_SKILL.
function SP.LearnFromLines(prof, lines, pattern)
    if type(pattern) ~= "string" then return nil end
    for _, l in ipairs(lines or {}) do
        if type(l) == "table" and type(l.left) == "string" then
            local p, need = l.left:match(pattern)
            if p == prof and tonumber(need) then return tonumber(need) end
        end
    end
    return nil
end
function SP.LearnSkill(prof, s)
    if not s then return nil end
    local seen = ns.db and ns.db.prof and ns.db.prof.recipeLearn and ns.db.prof.recipeLearn[prof]
    local n = type(seen) == "table" and seen[s.recipe] or nil
    if type(n) == "number" then return n end
    if s.recipeItem and ns.gear and ns.gear.TooltipLines and ns.actions and ns.actions._MIN_SKILL then
        local ok, lines = pcall(ns.gear.TooltipLines, ns.gear, "item:" .. s.recipeItem)
        if ok then return SP.LearnFromLines(prof, lines, ns.actions._MIN_SKILL) end
    end
    return nil
end
SP.LEARN_UNKNOWN = "learn skill unknown: check the trainer"

-- Two steps skill up alike at `rank` when the profession window showed both
-- at the same colour at that skill. No colour seen: not known to be alike.
local function alike(prof, a, b, rank)
    if not (prof and rank) then return false end
    local c = chance(prof, a, rank)
    return c > 0 and c == chance(prof, b, rank)
end

-- What one of an item costs (copper): the auction house price Flow last saw,
-- else a vendor's price, else what a vendor pays you for it (a low guess,
-- but it still ranks rare materials above common ones). nil: no idea.
function SP.MatCost(id)
    local ok, ah = pcall(function() return ns.auction and ns.auction:Price(id) end)
    if ok and ah and ah > 0 then return ah end
    local v = SP.Price(id)
    if v and v > 0 then return v end
    -- (ns.api.ItemInfo: some item globals are gone on Forever.)
    local ok2, sell = pcall(function() return A.ItemInfo and select(11, A.ItemInfo(id)) end)
    if ok2 and sell and sell > 0 then return sell end
end

-- The recipes that still give skill, cheapest materials per skill point
-- first. `known`: what your profession window showed (recipes:Known);
-- costOf(itemID) -> copper or nil (SP.MatCost unless given).
-- -> { { recipe, item, reagents, diff, cost, perPoint, unpriced } }
function SP.CheapSkillUps(known, costOf)
    costOf = costOf or SP.MatCost
    local out = {}
    for name, r in pairs(known or {}) do
        local c = type(r) == "table" and CHANCE[r.diff] or 0
        if c > 0 and r.reagents and next(r.reagents) and not r.partial then
            local cost, unpriced = 0, false
            for id, q in pairs(r.reagents) do
                local p = costOf(id)
                if p then cost = cost + p * q else unpriced = true end
            end
            out[#out + 1] = { recipe = name, item = r.item, reagents = r.reagents, diff = r.diff,
                              cost = cost, perPoint = cost / c, unpriced = unpriced or nil }
        end
    end
    table.sort(out, function(a, b)
        if (a.unpriced or false) ~= (b.unpriced or false) then return not a.unpriced end
        if a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
        return a.recipe < b.recipe
    end)
    return out
end

-- The recipes you can make right now from your bags that still give skill,
-- most expected skill points first. Points = how many you can make x the
-- chance each gives a point (it ignores colours shifting as you climb).
-- Ranked by whole points, and on a tie the surer recipe first: orange gives
-- a point every time, while 2 yellows can give none (owner made 2 yellow
-- Copper Chain Pants, listed above 2 orange belts, and got nothing).
-- bagsOf(itemID) -> count (tests); default: your bags.
-- -> { { recipe, item, reagents, diff, count, points, chance } }
function SP.MakeNowSkillUps(known, bagsOf)
    bagsOf = bagsOf or count
    local out = {}
    for name, r in pairs(known or {}) do
        local c = type(r) == "table" and CHANCE[r.diff] or 0
        if c > 0 and r.reagents and next(r.reagents) and not r.partial then
            local n
            for id, q in pairs(r.reagents) do
                local can = q > 0 and math.floor((bagsOf(id) or 0) / q) or 0
                n = n and math.min(n, can) or can
            end
            if n and n > 0 then
                out[#out + 1] = { recipe = name, item = r.item, reagents = r.reagents, diff = r.diff,
                                  count = n, points = n * c, chance = c }
            end
        end
    end
    table.sort(out, function(a, b)
        local pa, pb = math.floor(a.points + 1e-9), math.floor(b.points + 1e-9)
        if pa ~= pb then return pa > pb end
        if a.chance ~= b.chance then return a.chance > b.chance end
        if a.points ~= b.points then return a.points > b.points end
        return a.recipe < b.recipe
    end)
    return out
end

local function matUnits(step)
    local n = 0
    for _, q in pairs(step.mats or {}) do n = n + q end
    return math.max(n, 1)
end

-- A step your faction can use (a step may name one: its recipe or meat is
-- only sold or found on that side).
local function forYou(s)
    if not s.faction then return true end
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    return not mine or mine == s.faction
end

-- What one craft of a step costs (copper), or nil when a material has no price.
local function perCraft(step, costOf)
    local total = 0
    for id, q in pairs(step.mats or {}) do
        local p = costOf(id)
        if not p then return nil end
        total = total + p * q
    end
    return total
end

-- How good a step is at `rank` for what you want, worked out from the step
-- itself: the chance of a skill point (the colour your window showed, else
-- the step's colours), what its materials cost, what's in your bags.
--   goal = { prof, prefer = "cheap" | "materials" | "use-bags",
--            costOf = function(itemID) -> copper or nil (SP.MatCost unless given) }
--     cheap: skill per copper of materials (priced = false when a material
--            has no price; then it's skill per material, as "materials")
--     materials: skill per material (fewest to gather or buy)
--     use-bags: as materials; simulate puts what you can make now first
--   have = function(itemID) -> count in bags (nil: nothing counts as carried)
-- A recipe made from fish is worth nothing unless you carry the fish: Flow
-- doesn't send you fishing for another profession.
-- -> value (0: not a choice), chance, priced, makeable
function SP.Score(step, rank, goal, have)
    goal = goal or {}
    if not forYou(step) then return 0, 0, false, false end
    local c = chance(goal.prof, step, rank)
    if c <= 0 then return 0, 0, false, false end
    local makeable = true
    for id, q in pairs(step.mats or {}) do
        if ((have and have(id)) or 0) < q then
            makeable = false
            local s = src(id)
            if s and s.fished then return 0, c, false, false end
        end
    end
    if goal.prefer == "cheap" then
        local per = perCraft(step, goal.costOf or SP.MatCost)
        if per and per > 0 then return c / per, c, true, makeable end
    end
    return c / matUnits(step), c, false, makeable
end

-- Expected crafts per step to go from rank to target: at each point the step
-- SP.Score rates best. When two are as good (Charred Wolf Meat, Roasted Boar
-- Meat), the one whose materials are in your bags wins, so what you already
-- carry gets used before anything is farmed. With "cheap" and any choice
-- unpriced, every choice is rated by materials instead (copper and material
-- counts don't compare). Nothing left that gives skill: the plan stops there.
-- `have` (optional): item ID -> count in bags; defaults to your bags.
-- `goal` (optional): SP.Score's; prefer defaults to "materials".
-- -> crafts, order, reaches, spans, rank reached
local simulate
function simulate(prof, steps, rank, target, have, goal)
    goal = goal or {}
    local crafts, order, spans = {}, {}, {}   -- spans: step -> { from, to } skill it covers
    local left = {}
    local function bag(id)
        if left[id] == nil then left[id] = (have and have[id]) or (not have and count(id)) or 0 end
        return left[id]
    end
    local costOf, prices = goal.costOf or SP.MatCost, {}
    local rate = { prof = prof, costOf = function(id)
        if prices[id] == nil then prices[id] = costOf(id) or false end
        return prices[id] or nil
    end }
    local want = goal.prefer or "materials"
    local function run(prefer)
        rate.prefer = prefer
        local best, bestV, bestC, bestHave, unpriced
        for _, s in ipairs(steps) do
            local v, c, priced, h = SP.Score(s, rank, rate, bag)
            if v > 0 then
                if prefer == "cheap" and not priced then unpriced = true end
                local better
                if not bestV then better = true
                elseif prefer == "use-bags" and h ~= bestHave then better = h
                else better = v > bestV or (v == bestV and h and not bestHave) end
                if better then best, bestV, bestC, bestHave = s, v, c, h end
            end
        end
        return best, bestC, bestHave, unpriced
    end
    local guard = 0
    while rank < target and guard < 2000 do
        guard = guard + 1
        local best, bestC, bestHave, unpriced = run(want)
        if want == "cheap" and unpriced then best, bestC, bestHave = run("materials") end
        if not best then break end
        if not crafts[best] then crafts[best] = 0; order[#order + 1] = best; spans[best] = { math.floor(rank) } end
        crafts[best] = crafts[best] + 1
        if bestHave then for id, q in pairs(best.mats or {}) do left[id] = bag(id) - q end end
        rank = rank + bestC
        spans[best][2] = math.min(math.floor(rank + 1e-9), target)
    end
    return crafts, order, rank >= target, spans, rank
end

-- Materials that stand in for `id`: dropped materials of other steps that
-- skill up like the step using `id` at `rank` (the window showed both at the
-- same colour there, one material each). `id` itself comes first.
function SP.Alternatives(steps, id, prof, rank)
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
        if s ~= mine and other and other ~= id and os and (os.drops or os.looted) and alike(prof, s, mine, rank) then
            out[#out + 1] = other
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- Drop rates: how many kills a dropped material really takes. Only from your
-- own loot (SP.RecordLoot): Flow lists no rates of its own.
-------------------------------------------------------------------------------

-- -> rate, kills. rate = what dropped / what you killed; nil until one has
-- dropped in a counted kill (unknown, not a guess).
function SP.DropRate(id)
    local d = ns.db and ns.db.crafting and ns.db.crafting.drops and ns.db.crafting.drops[id]
    local kills, got = d and d.kills or 0, d and d.got or 0
    if kills > 0 and got > 0 then return got / kills, kills end
    return nil, kills
end
-- Pure: how many kills for `n` of a material, from the rates seen of each
-- material that will do ({ rate or false, ... }). nil: any of them unknown.
function SP.KillsFor(n, rates)
    local sum, count = 0, 0
    for _, r in ipairs(rates or {}) do
        if type(r) ~= "number" or r <= 0 then return nil end
        sum = sum + r; count = count + 1
    end
    if count == 0 then return nil end
    return math.ceil(n / (sum / count))
end

-- Pure: the words of a farm step. kills nil: how many it takes is unknown,
-- and no number is made up for it. mobs empty: what drops it is unknown.
function SP.FarmText(what, progress, kills)
    if kills then return string.format("Loot %s %s (about %d kills)", what, progress, kills) end
    return string.format("Loot %s %s", what, progress)
end
function SP.FarmDetails(kills, n, mobs)
    local out = {}
    if kills then
        out[1] = string.format("About %d kills for %d, going by your own loot so far.", kills, n)
    else
        out[1] = "How many kills it takes is unknown: Flow counts it from your own loot once it knows the mobs."
    end
    if #(mobs or {}) > 0 then
        out[2] = "Drops from: " .. table.concat(mobs, ", ") .. ". (The mobs you've looted it from; others may drop it too.)"
    else
        out[2] = "Which mobs drop it is unknown to Flow: the item's tooltip or a kill will tell you."
    end
    return out
end
-- Pure: the words of a gather step. No node count: how much a node gives
-- isn't something Flow has read from the game.
SP.GATHER_UNKNOWN = "How many nodes it takes, and whether your skill is enough for them, is unknown to Flow: the node's tooltip says what it asks."
function SP.GatherText(gather, node, items)
    return string.format("%s %s for %s", gather == "Mining" and "Mine" or "Gather", node, table.concat(items or {}, ", "))
end

-- Pure: the mobs you've looted a material from, most often first
-- ({ [mobName] = count } -> { names }). nil or empty: none seen.
function SP.SeenMobsFrom(seen)
    local out = {}
    for name, n in pairs(type(seen) == "table" and seen or {}) do
        if type(name) == "string" and type(n) == "number" and n > 0 then out[#out + 1] = name end
    end
    table.sort(out, function(a, b)
        if seen[a] ~= seen[b] then return seen[a] > seen[b] end
        return a < b
    end)
    return out
end
-- The mobs you've looted item `id` from (ns.db.crafting.dropMobs, filled only
-- by SP.RecordLoot from your own loot: Flow lists none of its own).
function SP.SeenMobs(id, c)
    c = c or (ns.db and ns.db.crafting)
    local all = type(c) == "table" and c.dropMobs
    return SP.SeenMobsFrom(type(all) == "table" and all[id] or nil)
end
-- Pure: the mobs a farm step names: the ones listed for the material (a
-- registered `drops`) and the ones you've looted it from, each once.
function SP.FarmMobs(listed, seen, into, have)
    into, have = into or {}, have or {}
    for _, list in ipairs({ listed or {}, seen or {} }) do
        for _, m in ipairs(list) do
            if type(m) == "string" and not have[m:lower()] then
                have[m:lower()] = true
                into[#into + 1] = m
            end
        end
    end
    return into, have
end

-- Looting a mob. Once per corpse:
--   * the mob is known to drop a material (listed in its `drops`, or you've
--     looted it from that mob before): one kill for the material, and one
--     "got" if it was in the loot. (The loot that first showed a mob drops
--     it isn't counted as a kill: it would count only the lucky one.)
--   * a looted material (`looted` or `drops`) was in the loot: the mob is
--     remembered for it, ns.db.crafting.dropMobs[itemID][mobName] = times.
-- Pure: one corpse's loot counted into `c` (the crafting data: c.drops,
-- c.dropMobs, made if missing or damaged). sources = { [itemID] = source }.
function SP.CountLoot(c, sources, mob, looted)
    if type(c) ~= "table" or type(mob) ~= "string" or mob == "" then return end
    looted = type(looted) == "table" and looted or {}
    if type(c.drops) ~= "table" then c.drops = {} end
    if type(c.dropMobs) ~= "table" then c.dropMobs = {} end
    local lower = mob:lower()
    for id, s in pairs(sources or {}) do
        if type(id) == "number" and type(s) == "table" and (s.drops or s.looted) then
            local seen = type(c.dropMobs[id]) == "table" and c.dropMobs[id] or nil
            local known = seen ~= nil and type(seen[mob]) == "number"
            for _, n in ipairs(s.drops or {}) do
                if n:lower() == lower then known = true break end
            end
            local got = (looted[id] or (s.name and looted[s.name:lower()])) and true or false
            if known then
                local d = c.drops[id] or { kills = 0, got = 0 }
                c.drops[id] = d
                d.kills = d.kills + 1
                if got then d.got = d.got + 1 end
            end
            if got then
                seen = seen or {}
                c.dropMobs[id] = seen
                seen[mob] = (type(seen[mob]) == "number" and seen[mob] or 0) + 1
            end
        end
    end
end
local lastCorpse
function SP.RecordLoot(mob, guid, looted)
    -- (In a group the game hides a corpse's name and ID: comparing a hidden
    -- value is an error, 0.35.209. Nothing to count then.)
    mob, guid = A.Safe(mob), A.Safe(guid)
    if type(mob) ~= "string" or (guid and guid == lastCorpse) then return end
    lastCorpse = guid
    local sources = {}
    for id, s in ns:Each("itemSource") do sources[id] = s end
    SP.CountLoot(ns.db.crafting, sources, mob, looted)
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


-- The skill that's right for your level, per profession. Crafting aims for
-- the cap of the highest tier you can train (A.ProfessionTarget, from what
-- trainers showed Flow). A profession can give
-- its own `pace` (level -> skill) when the general curve asks too much.
-- That curve is Flow's own estimate (Guides.lua), so it is said as "about".
-- Pure: is the skill to aim for Flow's own estimate (not a tier cap)?
function SP.PaceIsEstimate(prof)
    local g = prof and ns:Get("profGuide", prof)
    return (g and g.pace) ~= nil
end
-- Pure: "aim for ..." in words: "about 75 at level 20 (Flow's own estimate)"
-- or "150 at level 20 (the highest cap you can train)"; level nil: the number.
function SP.AimText(prof, target, level)
    local own = SP.PaceIsEstimate(prof)
    local n = (own and "about " or "") .. tostring(target)
    if not level then return n end
    return string.format("%s at level %d (%s)", n, level, own and "Flow's own estimate" or "the highest cap you can train")
end
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

-- Skinning by beast level: level 10 and under needs 1, 11 to 20 need
-- (level - 10) x 10, above 20 level x 5 (60 -> 300). Origin not established:
-- no record says where this rule came from and Flow never read it from the
-- game (a corpse's tooltip, "Requires Skinning N", is the truth there). Kept
-- because the Skinning plan has nothing else to go on.
-- Pure: the skill a beast of that level needs.
function SP.SkinSkill(level)
    level = math.floor(tonumber(level) or 1)
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end
-- Pure: the highest beast level that skill can skin (the inverse of SkinSkill).
function SP.SkinMaxLevel(rank)
    rank = math.floor(tonumber(rank) or 0)
    if rank < 10 then return 10 end
    if rank < 100 then return 10 + math.floor(rank / 10) end
    return math.floor(rank / 5)
end

function SP:Targets()
    -- A quest that asks for a skill keeps its step even with Professions
    -- switched off (map list, arrow menu): the quest can't be finished without
    -- it. Its step names the quest (forQuest) and counts as that quest's step
    -- (the "quests" route kind), not as a profession stop. Professions off:
    -- nothing else, no skill-ups for your level.
    local out = {}
    for _, q in ipairs(ns.quests.LogEntries and ns.quests.LogEntries() or {}) do
        for _, o in ipairs(q.objectives or {}) do
            local prof, n = SP.ParseObjective(o.text)
            if prof and not o.finished and (not out[prof] or out[prof].target < n) then
                out[prof] = { target = n, quest = q.title, required = true }
            end
        end
    end
    if ns.nav:Includes("professions") then
        local level = UnitLevel("player")
        for _, p in ipairs(ns:ProfessionPlan() or {}) do
            local g = ns:Get("profGuide", p.name)
            local rank = A.Skill(p.name)
            local want = SP.Pace(p.name, level)
            -- Gathering behind your level is the errands' optional skill-up step.
            -- A craft plan starts when you're 10+ behind and then holds until
            -- you reach its target (it used to vanish once you were within
            -- 10, halfway through crafting, so you didn't know when to stop).
            local active = ns.db.crafting.active or {}
            ns.db.crafting.active = active
            -- Gathering: what grows where you are and is beyond you.
            if g and g.kind == "gather" and g.spots and rank and not out[p.name] then
                local okN, need = pcall(function() return SP.ZoneNeed(rank, SP.NodesHere(p.name)) end)
                -- What's beyond you HERE: gathered on the way, behind your quests
                -- (0.35.285: "I'm not ready to leave the area: that should be
                -- bumped down so I'm doing the actual quests"): optional, so the
                -- route only takes it in when it's near the way you're going.
                if okN and need then out[p.name] = { target = need.skill, zone = need.name, optional = true } end
                -- Nothing here is beyond you: the zone your route goes to next.
                -- That one comes first, before you leave ("if they're about to
                -- leave the area, that's when it should focus on their skills").
                local nextStep = ns.nav and ns.nav.plan and SP.NextRealStep(ns.nav.plan)
                if not out[p.name] and nextStep and ns.nav.ZoneOf then
                    local pt = nextStep.point
                    local ahead = SP.AheadMap(here(), pt and pt.map, ns.nav.ZoneOf)
                    if ahead then
                        local okA, needA = pcall(function() return SP.ZoneNeed(rank, SP.NodesHere(p.name, ahead)) end)
                        if okA and needA then
                            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(ahead)
                            out[p.name] = { target = needA.skill, zone = needA.name, ahead = info and info.name or "the next zone" }
                        end
                    end
                end
            end
            -- Skinning: enough to skin the beasts of your own level. Optional:
            -- it's done on the beasts your quests bring you to, never a detour.
            if g and g.skin and rank and not out[p.name] then
                local wantSkin = math.min(SP.SkinSkill(level), 300)
                if rank < wantSkin then out[p.name] = { target = wantSkin, optional = true } end
            end
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

-- Professions whose steps come from here (Goals.lua skips its own skill-up).
local handled = {}
function SP:Handles(prof)
    if handled[prof] then return true end
    local ok, t = pcall(SP.Targets, SP)
    return ok and t[prof] ~= nil or false
end

-------------------------------------------------------------------------------
-- Steps
-------------------------------------------------------------------------------

local function why(t, prof, rank)
    if t.quest then return string.format("%s %d -> %d (needed for quest %s)", prof, rank, t.target, t.quest) end
    return string.format("%s %d -> %d (right for your level)", prof, rank, t.target)
end

local watched = {}  -- item IDs whose counts change the plan

-- The next skill tier: how you learn it, and whether you can now.
-- The trainer teaches it from 25 below the cap, so it goes on the route then,
-- not once you're stuck. The character level a tier asks is NOT listed here:
-- it is only what a profession trainer's window said (GetTrainerServiceLevelReq,
-- Trainer.lua -> ns.db.prof.tierSeen). Until Flow has read it the level is
-- unknown (tier.level nil): it holds nothing back, and the step says to check
-- the trainer.
-- Cooking, First Aid and Fishing learn Expert from a book and Artisan from a
-- quest; everything else from its trainer.
local TIER_NAME = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }
local TIER_BOOK = { Cooking = 16072, ["First Aid"] = 16084, Fishing = 16083 }
-- Clamlette Surprise; Triage (Horde, Alliance); Nat Pagle, Angler Extreme.
local TIER_QUEST = { Cooking = { 6610 }, ["First Aid"] = { 6622, 6624 }, Fishing = { 6607 } }
--
-- What the trainer itself says wins over those numbers: each time you open a
-- profession trainer, Flow reads what the next tier asks for and what it
-- costs (Trainer.lua, kept per character in ns.db.prof.tierSeen) and goes by
-- that from then on. Read on WoW: Forever on 2026-11-13: "Journeyman
-- Herbalism: asks for Herbalism 50; costs 500" (5 silver), no level asked:
-- classic's skill rule holds here.
--
-- A tier has a PRICE, and that was the trouble behind "Journeyman Skinning
-- ... I don't have it, but it is taking me there": the skill was there (58),
-- the 5 silver wasn't (2s 30c), and Flow sent the route to the trainer
-- anyway. The step now carries the price (SP.TierCost), so the route waits
-- until you can pay, as it does for your class trainer. (0.35.173 blamed the
-- profession list and 0.35.174 a level rule; both were wrong.)
--   seen: { cap, level, skill, cost, category, atLevel, atRank } as read at
--         the trainer for this cap, or nil / false (never looked).
--   -> { name, cap, level (nil: unknown), skill, cost, how = "trainer" | "book" | "quest", book, quests, ready, wait } or nil
function SP.TierName(max) return max and TIER_NAME[max] or nil end
function SP.TierSeen(prof, max)
    local s = ns.db and ns.db.prof and ns.db.prof.tierSeen and ns.db.prof.tierSeen[prof]
    return (s and s.cap == max) and s or nil
end
-- What a trainer charges for the tier after this cap, in copper: what this
-- profession's trainer said, else what any profession's trainer said for the
-- same tier (they charge alike), else the one price Flow has seen for itself
-- (Journeyman, 5 silver). nil: not known, so nothing to wait for.
-- The second value says where the price came from.
--   seenAll: ns.db.prof.tierSeen ({ [profession] = { cap, cost } })
SP.TIER_COST = { [75] = 500 }
SP.TIER_COST_SOURCE = { [75] = "read at a WoW: Forever Herbalism trainer, 2026-11-13" }
function SP.TierCost(prof, max, seenAll)
    local mine = seenAll and seenAll[prof]
    if mine and mine.cap == max and (mine.cost or 0) > 0 then return mine.cost, "the " .. prof .. " trainer's price" end
    for other, s in pairs(seenAll or {}) do
        if s.cap == max and (s.cost or 0) > 0 then return s.cost, "what the " .. tostring(other) .. " trainer asked for this tier" end
    end
    return SP.TIER_COST[max], SP.TIER_COST_SOURCE[max]
end
-- Estimates for a tier nobody has priced yet (Expert, Artisan): only with a
-- recorded source ({ cost = copper, source = "where and when it was read" }).
-- None is recorded, so this is empty: Flow doesn't invent prices. An
-- estimate is shown as "about", never waited on as if certain.
SP.TIER_ESTIMATE = {}
-- The line a trainer tier step shows about its price:
--   cost, source: from SP.TierCost (cost nil when unknown).
--   -> text, estimate (copper, or nil)
function SP.TierPriceLine(max, cost, source, money)
    money = money or ns.Money
    if cost then
        return string.format("Costs %s (%s).", money(cost), source or "seen at a trainer"), nil
    end
    local e = SP.TIER_ESTIMATE[max]
    if e and (e.cost or 0) > 0 and e.source then
        return string.format("Costs about %s (%s): check the trainer.", money(e.cost), e.source), e.cost
    end
    return "Price unknown\226\128\148check the trainer.", nil
end
function SP.Tier(prof, rank, max, level, seen)
    if not (rank and max and max > 0 and max < 300) then return nil end
    local t = { name = TIER_NAME[max] or "next", cap = max, skill = max - 25 }
    if max == 150 and TIER_BOOK[prof] then t.how, t.book = "book", TIER_BOOK[prof]
    elseif max == 225 and TIER_QUEST[prof] then
        -- (The Artisan quests ask for the cap itself, 225, not 25 below it.)
        t.how, t.quests, t.skill = "quest", TIER_QUEST[prof], max
    else t.how = "trainer" end
    if seen and t.how == "trainer" then
        t.level = tonumber(seen.level) or 0   -- (0: the trainer asked no level)
        if (seen.skill or 0) > 0 then t.skill = seen.skill end
        if (seen.cost or 0) > 0 then t.cost = seen.cost end
        t.seen = true
    end
    t.ready = rank >= t.skill and (t.level == nil or (level or 0) >= t.level)
    -- Red at the trainer although the level and skill it named were met:
    -- something else is in the way. Not on the route again until you've
    -- gained a level or five skill points since.
    if t.ready and seen and t.how == "trainer" and seen.category == "unavailable"
        and (level or 0) <= (seen.atLevel or 0) and rank < (seen.atRank or 0) + 5 then
        t.ready, t.wait = false, "it was red at the trainer"
    end
    return t
end
-- Pure: what a tier that isn't ready yet asks, in words. A level only when a
-- trainer's window gave one; unknown is said as unknown.
function SP.TierNeeds(tier)
    if not tier then return "check the trainer" end
    local skill = string.format("skill %d", tier.skill or 0)
    if tier.level == nil then return "needs " .. skill .. "; level unknown: check the trainer" end
    if tier.level > 0 then return string.format("needs level %d and %s", tier.level, skill) end
    return "needs " .. skill
end
-- Pure: why a capped profession's next tier can't be learned yet.
function SP.TierBlock(after, tier, level)
    if tier and tier.wait then return after .. ": " .. tier.wait end
    if tier and tier.level and tier.level > (level or 0) then return string.format("%s needs level %d", after, tier.level) end
    return after .. ": " .. SP.TierNeeds(tier)
end

-- Where a quest's giver stands, from Questie: points (nil if unknown), the
-- giver's name and the quest.
local function questGiver(id)
    local Q = ns.quests
    local q = Q:QuestieGet("GetQuest", id)
    local giver = q and q.Starts and q.Starts.NPC and q.Starts.NPC[1]
    local npc = giver and Q:QuestieGet("GetNPC", giver)
    if not (npc and npc.spawns) then return nil, nil, q end
    return spawnPoints({ npc.spawns }), npc.name, q
end

-- The route step that learns the next tier (key "train:<prof>"), once you
-- can: the trainer, the book (buy it, then read it) or the quest's giver.
-- nil while you can't yet, or while the quest is already in your log.
-- deps: the craft steps past your cap wait for it.
function SP.TierGoal(prof, level, optional)
    local rank, max = A.Skill(prof)
    local tier = SP.Tier(prof, rank, max, level, SP.TierSeen(prof, max))
    if not (tier and tier.ready) then return nil, tier end
    local key, title = "train:" .. prof, tier.name .. " " .. prof
    local why = string.format("%s %d of %d: %s raises the cap to %d.", prof, rank, max, title, max + 75)
    -- (cost: what a trainer charges for this tier; the route waits until you can pay.
    -- A book or a quest has its own price or none.)
    -- Unknown (no trainer read yet, nothing recorded): the step says so
    -- (costUnknown) instead of waiting on a made-up price.
    local cost, source, priceLine, estimate
    if tier.how == "trainer" then
        cost, source = SP.TierCost(prof, max, ns.db and ns.db.prof and ns.db.prof.tierSeen)
        priceLine, estimate = SP.TierPriceLine(max, cost, source)
    end
    local base = { key = key, title = title, optional = optional, weight = optional and 1.4 or 1.0, cost = cost,
                   costEstimate = estimate, costUnknown = (tier.how == "trainer" and not cost) or nil }
    local function goal(g)
        for k, v in pairs(base) do if g[k] == nil then g[k] = v end end
        return g
    end
    if tier.how == "book" then
        local id = tier.book
        watched[id] = true
        local name = itemName(id)
        if count(id) > 0 then
            return goal({ kind = "skill", points = { playerPoint() }, anywhere = true,
                          text = string.format("Read %s (in your bags): %s", name, title),
                          details = { why, "Right-click it in your bags to learn it." } }), tier
        end
        local pts, _, sellers = vendorPoints(id)
        return goal({ kind = "merchant", points = pts, npcs = sellers, cost = SP.Price(id),
                      text = string.format("Buy %s: %s", name, title),
                      details = { why, "No trainer teaches it: the book does. Read it once you have it.",
                                  #sellers > 0 and ("Sold by " .. table.concat(sellers, " or ") .. ".") or nil },
                      blockedBy = #pts == 0 and ("Flow doesn't know who sells " .. name) or nil }), tier
    end
    if tier.how == "quest" then
        local Q = ns.quests
        for _, id in ipairs(tier.quests) do
            if Q:IsCompleted(id) or Q:InLog(id) then return nil, tier end
        end
        for _, id in ipairs(tier.quests) do
            local pts, giver, q = questGiver(id)
            local fits = q and (not ns.dungeons or not ns.dungeons.Eligible or ns.dungeons.Eligible(q))
            if fits and giver then
                return goal({ kind = "accept", points = pts, npcs = { giver },
                              text = string.format("Accept %s (%s): %s", q.name or "the quest", giver, title),
                              details = { why, string.format("No trainer teaches it: %s's quest does.", giver) },
                              blockedBy = #pts == 0 and ("Flow doesn't know where " .. giver .. " stands") or nil }), tier
            end
        end
        return goal({ kind = "skill", points = { playerPoint() },
                      text = title .. ": a quest teaches it",
                      details = { why },
                      blockedBy = "Flow needs Questie to find the quest's giver" }), tier
    end
    -- Artisan is taught by one trainer per side (`artisan`), not the
    -- city's (Enchanting: Annora, inside Uldaman).
    local g = ns:Get("profGuide", prof)
    local names = (tier.cap == 225 and g and g.artisan) and SP.StepTrainers(prof, { trainer = g.artisan })
        or ns.places:TrainersFor(prof)
    local pts = npcPoints(names)
    return goal({ points = pts, npcs = names,
                  text = string.format("Train %s (%s)", title, #names > 0 and table.concat(names, " / ") or "trainer"),
                  details = { why, priceLine, #names > 0 and ("At " .. table.concat(names, " or ") .. ".") or nil },
                  blockedBy = #pts == 0 and ("no known " .. prof .. " trainer") or nil }), tier
end

-- The tool a profession needs (`tool`: Mining Pick, Blacksmith Hammer,
-- Fishing Pole) when you don't have one: a "Buy a X" step, and X's name so
-- the steps that need it can say "needs a X". Nothing when you have it.
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

-- A lure for a profession that uses one (Fishing: `lure`, the Shiny
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

-- A fished material whose step skills up like the step using `id` at `rank`
-- (same colour in the window there). Returns the step, the fish's source
-- entry and its item ID.
function SP.FishAlternative(steps, id, prof, rank)
    local mine
    for _, s in ipairs(steps or {}) do
        if s.mats and s.mats[id] then mine = s break end
    end
    if not mine then return nil end
    for _, s in ipairs(steps) do
        for mid in pairs(s.mats or {}) do
            local ms = src(mid)
            if s ~= mine and ms and ms.fished and alike(prof, s, mine, rank) then
                return s, ms, mid
            end
        end
    end
end

-- A recipe that's a quest's reward (step `quest = { id, npc }`): accept the
-- quest at its giver. Nothing once it's in your log (the quest's own steps
-- take over) or done.
local function questRecipeStop(s)
    local Q, id = ns.quests, s.quest.id
    if Q:IsCompleted(id) or Q:InLog(id) then return nil end
    local pts, giver, q = questGiver(id)
    giver = giver or s.quest.npc
    if not pts and giver then pts = npcPoints({ giver }) end
    pts = pts or {}
    local who = giver or "its giver"
    local need = q and q.requiredLevel
    local low = need and UnitLevel and (UnitLevel("player") or 0) < need
    return { key = "recipequest:" .. id, kind = "accept", points = pts, npcs = giver and { giver } or nil,
             text = string.format("Accept %s (%s): %s plans", (q and q.name) or "the quest", who, s.recipe),
             details = { string.format("Flow's plan makes %s here. No vendor or trainer has it: %s's quest gives it.", s.recipe, who) },
             blockedBy = (low and string.format("needs level %d", need))
                 or (#pts == 0 and ("Flow doesn't know where " .. who .. " stands")) or nil }
end

-- A bought recipe goes on the route once your skill is within this many
-- points of what it needs, not before: "Longjaw Mud Snapper requires 50" and
-- Flow sent a cook at 32 to buy it, then asked to use a recipe the game
-- wouldn't let them learn (0.35.172). Pure: rank nil = unknown, so yes.
SP.BUY_AHEAD = 10
function SP.RecipeDue(learn, rank, ahead)
    if not (learn and rank) then return true end
    return rank >= learn - (ahead or SP.BUY_AHEAD)
end
-- Pure: send you to the trainer for a recipe now? Yes once your skill meets
-- what the trainer asked for it; also when Flow hasn't seen what it asks
-- (learn nil: the step says so, and the trainer's window settles it).
function SP.TrainNow(learn, rank)
    if type(learn) ~= "number" then return true end
    return type(rank) == "number" and rank >= learn
end

-- Pure: buy a craft's vendor materials now? Only when the craft is
-- otherwise ready: you know the recipe and nothing else is missing.
--   recipeKnown: you can make it; shorts: { [itemID] = how many you lack };
--   fromVendor(id) -> true for what a vendor sells.
function SP.BuyNow(recipeKnown, shorts, fromVendor)
    if not recipeKnown then return false end
    for id, short in pairs(shorts or {}) do
        if short > 0 and not fromVendor(id) then return false end
    end
    return true
end

-- Pure: why a "Make X" step waits on its recipe, in a few words. A recipe
-- you own (bags or bank) never reads "buy ... first" ("I bought it, and Flow
-- tells me to buy the recipe", 0.35.205).
function SP.RecipeWait(inBags, inBank, fromQuest, name, prof, learn, rank)
    local tooLow = learn and rank and rank < learn
    if inBags then
        return tooLow and string.format("you have the recipe: learn it at %s %d", prof, learn) or "use the recipe in your bags first"
    end
    if inBank then
        return tooLow and string.format("the recipe is in your bank: learn it at %s %d", prof, learn) or ("take " .. name .. " out of your bank first")
    end
    if fromQuest then return "get the plans from the quest first" end
    return "buy " .. name .. " first"
end

-- "Buy Recipe: X" for a bought recipe you don't have (as far as Flow knows).
-- rank: your skill in the profession (nil: not looked at). banked: how many
-- are in your bank (nil: Flow looks).
local function recipeStop(prof, s, known, rank, banked)
    if not s.recipeItem or (known and known[s.recipe]) then return nil end
    local name = itemName(s.recipeItem)
    local learn = SP.LearnSkill(prof, s)   -- (nil: unknown, so nothing holds the step back)
    watched[s.recipeItem] = true
    if count(s.recipeItem) > 0 then
        -- In your bags but your skill is too low to learn it: nothing to do yet.
        if not SP.RecipeDue(learn, rank, 0) then return nil end
        return { key = "use:" .. s.recipeItem, kind = "craft", points = { playerPoint() }, anywhere = true,
                 icon = BAG_ICON, useItem = s.recipeItem,   -- in your bags: the arrow shows a bag
                 text = "Learn " .. s.recipe .. ": use the recipe in your bags" }
    end
    -- In your bank: you own it. ("I bought the recipe, Flow told me to put it
    -- in the bank, and now Flow tells me to stop and buy it", 0.35.203.)
    -- Nothing until you can learn it, then a step at the bank to fetch it.
    banked = banked or SP.BankCount(s.recipeItem)
    if banked > 0 then
        if not SP.RecipeDue(learn, rank, 0) then return nil end
        local pts, names = SP.BankerPoints()
        return { key = "bankget:" .. s.recipeItem, kind = "merchant", points = pts, npcs = names, fetch = { [s.recipeItem] = 1 },
                 text = "Bank: take out " .. name,
                 details = { learn and ("It's in your bank and your skill is high enough to learn " .. s.recipe .. " now.")
                                 or ("It's in your bank. " .. s.recipe .. ": learn skill unknown: the recipe's tooltip says.") },
                 blockedBy = #pts == 0 and "Flow doesn't know where a bank is" or nil }
    end
    if s.quest then return questRecipeStop(s) end
    if not SP.RecipeDue(learn, rank) then return nil end   -- (too early to buy: it waits until you're nearly there)
    local fish = false
    for mid in pairs(s.mats or {}) do
        local ms = src(mid)
        if ms and ms.fished then fish = true end
    end
    local pts, _, sellers = vendorPoints(s.recipeItem)
    return { key = "buy:" .. s.recipeItem, kind = "merchant", points = pts, npcs = sellers,
             cost = SP.Price(s.recipeItem),
             text = "Buy " .. name,
             details = { fish and ("So you can cook what you catch (skip it if you already know " .. s.recipe .. ").")
                             or ("Flow's plan makes " .. s.recipe .. " here. A vendor sells it; the trainer doesn't teach it."),
                         (not learn) and (s.recipe .. ": learn skill unknown: the recipe's tooltip says.") or nil },
             blockedBy = #pts == 0 and ("Flow doesn't know who sells " .. name) or nil }
end

-- Who teaches a trained step: its own trainer for your side (`trainer =
-- { Horde = .., Alliance = .. }`) or the profession's. A step marked with an
-- empty `trainer = {}` has a trainer of its own that Flow can't name.
--   -> names, label ("<name>" / "First Aid trainer")
SP.OWN_TRAINER_UNKNOWN = "a trainer of its own, unknown to Flow"
function SP.StepTrainers(prof, s)
    local t = s and s.trainer
    if not t then return ns.places:TrainersFor(prof), prof .. " trainer" end
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    if mine and t[mine] then return { t[mine] }, t[mine] end
    local both = {}
    for _, n in pairs(t) do both[#both + 1] = n end
    if #both == 0 then return both, SP.OWN_TRAINER_UNKNOWN end
    table.sort(both)
    return both, table.concat(both, " / ")
end
SP._recipeStop = recipeStop  -- for /flow test

-- The recipe to learn next, when the climb stops short of the target. The
-- climb (simulate) only orders recipes whose colour your profession window
-- showed, so a recipe you haven't learned is never in it and its learn or
-- buy step never came up. Chosen from the unlearned steps whose learn skill
-- Flow has read (a trainer's window or the recipe's tooltip) and your skill
-- meets (a bought recipe: from SP.BUY_AHEAD below it): of the trained ones
-- and of the bought ones, the one learned latest, as an older one is
-- likelier grey already. That last part is Flow's own reasoning, not a game value; how much skill the recipe gives is unknown
-- until the window shows it. A learn skill Flow hasn't read: not suggested.
--   known: recipes:Known(prof) (nil: window never seen, nothing suggested)
--   learnOf(step) -> skill or nil
--   -> { step, ... } (ties: every step learned at that skill)
function SP.LearnNext(steps, known, rank, learnOf)
    if type(known) ~= "table" or type(rank) ~= "number" or type(learnOf) ~= "function" then return {} end
    -- (Trained and bought are picked apart: a bought recipe is due ahead of
    -- its skill and must not hide a trained one you can learn today.)
    local best, picks = {}, { trained = {}, bought = {} }
    for _, s in ipairs(steps or {}) do
        if s.recipe and not known[s.recipe] and forYou(s) then
            local learn = learnOf(s)
            local kind = s.recipeItem and "bought" or "trained"
            if type(learn) == "number" and rank >= learn - (s.recipeItem and SP.BUY_AHEAD or 0) then
                if not best[kind] or learn > best[kind] then
                    best[kind], picks[kind] = learn, { s }
                elseif learn == best[kind] then
                    table.insert(picks[kind], s)
                end
            end
        end
    end
    local out = {}
    for _, s in ipairs(picks.trained) do out[#out + 1] = s end
    for _, s in ipairs(picks.bought) do out[#out + 1] = s end
    return out
end
SP.LEARN_GAIN_UNKNOWN = "Flow's plan from the recipes you know stops short. How much skill this one gives is unknown until your profession window shows it."

-------------------------------------------------------------------------------
-- Gear you can make: recipes you know whose item would be an upgrade for
-- you (the same verdict as your bags: at least +0.5 score for your levelling
-- role, and wearable at your level). Shown beside the skill plan, never
-- instead of it: the fastest way up stays the route either way.
-------------------------------------------------------------------------------

-- Pure: the veins to mine for skill (profGuide nodes = { { item } }): the
-- ones with a known spot on the map you're on. Flow doesn't list the skill a
-- vein asks, so it can't pick the best one for you: the vein's tooltip says.
--   pointsOf(item) -> points, onMap, node name.  -> points, names
function SP.VeinsHere(nodes, pointsOf)
    local pts, names = {}, {}
    for _, nd in ipairs(nodes or {}) do
        local p, onMap, name = pointsOf(nd.item)
        if onMap and p and #p > 0 then
            for _, pt in ipairs(p) do pts[#pts + 1] = pt end
            names[#names + 1] = name
        end
    end
    return pts, names
end

-- Blacksmithing gear is made at an anvil. (Recipes Flow read from your
-- profession window don't say where; the steps in Guides.lua do.)
local PROF_STATION = { Blacksmithing = "anvil" }

-- What the planner chooses from: the profession's steps (Guides.lua), and
-- each recipe your profession window showed that they don't have, as a step
-- of its own: its materials and the colour it had at the skill Flow saw.
-- (One with materials the game hadn't loaded isn't one: Recipes.lua.)
-- known: recipes:Known(prof).
function SP.Candidates(prof, steps, known)
    local out, listed = {}, {}
    for _, s in ipairs(steps or {}) do out[#out + 1] = s; listed[s.recipe] = true end
    local names = {}
    for name, r in pairs(known or {}) do
        if not listed[name] and type(r) == "table" and r.reagents and next(r.reagents) and not r.partial then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local r = known[name]
        out[#out + 1] = { recipe = name, item = r.item, mats = r.reagents, observed = true, station = PROF_STATION[prof] }
    end
    return out
end
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
-- The game answered about an item an upgrade check asked for. Loaded: re-plan
-- with it. "No such item" (item IDs differ on Forever): it's not an upgrade.
-- Asking again would only fail again, and each answer refreshed the whole
-- route, which asked again (0.35.152).
function SP.ItemInfoArrived(id, success)
    if not (id and pendingItems[id]) then return false end
    pendingItems[id] = nil
    if success == false then gainCache[id] = false return false end
    if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("an item's info loaded (skill plan)") end
    return true
end
SP._pendingItems, SP._gainCache = pendingItems, gainCache   -- (tests)
ns:On("GET_ITEM_INFO_RECEIVED", function(id, success) SP.ItemInfoArrived(id, success) end)

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

-- Pure: the bank slot by slot, for Flow Banker's picture of it. parts: one
-- list of slots per container ({ id, count } or false), in the game's order.
-- A container with nothing in it goes after the ones that hold something
-- (0.35.270: "why are there 3 rows of empty spaces? In my bank the items
-- start from the top left": this client still reports its old main bank as
-- a container of empty slots, ahead of the tabs your things are really in).
function SP.BankLayout(parts)
    local out = {}
    for pass = 1, 2 do
        for _, part in ipairs(parts or {}) do
            local holds = false
            for _, s in ipairs(part) do if s then holds = true break end end
            if holds == (pass == 1) then
                for _, s in ipairs(part) do out[#out + 1] = s end
            end
        end
    end
    return out
end

-- The open bank's slots that hold one of these items (Flow Banker takes
-- them out): want = { [itemID] = true } -> { { bag, slot, id, count } }.
function SP.BankSlotsWith(want)
    local out = {}
    if not bankOpen then return out end
    for _, bag in ipairs(bankContainers()) do
        local okSlots, n = pcall(containerSlots, bag)
        for slot = 1, okSlots and n or 0 do
            local okI, id, c = pcall(containerItem, bag, slot)
            if okI and id and want[id] then out[#out + 1] = { bag, slot, id, c or 1 } end
        end
    end
    return out
end

-- Reads the bank while it's open. True when what's in it changed.
function SP.ReadBank()
    if not bankOpen then return false end
    local items = {}
    -- layout: every slot in the bank's own order, { itemID, count } or false
    -- for an empty one, so Flow Banker can draw the bank as it looks (0.35.215).
    local parts = {}
    for _, bag in ipairs(bankContainers()) do
        local okSlots, n = pcall(containerSlots, bag)
        local part = { bag = bag, used = 0 }
        for slot = 1, okSlots and n or 0 do
            local id, c = containerItem(bag, slot)
            if id and c then items[id] = (items[id] or 0) + c; part.used = part.used + 1 end
            part[#part + 1] = (id and c) and { id, c } or false
        end
        if #part > 0 then parts[#parts + 1] = part end
    end
    local layout = SP.BankLayout(parts)
    local summary = {}
    for _, part in ipairs(parts) do summary[#summary + 1] = { bag = part.bag, slots = #part, used = part.used } end
    local old = ns.db.bank and ns.db.bank.items or {}
    local changed = false
    for id, c in pairs(items) do if old[id] ~= c then changed = true end end
    for id in pairs(old) do if items[id] == nil then changed = true end end
    ns.db.bank = { items = items, layout = layout, seenAt = time(), parts = summary }
    return changed
end

local function rereadBank()
    local ok, changed = pcall(SP.ReadBank)
    if ok and changed and ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("bank changed") end
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

-- What's on hand for a plan, shared by its steps so nothing is counted
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

-- Buying a material at the auction house (0.35.282). "Get 57 Wool Cloth"
-- sat in the blocked list ("Flow doesn't know where Wool Cloth comes from
-- (Auction House?)"). When Flow has seen a price for it there and knows an
-- auctioneer, that's a step: at the auctioneer, with what it should cost, so
-- the route waits until you can pay (as it does for a trainer).
function SP.AuctionPoints()
    local names = {}
    for name, spot in pairs(ns.db.places or {}) do
        if ns.places.HasRole(spot, "auction") then names[#names + 1] = name end
    end
    table.sort(names)
    if #names > 0 then
        local pts = npcPoints(names)
        if #pts > 0 then return pts, names end
    end
    local a = ns.services and ns.services.Nearest and ns.services:Nearest("auction")
    if a and a.map then return { { map = a.map, x = a.x, y = a.y } }, { a.name } end
    return {}, names
end
-- Pure: what buying n at `price` each comes to (copper), or nil with no price.
function SP.AuctionCost(n, price)
    if type(price) ~= "number" or price <= 0 or type(n) ~= "number" or n <= 0 then return nil end
    return math.ceil(n * price)
end
-- Pure: the step's words.
function SP.AuctionText(n, name, cost, money)
    return string.format("Buy %d %s at the auction house (about %s)", n, name, (money or ns.Money)(cost))
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
        local cont, wx, wy = pt.cont, pt.wx, pt.wy
        if not wx and pt.map then cont, wx, wy = ns.nav:ToWorld(pt.map, pt.x, pt.y) end
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
        if r then return true end   -- (whether your skill is enough for the node is unknown to Flow: the step says so)
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
-- Remembered per material until the next route gather (which wipes it):
-- looking up every spawn and vendor of each material on every gather made
-- the skill-plan gather 8 times slower in 0.35.140.
local farmMemo = {}
function SP.FarmableHere(id)
    local v = farmMemo[id]
    if v == nil then
        v = SP.Farmable(id, hereEnv) and true or false
        farmMemo[id] = v
    end
    return v
end
function SP.ForgetFarmable() wipe(farmMemo) end

-- How sure Flow is of your bank, for the bank step: seenAt = when Flow last
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
    local rank, max, unsure = A.Skill(prof)
    local label = why(t, prof, rank or 0)
    local weight = t.optional and 1.5 or 1.0
    -- (forQuest: a quest needs this skill; the step stays with Professions off.)
    local base = { title = t.quest or prof, optional = t.optional, weight = weight,
                   forQuest = t.required and t.quest or nil }
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
    -- You have it, but the game doesn't give Flow its skill here (a third
    -- profession on WoW: Forever): nothing is planned from a number Flow
    -- would have to make up. It's listed with the reason, not routed.
    if unsure then
        add({ key = "skillplan:" .. prof, kind = "skill", points = { playerPoint() }, anywhere = true,
              text = prof .. ": Flow can't read your skill yet",
              blockedBy = "the game doesn't report your " .. prof .. " skill to add-ons here (/flow skills shows what it does report)" })
        return
    end
    if rank >= t.target then return end
    -- Past your cap: plan only up to it (skill can't go higher, so no
    -- crafting or buying for the points above it), and put the next tier on
    -- the route. Once you've trained it the plan goes on from there.
    if max and max > 0 and t.target > max then
        local planned = false
        if ns.nav:Includes("professions") then   -- (the route menu's Professions tick)
            for _, p in ipairs(ns:ProfessionPlan() or {}) do if p.name == prof then planned = true end end
        end
        local tg, tier = SP.TierGoal(prof, UnitLevel("player"), t.optional)
        -- (Planned professions get theirs from the errands, which skip a step Flow
        -- can't place: then it is listed here, blocked with the reason, not lost.)
        if tg and (not planned or not (tg.points and #tg.points > 0)) then out[#out + 1] = tg end
        local after = tier and tier.name and (tier.name .. " " .. prof) or "the next tier"
        t = setmetatable({ target = max }, { __index = t })
        label = string.format("%s%s %d -> %d, then %s", t.quest and (t.quest .. ": ") or "", prof, rank, max, after)
        if tier and not tier.ready then
            label = label .. " (" .. SP.TierNeeds(tier) .. ")"
        end
        if rank >= max then
            -- Capped and the next tier can't be learned yet: say why. (When it
            -- can, the "train:" step above is the next step.)
            if tier and not tier.ready then
                add({ key = "skillplan:cap:" .. prof, kind = "skill", points = { playerPoint() }, anywhere = true,
                      text = string.format("%s is capped at %d: %s next", prof, max, after),
                      blockedBy = SP.TierBlock(after, tier, UnitLevel("player")) })
            end
            return
        end
    end
    -- A craft with no steps in Guides.lua plans from the recipes your
    -- profession window showed; until Flow has seen it, it can't plan.
    local known = ns.recipes:Known(prof)
    if not g and known and next(known) then g = { kind = "craft", steps = {} } end
    if not g then
        add({ key = "skillplan:" .. prof, kind = "skill", points = { playerPoint() },
              text = string.format("Raise %s to %d", prof, t.target),
              blockedBy = "open the " .. prof .. " window once so Flow can plan from your recipes" })
        return
    end
    handled[prof] = true

    -- Skinning: nowhere to go. The beasts you kill on your way are the skill-up,
    -- so the step is "along the way" (Nav.lua: listed, never a detour); only
    -- the knife, when you have none, is a stop of its own.
    if g.skin then
        local tool, missing = SP:ToolGoal(prof)
        if tool then add(tool) end
        local top = SP.SkinMaxLevel(rank)
        add({ key = "skill:" .. prof, kind = "skill", prof = prof, points = { playerPoint() }, anywhere = true,
              along = true,
              text = string.format("Skin beasts up to level %d: %s %d -> %d", top, prof, rank, t.target),
              details = { "Skinning has no spots to go to: skin the beasts you kill on your way.",
                  string.format("At %d you can skin beasts up to level %d; level %d needs %d.",
                      rank, top, top + 1, SP.SkinSkill(top + 1)),
                  g.tip },
              blockedBy = missing and ("needs a " .. missing) or nil })
        return
    end

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
        -- What to pick here, by name ("Pick Earthroot, Silverleaf or Peacebloom").
        local okP, picks = pcall(function() return SP.PickNames(SP.NodesHere(prof), rank, ns.nearby and ns.nearby.SkillUp) end)
        local what = okP and SP.NameList(picks) or nil
        -- (An area, as a kill step is: the world map draws where its spots are,
        -- and inside it the arrow goes from spot to spot. 0.35.279: "I really
        -- wish it would show me where I needed to go to get these herbs".)
        add({ key = "skill:" .. prof, kind = "skill", prof = prof, points = points, area = (#points > 1) or nil,
              text = (what and ("Pick " .. what .. ": ") or "") .. string.format("%s %d -> %d", prof == "Fishing" and "Fish" or prof, rank, t.target)
                  .. (t.zone and string.format(t.ahead and (" (%s in " .. t.ahead .. " needs %d)") or " (%s here needs %d)", t.zone, t.target) or ""),
              details = (t.zone and { string.format(t.ahead and ("%s grows in " .. t.ahead .. ", where your route goes next, and needs %s %d. Gather what you can here before you leave.")
                        or "%s grows in this zone and needs %s %d. Gather what you can here until you're there.", t.zone, prof, t.target),
                    what and ("Here that's " .. what .. ": the arrow leads to the nearest spot, then the next. The green clouds on your minimap are these.") or "Nothing you can pick grows on this map.",
                    "The spots are where it can grow, not what's up now: Flow isn't told that. Stand at an empty one a few seconds and the arrow goes on to the next; the game's Find Herbs dots are the ones that are up." })
                  or (g.tip and { g.tip }) or nil,
              blockedBy = (missing and ("needs a " .. missing))
                  or (#points == 0 and ("no known " .. prof .. " spot on this map")) or nil })
        return
    end

    -- Tool in your bags?
    local toolGoal, toolMissing = SP:ToolGoal(prof)
    if toolGoal then add(toolGoal) end

    -- Mining also levels from the veins themselves.
    local steps = g.steps or {}
    -- Optional skill-ups use what you carry first; the rest go by price
    -- (SP.Score; by materials while something has no price).
    local crafts, order, reaches, spans, reached = simulate(prof, SP.Candidates(prof, steps, known), rank, t.target, nil,
        { prefer = t.optional and "use-bags" or "cheap" })
    -- Each step's share of the climb, and what the plan makes after it.
    local function stepTo(s) return spans[s] and spans[s][2] or t.target end
    local function after(s)
        for i, o in ipairs(order) do if o == s then return order[i + 1] end end
    end

    -- One stock for the whole plan: bags, then bank, then smelting. What it
    -- takes from the bank becomes a bank step, what it smelts a smelt step;
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
        -- (The skill smelting asks: only what a Mining trainer's window showed.)
        local need = sm.spell and SP.LearnSkill("Mining", { recipe = sm.spell })
        if need and mining < need then return string.format("needs Mining %d to smelt", need) end
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
    -- (The climb orders only recipes the window showed, so when it stops short
    -- the recipe to learn next comes from SP.LearnNext.)
    local toLearn, stopsShort = {}, {}
    for _, s in ipairs(order) do toLearn[#toLearn + 1] = s end
    if not reaches then
        for _, s in ipairs(SP.LearnNext(steps, known, rank, function(st) return SP.LearnSkill(prof, st) end)) do
            toLearn[#toLearn + 1] = s
            stopsShort[s] = true
        end
    end
    for _, s in ipairs(toLearn) do
        if s.recipeItem then
            -- Bought, not trained (Recipe: Brilliant Smallfish).
            local r = recipeStop(prof, s, known, rank)
            if r then
                if stopsShort[s] then r.details = r.details or {}; r.details[#r.details + 1] = SP.LEARN_GAIN_UNKNOWN end
                add(r)
            end
        elseif known and not known[s.recipe] and SP.TrainNow(SP.LearnSkill(prof, s), rank) then
            local names, who = SP.StepTrainers(prof, s)
            local pts = npcPoints(names)
            add({ key = "learn:" .. prof .. ":" .. s.recipe, kind = "proftrainer", points = pts, npcs = names,
                  text = string.format("Learn %s (%s)", s.recipe, who),
                  details = (not SP.LearnSkill(prof, s)) and { s.recipe .. ": " .. SP.LEARN_UNKNOWN .. "." }
                      or (stopsShort[s] and { SP.LEARN_GAIN_UNKNOWN }) or nil,
                  blockedBy = #pts == 0 and (s.trainer and (#names == 0 and "who teaches it is unknown to Flow" or ("Flow doesn't know where " .. who .. " stands")) or ("no known " .. who)) or nil })
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
        -- A recipe you don't have yet (its learn/buy stop is above) gets no
        -- mats stops: the recipe comes first, then the plan re-forms and
        -- tells you what to gather for it.
        local unlearned = known and not known[s.recipe]
        if planned > n and not unlearned then
            local shorts = {}
            for _, id in ipairs(ids) do
                shorts[id] = stock:Take(id, (planned - n) * s.mats[id]).short
            end
            -- Things a vendor sells are bought when the craft is otherwise
            -- ready, not carried for levels ("you had me buy apples and carry
            -- them while levelling for a future profession item: we could buy
            -- those right when we need them", 0.35.234).
            local function fromVendor(id)
                local sr = src(id)
                return (sr and sr.vendor) and true or false
            end
            local buyNow = SP.BuyNow(not (known and not known[s.recipe]), shorts, fromVendor)
            for _, id in ipairs(ids) do
                local short = shorts[id]
                if short > 0 and not (fromVendor(id) and not buyNow) then
                    local sm = smeltOf(id)
                    if sm then raw[sm.from] = (raw[sm.from] or 0) + short * sm.n
                    else raw[id] = (raw[id] or 0) + short end
                elseif short > 0 then
                    SP.buyLater = SP.buyLater or {}
                    SP.buyLater[id] = (SP.buyLater[id] or 0) + short
                end
            end
        end
        -- Nothing to make it from yet: no step, but the profession window
        -- still names it and what to gather (CraftHint.lua).
        if n == 0 and planned > 0 then
            SP.lastWaiting = SP.lastWaiting or {}
            local list = SP.lastWaiting[prof] or {}
            SP.lastWaiting[prof] = list
            local nx = after(s)
            list[#list + 1] = { prof = prof, recipe = s.recipe, makeCount = planned, planned = planned,
                                rank = rank, target = t.target, stepTo = stepTo(s), nextRecipe = nx and nx.recipe,
                                reagents = s.mats,
                                unlearned = (known and not known[s.recipe]) or nil }
        end
        if n > 0 then
            local deps, depBlocked = before(takes)
            local pts, anywhere = stationPoints(s.station), false
            if not pts or #pts == 0 then pts, anywhere = { playerPoint() }, true end
            if s.tool then watched[s.tool] = true end
            local blocked = toolMissing and ("needs a " .. toolMissing)
                or (s.tool and not haveStepTool(s.tool) and ("needs a " .. itemName(s.tool) .. " (make it first)"))
                or (known and not known[s.recipe] and ((s.recipeItem and SP.RecipeWait(count(s.recipeItem) > 0, SP.BankCount(s.recipeItem) > 0,
                        s.quest ~= nil, itemName(s.recipeItem), prof, SP.LearnSkill(prof, s), rank))
                    or ("learn " .. s.recipe .. " first")))
            blocked = blocked or depBlocked
            -- The count is the point: exactly what reaches your target, so
            -- it's highlighted, and the details say why that many.
            local num = "|cffffd100" .. n .. "|r"
            local c = chance(prof, s, rank)
            local from = spans[s] and spans[s][1] or rank
            local nx = after(s)
            local details = {
                string.format("%d takes %s %d -> %d: %s.", planned, prof, from, stepTo(s),
                    c >= 1 and "each one gives a skill point while it's orange"
                    or "it isn't orange, so only some give a point (Flow counted on that)"),
                nx and string.format("Then %s: past %d it gives more skill for what it takes.", nx.recipe, stepTo(s))
                    or "More than that won't raise the skill further for now, so it'd be wasted materials.",
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
                  stepTo = stepTo(s), nextRecipe = nx and nx.recipe,
                  text = s.recipe:find("^Smelt ") and string.format("%s x%s at a forge", s.recipe, num)
                      or string.format("Make %s x %s", num, s.recipe),
                  details = details,
                  blockedBy = blocked or nil })
        end
    end

    -- Gear you can make that's an upgrade for you. When the plan already
    -- makes it, its craft step says so. Otherwise, with everything it needs
    -- on hand (bags, bank, smelting), it's an extra, optional step: the route
    -- takes it only when it's on the way and it never changes what the plan
    -- makes. Missing materials: not a step at all, only listed in the
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
                -- Only a step you can actually make sets its materials aside.
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

    -- Smelt steps: bars from the ore you have (bags or bank), at a forge,
    -- before the crafts that use them.
    for _, id in ipairs(sortedIds(smeltWant)) do
        local sm, n = smeltOf(id), smeltWant[id]
        local pts = stationPoints("forge") or {}
        local bar = itemName(id)
        add({ key = "smelt:" .. prof .. ":" .. id, kind = "craft", points = pts, extra = "smelt",
              -- (weight 1: a far forge counts as far; at 0.5 the route would
              -- cross the zone to smelt before the steps on the way)
              optional = not smeltNeeded[id] or nil, weight = smeltNeeded[id] and 1 or 1.5,
              deps = smeltBankOre[id] and { "bank:" .. prof } or nil,
              icon = profIcon("Mining"), station = "forge",
              -- Done in the Mining (smelting) window: the hint shows it there.
              prof = "Mining", serves = prof, recipe = "Smelt " .. bar:gsub(" Bar$", ""),
              makeCount = n, planned = n, reagents = { [sm.from] = sm.n },
              text = string.format("Smelt |cffffd100%d|r %s at a forge", n, bar),
              details = { string.format("%d %s for your %s crafts, from %d %s%s.", n, bar, prof, n * sm.n,
                              itemName(sm.from), smeltBankOre[id] and " (some from your bank)" or ""),
                          "Flow sends you to the forge quickest to reach (flights counted): one you've used, or the one by a blacksmith." },
              blockedBy = smeltBlocked(id) })
    end

    -- Bank step: what the plan takes out of your bank, first.
    local fromBank, fetch = {}, {}
    for _, id in ipairs(sortedIds(bankPull)) do
        local n = math.min(bankPull[id], SP.BankCount(id))
        if n > 0 then
            fromBank[#fromBank + 1] = string.format("%d %s", n, itemName(id))
            fetch[id] = n   -- (Flow Banker's Take out reads this: Banker.lua, 0.35.353)
        end
    end
    if #fromBank > 0 then
        local seen = ns.db.bank and ns.db.bank.seenAt
        add({ key = "bank:" .. prof, kind = "merchant", points = bankPts, npcs = bankNames,   -- (a town errand, not an item drop: near first and the buff steps read "collect" as killing)
              optional = not bankNeeded or nil, weight = bankNeeded and 0.5 or 1.5, fetch = fetch,
              text = "Get from your bank: " .. table.concat(fromBank, ", "),
              details = { string.format("For your %s crafts. Take them out at the banker.", prof),
                          SP.BankNote(seen) },
              blockedBy = bankBlocked })
    end

    -- Still short: group by where it comes from: one step per node type / mob group.
    local nodes = {}
    for id, n in pairs(raw) do
        watched[id] = true
        local s = src(id)
        local name = itemName(id)
        if s and s.gather then
            local key = s.node or s.gather
            local nd = nodes[key] or { src = s, items = {} }
            nodes[key] = nd
            nd.items[#nd.items + 1] = string.format("%d %s", n, name)
        elseif s and s.fished then
            -- Comes from your Fishing step; nothing to farm for it.
            watched[id] = true
        elseif s and (s.drops or s.looted) then
            -- Fish you'll catch levelling Fishing anyway cook just as well:
            -- they come off the meat to farm (and the recipe goes on the route).
            local fishStep, fishSrc, fishId = SP.FishAlternative(steps, id, prof, rank)
            local fromFish = 0
            if fishStep then
                fromFish = math.min(n, math.floor(SP.PlannedCatch(SP.lastTargets) * (fishSrc.share or 0.7)))
                if fromFish > 0 then
                    watched[fishId] = true
                    local r = recipeStop(prof, fishStep, known, rank)
                    if r then add(r) end
                end
            end
            n = n - fromFish
            SP.lastFromFish = fromFish  -- (for /flow prof plan and tests)
            if n > 0 then
            -- Other materials that level the same (wolf meat or boar meat): any of them will
            -- do, so their mobs count too.
            local ids = SP.Alternatives(steps, id, prof, rank)
            -- The mobs: any listed for the material, and the ones you've
            -- looted it from yourself (none seen: unknown to Flow).
            local names, mobs, rates, haveMob = {}, {}, {}, {}
            for _, aid in ipairs(ids) do
                local as = src(aid)
                names[#names + 1] = itemName(aid)
                SP.FarmMobs(as.drops, SP.SeenMobs(aid), mobs, haveMob)
                rates[#rates + 1] = SP.DropRate(aid) or false
            end
            local kills = SP.KillsFor(n, rates)
            local pts = npcPoints(mobs)
            local details = SP.FarmDetails(kills, n, mobs)
            if t.optional then
                table.insert(details, 1, prof .. " isn't needed for a quest: loot these as you quest. No need to stop just for this.")
            end
            if fromFish > 0 then
                details[#details + 1] = string.format("%d fewer than without fishing: about %d %s from your Fishing step cook just as well.",
                    fromFish, fromFish, itemName(fishId))
            end
            local have = 0
            for _, aid in ipairs(ids) do watched[aid] = true; have = have + count(aid) end
            add({ key = "farm:" .. id, kind = "kill", points = pts, npcs = mobs, area = true,
                  -- Optional (no quest needs it): never a step of its own; loot the
                  -- mobs your quests and travel bring you to (Nav.lua: alongGoals).
                  along = t.optional or nil,
                  -- Which profession, what it drops and how many: the mobs get the
                  -- profession's icon over their nameplates, and a line in their
                  -- tooltip (QuestMarks.lua, 0.35.319).
                  prof = prof, loot = table.concat(names, " or "), have = have, need = have + n,
                  -- Progress like a quest objective: what you carry / what the plan uses.
                  text = SP.FarmText(table.concat(names, " or "), ns.Progress(have, have + n), kills),
                  details = details,
                  blockedBy = (#mobs == 0 and ("what drops " .. name .. " is unknown to Flow"))
                      or (#pts == 0 and ("no known " .. name .. " drops nearby")) or nil })
            end
        elseif s and s.vendor then
            local pts, _, sellers = vendorPoints(id)
            add({ key = "buy:" .. id, kind = "merchant", points = pts, npcs = sellers,
                  cost = SP.Price(id) and SP.Price(id) * n or nil,
                  text = string.format("Buy %d %s", n, name),
                  blockedBy = #pts == 0 and ("Flow doesn't know who sells " .. name) or nil })
        elseif s and s.made then
            -- You make it yourself (Heavy Grinding Stone for Green Iron Leggings).
            add({ key = "need:" .. id, kind = "collect", points = { playerPoint() },
                  text = string.format("Make %d %s (%s)", n, name, s.made),
                  blockedBy = string.format("make %d %s first (%s)", n, name, s.made) })
        else
            -- Nothing drops or sells it in Flow's data: the auction house, on a price Flow has seen there.
            local price = ns.auction and ns.auction.Price and ns.auction:Price(id)
            local cost = SP.AuctionCost(n, price)
            local okA, ahPts = pcall(SP.AuctionPoints)
            if cost and okA and #ahPts > 0 then
                local money = ns.auction.Money
                add({ key = "need:" .. id, kind = "buy", points = ahPts, cost = cost,
                      text = SP.AuctionText(n, name, cost, money),
                      details = { string.format("Nothing Flow knows of drops or sells %s. At the auction house it was about %s each when Flow last looked.",
                                      name, (money or ns.Money)(math.floor(price))),
                                  "The price there changes: look before you buy. The route waits until you have the money." } })
            else
                add({ key = "need:" .. id, kind = "collect", points = { playerPoint() },
                      text = string.format("Get %d %s", n, name),
                      blockedBy = cost and ("Flow doesn't know where " .. name .. " comes from, and knows no auctioneer yet: talk to one once")
                          or ("Flow doesn't know where " .. name .. " comes from, and has seen no price for it at an auction house") })
            end
        end
    end
    for node, nd in pairs(nodes) do
        local s = nd.src
        local gr = A.Skill(s.gather)
        local pts, onMap = objectPoints(s.objects)
        local blocked
        if not gr then blocked = "needs " .. s.gather .. " (or buy them)"
        elseif #pts == 0 then blocked = "no known " .. node .. " in Flow's data"
        end
        if s.gather == "Mining" and not hasTool("Mining", 2901) and not blocked then blocked = "needs a Mining Pick" end
        handled[s.gather] = true
        add({ key = "gather:" .. node, kind = "gather", prof = s.gather, points = pts,
              text = SP.GatherText(s.gather, node, nd.items),
              details = { onMap and "Nearest ones on this map; the route picks the ones on your way."
                              or "None on this map: these are elsewhere.",
                          SP.GATHER_UNKNOWN },
              blockedBy = blocked })
    end

    -- Gathering profession with nodes (Mining): the veins themselves skill up.
    -- Which vein your skill can mine, and how many it takes, are unknown (Flow
    -- lists no vein skills, and the game doesn't say when a vein stops giving
    -- skill): the veins on this map, no count, and the step says so.
    -- (Not when the plan already sends you to a vein for its ore, above.)
    local mining = false
    for _, nd in pairs(nodes) do if nd.src.gather == prof then mining = true end end
    if g.nodes and not mining then
        local pts, names = SP.VeinsHere(g.nodes, function(item)
            local s = src(item)
            if not s then return nil end
            local p, onMap = objectPoints(s.objects)
            return p, onMap, s.node
        end)
        local details = {}
        if #names > 0 then details[#details + 1] = "On this map: " .. table.concat(names, ", ") .. "." end
        details[#details + 1] = "Which of them your skill can mine is unknown to Flow: a vein's tooltip says what it asks."
        details[#details + 1] = string.format("How many it takes to reach %d is unknown too.", t.target)
        details[#details + 1] = "Smelting the ore at a forge raises Mining too."
        add({ key = "gather:veins:" .. prof, kind = "gather", prof = prof, points = pts,
              text = "Mine veins for skill", details = details,
              blockedBy = (not hasTool("Mining", 2901) and "needs a Mining Pick")
                  or (#pts == 0 and "no known veins on this map in Flow's data") or nil })
    end

    if not reaches then
        -- Past what Flow can work out: a window recipe's colour is known only
        -- at the skill Flow saw it, so after those crafts it needs a fresh look.
        local past = math.floor(reached + 1e-9)
        local seenOnly = false
        for _, s in ipairs(order) do if s.observed then seenOnly = true end end
        add({ key = "skillplan:more:" .. prof, kind = "skill", points = { playerPoint() },
              text = string.format("%s past %d: open the %s window so Flow reads your recipes", prof, past, prof),
              blockedBy = seenOnly and string.format("Flow knows your recipes' colours only at %s %d: open the window again after these crafts", prof, rank)
                  or string.format("no recipe Flow knows gives %s skill past %d (learn one at the trainer)", prof, past) })
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
        SP.lastWaiting = {}
        SP.buyLater = {}      -- (vendor materials left for when their craft is ready: SP.BuyNow)
        SP.ForgetFarmable()   -- (you may have moved zone since the last gather)
        -- (Each profession's time is listed under "gather: skillplan" in
        -- /flow perf, so a slow gather says which profession costs.)
        local clock, addPart = debugprofilestop, ns.perf and ns.perf.AddPart
        for prof, t in pairs(SP.lastTargets) do
            local t0 = clock and addPart and clock()
            local ok, err = pcall(planProfession, prof, t, out)
            if not ok then ns:Log("skillplan", prof .. ": " .. tostring(err)) end
            if t0 then addPart("gather: skillplan", prof, clock() - t0) end
        end
        -- Drop steps with no place at all, unless blocked (those are listed, not routed).
        local kept, seen = {}, {}
        for _, g in ipairs(out) do
            g.points = g.points or {}
            if seen[g.key] then
                -- Two professions want the same step (e.g. Copper Veins): one step, both reasons.
                for _, d in ipairs(g.details or {}) do table.insert(seen[g.key].details, d) end
            elseif #g.points > 0 or g.blockedBy then
                kept[#kept + 1] = g; seen[g.key] = g
            end
        end
        SP.lastStops = kept
        -- The profession window's panel shows this plan: bring it up to date
        -- (the upgrade you just made is in your bags, so it's off the plan).
        if ns.craftHint and ns.craftHint.PlanChanged then ns.craftHint.PlanChanged() end
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
    if changed and ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("bag count of a planned item") end
    -- Moving things in or out of the bank: read it again.
    if bankOpen then rereadBank() end
end)
ns:On("SKILL_LINES_CHANGED", function() if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("SKILL_LINES_CHANGED") end end)

-- /flow prof plan: what the planner thinks, profession by profession.
function SP:Explain()
    local any = false
    for prof, t in pairs(SP:Targets()) do
        any = true
        local rank, max = A.Skill(prof)
        local to = (max and max > 0) and math.min(t.target, max) or t.target
        ns:Print(string.format("%s %s -> %d%s%s", prof, tostring(rank), to, to < t.target and (" (cap; wants " .. t.target .. ")") or "",
            t.quest and (" (" .. t.quest .. ")") or ""))
        local g = ns:Get("profGuide", prof)
        local known = ns.recipes:Known(prof)
        if rank and ((g and g.steps) or known) then
            local crafts, order = simulate(prof, SP.Candidates(prof, g and g.steps, known), rank, to, nil,
                { prefer = t.optional and "use-bags" or "cheap" })
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
        print(string.format("  step: %s%s", g.text or g.key, g.blockedBy and ("  [blocked: " .. g.blockedBy .. "]") or ""))
    end
end

SP._simulate = simulate  -- for /flow test
SP._planProfession = planProfession  -- (tests)
