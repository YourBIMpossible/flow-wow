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
--   CE.Declare(k[, iconOf]) -> { shown = fn }
--     The module on kernel k. iconOf() gives the rotation icon handle.
--
-- CLIENT NEEDS, neither is in Core/Client.lua yet. Until both are there
-- one problem is recorded and nothing is drawn:
--   client.casting() -> startMs, endMs, channel | nil
--     the cast or channel of the player now: the 4th and 5th values of
--     UnitCastingInfo("player"), else of UnitChannelInfo("player") with
--     channel = true. The times are on the clock client.now() reads, in
--     milliseconds (warcraft.wiki.gg, API UnitCastingInfo).
--   the edge of the icon handle: handle.edge = { set(p), show(on) }
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

function CE.Declare(k, iconOf)
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

    local function edge()
        if type(iconOf) ~= "function" then return nil end
        local ok, icon = pcall(iconOf)
        if not ok or type(icon) ~= "table" then return nil end
        local e = icon.edge
        if type(e) ~= "table" or type(e.set) ~= "function" or type(e.show) ~= "function" then
            problem("frame", "the icon has no edge bar; the cast edge is not drawn")
            return nil
        end
        return e
    end

    local function hide()
        if not shown then return end
        shown = false
        local e = edge()
        if e then pcall(e.show, false) end
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
        local e = edge()
        if not e then return end
        pcall(e.set, p)
        if not shown then
            shown = true
            pcall(e.show, true)
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

-- The addon's own: on the rotation icon, when that file has loaded.
ns.castEdge = CE.Declare(ns, function()
    local icon = ns.rotationIcon
    return icon and icon.handle() or nil
end)
