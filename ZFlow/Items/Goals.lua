local _, ns = ...

-- ItemGoals: the player's goals list, the first producer of reservations.
-- A goal says "keep this many of this item for later" (or, with a recipe,
-- "make this many": keep what is owned of it and the mats for the rest); the
-- bank list, the bank prompt and the banker word then hold that back,
-- through Items/Reservations.lua.
--
--   <slash> goal add <item> <count>   set a goal: one item link or an item
--                                     ID, a count of 1 to MAX_COUNT in digits;
--                                     a second add for the item changes its
--                                     count (and drops a second saved entry)
--   <slash> goal make <item> <count>  as add, with the recipe the recipe
--                                     book (Items/RecipeBook.lua) knows for
--                                     the item; none known: nothing is
--                                     saved and the player is told to open
--                                     the profession window that makes it
--   <slash> goal remove <item>        drop it (every saved entry for it)
--   <slash> goal list                 the list (the bare word too)
--   <slash> goal clean                remove the saved entries that can't be
--                                     read; the goals that read are kept
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
--     pure. Per goal: with a recipe that recipes knows, what is owned of
--     the item (bags, and the bank once seen) is held first, up to the
--     count, and for the rest ItemPlan.Build over the snapshot and
--     ItemPlan.Claims(plan, "goal:" .. item, "goal"). When ItemPlan can't
--     plan it, or with no recipe known, the item itself (kind "item",
--     amount count, from the bags or the bank). Every claim is marked
--     selected: the player picked it. A goal that is not a table, names no
--     item, or has no whole count of at least 1 is skipped and counted; a
--     saved value that is no list counts as one, and so does each entry
--     outside 1..#goals (after a hole, or under a name).
--     recipes: { [name] = { makes, yield, mats } } as ItemPlan reads them.
--     Section 225 (GS-2): a recipe part never makes a goal skipped.
--     Section 227 (P-GOALS-RECIPE): the source passes the recipe book; a
--     recipe it has not seen holds the item and count, as a goal with none
--     does, and the list says the recipe is not seen yet (NOT_SEEN).
--   ItemGoals.Crafts(k, snapshot) -> rows   the recipe goals, in order, for
--     the list and for P-CRAFT. snapshot: nil for the reservations' own.
--     nil while the goals can't be read (store not open, a saved value that
--     is no list); {} with none. Each row:
--       { item, count, recipe, known (the book has it), recipeId, makes,
--         have (owned), times (crafts of it still to do), ready (ItemPlan's),
--         missing = { { key, count } } (still to get, not crafted),
--         bankUnseen (some may be in the bank), bagsUnread }
--   ItemGoals.NoRecipe(name) -> line   make, for an item no recipe makes
--   ItemGoals.NotRead(name) -> line    make, when the last profession window
--                                      was open but none of its recipes
--                                      could be read (section 233, GR2-1)
--   ItemGoals.Unread(n) -> line   what the word says while n saved entries
--                                 can't be read (section 225, GS-3)
--   ItemGoals.Run(k, rest) -> lines, changed      the goal word
--   ItemGoals.Start(k, diag) -> { run = fn }      adds the word
--
-- Precedence is Resources.Resolve's, unchanged: never-sell, bank and carry
-- rules still win, and a goal protects only the count it reserves.
--
-- ADVICE DATA ONLY. Nothing here deposits, withdraws, moves, sells, buys or
-- uses anything; the source adds no event and no window. A change made with
-- the word calls Reservations.Changed, so an open sell or bank list relists
-- with it.
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
Goals.MAX_COUNT = 100000      -- the most a goal keeps (section 223, G-6)
Goals.RECIPE_MAX = 40         -- the most of a recipe part the list shows (G-8)
do
    local cmd = tostring(ns.id.slash) .. " " .. Goals.WORD
    Goals.CLEAN = cmd .. " clean"
    Goals.USAGE = "Say " .. cmd .. " add <item link> <count>, " .. cmd .. " make <item link> <count>, "
        .. cmd .. " remove <item link>, " .. cmd .. " list, or " .. Goals.CLEAN .. "."
    -- Section 227: a goal whose recipe the book has not seen.
    Goals.NOT_SEEN = "recipe not seen yet, so the goal keeps the item itself. Open the profession window"
        .. " that makes it."
    -- Section 227: make, for an item no recipe in the book makes.
    function Goals.NoRecipe(name)
        return "No recipe you have seen makes " .. tostring(name) .. ". Open the profession window that makes"
            .. " it, then say " .. cmd .. " make again."
    end
    -- Section 233 (GR2-1): make, when the window was seen but not read.
    function Goals.NotRead(name)
        return "Your profession window was open, but " .. tostring(ns.id.title) .. " could not read its recipes, so none that makes "
            .. tostring(name) .. " is saved."
    end
    Goals.EMPTY = "You have no goals. Say " .. cmd .. " add <item link> <count> to keep that many for later."
    Goals.UNREADABLE = "Your saved goals can't be read, so nothing was changed. Say " .. Goals.CLEAN
        .. " to clear them."
    Goals.CLEAN_NONE = "Every saved goal can be read, so nothing was removed."
    Goals.CLEAN_ORDER = "Every saved goal can be read now; they are back in one list."
end

-- Section 225 (GS-3): while a saved entry can't be read the source gives no
-- list, so no sell advice rests on the goals. The player is told so, and how
-- to clear it, whenever the word sees one.
function Goals.Unread(n)
    local one = n == 1
    return n .. (one and " saved goal" or " saved goals") .. " could not be read. While "
        .. (one and "it is" or "they are") .. " saved, " .. tostring(ns.id.title) .. " can't say what your goals keep, so it gives"
        .. " no sell advice. Say " .. Goals.CLEAN .. " to remove " .. (one and "it" or "them") .. "."
end

local function isCount(n)
    return type(n) == "number" and n == n and n >= 1 and n < math.huge and n == math.floor(n)
end

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One goal's item key and count, or nil when it is malformed. The recipe
-- part is not read here (section 225, GS-2): it never makes a goal skipped.
local function readGoal(g)
    if type(g) ~= "table" then return nil end
    local key = ns.Items.Key(g.item)
    if key == nil or not isCount(g.count) then return nil end
    return key, g.count
end

-- What the snapshot says is owned of key: the bags, and the bank once it was
-- seen. nil when the bags were not read.
local function owned(snapshot, key)
    if type(snapshot) ~= "table" or type(snapshot.bags) ~= "table" then return nil end
    local n = tonumber(snapshot.bags[key]) or 0
    if snapshot.bankKnown and type(snapshot.bank) == "table" then n = n + (tonumber(snapshot.bank[key]) or 0) end
    return n
end

function Goals.Claims(snapshot, goals, recipes)
    local claims, skipped = {}, 0
    if goals == nil then return claims, 0 end
    if type(goals) ~= "table" then return claims, 1 end
    local n = #goals
    for i = 1, n do
        local g = goals[i]
        local key, count = readGoal(g)
        if key == nil then
            skipped = skipped + 1
        else
            -- Section 227: what is owned of the item is held first; the
            -- mats are planned for the rest only. Bags unread: nothing is
            -- known to be owned, so the plan is for the whole count.
            local plan, held
            if type(g.recipe) == "string" and type(recipes) == "table" and recipes[g.recipe] ~= nil then
                held = math.min(owned(snapshot, key) or 0, count)
                if held < count then
                    plan = ns.ItemPlan.Build({ recipe = g.recipe, count = count - held },
                        { recipes = recipes, snapshot = snapshot })
                end
            end
            if held ~= nil and (held == count or (type(plan) == "table" and plan.ok)) then
                if held > 0 then
                    claims[#claims + 1] = { owner = Goals.OWNER .. key, activity = Goals.ACTIVITY, kind = "item",
                                            key = key, amount = held, bank = true, selected = true }
                end
                if plan ~= nil then
                    for _, c in ipairs(ns.ItemPlan.Claims(plan, Goals.OWNER .. key, Goals.ACTIVITY)) do
                        c.selected = true
                        claims[#claims + 1] = c
                    end
                end
            else
                claims[#claims + 1] = { owner = Goals.OWNER .. key, activity = Goals.ACTIVITY, kind = "item",
                                        key = key, amount = count, bank = true, selected = true }
            end
        end
    end
    -- Section 220 (G-2): what the list holds past a hole or under a name is
    -- not read by the loop above; it is counted, not dropped.
    for i in pairs(goals) do
        if not (type(i) == "number" and i >= 1 and i <= n and i == math.floor(i)) then skipped = skipped + 1 end
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

local function storeOpen(k)
    return type(k) == "table" and type(k.store) == "table" and k.store.opened and true or false
end

local function savedGoals(k)
    if not storeOpen(k) then return nil end
    return k.store:get("char", Goals.PATH)
end

-- The reservations source: the saved list of the evaluating kernel (k; nil:
-- the add-on's own) over the evaluation's snapshot. Idle only when the store
-- is open and nothing is saved (nil, or a table with nothing in it), so a
-- player with no goal sees what they saw before goals existed, bags read or
-- not. Anything saved, even an entry that can't be read, makes it active.
-- Section 220:
--   G-1  the store not open: the saved goals can't be read, so the source is
--        active and gives no list. The status is "unavailable", never "none".
--   G-2  "nothing in it" is next(raw) == nil: a list with a hole at 1 or only
--        named entries is not taken for no goals.
--   G-3  a skipped goal (one that can't be read) may hold an item the
--        player wants kept, so any skipped goal gives no list either:
--        "unavailable", and no sell advice rests on it. The word says so
--        and how to clear it (section 225, GS-1 and GS-3: goal clean).
ns.Reservations.Source(Goals.SOURCE, function(snapshot, k)
    k = k or ns
    if not storeOpen(k) then return nil end
    local claims, skipped = Goals.Claims(snapshot, savedGoals(k), ns.RecipeBook.Recipes(k))
    if skipped > 0 then return nil end
    return claims
end, function(k)
    k = k or ns
    if not storeOpen(k) then return true end
    local raw = savedGoals(k)
    return raw ~= nil and not (type(raw) == "table" and next(raw) == nil)
end)

-------------------------------------------------------------------------------
-- Section 227: what each recipe goal still needs
-------------------------------------------------------------------------------

-- The reservations' own snapshot, or nil when it can't be had.
local function currentSnapshot(k)
    local r = type(k) == "table" and k.reservations or nil
    if type(r) ~= "table" or type(r.Current) ~= "function" then return nil end
    local ok, cur = pcall(r.Current)
    if ok and type(cur) == "table" and type(cur.snapshot) == "table" then return cur.snapshot end
    return nil
end

local function craftRow(key, count, recipe, recipes, snapshot)
    local row = { item = key, count = count, recipe = recipe, known = false }
    local r = type(recipe) == "string" and recipes[recipe] or nil
    if r == nil then return row end
    row.known, row.recipeId, row.makes = true, r.id, r.makes
    local have = owned(snapshot, key)
    if have == nil then
        row.bagsUnread, row.ready = true, "unknown"
        return row
    end
    row.have = have
    local rest = count - math.min(have, count)
    if rest == 0 then
        row.times, row.ready, row.missing = 0, true, {}
        return row
    end
    local plan = ns.ItemPlan.Build({ recipe = recipe, count = rest }, { recipes = recipes, snapshot = snapshot })
    if type(plan) ~= "table" or not plan.ok then
        row.ready = false
        return row
    end
    -- Inner crafts come first: the goal's own craft is the last of its recipe.
    for _, c in ipairs(plan.crafts or {}) do
        if c.recipe == recipe then row.times = c.times end
    end
    row.ready, row.missing = plan.ready, {}
    for _, pr in ipairs(plan.rows or {}) do
        local short = tonumber(pr.missing) or 0
        for _, s in ipairs(pr.sources or {}) do
            if s.from == "craft" then short = short - (tonumber(s.count) or 0) end
        end
        if short > 0 then
            row.missing[#row.missing + 1] = { key = pr.key, count = short }
            if pr.bankUnseen then row.bankUnseen = true end
        end
    end
    return row
end

function Goals.Crafts(k, snapshot)
    if not storeOpen(k) then return nil end
    local raw = savedGoals(k)
    if raw == nil then return {} end
    if type(raw) ~= "table" then return nil end
    local recipes, rows = ns.RecipeBook.Recipes(k), {}
    for i = 1, #raw do
        local g = raw[i]
        local key, count = readGoal(g)
        if key ~= nil and g.recipe ~= nil then
            if snapshot == nil then snapshot = currentSnapshot(k) end
            rows[#rows + 1] = craftRow(key, count, g.recipe, recipes, snapshot)
        end
    end
    return rows
end

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

-- Section 223 (G-4): every entry of the saved list (a table), in order, and
-- what it holds under any other key. Entries 1..#raw come first, then each
-- whole-number key past them (after a hole) in order, so nothing is lost and
-- the list written back has no hole. Anything under another key (a name, 0,
-- a fraction) is returned apart, to be written back under that key.
local function entries(raw)
    local seq, other, later, n = {}, {}, {}, #raw
    for i = 1, n do
        if raw[i] ~= nil then seq[#seq + 1] = raw[i] end
    end
    for key, value in pairs(raw) do
        local whole = type(key) == "number" and key < math.huge and key == math.floor(key)
        if whole and key > n then
            later[#later + 1] = key
        elseif not (whole and key >= 1 and key <= n) then
            other[key] = value
        end
    end
    table.sort(later)
    for _, key in ipairs(later) do seq[#seq + 1] = raw[key] end
    return seq, other
end

local function withOthers(list, other)
    for key, value in pairs(other) do list[key] = value end
    return list
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- How many saved entries the source would skip: the count Claims gives.
local function unread(raw)
    local _, skipped = Goals.Claims(nil, raw)
    return skipped
end

-- A reply, with the unread line after it when the list written still holds
-- an entry that can't be read (section 225, GS-3).
local function withUnread(lines, list)
    local bad = unread(list)
    if bad > 0 then lines[#lines + 1] = Goals.Unread(bad) end
    return lines
end

-- Section 223 (G-8): a recipe part as the list shows it. No control
-- characters, at most RECIPE_MAX bytes (a cut never leaves half a
-- character), and each "|" doubled so chat shows it and it starts no link
-- or colour.
local function shown(text)
    text = tostring(text):gsub("%c", "")
    if #text > Goals.RECIPE_MAX then
        text = text:sub(1, Goals.RECIPE_MAX):gsub("[\192-\255][\128-\191]*$", "") .. "..."
    end
    return (text:gsub("|", "||"))
end

-- Section 227: what a recipe goal's list line says after its recipe.
local function craftStatus(k, row)
    if not row.known then return Goals.NOT_SEEN end
    if row.bagsUnread then return "can't say what is missing: the bags were not read" end
    if row.have >= row.count then return "you have all " .. row.count end
    local text = row.have > 0 and ("you have " .. row.have .. "; ") or ""
    if row.missing == nil then return text .. "can't say what is missing: the recipe can't be planned" end
    if #row.missing == 0 then return text .. "ready to make " .. (row.count - row.have) end
    local parts = {}
    for _, m in ipairs(row.missing) do parts[#parts + 1] = m.count .. " x " .. nameOf(k, m.key) end
    text = text .. "missing " .. table.concat(parts, ", ")
    if row.bankUnseen then text = text .. " (the bank was not seen; some may be there)" end
    return text
end

local function listLines(k, raw)
    local rows = {}
    if type(raw) == "table" then
        local recipes, snapshot, read
        for i = 1, #raw do
            local g = raw[i]
            local key, count = readGoal(g)
            if key ~= nil then
                local text = count .. " x " .. nameOf(k, key)
                if g.recipe ~= nil then
                    if not read then recipes, snapshot, read = ns.RecipeBook.Recipes(k), currentSnapshot(k), true end
                    text = text .. ", made by " .. shown(g.recipe) .. ": "
                        .. craftStatus(k, craftRow(key, count, g.recipe, recipes, snapshot))
                end
                rows[#rows + 1] = text
            end
        end
    end
    local bad = unread(raw)
    if #rows == 0 and bad == 0 then return { Goals.EMPTY } end
    local lines = { "Your goals (" .. #rows .. "):" }
    for i = 1, #rows do lines[#lines + 1] = rows[i] end
    if bad > 0 then lines[#lines + 1] = Goals.Unread(bad) end
    return lines
end

-- Section 223 (G-7): an item as the word takes it: an item ID (digits only)
-- or exactly one item link with nothing after it. Words around a link, a
-- second link, and an "id:suffix" or "item:" string typed by hand are
-- refused. The slash command hands a link over lower-cased, so the escape
-- letters are matched in either case.
local function parseItem(text)
    text = trim(text)
    if text:match("^%d+$") then return ns.Items.Key(text) end
    local body = text:gsub("^|[cC]%x%x%x%x%x%x%x%x", "", 1)
    local item, after = body:match("^|[hH](item:[%-%d:]+)|[hH]%[.-%]|[hH](.*)$")
    if item == nil then return nil end
    if after ~= "" and not after:match("^|[rR]$") then return nil end
    return ns.Items.Key(item)
end

-- The words after "add": an item (one link or an ID; a link's name may
-- hold spaces) and, last, a count. Section 223 (G-6): the count is digits
-- only, 1 to MAX_COUNT, so "0x10", "1e3" or "+8" is refused.
local function parseAdd(rest)
    local what, n = rest:match("^(.-)%s+(%S+)$")
    if not what then return nil end
    if not n:match("^%d+$") or #n > #tostring(Goals.MAX_COUNT) then return nil end
    local count = tonumber(n)
    if not isCount(count) or count > Goals.MAX_COUNT then return nil end
    local key = parseItem(what)
    if key == nil then return nil end
    return key, count
end

local function save(k, list)
    local ok, reason = k.store:set("char", Goals.PATH, list)
    if not ok then
        -- The store's reason names internal paths: kept for diagnostics
        -- only, never printed (section 223, G-8). Its reasons name a scope,
        -- a path or a schema number, not the character; a migration step's
        -- own error text is passed through as it is.
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

    -- Section 223 (G-4): a saved value that is no list is not written over;
    -- the player is told to clear it. Each saved entry is written back as it
    -- is (G-4 iii); only the changed goal is copied, with its new count.
    -- (G-5) add sets the first entry for the item and drops later ones;
    -- remove drops every one.
    -- Section 227: make is add with the recipe the book knows for the item.
    if word == "add" or word == "make" then
        local key, count = parseAdd(more)
        if key == nil then return { Goals.USAGE }, false end
        if raw ~= nil and type(raw) ~= "table" then return { Goals.UNREADABLE }, false end
        local recipe
        if word == "make" then
            recipe = ns.RecipeBook.For(k, key)
            if recipe == nil then
                local rb = type(k) == "table" and k.recipeBook or nil
                local last = type(rb) == "table" and type(rb.last) == "function" and rb.last() or nil
                if type(last) == "table" and last.reason == ns.RecipeBook.UNREAD then
                    return { Goals.NotRead(nameOf(k, key)) }, false
                end
                return { Goals.NoRecipe(nameOf(k, key)) }, false
            end
        end
        local seq, other = entries(raw or {})
        local list, set = {}, false
        for _, g in ipairs(seq) do
            if readGoal(g) == key then
                if not set then
                    local copy = {}
                    for field, value in pairs(g) do copy[field] = value end
                    copy.count = count
                    -- Section 233 (GR2-2): add keeps the item, not a recipe.
                    copy.recipe = recipe
                    list[#list + 1] = copy
                    set = true
                end
            else
                list[#list + 1] = g
            end
        end
        if not set then list[#list + 1] = { item = key, count = count, recipe = recipe } end
        list = withOthers(list, other)
        if not save(k, list) then return { Goals.FAILED }, false end
        local said
        if recipe ~= nil then
            said = "Goal set: make " .. count .. " x " .. nameOf(k, key) .. " (recipe: " .. shown(recipe) .. ")."
        else
            said = "Goal set: keep " .. count .. " x " .. nameOf(k, key) .. "."
        end
        return withUnread({ said }, list), true
    end

    if word == "remove" then
        local key = parseItem(more)
        if key == nil then return { Goals.USAGE }, false end
        if raw ~= nil and type(raw) ~= "table" then return { Goals.UNREADABLE }, false end
        local seq, other = entries(raw or {})
        local list, found = {}, false
        for _, g in ipairs(seq) do
            if readGoal(g) == key then found = true else list[#list + 1] = g end
        end
        if not found then return { nameOf(k, key) .. " is not one of your goals." }, false end
        list = withOthers(list, other)
        if not save(k, list) then return { Goals.FAILED }, false end
        return withUnread({ nameOf(k, key) .. " is off your goals." }, list), true
    end

    -- Section 225 (GS-1): remove what the source can't read (an entry that
    -- is no goal, one under a name, a saved value that is no list) and keep
    -- every goal that reads, in order. An entry past a hole that reads is
    -- kept and put back in the list.
    if word == "clean" then
        if more ~= "" then return { Goals.USAGE }, false end
        if unread(raw) == 0 then return { Goals.CLEAN_NONE }, false end
        local list, removed = {}, 1
        if type(raw) == "table" then
            removed = 0
            local seq, other = entries(raw)
            for _, g in ipairs(seq) do
                if readGoal(g) ~= nil then list[#list + 1] = g else removed = removed + 1 end
            end
            for _ in pairs(other) do removed = removed + 1 end
        end
        if not save(k, list) then return { Goals.FAILED }, false end
        if removed == 0 then return { Goals.CLEAN_ORDER }, true end
        return { "Removed " .. plural(removed, "saved goal", "saved goals")
            .. " that could not be read. Your other goals are kept." }, true
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
        if type(diag.help) == "table" then diag.help[Goals.WORD] = "your goals: goal add|make <item> <count>, goal remove <item>, goal list, goal clean" end
    end
    return { run = run }
end

-- The addon's own: the word is added when this file loads.
ns.itemGoals = Goals.Start(ns, ns.diag)
