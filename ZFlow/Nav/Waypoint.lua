local _, ns = ...
-- Z-Flow waypoint: one point the player set by hand, kept in saved data.
-- Pure Lua 5.1: no client calls, no frames, no slash command. A caller
-- hands in the text typed, where the player stands and the saved table.
-- Not tested in game.
--
--   W = ns.Nav.Waypoint
--   W.Parse(text)                  -> { x, y, label } or nil, reason
--   W.Set(slot, position, text)    -> waypoint or nil, reason
--   W.Get(slot)                    -> waypoint or nil, reason
--   W.Clear(slot)                  -> true when one was there
--   W.Step(slot, position, zone)   -> step or nil
--   W.Arrive(slot, distance)       -> "arrived" or nil, reason
--   W.Slot(store)                  -> the saved table or nil
--   W.Text(waypoint)               -> "45.2, 61.8 label" or nil
--
--   text: "way x y [label]"; the word "way" (or "/way") may be left out.
--     x and y are percents, 0 to 100, on the map the player is on, written
--     with digits and at most one point: 45, 45.2. Anything else is turned
--     down with a reason: nothing is rounded, cut or guessed. A reason
--     names the token that was wrong, but never one holding "|" or a
--     control character: a reason is shown as it is.
--   waypoint = { map, x, y, label }: x and y are shares 0..1 of map, the
--     shape client.position() has; label is left out when none was typed.
--     A label is W.LABEL_MAX bytes at most (a letter outside ASCII is more
--     than one).
--   position: client.position(), { map, x, y }. Only map is used.
--   slot: a table; the waypoint is slot.waypoint. One per character: where
--     this character is heading is not where the others are (scope "char",
--     path "state.nav", with the rest of what changes while playing;
--     W.Slot asks the store for it).
--   step: { label, place = { cont, map, x, y }, radius = W.NEAR }, the shape
--     N.Guide takes as a step and N.WaypointStep gives. cont as there: the
--     player's continent, only for a waypoint on the player's own map.
--   distance: yards from the player to the waypoint (N.Guide's distance).
--     At W.NEAR or less the waypoint is cleared and the answer is "arrived".
--     A distance that is not known clears nothing.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local W = N.Waypoint or {}
N.Waypoint = W

W.NEAR = 10            -- yards. A first guess, not a measured number.
W.LABEL_MAX = 40       -- bytes
W.ARRIVED = "arrived"
W.SCOPE, W.PATH = "char", "state.nav"

W.REASON = {
    none = "no waypoint text",
    usage = "give x and y, as in: way 45.2 61.8 label",
    comma = "use a point for decimals and a space between x and y",
    label = "the label has a character that cannot be shown",
    long = "the label is too long (" .. W.LABEL_MAX .. " bytes at most)",
    map = "the map you are on is not known",
    slot = "no saved table for the waypoint",
    unset = "no waypoint is set",
    damaged = "the saved waypoint cannot be used",
    distance = "the distance to the waypoint is not known",
    far = "not there yet",
}
local R = W.REASON

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function goodMap(map)
    return type(map) == "string" and map ~= "" or finite(map)
end

-- One percent as typed -> share 0..1, or nil and a reason naming `axis`.
local function share(token, axis)
    if token:find(",", 1, true) then return nil, R.comma end
    if not (token:find("^%d+$") or token:find("^%d+%.%d+$")) then
        if token:find("[%c|]") then return nil, axis .. " is not a number" end
        return nil, axis .. " is not a number: " .. token
    end
    local n = tonumber(token)
    if not finite(n) or n > 100 then return nil, axis .. " is outside 0 to 100: " .. token end
    return n / 100
end

function W.Parse(text)
    if type(text) ~= "string" then return nil, R.none end
    local body = text:match("^%s*(.-)%s*$")
    local head, rest = body:match("^(%S+)%s*(.*)$")
    if head then
        local word = head:lower()
        if word == "way" or word == "/way" then body = rest end
    end
    if body == "" then return nil, head and R.usage or R.none end
    local xs, ys, label = body:match("^(%S+)%s+(%S+)%s*(.-)$")
    if not xs then return nil, R.usage end
    local x, whyX = share(xs, "x")
    if not x then return nil, whyX end
    local y, whyY = share(ys, "y")
    if not y then return nil, whyY end
    if label:find("[%c|]") then return nil, R.label end
    if #label > W.LABEL_MAX then return nil, R.long end
    return { x = x, y = y, label = label ~= "" and label or nil }
end

local function usable(wp)
    return type(wp) == "table" and goodMap(wp.map)
        and finite(wp.x) and wp.x >= 0 and wp.x <= 1
        and finite(wp.y) and wp.y >= 0 and wp.y <= 1
        and (wp.label == nil or type(wp.label) == "string")
end

function W.Get(slot)
    if type(slot) ~= "table" then return nil, R.slot end
    local wp = slot.waypoint
    if wp == nil then return nil, R.unset end
    if not usable(wp) then return nil, R.damaged end
    return wp
end

-- A waypoint that was set stays as it is when the new text is turned down.
function W.Set(slot, position, text)
    if type(slot) ~= "table" then return nil, R.slot end
    local parsed, why = W.Parse(text)
    if not parsed then return nil, why end
    local map = type(position) == "table" and position.map or nil
    if not goodMap(map) then return nil, R.map end
    local wp = { map = map, x = parsed.x, y = parsed.y, label = parsed.label }
    slot.waypoint = wp
    return wp
end

-- Also removes a saved waypoint that cannot be used.
function W.Clear(slot)
    if type(slot) ~= "table" or slot.waypoint == nil then return false end
    slot.waypoint = nil
    return true
end

function W.Step(slot, position, zone)
    local wp = W.Get(slot)
    if not wp then return nil end
    local cont
    if type(position) == "table" and position.map ~= nil and position.map == wp.map
        and type(zone) == "table" then
        cont = zone.cont
    end
    return {
        label = wp.label or N.WAYPOINT_LABEL or "Waypoint",
        place = { cont = cont, map = wp.map, x = wp.x, y = wp.y },
        radius = W.NEAR,
    }
end

function W.Arrive(slot, distance)
    local wp, why = W.Get(slot)
    if not wp then return nil, why end
    if not finite(distance) or distance < 0 then return nil, R.distance end
    if distance > W.NEAR then return nil, R.far end
    slot.waypoint = nil
    return W.ARRIVED
end

-- The waypoint as it is said to the player: the percents as they are
-- typed, one decimal, then the label. nil for one that cannot be used.
function W.Text(wp)
    if not usable(wp) then return nil end
    local text = ("%.1f, %.1f"):format(wp.x * 100, wp.y * 100)
    if wp.label and wp.label ~= "" then text = text .. " " .. wp.label end
    return text
end

function W.Slot(store)
    if type(store) ~= "table" or type(store.table) ~= "function" then return nil end
    local slot = store:table(W.SCOPE, W.PATH)
    if type(slot) ~= "table" then return nil end
    return slot
end
