local _, ns = ...
-- Readers for the values the Flow import stores and nothing else reads yet:
--   layout.buffButton (frame, scale, dockScale)   settings.buffButton.*
--   layout.rotation.scale                         layout.auction.chart
--   layout.prof.frame (per character)             settings.auction.chartClick
-- Pure Lua 5.1: no client calls. Each reader takes the layout or settings
-- table as stored, tolerates a missing or half-written one, never raises,
-- and returns new tables with every default filled in. A value that cannot
-- be used reads as its default (or nil where there is no default).
--
-- And the one writer: Stored.Adopt lands an import's settings in the
-- player's, through the settings model (Settings/Model.lua, which loads
-- after this file and is looked up when Adopt is called).
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

-- ---------------------------------------------------------------- adopt
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, one in pairs(v) do out[k] = copy(one) end
    return out
end

-- Stored.Adopt(settings, result [, confirmed [, model]]) -> settings, report
-- Lands the settings of an import in the player's settings. This is the
-- deliberate import call: nothing else writes an imported setting.
--   settings   the player's account settings as stored, or nil
--   result     what Import.FromFlow returned
--   confirmed  { ["sell.autoRepair"] = true, ... }: the vendor automations
--              the player confirmed, by Flow key. Only a true counts.
--   model      the settings model; the shipped rows when left out
-- Returns a new settings table; neither table given is changed.
--   A value Flow held is stored as found and counts as chosen, also when it
--   equals the default.
--   A value Flow did not hold is not stored: it reads as the model default.
--   A value the player already chose is kept. Landing the same import again
--   changes nothing.
--   A vendor automation Flow had off is stored off. One Flow had on is
--   stored on only when the player confirmed that one; unconfirmed it is
--   not stored and reads as off. The gate is Import.VendorGate
--   (Import/FromFlow.lua), the one the merge uses; none is kept here. The
--   model holds off any other vendor row that is on in the settings
--   (Settings/Model.lua, adopt).
--   Only settings the model has a row for are landed. Every other setting
--   the import holds is listed in dropped.
-- report = { ok, reason, taken, kept, refused, dropped,
--            vendorConfirmed, vendorLeftOff }
--   taken, kept       model keys, in row order
--   refused           { { key, reason }, ... }: values that did not fit
--   dropped           { { key, reason = "no model row" }, ... } sorted by
--                     key: where each setting sits in the settings. A
--                     setting the import maps is listed once, whole; any
--                     other table is listed value by value.
--   vendorConfirmed   sorted Flow keys: the confirmed automations whose on
--                     was stored by this call. One the player had already
--                     chosen is in kept, not here.
--   vendorLeftOff     sorted Flow keys: the automations found on and not
--                     confirmed, and the confirmed ones the model has no
--                     row for. A vendor row Flow has no key for is listed
--                     by its model key.
-- When there is nothing to land (no model, or an import that did not
-- succeed) ok is false, reason says why and the settings come back as given.
function S.Adopt(settings, result, confirmed, model)
    local report = {
        ok = true, taken = {}, kept = {}, refused = {}, dropped = {},
        vendorConfirmed = {}, vendorLeftOff = {},
    }
    local function fail(reason)
        report.ok, report.reason = false, reason .. "; nothing was changed"
        if type(settings) == "table" then return copy(settings), report end
        return {}, report
    end

    if model == nil then
        local Model = ns.Settings and ns.Settings.Model
        if not Model then return fail("the settings model is not loaded") end
        model = Model.Default()
    end
    if type(result) ~= "table" then return fail("there is no import result") end
    if result.ok ~= true or type(result.account) ~= "table" then
        return fail("the import did not succeed: " .. tostring(result.reason or "no reason given"))
    end

    -- Looked up when called: the gate is the import's, not a copy of it.
    local Import = ns.Import
    local gate = Import and Import.VendorGate
    if type(gate) ~= "function" then return fail("the import is not loaded") end

    local gated, on, off = gate({ settings = sub(result.account, "settings") or {} },
        result.vendorToConfirm, confirmed)
    local imported = sub(gated, "settings") or {}

    local leftOff = {}
    for i = 1, #off do leftOff[off[i].key] = true end
    -- agreed[model key] = true is what the model may switch on;
    -- flowKeyOf[model key] names it in the report.
    local agreed, flowKeyOf = {}, {}
    for i = 1, #on do
        local key = type(on[i].to) == "string" and on[i].to:match("^settings%.(.+)$") or nil
        if key and model:row(key) then
            agreed[key], flowKeyOf[key] = true, on[i].key
        else
            leftOff[on[i].key] = true
        end
    end

    local out, landed = model:adopt(settings, imported, agreed)
    report.taken, report.kept, report.refused = landed.taken, landed.kept, landed.refused
    for i = 1, #landed.taken do
        local flowKey = flowKeyOf[landed.taken[i]]
        if flowKey then report.vendorConfirmed[#report.vendorConfirmed + 1] = flowKey end
    end
    if type(landed.gated) == "table" then
        for i = 1, #landed.gated do leftOff[landed.gated[i]] = true end
    end
    for key in pairs(leftOff) do report.vendorLeftOff[#report.vendorLeftOff + 1] = key end
    table.sort(report.vendorConfirmed)
    table.sort(report.vendorLeftOff)

    -- What the import holds and the model has no row for.
    local mapped = {}
    if type(Import.flowMap) == "table" then
        for i = 1, #Import.flowMap do
            local row = Import.flowMap[i]
            local to = type(row) == "table" and row.to or nil
            local key = type(to) == "string" and to:match("^settings%.(.+)$") or nil
            if key then mapped[key] = true end
        end
    end
    local function walk(t, prefix)
        for name, value in pairs(t) do
            local key = prefix and (prefix .. "." .. tostring(name)) or tostring(name)
            if not model:row(key) then
                if type(value) == "table" and not mapped[key] then
                    walk(value, key)
                else
                    report.dropped[#report.dropped + 1] = { key = key, reason = "no model row" }
                end
            end
        end
    end
    walk(imported, nil)
    table.sort(report.dropped, function(a, b) return a.key < b.key end)
    return out, report
end
