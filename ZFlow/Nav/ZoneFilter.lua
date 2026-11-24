local _, ns = ...
-- Z-Flow: the zone filter, selected zones first (parity row A1-27, lead
-- section 488). The zones you pick are yours; the route's quest stops in
-- them come first. The other zones' stops come after them with the setting
-- ZF.SETTING on, and are left out (still in your log) with it off.
-- The picks are per character (store "char", ZF.PATH); not picked yet
-- (nil, or an empty pick table): every zone is yours, as before.
-- Not here yet: a caller and a place to pick. The route order is
-- Nav/TripRoute.lua's (lane B's file; not edited), and ticking zones is a
-- new UI surface that waits for a Muse note. Until then the player sees
-- nothing. The settings row (ZF.SETTING, words ZF.ROW_LABEL and
-- ZF.ROW_HELP) is held back until the route reads it (lead section 507).
-- Compared with Flow Modules/Nav/Nav.lua N.ZoneFilter, N.ZoneLine,
-- N.SelectedZones, N.ZonesFirstOn and its "Finish the selected zones first"
-- row: the same split and words. Flow also counts steps to accept and the
-- levels per zone; Z-Flow's stops carry no level, so the line has none.
-- Not tested in game.
--
-- Pure:
--   ZF.Order(stops, selected, first, zoneOf) -> ordered, summary, left
--     stops     a list (tripRoute Current().stops or the like)
--     selected  { [zone] = true }; nil or empty: every zone
--     first     true: other zones after; else they are left out
--     zoneOf(stop) -> zone or nil (a stop with no zone always stays)
--     summary   { { zone, steps, off, later } }, most steps first
--   ZF.Line(z, nameOf) -> "Ashenvale: 3 steps - after your zones"
-- Module "zoneFilter" provides Selected(), SetZoneOn(zone, on), First(),
-- Order(stops, zoneOf).
ns.Nav = ns.Nav or {}
local N = ns.Nav
local ZF = {}
N.ZoneFilter = ZF

ZF.NAME = "zoneFilter"
ZF.PATH = "nav.zonesOn"
ZF.SETTING = "nav.zonesFirst"
-- Player-visible words, from Flow.
ZF.ROW_LABEL = "Finish the selected zones first"
ZF.ROW_HELP = "On: the route does your selected zones first, and the other zones' quests after them. "
    .. "Off (default): a zone you have not selected is left out of the route; its quests stay in your log."
ZF.LINE = "%s: %d step%s%s"
ZF.LEFT_OUT = " - LEFT OUT"
ZF.LATER = " - after your zones"

function ZF.Order(stops, selected, first, zoneOf)
    local byZone, summary, mine, later, left = {}, {}, {}, {}, 0
    if type(selected) ~= "table" or next(selected) == nil then selected = nil end
    for _, s in ipairs(type(stops) == "table" and stops or {}) do
        local zone = type(zoneOf) == "function" and zoneOf(s) or nil
        local out = zone ~= nil and type(selected) == "table" and selected[zone] ~= true
        if zone ~= nil then
            local z = byZone[zone]
            if not z then
                z = { zone = zone, steps = 0, off = out and not first, later = out and first == true }
                byZone[zone] = z
                summary[#summary + 1] = z
            end
            z.steps = z.steps + 1
        end
        if not out then mine[#mine + 1] = s
        elseif first then later[#later + 1] = s
        else left = left + 1 end
    end
    for _, s in ipairs(later) do mine[#mine + 1] = s end
    table.sort(summary, function(a, b)
        if a.steps ~= b.steps then return a.steps > b.steps end
        return tostring(a.zone) < tostring(b.zone)
    end)
    return mine, summary, left
end

function ZF.Line(z, nameOf)
    if type(z) ~= "table" or type(z.steps) ~= "number" then return nil end
    local name = type(nameOf) == "function" and nameOf(z.zone) or z.zone
    return ZF.LINE:format(tostring(name), z.steps, z.steps == 1 and "" or "s",
        z.off and ZF.LEFT_OUT or (z.later and ZF.LATER or ""))
end

function ZF.Declare(k)
    local api = {}
    local ctx

    function api.Selected()
        if not ctx then return nil end
        local ok, v = pcall(ctx.store.get, ctx.store, "char", ZF.PATH)
        if not ok or type(v) ~= "table" then return nil end
        local out = {}
        for zone, on in pairs(v) do if on == true then out[zone] = true end end
        if next(out) == nil then return nil end
        return out
    end

    function api.SetZoneOn(zone, on)
        if not ctx or zone == nil then return false end
        local copy = api.Selected() or {}
        copy[zone] = on and true or nil
        local ok, done = pcall(ctx.store.set, ctx.store, "char", ZF.PATH, copy)
        return ok and done ~= false
    end

    function api.First()
        if not ctx then return false end
        local ok, v = pcall(ctx.settings.get, ctx.settings, ZF.SETTING)
        return ok and v == true
    end

    function api.Order(stops, zoneOf)
        return ZF.Order(stops, api.Selected(), api.First(), zoneOf)
    end

    k:Module({
        name = ZF.NAME,
        needs = { "store", "settings" },
        provides = {
            Selected = function() return api.Selected() end,
            SetZoneOn = function(zone, on) return api.SetZoneOn(zone, on) end,
            First = function() return api.First() end,
            Order = function(stops, zoneOf) return api.Order(stops, zoneOf) end,
        },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.zoneFilter = ZF.Declare(ns)
