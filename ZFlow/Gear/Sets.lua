local _, ns = ...

-- GearSets (package P-SETS, branch 1): named sets of what the character
-- wears, saved as item keys, so the pieces are kept. The hold goes through
-- Disposition's own inSet rule: every decision context (the sell list, the
-- bank list and what uses its context, the loot note) is given
-- context.sets = GearSets.Facts(store), and a set piece is kept "in your
-- <name> set": never offered for sale, to the bank or for the auction house.
--
--   <slash> set                  your sets with their piece counts, and the
--                                sets imported from Flow (shown only)
--   <slash> set save <name>      what you wear now, saved as set <name>
--   <slash> set forget <name>    that set removed
--
-- LOOK ONLY. Nothing is equipped, moved, sold or clicked; equipping a set is
-- not here. It writes only the character's own saved data.
--
--   facts = GearSets.Facts(store)   { [item key] = { set name, ... } }, or
--                                   nil when no set is saved: what
--                                   Disposition's inSet rule reads
--   sets  = GearSets.Saved(store)   { { name, items = { key ... },
--                                   slots = { slot ... } or nil } ... }
--   lines, changed = GearSets.Run(k, rest)
--   lines = GearSets.TipLines(store, link)   the tooltip keep line, or nil
--   api   = GearSets.Declare(k, diag)        adds the word; a module that
--                                   adds the keep line to item tooltips
--
-- Saved data: char state.gearSets = { { name = "tank", items = { 1000,
-- "15234:588", ... }, slots = { 15, 11, ... } } ... }, a list in the order
-- saved. A set holds its name (what the player typed), the item keys
-- (Items/Key.lua: an item with a random suffix is its own key) and the
-- inventory slot each was worn in (a set saved before slots has none),
-- never a character name. Imported
-- sets (account settings.gear.mySets, Flow's { [role] = { [slot] = link } })
-- are read only, listed, and never hold anything: they are account wide, so
-- they may be another character's.
-- Reads: client.wornLinks() -> { [slot] = link } or nil (not known).
-- After a change Reservations.Changed(k): an open sell or bank list lists
-- again, as for goals.

local Sets = {}
ns.GearSets = Sets

Sets.NAME = "gearSets"
Sets.WORD = "set"
Sets.PATH = "state.gearSets"                 -- char
Sets.IMPORTED_PATH = "settings.gear.mySets"  -- account, imported from Flow
Sets.MAX_NAME = 32
Sets.MAX_SETS = 20
Sets.HELP = "save what you wear as a named set (set save <name>), forget one (set forget <name>), "
    .. "or list them; a set's pieces are never offered for sale"
Sets.NOT_LOADED = "Your saved data is not loaded yet; try again after login."
Sets.CANT_READ = "Can't read what you wear right now, so no set was saved."
Sets.NOTHING_WORN = "You wear nothing to save, so no set was saved."
Sets.FAILED = "That could not be saved, so nothing was changed."
Sets.TOO_MANY = "You have " .. Sets.MAX_SETS .. " sets; forget one first. Nothing was saved."
Sets.BAD_NAME = "A set name is up to " .. Sets.MAX_NAME .. " letters, with no bars or control characters."

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function goodName(name)
    return type(name) == "string" and name ~= "" and #name <= Sets.MAX_NAME and not name:find("[|%c]")
end

local function plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

local function usage(slash)
    local cmd = tostring(slash or "") .. " " .. Sets.WORD
    return "Say " .. cmd .. " save <name>, " .. cmd .. " forget <name>, or " .. cmd .. " to list your sets."
end

local function noSets(slash)
    return "You have no saved sets. Say " .. tostring(slash or "") .. " " .. Sets.WORD
        .. " save <name> to save what you wear as one."
end

local function get(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

-- An inventory slot id as saved: a whole number 1..19.
local function goodSlot(slot)
    return type(slot) == "number" and slot >= 1 and slot <= 19 and slot == math.floor(slot)
end

-- The saved sets that read, in order; a set or a key that does not read is
-- left out. slots (the inventory slot each key was worn in, same order) is
-- kept only when every kept key has a good one; else nil (an older set).
-- noSlot: how many pieces of a set saved with slots have none that reads.
function Sets.Saved(store)
    local raw, out = get(store, "char", Sets.PATH), {}
    if type(raw) ~= "table" then return out end
    for i = 1, #raw do
        local s = raw[i]
        if type(s) == "table" and goodName(s.name) and type(s.items) == "table" then
            local withSlots = type(s.slots) == "table"
            local items, slots, allSlots, noSlot = {}, {}, withSlots, 0
            for j = 1, #s.items do
                local key = ns.Items.Key(s.items[j])
                if key ~= nil then
                    items[#items + 1] = key
                    if withSlots and goodSlot(s.slots[j]) then
                        slots[#items] = s.slots[j]
                    elseif withSlots then
                        allSlots = false
                        noSlot = noSlot + 1
                    end
                end
            end
            local set = { name = s.name, items = items }
            if allSlots then set.slots = slots end
            -- Pieces of a set saved with slots whose slot does not read.
            if noSlot > 0 then set.noSlot = noSlot end
            out[#out + 1] = set
        end
    end
    return out
end

function Sets.Facts(store)
    local facts, any = {}, false
    for _, s in ipairs(Sets.Saved(store)) do
        for _, key in ipairs(s.items) do
            local names = facts[key]
            if not names then
                names = {}
                facts[key] = names
            end
            -- A set wearing two of one item names it once.
            if names[#names] ~= s.name then names[#names + 1] = s.name end
            any = true
        end
    end
    return any and facts or nil
end

-- The imported sets: { { name, pieces } } sorted by name.
local function imported(store)
    local raw, out = get(store, "account", Sets.IMPORTED_PATH), {}
    if type(raw) ~= "table" then return out end
    for name, slots in pairs(raw) do
        if goodName(name) and type(slots) == "table" then
            local n = 0
            for _, link in pairs(slots) do
                if ns.Items.Key(link) ~= nil then n = n + 1 end
            end
            out[#out + 1] = { name = name, pieces = n }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Is the character's saved data there and the store open? (saved() makes
-- the table when it is missing, so ask whether it exists.)
local function loaded(k)
    local c = k.client
    if type(c) ~= "table" or type(k.store) ~= "table" or not k.store.opened then return false end
    if type(c.savedExists) == "function" then return c.savedExists(k.id.charDB) and true or false end
    return type(c.saved) == "function" and type(c.saved(k.id.charDB)) == "table"
end

-- What is worn now, as item keys in slot order, and the slot of each key
-- (same order); nil when not known.
local function wornKeys(client)
    if type(client) ~= "table" or type(client.wornLinks) ~= "function" then return nil end
    local ok, links = pcall(client.wornLinks)
    if not ok or type(links) ~= "table" then return nil end
    local slots = {}
    for slot in pairs(links) do
        if type(slot) == "number" then slots[#slots + 1] = slot end
    end
    table.sort(slots)
    local keys, at = {}, {}
    for _, slot in ipairs(slots) do
        local key = ns.Items.Key(links[slot])
        if key ~= nil then
            keys[#keys + 1] = key
            at[#keys] = slot
        end
    end
    return keys, at
end

-- The list as saved: plain tables, nothing but name, items and slots.
local function save(k, sets)
    local list = {}
    for i, s in ipairs(sets) do
        local items = {}
        for j, key in ipairs(s.items) do items[j] = key end
        list[i] = { name = s.name, items = items }
        if type(s.slots) == "table" then
            local slots = {}
            for j = 1, #items do slots[j] = s.slots[j] end
            list[i].slots = slots
        end
    end
    local ok, reason = k.store:set("char", Sets.PATH, list)
    if not ok then
        -- The store's reason names internal paths: kept for diagnostics only.
        if type(k.problems) == "table" then k.problems:add("gearSets", "save", tostring(reason)) end
        return false
    end
    return true
end

local function find(sets, name)
    for i, s in ipairs(sets) do
        if s.name == name then return i end
    end
    return nil
end

function Sets.Run(k, rest)
    rest = trim(rest)
    local slash = k.id and k.id.slash
    local word, more = rest:match("^(%S*)%s*(.-)$")
    more = trim(more)

    if rest == "" then
        if not loaded(k) then return { Sets.NOT_LOADED }, false end
        local lines = {}
        local mine = Sets.Saved(k.store)
        if #mine == 0 then
            lines[1] = noSets(slash)
        else
            local parts = {}
            for i, s in ipairs(mine) do parts[i] = s.name .. " (" .. plural(#s.items, "piece", "pieces") .. ")" end
            lines[1] = "Your sets: " .. table.concat(parts, ", ")
        end
        local theirs = imported(k.store)
        if #theirs > 0 then
            local parts = {}
            for i, s in ipairs(theirs) do parts[i] = s.name .. " (" .. plural(s.pieces, "piece", "pieces") .. ")" end
            local from = k.id and k.id.predecessor or "Flow"
            lines[#lines + 1] = "Imported from " .. tostring(from) .. " (not used to keep items): "
                .. table.concat(parts, ", ")
        end
        return lines, false
    end

    if word ~= "save" and word ~= "forget" then return { usage(slash) }, false end
    if more == "" then return { usage(slash) }, false end
    if not goodName(more) then return { Sets.BAD_NAME }, false end
    if not loaded(k) then return { Sets.NOT_LOADED }, false end
    local sets = Sets.Saved(k.store)
    local at = find(sets, more)

    if word == "forget" then
        if not at then return { "You have no set named " .. more .. "." }, false end
        table.remove(sets, at)
        if not save(k, sets) then return { Sets.FAILED }, false end
        return { "Set " .. more .. " forgotten." }, true
    end

    local keys, slots = wornKeys(k.client)
    if keys == nil then return { Sets.CANT_READ }, false end
    if #keys == 0 then return { Sets.NOTHING_WORN }, false end
    if not at and #sets >= Sets.MAX_SETS then return { Sets.TOO_MANY }, false end
    local set = { name = more, items = keys, slots = slots }
    if at then sets[at] = set else sets[#sets + 1] = set end
    if not save(k, sets) then return { Sets.FAILED }, false end
    return { "Set " .. more .. " saved: " .. plural(#keys, "piece", "pieces") .. "." }, true
end

-- Disposition's inSet rule alone, so the tooltip says the set and nothing
-- the other rules would add.
local function inSetRule()
    for _, r in ipairs(ns.Disposition.RULES) do
        if r.key == "inSet" then return r end
    end
    return nil
end

function Sets.TipLines(store, link)
    local key = ns.Items.Key(link)
    if key == nil then return nil end
    local facts = Sets.Facts(store)
    if not facts or not facts[key] then return nil end
    local rule = inSetRule()
    if not rule then return nil end
    local d = ns.Disposition.Decide({ key = key }, { sets = facts, rules = { rule } })
    if type(d) ~= "table" or d.rule ~= "inSet" then return nil end
    return ns.TooltipDisposition.Lines(d)
end

-- A line's colour by its tone, as the gear tooltip colours its lines.
Sets.COLOUR = {
    good = { 0.1, 1, 0.1 },
    same = { 1, 1, 1 },
    bad = { 1, 0.3, 0.3 },
    none = { 0.6, 0.6, 0.6 },
}

function Sets.Declare(k, diag)
    local api = {}
    local hooked, errors, cancel = false, 0, nil
    local seen = {}
    function api.hooked() return hooked end
    function api.errors() return errors end

    local function run(rest)
        local lines, changed = Sets.Run(k, rest)
        for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
        if changed then ns.Reservations.Changed(k) end
        return changed
    end
    api.run = run

    if diag and type(diag.commands) == "table" then
        diag.commands[Sets.WORD] = run
        if type(diag.help) == "table" then diag.help[Sets.WORD] = Sets.HELP end
    end

    k:Module({
        name = Sets.NAME,
        needs = { "client", "store" },
        provides = { Hooked = api.hooked, Errors = api.errors },
        start = function(ctx)
            if type(ctx.client.onItemTooltip) ~= "function" then return end
            local got = ctx.client.onItemTooltip(function(link, add)
                if type(add) ~= "function" then return end
                -- Worked out before anything is added: an error leaves the
                -- tooltip as the game made it.
                local ok, lines = pcall(Sets.TipLines, ctx.store, link)
                if not ok then
                    errors = errors + 1
                    local text = tostring(lines)
                    if not seen[text] and type(k.problems) == "table" then
                        seen[text] = true
                        k.problems:add("gearSets", "tooltip", text)
                    end
                    return
                end
                for i = 1, #(lines or {}) do
                    local colour = Sets.COLOUR[lines[i].tone] or Sets.COLOUR.none
                    add(lines[i].text, colour[1], colour[2], colour[3])
                end
            end)
            if type(got) == "function" then
                cancel, hooked = got, true
            end
        end,
        stop = function()
            if cancel then cancel() end
            cancel, hooked = nil, false
        end,
    })
    return api
end

-- The addon's own: the word is added and the module declared when this
-- file loads; the tooltip is followed from login.
ns.gearSets = Sets.Declare(ns, ns.diag)
