local _, ns = ...
-- Z-Flow: the corpse-run hint (parity row A1-14, lead section 485). While
-- dead, the words that say what to do next, and a pin on the minimap at
-- the corpse.
--   dead, not released (client.ghost a plain false): CH.RELEASE
--   a ghost, the corpse on another map:               CH.ELSEWHERE
--   a ghost, at the corpse (within CH.HERE_YARDS):    CH.HERE
--   otherwise: no hint (alive, not known, or on the way).
-- THE PIN: N.MinimapPin (Nav/MinimapPin.lua, read, not changed) with the
-- corpse as the target, in a frame of its own (CH.PIN_NAME), hidden when
-- there is no corpse place or the player is not a ghost.
-- Not here yet: a caller for the words. The arrow's corpse step still says
-- its own lines; using Hint() there is a later hook.
-- Compared with Flow Modules/Nav/Nav.lua N:ShowCorpse: the same three
-- lines. Flow's title "Your corpse" is not taken (the arrow's "Corpse"
-- stays), and Flow's pin is red: the client here gives no pin colour.
-- LOOK ONLY: nothing is released or resurrected. Not tested in game.
--
-- Pure:
--   CH.Words(ghost, corpse, distance) -> a hint line or nil
--     ghost    client.ghost(): true, false or nil
--     corpse   client.corpse(): a place, false (another map) or nil
--     distance yards to the corpse, or nil when not known
-- Module "corpseHint" provides Hint(), Pin() (the last pin report).
ns.Nav = ns.Nav or {}
local N = ns.Nav
local CH = {}
N.CorpseHint = CH

CH.NAME = "corpseHint"
CH.EVERY = 0.1
CH.SIZE = 12
CH.HERE_YARDS = 5
CH.PIN_NAME = "CorpsePin"
-- Player-visible words, from Flow N:ShowCorpse.
CH.RELEASE = "Release your spirit, then follow the red arrow"
CH.ELSEWHERE = "On another map: follow the graveyard path"
CH.HERE = "Here: resurrect"

local function place(v)
    return type(v) == "table" and type(v.map) == "number" and type(v.x) == "number" and type(v.y) == "number"
end

function CH.Words(ghost, corpse, distance)
    if ghost == false then return CH.RELEASE end
    if ghost ~= true then return nil end
    if corpse == false then return CH.ELSEWHERE end
    if place(corpse) and type(distance) == "number" and distance <= CH.HERE_YARDS then return CH.HERE end
    return nil
end

function CH.Declare(k)
    local api = {}
    local ctx
    local state = {}
    local last

    local function ask(name, ...)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    local function hide(reason)
        if state.handle and state.shown then pcall(state.handle.hide) end
        state.shown = false
        return { shown = false, reason = reason }
    end

    local function handle()
        if state.handle or state.tried then return state.handle end
        state.tried = true
        local h = ask("minimapPin", { name = tostring(ns.id.addon) .. CH.PIN_NAME, size = CH.SIZE })
        if type(h) == "table" and type(h.place) == "function" and type(h.hide) == "function" then state.handle = h end
        return state.handle
    end

    -- The corpse pin; also the distance the words use.
    local function look()
        if ask("ghost") ~= true then return hide("not a ghost") end
        local at = ask("corpse")
        if not place(at) then return hide("no corpse place") end
        local seen = ask("minimap")
        local mini
        if type(seen) == "table" then
            mini = { size = seen.size, radius = seen.radius, rotates = seen.rotates, square = seen.square, inset = CH.SIZE / 2 }
        end
        local pin, why = N.MinimapPin({ map = at.map, x = at.x, y = at.y }, {
            position = ask("position"), size = ask("mapSize", at.map), facing = ask("facing"),
        }, mini)
        if not pin then return hide(why) end
        local h = handle()
        if not h then return { shown = false, reason = "no pin frame", distance = pin.distance } end
        h.place(pin.x, pin.y, pin.edge)
        state.shown = true
        return { shown = true, x = pin.x, y = pin.y, edge = pin.edge, distance = pin.distance }
    end

    function api.Hint()
        if not ctx then return nil end
        local r = look()
        return CH.Words(ask("ghost"), ask("corpse"), r and r.distance)
    end

    function api.Pin() return last end

    k:Module({
        name = CH.NAME,
        needs = { "client", "sched" },
        provides = {
            Hint = function() return api.Hint() end,
            Pin = function() return api.Pin() end,
        },
        start = function(c)
            ctx = c
            c.sched:every(CH.NAME, CH.EVERY, function() last = look() end)
        end,
        stop = function()
            last = hide("stopped")
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.corpseHint = CH.Declare(ns)
