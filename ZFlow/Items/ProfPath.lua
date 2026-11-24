local _, ns = ...

-- ProfPath (lead section 449, P-PATH-1): the path of one profession from
-- the current skill to 300, as brackets of one recipe each, with the
-- materials it takes (less what the bags and bank hold) and where each
-- comes from. Pure and free of UI: the window (P-PATH-2) and the arrow
-- (P-PATH-3) read what this returns.
--
--   path, why = ProfPath.Path(input)
--   input     = ProfPath.FromPlanInput(ProfPlan.Input(client, store, prof))
--   colour, seen = ProfPath.Colour(row, skill, colours)
--   n         = ProfPath.CraftsPerPoint(row, colour, skill)
--   source    = ProfPath.Source(item, price, data)
--   line      = ProfPath.Text(bracket)
--
-- input = {
--   prof, skill, max     the profession, its skill and its current cap
--   known                { [recipe] = true }: recipes this character knows
--   bags, bank           { [itemID] = count }
--   prices               { [itemID] = copper } or function(itemID) -> copper
--   colours              char "learned.recipeColors" (Items/RecipeColours.lua)
--   faction              "Horde" | "Alliance" | nil (nil keeps both sides)
--   data                 the rows (default ns.ProfData)
-- }
-- path = {
--   prof, from, to,
--   brackets = { { from, to, recipe, item, count, colour, seen, learn,
--                  recipeItem, trainer, station, tool, mats, text } },
--   trains   = { { at, cap } }   train the next rank at this skill
--   mats     = { { item, name, need, bags, bank, short, source } } by item
--   lines    = the brackets' text, in order
-- }
-- why (no path): "no reading", "no data", "at the top".
--
-- At each skill the pick is the cheapest recipe that is orange or yellow:
-- the colour the player saw in game wins over the table's numbers. Cost is
-- per point: the materials at the prices given, else the table's vendor
-- price, else nothing for what you gather, fish, loot, smelt or make
-- yourself; an unknown cost sorts after every known one. Only when nothing
-- is orange or yellow is the cheapest green used, so the path never stops.
-- First guesses, not seen in game: crafts per point (orange 1; yellow
-- (grey - yellow) / (grey - skill), else 1.5; green 4), the herb colours
-- (learn + 25 / 50 / 100, as the table's ore veins) and catches per point
-- while fishing (1 + skill / 150).
local ProfPath = {}
ns.ProfPath = ProfPath

ProfPath.TOP = 300
ProfPath.TIERS = { 75, 150, 225, 300 }
ProfPath.AUCTION = "Auction House"
ProfPath.FISH = "Fish"
ProfPath.LINE = "skill %d\226\128\147%d: %s \195\151%d"
ProfPath.NONE = "no recipe gives a point"
ProfPath.PER = { optimal = 1, medium = 1.5, easy = 4 }
ProfPath.HERB = { yellow = 25, green = 50, grey = 100 }
ProfPath.SOURCE_TEXT = {
    gather = "Gather (%s)",
    fish = "Fish",
    kill = "Kill: %s",
    smelt = "Smelt (%s)",
    make = "Make it (%s)",
    vendor = "Vendor, %s",
}

local ORDER = { "optimal", "medium", "easy", "trivial" }
local FREE = { gather = true, fish = true, kill = true, smelt = true, make = true }

local function whole(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge and n == math.floor(n)
end

local function dataOf(input)
    if type(input) == "table" and type(input.data) == "table" then return input.data end
    return ns.ProfData
end

local function priceOf(prices, item)
    if type(prices) == "function" then
        local ok, v = pcall(prices, item)
        if ok and type(v) == "number" then return v end
        return nil
    end
    if type(prices) == "table" and type(prices[item]) == "number" then return prices[item] end
    return nil
end

local function count(t, item)
    if type(t) ~= "table" or not whole(t[item]) then return 0 end
    return t[item]
end

-- The colour of a row at a skill: the one seen in game when a seen span
-- holds the skill, else from the table. nil when not learnable yet.
function ProfPath.Colour(row, skill, colours)
    if type(row) ~= "table" or not whole(skill) then return nil, false end
    local name = row.recipe or row.name
    local spans = type(colours) == "table" and name ~= nil and colours[name] or nil
    if type(spans) == "table" then
        for _, d in ipairs(ORDER) do
            local s = spans[d]
            if type(s) == "table" and type(s.lo) == "number" and type(s.hi) == "number"
                and skill >= s.lo and skill <= s.hi then
                return d, true
            end
        end
    end
    if type(row.learn) ~= "number" or skill < row.learn then return nil, false end
    if type(row.yellow) == "number" and skill < row.yellow then return "optimal", false end
    if type(row.green) == "number" and skill < row.green then return "medium", false end
    if type(row.grey) == "number" and skill < row.grey then return "easy", false end
    return "trivial", false
end

function ProfPath.CraftsPerPoint(row, colour, skill)
    if colour == "medium" and type(row) == "table" and type(row.yellow) == "number"
        and type(row.grey) == "number" and row.grey > row.yellow and whole(skill)
        and skill >= row.yellow and skill < row.grey then
        return (row.grey - row.yellow) / (row.grey - skill)
    end
    return ProfPath.PER[colour]
end

-- Where an item comes from: { kind, text, price }. kind is gather, fish,
-- kill, smelt, make, vendor or auction (no source in the table).
function ProfPath.Source(item, price, data)
    data = type(data) == "table" and data or ns.ProfData
    local s = type(data) == "table" and type(data.SOURCES) == "table" and data.SOURCES[item] or nil
    local T = ProfPath.SOURCE_TEXT
    if type(s) ~= "table" then return { kind = "auction", text = ProfPath.AUCTION } end
    if s.vendor then
        local seen = type(price) == "number"
        local p = seen and price or s.price
        local text
        if ns.Prices and ns.Prices.Text then
            text = ns.Prices.Text(type(p) == "number" and { value = p,
                basis = seen and ns.Prices.OBSERVED or ns.Prices.ESTIMATED } or nil, "vendor")
        end
        return { kind = "vendor", price = p, text = T.vendor:format(text or "price unknown\226\128\148check vendor") }
    end
    if type(s.gather) == "string" then return { kind = "gather", text = T.gather:format(s.gather) } end
    if s.fished then return { kind = "fish", text = T.fish } end
    if type(s.drops) == "table" and #s.drops > 0 then
        return { kind = "kill", text = T.kill:format(table.concat(s.drops, ", ")) }
    end
    if type(s.smelt) == "table" and type(s.smelt.spell) == "string" then
        return { kind = "smelt", text = T.smelt:format(s.smelt.spell) }
    end
    if type(s.made) == "string" then return { kind = "make", text = T.make:format(s.made) } end
    return { kind = "auction", text = ProfPath.AUCTION }
end

-- Copper for one, or nil when not known (free for a source you work yourself).
local function unitCost(input, data, item)
    local p = priceOf(input.prices, item)
    if p then return p end
    local src = ProfPath.Source(item, nil, data)
    if src.kind == "vendor" then return src.price end
    if FREE[src.kind] then return 0 end
    return nil
end

local function craftCost(input, data, mats)
    local total = 0
    for item, per in pairs(type(mats) == "table" and mats or {}) do
        local c = unitCost(input, data, item)
        if c == nil then return nil end
        total = total + c * per
    end
    return total
end

function ProfPath.Text(b)
    return ProfPath.LINE:format(b.from, b.to, b.recipe or ProfPath.NONE, b.count or 0)
end

-- The rows one point can come from: crafts, nodes, or the herbs of the table.
local function rowsOf(input, data, g)
    local rows = {}
    if type(g.nodes) == "table" and #g.nodes > 0 then
        for _, n in ipairs(g.nodes) do
            local s = data.SOURCES and data.SOURCES[n.item]
            rows[#rows + 1] = { recipe = type(s) == "table" and s.node or tostring(n.item), item = n.item,
                learn = n.learn, yellow = n.yellow, green = n.green, grey = n.grey, gather = true }
        end
        return rows
    end
    if g.kind == "gather" then
        local H = ProfPath.HERB
        for item, s in pairs(type(data.SOURCES) == "table" and data.SOURCES or {}) do
            if type(s) == "table" and s.gather == input.prof and whole(s.skill) then
                rows[#rows + 1] = { recipe = s.node or s.name, item = item, learn = s.skill,
                    yellow = s.skill + H.yellow, green = s.skill + H.green, grey = s.skill + H.grey, gather = true }
            end
        end
        return rows
    end
    for _, r in ipairs(type(g.steps) == "table" and g.steps or {}) do
        if type(r) == "table" and type(r.recipe) == "string"
            and (r.faction == nil or input.faction == nil or r.faction == input.faction) then
            rows[#rows + 1] = r
        end
    end
    return rows
end

-- The pick at one skill: row, colour, seen, crafts for this point.
local function pick(input, data, rows, skill)
    local best
    for _, r in ipairs(rows) do
        local colour, seen = ProfPath.Colour(r, skill, input.colours)
        local per = colour and ProfPath.PER[colour] and ProfPath.CraftsPerPoint(r, colour, skill)
        if per then
            local cost = craftCost(input, data, r.mats)
            local c = { row = r, colour = colour, seen = seen, per = per,
                tier = colour == "easy" and 2 or 1, cost = cost and cost * per or nil }
            if best == nil then
                best = c
            else
                local better
                if c.tier ~= best.tier then better = c.tier < best.tier
                elseif (c.cost == nil) ~= (best.cost == nil) then better = c.cost ~= nil
                elseif c.cost ~= best.cost then better = c.cost < best.cost
                elseif c.colour ~= best.colour then better = c.colour == "optimal"
                else better = r.recipe < best.row.recipe end
                if better then best = c end
            end
        end
    end
    return best
end

local function firstCap(skill, max)
    if whole(max) and max > skill then return max end
    for _, t in ipairs(ProfPath.TIERS) do
        if t > skill then return t end
    end
    return ProfPath.TOP
end

local function known(input, recipe)
    return type(input.known) == "table" and input.known[recipe] ~= nil and input.known[recipe] ~= false
end

-- Lead section 450: the contract fields on a made path. The brackets,
-- trains, mats and lines above stay for the readers that came first.
local revs = {}

local function learnAt(b)
    if b.learn ~= true then return { kind = "known" } end
    if b.recipeItem ~= nil then return { kind = "recipe", item = b.recipeItem } end
    return { kind = "trainer", npc = b.trainer }
end

local function nameOf(input, item)
    if type(input.name) ~= "function" then return nil end
    local ok, v = pcall(input.name, item)
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

-- The bank counts as seen when the input says so, or (no word either way)
-- when it was handed a bank table at all.
local function bankSeenOf(input)
    if input.bankSeen ~= nil then return input.bankSeen == true end
    return type(input.bank) == "table"
end

-- Lead section 450, "Selected": the range the player picked (input.pick,
-- { recipe, from }), found again by its recipe as the skill moves; else the
-- first range with a recipe, so with a point to give. index, picked.
local function selectedOf(ranges, pick)
    if type(pick) == "table" and type(pick.recipe) == "string" then
        local first
        for i, r in ipairs(ranges) do
            if r.recipe == pick.recipe then
                if r.from == pick.from then return i, true end
                if first == nil then first = i end
            end
        end
        if first ~= nil then return first, true end
    end
    for i, r in ipairs(ranges) do
        if r.recipe ~= nil then return i, false end
    end
    if ranges[1] then return 1, false end
    return nil, false
end

local function contract(input, path)
    local parts = { tostring(input.skill), tostring(input.max) }
    local at = {}
    for _, tr in ipairs(path.trains) do at[tr.at] = tr.cap end
    path.id, path.skill, path.status = input.prof, input.skill, "ok"
    if whole(input.max) then path.max = input.max else path.max = firstCap(input.skill, nil) end
    path.ranges, path.materials, path.tasks = {}, {}, {}
    for _, b in ipairs(path.brackets) do
        local colourFrom = "table"
        if b.seen == true then colourFrom = "seen" end
        local range = { from = b.from, to = b.to, recipe = b.recipe, crafts = b.count,
            sure = b.colour == "optimal", colourFrom = colourFrom, learnAt = learnAt(b),
            station = b.station, alternatives = {}, parts = b.mats }
        if at[b.from] ~= nil then range.prereq = { skill = b.from, tier = at[b.from] } end
        path.ranges[#path.ranges + 1] = range
        parts[#parts + 1] = table.concat({ b.from, b.to, tostring(b.recipe), b.count, tostring(b.colour),
            colourFrom, range.learnAt.kind }, ":")
    end
    path.selected, path.picked = selectedOf(path.ranges, input.pick)
    parts[#parts + 1] = "selected:" .. tostring(path.selected) .. ":" .. tostring(path.picked)
    local seen = bankSeenOf(input)
    for _, m in ipairs(path.mats) do
        local row = { item = m.item, name = m.name or nameOf(input, m.item), need = m.need, bags = m.bags,
            bankSeen = seen, allocated = 0, source = m.source }
        local left = m.need - m.bags
        if seen then
            row.bank = m.bank
            row.net = math.max(0, left - m.bank)
        elseif left <= 0 then
            row.net = 0
        else
            row.net = "unknown"
        end
        path.materials[#path.materials + 1] = row
        parts[#parts + 1] = table.concat({ tostring(m.item), m.need, m.bags, tostring(row.bank), tostring(row.net),
            tostring(m.source and m.source.price) }, ":")
    end
    -- rev: one more each time anything a reader shows has changed.
    local sig = table.concat(parts, "|")
    local r = revs[input.prof]
    if r == nil then
        r = { sig = sig, n = 1 }
        revs[input.prof] = r
    elseif r.sig ~= sig then
        r.sig, r.n = sig, r.n + 1
    end
    path.rev = r.n
    return path
end

function ProfPath.Path(input)
    if type(input) ~= "table" or type(input.prof) ~= "string" or not whole(input.skill) then
        return nil, "no reading"
    end
    local data = dataOf(input)
    local g = type(data) == "table" and type(data.PROFS) == "table" and data.PROFS[input.prof] or nil
    if type(g) ~= "table" then return nil, "no data" end
    if input.skill >= ProfPath.TOP then return nil, "at the top" end
    local fishing = g.kind == "gather" and type(g.nodes) ~= "table" and input.prof == "Fishing"
    local rows = fishing and {} or rowsOf(input, data, g)
    local path = { prof = input.prof, from = input.skill, to = ProfPath.TOP,
        brackets = {}, trains = {}, mats = {}, lines = {} }
    local cap = firstCap(input.skill, input.max)
    local cur, crafts
    local function close()
        if cur then
            cur.count = math.ceil(crafts - 1e-9)
            cur.text = ProfPath.Text(cur)
            path.brackets[#path.brackets + 1] = cur
            path.lines[#path.lines + 1] = cur.text
        end
        cur = nil
    end
    local skill = input.skill
    while skill < ProfPath.TOP do
        if skill >= cap then
            close()
            local nextCap = firstCap(cap, nil)
            path.trains[#path.trains + 1] = { at = skill, cap = nextCap }
            cap = nextCap
        end
        local name, row, c, per
        if fishing then
            name, per = ProfPath.FISH, 1 + skill / 150
        else
            c = pick(input, data, rows, skill)
            row = c and c.row
            name = row and row.recipe or nil
            per = c and c.per or 1
        end
        if cur == nil or cur.recipe ~= name then
            close()
            cur = { from = skill, recipe = name, item = row and row.item, colour = c and c.colour,
                seen = c and c.seen or false, recipeItem = row and row.recipeItem, trainer = row and row.trainer,
                station = row and row.station, tool = row and row.tool or g.tool, mats = row and row.mats }
            cur.learn = row ~= nil and not row.gather and not known(input, name)
            crafts = 0
        end
        crafts = crafts + per
        skill = skill + 1
        cur.to = skill
    end
    close()
    -- Materials: the brackets' crafts, less the bags and the bank.
    local need, order = {}, {}
    for _, b in ipairs(path.brackets) do
        for item, per in pairs(type(b.mats) == "table" and b.mats or {}) do
            if need[item] == nil then order[#order + 1] = item; need[item] = 0 end
            need[item] = need[item] + per * b.count
        end
    end
    table.sort(order)
    for _, item in ipairs(order) do
        local bags, bank = count(input.bags, item), count(input.bank, item)
        local s = type(data.SOURCES) == "table" and data.SOURCES[item] or nil
        path.mats[#path.mats + 1] = { item = item, name = type(s) == "table" and s.name or nil,
            need = need[item], bags = bags, bank = bank, short = math.max(0, need[item] - bags - bank),
            source = ProfPath.Source(item, priceOf(input.prices, item), data) }
    end
    return contract(input, path)
end

-- The profession plan's input (Items/ProfPlan.lua, ProfPlan.Input) as a path
-- input: the same readers, one shape.
function ProfPath.FromPlanInput(p)
    if type(p) ~= "table" then return nil end
    local knownSet = {}
    for name, r in pairs(type(p.book) == "table" and p.book or {}) do
        if type(r) == "table" and r.profession == p.prof then knownSet[name] = true end
    end
    return { prof = p.prof, skill = p.skill, max = p.max, known = knownSet, colours = p.colours,
        bags = p.bags, bank = p.bank, bankSeen = p.bankSeen, prices = p.price, faction = p.faction,
        name = p.name }
end

-- Lead section 450, "Selected": the player's pick is kept for the character,
-- one per profession, as the range's recipe and where it started.
ProfPath.PICKS = "layout.profPathPick"

local function picks(store)
    if type(store) ~= "table" or type(store.get) ~= "function" then return {} end
    local ok, v = pcall(store.get, store, "char", ProfPath.PICKS)
    if ok and type(v) == "table" then return v end
    return {}
end

-- The saved pick of a profession, { recipe, from }, or nil.
function ProfPath.Picked(store, prof)
    local p = picks(store)[prof]
    if type(p) == "table" and type(p.recipe) == "string" then return { recipe = p.recipe, from = p.from } end
    return nil
end

-- Keep the range the player picked (a range of the plan); nil forgets it.
-- true when it was saved.
function ProfPath.Select(store, prof, range)
    if type(prof) ~= "string" or type(store) ~= "table" or type(store.set) ~= "function" then return false end
    local all = picks(store)
    if type(range) == "table" and type(range.recipe) == "string" then
        all[prof] = { recipe = range.recipe, from = range.from }
    else
        all[prof] = nil
    end
    local ok = pcall(store.set, store, "char", ProfPath.PICKS, all)
    return ok
end

-- Lead section 450, "Task": the selected range's steps, in ProfPlan's kinds,
-- each with what is left of it. With nothing picked they are the planner's
-- own steps. A picked recipe the player does not know yet is learned first
-- (where is not known here, so the step has no place); a picked recipe that
-- gives a point now is the one the planner plans.
local function tasksOf(P, planInput, path)
    local range = path.ranges[path.selected]
    local b = path.brackets[path.selected]
    if path.picked ~= true or type(range) ~= "table" then return P.Plan(planInput) end
    if type(b) == "table" and b.learn == true then
        local where = "a trainer"
        if range.learnAt.kind == "recipe" then where = "its recipe" end
        return { { kind = "learn_recipe", recipe = range.recipe, npc = range.learnAt.npc,
            item = range.learnAt.item, remaining = 1,
            text = string.format("Learn %s from %s (%s %d of %d)", range.recipe, where, path.prof,
                path.skill, path.max) } }
    end
    local wanted = {}
    for k, v in pairs(planInput) do wanted[k] = v end
    wanted.want = range.recipe
    local steps, why, say = P.Plan(wanted)
    for _, s in ipairs(steps) do
        if s.kind == "craft" and s.recipe == range.recipe then
            s.remaining = range.crafts
        elseif s.remaining == nil then
            s.remaining = s.count
        end
    end
    return steps, why, say
end

-- The one live plan (lead section 450): the path panel and the arrow's feed
-- both read it here, so one rev counts for both. The open profession
-- window's own skill is the newest reading there is. source is ProfPlan's
-- node source, or nil. nil when there is no path.
function ProfPath.Live(client, store, prof, source)
    if type(prof) ~= "string" or prof == "" or type(client) ~= "table" then return nil end
    local P = ns.ProfPlan
    local input, planInput
    if type(P) == "table" and type(P.Input) == "function" then
        local ok, v = pcall(P.Input, client, store, prof, source)
        if ok and type(v) == "table" then
            planInput = v
            input = ProfPath.FromPlanInput(v)
        end
    end
    if type(input) ~= "table" then input = { prof = prof } end
    input.pick = ProfPath.Picked(store, prof)
    local r
    for _, name in ipairs({ "recipes", "tradeSkillRows" }) do
        if type(r) ~= "table" and type(client[name]) == "function" then
            local ok, v = pcall(client[name])
            if ok then r = v end
        end
    end
    if type(r) == "table" and r.name == prof and whole(r.skill) and whole(r.max) then
        input.skill, input.max = r.skill, r.max
        if planInput then planInput.skill, planInput.max = r.skill, r.max end
    end
    local ok, path = pcall(ProfPath.Path, input)
    if not ok or type(path) ~= "table" then return nil end
    if planInput and type(P.Plan) == "function" then
        local done, tasks, why, say = pcall(tasksOf, P, planInput, path)
        if done and type(tasks) == "table" then
            path.tasks, path.taskWhy, path.say, path.planned = tasks, why, say, true
        end
    end
    return path
end
