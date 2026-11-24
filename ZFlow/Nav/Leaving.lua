local _, ns = ...
-- Z-Flow "before leaving a zone" (S37, LEDGER 143): finish the quests in
-- the player's zone before the route goes on to another zone. Ported from
-- legacy Flow 0.35.377 (Modules/Nav/Nav.lua, N.AreaSplit; setting
-- nav.zoneFirst, on by default). Pure Lua 5.1: no client calls, nothing
-- saved, nothing printed. It decides which stops wait; it moves no one and
-- casts nothing. Research: WoW/from-zen/RESEARCH-S37.md. Not tested in game.
--
-- Flow's rule. Quest stops in the player's zone come before stops in
-- another zone, except:
--   * a quest 3 or more levels above the player (levelsAbove >= 3), one too
--     low to give full XP (share < 1), or an optional stop does not hold
--     the player here;
--   * a stop in another zone within N.LEAVING_BRIEF yards of the player (a
--     short trip over the border), or a milestone (the class trainer), does
--     not wait;
--   * a stop here that depends (deps) on a stop that waits cannot hold the
--     player here: it waits too, until nothing changes.
-- The rule holds only when something holds the player here and something
-- waits.
--
-- Unknown stays unknown (F-086). Flow measured "just over the border" in
-- world yards. Here a distance across two maps is known only when the zone
-- link gives both maps an origin and a size, as Nav/Bearing.lua and
-- Nav/Guide.lua take it. With no such entry, or no player position, the
-- distance is not known and the stop waits: it is never taken as near.
--
-- N.LEAVING_BRIEF    yards for a short trip over the border (Flow: 150)
-- N.LEAVING_SETTING  the setting row, "nav.zoneFirst"; bool, default true.
--                    The caller asks it; this file does not read settings.
--
-- N.LeavingSplit(stops, zone, player, zoneOf, link) -> here, away
--                                                  -> nil, nil, reason
--   stops   a list; each { key, quest, places = { { map, x, y }, ... },
--           levelsAbove, share, optional, milestone, deps = { key, ... } }.
--           quest = true marks a quest stop (only those hold the player
--           here). x, y are shares 0..1 of map. Read only.
--   zone    the player's zone (zoneOf of the player's map)
--   player  { map, x, y } or nil
--   zoneOf  function(map) -> the zone the map belongs to, or nil (a town or
--           cave map gives its zone; CLIENT NEED client.zoneOf)
--   link    optional { [map] = { x, y, w, h } }: each map's origin in one
--           shared frame, in yards, and its size in yards
--   here, away   sets of stop keys: { [key] = true }
--   reason  "no zone"       zone is nil
--           "nothing here"  no stop holds the player here
--           "nothing away"  no stop waits
--
-- N.LeavingHold(stops, away) -> the stops not in away, in their order: what
--   the caller hands Nav/RoutePlan.lua now. away nil: all of them. A new
--   list; the stops themselves are not copied or changed.
-- N.LeavingStep(zoneName) -> { label = "Finishing <zone> first", text = true }
--   A text step: no place, no arrow. With no name, or a label over
--   N.Waypoint.LABEL_MAX bytes (never cut): "Finishing this zone first",
--   and with no name the reason "zone name unknown" comes with it. The
--   reason is for diagnostics only: a caller never shows it to the player
--   (the label already reads plainly without it).
-- N.LeavingWaits(zoneName) -> "(<zone>, after this zone)", the words after a
--   waiting stop; "(after this zone)" when the name is not known.
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.LEAVING_BRIEF = 150
N.LEAVING_SETTING = "nav.zoneFirst"

local PLAIN_STEP = "Finishing this zone first"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A place in the link's shared frame, in yards, or nil when not known.
local function inFrame(link, place)
    if type(link) ~= "table" or type(place) ~= "table" or place.map == nil then return nil end
    if not (finite(place.x) and finite(place.y)) then return nil end
    local e = link[place.map]
    if type(e) ~= "table" or not (finite(e.x) and finite(e.y) and finite(e.w) and finite(e.h)) then return nil end
    if e.w <= 0 or e.h <= 0 then return nil end
    return e.x + place.x * e.w, e.y + place.y * e.h
end

-- Yards from the player to a place, or nil when not known.
local function yards(link, player, place)
    local px, py = inFrame(link, player)
    if not px then return nil end
    local qx, qy = inFrame(link, place)
    if not qx then return nil end
    local dx, dy = px - qx, py - qy
    return math.sqrt(dx * dx + dy * dy)
end

local function zoneFor(zoneOf, map)
    if map == nil or type(zoneOf) ~= "function" then return nil end
    local ok, z = pcall(zoneOf, map)
    if ok then return z end
    return nil
end

function N.LeavingSplit(stops, zone, player, zoneOf, link)
    if zone == nil then return nil, nil, "no zone" end
    local here, away, byKey = {}, {}, {}
    for _, s in ipairs(type(stops) == "table" and stops or {}) do
        if type(s) == "table" and s.key ~= nil then
            byKey[s.key] = s
            local places = type(s.places) == "table" and s.places or {}
            local inZone, nearest = false, nil
            for _, pt in ipairs(places) do
                if type(pt) == "table" and pt.map ~= nil and zoneFor(zoneOf, pt.map) == zone then inZone = true end
                local d = yards(link, player, pt)
                if d and (not nearest or d < nearest) then nearest = d end
            end
            if inZone then
                local tooHigh = finite(s.levelsAbove) and s.levelsAbove >= 3
                local tooLow = finite(s.share) and s.share < 1
                if s.quest == true and not (tooHigh or tooLow or s.optional) then here[s.key] = true end
            elseif #places > 0 then
                local brief = nearest ~= nil and nearest < N.LEAVING_BRIEF
                if not (brief or s.milestone) then away[s.key] = true end
            end
        end
    end
    -- A stop here that needs a waiting stop first waits too, until nothing changes.
    local changed = true
    while changed do
        changed = false
        for key in pairs(here) do
            local deps = byKey[key].deps
            for _, dep in ipairs(type(deps) == "table" and deps or {}) do
                if away[dep] then
                    here[key] = nil
                    away[key] = true
                    changed = true
                    break
                end
            end
        end
    end
    if next(here) == nil then return nil, nil, "nothing here" end
    if next(away) == nil then return nil, nil, "nothing away" end
    return here, away
end

function N.LeavingHold(stops, away)
    local out = {}
    for _, s in ipairs(type(stops) == "table" and stops or {}) do
        if not (type(away) == "table" and type(s) == "table" and away[s.key]) then out[#out + 1] = s end
    end
    return out
end

local function named(zoneName)
    return type(zoneName) == "string" and zoneName ~= "" and zoneName or nil
end

function N.LeavingStep(zoneName)
    local name = named(zoneName)
    if not name then return { label = PLAIN_STEP, text = true }, "zone name unknown" end
    local label = "Finishing " .. name .. " first"
    local max = N.Waypoint and N.Waypoint.LABEL_MAX
    if finite(max) and #label > max then label = PLAIN_STEP end
    return { label = label, text = true }
end

function N.LeavingWaits(zoneName)
    local name = named(zoneName)
    if not name then return "(after this zone)" end
    return "(" .. name .. ", after this zone)"
end
