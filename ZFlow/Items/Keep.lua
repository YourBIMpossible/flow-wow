local _, ns = ...

-- ItemKeep (L6-G, G3): the never-sell list from the chat line.
--
--   <slash> keep                  the list
--   <slash> keep <item>           put an item on it (a link, or an item ID)
--   <slash> keep remove <item>    take it off
--
-- It writes only Z-Flow's own saved data: the character's
-- settings.sell.never, { [item key] = true }, the list Disposition's
-- "neverSell" rule and the sell list already read. Nothing in the game is
-- touched: nothing is sold, bought back, moved or clicked.
--
--   ItemKeep.Run(k, rest) -> lines, changed
--     rest     what follows the word (the slash command lower-cases it; an
--              item link still reads, its "item:..." part is all that is used)
--     lines    what to say, without the title
--     changed  true only when the list was written
--   ItemKeep.Start(k, diag, sellList) -> { run = fn }
--     adds the word to diag.commands; after a change, sellList.refresh()
--     (UI/SellList.lua) so an open sell list shows it at once.
--
-- Names come from client.itemInfo (CLIENT NEED, as the sell list) through
-- ItemPresent.Name: an item whose name is not read is "item <key>".

local Keep = {}
ns.ItemKeep = Keep

Keep.WORD = "keep"
Keep.PATH = "settings.sell.never"
-- The words are ItemPresent's (the Items text path); these are their names here.
Keep.NOT_LOADED = ns.ItemPresent.KEEP_NOT_LOADED
Keep.EMPTY = ns.ItemPresent.KEEP_EMPTY
Keep.ONE_AT_A_TIME = ns.ItemPresent.KEEP_ONE_AT_A_TIME
Keep.USAGE = ns.ItemPresent.KeepUsage(ns.id.slash)

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function nameOf(k, key)
    local client = k.client
    -- Coloured by the item's quality (ItemPresent.Tint).
    return ns.ItemPresent.Name(key, ns.ItemPresent.Names(type(client) == "table" and client.itemInfo or nil))
end

-- The saved list, with every entry under its item key. nil when the
-- character's saved data is not there.
local function listOf(k)
    -- saved() makes the table when it is missing, so ask whether it exists
    -- (lead, L6-G merge: the check never failed before).
    local c = k.client
    if type(c.savedExists) == "function" then
        if not c.savedExists(k.id.charDB) then return nil end
    elseif type(c.saved(k.id.charDB)) ~= "table" then
        return nil
    end
    -- Read as the sell list reads it (a set or a list), so what is written
    -- back never loses an entry saved in the other shape.
    local never = ns.SellList.Choices(k.store).never
    local out = {}
    for key in pairs(never) do out[key] = true end
    return out
end

-- How many items a line names: each "item:<n>" in it, or one for a bare ID.
local function itemsIn(text)
    local n = 0
    for _ in tostring(text):gmatch("item:%d+") do n = n + 1 end
    if n == 0 and tostring(text):match("^%d+$") then n = 1 end
    return n
end

function Keep.Run(k, rest)
    rest = trim(rest)
    local list = listOf(k)
    if not list then return { Keep.NOT_LOADED }, false end

    if rest == "" then
        local names = {}
        for key in pairs(list) do names[#names + 1] = nameOf(k, key) end
        if #names == 0 then return { Keep.EMPTY }, false end
        table.sort(names, function(a, b)
            return ns.ItemPresent.Plain(a) < ns.ItemPresent.Plain(b)
        end)
        local lines = { ns.ItemPresent.KeepText("header", #names) }
        for i = 1, #names do lines[#lines + 1] = names[i] end
        return lines, false
    end

    local remove = false
    local what = rest
    local word, more = rest:match("^(%S+)%s*(.*)$")
    if word == "remove" then remove, what = true, trim(more) end
    if itemsIn(what) > 1 then return { Keep.ONE_AT_A_TIME }, false end
    local key = ns.Items.Key(what)
    if key == nil then return { Keep.USAGE }, false end
    local name = nameOf(k, key)

    local say = ns.ItemPresent.KeepText
    if remove then
        if not list[key] then return { say("absent", name) }, false end
        list[key] = nil
    else
        if list[key] then return { say("already", name) }, false end
        list[key] = true
    end
    local ok, reason = k.store:set("char", Keep.PATH, list)
    if not ok then
        -- The store's own reason names internal paths: kept as a problem
        -- for diagnostics, and the player is told only what it means.
        if type(k.problems) == "table" then k.problems:add("keep", "save", tostring(reason)) end
        return { say("failed") }, false
    end
    return { say(remove and "removed" or "added", name) }, true
end

-- E-13 (lead section 660; Flow Modules/Items/Vendor.lua:718-720): an item
-- the player bought back goes on the never-sell list, so it is not sold
-- again. Silent when it is already there, names no item, or the saved data
-- is not loaded. -> lines, changed (as Run).
function Keep.BoughtBack(k, item)
    local key = item ~= nil and ns.Items.Key(tostring(item)) or nil
    if key == nil then return {}, false end
    local list = listOf(k)
    if not list or list[key] then return {}, false end
    list[key] = true
    local ok, reason = k.store:set("char", Keep.PATH, list)
    if not ok then
        if type(k.problems) == "table" then k.problems:add("keep", "boughtBack", tostring(reason)) end
        return {}, false
    end
    return { ns.ItemPresent.KeepText("boughtBack", nameOf(k, key)) }, true
end

function Keep.Start(k, diag, sellList)
    local function run(rest)
        local lines, changed = Keep.Run(k, rest)
        for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
        if changed and type(sellList) == "table" and type(sellList.refresh) == "function" then
            sellList.refresh()
        end
        return changed
    end
    -- The buy-back read is client.onBoughtBack (CLIENT NEED); without it
    -- the list is only the word's.
    local c = k.client
    if type(c) == "table" and type(c.onBoughtBack) == "function" then
        pcall(c.onBoughtBack, function(item)
            local lines, changed = Keep.BoughtBack(k, item)
            for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
            if changed and type(sellList) == "table" and type(sellList.refresh) == "function" then
                sellList.refresh()
            end
        end)
    end
    if diag and type(diag.commands) == "table" then
        diag.commands[Keep.WORD] = run
        if type(diag.help) == "table" then diag.help[Keep.WORD] = "the never-sell list: keep <item> adds, keep remove <item> takes off" end
    end
    return { run = run }
end

-- The addon's own: the word is added when this file loads.
ns.itemKeep = Keep.Start(ns, ns.diag, ns.sellList)
