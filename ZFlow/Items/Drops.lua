local _, ns = ...

-- Drops (L6-J, G10 second part): what this character looted from which
-- creature, from loot-window readings.
--
-- LOOK ONLY. It reads the loot window when the game opens it and writes
-- Z-Flow's own saved data. It never loots, auto-loots, rolls, picks up or
-- closes anything.
--
--   ok, why = Drops.Record(book, seen, reading)     pure
--   lines   = Drops.Run(k, rest)                    `<slash> drops [creature]`
--   api     = Drops.Declare(k, diag)                api.recorded()
--
-- reading: what client.lootWindow() gives (CLIENT NEED), or nil:
--   { source = { kind = "creature", guid = "...", id = npc id, name = "..." },
--     items  = { { item = link or ID, count = n }, ... } }
--   Only a creature's corpse is recorded: a chest, a fished-up item, a
--   pickpocket or a window whose source was not read is left alone, because
--   whose loot it is would be a guess.
-- book:   the character's "learned.drops":
--   { [npc id] = { name, looted = how many corpses, unread = entries that
--                  could not be read (left out when none),
--                  items = { [item key] = { count = how many in all,
--                                           times = in how many corpses } } } }
-- seen:   { [guid] = true }, kept in memory for the session only: a corpse
--   opened again (some loot left the first time) is counted once.
--
-- Counts, not rates. Each figure is what this character saw. A share is
-- shown only from Drops.MIN_SAMPLES loots of that creature on, and then
-- worded as a share of your own loots. MIN_SAMPLES = 30 is a first guess,
-- not a measured number: even at 30 loots a true 10% drop is commonly
-- seen anywhere from 0 to 6 times, so below it a percentage would mislead.
--
-- Setting: "loot.record" (bool, on by default); the row is the lead's to add.
-- Not tested in game: LOOT_OPENED and the loot read are first guesses.

local Drops = {}
ns.Drops = Drops

Drops.NAME = "drops"
Drops.WORD = "drops"
Drops.EVENT = "LOOT_OPENED"
Drops.SETTING = "loot.record"
Drops.PATH = "learned.drops"
Drops.MIN_SAMPLES = 30
Drops.LIST_MAX = 15
Drops.EMPTY = "No loot recorded yet."

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

function Drops.Record(book, seen, reading)
    if type(book) ~= "table" or type(seen) ~= "table" then return false, "no book" end
    if type(reading) ~= "table" then return false, "no reading" end
    local src = reading.source
    if type(src) ~= "table" or src.kind ~= "creature" then return false, "not a creature" end
    if type(src.guid) ~= "string" or src.guid == "" then return false, "no guid" end
    if not isCount(src.id) or src.id ~= math.floor(src.id) or src.id == 0 then return false, "no creature id" end
    if type(reading.items) ~= "table" then return false, "items not read" end
    if seen[src.guid] then return false, "already counted" end
    seen[src.guid] = true

    local entry = book[src.id]
    if type(entry) ~= "table" then
        entry = { looted = 0, items = {} }
        book[src.id] = entry
    end
    if type(entry.items) ~= "table" then entry.items = {} end
    if type(src.name) == "string" and src.name ~= "" then entry.name = src.name end
    entry.looted = (isCount(entry.looted) and entry.looted or 0) + 1

    local inThis, unread = {}, 0
    for i = 1, #reading.items do
        local it = reading.items[i]
        local key = type(it) == "table" and ns.Items.Key(it.item) or nil
        if key ~= nil and isCount(it.count) and it.count > 0 then
            inThis[key] = (inThis[key] or 0) + it.count
        else
            unread = unread + 1
        end
    end
    for key, n in pairs(inThis) do
        local e = entry.items[key]
        if type(e) ~= "table" or not isCount(e.count) or not isCount(e.times) then
            e = { count = 0, times = 0 }
            entry.items[key] = e
        end
        e.count, e.times = e.count + n, e.times + 1
    end
    if unread > 0 then entry.unread = (isCount(entry.unread) and entry.unread or 0) + unread end
    return true
end

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function namesOf(k)
    local client = k.client
    if type(client) ~= "table" or type(client.itemInfo) ~= "function" then return nil end
    return function(key)
        local ok, info = pcall(client.itemInfo, ns.Items.Id(key) or key)
        if ok and type(info) == "table" then return info.name end
        return nil
    end
end

local function listLines(entries)
    table.sort(entries, function(a, b)
        local la, lb = isCount(a.looted) and a.looted or 0, isCount(b.looted) and b.looted or 0
        if la ~= lb then return la > lb end
        return tostring(a.name) < tostring(b.name)
    end)
    local lines = { "Loot recorded from " .. #entries .. (#entries == 1 and " kind" or " kinds") .. " of creature:" }
    for i = 1, math.min(#entries, Drops.LIST_MAX) do
        lines[#lines + 1] = ns.ItemPresent.DropLines(entries[i], nil, nil)[1]
    end
    if #entries > Drops.LIST_MAX then
        lines[#lines + 1] = "and " .. (#entries - Drops.LIST_MAX) .. " more; say drops <creature name> for one."
    end
    return lines
end

function Drops.Run(k, rest)
    rest = trim(rest):lower()
    local book = k.store:get("char", Drops.PATH)
    local entries = {}
    for _, e in pairs(type(book) == "table" and book or {}) do
        if type(e) == "table" then entries[#entries + 1] = e end
    end
    if #entries == 0 then return { Drops.EMPTY } end
    if rest == "" then return listLines(entries) end
    local exact, partial = {}, {}
    for _, e in ipairs(entries) do
        local name = type(e.name) == "string" and e.name:lower() or nil
        if name == rest then
            exact[#exact + 1] = e
        elseif name and name:find(rest, 1, true) then
            partial[#partial + 1] = e
        end
    end
    local hits = #exact > 0 and exact or partial
    if #hits == 0 then return { 'No loot recorded from a creature named "' .. rest .. '".' } end
    if #hits > 1 then return listLines(hits) end
    return ns.ItemPresent.DropLines(hits[1], namesOf(k), Drops.MIN_SAMPLES)
end

function Drops.Declare(k, diag)
    local api = {}
    local recorded, seen = 0, {}
    function api.recorded() return recorded end
    k:Module({
        name = Drops.NAME,
        needs = { "client", "store", "bus", "settings" },
        provides = { Recorded = api.recorded },
        start = function(ctx)
            ctx.bus:on(Drops.NAME, Drops.EVENT, function()
                if ctx.settings:get(Drops.SETTING) == false then return end
                local read = ctx.client.lootWindow
                if type(read) ~= "function" then return end
                local reading = read()
                if type(reading) ~= "table" then return end
                -- Recorded into a copy first: the saved table is only made
                -- (or touched) when there is something to record.
                local book = ctx.store:get("char", Drops.PATH)
                local made = type(book) ~= "table"
                if made then book = {} end
                if Drops.Record(book, seen, reading) then
                    recorded = recorded + 1
                    if made then ctx.store:set("char", Drops.PATH, book) end
                end
            end)
        end,
    })
    if diag and type(diag.commands) == "table" then
        diag.commands[Drops.WORD] = function(rest)
            local lines = Drops.Run(k, rest)
            for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
        end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.drops = Drops.Declare(ns, ns.diag)
