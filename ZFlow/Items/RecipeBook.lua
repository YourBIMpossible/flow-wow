local _, ns = ...

-- RecipeBook: what this player's own profession windows showed of each
-- learned recipe, saved for the goals list (Items/Goals.lua) and for
-- P-CRAFT to craft from. Section 227 (P-GOALS-RECIPE). Nothing is authored
-- here, no recipe is shipped, and nothing is printed.
--
-- When a profession window answers (client.recipes()), each recipe in it
-- that is learned, has a name and an id, and whose schematic the client
-- reads (client.recipeSchematic(id)) is saved under its name:
--   char "learned.facts.recipeBook"[name] =
--     { id, makes, yield, mats = { [item] = n a craft }, profession }
-- Entries already saved (another profession's) are kept; one with the same
-- name is replaced. Nothing to save, or no answer: nothing is written.
--
--   RecipeBook.Read(client, store) -> report   one profession window read
--     report = { ok, reason (when not ok), saved = entries written }
--   RecipeBook.Recipes(k) -> { [name] = { id, makes, yield, mats } }
--     the saved entries that read, as ItemPlan reads recipes; {} while the
--     store is not open. An entry that can't be read is left out (and left
--     saved as it is).
--   RecipeBook.For(k, item) -> name or nil   a saved recipe that makes the
--     item (the first by name when several do)
--   RecipeBook.Declare(k) -> api   declares the module on kernel k
--     api.last()   the report of the last window read, nil before the first
--
-- This only reads the client. Not tested in game: the schematic read is a
-- first guess (Core/Client.lua).

local RecipeBook = ns.RecipeBook or {}
ns.RecipeBook = RecipeBook

RecipeBook.NAME = "recipeBook"
RecipeBook.EVENT = "TRADE_SKILL_LIST_UPDATE"
RecipeBook.PATH = "learned.facts.recipeBook"

local function whole(n, least)
    return type(n) == "number" and n == n and n < math.huge and n == math.floor(n) and n >= least
end

-- A saved or read entry as ItemPlan reads it, a copy; nil when it can't be
-- read: a product, a whole yield of at least 1 (1 when not given), and at
-- least one mat, each a whole item ID with a whole count of at least 1.
local function readEntry(e)
    if type(e) ~= "table" or not whole(e.makes, 1) then return nil end
    if e.yield ~= nil and not whole(e.yield, 1) then return nil end
    if type(e.mats) ~= "table" or next(e.mats) == nil then return nil end
    local mats = {}
    for item, n in pairs(e.mats) do
        if not whole(item, 1) or not whole(n, 1) then return nil end
        mats[item] = n
    end
    return { id = whole(e.id, 1) and e.id or nil, makes = e.makes, yield = e.yield or 1, mats = mats }
end

-- One read of the client; nil when it has no such read. An error is not
-- caught: the kernel counts it against the module.
local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

local function refuse(report, reason)
    report.ok, report.reason = false, reason
    return report
end

function RecipeBook.Read(client, store)
    local report = { saved = 0 }
    local r = ask(client, "recipes")
    if type(r) ~= "table" or type(r.recipes) ~= "table" then
        return refuse(report, "no profession window answered")
    end
    local profession = type(r.name) == "string" and r.name ~= "" and r.name or nil
    -- Every read comes before the write.
    local found, n = {}, 0
    for _, row in ipairs(r.recipes) do
        if type(row) == "table" and row.learned == true and type(row.name) == "string" and row.name ~= ""
            and whole(row.id, 1) then
            local e = readEntry(ask(client, "recipeSchematic", row.id))
            if e ~= nil then
                e.id, e.profession = row.id, profession
                if found[row.name] == nil then n = n + 1 end
                found[row.name] = e
            end
        end
    end
    if n == 0 then
        report.ok = true
        return report
    end
    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then
        return refuse(report, "the recipe book cannot be saved")
    end
    local cur = store:get("char", RecipeBook.PATH)
    if cur ~= nil and type(cur) ~= "table" then return refuse(report, "the recipe book cannot be saved") end
    local out = {}
    for key, value in pairs(cur or {}) do out[key] = value end
    for key, value in pairs(found) do out[key] = value end
    if store:set("char", RecipeBook.PATH, out) ~= true then
        return refuse(report, "the recipe book cannot be saved")
    end
    report.ok, report.saved = true, n
    return report
end

local function saved(k)
    if type(k) ~= "table" or type(k.store) ~= "table" or not k.store.opened then return nil end
    local raw = k.store:get("char", RecipeBook.PATH)
    return type(raw) == "table" and raw or nil
end

function RecipeBook.Recipes(k)
    local out = {}
    for name, e in pairs(saved(k) or {}) do
        if type(name) == "string" then
            local entry = readEntry(e)
            if entry ~= nil then out[name] = entry end
        end
    end
    return out
end

function RecipeBook.For(k, item)
    local key = ns.Items.Key(item)
    if key == nil then return nil end
    local names = {}
    for name, e in pairs(RecipeBook.Recipes(k)) do
        if ns.Items.Key(e.makes) == key then names[#names + 1] = name end
    end
    table.sort(names)
    return names[1]
end

-- Declares the module on kernel k. Usable at once: before the first event
-- last() is nil.
function RecipeBook.Declare(k)
    local api = {}
    local last
    function api.last() return last end
    k:Module({
        name = RecipeBook.NAME,
        needs = { "client", "store", "bus" },
        provides = { Last = api.last },
        start = function(ctx)
            ctx.bus:on(RecipeBook.NAME, RecipeBook.EVENT, function()
                last = RecipeBook.Read(ctx.client, ctx.store)
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.recipeBook = RecipeBook.Declare(ns)
