local _, ns = ...

-- ProfessionDot (slice 6): the profession step's destination on the
-- minimap — one solid purple dot while a profession step is live
-- (Nav/ProfStep.lua: the step the profession arrow points at), in
-- RC.ProfessionDot's purple (§8.1: purple always means
-- professions). It follows the profession arrow's switch
-- (nav.profArrow): no arrow, no dot. Where it goes is N.MinimapPin's,
-- as every minimap mark. The dot stays a dot: the arrival ring is
-- proposed, not approved, and is not built here.
--
-- LOOK ONLY: nothing is clicked, targeted, moved, saved or printed.
--
--   PD.Update(client, step, state, palette) -> report   one look;
--     state is kept between looks (the dot is made once)
--     report = { shown = true, x, y, edge, distance, r, g, b }
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
    if type(h.hollow) == "function" then
        h.hollow(pin.x * pin.x + pin.y * pin.y <= PD.ON_ICON * PD.ON_ICON)
    end
    local out = { shown = true, x = pin.x, y = pin.y, edge = pin.edge, distance = pin.distance }
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
