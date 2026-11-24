local _, ns = ...
-- Z-Flow travel advice (S33, lead dispatch section 395 item 4): one
-- advisor line that says when a travel spell or a ride saves the walk to
-- the next stop. ADVICE ONLY: nothing is cast, summoned, bound or clicked.
-- Not tested in game.
--
-- Pure:
--   T.World(corners, p) -> wx, wy, cont for p = { map, x, y } (shares of
--     the map), from corners = client.mapCorners(map) ({ cont, ox, oy, ex,
--     ey, sx, sy }), or nil.
--   T.Yards(a, b, cornersOf) -> straight yards from a to b, or nil when
--     either is not placed, its map's corners are not known, or the two
--     are on different continents (a sea is not walked).
--   T.Advice(o) -> line or nil, reason
--     o = { here = { map, x, y }, target = { map, x, y },
--           cornersOf = function(map) -> corners,
--           spells = { { kind = "recall" | "teleport", name, known,
--                        cooldown, dest = { map, x, y } }, ... },
--           mount = { known, mounted, indoors } }
--     known: true / false / nil (not said). cooldown: client.spellCooldown,
--     false is ready; true (on cooldown) and nil (not known) give no line.
--     The first of these that holds:
--       "no target"   the stop not placed
--       "far unknown" the walk from here to the stop cannot be measured
--       "near"        the walk is under T.SAVES seconds
--       "spell"       the spell that saves the most, if that is at least
--                     T.SAVES: T.RECALL or T.TELEPORT with whole minutes
--       "mount"       a mount known, not mounted, not indoors, and half
--                     the walk is at least T.SAVES: T.RIDE
--       "no saving"   nothing saves enough
--   T.Spells(client, bind) -> the spells rows read from the client: only
--     spells whose name the client gives (client.spellName, localized).
--     The recall goes to bind = { map, x, y } (the saved home,
--     Nav/HearthSeen.lua, only when its name is client.bindLocation());
--     a teleport lands at the middle of its city's map (a guess, not
--     measured in game).
--   T.MountKnown(client) -> true when a class mount spell is known or a
--     riding skill has rank 75 or more; false when the skills were read and
--     none is; nil when not known.
--
-- Module "travelAdvice": a look every T.EVERY seconds at the next stop
-- (ns.use("tripRoute").Current(), else ns.use("arrow").Heading()); the
-- line is the advisor prompt T.PROMPT, removed when nothing saves.
-- Setting "nav.travelAdvice" (bool, default true).
-- Reads: client.position, mapCorners, spellName, spell, spellCooldown,
-- bindLocation, mounted, indoors, skillRanks; char "learned.places.bind".
ns.Nav = ns.Nav or {}
local T = {}
ns.TravelAdvice = T
ns.Nav.TravelAdvice = T

T.NAME = "travelAdvice"
T.SETTING = "nav.travelAdvice"
T.PROMPT = "nav.travelAdvice"
T.PRIORITY = 1
T.SAVES = 120      -- seconds a spell or ride must save before it is advised
T.CAST = 10        -- seconds a recall or teleport takes to cast
T.RUN = 7          -- yards a second on foot (Nav/Legs.lua L.RUN)
T.RIDE_AT = 75     -- riding skill rank of the first mount
T.EVERY = 2        -- seconds between looks
T.BIND = "learned.places.bind"
T.RECALL = "Your %s is ready: it saves about %d minutes."
T.TELEPORT = "%s would save about %d minutes."
T.RIDE = "Ride your mount: it halves this walk."

-- Spell ids only; names come from the client. Maps are uiMapIDs.
T.RECALL_SPELLS = { 556 }  -- Astral Recall (shaman)
T.TELEPORTS = {
    { id = 3561, map = 1453 },  -- Teleport: Stormwind
    { id = 3562, map = 1455 },  -- Teleport: Ironforge
    { id = 3565, map = 1457 },  -- Teleport: Darnassus
    { id = 3567, map = 1454 },  -- Teleport: Orgrimmar
    { id = 3563, map = 1458 },  -- Teleport: Undercity
    { id = 3566, map = 1456 },  -- Teleport: Thunder Bluff
    { id = 18960, map = 1450 }, -- Teleport: Moonglade (druid)
}
T.MOUNT_SPELLS = { 13819, 5784 }  -- Summon Warhorse, Summon Felsteed
T.RIDING = {
    ["Riding"] = true, ["Horse Riding"] = true, ["Wolf Riding"] = true, ["Ram Riding"] = true,
    ["Tiger Riding"] = true, ["Raptor Riding"] = true, ["Kodo Riding"] = true,
    ["Undead Horsemanship"] = true, ["Mechanostrider Piloting"] = true,
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function placed(p)
    return type(p) == "table" and p.map ~= nil and finite(p.x) and finite(p.y)
end

function T.World(corners, p)
    if type(corners) ~= "table" or not placed(p) then return nil end
    local o = corners
    if not (finite(o.ox) and finite(o.oy) and finite(o.ex) and finite(o.ey) and finite(o.sx) and finite(o.sy)) then
        return nil
    end
    local wx = o.ox + p.x * (o.ex - o.ox) + p.y * (o.sx - o.ox)
    local wy = o.oy + p.x * (o.ey - o.oy) + p.y * (o.sy - o.oy)
    return wx, wy, o.cont
end

function T.Yards(a, b, cornersOf)
    if not placed(a) or not placed(b) or type(cornersOf) ~= "function" then return nil end
    local ax, ay, ac = T.World(cornersOf(a.map), a)
    local bx, by, bc = T.World(cornersOf(b.map), b)
    if not ax or not bx then return nil end
    if ac == nil or ac ~= bc then return nil end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function minutes(seconds)
    return math.floor(seconds / 60 + 0.5)
end

function T.Advice(o)
    o = type(o) == "table" and o or {}
    if not placed(o.target) then return nil, "no target" end
    local yards = T.Yards(o.here, o.target, o.cornersOf)
    if not yards then return nil, "far unknown" end
    local walk = yards / T.RUN
    if walk < T.SAVES then return nil, "near" end

    local best, bestSaved = nil, nil
    for _, s in ipairs(type(o.spells) == "table" and o.spells or {}) do
        if type(s) == "table" and s.known == true and s.cooldown == false
            and type(s.name) == "string" and s.name ~= "" then
            local after = T.Yards(s.dest, o.target, o.cornersOf)
            if after then
                local saved = walk - (T.CAST + after / T.RUN)
                if saved >= T.SAVES and (bestSaved == nil or saved > bestSaved) then
                    best, bestSaved = s, saved
                end
            end
        end
    end
    if best then
        local fmt = best.kind == "recall" and T.RECALL or T.TELEPORT
        return fmt:format(best.name, minutes(bestSaved)), "spell"
    end

    local m = type(o.mount) == "table" and o.mount or {}
    if m.known == true and m.mounted == false and m.indoors ~= true and walk / 2 >= T.SAVES then
        return T.RIDE, "mount"
    end
    return nil, "no saving"
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read], ...)
    if not ok then return nil end
    return v
end

local function knownOf(client, id)
    local row = ask(client, "spell", id)
    if type(row) ~= "table" then return nil end
    if row.known == true or row.known == false then return row.known end
    return nil
end

local function row(client, id, kind, dest)
    local name = ask(client, "spellName", id)
    if type(name) ~= "string" or name == "" then return nil end
    local cd = ask(client, "spellCooldown", id)
    if cd ~= true and cd ~= false then cd = nil end
    return { id = id, kind = kind, name = name, known = knownOf(client, id), cooldown = cd, dest = dest }
end

function T.Spells(client, bind)
    local out = {}
    if placed(bind) then
        for _, id in ipairs(T.RECALL_SPELLS) do
            local r = row(client, id, "recall", { map = bind.map, x = bind.x, y = bind.y })
            if r then out[#out + 1] = r end
        end
    end
    for _, tp in ipairs(T.TELEPORTS) do
        local r = row(client, tp.id, "teleport", { map = tp.map, x = 0.5, y = 0.5 })
        if r then out[#out + 1] = r end
    end
    return out
end

function T.MountKnown(client)
    for _, id in ipairs(T.MOUNT_SPELLS) do
        if knownOf(client, id) == true then return true end
    end
    local ranks = ask(client, "skillRanks")
    if type(ranks) ~= "table" then return nil end
    for name, r in pairs(ranks) do
        if T.RIDING[name] and type(r) == "table" and finite(r.rank) and r.rank >= T.RIDE_AT then return true end
    end
    return false
end

function T.Declare(k)
    local api = {}
    local ctx
    local shown

    local function use(name)
        local m = ctx and ctx.use and ctx.use(name)
        if type(m) ~= "table" and k.use then m = k.use(name) end
        return type(m) == "table" and m or nil
    end

    -- The next stop: the route's first, else the arrow's place.
    local function target()
        local route = use("tripRoute")
        if route and type(route.Current) == "function" then
            local ok, cur = pcall(route.Current)
            if ok and type(cur) == "table" and type(cur.stops) == "table" and type(cur.stops[1]) == "table" then
                return cur.stops[1].place
            end
        end
        local arrow = use("arrow")
        if arrow and type(arrow.Heading) == "function" then
            local ok, place = pcall(arrow.Heading)
            if ok and type(place) == "table" then return place end
        end
        return nil
    end

    local function show(text)
        if text == shown then return end
        local advisor = use("advisor")
        if type(advisor) ~= "table" then return end
        if text then advisor.Add(T.PROMPT, text, T.PRIORITY) else advisor.Remove(T.PROMPT) end
        shown = text
    end

    function api.look()
        if not ctx then return nil, "not started" end
        if ctx.settings and ctx.settings:get(T.SETTING) == false then
            show(nil)
            return nil, "off"
        end
        local client = ctx.client
        local bind
        local name = ask(client, "bindLocation")
        local place = ctx.store and ctx.store:get("char", T.BIND)
        if type(name) == "string" and name ~= "" and type(place) == "table" and place.name == name then
            bind = place
        end
        local line, why = T.Advice({
            here = ask(client, "position"),
            target = target(),
            cornersOf = function(map) return ask(client, "mapCorners", map) end,
            spells = T.Spells(client, bind),
            mount = { known = T.MountKnown(client), mounted = ask(client, "mounted"),
                      indoors = ask(client, "indoors") },
        })
        show(line)
        return line, why
    end

    k:Module({
        name = T.NAME,
        needs = { "client", "store", "settings", "advisor" },
        settings = { {
            key = T.SETTING, scope = "char", type = "bool", default = true,
            label = "Travel spell and mount advice",
            help = "Says when a travel spell you know, or your mount, would save a long walk to your next stop. "
                .. "It only says so: nothing is cast or summoned.",
            group = "travel.route",
            synonyms = { "teleport", "recall", "mount", "ride", "travel", "advice" },
        } },
        provides = { Look = function() return api.look() end },
        ticks = { { every = T.EVERY, when = "always", run = function() api.look() end } },
        start = function(c) ctx = c; shown = nil end,
        stop = function() ctx = nil; shown = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.travelAdvice = T.Declare(ns)
