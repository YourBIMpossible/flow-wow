local _, ns = ...

-- ProfessionDot (slice 6): the profession step's destination on the
-- minimap — one solid purple dot while a profession step is live
-- (Nav/ProfStep.lua: the step the profession arrow points at), in
-- RC.ProfessionDot's purple (§8.1: purple always means
-- professions). It follows the profession arrow's switch
-- (nav.profArrow): no arrow, no dot. Where it goes is N.MinimapPin's,
-- as every minimap mark.
--
-- THE ARRIVAL RING (owner's word, 2026-11-26: build it): when the
-- player reaches the profession destination — inside the step's own
-- reach (its radius), or the arrow's 24 yards for a step with no
-- radius of its own — the dot becomes a purple ring: the pin is told
-- hollow, so the player marker shows through it, and the report says
-- ring. Reaching the place does not complete the step: training,
-- buying or crafting there is still the step's own business, and
-- nothing here touches it.
--
-- CLIENT NEED (the lead's): the pin's hollow call in Core/Client.lua
-- is an empty body over a named gap (no ring texture exists in Flow,
-- Questie or Z-Flow). Until the lead names a texture or draws the
-- ring there, the pin is told hollow and still draws the solid dot;
-- this file's half — when to ring, and the purple — is complete.
--
-- LOOK ONLY: nothing is clicked, targeted, moved, saved or printed.
--
--   PD.Update(client, step, state, palette) -> report   one look;
--     state is kept between looks (the dot is made once)
--     report = { shown = true, x, y, edge, distance, r, g, b,
--                ring = true when the destination is reached }
--            or { shown = false, reason }
--   PD.Declare(k, diag) -> api   api.Refresh(), api.Shown(), api.last()
-- Not tested in game.

local PD = {}
ns.ProfessionDot = PD

PD.NAME = "professionDot"
PD.EVERY = 0.1     -- seconds between looks, as the area marks'
PD.SIZE = 12       -- how wide the dot is, as the waypoint pin. A first guess.
PD.ON_ICON = 6     -- the dot's middle this close (minimap units) to the
                   -- minimap's middle sits on the character icon: half
                   -- the dot. A first guess.
local N = ns.Nav
-- yards: the reach for a step with no radius of its own, the arrow's own
-- at-point, read once here as the slice 4 files do.
local at = 24
if N and N.AT_POINT then at = N.AT_POINT end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

local function hidden(state, reason)
    if state.handle and state.placed then state.handle.hide() end
    state.placed = false
    return { shown = false, reason = reason }
end

-- The dot's frame, made once, in the purple of its first look.
local function handleOf(client, state, colour)
    if state.handle or state.tried then return state.handle end
    state.tried = true
    local spec = { size = PD.SIZE }
    if colour then spec.r, spec.g, spec.b = colour[1], colour[2], colour[3] end
    local h = ask(client, "minimapPin", spec)
    if type(h) == "table" and type(h.place) == "function" and type(h.hide) == "function" then
        state.handle = h
    end
    return state.handle
end

function PD.Update(client, step, state, palette)
    if type(state) ~= "table" then state = {} end
    local place
    if type(step) == "table" then place = step.place end
    if type(place) ~= "table" then return hidden(state, "no profession step") end
    local seen = ask(client, "minimap")
    if type(seen) ~= "table" then return hidden(state, "no minimap") end
    local mini = { size = seen.size, radius = seen.radius, rotates = seen.rotates,
                   square = seen.square, inset = PD.SIZE / 2 }
    local pin = N.MinimapPin(place, { position = ask(client, "position"),
        size = ask(client, "mapSize", place.map), facing = ask(client, "facing") }, mini)
    if not pin then return hidden(state, "off the minimap") end
    local RC = ns.RouteColor
    local colour
    if type(RC) == "table" and type(RC.ProfessionDot) == "function" then
        local r, g, b = RC.ProfessionDot(palette)
        if r then colour = { r, g, b } end
    end
    local h = handleOf(client, state, colour)
    if not h then return hidden(state, "no pin frame") end
    h.place(pin.x, pin.y, pin.edge)
    state.placed = true
    if colour then
        local prev = state.colour
        if prev and (prev[1] ~= colour[1] or prev[2] ~= colour[2] or prev[3] ~= colour[3])
            and type(h.colour) == "function" then
            h.colour(colour[1], colour[2], colour[3])
        end
        state.colour = colour
    end
    -- Reached: inside the step's own reach, or the arrow's for a step
    -- with no radius of its own.
    local arrived = false
    if type(pin.distance) == "number" then
        local reach = at
        if type(step.radius) == "number" and step.radius > 0 then reach = step.radius end
        arrived = pin.distance < reach
    end
    if type(h.hollow) == "function" then
        local onIcon = pin.x * pin.x + pin.y * pin.y <= PD.ON_ICON * PD.ON_ICON
        h.hollow(onIcon or arrived)
    end
    local out = { shown = true, x = pin.x, y = pin.y, edge = pin.edge, distance = pin.distance }
    if arrived then out.ring = true end
    if colour then out.r, out.g, out.b = colour[1], colour[2], colour[3] end
    return out
end

function PD.Declare(k, diag)
    local api = {}
    local ctx
    local state = {}
    local last
    function api.last() return last end
    function api.Shown() return last ~= nil and last.shown == true end

    local function client()
        if ctx and ctx.client then return ctx.client end
        return k.client
    end

    function api.Refresh()
        if not ctx then return end
        local s = ctx.settings
        local on = true
        if type(s) == "table" and type(s.get) == "function" then
            local okA, a = pcall(s.get, s, "nav.profArrow")
            if okA and a == false then on = false end
        end
        local step
        if on then
            local ps = k.use and k.use(N.PROF_STEP or "profStep")
            if type(ps) == "table" and type(ps.Step) == "function" then
                local ok, v = pcall(ps.Step)
                if ok then step = v end
            end
        end
        local palette
        if type(s) == "table" and type(s.get) == "function" then
            local okP, p = pcall(s.get, s, "arrow.palette")
            if okP and type(p) == "string" then palette = p end
        end
        last = PD.Update(client(), step, state, palette)
    end

    k:Module({
        name = PD.NAME,
        needs = { "client", "settings" },
        ticks = { { every = PD.EVERY, when = "always", run = function() api.Refresh() end } },
        start = function(c) ctx = c end,
        stop = function() last = PD.Update(nil, nil, state, nil) end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.professionDot = PD.Declare(ns, ns.diag)
