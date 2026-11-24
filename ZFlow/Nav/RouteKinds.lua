local _, ns = ...
-- Z-Flow: which kinds of stop the route takes (parity row A1-26, lead
-- section 547). Flow's "/flow nav include" choice, as pure rules over the
-- saved table settings.nav.kinds (account; Import/FromFlow.lua already
-- brings Flow's nav.kinds there).
-- Not here yet: a caller. The slash word and the filter on the route's
-- stops belong in Nav/TripRoute.lua (Zen is its single writer); this file
-- is what that hook calls.
-- Compared with Flow Modules/Nav/Nav.lua N.Kinds, N:Includes, N.FilterKinds
-- and N.KindsSummary: the same keys, defaults and summary words. A stop no
-- kind claims stays on the route, as in Flow. Here only quest stops are
-- told apart (new = a pick-up); Flow's lowQuests needs the quest level and
-- is left out until the route stops carry it.
-- Not tested in game.
--
-- Pure:
--   RK.Includes(kinds, key) -> bool   (the saved choice, else the default)
--   RK.Set(kinds, key, on) -> kinds | nil, why   ("all" / "none" set every key)
--   RK.KindOf(stop) -> key | nil
--   RK.Filter(stops, kinds) -> the stops whose kind is included
--   RK.Summary(kinds) -> "everything" | "nothing" | "all but X" | "N of M kinds"
ns.Nav = ns.Nav or {}
local N = ns.Nav
local RK = {}
N.RouteKinds = RK

RK.KINDS = {
    { key = "quests",    label = "quests",     default = true },
    { key = "newQuests", label = "new quests", default = true },
}
RK.DEFAULT = {}
for _, k in ipairs(RK.KINDS) do RK.DEFAULT[k.key] = k.default end

function RK.Includes(kinds, key)
    local v = type(kinds) == "table" and kinds[key] or nil
    if type(v) == "boolean" then return v end
    return RK.DEFAULT[key] == true
end

function RK.Set(kinds, key, on)
    if type(on) ~= "boolean" then return nil, "on or off" end
    local out = {}
    for k, v in pairs(type(kinds) == "table" and kinds or {}) do out[k] = v end
    if key == "all" or key == "none" then
        for _, k in ipairs(RK.KINDS) do out[k.key] = key == "all" end
        return out
    end
    if RK.DEFAULT[key] == nil then return nil, "no kind called " .. tostring(key) end
    out[key] = on
    return out
end

function RK.KindOf(stop)
    if type(stop) ~= "table" then return nil end
    if stop.kind == "pickup" then return "newQuests" end
    if stop.quest ~= nil then return "quests" end
    return nil
end

function RK.Filter(stops, kinds)
    local out = {}
    for _, s in ipairs(type(stops) == "table" and stops or {}) do
        local key = RK.KindOf(s)
        if key == nil or RK.Includes(kinds, key) then out[#out + 1] = s end
    end
    return out
end

function RK.Summary(kinds)
    local on, off = 0, {}
    for _, k in ipairs(RK.KINDS) do
        if RK.Includes(kinds, k.key) then on = on + 1 else off[#off + 1] = k.label end
    end
    if on == #RK.KINDS then return "everything" end
    if on == 0 then return "nothing" end
    if #off == 1 then return "all but " .. off[1] end
    return ("%d of %d kinds"):format(on, #RK.KINDS)
end
