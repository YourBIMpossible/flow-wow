local _, ns = ...
-- Readers for the values the Flow import stores and nothing else reads yet:
--   layout.buffButton (frame, scale, dockScale)   settings.buffButton.*
--   layout.rotation.scale                         layout.auction.chart
--   layout.prof.frame (per character)             settings.auction.chartClick
-- Pure Lua 5.1: no client calls. Each reader takes the layout or settings
-- table as stored, tolerates a missing or half-written one, never raises,
-- and returns new tables with every default filled in. A value that cannot
-- be used reads as its default (or nil where there is no default).
ns.Import = ns.Import or {}
local S = {}
ns.Import.Stored = S

-- Exact values carried over from Flow.
S.SCALE_MIN, S.SCALE_MAX, S.SCALE_DEFAULT = 0.5, 2, 1
S.SCALE_GRAIN = 0.05 -- sizes are kept to the nearest twentieth

-- ---------------------------------------------------------------- helpers
local SPOT = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function sub(t, key)
    local v = type(t) == "table" and t[key]
    if type(v) == "table" then return v end
    return nil
end

-- A saved point that can be used, or nil. { anchor, relative anchor, x, y }.
-- The relative anchor defaults to the anchor; x and y default to 0.
local function goodPoint(p)
    if type(p) ~= "table" or type(p[1]) ~= "string" or not SPOT[p[1]] then return nil end
    local r = p[2]
    if r == nil then
        r = p[1]
    elseif type(r) ~= "string" or not SPOT[r] then
        return nil
    end
    local x, y = p[3], p[4]
    if x == nil then x = 0 end
    if y == nil then y = 0 end
    if not finite(x) or not finite(y) then return nil end
    return { p[1], r, x, y }
end

-- A saved size that can be used (a finite number above zero), rounded to the
-- grain and held within the limits; nil for anything else.
local function goodScale(v)
    if not finite(v) or v <= 0 then return nil end
    local s = math.floor(v / S.SCALE_GRAIN + 0.5) * S.SCALE_GRAIN
    return math.max(S.SCALE_MIN, math.min(S.SCALE_MAX, s))
end

-- A saved key binding that can be used (a string with something in it), or nil.
local function goodKey(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

S.Point = goodPoint
S.Scale = goodScale

-- ---------------------------------------------------------------- layout
-- layout.buffButton: where the self button stands and how big it is.
--   frame      a point, or nil (never moved)
--   scale      its size on its own; 1 when unset
--   dockScale  its size while docked, or nil (never set: see DockScale)
function S.BuffButtonLayout(layout)
    local b = sub(layout, "buffButton") or {}
    return {
        frame = goodPoint(b.frame),
        scale = goodScale(b.scale) or S.SCALE_DEFAULT,
        dockScale = goodScale(b.dockScale),
    }
end

-- The size the docked self button takes: the saved one, else the size of
-- the main button (main), else 1.
function S.DockScale(layout, main)
    local b = sub(layout, "buffButton") or {}
    return goodScale(b.dockScale) or goodScale(main) or S.SCALE_DEFAULT
end

-- layout.rotation.scale: the size of the main button; 1 when unset.
function S.RotationScale(layout)
    local r = sub(layout, "rotation") or {}
    return goodScale(r.scale) or S.SCALE_DEFAULT
end

-- layout.auction.chart: where the price chart stands, or nil (never moved).
function S.AuctionChart(layout)
    local a = sub(layout, "auction") or {}
    return goodPoint(a.chart)
end

-- layout.prof.frame, from the character layout: where the profession window
-- stands for this character, or nil (never moved).
function S.ProfFrame(charLayout)
    local p = sub(charLayout, "prof") or {}
    return goodPoint(p.frame)
end

-- ---------------------------------------------------------------- settings
-- settings.auction.chartClick: clicking a price opens the chart. On unless
-- switched off.
function S.AuctionChartClick(settings)
    local a = sub(settings, "auction") or {}
    return a.chartClick ~= false
end

-- settings.buffButton: the self button. Defaults as Flow reads them.
--   enabled     off unless true
--   key, key2   key bindings, or nil; key2 is dropped when it repeats key
--   keys        the bindings in order, as a list (empty when there are none)
--   dock        docked unless false
--   always      off unless true
--   care        on unless false
--   keepOnMain  off unless true
function S.BuffButtonSettings(settings)
    local b = sub(settings, "buffButton") or {}
    local key, key2 = goodKey(b.key), goodKey(b.key2)
    if key2 == key then key2 = nil end
    local keys = {}
    if key then keys[#keys + 1] = key end
    if key2 then keys[#keys + 1] = key2 end
    return {
        enabled = b.enabled == true,
        key = key, key2 = key2, keys = keys,
        dock = b.dock ~= false,
        always = b.always == true,
        care = b.care ~= false,
        keepOnMain = b.keepOnMain == true,
    }
end
