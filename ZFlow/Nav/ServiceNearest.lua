local _, ns = ...
-- Z-Flow nearest service (G36): the nearest place of one kind the player
-- has learned, on the map the player is on. The places are the ones
-- Nav/ServiceSeen.lua saved from what this client showed; nothing is
-- authored here and nothing is printed. Pure but for N.Nearest, which
-- reads the client and the store it is handed. Not tested in game.
--
-- N.SERVICE_KINDS  the kinds, in order: "vendor", "repair", "banker",
--                  "innkeeper", "flight", "mailbox"
-- N.SERVICES       the saved table, char scope: "learned.places.services"
--
-- N.NearestOf(kind, places, here) -> place, or nil
--   places  the saved table: { [key] = { name, guid, map, x, y,
--             kinds = { [kind] = true }, seen, n } }, x and y as shares of
--             the map (0..1)
--   here    { map, x, y, cont, size = { w, h } } (size in yards, optional)
--   place   { kind, key, name, guid, map, x, y, cont, yards, seen }
--             name and guid are nil when they were never known (a mailbox
--             has neither); cont is here.cont; yards is the straight-line
--             distance, nil when the size of the map is not known.
--   nil when the kind is not one of N.SERVICE_KINDS, when the map or the
--   position of the player is not known, or when no such place is known on
--   that map. Nearest is by yards when the size is known, else by shares
--   of the map. A tie goes to the lower key, so the answer does not change
--   by itself. Places on other maps are never returned.
--
-- N.Nearest(kind, client, store) -> place, or nil
--   The same, from the position, zone and map size the client gives and
--   the places the store has saved. client and store default to the ones
--   of the addon (ns.client, ns.store), so N.Nearest(kind) is enough
--   inside the addon. A read that fails is "not known".
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.SERVICE_KINDS = { "vendor", "repair", "banker", "innkeeper", "flight", "mailbox" }
N.SERVICES = "learned.places.services"

local KNOWN = {}
for _, kind in ipairs(N.SERVICE_KINDS) do KNOWN[kind] = true end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

function N.NearestOf(kind, places, here)
    if not KNOWN[kind] or type(places) ~= "table" or type(here) ~= "table" then return nil end
    if here.map == nil or not (finite(here.x) and finite(here.y)) then return nil end
    local size = type(here.size) == "table" and finite(here.size.w) and finite(here.size.h)
        and here.size.w > 0 and here.size.h > 0 and here.size or nil
    local w, h = size and size.w or 1, size and size.h or 1
    local best, bestKey, bestD
    for key, e in pairs(places) do
        if type(e) == "table" and type(e.kinds) == "table" and e.kinds[kind] == true
            and e.map == here.map and finite(e.x) and finite(e.y) then
            local dx, dy = (e.x - here.x) * w, (e.y - here.y) * h
            local d = dx * dx + dy * dy
            if best == nil or d < bestD or (d == bestD and tostring(key) < tostring(bestKey)) then
                best, bestKey, bestD = e, key, d
            end
        end
    end
    if best == nil then return nil end
    return {
        kind = kind, key = bestKey, name = text(best.name), guid = text(best.guid),
        map = best.map, x = best.x, y = best.y, cont = here.cont,
        yards = size and math.sqrt(bestD) or nil,
        seen = finite(best.seen) and best.seen or nil,
    }
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function N.Nearest(kind, client, store)
    if client == nil then client = ns.client end
    if store == nil then store = ns.store end
    if not KNOWN[kind] then return nil end
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, places = pcall(store.get, store, "char", N.SERVICES)
    if not ok or type(places) ~= "table" then return nil end
    local at = ask(client, "position")
    if type(at) ~= "table" or at.map == nil then return nil end
    local zone = ask(client, "zone")
    local size = ask(client, "mapSize", at.map)
    return N.NearestOf(kind, places, {
        map = at.map, x = at.x, y = at.y,
        cont = type(zone) == "table" and zone.cont or nil,
        size = type(size) == "table" and { w = size.w, h = size.h } or nil,
    })
end
