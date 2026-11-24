local _, ns = ...

-- Profession plan (lead section 382, P-COACH C1): the ordered steps toward
-- the next skill point of one profession, read from what this character
-- already saved. A planner only (section 379): no ladder table, nothing is
-- crafted, bought, posted, withdrawn or trained; every step is a line of
-- text, with a place only where one was seen (target nil: never guessed).
--
--   steps, why = ProfPlan.Plan(input)        pure
--   list       = ProfPlan.Candidates(input)  pure
--   api        = ProfPlan.Declare(k)
--     api.plan(profession) -> steps, why, say, read from the client and store
--   ns.use(ProfPlan.NAME) -> { Plan = api.plan }
--
-- input = {
--   prof, skill, max     the profession and its reading (whole numbers)
--   book                 char "learned.facts.recipeBook"
--   colours              char "learned.recipeColors": [name][difficulty] = { lo, hi }
--   bags, bank           { [itemKey] = count }
--   price(item)          copper for one, or nil when not known
--   name(item)           the item's name, or nil
--   trainerLists         char "learned.trainerLists"
--   npcs                 account "learned.places.npcs"
--   station              the station kind the craft needs ("anvil"), or nil
--   stationTarget        { map, x, y } of one seen, or nil
--   atStation            true when standing at one
-- }
-- step = { kind, text, item, count, target, recipe, npc, station }; make_part adds from = { item,
-- count } (the ore); craft adds mats (one line per material), and for a
-- sure craft reach, after and thenText (section 388 a);
-- kind one of learn_recipe, train_tier, make_part, take_bank, go_station, craft, in
-- that order; or the one gather_skill step of a gathering profession with
-- no craft to make (P.GATHER; adds gather = the profession and, with a
-- node seen, node and target). why (with no steps): "no reading", "no recipe" (nothing gives
-- a point and nothing can be learned at this skill), "no colours" (the
-- window's colours were never read) or "no materials"; say is then the one
-- thing a new player does next, in plain words (section 383).
--
-- Only orange (sure) and yellow (maybe) give a point. Sure comes first,
-- then the cheapest by known prices (unpriced last), then by name.
-- Materials come from the bags, then the bank, then a known Mining smelt
-- of ore in the bags. When none of the candidates can be made from those
-- and the input carries source reads (nodes or vendorPrice, C3), the first
-- candidate's short materials get a gather, buy_vendor or buy_auction step
-- (Items/ProfSources.lua), ahead of the rest; without source reads a
-- recipe short of materials gives no step.
--   here, nodes, vendorPrice   as ProfSources.For takes them (C3)

ns.ProfPlan = {}
local P = ns.ProfPlan

P.NAME = "profPlan"
P.NODE_SOURCE = "gatherMateSource"
-- Section 383: a material whose name is not read yet; never its number.
P.UNNAMED = "of the materials"
-- Section 383: the one thing to do when the plan is empty, by reason.
P.SAY = {
    ["no reading"] = "Open your %s window once",
    ["no colours"] = "Open your %s window once",
    ["no materials"] = "Get the materials for %s",
    ["no recipe"] = "Visit a %s trainer for new recipes",
    ["at the top"] = "%s is done: the top rank is reached",
}
-- Section 400 item 2: the last rank's end in Classic. No rank past it to train.
P.TOP = 300
-- Section 400 item 2: no recipe of this profession in the book read and no
-- trainer list seen: the cheapest next step is a first recipe at a trainer.
P.LEARN_ANY = "Learn a %s recipe at %s (%s)"
P.SAY_NO_PROF = "Open a profession window once"
-- Queue item A2: the gathering professions. Their points come from
-- gathering, not from a recipe, so with no craft to make the plan is one
-- gather_skill step: a line of text, with the nearest node seen on this
-- map as its place when the profession has a node kind (never guessed).
-- kind is the node kind Nav/AddonSources.lua gives. First guesses, not
-- seen in game: the lines, and that any node gives a point.
P.GATHER = {
    Mining = { kind = "Mining", text = "Mine any ore vein you find", tool = "Mining Pick" },
    Herbalism = { kind = "Herb Gathering", text = "Pick any herb you find" },
    Fishing = { kind = "Fishing", text = "Fish in any water, with a fishing pole on", tool = "Fishing Pole" },
    Skinning = { text = "Skin the beasts you kill, with a skinning knife in your bags", tool = "Skinning Knife" },
}
-- Section 402 item 4 (G19): the gathering tool, bought from a vendor at a
-- price this account saw. Never the auction house; nothing is bought.
P.BUY_TOOL = "Buy a %s from a vendor (%s)"
P.GATHER_NEAR = "%s; the nearest seen is %s"
-- A gathering profession with no skill read: it has no window to open.
P.SAY_GATHER = "Learn %s from a trainer, then gather once"
-- "no recipe" with a trainer of this profession seen.
P.SAY_TRAINER = "Visit %s for new %s recipes"
P.SMELT_PROF = "Mining"
P.SMELT_STATION = "forge"
P.CHANCE = { optimal = "sure", medium = "maybe" }

local function whole(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge and n == math.floor(n)
end

-- t[k] when t is a table, else nil.
local function get(t, k)
    if type(t) ~= "table" then return nil end
    return t[k]
end

-- f(...) when f is a function, else nil.
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    return f(...)
end

local function count(t, item)
    local n = get(t, item)
    if whole(n) then return n end
    return 0
end

local function article(word)
    if word:match("^[AEIOUaeiou]") then return "an " .. word end
    return "a " .. word
end

local function itemName(input, item)
    local n = call(input.name, item)
    if type(n) == "string" and n ~= "" then return n end
    return P.UNNAMED
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- The span of a colour that holds this skill: chance, span. Sure wins over
-- maybe when a recipe was saved with both.
local function colourAt(spans, skill)
    if type(spans) ~= "table" then return nil end
    for _, d in ipairs({ "optimal", "medium" }) do
        local s = spans[d]
        if type(s) == "table" and type(s.lo) == "number" and type(s.hi) == "number"
            and skill >= s.lo and skill <= s.hi then
            return P.CHANCE[d], s
        end
    end
    return nil
end

local function cost(input, mats)
    local total = 0
    for item, per in pairs(mats) do
        local p = call(input.price, item)
        if type(p) ~= "number" then return nil end
        total = total + p * per
    end
    return total
end

local function gathers(input)
    if type(input) ~= "table" or type(input.prof) ~= "string" then return nil end
    return P.GATHER[input.prof]
end

-- A gathering profession needs no recipe book: its plan can be the gather
-- step alone.
local function usable(input)
    return type(input) == "table" and type(input.prof) == "string"
        and whole(input.skill) and whole(input.max) and input.max > 0
        and (type(input.book) == "table" or gathers(input) ~= nil)
end

function P.Candidates(input)
    local out = {}
    if not usable(input) then return out end
    local colours = type(input.colours) == "table" and input.colours or {}
    for name, r in pairs(type(input.book) == "table" and input.book or {}) do
        if type(r) == "table" and r.profession == input.prof and r.partial ~= true
            and type(r.mats) == "table" and next(r.mats) ~= nil then
            local chance, span = colourAt(colours[name], input.skill)
            if chance then
                out[#out + 1] = { recipe = name, entry = r, chance = chance, span = span,
                    cost = cost(input, r.mats) }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.chance ~= b.chance then return a.chance == "sure" end
        if (a.cost == nil) ~= (b.cost == nil) then return a.cost ~= nil end
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.recipe < b.recipe
    end)
    return out
end

-- A known smelt that makes this item: name, entry (one ore item only).
local function smeltFor(input, item)
    for name, r in pairs(type(input.book) == "table" and input.book or {}) do
        if type(r) == "table" and r.profession == P.SMELT_PROF and r.makes == item and r.partial ~= true
            and type(r.mats) == "table" then
            local ore, per, n = nil, nil, 0
            for k, v in pairs(r.mats) do ore, per, n = k, v, n + 1 end
            if n == 1 and whole(per) and per > 0 then return name, ore, per end
        end
    end
    return nil
end

-- How many of this item can be had: bags, bank, then smelted from ore in
-- the bags and the bank (section 400 item 3).
local function have(input, item)
    local bags, bank = count(input.bags, item), count(input.bank, item)
    local smelt, ore, per = smeltFor(input, item)
    local made = smelt and math.floor((count(input.bags, ore) + count(input.bank, ore)) / per) or 0
    return bags + bank + made, bags, bank, smelt
end

-- The most crafts for points: sure to the end of the orange span, maybe to
-- the cap; never past the cap.
local function limit(input, c)
    local left = input.max - input.skill
    if c.chance == "sure" then return math.min(left, c.span.hi - input.skill + 1) end
    return left
end

local function placeOf(input, npc)
    local n = get(input.npcs, npc)
    if type(n) == "table" and n.map ~= nil and type(n.x) == "number" and type(n.y) == "number" then return n end
    return nil
end

-- Section 400 item 4: a trainer whose place is on another continent than
-- the player's is never a step (no training trip). Both continents known,
-- or it is not away.
local function away(input, npc)
    local n, here = placeOf(input, npc), input.here
    if not n or type(here) ~= "table" or here.map == nil or type(input.contOf) ~= "function" then return false end
    local mine, theirs = input.contOf(here.map), input.contOf(n.map)
    return mine ~= nil and theirs ~= nil and mine ~= theirs
end

-- Section 402 item 3: how far a trainer is; one on another map, or with no
-- place seen, comes after every one on this map.
local function farness(input, npc)
    local n, here = placeOf(input, npc), input.here
    if not n or type(here) ~= "table" or n.map ~= here.map then return math.huge end
    return (n.x - (here.x or 0)) ^ 2 + (n.y - (here.y or 0)) ^ 2
end

-- This profession's trainer list nearest the player, never one away.
local function trainerAt(input)
    local best, bestD
    if type(input.trainerLists) ~= "table" then return nil end
    for _, key in ipairs(sortedKeys(input.trainerLists)) do
        local l = input.trainerLists[key]
        if type(l) == "table" and l.profession == input.prof and type(l.npc) == "string" and not away(input, l.npc) then
            local d = farness(input, l.npc)
            if not best or d < bestD or (d == bestD and l.npc < best.npc) then best, bestD = l, d end
        end
    end
    return best
end

local function npcTarget(input, npc)
    if type(npc) ~= "string" then return nil end
    local n = get(input.npcs, npc)
    if type(n) == "table" and n.map ~= nil and type(n.x) == "number" and type(n.y) == "number" then
        return { map = n.map, x = n.x, y = n.y }
    end
    return nil
end

local function reading(input)
    return string.format("%s %d of %d", input.prof, input.skill, input.max)
end

local function learnStep(input)
    if type(input.trainerLists) ~= "table" then return nil end
    for _, key in ipairs(sortedKeys(input.trainerLists)) do
        local l = input.trainerLists[key]
        if type(l) == "table" and l.profession == input.prof and type(l.rows) == "table"
            and not away(input, l.npc) then
            for _, row in ipairs(l.rows) do
                if type(row) == "table" and type(row.name) == "string" and row.state ~= "known"
                    and whole(row.skill) and row.skill <= input.skill then
                    local npc = l.npc
                    return { kind = "learn_recipe", recipe = row.name, npc = npc, target = npcTarget(input, npc),
                        text = string.format("Learn %s at %s (%s)", row.name, npc or "a trainer", reading(input)) }
                end
            end
        end
    end
    return nil
end

-- Section 400 item 2: the book read holds no recipe of this profession.
local function bookEmpty(input)
    for _, r in pairs(type(input.book) == "table" and input.book or {}) do
        if type(r) == "table" and r.profession == input.prof then return false end
    end
    return true
end

local function firstRecipeStep(input)
    local npc = get(trainerAt(input), "npc")
    return { kind = "learn_recipe", npc = npc, target = npcTarget(input, npc),
        text = string.format(P.LEARN_ANY, input.prof, npc or "a trainer", reading(input)) }
end

local function tierStep(input)
    local l = trainerAt(input)
    local npc = get(l, "npc")
    return { kind = "train_tier", npc = npc, target = npcTarget(input, npc),
        text = string.format("Train the next %s rank at %s (%d of %d)", input.prof, npc or "a trainer",
            input.skill, input.max) }
end

-- The steps for one candidate, or nil when its materials make none.
-- Section 402 item 4 (G19): the gathering tool is not in the bags and a
-- vendor price was seen for an item of that name: buy it first, with the
-- cost. No price seen: no step (the gather line names the tool).
local function toolStep(input)
    local tool = get(gathers(input), "tool")
    if type(tool) ~= "string" or type(input.name) ~= "function" then return nil end
    for key in pairs(type(input.bags) == "table" and input.bags or {}) do
        if count(input.bags, key) > 0 and input.name(key) == tool then return nil end
    end
    local keys = type(input.vendorItems) == "function" and input.vendorItems() or nil
    if type(keys) ~= "table" then return nil end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local price = type(input.vendorPrice) == "function" and input.vendorPrice(key) or nil
        if input.name(key) == tool and type(price) == "number" and price >= 0 and ns.Prices then
            local cost = ns.Prices.Text({ value = price, basis = ns.Prices.OBSERVED })
            return { kind = "buy_tool", item = key, cost = price, text = string.format(P.BUY_TOOL, tool, cost) }
        end
    end
    return nil
end

-- Section 388 (a), R1: one material's line, "Test Bar x4: 1 in your bags,
-- 1 from your bank, smelt 2 from 4 Test Ore".
local function matLine(input, item, need, bags, bank, smelt)
    local m = { item = item, need = need, bags = bags, bank = bank, smelt = smelt }
    local say = {}
    if bags > 0 then say[#say + 1] = string.format("%d in your bags", bags) end
    if bank > 0 then say[#say + 1] = string.format("%d from your bank", bank) end
    if smelt > 0 then
        local _, ore, per = smeltFor(input, item)
        m.ore, m.oreCount = ore, smelt * per
        say[#say + 1] = string.format("smelt %d from %d %s", smelt, m.oreCount, itemName(input, ore))
    end
    m.text = string.format("%s x%d: %s", itemName(input, item), need, table.concat(say, ", "))
    return m
end

local function craftSteps(input, c)
    local n = limit(input, c)
    for item, per in pairs(c.entry.mats) do
        n = math.min(n, math.floor((have(input, item)) / per))
    end
    if n < 1 then return nil end
    local ores, parts, banks, mats = {}, {}, {}, {}
    for _, item in ipairs(sortedKeys(c.entry.mats)) do
        local need = c.entry.mats[item] * n
        local _, bags, bank, smelt = have(input, item)
        local fromBank = math.min(bank, math.max(0, need - bags))
        local short = need - bags - fromBank
        mats[#mats + 1] = matLine(input, item, need, math.min(bags, need), fromBank, short)
        if fromBank > 0 then
            banks[#banks + 1] = { kind = "take_bank", item = item, count = fromBank, recipe = c.recipe,
                text = string.format("Take %d %s from your bank, for %s", fromBank, itemName(input, item), c.recipe) }
        end
        if short > 0 then
            local _, ore, per = smeltFor(input, item)
            local oreBags = count(input.bags, ore)
            local oreBank = math.min(count(input.bank, ore), math.max(0, short * per - oreBags))
            if oreBank > 0 then
                ores[#ores + 1] = { kind = "take_bank", item = ore, count = oreBank, recipe = c.recipe,
                    text = string.format("Take %d %s from your bank, for %s", oreBank, itemName(input, ore), c.recipe) }
            end
            parts[#parts + 1] = { kind = "make_part", item = item, count = short, recipe = smelt,
                station = P.SMELT_STATION, from = { item = ore, count = short * per },
                text = string.format("Smelt %d %s at %s, for %s", short, itemName(input, item),
                    article(P.SMELT_STATION), c.recipe) }
        end
    end
    local steps = {}
    for _, s in ipairs(ores) do steps[#steps + 1] = s end
    for _, s in ipairs(parts) do steps[#steps + 1] = s end
    for _, s in ipairs(banks) do steps[#steps + 1] = s end
    local at = ""
    if type(input.station) == "string" then
        at = " at " .. article(input.station)
        if input.atStation ~= true then
            steps[#steps + 1] = { kind = "go_station", station = input.station, target = input.stationTarget,
                text = "Go to " .. article(input.station) }
        end
    end
    steps[#steps + 1] = { kind = "craft", recipe = c.recipe, item = c.entry.makes, count = n,
        station = input.station, text = string.format("Make %d %s%s (%s)", n, c.recipe, at, reading(input)),
        mats = mats }
    return steps
end

-- The steps for the first candidate with its short materials named first,
-- or nil.
local function sourcedSteps(input, c)
    local n = limit(input, c)
    if n < 1 then return nil end
    local steps, extra = {}, {}
    for _, item in ipairs(sortedKeys(c.entry.mats)) do
        local need = c.entry.mats[item] * n
        local got = have(input, item)
        if need > got then
            local s = ns.ProfSources.For(input, item, need - got)
            -- Lead section 407 item 1: G19 keeps the auction house out of the
            -- gathering-tool step only; a short material may come from it.
            if s then
                s.recipe = c.recipe
                steps[#steps + 1] = s
                extra[item] = need - got
            end
        end
    end
    local filled = {}
    for k, v in pairs(input) do filled[k] = v end
    local bags = {}
    if type(input.bags) == "table" then
        for k in pairs(input.bags) do bags[k] = count(input.bags, k) end
    end
    for item, x in pairs(extra) do bags[item] = count(bags, item) + x end
    filled.bags = bags
    local rest = craftSteps(filled, c)
    if not rest then return nil end
    for _, s in ipairs(rest) do steps[#steps + 1] = s end
    return steps
end

local function sourced(input)
    return type(ns.ProfSources) == "table" and (input.nodes ~= nil or input.vendorPrice ~= nil)
end

-- Was any recipe colour of this profession read?
local function coloursRead(input)
    if type(input.colours) ~= "table" then return false end
    for name, r in pairs(type(input.book) == "table" and input.book or {}) do
        if type(r) == "table" and r.profession == input.prof and type(input.colours[name]) == "table" then
            return true
        end
    end
    return false
end

local function empty(why, input, about)
    if type(input) ~= "table" or type(input.prof) ~= "string" then return {}, why, P.SAY_NO_PROF end
    if why == "no reading" and gathers(input) then return {}, why, string.format(P.SAY_GATHER, input.prof) end
    if why == "no recipe" then
        local npc = get(trainerAt(input), "npc")
        if type(npc) == "string" and npc ~= "" then
            return {}, why, string.format(P.SAY_TRAINER, npc, input.prof)
        end
    end
    return {}, why, string.format(P.SAY[why], about or input.prof)
end

-- Queue item A2: the one step of a gathering profession with no craft to
-- make. target is the nearest node of its kind seen on the map the player
-- is on, or nil.
local function gatherStep(input)
    local g = gathers(input)
    local here, best, bestD = input.here, nil, nil
    if type(g.kind) == "string" and type(here) == "table" and here.map ~= nil and type(input.nodes) == "table" then
        for _, n in ipairs(input.nodes) do
            if type(n) == "table" and n.kind == g.kind and n.map == here.map
                and type(n.x) == "number" and type(n.y) == "number" then
                local d = (n.x - (here.x or 0)) ^ 2 + (n.y - (here.y or 0)) ^ 2
                if not best or d < bestD then best, bestD = n, d end
            end
        end
    end
    local line, step = g.text, { kind = "gather_skill", gather = input.prof }
    if best then
        step.target = { map = best.map, x = best.x, y = best.y }
        if type(best.node) == "string" and best.node ~= "" then
            step.node = best.node
            line = string.format(P.GATHER_NEAR, line, best.node)
        end
    end
    step.text = string.format("%s (%s)", line, reading(input))
    return step
end

-- Section 388 (a), R1: the skill a sure craft reaches and the next recipe
-- that gives a point, on the craft step: "Blacksmithing 50 -> 56, then X".
local function thenLine(input, list, c, steps)
    local craft = steps[#steps]
    if c.chance ~= "sure" then return steps end
    craft.reach = input.skill + craft.count
    craft.thenText = string.format("%s %d -> %d", input.prof, input.skill, craft.reach)
    for _, other in ipairs(list) do
        if other.recipe ~= c.recipe then
            craft.after = other.recipe
            craft.thenText = craft.thenText .. ", then " .. other.recipe
            break
        end
    end
    return steps
end

function P.Plan(input)
    if not usable(input) then return empty("no reading", input) end
    if input.skill >= input.max then
        if input.max >= P.TOP then return empty("at the top", input) end
        return { tierStep(input) }
    end
    local list = P.Candidates(input)
    for _, c in ipairs(list) do
        local steps = craftSteps(input, c)
        if steps then return thenLine(input, list, c, steps) end
    end
    if gathers(input) then
        local tool = toolStep(input)
        if tool then return { tool, gatherStep(input) } end
        return { gatherStep(input) }
    end
    if #list > 0 and sourced(input) then
        local steps = sourcedSteps(input, list[1])
        if steps then return thenLine(input, list, list[1], steps) end
    end
    if #list > 0 then return empty("no materials", input, list[1].recipe) end
    if bookEmpty(input) then return { learnStep(input) or firstRecipeStep(input) } end
    if not coloursRead(input) then return empty("no colours", input) end
    local learn = learnStep(input)
    if learn then return { learn } end
    return empty("no recipe", input)
end

-- Live reads -------------------------------------------------------------

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

-- The nearest seen station on this map that serves the craft, or nil.
local function stationTarget(stations, kind, pos)
    local spots = get(get(ns.Nav, "PROF_STATION_SPOTS"), kind)
    if type(spots) ~= "table" then spots = { [kind] = true } end
    if type(stations) ~= "table" or type(pos) ~= "table" or pos.map == nil then return nil end
    local best, bestD
    for _, s in ipairs(stations) do
        if type(s) == "table" and spots[s.kind] == true and s.map == pos.map
            and type(s.x) == "number" and type(s.y) == "number" then
            local d = (s.x - (pos.x or 0)) ^ 2 + (s.y - (pos.y or 0)) ^ 2
            if not best or d < bestD then best, bestD = s, d end
        end
    end
    if not best then return nil end
    return { map = best.map, x = best.x, y = best.y }
end

function P.Input(client, store, prof, nodeSource)
    local readings = saved(store, "char", "learned.facts.profSkill")
    local r = get(readings, prof)
    -- Queue item A2: a profession with no window (Herbalism, Skinning) never
    -- saves a reading, so its skill is read from the skill lines.
    if type(r) ~= "table" then
        local line = get(ask(client, "skillRanks"), prof)
        if type(line) == "table" then r = { skill = line.rank, max = line.max } end
    end
    local keyOf = ns.Items and ns.Items.Key or function(v) return v end
    local bags = call(get(ns.HaveTip, "Counts"), ask(client, "bagItems"), keyOf)
    local bank = get(saved(store, "char", "learned.bankCounts"), "counts")
    if type(bank) ~= "table" then bank = {} end
    local prices = saved(store, "account", "learned.prices")
    local kind = get(get(ns.Nav, "PROF_STATION"), prof)
    local pos = ask(client, "position")
    local stations = saved(store, "account", "learned.keyStations")
    local target
    if kind then target = stationTarget(stations, kind, pos) end
    local nodes
    if type(nodeSource) == "table" and type(nodeSource.Nodes) == "function" then
        local ok, list = pcall(nodeSource.Nodes)
        if ok and type(list) == "table" then
            nodes = {}
            for _, n in ipairs(list) do
                if type(n) == "table" then
                    -- Nodes() gives the current map's nodes, without a map.
                    local map = n.map
                    if map == nil then map = get(pos, "map") end
                    nodes[#nodes + 1] = { kind = n.kind, node = n.node, x = n.x, y = n.y, map = map }
                end
            end
        end
    end
    return {
        prof = prof,
        here = pos,
        nodes = nodes or {},
        vendorPrice = function(item)
            if type(prices) ~= "table" or not ns.Prices then return nil end
            local p = ns.Prices.Get(prices, item, "vendor")
            if type(p) == "table" and type(p.value) == "number" then return p.value end
            return nil
        end,
        skill = get(r, "skill"),
        max = get(r, "max"),
        book = saved(store, "char", "learned.facts.recipeBook"),
        colours = saved(store, "char", "learned.recipeColors"),
        bags = bags or {},
        bank = bank,
        price = function(item)
            if type(prices) ~= "table" or not ns.Prices then return nil end
            for _, k in ipairs({ "auction", "vendor" }) do
                local p = ns.Prices.Get(prices, item, k)
                if type(p) == "table" and type(p.value) == "number" then return p.value end
            end
            return nil
        end,
        vendorItems = function()
            local out = {}
            for key in pairs(type(get(prices, "vendor")) == "table" and prices.vendor or {}) do out[#out + 1] = key end
            return out
        end,
        name = function(item)
            local info = ask(client, "itemInfo", item)
            return get(info, "name")
        end,
        trainerLists = saved(store, "char", "learned.trainerLists"),
        npcs = saved(store, "account", "learned.places.npcs"),
        contOf = function(map) return ask(client, "mapCont", map) end,
        station = kind,
        stationTarget = target,
        atStation = false,
    }
end

function P.Declare(k)
    local api = {}
    local ctx
    function api.plan(prof)
        if not ctx then return {}, "no reading", P.SAY_NO_PROF end
        local source
        if type(ctx.use) == "function" then
            local ok, s = pcall(ctx.use, P.NODE_SOURCE)
            if ok then source = s end
        end
        return P.Plan(P.Input(ctx.client, ctx.store, prof, source))
    end
    k:Module({
        name = P.NAME,
        needs = { "client", "store" },
        provides = { Plan = api.plan },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.profPlan = P.Declare(ns)
