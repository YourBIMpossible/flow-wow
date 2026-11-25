local _, ns = ...
-- Z-Flow nearest service (G36): the nearest place of one kind the player
-- has learned, on the map the player is on. The places are the ones
-- Nav/ServiceSeen.lua saved from what this client showed; nothing is
-- authored here and nothing is printed. Pure but for N.Nearest, which
-- reads the client and the store it is handed, and asks the profession
-- feed for what the player's own Questie gives. Not tested in game.
--
-- N.SERVICE_KINDS  the kinds, in order: "vendor", "repair", "banker",
--                  "innkeeper", "flight", "mailbox", "auction"
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
-- N.NearerOf(kind, saved, q, places, here) -> place, or nil      pure
--   saved   N.NearestOf's answer, or nil
--   q       Questie's nearest NPC of that kind the player's faction can
--           use: { name, map, x, y, yards }, on here.map or on another map
--           of the player's continent; or nil
--   The rule of the predecessor's Modules/Nav/Services.lua (S:Nearest): the
--   places the player has used and Questie's are set side by side and the
--   nearest wins, whichever it is from; at the same distance the one the
--   player has used. Here: on the map the player is on. An NPC of Questie's
--   that the player has used (the same name saved on the same map, for
--   that kind) is the saved place, never an unvisited one. With no place
--   on this map from either, Questie's on another map of the continent.
--   A place from Questie has the shape of a saved one, with
--     key = "questie:<name>:<map>:<x>:<y>", unvisited = true,
--     from = N.QUESTIE, and no seen and no guid;
--   yards on another map is q.yards (nil when the world does not say).
--
-- N.Nearest(kind, client, store, use) -> place, or nil[, N.READING]
--   The same, from the position, zone and map size the client gives, the
--   places the store has saved, and Questie's nearest from the profession
--   feed (use(N.ProfFeed.NAME).Service, the one owner of the Questie
--   reader; looked up when called). client and store default to the ones
--   of the addon (ns.client, ns.store). use does NOT default (lead section
--   626): Questie's places go only to a caller that asks for them by
--   handing in the module lookup; with none handed in the answer is a
--   place this character used, or nil, and Questie's read is not started.
--   A read that fails is "not known". No Questie,
--   none of the kind, the other faction's, another continent: the saved
--   place or nil, as before. A mailbox is no NPC: Questie is never asked.
--   The ask reads nothing of Questie itself (the feed's pass does, out of
--   combat): nil with N.READING says Questie's list is still being gone
--   through and a later ask may have a place.
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.SERVICE_KINDS = { "vendor", "repair", "banker", "innkeeper", "flight", "mailbox", "auction" }
N.SERVICES = "learned.places.services"
N.QUESTIE = "questie"
N.READING = "reading"

local KNOWN = {}
for _, kind in ipairs(N.SERVICE_KINDS) do KNOWN[kind] = true end
-- The kinds that are no NPC: saved places only.
local NO_NPC = { mailbox = true }

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- The size of the player's map in yards, or nil when it is not known.
local function sizeOf(here)
    return type(here.size) == "table" and finite(here.size.w) and finite(here.size.h)
        and here.size.w > 0 and here.size.h > 0 and here.size or nil
end

function N.NearestOf(kind, places, here)
    if not KNOWN[kind] or type(places) ~= "table" or type(here) ~= "table" then return nil end
    if here.map == nil or not (finite(here.x) and finite(here.y)) then return nil end
    local size = sizeOf(here)
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

function N.NearerOf(kind, saved, q, places, here)
    if not KNOWN[kind] or type(here) ~= "table" or here.map == nil
        or not (finite(here.x) and finite(here.y)) then
        return saved
    end
    if type(q) ~= "table" or q.map == nil or not (finite(q.x) and finite(q.y)) then return saved end
    local name = text(q.name)
    local away = q.map ~= here.map
    -- One on this map comes before any on another map.
    if away and saved then return saved end
    -- Questie's NPC the player has used: the place saved for it.
    local used
    if name and type(places) == "table" then
        local same = {}
        for key, e in pairs(places) do
            if type(e) == "table" and e.map == q.map and text(e.name) == name then same[key] = e end
        end
        local at = here
        if away then at = { map = q.map, x = q.x, y = q.y, cont = here.cont } end
        used = N.NearestOf(kind, same, at)
    end
    local size = sizeOf(here)
    local dq
    if not away then
        local w, h = size and size.w or 1, size and size.h or 1
        local dx, dy = (q.x - here.x) * w, (q.y - here.y) * h
        dq = dx * dx + dy * dy
        if saved then
            -- The nearest saved one is at least as near as the one used.
            if used then return saved end
            local sx, sy = (saved.x - here.x) * w, (saved.y - here.y) * h
            if dq >= sx * sx + sy * sy then return saved end
        end
    elseif used then
        used.yards = finite(q.yards) and q.yards >= 0 and q.yards or nil
        return used
    end
    local yards
    if away then
        yards = finite(q.yards) and q.yards >= 0 and q.yards or nil
    elseif size then
        yards = math.sqrt(dq)
    end
    return {
        kind = kind,
        key = N.QUESTIE .. ":" .. tostring(q.name) .. ":" .. tostring(q.map) .. ":" .. tostring(q.x) .. ":" .. tostring(q.y),
        name = name, map = q.map, x = q.x, y = q.y, cont = here.cont,
        yards = yards, unvisited = true, from = N.QUESTIE,
    }
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

-- Questie's nearest of kind from the profession feed, and true while its
-- list is still being gone through. The feed is looked up now, not when
-- this file loads.
local function fromQuestie(kind, client, use)
    local feedName = type(N.ProfFeed) == "table" and N.ProfFeed.NAME or nil
    if feedName == nil or type(use) ~= "function" then return nil end
    local okUse, feed = pcall(use, feedName)
    if not okUse or type(feed) ~= "table" or type(feed.Service) ~= "function" then return nil end
    local ok, q, reading = pcall(feed.Service, kind, client)
    if not ok then return nil end
    if type(q) ~= "table" then return nil, reading == true end
    return q
end

function N.Nearest(kind, client, store, use)
    if client == nil then client = ns.client end
    if store == nil then store = ns.store end
    if not KNOWN[kind] then return nil end
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, places = pcall(store.get, store, "char", N.SERVICES)
    if not ok then return nil end
    -- Nothing saved yet: Questie may still know one.
    if places == nil then places = {} end
    if type(places) ~= "table" then return nil end
    local at = ask(client, "position")
    if type(at) ~= "table" or at.map == nil then return nil end
    local zone = ask(client, "zone")
    local size = ask(client, "mapSize", at.map)
    local here = {
        map = at.map, x = at.x, y = at.y,
        cont = type(zone) == "table" and zone.cont or nil,
        size = type(size) == "table" and { w = size.w, h = size.h } or nil,
    }
    local saved = N.NearestOf(kind, places, here)
    -- Lead section 626: Questie's places only for a caller that asks, by
    -- handing in the module lookup. With none handed in the answer is as it
    -- always was: a place this character used, or none.
    if NO_NPC[kind] or type(use) ~= "function" then return saved end
    local q, reading = fromQuestie(kind, client, use)
    local place = N.NearerOf(kind, saved, q, places, here)
    if place == nil and reading then return nil, N.READING end
    return place
end
