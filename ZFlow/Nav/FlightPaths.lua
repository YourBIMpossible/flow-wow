local _, ns = ...

-- FlightPaths (S30): flight paths to learn as you pass.
--
-- "Learn the flight path: <name>" for each flight master this player's
-- characters have learned of whose path this character does not have. A
-- flight path costs nothing but the few steps to its master, and every
-- later trip through that town is shorter for it.
--
-- ADVICE ONLY. Nothing here talks to an NPC, opens a window or takes a
-- flight. It reads saved places and four events the player causes, and
-- writes two notes of its own for this character.
--
-- Ported from Flow's Modules/Nav/FlightPaths.lua (0.35.377); the research,
-- with what changed and why, is WoW/from-zen/RESEARCH-S30.md. In short:
--   * the candidates are learned places only (account learned.places.npcs
--     with the flight role): no quest or NPC data is shipped or copied;
--   * a master must have been seen by a character of your faction
--     (Nav/ProfStep.lua's rule): one with no faction on record is no target;
--   * "a flight point you know stands by them" is told from the flight
--     masters this character used (Nav/ServiceSeen.lua), on the same map,
--     in yards when the map's size is known, else by name only.
--
-- Pure (plain tables in, nothing read, nothing remembered):
--   FP.Waits(note, level)             is a "no flight path here" note holding?
--   FP.Masters(npcs, faction, isRide) the candidates: { name, map, x, y, seen }
--   FP.Learned(fm, facts)             do you have this master's path?
--   FP.Goals(masters, facts, here)    one goal per master not learned
--   FP.Step(goals, here, zone)        the nearest goal on your map, as a step
--
--   npcs    account "learned.places.npcs": { [name] = { map, x, y, roles =
--           { flight = true }, kind, factions = { [faction] = true }, seen } }
--   isRide  optional fn(name) -> true for an NPC that carries you itself and
--           has no path to learn (Nav/Rides.lua, when it exists)
--   facts   { talked = char "learned.flights.talked" ({ [name] = true }),
--             none   = char "learned.flights.none" ({ [name] = { level, at } }),
--             level  = your level,
--             seen   = char "learned.places.services" (ServiceSeen's table),
--             size   = fn(map) -> { w, h } in yards, or nil }
--   here    { map, x, y, size = { w, h } }: where you are; x, y shares 0..1
--   goal    { key = "flightpath:<name>", kind = "flight", name,
--             place = { map, x, y }, text, details = { two lines },
--             optional = true unless the master is on your map within
--             FP.HERE yards, weight (0.8 close, else 1), yards (when known) }
--           `optional` means "only when it is close to the way you are
--           going anyway": that is for whoever plans the route to honour.
--   step    { kind = "flight", label, place = { cont, map, x, y }, radius }:
--           the shape Nav/ProfStep.lua gives the guide. A new step kind;
--           Nav/RoutePlan.lua and Nav/Guide.lua are not changed here.
--
-- Module: FP.Declare(k) -> api (api.goals(), api.step());
--   ns.use(FP.NAME) -> { Goals = api.goals, Step = api.step }
--   TAXIMAP_OPENED                      that master's path is yours: noted
--   GOSSIP_SHOW / MERCHANT_SHOW / QUEST_GREETING at a master that is a goal,
--     and no flight map within FP.WAIT seconds: they have no path for you
--     yet. Noted with your level; suggested again after a level; one chat line.
-- Setting: "nav.flightPaths" (bool, on by default); the row is the lead's to
--   add. Off: no goals, no step, nothing written.
-- Reads: client.serviceNpc() (who the player is talking to), position, zone,
--   faction, mapSize, level, clock.
-- Not tested in game: the events and the NPC read are first guesses.

local FP = ns.FlightPaths or {}
ns.FlightPaths = FP

FP.NAME = "flightPaths"
FP.SETTING = "nav.flightPaths"
FP.SAME = 250      -- yards: a flight master you used this close to one is the same one (Flow: FP.SAME)
FP.HERE = 800      -- yards: a master this close on your map is a step in its own right (Flow: FP.HERE)
FP.MAX = 30        -- goals given at most, the nearest first (Flow: FP.MAX)
FP.WAIT = 3        -- seconds for a flight map to open after talking (Flow: FP.WAIT)
FP.NEAR = 10       -- yards from the master that count as there (as N.PROF_NEAR)
FP.NPCS = "learned.places.npcs"
FP.SEEN = "learned.places.services"
FP.TALKED = "learned.flights.talked"
FP.NONE = "learned.flights.none"
FP.TALK_EVENTS = { "GOSSIP_SHOW", "MERCHANT_SHOW", "QUEST_GREETING" }

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function sizeOk(size)
    return type(size) == "table" and finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0
end

-- Yards between two places on one map of that size.
local function yards(a, b, size)
    local dx, dy = (a.x - b.x) * size.w, (a.y - b.y) * size.h
    return math.sqrt(dx * dx + dy * dy)
end

-- Flow :32-39. A note of true is one from before levels were kept: it no
-- longer holds. A level that is not known does not release the note.
function FP.Waits(note, level)
    if type(note) ~= "table" then return false end
    if not finite(level) then return true end
    return level <= (finite(note.level) and note.level or 0)
end

local function isFlight(e)
    if type(e.roles) == "table" and e.roles.flight == true then return true end
    return e.kind == "flight"
end

function FP.Masters(npcs, faction, isRide)
    local out = {}
    if type(npcs) ~= "table" or type(faction) ~= "string" then return out end
    for name, e in pairs(npcs) do
        if type(name) == "string" and name ~= "" and type(e) == "table" and isFlight(e)
            and e.map ~= nil and share(e.x) and share(e.y)
            and type(e.factions) == "table" and e.factions[faction] == true then
            local ride = false
            if type(isRide) == "function" then
                local ok, yes = pcall(isRide, name)
                ride = ok and yes and true or false
            end
            if not ride then
                out[#out + 1] = { name = name, map = e.map, x = e.x, y = e.y, seen = finite(e.seen) and e.seen or nil }
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Flow :40-54.
function FP.Learned(fm, facts)
    if type(fm) ~= "table" or type(facts) ~= "table" then return false end
    if type(facts.talked) == "table" and facts.talked[fm.name] then return true end
    if type(facts.none) == "table" and FP.Waits(facts.none[fm.name], facts.level) then return true end
    if type(facts.seen) == "table" then
        local size
        if type(facts.size) == "function" then
            local ok, got = pcall(facts.size, fm.map)
            if ok and sizeOk(got) then size = got end
        end
        for _, s in pairs(facts.seen) do
            if type(s) == "table" and type(s.kinds) == "table" and s.kinds.flight == true then
                if s.name ~= nil and s.name == fm.name then return true end
                if size and s.map == fm.map and share(s.x) and share(s.y) and yards(s, fm, size) <= FP.SAME then
                    return true
                end
            end
        end
    end
    return false
end

-- Flow :56-85.
function FP.Goals(masters, facts, here)
    facts = type(facts) == "table" and facts or {}
    local at = type(here) == "table" and here.map ~= nil and share(here.x) and share(here.y) and here or nil
    local size = at and sizeOk(at.size) and at.size or nil
    local out, seen = {}, {}
    for _, fm in ipairs(type(masters) == "table" and masters or {}) do
        if type(fm) == "table" and type(fm.name) == "string" and not seen[fm.name] and not FP.Learned(fm, facts) then
            seen[fm.name] = true
            local onMap = at ~= nil and fm.map == at.map
            local far = (onMap and size) and yards(fm, at, size) or nil
            local close = far ~= nil and far <= FP.HERE
            out[#out + 1] = {
                key = "flightpath:" .. fm.name, kind = "flight", name = fm.name,
                place = { map = fm.map, x = fm.x, y = fm.y },
                optional = (not close) or nil, weight = close and 0.8 or 1,
                yards = far, onMap = onMap or nil,
                text = "Learn the flight path: " .. fm.name,
                details = {
                    "You don't have this flight path yet. Talk to " .. fm.name
                        .. " once: it's free, and later trips through here are shorter for it.",
                    "Only on the route while it's close to the way you're going anyway.",
                },
            }
        end
    end
    -- On your map first, the nearest first when distance is known; then by name.
    table.sort(out, function(a, b)
        if (a.onMap ~= nil) ~= (b.onMap ~= nil) then return a.onMap ~= nil end
        if a.yards ~= b.yards then
            if a.yards and b.yards then return a.yards < b.yards end
            return a.yards ~= nil
        end
        return a.name < b.name
    end)
    for i = #out, FP.MAX + 1, -1 do out[i] = nil end
    return out
end

function FP.Step(goals, here, zone)
    if type(goals) ~= "table" or type(here) ~= "table" or here.map == nil then return nil end
    for _, g in ipairs(goals) do          -- already nearest first
        if type(g) == "table" and type(g.place) == "table" and g.place.map == here.map then
            local step = {
                kind = "flight",
                place = { cont = type(zone) == "table" and zone.cont or nil, map = g.place.map, x = g.place.x, y = g.place.y },
                radius = FP.NEAR,
            }
            local max = ns.Nav and ns.Nav.Waypoint and ns.Nav.Waypoint.LABEL_MAX or 40
            if type(g.text) == "string" and #g.text <= max then step.label = g.text end
            return step
        end
    end
    return nil
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

-- The goals from what the client and the store give now. isRide is optional.
function FP.From(client, store, isRide)
    local position = ask(client, "position")
    local here
    if type(position) == "table" then
        here = { map = position.map, x = position.x, y = position.y, size = ask(client, "mapSize", position.map) }
    end
    local facts = {
        talked = saved(store, "char", FP.TALKED), none = saved(store, "char", FP.NONE),
        level = ask(client, "level"), seen = saved(store, "char", FP.SEEN),
        size = function(map) return ask(client, "mapSize", map) end,
    }
    local masters = FP.Masters(saved(store, "account", FP.NPCS), ask(client, "faction"), isRide)
    return FP.Goals(masters, facts, here), here
end

function FP.Declare(k)
    local api = {}
    local ctx
    local pending = {}       -- [name] = true while waiting for a flight map after a talk

    local function on()
        return ctx ~= nil and ctx.settings:get(FP.SETTING) ~= false
    end

    -- NPCs that carry you themselves, when a module says so (Nav/Rides.lua).
    local function isRide(name)
        local ok, rides = pcall(ctx.use, "rides")
        if ok and type(rides) == "table" and type(rides.IsRide) == "function" then return rides.IsRide(name) end
        return false
    end

    function api.goals()
        if not on() then return {} end
        return (FP.From(ctx.client, ctx.store, isRide))
    end

    function api.step()
        if not on() then return nil end
        local goals, here = FP.From(ctx.client, ctx.store, isRide)
        return FP.Step(goals, here, ask(ctx.client, "zone"))
    end

    -- The name of whoever the player is talking to, or nil.
    local function npcName()
        local npc = ask(ctx.client, "serviceNpc")
        local name = type(npc) == "table" and npc.name or nil
        if type(name) == "string" and name ~= "" then return name end
        return nil
    end

    -- A note written by key: a name may hold a dot, so never a dotted path.
    local function note(path, name, value)
        local t = ctx.store:table("char", path)
        if type(t) ~= "table" then return false end
        t[name] = value
        return true
    end

    k:Module({
        name = FP.NAME,
        needs = { "client", "store", "bus", "sched", "settings" },
        provides = { Goals = function() return api.goals() end, Step = function() return api.step() end },
        start = function(c)
            ctx = c
            c.bus:on(FP.NAME, "TAXIMAP_OPENED", function()
                if not on() then return end
                local name = npcName()
                -- A flight map opened, so whoever was being waited on does
                -- have one: every wait ends here, also when the NPC read
                -- gives nothing. An unread NPC is not "no flight path".
                pending = {}
                if not name then return end
                note(FP.TALKED, name, true)
            end)
            local function talked()
                if not on() then return end
                local name = npcName()
                if not name or pending[name] then return end
                local mine = false
                for _, g in ipairs(api.goals()) do
                    if g.name == name then mine = true break end
                end
                if not mine then return end
                pending[name] = true
                c.sched:after(FP.NAME, FP.WAIT, function()
                    if not pending[name] then return end       -- a flight map came
                    pending[name] = nil
                    local was = saved(c.store, "char", FP.TALKED)
                    if type(was) == "table" and was[name] then return end
                    local clock = ask(c.client, "clock")
                    if note(FP.NONE, name, { level = ask(c.client, "level"), at = finite(clock) and clock or nil }) then
                        local id = k.id or ns.id
                        c.client.print(id.title .. ": " .. name
                            .. " has no flight path for you yet. It will be suggested again when you have gained a level.")
                    end
                end)
            end
            for i = 1, #FP.TALK_EVENTS do
                c.bus:on(FP.NAME, FP.TALK_EVENTS[i], talked)
            end
        end,
        stop = function() pending = {} end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.flightPaths = FP.Declare(ns)
