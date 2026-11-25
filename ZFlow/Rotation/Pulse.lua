local _, ns = ...

-- The suggestion pulse (S14), ported from Flow 0.35.377 Modules/Pulse.lua:
-- one colour and one beat for everything that says "press this". Everything
-- that pulses is on the same beat, because the brightness is worked out
-- from the clock alone.
--
-- It only changes how bright a thing is drawn. It presses nothing.
--
--   P.Alpha(now[, period, low]) -> number   pure: the brightness at a
--               moment; 1 at the start of a beat, low halfway. A moment
--               that is not a number gives 1 (steady, not a guess).
--   P.New({ onFrame, now }) -> p            a set of things that pulse
--     p.add(region) -> true | false   region: a table with setAlpha(a).
--                                     false: it cannot be dimmed
--     p.remove(region[, alpha])       stops it and leaves it at alpha (1)
--     p.has(region), p.count(), p.running()
--     p.tick()                        sets every region to the beat now
--   The frame listener is asked for at the first add and cancelled when
--   the set is empty, so nothing runs while nothing pulses.
--   P.Declare(k[, iconOf]) -> { add, remove, has, count, lit }
--     The module on kernel k. iconOf() gives the rotation icon handle.
--     While the driver suggests a spell, the glow of the handle pulses:
--       handle.glow = { setAlpha(a), show(on)[, setColor(r, g, b)] }
--     CLIENT NEED: the icon handle of Core/Client.lua has no glow yet.
--     Until it has, one problem is recorded and nothing pulses.
--
-- Not tested in game.
local P = {}
ns.Pulse = P

local D = ns.RotationDriver

P.NAME = "pulse"
P.COLOR = { 1, 0.5, 0 } -- as Flow: legendary orange
P.PERIOD = 0.9          -- as Flow: seconds from bright to dim and back
P.LOW = 0.3             -- as Flow: the dimmest it gets

function P.Alpha(now, period, low)
    if type(now) ~= "number" then return 1 end
    if type(period) ~= "number" or period <= 0 then period = P.PERIOD end
    if type(low) ~= "number" then low = P.LOW end
    local phase = (now % period) / period
    local wave = 0.5 + 0.5 * math.cos(phase * 2 * math.pi)
    return low + (1 - low) * wave
end

local function put(region, alpha)
    if type(region.setAlpha) ~= "function" then return false end
    return (pcall(region.setAlpha, alpha))
end

function P.New(opts)
    opts = type(opts) == "table" and opts or {}
    local onFrame, now = opts.onFrame, opts.now
    local set, n = {}, 0
    local listening, cancel = false, nil
    local p = {}

    function p.tick()
        if n == 0 then return end
        local t
        if type(now) == "function" then
            local ok, v = pcall(now)
            if ok then t = v end
        end
        local alpha = P.Alpha(t)
        for region in pairs(set) do put(region, alpha) end
    end

    function p.add(region)
        if type(region) ~= "table" or type(region.setAlpha) ~= "function" then return false end
        if set[region] then return true end
        set[region] = true
        n = n + 1
        if not listening and type(onFrame) == "function" then
            local ok, c = pcall(onFrame, p.tick)
            if ok then
                listening = true
                cancel = type(c) == "function" and c or nil
            end
        end
        p.tick()
        return true
    end

    function p.remove(region, alpha)
        if region == nil or not set[region] then return false end
        set[region] = nil
        n = n - 1
        put(region, type(alpha) == "number" and alpha or 1)
        -- With no cancel given the listener stays; tick does nothing while
        -- the set is empty.
        if n == 0 and cancel then
            local c = cancel
            cancel, listening = nil, false
            pcall(c)
        end
        return true
    end

    function p.has(region) return region ~= nil and set[region] == true end
    function p.count() return n end
    function p.running() return listening end
    return p
end

function P.Declare(k, iconOf)
    local pulse, lit
    local said = false
    local api = {}
    function api.add(region) return pulse ~= nil and pulse.add(region) end
    function api.remove(region, alpha) return pulse ~= nil and pulse.remove(region, alpha) end
    function api.has(region) return pulse ~= nil and pulse.has(region) end
    function api.count() return pulse and pulse.count() or 0 end
    -- The glow that pulses for the suggestion now, or nil.
    function api.lit() return lit end

    -- The glow, or nil; the second value is true when there is an icon
    -- and it has no glow.
    local function glow()
        if type(iconOf) ~= "function" then return nil end
        local ok, icon = pcall(iconOf)
        if not ok or type(icon) ~= "table" then return nil end
        local g = icon.glow
        if type(g) ~= "table" or type(g.setAlpha) ~= "function" then return nil, true end
        return g
    end

    local function dark()
        if not lit then return end
        local g = lit
        lit = nil
        pulse.remove(g, 1)
        if type(g.show) == "function" then pcall(g.show, false) end
    end

    local function onView(view)
        if not pulse then return end
        local on = k.settings:get(D.SETTING) == true
            and type(view) == "table" and type(view.suggestion) == "table"
            and type(view.suggestion.spell) == "string" and view.suggestion.spell ~= ""
        if not on then
            dark()
            return
        end
        local g, lacking = glow()
        if not g then
            dark()
            if lacking and not said then
                said = true
                k.problems:add(P.NAME, "frame", "the icon has no glow; the suggestion does not pulse")
            end
            return
        end
        if lit == g then return end
        dark()
        if type(g.setColor) == "function" then pcall(g.setColor, P.COLOR[1], P.COLOR[2], P.COLOR[3]) end
        if type(g.show) == "function" then pcall(g.show, true) end
        if pulse.add(g) then lit = g end
    end

    k:Module({
        name = P.NAME,
        needs = { "client", "bus", D.NAME },
        -- D-32: the one set, for every other thing that pulses (as Flow's
        -- one driver, Modules/Pulse.lua:34): add, remove, has, count, lit.
        provides = { add = api.add, remove = api.remove, has = api.has, count = api.count, lit = api.lit },
        start = function(ctx)
            local client = ctx.client
            pulse = P.New({ onFrame = client.onFrame, now = client.now })
            ctx.bus:on(P.NAME, D.EVENT, onView)
        end,
    })
    return api
end

-- The addon's own: on the rotation icon, when that file has loaded.
ns.pulse = P.Declare(ns, function()
    local icon = ns.rotationIcon
    return icon and icon.handle() or nil
end)
