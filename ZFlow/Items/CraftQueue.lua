local _, ns = ...

-- CraftQueue (P-CRAFT, lead section 226: #34 Smelt All, G21 the craft bar,
-- craft controls): the recipes the player ticked on the craft bar, made one
-- craft at a time, row after row, and what stops the next craft.
--
--   q = Q.New(picks)             picks: { { id =, name =, count = }, ... }
--   Q.Current(q) -> row | nil    the row whose next craft is due
--   Q.Made(q) -> done            one craft of the current row finished
--   Q.Total(q) -> made, total
--   Q.Blocker(row, reads) -> why, detail | nil
--   Q.Line(q), Q.StopLine(q, why, detail), Q.DoneLine(q) -> the player's lines
--   Q.MakeAll(recipes, reagentsOf, have) -> picks   (Smelt all)
--
-- Pure: nothing read from the game and nothing crafted. The bar
-- (UI/CraftBar.lua) gives the reads and owns the click.
-- Unknown stays unknown: a read that is not known never counts as room in
-- the bags or as reagents in hand. Two reads the game itself guards are not
-- stops when not known: moving (a move breaks the cast) and whether the
-- recipe can be made here (the craft call then fails, and the bar stops).

local Q = {}
ns.CraftQueue = Q

-- The most of one recipe in one run: the bar's count goes no higher.
Q.MAX = 999

-- Professions whose window gets the Smelt all button: Mining (186).
Q.SMELTS = { [186] = true }

-- Why a run stopped, as the player reads it after "Stopped: ".
Q.WHY = {
    combat = "you are in combat",
    moving = "you moved",
    station = "this recipe cannot be made here",
    bagsFull = "your bags are full",
    bagsUnread = "your bags could not be read",
    reagentsUnread = "the reagents could not be counted",
    missing = "not enough %s",
    click = "you stopped it",
    interrupted = "the craft was interrupted",
    window = "the profession window closed",
    noStart = "no craft started",
    noCall = "the craft could not start",
    closed = "the craft bar was closed",
}

local function whole(n)
    return type(n) == "number" and n == n and n >= 1 and n < math.huge and n == math.floor(n)
end

function Q.New(picks)
    local q = { rows = {}, at = 1 }
    for _, p in ipairs(type(picks) == "table" and picks or {}) do
        if type(p) == "table" and type(p.id) == "number" and whole(p.count) then
            q.rows[#q.rows + 1] = { id = p.id, name = type(p.name) == "string" and p.name or nil,
                count = math.min(p.count, Q.MAX), made = 0 }
        end
    end
    return q
end

function Q.Current(q)
    return q.rows[q.at]
end

function Q.Made(q)
    local row = q.rows[q.at]
    if row then
        row.made = row.made + 1
        if row.made >= row.count then q.at = q.at + 1 end
    end
    return q.rows[q.at] == nil
end

function Q.Total(q)
    local made, total = 0, 0
    for _, r in ipairs(q.rows) do
        made, total = made + r.made, total + r.count
    end
    return made, total
end

-- What stops the next craft of row, in this order: combat, moving, the
-- station, the bags, the reagents. reads = { combat, moving, usable, why,
-- free (free bag slots, nil when the bags were not read), reagents (the
-- recipe's { { item, count } }, nil when not read), have(item) -> count | nil }.
function Q.Blocker(row, reads)
    if reads.combat ~= false then return "combat" end
    if reads.moving == true then return "moving" end
    if reads.usable == false then
        if type(reads.why) == "string" and reads.why ~= "" then return "station", reads.why end
        return "station"
    end
    if reads.free == nil then return "bagsUnread" end
    if reads.free < 1 then return "bagsFull" end
    if type(reads.reagents) ~= "table" then return "reagentsUnread" end
    local short
    for _, r in ipairs(reads.reagents) do
        local n = reads.have(r.item)
        if type(n) ~= "number" then return "reagentsUnread" end
        if short == nil and n < r.count then short = r.item end
    end
    if short ~= nil then return "missing", short end
    return nil
end

local function nameOf(row)
    return row.name or ("recipe " .. tostring(row.id))
end

function Q.Line(q)
    local row = Q.Current(q)
    if not row then return Q.DoneLine(q) end
    local line = "Making " .. nameOf(row) .. ": " .. row.made .. " of " .. row.count
    if #q.rows > 1 then line = line .. " (recipe " .. q.at .. " of " .. #q.rows .. ")" end
    return line
end

-- detail: the missing item's name for "missing", the game's reason for
-- "station".
function Q.StopLine(q, why, detail)
    local text = Q.WHY[why] or tostring(why)
    if why == "missing" then
        text = text:format(type(detail) == "string" and detail or "a reagent")
    elseif why == "station" and type(detail) == "string" and detail ~= "" then
        text = detail
    end
    local made, total = Q.Total(q)
    return "Stopped: " .. text .. ". Made " .. made .. " of " .. total .. "."
end

function Q.DoneLine(q)
    local parts = {}
    for _, r in ipairs(q.rows) do
        if r.made > 0 then parts[#parts + 1] = r.made .. " x " .. nameOf(r) end
    end
    if #parts == 0 then return "Made nothing." end
    return "Made " .. table.concat(parts, ", ") .. "."
end

-- Smelt all: each learned recipe at as many crafts as the bags cover, the
-- scarcest reagent deciding. A recipe whose reagents or counts were not
-- read is left out, never guessed.
function Q.MakeAll(recipes, reagentsOf, have)
    local picks = {}
    for _, r in ipairs(type(recipes) == "table" and recipes or {}) do
        local need = r.learned == true and reagentsOf(r.id) or nil
        if type(need) == "table" and #need > 0 then
            local n
            for _, g in ipairs(need) do
                local held = have(g.item)
                if type(held) ~= "number" or not whole(g.count) then n = nil break end
                local can = math.floor(held / g.count)
                if n == nil or can < n then n = can end
            end
            if n and n >= 1 then
                picks[#picks + 1] = { id = r.id, name = r.name, count = math.min(n, Q.MAX) }
            end
        end
    end
    return picks
end
