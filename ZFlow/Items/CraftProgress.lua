local _, ns = ...

-- CraftProgress (parity row E-57, the data half; lead section 660): while
-- the player makes several of a recipe, how far the run is and about how
-- long is left: "Making Linen Bandage 3/10 (about 21 s)". Data only: the
-- bar is the drawing lane's, built on ns.use("craftProgress").Current()
-- and the bus event P.EVENT. LOOK ONLY: nothing is crafted, stopped,
-- clicked or cast here.
--
-- From Flow (Modules/Crafting/CraftBar.lua at a529eea): CB.Left (:48-52),
-- CB.Span (:54-61), CB.Text (:64-70), a batch only for two or more
-- (:109-114), one cast finished or interrupted (:119-126), the cast's
-- length from the game's own cast times (:146-155), only "interrupted"
-- ends it, not "failed" (:160), and a fight ends it (:169). Flow matched
-- its casts by the spell's name; here by the recipe's number, which is the
-- spell the game casts for it (as Items/CraftSpots.lua reads it).
--
-- The run is Items/CraftQueue.lua's (its first caller): the rows, which
-- one is due, and the counts.
--
-- Where the facts are from (lead section 611): the game's own cast events
-- of the player (UNIT_SPELLCAST_START, _SUCCEEDED, _INTERRUPTED: unit,
-- cast guid, spell id), the time (client.now()), and two reads the client
-- does not have yet (CLIENT NEED; stubs in Core/ClientFake.lua):
--   client.ownCastSeconds() -> how long the cast the player is making now
--     takes in all, in seconds, or nil (UnitCastingInfo("player"): end
--     less start, in milliseconds). Without it no time is said: the line
--     ends at the count. Nothing is guessed from earlier casts.
--   client.onCraftStarted(fn) -> cancel | nil. fn(id, count, name) when
--     the game's own craft call is made (the profession window's Create
--     and Create All). Without it a run starts only through Begin.
--
-- Pure:
--   P.Left(total, done, castSecs, into) -> seconds left, or nil when one
--     cast's length is not known
--   P.Span(seconds) -> "21 s", "1 min 30 s"
--   P.Text(view, now) -> the line; view as Current() gives it
--
-- Module "craftProgress" (P.Declare(k) -> api):
--   Begin(picks) -> true | false, reason   picks as CraftQueue.New takes
--     them ({ { id, name, count } }). Refused for fewer than P.LEAST
--     crafts in all: one craft has its cast bar already.
--   Stop(why) -> true when a run was going
--   Current() -> nil with no run, else a copy:
--     { name, id, done, total (of the recipe being made), made, all (of
--       the whole run), at, rows, castSecs, castStart, stopped = why or
--       nil, finished = true or nil, text }
--     A finished or stopped run stays until the next Begin.
-- P.EVENT is sent on the bus each time that answer changes.
-- Not tested in game.

local P = {}
ns.CraftProgress = P

P.NAME = "craftProgress"
P.EVENT = "craftProgress.changed"
P.LEAST = 2
P.START = "UNIT_SPELLCAST_START"
P.DONE = "UNIT_SPELLCAST_SUCCEEDED"
P.BROKEN = "UNIT_SPELLCAST_INTERRUPTED"
P.FIGHT = "PLAYER_REGEN_DISABLED"
P.TOO_FEW = "a run is two crafts or more."
P.NO_QUEUE = "the craft queue is not loaded."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function P.Left(total, done, castSecs, into)
    if not (finite(castSecs) and castSecs > 0) or not finite(total) or not finite(done) then return nil end
    if not finite(into) then into = 0 end
    local left = (total - done) * castSecs - math.max(0, math.min(castSecs, into))
    return math.max(0, left)
end

function P.Span(seconds)
    if not finite(seconds) then seconds = 0 end
    seconds = math.floor(seconds + 0.5)
    -- Seconds, written with a format: this is time, not a price.
    if seconds >= 60 then
        local rest = seconds % 60
        if rest > 0 then return ("%d min %d s"):format(math.floor(seconds / 60), rest) end
        return ("%d min"):format(math.floor(seconds / 60))
    end
    return ("%d s"):format(seconds)
end

function P.Text(view, now)
    if type(view) ~= "table" then return "" end
    local name = type(view.name) == "string" and view.name or "recipe"
    if view.stopped then return ("Stopped: %s %d/%d"):format(name, view.done or 0, view.total or 0) end
    if view.finished then return ("Made %d %s"):format(view.total or 0, name) end
    local left
    if finite(now) then
        local into = 0
        if finite(view.castStart) then into = now - view.castStart end
        left = P.Left(view.total, view.done, view.castSecs, into)
    end
    local line = ("Making %s %d/%d"):format(name, view.done or 0, view.total or 0)
    if left then line = line .. " (about " .. P.Span(left) .. ")" end
    return line
end

function P.Declare(k)
    local api = {}
    local ctx, cancelStarted
    -- run: { q = the CraftQueue run, stopped, finished, castSecs, castStart }
    local run

    local function ask(name, ...)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    local function now()
        local t = ask("now")
        if finite(t) then return t end
        return nil
    end

    local function tell()
        if ctx and type(ctx.bus) == "table" and type(ctx.bus.emit) == "function" then
            pcall(ctx.bus.emit, ctx.bus, P.EVENT)
        end
    end

    -- The row being made: the one due, or the last one once all is made.
    local function rowOf()
        local Q = ns.CraftQueue
        local q = run.q
        return Q.Current(q) or q.rows[#q.rows], q
    end

    function api.Current()
        if not run then return nil end
        local Q = ns.CraftQueue
        local row, q = rowOf()
        local made, all = Q.Total(q)
        local view = { name = row.name or ("recipe " .. tostring(row.id)), id = row.id, done = row.made,
            total = row.count, made = made, all = all, at = math.min(q.at, #q.rows), rows = #q.rows,
            castSecs = run.castSecs, castStart = run.castStart, stopped = run.stopped, finished = run.finished }
        view.text = P.Text(view, now())
        return view
    end

    function api.Begin(picks)
        local Q = ns.CraftQueue
        if type(Q) ~= "table" or type(Q.New) ~= "function" then return false, P.NO_QUEUE end
        local q = Q.New(picks)
        local _, all = Q.Total(q)
        if all < P.LEAST then return false, P.TOO_FEW end
        run = { q = q }
        tell()
        return true
    end

    function api.Stop(why)
        if not run or run.stopped or run.finished then return false end
        run.stopped = type(why) == "string" and why ~= "" and why or "stopped"
        run.castStart = nil
        tell()
        return true
    end

    local function going()
        return run ~= nil and not run.stopped and not run.finished
    end

    -- Is the spell the recipe being made? Only a plain match counts.
    local function mine(unit, id)
        if unit ~= "player" or not going() then return false end
        local row = rowOf()
        return type(id) == "number" and row.id == id
    end

    local function started(unit, _, id)
        if not mine(unit, id) then return end
        run.castStart = now()
        local secs = ask("ownCastSeconds")
        if finite(secs) and secs > 0 then run.castSecs = secs end
        tell()
    end

    local function done(unit, _, id)
        if not mine(unit, id) then return end
        local Q = ns.CraftQueue
        local before = run.q.at
        run.castStart = nil
        if Q.Made(run.q) then run.finished = true end
        -- Another recipe is next: its cast's length is not known yet.
        if run.q.at ~= before then run.castSecs = nil end
        tell()
    end

    local function broken(unit, _, id)
        if mine(unit, id) then api.Stop("interrupted") end
    end

    k:Module({
        name = P.NAME,
        needs = { "client", "bus" },
        provides = { Begin = api.Begin, Stop = api.Stop, Current = api.Current },
        start = function(c)
            ctx = c
            c.bus:on(P.NAME, P.START, started)
            c.bus:on(P.NAME, P.DONE, done)
            c.bus:on(P.NAME, P.BROKEN, broken)
            c.bus:on(P.NAME, P.FIGHT, function() api.Stop("combat") end)
            -- CLIENT NEED: the game's own craft call. Absent: no run starts
            -- by itself, and nothing is claimed.
            if type(c.client.onCraftStarted) == "function" then
                local ok, cancel = pcall(c.client.onCraftStarted, function(id, count, name)
                    api.Begin({ { id = id, name = name, count = count } })
                end)
                if ok and type(cancel) == "function" then cancelStarted = cancel end
            end
        end,
        stop = function()
            if cancelStarted then pcall(cancelStarted) end
            cancelStarted, ctx, run = nil, nil, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.craftProgress = P.Declare(ns)
