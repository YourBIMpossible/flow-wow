local _, ns = ...
-- Z-Flow hearthstone step (G46): "hearth to <place>", said when using the
-- hearthstone saves travel to the step the guide is on. Made only from the
-- bind name the client gives and the bind place this player saved
-- (Nav/HearthSeen.lua). Nothing is authored here and nothing is printed.
-- It only says so: nothing uses the stone for the player. Pure but for
-- N.HearthStepFrom, which reads the client and the store it is handed.
-- Not tested in game.
--
-- N.HEARTH_BIND   the saved bind place, char scope: "learned.places.bind"
--                 = { name, map, x, y, seen }
-- N.HEARTH_SAVES  yards the stone must save on one map. A first guess.
-- N.HEARTH_PLAIN  the text when the name is not known or does not fit
--
-- N.HearthStep(bind, target, here, cooldown) -> step, reason
--   bind      { name, map, x, y }: the name of the bind place and where it
--             is (x, y shares 0..1 of map). Any may be absent.
--   target    { map, x, y }: the place of the step the guide is on
--   here      { position = { map, x, y },
--               mapSize = function(map) -> { w, h } in yards, or nil }
--   cooldown  seconds until the stone is ready: 0 ready, nil not known
--
--   step = { label, text = true, lands = { map, x, y }, saves }
--   A text step: it has no place, so no arrow points anywhere for it.
--   label is "Hearth to <name>"; N.HEARTH_PLAIN when the name is not known
--   or the label would be over N.Waypoint.LABEL_MAX bytes (never cut).
--   lands is where the stone takes the player, when known. saves is the
--   yards saved, straight lines, when both are on the map of the target.
--
--   No step, and the reason, for the first of these that holds:
--     "no target"         target has no map or no x, y in 0..1
--     "cooldown unknown"  cooldown is not a number: never taken as ready
--     "on cooldown"       cooldown is above 0
--   Then, where the bind place is not known (no map, or no x, y in 0..1):
--   the step is text only, { label, text = true }, and the reason
--   "bind place unknown" comes with it: whether it saves travel is not
--   known and is not claimed. The caller decides whether to show it.
--   Then no step for:
--     "other map"         the bind place is not on the map of the target
--     "position unknown"  the map or the x, y of the player is not known
--     "size unknown"      all on one map, and its size in yards is not known
--     "no saving"         all on one map, and less than N.HEARTH_SAVES saved
--   A player on another map than the target, with the bind place on the map
--   of the target, gets the step with no saves: how much is not known.
--
-- N.HearthStepFrom(target, client, store) -> the same, read from
--   client.bindLocation(), client.hearthCooldown() (CLIENT NEED, both),
--   client.position(), client.mapSize(map) and the saved bind place. The
--   saved place is used only when its name is the name the client gives
--   now: a home made while the addon was not there is not known. client
--   and store default to the ones of the addon. It writes nothing; a read
--   that fails is "not known".
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.HEARTH_BIND = "learned.places.bind"
N.HEARTH_SAVES = 300
N.HEARTH_PLAIN = "Use your hearthstone"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function placed(p)
    return type(p) == "table" and p.map ~= nil and share(p.x) and share(p.y)
end

local function labelOf(name)
    if name then
        local label = "Hearth to " .. name
        if #label <= (N.Waypoint and N.Waypoint.LABEL_MAX or 40) then return label end
    end
    return N.HEARTH_PLAIN
end

-- The size of a map in yards, or nil when it is not known.
local function sizeOf(here, map)
    if type(here.mapSize) ~= "function" then return nil end
    local ok, size = pcall(here.mapSize, map)
    if not ok or type(size) ~= "table" then return nil end
    if not (finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0) then return nil end
    return size
end

local function yards(a, b, size)
    local dx, dy = (a.x - b.x) * size.w, (a.y - b.y) * size.h
    return math.sqrt(dx * dx + dy * dy)
end

function N.HearthStep(bind, target, here, cooldown)
    if type(bind) ~= "table" then bind = {} end
    if type(here) ~= "table" then here = {} end
    if not placed(target) then return nil, "no target" end
    if not finite(cooldown) then return nil, "cooldown unknown" end
    if cooldown > 0 then return nil, "on cooldown" end

    local step = { label = labelOf(text(bind.name)), text = true }
    if not placed(bind) then return step, "bind place unknown" end
    if bind.map ~= target.map then return nil, "other map" end

    local at = type(here.position) == "table" and here.position or nil
    if not at or at.map == nil then return nil, "position unknown" end
    if at.map == target.map then
        if not (finite(at.x) and finite(at.y)) then return nil, "position unknown" end
        local size = sizeOf(here, target.map)
        if not size then return nil, "size unknown" end
        local saves = yards(at, target, size) - yards(bind, target, size)
        if saves < N.HEARTH_SAVES then return nil, "no saving" end
        step.saves = saves
    end
    step.lands = { map = bind.map, x = bind.x, y = bind.y }
    return step
end

-- One read of the client, or nil when it has no such read or the read fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

-- One saved table, read without making it; nil when it is not there.
local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

function N.HearthStepFrom(target, client, store)
    if client == nil then client = ns.client end
    if store == nil then store = ns.store end
    local name = text(ask(client, "bindLocation"))
    local bind = { name = name }
    local place = saved(store, "char", N.HEARTH_BIND)
    if name and type(place) == "table" and place.name == name then
        bind.map, bind.x, bind.y = place.map, place.x, place.y
    end
    return N.HearthStep(bind, target, {
        position = ask(client, "position"),
        mapSize = function(map) return ask(client, "mapSize", map) end,
    }, ask(client, "hearthCooldown"))
end
