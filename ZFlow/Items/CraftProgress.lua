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
-- ends it, not "failed" (:160), a fight ends it (:169), and a run that goes
-- quiet is over (CB.Stalled :73-78, its watch :170-180: running out of
-- reagents, closing the window or walking away fires no interrupt). Flow
-- matched its casts by the spell's name; here by the spell's number (the
-- spell the game casts for the recipe, as Items/CraftSpots.lua reads it).
-- An interrupt whose spell the game does not name is not taken as the
-- run's (Flow stopped the batch on it); the stall rule ends the run then.
--
-- The run is Items/CraftQueue.lua's (its first caller): the rows, which
-- one is due, and the counts.
--
-- Where the facts are from (lead section 611): the game's own cast events
-- of the player (UNIT_SPELLCAST_START, _SUCCEEDED, _INTERRUPTED: unit,
-- cast guid, spell id), the time (client.now()), and two reads the client
-- does not have yet (CLIENT NEED):
--   client.casting() -> startMs, endMs, channel | nil   the player's cast
--     now. The same CLIENT NEED Rotation/CastEdge.lua names: the 4th and
--     5th values of UnitCastingInfo("player"), else of UnitChannelInfo
--     ("player") with channel = true, in milliseconds on the clock
--     client.now() reads; nil when nothing is cast. Used for one cast's
--     length (the time left) and for whether a cast is going (the stall
--     rule). Without it no time is said, and a cast seen starting is
--     waited for until it is seen done (its length is not guessed).
--   client.onCraftStarted(fn) -> cancel | nil. fn(id, count, name) each
--     time the game's own craft call is made; stubbed in Core/ClientFake.lua
--     (the "§ E-57" block). Look only: both calls are watched with
--     hooksecurefunc, never called or replaced.
--       DoTradeSkill(index, count): the trade skill window's list index.
--         id is GetTradeSkillRecipeLink(index)'s spell ("enchant:<spell>"
--         in the link), name GetTradeSkillInfo(index)'s first value.
--       C_TradeSkillUI.CraftRecipe(recipeID, count): id is recipeID, the
--         spell the recipe casts; name C_TradeSkillUI.GetRecipeInfo's.
--     id is the SPELL the game casts for the recipe: the cast events carry
--     that number, and a run counts only casts of it. nil when the client
--     cannot tell it from the index (then no run starts). count: how many
--     were asked for; absent or not a whole number from 1 means one, which
--     starts no run (one craft has its cast bar already). Without the read
--     a run starts only through Begin.
--
-- Pure:
--   P.Left(total, done, castSecs, into) -> seconds left, or nil when one
--     cast's length is not known
--   P.Span(seconds) -> "21 s", "1 min 30 s"
--   P.Text(view, now) -> the line; view as Current() gives it
--   P.Stalled(view, now, casting[, idle]) -> true when a run going has had
--     nothing made or cast for more than idle seconds (P.IDLE): no time
--     kept or no time now is no stall
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
--     lastAt: when a craft was last begun, cast or made.
--     A finished or stopped run stays until the next Begin. A run that
--     stalls stops with stopped = "stalled", looked at every P.EVERY
--     seconds and whenever Current() is read.
-- P.EVENT is sent on the bus each time that answer changes.
-- Not tested in game.

local P = {}
ns.CraftProgress = P

P.NAME = "craftProgress"
P.EVENT = "craftProgress.changed"
P.LEAST = 2
P.IDLE = 2.5     -- seconds with nothing cast before a run is over (Flow's CB.IDLE)
P.EVERY = 0.5    -- seconds between looks for a stall
P.STALLED = "stalled"
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

function P.Stalled(view, now, casting, idle)
    if type(view) ~= "table" or view.stopped or view.finished then return false end
    if casting then return false end
    if not finite(now) or not finite(view.lastAt) then return false end
    if not finite(idle) then idle = P.IDLE end
    return now - view.lastAt > idle
end

function P.Declare(k)
    local api = {}
    local ctx, cancelStarted
    -- run: { q = the CraftQueue run, stopped, finished, castSecs, castStart,
    --        lastAt }
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

    -- The player's cast now from client.casting: true, false, or nil when
    -- the client has no such read; and its length in seconds when known.
    local function castNow()
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c.casting) ~= "function" then return nil end
        local ok, startMs, endMs = pcall(c.casting)
        if not ok or not finite(startMs) then return false end
        local secs
        if finite(endMs) and endMs > startMs then secs = (endMs - startMs) / 1000 end
        local t = now()
        if secs and finite(t) and t * 1000 > endMs then return false end
        return true, secs
    end

    local check
    function api.Current()
        if not run then return nil end
        check()
        local Q = ns.CraftQueue
        local row, q = rowOf()
        local made, all = Q.Total(q)
        local view = { name = row.name or ("recipe " .. tostring(row.id)), id = row.id, done = row.made,
            total = row.count, made = made, all = all, at = math.min(q.at, #q.rows), rows = #q.rows,
            castSecs = run.castSecs, castStart = run.castStart, stopped = run.stopped, finished = run.finished,
            lastAt = run.lastAt }
        view.text = P.Text(view, now())
        return view
    end

    function api.Begin(picks)
        local Q = ns.CraftQueue
        if type(Q) ~= "table" or type(Q.New) ~= "function" then return false, P.NO_QUEUE end
        local q = Q.New(picks)
        local _, all = Q.Total(q)
        if all < P.LEAST then return false, P.TOO_FEW end
        run = { q = q, lastAt = now() }
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

    -- The stall rule (Zen-3's review): a run that has had nothing cast for
    -- a while is over. Without the casting read, a cast seen starting is
    -- going until it is seen done, or until its length is past.
    check = function()
        if not going() then return end
        local t = now()
        local casting = castNow()
        if casting == nil then
            casting = run.castStart ~= nil
                and not (finite(run.castSecs) and finite(t) and t - run.castStart > run.castSecs)
        end
        if casting and finite(t) then run.lastAt = t end
        local view = { lastAt = run.lastAt }
        if P.Stalled(view, t, casting) then api.Stop(P.STALLED) end
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
        run.lastAt = run.castStart
        local _, secs = castNow()
        if finite(secs) and secs > 0 then run.castSecs = secs end
        tell()
    end

    local function done(unit, _, id)
        if not mine(unit, id) then return end
        local Q = ns.CraftQueue
        local before = run.q.at
        run.castStart = nil
        run.lastAt = now()
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
        ticks = { { every = P.EVERY, when = "always", run = function() check() end } },
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
                    -- Zen-3's review: a run going for this recipe (one
                    -- begun with several rows, say) is not replaced.
                    if going() and rowOf().id == id then return end
                    if type(count) ~= "number" then count = 1 end
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
