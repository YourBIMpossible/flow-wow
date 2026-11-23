local _, ns = ...

-- Reservations: what the player's goals hold of their things right now, for
-- the bank list, the bank prompt and the banker word to share.
--
--   r = ns.reservations.Current()   one evaluation: { status, snapshot, grants }
--   Reservations.Evaluate(read)     the same from a `read` table (pure but for read)
--   Reservations.Source(name, fn)   a producer of claims; fn(snapshot) -> claims
--   Reservations.Grants(r)          r's grants, or nil when unavailable
--   Reservations.HeldIn(grants, "bags" | "bank")   what they hold in one place
--
-- One evaluation is one Resources.Take and one Resources.Resolve over every
-- claim the sources give for that snapshot, so the bags and the bank are
-- counted once and no two claims hold the same stack.
--
-- status:
--   "ok"           claims were resolved; grants holds them
--   "none"         nothing claims anything: no active reservations. grants is
--                  a real, empty resolve, so Held is 0 for every item
--   "unavailable"  a source is registered and the bags could not be read,
--                  or a source failed (raised, or gave no list): Z-Flow
--                  can't say what is reserved. grants is nil, and nothing may
--                  be advised to be sold on the strength of it
--
-- Sources: a producer that plans in goals or steps (ItemPlan.Claims,
-- Resources.ClaimsOf) registers once, by name; they are asked in name order.
-- None is registered at this commit, so the status is "none" until one is.
--
-- READ ONLY. Nothing here deposits, withdraws, moves, sells, buys or uses
-- anything, adds an event, a window or saved data. Fresh on every call: the
-- callers already re-ask on the game's bag and bank events, so nothing polls.
-- Not tested in game.

local Reservations = {}
ns.Reservations = Reservations

Reservations.NAME = "reservations"
Reservations.OK = "ok"
Reservations.NONE = "none"
Reservations.UNAVAILABLE = "unavailable"

local sources = {}

function Reservations.Source(name, fn)
    if type(name) ~= "string" or name == "" then error("a reservation source needs a name", 2) end
    if fn ~= nil and type(fn) ~= "function" then error("a reservation source is a function", 2) end
    sources[name] = fn
end

local function sourceNames()
    local names = {}
    for name in pairs(sources) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function unavailable(snapshot, why)
    return { status = Reservations.UNAVAILABLE, snapshot = snapshot, why = why }
end

function Reservations.Evaluate(read)
    local R = ns.Resources
    local snapshot = R.Take(read)
    local names = sourceNames()
    -- With no source at all nothing can be reserved, read or not.
    if #names > 0 and type(snapshot.bags) ~= "table" then return unavailable(snapshot, "bags") end
    local claims = {}
    for _, name in ipairs(names) do
        local ok, got = pcall(sources[name], snapshot)
        if not ok or type(got) ~= "table" then return unavailable(snapshot, name) end
        for i = 1, #got do claims[#claims + 1] = got[i] end
    end
    local grants = R.Resolve(snapshot, claims)
    return { status = #claims > 0 and Reservations.OK or Reservations.NONE, snapshot = snapshot, grants = grants }
end

-- The grants of an evaluation that may be used, or nil.
function Reservations.Grants(r)
    if type(r) ~= "table" or r.status == Reservations.UNAVAILABLE then return nil end
    return r.grants
end

-- What the grants hold in one place, "bags" or "bank", as an object with
-- Held(key) the way Disposition and Bank.Pick ask it, so an item counted in
-- the bags is never counted again in the bank. An item claim that may take
-- from a bank not seen this session holds, in the bank, the most it could
-- take there: Z-Flow can't say it doesn't. nil when grants is nil.
function Reservations.HeldIn(grants, place)
    if type(grants) ~= "table" then return nil end
    local held = {}
    for i = 1, #grants do
        local g = grants[i]
        local c = g.claim
        if not g.invalid and type(c) == "table" and c.kind == "item" then
            local n = 0
            if type(g.from) == "table" and ns.Resources.IsCount(g.from[place]) then n = g.from[place] end
            if place == "bank" and g.unknown == "bank" and ns.Resources.IsCount(c.amount) then
                n = n + math.max(0, c.amount - (g.got or 0))
            end
            if n > 0 then held[c.key] = (held[c.key] or 0) + n end
        end
    end
    return { Held = function(_, key) return held[key] or 0 end }
end

function Reservations.Declare(k)
    local api = {}
    local read

    function api.Current()
        if not read then return unavailable(nil, "not started") end
        local ok, r = pcall(Reservations.Evaluate, read)
        if not ok or type(r) ~= "table" then return unavailable(nil, "failed") end
        return r
    end

    k:Module({
        name = Reservations.NAME,
        needs = { "client" },
        provides = { Current = api.Current },
        -- One read table per session: it keeps the bank's last reading.
        start = function(ctx) read = ns.make.resourceRead(ctx.client) end,
        stop = function() read = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.reservations = Reservations.Declare(ns)
