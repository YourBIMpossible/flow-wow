local _, ns = ...

-- The cast edge (S14), ported from Flow 0.35.377
-- Modules/Rotation/CastEdge.lua: a thin bar along the bottom edge of the
-- rotation icon that fills while you cast and drains while you channel, so
-- you see when the next press will be taken without looking at the cast
-- bar. It only draws. It presses nothing.
--
--   CE.Progress(startMs, endMs, nowMs[, channel]) -> number | nil
--     Pure, as Flow: how far through the cast, 0..1; a channel counts
--     down. nil: no cast, times not known, or a cast that is over (more
--     than 5% past its end).
--   CE.Declare(k[, iconOf[, selfOf]]) -> { shown = fn }
--     The module on kernel k. iconOf() gives the rotation icon handle;
--     selfOf() the self button's row handle (FLOW-PARITY D-08: Flow drew
--     on its buff button too, CastEdge.lua:47). Either may be absent.
--
-- CLIENT NEEDS (Core/Client.lua, FLOW-PARITY D-08). Without them one
-- problem is recorded and nothing is drawn:
--   client.casting() -> startMs, endMs, channel | nil
--     the cast or channel of the player now: the 4th and 5th values of
--     UnitCastingInfo("player"), else of UnitChannelInfo("player") with
--     channel = true. The times are on the clock client.now() reads, in
--     milliseconds (warcraft.wiki.gg, API UnitCastingInfo).
--   the edge of a handle (icon or click row): handle.edge = { set(p), show(on) }
--     p is 0..1; Flow drew it 3 high, gold over black.
--
-- Not tested in game: whether this client answers UnitCastingInfo for the
-- player is not known.
local CE = {}
ns.CastEdge = CE

local D = ns.RotationDriver

CE.NAME = "castEdge"
CE.HEIGHT = 3               -- as Flow
CE.COLOR = { 1, 0.82, 0.1 } -- as Flow: gold
CE.OVER = 1.05              -- as Flow: this far past the end it is over

function CE.Progress(startMs, endMs, nowMs, channel)
    if type(startMs) ~= "number" or type(endMs) ~= "number" or type(nowMs) ~= "number" then return nil end
    if endMs <= startMs then return nil end
    local p = (nowMs - startMs) / (endMs - startMs)
    if p < 0 or p > CE.OVER then return nil end
    if p > 1 then p = 1 end
    if channel then p = 1 - p end
    return p
end

function CE.Declare(k, iconOf, selfOf)
    local client
    local shown = false
    local said = {}
    local api = {}
    function api.shown() return shown end

    local function problem(kind, text)
        if said[kind] then return end
        said[kind] = true
        k.problems:add(CE.NAME, kind, text)
    end

    local function edgeOf(of, says)
        if type(of) ~= "function" then return nil end
        local ok, h = pcall(of)
        if not ok or type(h) ~= "table" then return nil end
        local e = h.edge
        if type(e) ~= "table" or type(e.set) ~= "function" or type(e.show) ~= "function" then
            if says then problem("frame", "the icon has no edge bar; the cast edge is not drawn") end
            return nil
        end
        return e
    end

    -- Every edge to draw on: the icon's, then the self button's.
    local function edges()
        local out = {}
        out[#out + 1] = edgeOf(iconOf, true)
        out[#out + 1] = edgeOf(selfOf, false)
        return out
    end

    local function hide()
        if not shown then return end
        shown = false
        for _, e in ipairs(edges()) do pcall(e.show, false) end
    end

    local function frame()
        if k.settings:get(D.SETTING) ~= true then
            hide()
            return
        end
        local ok, startMs, endMs, channel = pcall(client.casting)
        local okNow, now = pcall(client.now)
        local p = ok and okNow and type(now) == "number"
            and CE.Progress(startMs, endMs, now * 1000, channel) or nil
        if not p then
            hide()
            return
        end
        local list = edges()
        if #list == 0 then return end
        for _, e in ipairs(list) do pcall(e.set, p) end
        if not shown then
            shown = true
            for _, e in ipairs(list) do pcall(e.show, true) end
        end
    end

    k:Module({
        name = CE.NAME,
        needs = { "client", D.NAME },
        start = function(ctx)
            client = ctx.client
            if type(client.casting) ~= "function" or type(client.now) ~= "function" then
                problem("read", "the client has no cast read; the cast edge is not drawn")
                return
            end
            client.onFrame(frame)
        end,
    })
    return api
end

-- The addon's own: on the rotation icon and the self button, when those
-- files have loaded.
ns.castEdge = CE.Declare(ns, function()
    local icon = ns.rotationIcon
    return icon and icon.handle() or nil
end, function()
    local fb = ns.flowButton
    return type(fb) == "table" and type(fb.selfRow) == "function" and fb.selfRow() or nil
end)
