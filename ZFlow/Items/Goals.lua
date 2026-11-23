local _, ns = ...

-- ItemGoals: the player's goals list, the first producer of reservations.
-- A goal says "keep this many of this item for later" (or, with a recipe,
-- "keep the mats to make this many"); the bank list, the bank prompt and the
-- banker word then hold that count back, through Items/Reservations.lua.
--
--   <slash> goal add <item> <count>   set a goal (a link or an item ID); a
--                                     second add for the item changes its count
--   <slash> goal remove <item>        drop it
--   <slash> goal list                 the list (the bare word too)
--
-- Saved data: the character's settings.goals, a list of
--   { item = <item key>, count = <whole count >= 1>, recipe = <name>? }
-- written only by the goal word (and read by the source). Kept where the
-- never-sell list is kept (settings.sell.never, Items/Keep.lua): a plain
-- char path under the store's "settings" section, with no settings row, so
-- the settings page shows nothing for it and a reset of all settings does
-- not touch it.
--
--   ItemGoals.Claims(snapshot, goals, recipes) -> claims, skipped
--     pure. Per goal: with a recipe, ItemPlan.Build over the snapshot and
--     ItemPlan.Claims(plan, "goal:" .. item, "goal"); with none, the item
--     itself (kind "item", amount count, from the bags or the bank). Every
--     claim is marked selected: the player picked it. A goal that is not a
--     table, names no item, has no whole count of at least 1, or names a
--     recipe that recipes does not know (or ItemPlan can't plan) is skipped
--     and counted; a saved value that is no list counts as one.
--     recipes: { [name] = { makes, yield, mats } } as ItemPlan reads them.
--     Z-Flow holds no such data yet, so the source passes none and a goal
--     with a recipe is skipped until it does.
--   ItemGoals.Run(k, rest) -> lines, changed      the goal word
--   ItemGoals.Start(k, diag) -> { run = fn }      adds the word
--
-- Precedence is Resources.Resolve's, unchanged: never-sell, bank and carry
-- rules still win, and a goal protects only the count it reserves.
--
-- ADVICE DATA ONLY. Nothing here deposits, withdraws, moves, sells, buys or
-- uses anything; the source adds no event and no window. A change made with
-- the word calls Reservations.Changed, so an open sell list relists with it.
-- Not tested in game.

local Goals = {}
ns.ItemGoals = Goals

Goals.WORD = "goal"
Goals.PATH = "settings.goals"
Goals.SOURCE = "goals"
Goals.ACTIVITY = "goal"
Goals.OWNER = "goal:"

Goals.NOT_LOADED = ns.ItemPresent.KEEP_NOT_LOADED
Goals.FAILED = "That could not be saved, so nothing was changed."
do
    local cmd = tostring(ns.id.slash) .. " " .. Goals.WORD
    Goals.USAGE = "Say " .. cmd .. " add <item link> <count>, " .. cmd .. " remove <item link>, or "
        .. cmd .. " list."
    Goals.EMPTY = "You have no goals. Say " .. cmd .. " add <item link> <count> to keep that many for later."
end

local function isCount(n)
    return type(n) == "number" and n == n and n >= 1 and n < math.huge and n == math.floor(n)
end

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One goal's item key and count, or nil when it is malformed.
local function readGoal(g)
    if type(g) ~= "table" then return nil end
    local key = ns.Items.Key(g.item)
    if key == nil or not isCount(g.count) then return nil end
    if g.recipe ~= nil and (type(g.recipe) ~= "string" or g.recipe == "") then return nil end
    return key, g.count
end

function Goals.Claims(snapshot, goals, recipes)
    local claims, skipped = {}, 0
    if goals == nil then return claims, 0 end
    if type(goals) ~= "table" then return claims, 1 end
    for i = 1, #goals do
        local g = goals[i]
        local key, count = readGoal(g)
        if key == nil then
            skipped = skipped + 1
        elseif g.recipe == nil then
            claims[#claims + 1] = { owner = Goals.OWNER .. key, activity = Goals.ACTIVITY, kind = "item",
                                    key = key, amount = count, bank = true, selected = true }
        else
            local plan
            if type(recipes) == "table" and recipes[g.recipe] ~= nil then
                plan = ns.ItemPlan.Build({ recipe = g.recipe, count = count },
                    { recipes = recipes, snapshot = snapshot })
            end
            if type(plan) == "table" and plan.ok then
                for _, c in ipairs(ns.ItemPlan.Claims(plan, Goals.OWNER .. key, Goals.ACTIVITY)) do
                    c.selected = true
                    claims[#claims + 1] = c
                end
            else
                skipped = skipped + 1
            end
        end
    end
    return claims, skipped
end

-------------------------------------------------------------------------------
-- Saved data
-------------------------------------------------------------------------------

-- Is the character's saved data there? (saved() makes the table when it is
-- missing, so ask whether it exists, as Items/Keep.lua does.)
local function loaded(k)
    local c = k.client
    if type(c) ~= "table" then return false end
    if type(c.savedExists) == "function" then return c.savedExists(k.id.charDB) and true or false end
    return type(c.saved) == "function" and type(c.saved(k.id.charDB)) == "table"
end

local function savedGoals(k)
    if type(k.store) ~= "table" or not k.store.opened then return nil end
    return k.store:get("char", Goals.PATH)
end

-- The reservations source: the saved list over the evaluation's snapshot.
-- Idle while nothing is saved (or the store is not open yet), so a player
-- with no goal sees what they saw before goals existed, bags read or not.
-- Anything saved, even an entry that can't be read, makes it active.
ns.Reservations.Source(Goals.SOURCE, function(snapshot)
    return (Goals.Claims(snapshot, savedGoals(ns)))
end, function()
    local raw = savedGoals(ns)
    return raw ~= nil and not (type(raw) == "table" and #raw == 0)
end)

-------------------------------------------------------------------------------
-- The goal word
-------------------------------------------------------------------------------

local function nameOf(k, key)
    local client = k.client
    local names
    if type(client) == "table" and type(client.itemInfo) == "function" then
        names = function(item)
            local ok, info = pcall(client.itemInfo, ns.Items.Id(item) or item)
            if ok and type(info) == "table" then return info.name end
            return nil
        end
    end
    return ns.ItemPresent.Name(key, names)
end

-- The saved list as a fresh list of the goals that read, and how many did not.
local function copyOf(raw)
    local list, bad = {}, 0
    if raw == nil then return list, 0 end
    if type(raw) ~= "table" then return list, 1 end
    for i = 1, #raw do
        local g = raw[i]
        local key, count = readGoal(g)
        if key == nil then
            bad = bad + 1
        else
            list[#list + 1] = { item = key, count = count, recipe = g.recipe }
        end
    end
    return list, bad
end

-- The saved list to write back, and where the goal for key is in it (nil:
-- none). Entries that do not read are kept as they are, so a change made
-- with the word never loses what it can't read; they stay skipped.
local function rewrite(raw, key)
    local list, at = {}, nil
    if type(raw) ~= "table" then return list, nil end
    for i = 1, #raw do
        local g = raw[i]
        local k2, count = readGoal(g)
        if k2 == nil then
            list[#list + 1] = g
        else
            list[#list + 1] = { item = k2, count = count, recipe = g.recipe }
            if k2 == key and at == nil then at = #list end
        end
    end
    return list, at
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

local function listLines(k, raw)
    local list, bad = copyOf(raw)
    if #list == 0 and bad == 0 then return { Goals.EMPTY } end
    local rows = {}
    for _, g in ipairs(list) do
        local text = g.count .. " x " .. nameOf(k, g.item)
        if g.recipe then text = text .. " (to make, recipe " .. g.recipe .. ")" end
        rows[#rows + 1] = text
    end
    local lines = { "Your goals (" .. #list .. "):" }
    for i = 1, #rows do lines[#lines + 1] = rows[i] end
    if bad > 0 then
        lines[#lines + 1] = plural(bad, "saved goal", "saved goals")
            .. (bad == 1 and " could not be read and is skipped." or " could not be read and are skipped.")
    end
    return lines
end

-- The words after "add": an item (a link or an ID, maybe with spaces in a
-- link's name) and, last, a whole count.
local function parseAdd(rest)
    local what, n = rest:match("^(.-)%s+(%S+)$")
    if not what then return nil end
    local count = tonumber(n)
    if not isCount(count) then return nil end
    local key = ns.Items.Key(trim(what))
    if key == nil then return nil end
    return key, count
end

local function save(k, list)
    local ok, reason = k.store:set("char", Goals.PATH, list)
    if not ok then
        -- The store's reason names internal paths: kept for diagnostics.
        if type(k.problems) == "table" then k.problems:add("goals", "save", tostring(reason)) end
        return false
    end
    return true
end

function Goals.Run(k, rest)
    rest = trim(rest)
    if not loaded(k) or type(k.store) ~= "table" or not k.store.opened then return { Goals.NOT_LOADED }, false end
    local raw = savedGoals(k)
    local word, more = rest:match("^(%S*)%s*(.*)$")

    if word == "" or word == "list" then
        if more ~= "" then return { Goals.USAGE }, false end
        return listLines(k, raw), false
    end

    if word == "add" then
        local key, count = parseAdd(more)
        if key == nil then return { Goals.USAGE }, false end
        local list, at = rewrite(raw, key)
        if at then list[at] = { item = key, count = count, recipe = list[at].recipe }
        else list[#list + 1] = { item = key, count = count } end
        if not save(k, list) then return { Goals.FAILED }, false end
        return { "Goal set: keep " .. count .. " x " .. nameOf(k, key) .. "." }, true
    end

    if word == "remove" then
        local key = ns.Items.Key(trim(more))
        if key == nil then return { Goals.USAGE }, false end
        local list, at = rewrite(raw, key)
        if not at then return { nameOf(k, key) .. " is not one of your goals." }, false end
        table.remove(list, at)
        if not save(k, list) then return { Goals.FAILED }, false end
        return { nameOf(k, key) .. " is off your goals." }, true
    end

    return { Goals.USAGE }, false
end

function Goals.Start(k, diag)
    local function run(rest)
        local lines, changed = Goals.Run(k, rest)
        for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
        if changed then ns.Reservations.Changed(k) end
        return changed
    end
    if diag and type(diag.commands) == "table" then
        diag.commands[Goals.WORD] = run
    end
    return { run = run }
end

-- The addon's own: the word is added when this file loads.
ns.itemGoals = Goals.Start(ns, ns.diag)
