local _, ns = ...

-- HearthSeen (G46): the module that saves where this player made a home,
-- for N.HearthStepFrom (Nav/HearthStep.lua) to read. The same pattern as
-- Nav/ProfSeen.lua: only what this client showed, nothing authored,
-- nothing printed. It only reads; it opens no window and talks to no one.
--
-- What is taken as seen: HEARTHSTONE_BOUND, the one event the client sends
-- when the player has made an inn home. At that moment the player stands
-- beside the innkeeper, so client.position() is where the stone will bring
-- the player back to (near enough: beside the npc, not on it).
--
-- Saved per character, char "learned.places.bind" =
--   { name, map, x, y, seen }
-- name is client.bindLocation() (CLIENT NEED) read at the event; map, x, y
-- are client.position(); seen is client.clock(), left out when the clock
-- is not known. A new home takes the place of the last one whole: nothing
-- of the old entry is kept.
--
-- With no name, or with no position, nothing is written at all: a place
-- that cannot be matched to the bind name later is of no use. A store that
-- refuses a write is left as it was.
--
--   HearthSeen.Seen(client, store) -> report   one sighting read
--   HearthSeen.Declare(k)          -> api      declares the module
--     api.last()   the report of the last event read, nil before the first
--   ns.use(HearthSeen.NAME) -> { Last = api.last }
--
--   report = { kind = "bind", ok, reason (when not ok), name }
--
-- Not tested in game: the event name and every client read used here are
-- first guesses.
-- The event name is on warcraft.wiki.gg (HEARTHSTONE_BOUND).

local HearthSeen = ns.HearthSeen or {}
ns.HearthSeen = HearthSeen

HearthSeen.NAME = "hearthSeen"
HearthSeen.EVENT = "HEARTHSTONE_BOUND"
HearthSeen.PLACE = "learned.places.bind"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- One read of the client; nil when it has no such read. An error is not
-- caught: the kernel counts it against the module.
local function ask(client, read)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read]()
end

local function refuse(report, reason)
    report.ok, report.reason = false, reason
    return report
end

function HearthSeen.Seen(client, store)
    local report = { kind = "bind" }
    -- Every read comes before the write.
    local name = text(ask(client, "bindLocation"))
    if not name then return refuse(report, "the bind place is not known") end
    report.name = name
    local pos = ask(client, "position")
    if type(pos) ~= "table" or not (finite(pos.map) and finite(pos.x) and finite(pos.y)) then
        return refuse(report, "the position is not known")
    end
    local now = ask(client, "clock")
    if not finite(now) then now = nil end

    if type(store) ~= "table" or type(store.set) ~= "function" then
        return refuse(report, "the bind place cannot be saved")
    end
    local e = { name = name, map = pos.map, x = pos.x, y = pos.y, seen = now }
    if store:set("char", HearthSeen.PLACE, e) ~= true then
        return refuse(report, "the bind place cannot be saved")
    end
    report.ok = true
    return report
end

-- Declares the module on kernel k. Usable at once: before the first event
-- last() is nil.
function HearthSeen.Declare(k)
    local api = {}
    local last
    function api.last() return last end
    k:Module({
        name = HearthSeen.NAME,
        needs = { "client", "store", "bus" },
        provides = { Last = api.last },
        start = function(ctx)
            ctx.bus:on(HearthSeen.NAME, HearthSeen.EVENT, function()
                last = HearthSeen.Seen(ctx.client, ctx.store)
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.hearthSeen = HearthSeen.Declare(ns)
