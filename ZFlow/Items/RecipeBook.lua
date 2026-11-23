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
-- Section 233 (GR2-1): when that read gives no answer, or no recipe in it
-- can be read, the classic window is walked row by row
-- (client.tradeSkillRows(), client.tradeSkillSchematic(index)); an entry
-- from there has no id. A window that answered with learned recipes, none
-- of which could be read, is reported as RecipeBook.UNREAD, not as no window.
-- Entries already saved (another profession's) are kept; one with the same
-- name is replaced. Section 233 (GR2-3): two recipes of one name in one
-- read are both saved: the first (by id, then as read) under the name, each
-- other under "name (id)", or "name (n)" without an id; report.collided
-- counts them. When every learned recipe of a named profession was read,
-- a saved entry of that profession not in the read is no longer learned and
-- is dropped. Section 233 (GR2-4): a read that changes nothing writes
-- nothing (report.unchanged). Nothing to save, or no answer: nothing is
-- written.
--
--   RecipeBook.Read(client, store) -> report   one profession window read
--     report = { ok, reason (when not ok), saved = entries written,
--                collided = n (when names were shared), unchanged = true }
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

-- Section 233 (GR2-1): the reason when a window answered with learned
-- recipes but none of them could be read. Goals says so on make.
RecipeBook.UNREAD = "the profession window was open, but none of its recipes could be read"

local function named(v)
    return type(v) == "string" and v ~= "" and v or nil
end

-- One window read: { profession, rows = learned rows met, list = { { name,
-- entry, at } } }, or nil when that read did not answer. Every read comes
-- before the write.
local function readModern(client)
    local r = ask(client, "recipes")
    if type(r) ~= "table" or type(r.recipes) ~= "table" then return nil end
    local got = { profession = named(r.name), rows = 0, list = {} }
    for _, row in ipairs(r.recipes) do
        if type(row) == "table" and row.learned == true and named(row.name) and whole(row.id, 1) then
            got.rows = got.rows + 1
            local e = readEntry(ask(client, "recipeSchematic", row.id))
            if e ~= nil then
                e.id, e.profession = row.id, got.profession
                got.list[#got.list + 1] = { name = row.name, entry = e, at = #got.list + 1 }
            end
        end
    end
    return got
end

-- Section 233 (GR2-1): the classic window, row by row. Every row it gives is
-- a learned recipe; no recipe id is read, so an entry from here has none.
local function readClassic(client)
    local r = ask(client, "tradeSkillRows")
    if type(r) ~= "table" or type(r.rows) ~= "table" then return nil end
    local got = { profession = named(r.name), rows = 0, list = {} }
    for _, row in ipairs(r.rows) do
        if type(row) == "table" and named(row.name) and whole(row.index, 1) then
            got.rows = got.rows + 1
            local e = readEntry(ask(client, "tradeSkillSchematic", row.index))
            if e ~= nil then
                e.id, e.profession = nil, got.profession
                got.list[#got.list + 1] = { name = row.name, entry = e, at = #got.list + 1 }
            end
        end
    end
    return got
end

-- Section 233 (GR2-3): the names to save under. Two recipes of one name are
-- not written over each other: the first by id (then as read) keeps the
-- name, each other gets "name (id)", or "name (n)" without an id.
local function keyed(list, report)
    local byName, order = {}, {}
    for _, it in ipairs(list) do
        if byName[it.name] == nil then
            byName[it.name] = {}
            order[#order + 1] = it.name
        end
        local same = byName[it.name]
        same[#same + 1] = it
    end
    local out = {}
    for _, name in ipairs(order) do
        local same = byName[name]
        if #same > 1 then
            table.sort(same, function(a, b)
                local ia, ib = a.entry.id or math.huge, b.entry.id or math.huge
                if ia ~= ib then return ia < ib end
                return a.at < b.at
            end)
            report.collided = (report.collided or 0) + #same - 1
        end
        for i, it in ipairs(same) do
            local key = name
            if i > 1 then key = name .. " (" .. tostring(it.entry.id or i) .. ")" end
            out[key] = it.entry
        end
    end
    return out
end

-- Section 233 (GR2-4): two saved values the same, all the way down.
local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, v in pairs(a) do
        if not same(v, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

function RecipeBook.Read(client, store)
    local report = { saved = 0 }
    local got = readModern(client)
    if got == nil or #got.list == 0 then
        local classic = readClassic(client)
        if classic ~= nil and (got == nil or #classic.list > 0) then got = classic end
    end
    if got == nil then return refuse(report, "no profession window answered") end
    if #got.list == 0 then
        if got.rows > 0 then return refuse(report, RecipeBook.UNREAD) end
        report.ok = true
        return report
    end
    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then
        return refuse(report, "the recipe book cannot be saved")
    end
    local cur = store:get("char", RecipeBook.PATH)
    if cur ~= nil and type(cur) ~= "table" then return refuse(report, "the recipe book cannot be saved") end
    local found = keyed(got.list, report)
    -- GR2-3: every learned recipe of a named profession read: what is saved
    -- of that profession and not in this read is no longer learned.
    local complete = got.profession ~= nil and got.rows == #got.list
    local out = {}
    for key, value in pairs(cur or {}) do
        local gone = complete and type(value) == "table" and value.profession == got.profession
        if not gone then out[key] = value end
    end
    local n = 0
    for key, value in pairs(found) do
        out[key] = value
        n = n + 1
    end
    if same(out, cur or {}) then
        report.ok, report.unchanged = true, true
        return report
    end
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
