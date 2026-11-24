local _, ns = ...
-- Lead section 406 item 3: the profession guide reads recipe facts through
-- this one interface. Two providers, in order:
--   seen:    what this character saw in game (its recipe book, the trainer
--            lists it opened). The working path.
--   shipped: a factual table shipped with the addon. Empty: it is filled
--            only from a source the lead cleared (section 406 item 1), never
--            from a site, guide or other addon.
-- A shipped row never overrides a seen one: a recipe in the book, or on a
-- seen trainer list of the same profession, is left out. The order of the
-- plan's steps stays ours (Items/ProfPlan.lua), from skill and material facts.
local RF = {}

-- [profession] = { { name = recipe, skill = skill to learn it }, ... }
RF.SHIPPED = {}

-- Shipped rows sit under one list per profession, keyed to sort after every
-- seen list, with no trainer named.
RF.SHIPPED_KEY = "~shipped:%s"

local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

local function whole(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge and n == math.floor(n)
end

function RF.Seen(store)
    return {
        book = saved(store, "char", "learned.facts.recipeBook"),
        trainerLists = saved(store, "char", "learned.trainerLists"),
    }
end

-- facts: what the providers before this one gave ({ book, trainerLists }).
function RF.Shipped(facts, shipped)
    local out = {}
    local book = type(facts.book) == "table" and facts.book or {}
    local seenLists = type(facts.trainerLists) == "table" and facts.trainerLists or {}
    for prof, rows in pairs(type(shipped) == "table" and shipped or {}) do
        if type(prof) == "string" and type(rows) == "table" then
            local seen = {}
            for _, l in pairs(seenLists) do
                if type(l) == "table" and l.profession == prof and type(l.rows) == "table" then
                    for _, r in ipairs(l.rows) do
                        if type(r) == "table" and type(r.name) == "string" then seen[r.name] = true end
                    end
                end
            end
            local list = {}
            for _, r in ipairs(rows) do
                if type(r) == "table" and type(r.name) == "string" and whole(r.skill) and not seen[r.name] then
                    local known = type(book[r.name]) == "table" and book[r.name].profession == prof
                    list[#list + 1] = { name = r.name, skill = r.skill, state = known and "known" or nil }
                end
            end
            table.sort(list, function(a, b)
                if a.skill ~= b.skill then return a.skill < b.skill end
                return a.name < b.name
            end)
            if #list > 0 then out[RF.SHIPPED_KEY:format(prof)] = { profession = prof, rows = list } end
        end
    end
    return out
end

-- The recipe facts the plan reads: { book, trainerLists }. Each field is
-- nil when no provider gave it (the plan reads nil as not seen).
function RF.Read(store, shipped)
    local facts = RF.Seen(store)
    local extra = RF.Shipped(facts, shipped == nil and RF.SHIPPED or shipped)
    if next(extra) ~= nil then
        local lists = {}
        for k, l in pairs(type(facts.trainerLists) == "table" and facts.trainerLists or {}) do lists[k] = l end
        for k, l in pairs(extra) do lists[k] = l end
        facts.trainerLists = lists
    end
    return facts
end

ns.RecipeFacts = RF
