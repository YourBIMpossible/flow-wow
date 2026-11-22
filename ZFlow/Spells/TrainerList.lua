local _, ns = ...

-- S26 trainer spell lists (A-D): per character, what each trainer window
-- offered, with rank, level and cost, kept for later (after the window
-- closes). Plexy's P-I shows the list live at the open window; this keeps
-- the last list seen at each trainer.
--
-- Pure. A reading comes in as the CLIENT NEED read c.trainerServices()
-- would return it (see the A-C note):
--   { npc =, profession = (nil for a class trainer),
--     rows = { { name =, rank =, state = "available" | "unavailable" | "known",
--                cost = copper, level = n }, ... } }
-- Stored as lists["<npc>|<profession or class>"] = { npc =, profession =,
-- seen = when, rows = {...} } in the character's saved table (the caller
-- writes it through Core/Store.lua).
--
-- Nothing is guessed: a field the client did not give stays nil, and one
-- unreadable row drops the whole reading (never a shorter list). A new
-- visit replaces that trainer's whole list. Look-only: it trains nothing.

ns.TrainerList = {}
local T = ns.TrainerList

-- F-085 trainer wording (§113 Decision 2), em dash.
T.PRICE_UNKNOWN = "price unknown—check trainer"

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

-- The key a trainer's list is kept under.
function T.Key(npc, profession)
    return npc .. "|" .. (text(profession) or "class")
end

-- Returns lists with this reading's trainer replaced; lists is unchanged
-- (and returned as is) when the reading cannot be read.
function T.Record(lists, reading, when)
    if type(lists) ~= "table" then lists = {} end
    if type(reading) ~= "table" or type(reading.rows) ~= "table" then return lists end
    local npc = text(reading.npc)
    if not npc then return lists end
    local rows = {}
    for i = 1, #reading.rows do
        local r = row(reading.rows[i])
        if not r then return lists end
        rows[i] = r
    end
    lists[T.Key(npc, reading.profession)] = {
        npc = npc,
        profession = text(reading.profession),
        seen = count(when) and when or nil,
        rows = rows,
    }
    return lists
end

-- One plain line per row: "Moonfire (Rank 2), level 10, 1s 50c: can learn".
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
    return out
end
