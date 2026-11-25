local _, ns = ...

-- MinimapPin (G43): a pin on the minimap at the waypoint the player set
-- (Nav/Waypoint.lua, char "state.nav"). Where the pin goes is worked out by
-- N.MinimapPin (Nav/MinimapPin.lua); this module reads the client, asks
-- that, and moves one pin. It only shows: nothing is clicked, targeted or
-- moved for the player, and nothing is saved or printed. The waypoint is
-- read, never made, changed or cleared here.
--
-- CLIENT NEED, both. On a client without them the module does nothing.
--   client.minimap() -> { size, radius, rotates, square } or nil
--     size     how wide the minimap frame is, in its own units
--     radius   yards from the middle to the edge at the zoom now. Only
--              what the client itself says: no table of yards per zoom
--              step lives in this addon. Not known: nil, and no pin.
--     rotates  true or false: the minimap turns with the player
--     square   true for a square minimap, else nil
--   client.minimapPin(spec) -> handle or nil
--     spec = { name, size }: one small mark on the minimap, hidden when
--     made. It takes no mouse.
--     handle.place(x, y, edge)  shows it, its middle x to the right and y
--                               up from the middle of the minimap; edge is
--                               true when the place is off the minimap
--     handle.hide()
--
--   FLOW-PARITY A2-23: with no waypoint set, the pin shows where the quest
--   arrow points now, its step of any kind (the arrow's Heading, UI/
--   Arrow.lua), as legacy Flow's pin sits at the arrow's point
--   (Modules/Nav/MinimapPin.lua P:Update, :384-408). Your waypoint first.
--   MinimapPin.Target(waypoint, heading, followed) -> place, source
--     | nil, Pin.NONE (pure). source "waypoint" (yours, or a party member
--     you follow: followed true, as Flow :397-398) or "step"; the report
--     carries it so the drawing lane can colour the pin.
--   MinimapPin.Update(client, store, state[, heading[, followed]]) -> report
--     state: a table kept between looks (the handle is made once).
--     report = { shown = true, x, y, edge, distance }
--            or { shown = false, reason }
--       reason: "no waypoint", "no pin frame", or a reason of N.MinimapPin
--   MinimapPin.Declare(k) -> api    declares the module and its setting
--     Pin.SETTING (on at first; lead section 519 slice 2): off, the pin is
--     hidden and no look reads the client; the report's reason is Pin.OFF.
--     Only this pin: the arrow and the world map are not touched.
--     api.last()    the report of the last look, nil before the first
--     api.update()  looks now; nil before the module has started
--   ns.use(MinimapPin.NAME) -> { Last = api.last }
--
-- Not tested in game: both client reads are asked for, not yet there.

local Pin = ns.MinimapPin or {}
ns.MinimapPin = Pin

Pin.NAME = "minimapPin"
Pin.SETTING = "nav.waypointPin"
Pin.LABEL = "Show your waypoint or the next step on the minimap"
Pin.HELP = "Puts a dot on the minimap for a waypoint you set yourself or, without one, the step the arrow points at, so you can see it without opening the map."
Pin.OFF = "turned off"
Pin.NONE = "no waypoint"   -- nothing to pin: no waypoint, and the arrow points nowhere
Pin.EVERY = 0.1        -- seconds between looks. A first guess.
Pin.SIZE = 12          -- how wide the pin is. A first guess.

local N = ns.Nav

-- One read of the client; nil when it has no such read. An error is not
-- caught: the kernel counts it against the module.
local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

local function hidden(state, reason)
    if state.handle and state.shown then
        state.handle.hide()
    end
    state.shown = false
    return { shown = false, reason = reason }
end

-- The pin frame, made once. A client that gives none is not asked again.
local function handleOf(client, state)
    if state.handle or state.tried then return state.handle end
    state.tried = true
    local h = ask(client, "minimapPin", { name = tostring(ns.id.addon) .. "MinimapPin", size = Pin.SIZE })
    if type(h) == "table" and type(h.place) == "function" and type(h.hide) == "function" then
        state.handle = h
    end
    return state.handle
end

local function placed(p)
    return type(p) == "table" and p.map ~= nil and type(p.x) == "number" and type(p.y) == "number"
        and p.x == p.x and p.y == p.y
end

function Pin.Target(waypoint, heading, followed)
    if placed(waypoint) then return waypoint, "waypoint" end
    if placed(heading) then
        if followed == true then return heading, "waypoint" end
        return heading, "step"
    end
    return nil, Pin.NONE
end

-- Lead section 749: Nav/Follow.lua's Step reads the party (client.party)
-- on every call. The pin asks it at most every FOLLOW_EVERY seconds, and in
-- a fight (or a fight not known) not at all: the answer it holds stands
-- (nothing held: not followed). memo is the pin's own table; now the
-- client's clock (nil: asked each look); read() -> truthy when following.
Pin.FOLLOW_EVERY = 0.5
function Pin.Followed(memo, now, fight, read)
    if type(memo) ~= "table" then memo = {} end
    if fight ~= false then return memo.value == true end
    if type(now) == "number" and type(memo.at) == "number" and now - memo.at < Pin.FOLLOW_EVERY then
        return memo.value == true
    end
    local ok, v = pcall(read)
    memo.value = false
    if ok and v then memo.value = true end
    memo.at = now
    return memo.value
end

function Pin.Update(client, store, state, heading, followed)
    if type(state) ~= "table" then state = {} end
    local W = N.Waypoint
    local slot
    if type(store) == "table" and type(store.get) == "function" then
        slot = store:get(W.SCOPE, W.PATH)
    end
    local target, source = Pin.Target(W.Get(slot), heading, followed)
    if not target then return hidden(state, source) end

    local seen = ask(client, "minimap")
    local mini
    if type(seen) == "table" then
        mini = {
            size = seen.size, radius = seen.radius,
            rotates = seen.rotates, square = seen.square,
            inset = Pin.SIZE / 2,
        }
    end
    local pin, why = N.MinimapPin(target, {
        position = ask(client, "position"),
        size = ask(client, "mapSize", target.map),
        facing = ask(client, "facing"),
    }, mini)
    if not pin then return hidden(state, why) end

    local handle = handleOf(client, state)
    if not handle then return hidden(state, "no pin frame") end
    handle.place(pin.x, pin.y, pin.edge)
    state.shown = true
    return { shown = true, x = pin.x, y = pin.y, edge = pin.edge, distance = pin.distance, source = source }
end

-- Declares the module on kernel k. On a client without the two reads it
-- starts and does nothing: no look is ever taken.
function Pin.Declare(k)
    local api = {}
    local last, look
    local state = {}
    function api.last() return last end
    function api.update()
        if not look then return nil end
        return look()
    end
    k:Setting({ key = Pin.SETTING, scope = "account", type = "bool", default = true,
        label = Pin.LABEL, group = "travel.map", help = Pin.HELP,
        synonyms = { "waypoint", "minimap", "dot", "pin" } })

    -- Off only when the setting says false; a read that fails is not off.
    local function off(s)
        if type(s) ~= "table" or type(s.get) ~= "function" then return false end
        local ok, v = pcall(s.get, s, Pin.SETTING)
        return ok and v == false
    end

    k:Module({
        name = Pin.NAME,
        needs = { "client", "store", "sched", "settings" },
        provides = { Last = api.last },
        start = function(ctx)
            local client = ctx.client
            if type(client.minimap) ~= "function" or type(client.minimapPin) ~= "function" then return end
            look = function()
                if off(ctx.settings) then
                    last = hidden(state, Pin.OFF)
                    return last
                end
                -- A2-23: where the quest arrow points now (its provides).
                local heading
                local arrow = k.use and k.use("arrow")
                if type(arrow) == "table" and type(arrow.Heading) == "function" then
                    local okH, h = pcall(arrow.Heading)
                    if okH then heading = h end
                end
                -- A party member you point at (Nav/Follow.lua) is a waypoint's
                -- colour; read at most every FOLLOW_EVERY, never in a fight.
                local now, fight
                if type(client.now) == "function" then
                    local okN, v = pcall(client.now)
                    if okN and type(v) == "number" then now = v end
                end
                if type(client.inCombat) == "function" then
                    local okC, v = pcall(client.inCombat)
                    if okC and type(v) == "boolean" then fight = v end
                end
                state.follow = state.follow or {}
                local followed = Pin.Followed(state.follow, now, fight, function()
                    local follow = k.use and k.use("follow")
                    if type(follow) ~= "table" or type(follow.Step) ~= "function" then return false end
                    return type(follow.Step()) == "table"
                end)
                last = Pin.Update(client, ctx.store, state, heading, followed)
                return last
            end
            ctx.sched:every(Pin.NAME, Pin.EVERY, look)
        end,
        stop = function()
            look = nil
            last = hidden(state, "stopped")
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.minimapPin = Pin.Declare(ns)
