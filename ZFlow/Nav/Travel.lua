local _, ns = ...
-- Z-Flow travel wiring (S33 + S35, LEDGER 156): the step the arrow is given
-- when the way to the chosen step is not a walk in a straight line. It puts
-- together what the travel files already work out, each from the player's
-- own data:
--   Nav/TravelSpells.lua  "Cast Teleport: Moonglade"
--   Nav/HearthStep.lua    "Hearth to <place>"
--   Nav/Rides.lua         "Talk to <the ride's master>"
--   Nav/Gates.lua         "Way to <walled city>", at a gate this player learned
-- and Nav/TravelIcon.lua's rule for which of the cast and the stone is the
-- action (N.TravelAction). As legacy Flow 0.35.377 did, the action is shown
-- in the arrow's place and the step itself is said next ("Then: ...").
--
-- LOOK ONLY. It says what to do. Nothing casts, uses the stone, talks to
-- anyone, flies or walks for the player. The spell's picture in the arrow
-- frame is not drawn yet: the arrow shows the words. Not tested in game.
--
-- N.TravelVia(step, ways, skipped) -> step, how
--   step     the step chosen for the quest arrow: { label, place, ... }
--   ways     what each travel file answered for step.place; any may be nil:
--              spell   from N.TravelSpellStep
--              hearth  from N.HearthStep
--              ride    from N.RideStep
--              gate    from ns.use("gates").Step
--              crossing  from ns.use("crossings").Way(target) (S45; Twin's)
--              flight    from ns.use("flights").Way(target) (S45; MyBuddy's)
--                      each a step { kind, label, place = { cont, map, x, y },
--                      radius, ... } at the boarding place or flight master
--              cont    the continent the player is on (for the ride's place)
--   skipped  true when the player chose to walk to this step
--   The first of these that holds, and how:
--     "spell"   a spell the player knows (not one to learn)
--               -> { label, still = true, detail = "Then: <step label>" }
--     "hearth"  the stone, only when its saving is a known number above 0
--               -> the same shape
--     "ride"    -> { label, detail = how the ride goes, place, radius } when
--               the master's saved place is known, else the words with
--               still = true. No place is made up.
--     "crossing"  a crossing's step, detail = "Then: ..." (never skipped:
--               there is no walking over the sea). No place: not used.
--     "flight"  a flight's step, detail = "Then: ...". No place: not used.
--     "gate"    a learned gate -> the gate step, detail = "Then: ..."
--     "gate unknown"  a walled map with no gate known: a copy of the step
--               with N.GATE_UNKNOWN as its detail; a step that has a line of
--               its own (detail or lines) is handed back as it is
--   Else, with a spell to learn (not skipped, no hint of its own and no
--   flight line): a copy of the step whose hint is the learn step's own
--   line (its hint), or "Learn <spell> (<where>)" (Travel.LEARN) from its
--   detail, and no how. Lead section 403 (b). A learn step with neither
--   says nothing about where the spell is learned: no place is guessed
--   (lead section 632).
--   Else the step itself (the same table) and no how. skipped drops the
--   spell, the stone, the ride and the flight; the crossing and the gate
--   stay.
--   The step handed in and the ways are never changed. Each new step
--   carries via = how. (Not "travel": Nav/ViewState.lua reads a step's
--   travel as "the travel icon is shown" and halves the arrow for it.)
--
-- N.Travel.Declare(k, diag) -> api
--   api.via(step)   reads the client and the store and answers N.TravelVia.
--                   A step with no map place comes back as it is; so does
--                   one no way applies to (on the player's own map that is
--                   usually so, unless a provider of a crossing or a flight
--                   answers for it: the providers judge that themselves).
--   api.walk()      the word N.Travel.WORD: walk to this step instead, or
--                   back to the shortcut when said again. This session only.
--   ns.use("travel") -> { Via = api.via }
--   UI/Arrow.lua asks Via for the step it chose. With this module off the
--   arrow is as before. No setting is read here.
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.Travel = N.Travel or {}
local Travel = N.Travel

Travel.NAME = "travel"
Travel.WORD = "walk"
Travel.HELP = "walk to this step instead of the shortcut; say it again for the shortcut"
Travel.NEAR = 10               -- yards from a ride's master that count as there
Travel.THEN = "Then: %s"
-- Shown under a step whose place is on another continent with no way there
-- known yet (lead section 187).
Travel.FAR = "On another continent: no boat or zeppelin learned yet"
-- Under a step when the travel spell is one to learn (lead section 403 b):
-- "Learn <spell> (<where>)".
Travel.LEARN = "%s (%s)"
-- S45: the ways asked of other modules, in no order of their own (the
-- order is N.TravelVia's). module: its name for k.use; key: its field in ways.
Travel.WAYS = { { module = "crossings", key = "crossing" }, { module = "flights", key = "flight" } }

local function thenLine(step)
    if type(step.label) == "string" and step.label ~= "" then return Travel.THEN:format(step.label) end
    return nil
end

-- A crossing's or a flight's step (S45) as the arrow is given it: a copy
-- with "Then: <step>" as its detail and via = how. nil for one with no
-- label or no map place: no place is made up.
local function wayStep(way, how, step)
    if type(way) ~= "table" or type(way.label) ~= "string" then return nil end
    local p = way.place
    if type(p) ~= "table" or p.map == nil or type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
    local out = {}
    for key, v in pairs(way) do out[key] = v end
    out.detail = thenLine(step)
    out.via = how
    return out
end

function N.TravelVia(step, ways, skipped)
    if type(step) ~= "table" then return step end
    if type(ways) ~= "table" then return step end

    if not skipped then
        local action = N.TravelAction(ways.spell, ways.hearth, false)
        if action then
            return { label = action.text, still = true, detail = thenLine(step), via = action.kind }, action.kind
        end
        local ride = ways.ride
        if type(ride) == "table" and type(ride.label) == "string" then
            local out = { label = ride.label, detail = ride.detail, via = "ride" }
            local p = ride.point
            if type(p) == "table" and p.map ~= nil and type(p.x) == "number" and type(p.y) == "number" then
                out.place = { cont = ways.cont, map = p.map, x = p.x, y = p.y }
                out.radius = Travel.NEAR
            else
                out.still = true
            end
            return out, "ride"
        end
    end

    -- S45: a crossing to another continent (never skipped: there is no
    -- walking over the sea), then a flight (skipped when walking).
    local crossing = wayStep(ways.crossing, "crossing", step)
    if crossing then return crossing, "crossing" end
    if not skipped then
        local flight = wayStep(ways.flight, "flight", step)
        if flight then return flight, "flight" end
    end

    local gate = ways.gate
    if type(gate) == "table" and type(gate.label) == "string" then
        if type(gate.place) == "table" then
            local out = {}
            for key, v in pairs(gate) do out[key] = v end
            out.detail = thenLine(step)
            out.via = "gate"
            return out, "gate"
        end
        if gate.text then
            if step.detail ~= nil or step.lines ~= nil then return step, "gate unknown" end
            local out = {}
            for key, v in pairs(step) do out[key] = v end
            out.detail = gate.label
            return out, "gate unknown"
        end
    end

    -- Lead section 187: the place is on another continent and no way there
    -- is known (no crossing learned, no spell, no gate). There is no turn to
    -- give: a bearing over the sea would be wrong, and "direction unknown"
    -- reads as a fault. The step says so instead and is still. Both
    -- continents must be read numbers; either unknown and nothing is claimed.
    if type(ways.cont) == "number" and type(ways.far) == "number" and ways.cont ~= ways.far then
        local out = {}
        for key, v in pairs(step) do out[key] = v end
        local lines = {}
        if type(step.lines) == "table" then
            for i = 1, #step.lines do lines[i] = step.lines[i] end
        else
            if step.label ~= nil then lines[#lines + 1] = step.label end
            if step.detail ~= nil then lines[#lines + 1] = step.detail end
        end
        lines[#lines + 1] = Travel.FAR
        out.lines = lines
        out.place = nil
        out.radius = nil
        out.still = true
        out.via = "far"
        return out, "far"
    end
    -- Lead section 403 (b): a spell this player has still to learn is no
    -- way (N.TravelAction leaves it out), but where to learn it is said
    -- under the step, so the hint is not lost. A step's own hint stays.
    -- Parity B-32: it comes before the no-flight line (one hint only: the
    -- spell is the shorter way once learned).
    -- Owner, lead section 619: a learn step with a line of its own (the
    -- level the spell needs) is said as it is, no place added.
    -- Lead section 632: a learn step that says neither a line nor a place
    -- gives no learn line at all. Legacy Flow said "your class trainer"
    -- there; that is not verified, so it is never guessed.
    local learn = ways.spell
    if not skipped and type(learn) == "table" and learn.learn and type(learn.label) == "string"
        and step.hint == nil then
        local hint
        if type(learn.hint) == "string" and learn.hint ~= "" then
            hint = learn.hint
        elseif type(learn.detail) == "string" and learn.detail ~= "" then
            hint = Travel.LEARN:format(learn.label, learn.detail)
        end
        if hint then
            local out = {}
            for key, v in pairs(step) do out[key] = v end
            out.hint = hint
            return out
        end
    end
    -- Lead section 286: a far goal with no flight says why under it (the
    -- flights way's line). Still the waypoint itself.
    if not skipped and type(ways.flightHint) == "string" and step.lines == nil then
        local out = {}
        for key, v in pairs(step) do out[key] = v end
        out.hint = ways.flightHint
        return out
    end
    return step
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

-- A step's place as one word, for the walk list. nil for no map place.
local function keyOf(step)
    local p = type(step) == "table" and step.place or nil
    if type(p) ~= "table" or type(p.map) ~= "number" or type(p.x) ~= "number" or type(p.y) ~= "number" then
        return nil
    end
    return ("%d:%.4f:%.4f"):format(p.map, p.x, p.y)
end

function Travel.Declare(k, diag)
    local api = {}
    local ctx
    local skips = {}                 -- [key] = true: walk to this step (this session)
    local lastKey, lastHow = nil, nil

    local function say(line)
        if ctx then ctx.client.print(ns.id.title .. ": " .. line) end
    end

    function api.via(step)
        local key = keyOf(step)
        if not ctx or not key then
            lastKey, lastHow = nil, nil
            return step
        end
        local client, target = ctx.client, step.place
        -- Lead section 184 G1: a place with no continent (a quest place on
        -- another map) gets it from its own map, the same number the zone
        -- read gives. Not read: it stays nil. The step's place is not
        -- changed; every way below is handed the filled copy.
        if type(target) == "table" and target.cont == nil and type(target.map) == "number" then
            local cont = ask(client, "mapCont", target.map)
            if type(cont) == "number" then
                local filled = {}
                for f, v in pairs(target) do filled[f] = v end
                filled.cont = cont
                target = filled
            end
        end
        local pos = ask(client, "position")
        local zone = ask(client, "zone")
        local here = { position = pos }
        local mapSize = function(map) return ask(client, "mapSize", map) end
        local ways = { cont = type(zone) == "table" and zone.cont or nil }
        ways.far = type(target) == "table" and target.cont or nil

        local okSpell, spell = pcall(N.TravelSpellStepFrom, target, client, ctx.store)
        if okSpell then ways.spell = spell end
        local okHearth, hearth = pcall(N.HearthStepFrom, target, client, ctx.store)
        if okHearth then ways.hearth = hearth end
        local okNpcs, npcs = pcall(ctx.store.get, ctx.store, "account", "learned.places.npcs")
        local okRide, ride = pcall(N.RideStep, N.RIDES, target, here, ask(client, "class"), ask(client, "faction"),
            okNpcs and npcs or nil, mapSize)
        if okRide then ways.ride = ride end
        local gates = k.use and k.use(N.Gates and N.Gates.NAME or "gates")
        if type(gates) == "table" and type(gates.Step) == "function" then
            local okGate, gate = pcall(gates.Step, target)
            if okGate then ways.gate = gate end
        end
        -- S45: the crossing and the flight, from their owners' modules when
        -- they exist (Travel.WAYS). Each is handed a copy of the place.
        for _, w in ipairs(Travel.WAYS) do
            local provider = k.use and k.use(w.module)
            if type(provider) == "table" and type(provider.Way) == "function" then
                local okWay, way, _, line = pcall(provider.Way,
                    { cont = target.cont, map = target.map, x = target.x, y = target.y })
                if okWay then
                    ways[w.key] = way
                    if way == nil and type(line) == "string" then ways[w.key .. "Hint"] = line end
                end
            end
        end

        -- What it would be with no walking chosen: the walk word needs to
        -- know whether there is a shortcut to skip at all.
        local _, shortcut = N.TravelVia(step, ways, false)
        lastKey = key
        lastHow = (shortcut == "spell" or shortcut == "hearth" or shortcut == "ride" or shortcut == "flight")
            and shortcut or nil
        return N.TravelVia(step, ways, skips[key] == true)
    end

    -- menu: true from the arrow menu's row (parity B-30), whose own row
    -- brings the shortcut back; the typed word names itself.
    function api.walk(menu)
        if not lastKey or (not lastHow and not skips[lastKey]) then
            say("no shortcut on this step: nothing to walk past.")
            return false
        end
        local on = not skips[lastKey]
        N.TravelSkip(skips, lastKey, on)
        if on and menu then
            say("you walk to this step. The arrow's menu has the shortcut back.")
        elseif on then
            say("you walk to this step. Say " .. ns.id.slash .. " " .. Travel.WORD .. " again for the shortcut.")
        else
            say("the shortcut is back for this step; no more walk past it.")
        end
        return true
    end

    -- Parity B-30: what the arrow menu's walk row reads. nil with no step;
    -- else { how = the shortcut it would take or nil, skipped }.
    function api.state()
        if not lastKey then return nil end
        return { how = lastHow, skipped = skips[lastKey] == true }
    end

    k:Module({
        name = Travel.NAME,
        needs = { "client", "store" },
        provides = {
            Via = function(step) return api.via(step) end,
            State = function() return api.state() end,
            Walk = function() return api.walk(true) end,
        },
        start = function(c) ctx = c end,
        stop = function()
            skips, lastKey, lastHow = {}, nil, nil
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[Travel.WORD] = function() api.walk() end
        if type(diag.help) == "table" then diag.help[Travel.WORD] = Travel.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.travel = Travel.Declare(ns, ns.diag)
