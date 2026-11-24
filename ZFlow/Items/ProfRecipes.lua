local _, ns = ...
-- Z-Flow profession coach, C4 (DISPATCH 382-384): where a recipe the
-- character is missing comes from. Look-only, pure Lua 5.1: every fact
-- arrives as an argument. Steps use the 382 contract shape
-- { kind, text, item, count, target }; target is { map, x, y } only when
-- the place was actually seen, else nil. Nothing is guessed.
--
-- recipe = { name, profession, item = recipe item key (optional) }
-- facts  = { stacks = { { item, count } }, nameOf = fn(key) -> name,
--            trainerLists = char "learned.trainerLists",
--            npcs = account "learned.places.npcs",
--            prices = account "learned.prices" }
local PR = {}
ns.ProfRecipes = PR

PR.PREFIXES = { "Recipe: ", "Pattern: ", "Plans: ", "Formula: ", "Schematic: ", "Manual: " }

local function str(v)
    return type(v) == "string" and v ~= ""
end

local function nameOf(facts, key)
    if type(facts.nameOf) ~= "function" or key == nil then return nil end
    local ok, n = pcall(facts.nameOf, key)
    if ok and str(n) then return n end
    return nil
end

local function isRecipeName(n, name)
    for i = 1, #PR.PREFIXES do
        if n == PR.PREFIXES[i] .. name then return true end
    end
    return false
end

local function fromBags(recipe, facts)
    if type(facts.stacks) ~= "table" then return nil end
    for i = 1, #facts.stacks do
        local st = facts.stacks[i]
        if type(st) == "table" and st.item ~= nil then
            local n = nameOf(facts, st.item)
            local same = recipe.item ~= nil and ns.Items.Same(st.item, recipe.item)
            if same or (n and isRecipeName(n, recipe.name)) then
                local label = n or ("the recipe for " .. recipe.name)
                return { kind = "learn_recipe", item = st.item, count = 1, target = nil,
                         text = label .. " is in your bags: right-click it to learn it." }
            end
        end
    end
    return nil
end

local function placeOf(facts, npc)
    local p = type(facts.npcs) == "table" and facts.npcs[npc]
    if type(p) ~= "table" then return nil end
    if type(p.map) ~= "number" or type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
    return { map = p.map, x = p.x, y = p.y }
end

-- -> step, or "known", or nil.
local function fromTrainer(recipe, facts)
    if type(facts.trainerLists) ~= "table" then return nil end
    local best
    for _, list in pairs(facts.trainerLists) do
        if type(list) == "table" and list.profession == recipe.profession and type(list.rows) == "table" then
            for i = 1, #list.rows do
                local r = list.rows[i]
                if type(r) == "table" and r.name == recipe.name then
                    if r.state == "known" then return "known" end
                    if not best or (best.row.state ~= "available" and r.state == "available") then
                        best = { row = r, npc = list.npc }
                    end
                end
            end
        end
    end
    if not best then return nil end
    local r = best.row
    local text = "Learn " .. recipe.name
    if str(best.npc) then
        text = text .. " from " .. best.npc .. ", your " .. recipe.profession .. " trainer"
    else
        text = text .. " from your " .. recipe.profession .. " trainer"
    end
    local coin = ns.Prices.Coin(r.cost)
    if coin then text = text .. ", for " .. coin end
    if r.state == "unavailable" and type(r.skill) == "number" then
        text = text .. ", once your " .. recipe.profession .. " is " .. r.skill
    end
    local target
    if str(best.npc) then target = placeOf(facts, best.npc) end
    return { kind = "learn_recipe", item = recipe.item, count = 1, target = target, text = text .. "." }
end

local function fromVendor(recipe, facts)
    if recipe.item == nil or type(facts.prices) ~= "table" then return nil end
    local key = ns.Items.Key(recipe.item)
    if key == nil then return nil end
    local p = ns.Prices.Get(facts.prices, key, "vendor")
    local coin = type(p) == "table" and ns.Prices.Coin(p.value)
    if not coin then return nil end
    local label = nameOf(facts, key) or ("the recipe for " .. recipe.name)
    return { kind = "buy_vendor", item = key, count = 1, target = nil,
             text = "A vendor you visited sells " .. label .. " for " .. coin
                 .. ": buy it, then right-click it to learn it." }
end

-- -> { steps }: every source known, bags first, then trainer, then vendor;
-- one step saying what to do so it will know when none is; {} when the
-- recipe is known or isn't one.
function PR.Steps(recipe, facts)
    local out = {}
    if type(recipe) ~= "table" or not str(recipe.name) or not str(recipe.profession) then return out end
    if type(facts) ~= "table" then facts = {} end
    local trainer = fromTrainer(recipe, facts)
    if trainer == "known" then return out end
    local bags = fromBags(recipe, facts)
    if bags then out[#out + 1] = bags end
    if trainer then out[#out + 1] = trainer end
    local vendor = fromVendor(recipe, facts)
    if vendor then out[#out + 1] = vendor end
    if #out == 0 then
        out[1] = { kind = "learn_recipe", item = recipe.item, count = 1, target = nil,
                   text = "Z-Flow does not know where to learn " .. recipe.name .. " yet: talk to your "
                       .. recipe.profession .. " trainer once so it can check." }
    end
    return out
end
