local _, ns = ...
-- P-PROF slice 1 (Lazy, zflow-prof-lz-1), as Flow's SkillPlan RecipeWait:
-- a recipe item in your bags whose recipe the recipe book does not hold
-- gets one look-only advisor prompt, "use it to learn". Never uses it.
--
-- L.Prompts(stacks, nameOf, book) -> { { id, text, priority, look }, ... }
--   stacks  client.bagItems(): { { item, count }, ... }
--   nameOf  function(id) -> the item's name, or nil (not read: no prompt)
--   book    char "learned.facts.recipeBook" (Items/RecipeBook.lua), by name
-- A recipe item is one whose name starts with L.PREFIXES (first guess:
-- the item's class is not read). Sorted by item id; one prompt an item.
-- The book holds only professions whose window was opened, so a recipe of
-- a profession you never opened is offered too (first guess, needs a game
-- test).
-- L.Sync(advisor, stacks, nameOf, book, shown) -> the ids now shown.
-- Module L.Declare(k): on login and BAG_UPDATE_DELAYED.
local L = {}
ns.ProfLearn = L
L.NAME = "profLearn"
L.ADVISOR = "advisor"
L.PREFIX = "aps.proflearn."
L.PRIORITY = 1
L.PREFIXES = { "Recipe: ", "Pattern: ", "Plans: ", "Formula: ", "Schematic: ", "Manual: " }

local function taught(name)
    for _, p in ipairs(L.PREFIXES) do
        if name:sub(1, #p) == p and #name > #p then return name:sub(#p + 1) end
    end
    return nil
end

function L.Prompts(stacks, nameOf, book)
    local out = {}
    if type(stacks) ~= "table" or type(nameOf) ~= "function" then return out end
    if type(book) ~= "table" then book = {} end
    local seen = {}
    for _, st in ipairs(stacks) do
        local id = nil
        if type(st) == "table" then id = ns.Items.Id(st.item) end
        if id and not seen[id] then
            seen[id] = true
            local ok, name = pcall(nameOf, id)
            if ok and type(name) == "string" then
                local recipe = taught(name)
                if recipe and book[recipe] == nil then
                    out[#out + 1] = { id = L.PREFIX .. id, item = id, priority = L.PRIORITY, look = true,
                        text = name .. " is in your bags: use it to learn " .. recipe .. "." }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.item < b.item end)
    return out
end

function L.Sync(advisor, stacks, nameOf, book, shown)
    if type(shown) ~= "table" then shown = {} end
    if type(advisor) ~= "table" or type(advisor.Add) ~= "function" or type(advisor.Remove) ~= "function" then
        return shown
    end
    local now = {}
    for _, p in ipairs(L.Prompts(stacks, nameOf, book)) do
        if advisor.Add(p.id, p.text, p.priority) then now[p.id] = true end
    end
    for id in pairs(shown) do
        if not now[id] then advisor.Remove(id) end
    end
    return now
end

function L.Declare(k)
    local shown, advisor = {}, nil
    k:Module({
        name = L.NAME,
        needs = { "client", "store", "bus", L.ADVISOR },
        start = function(ctx)
            local client = ctx.client
            local function nameOf(id)
                if type(client.itemInfo) ~= "function" then return nil end
                local info = client.itemInfo(id)
                if type(info) == "table" then return info.name end
                return nil
            end
            local function sync()
                local okA, found = pcall(ctx.use, L.ADVISOR)
                if not okA or type(found) ~= "table" then return end
                advisor = found
                if type(client.bagItems) ~= "function" then return end
                local okB, stacks = pcall(client.bagItems)
                if not okB then return end
                local okS, now = pcall(L.Sync, advisor, stacks, nameOf,
                    ctx.store:get("char", ns.RecipeBook.PATH), shown)
                if okS and type(now) == "table" then shown = now end
            end
            ctx.bus:on(L.NAME, "PLAYER_ENTERING_WORLD", sync)
            ctx.bus:on(L.NAME, "BAG_UPDATE_DELAYED", sync)
        end,
        stop = function()
            if type(advisor) == "table" and type(advisor.Remove) == "function" then
                for id in pairs(shown) do pcall(advisor.Remove, id) end
            end
            shown = {}
        end,
    })
end

L.Declare(ns)
