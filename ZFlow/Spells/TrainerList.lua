local _, ns = ...

-- S26 trainer spell lists (A-D): per character, what each trainer window
-- offered, with rank, level and cost, kept for later (after the window
-- closes). Plexy's P-I shows the list live at the open window; this keeps
-- the last list seen at each trainer.
--
-- Pure. A reading comes in as the CLIENT NEED read c.trainerServices()
-- would return it:
--   { npc =, profession = (nil for a class trainer), faction = (the
--     visiting character's, nil when not known),
--     filter = { available = bool, unavailable = bool, known = bool },
--     rows = { { name =, rank =, state = "available" | "unavailable" | "known",
--                cost = copper, level = n }, ... } }
-- filter is the window's own filter: which row states it showed. The
-- client maps the game's "used" rows to "known" and leaves out "header"
-- rows (CLIENT NEED).
--
-- Stored as lists[T.Key(npc, profession)] = { npc =, profession =, faction =,
-- seen = when, shown = { [state] = true }, complete = bool, rows = {...} }
-- in the character's saved table (the caller writes it by key through
-- Core/Store.lua, never through a dotted path; T.Key has no dot anyway).
--
-- A filtered window must not pass for a full list (review
-- zflow-aps-a-d-9ea3b8b): a visit replaces only the rows of the states the
-- window showed, and keeps the earlier visit's rows of the other states.
-- shown is every state seen at some visit, and complete is true once all
-- three have been. A reading with no filter, a filter that shows nothing,
-- or a row whose state the window did not show is not stored.
--
-- Nothing is guessed: a field the client did not give stays nil, and one
-- unreadable row drops the whole reading (never a shorter list). Look-only:
-- it trains nothing.

ns.TrainerList = {}
local T = ns.TrainerList

-- F-085 trainer wording (§113 Decision 2), em dash.
T.PRICE_UNKNOWN = "price unknown—check trainer"
T.FILTERED = "Not every row seen: the trainer window was filtered."

local STATE_ORDER = { "available", "unavailable", "known" }
local STATES = { available = "can learn", unavailable = "not yet", known = "known" }

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function count(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and math.floor(v) == v
end

local function row(r)
    if type(r) ~= "table" then return nil end
    local name = text(r.name)
    if not name or not STATES[r.state] then return nil end
    if r.rank ~= nil and not text(r.rank) then return nil end
    if r.cost ~= nil and not count(r.cost) then return nil end
    if r.level ~= nil and not count(r.level) then return nil end
    return { name = name, rank = text(r.rank), state = r.state, cost = r.cost, level = r.level }
end

-- The key a trainer's list is kept under. "%" and "." in names are
-- written as %25 and %2E, so the key never holds a dot (a saved-data path
-- separator) and two names cannot share a key. The real name is on the
-- entry.
function T.Key(npc, profession)
    local raw = npc .. "|" .. (text(profession) or "class")
    return (raw:gsub("[%%%.]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- Which states a filter showed, or nil when the filter cannot be read or
-- shows nothing.
local function shownBy(filter)
    if type(filter) ~= "table" then return nil end
    local shown, any = {}, false
    for _, s in ipairs(STATE_ORDER) do
        local v = filter[s]
        if type(v) ~= "boolean" then return nil end
        if v then shown[s] = true; any = true end
    end
    return any and shown or nil
end

-- Returns lists with this reading recorded; lists is unchanged (and
-- returned as is) when the reading cannot be read.
function T.Record(lists, reading, when)
    if type(lists) ~= "table" then lists = {} end
    if type(reading) ~= "table" or type(reading.rows) ~= "table" then return lists end
    local npc = text(reading.npc)
    if not npc then return lists end
    local shown = shownBy(reading.filter)
    if not shown then return lists end
    local rows = {}
    for i = 1, #reading.rows do
        local r = row(reading.rows[i])
        if not r or not shown[r.state] then return lists end
        rows[i] = r
    end
    local key = T.Key(npc, reading.profession)
    local old = lists[key]
    local seenStates = {}
    for s in pairs(shown) do seenStates[s] = true end
    if type(old) == "table" and type(old.rows) == "table" then
        -- A spell and rank the new visit lists (in any state) is not kept
        -- from the old list too: the new state wins (review d5a4dc1).
        local fresh = {}
        for _, r in ipairs(rows) do fresh[r.name .. "\0" .. (r.rank or "")] = true end
        for _, r in ipairs(old.rows) do
            if type(r) == "table" and STATES[r.state] and not shown[r.state]
                and type(r.name) == "string" and not fresh[r.name .. "\0" .. (r.rank or "")] then
                rows[#rows + 1] = r
            end
        end
        if type(old.shown) == "table" then
            for _, s in ipairs(STATE_ORDER) do
                if old.shown[s] == true then seenStates[s] = true end
            end
        end
    end
    local complete = true
    for _, s in ipairs(STATE_ORDER) do
        if not seenStates[s] then complete = false end
    end
    lists[key] = {
        npc = npc,
        profession = text(reading.profession),
        faction = text(reading.faction),
        seen = count(when) and when or nil,
        shown = seenStates,
        complete = complete,
        rows = rows,
    }
    return lists
end

-- One plain line per row: "Moonfire (Rank 2), level 10, 1s 50c: can learn",
-- and a last line when the list is not complete.
function T.Lines(entry)
    local out = {}
    if type(entry) ~= "table" or type(entry.rows) ~= "table" then return out end
    for _, r in ipairs(entry.rows) do
        local parts = { r.rank and (r.name .. " (" .. r.rank .. ")") or r.name }
        if r.level then parts[#parts + 1] = "level " .. r.level end
        local coin = r.cost and ns.Prices and ns.Prices.Coin and ns.Prices.Coin(r.cost) or nil
        parts[#parts + 1] = coin or T.PRICE_UNKNOWN
        out[#out + 1] = table.concat(parts, ", ") .. ": " .. STATES[r.state]
    end
    if entry.complete ~= true then out[#out + 1] = T.FILTERED end
    return out
end
