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
    return path
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
        bags = p.bags, bank = p.bank, prices = p.price, faction = p.faction }
end
