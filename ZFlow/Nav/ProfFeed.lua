local _, ns = ...
-- Z-Flow profession coach feed (lead section 382, C2 P-COACH): ONE step
-- across all the character's professions, for the profession needle.
-- LOOK ONLY: nothing here crafts, buys, trains or moves for the player.
--
-- The steps come from the planner (C1, Items/ProfPlan.lua, with C3's
-- Items/ProfSources.lua) through its declared module: ns.profPlan.plan(
-- profession) -> steps, why, say, read live from the client and the store.
-- Each step
--   { kind, text, item, count, target }
--   kind    learn_recipe | train_tier | craft | make_part | take_bank |
--           gather | buy_vendor | buy_auction | go_station
--   text    the plain instruction the player reads
--   target  { map, x, y } (x, y shares 0..1 of map), or nil: text only
-- With no steps, say is the one thing a new player does next.
--
-- F.Pick(input) -> result. Pure: plain tables in, nothing changed.
--   input = { names = { profession, ... }, readings = { [p] = { skill, max } },
--             plan = function(p) -> steps, why, say,
--             cont = the player's continent,
--             reached = function(target) -> true when the player stands there,
--             cost = function(target) -> seconds or nil,
--             contOf = function(map) -> continent or nil,
--             contName = function(map) -> its continent's name or nil }
--   result = { rows = { { prof, skill, max, capped, steps = { text, ... } } },
--              pick = { prof, step, rank, seconds, held, text } or nil }
--   A profession below its max is a candidate, and one at its max whose
--   plan says to train the next rank (the only way to its next point).
--   Its candidate is its plan's current step: the first, past a "go to a
--   station" the player already stands at (or whose place was never seen,
--   when the step after it names the station itself). Ranks, lowest first:
--     1 a craft or part with no place: done where the player stands (0 s)
--     2 a place on this continent with a travel time (with 1, by seconds)
--     3 a place on this continent, how far not known
--     4 no place known
--     5 a place on another continent: held back, as text
--     6 nothing known (no reading, or no step): the planner's own words
--       for what to do next, else "Open your X window once"
--   Ties: the lower profession name. pick is nil when no profession is
--   below its max (or none is known).
-- (The module's Step also gives the pick, for Nav/ProfStep.lua's
-- N.ProfChoose between it and the older step.)
-- F.Step(result) -> the step the needle takes (Nav/ProfStep.lua's shapes):
--   a place: { place = { cont, map, x, y }, radius, label, detail, also }
--   else text: { still = true, lines = { text, ... }, label }
--   Lead section 416 item 2: after the pick's own lines, one line for each
--   other profession, by name, its own current step (F.Also): the text
--   step's lines, a place step's also (said under its label and detail by
--   UI/Arrow.lua). The needle still points at the pick.
-- F.Lines(result) -> the lines of "/zflow prof plan".
--
-- Module F.Declare(k, diag): setting F.SETTING (account, on by default,
-- group "professions"; the "Professions" tick of the route menu), provides
-- { Step, Off, Lines }; Nav/ProfStep.lua's step asks it first. The word
-- "prof" ("prof plan").
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.ProfFeed = N.ProfFeed or {}
local F = N.ProfFeed

F.NAME = "profFeed"
F.SETTING = "nav.professions"
F.WORD = "prof"
F.HELP = "prof plan: what each of your professions needs next, and the step the arrow shows"
F.OPEN = "Open your %s window once"
F.HELD = "Next time you are in %s: %s"
F.HELD_UNNAMED = "Next time you are on that continent: %s"
-- Lead section 416 item 2: another profession's step over
-- N.Waypoint.LABEL_MAX bytes is said short, by its kind; a kind not here,
-- or a short line still over, is left out, never cut.
F.ALSO_SHORT = "%s: %s"
F.KIND_WORDS = {
    learn_recipe = "learn a recipe",
    train_tier = "train the next rank",
    craft = "make an item",
    make_part = "make a part",
    take_bank = "take from the bank",
    gather = "gather",
    gather_skill = "gather",
    buy_vendor = "buy from a vendor",
    buy_auction = "buy at the auction house",
    go_station = "go to a station",
}
-- Yards a second on foot (Nav/Legs.lua's L.RUN); a first guess.
F.RUN = 7
-- Kinds done where the player stands when the step has no place.
F.HERE = { craft = true, make_part = true }
-- Section 387 R5: the map pin's kind and role (the client's own colours
-- for "new"), and how often it is looked at, in seconds. A first guess.
F.PIN_KIND = "new"
F.PIN_ROLE = "profession"
F.PIN_EVERY = 1

F.WHY = {
    "it can be done where you stand",
    "the nearest, about %d seconds away",
    "its place is known, how far is not",
    "no place is known for it",
    "every other step is on another continent",
    "nothing is known about it yet",
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return v
end

local function reading(readings, prof)
    local r = type(readings) == "table" and readings[prof] or nil
    if type(r) == "table" and finite(r.skill) and finite(r.max) and r.max > 0 then return r end
    return nil
end

-- The usable steps of a plan answer (a table with non-empty text), and
-- the planner's words for an empty plan, or nil.
local function stepsOf(plan, prof)
    local out = {}
    if type(plan) ~= "function" then return out, nil end
    local ok, got, _, say = pcall(plan, prof)
    if not ok then return out, nil end
    if type(got) == "table" then
        for _, s in ipairs(got) do
            if type(s) == "table" and type(s.text) == "string" and s.text ~= "" then out[#out + 1] = s end
        end
    end
    if type(say) ~= "string" or say == "" then say = nil end
    return out, say
end

local function placed(target)
    return type(target) == "table" and target.map ~= nil and share(target.x) and share(target.y)
end

-- The step the player is on: past each leading "go to a station" that is
-- done (the player stands there) or that has no seen place while a later
-- step follows.
function F.Current(steps, reached)
    local i = 1
    while steps[i] and steps[i + 1] and steps[i].kind == "go_station" do
        local to = steps[i].target
        if placed(to) and call(reached, to) ~= true then break end
        i = i + 1
    end
    return steps[i]
end

-- One profession's candidate: { prof, step, rank, seconds, held, text }.
local function candidate(prof, first, input, say)
    if not first then return { prof = prof, rank = 6, text = say or F.OPEN:format(prof) } end
    local c = { prof = prof, step = first, text = first.text }
    if not placed(first.target) then
        if F.HERE[first.kind] then c.rank, c.seconds = 1, 0 else c.rank = 4 end
        return c
    end
    local cont = call(input.contOf, first.target.map)
    c.cont = cont
    if finite(cont) and finite(input.cont) and cont ~= input.cont then
        c.rank, c.held = 5, true
        local name = call(input.contName, first.target.map)
        if type(name) == "string" and name ~= "" then
            c.text = F.HELD:format(name, first.text)
        else
            c.text = F.HELD_UNNAMED:format(first.text)
        end
        return c
    end
    local seconds = call(input.cost, first.target)
    if finite(seconds) and seconds >= 0 then
        c.rank, c.seconds = 2, seconds
    else
        c.rank = 3
    end
    return c
end

local function better(a, b)
    local ra, rb = a.rank, b.rank
    -- Ranks 1 and 2 are one list, by seconds.
    if ra <= 2 and rb <= 2 then
        if a.seconds ~= b.seconds then return a.seconds < b.seconds end
    elseif ra ~= rb then
        return ra < rb
    end
    return a.prof < b.prof
end

function F.Pick(input)
    if type(input) ~= "table" then input = {} end
    local names = {}
    for _, name in ipairs(type(input.names) == "table" and input.names or {}) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    table.sort(names)
    local rows, best = {}, nil
    for _, prof in ipairs(names) do
        local r = reading(input.readings, prof)
        local steps, say = {}, nil
        if r then steps, say = stepsOf(input.plan, prof) end
        local row = { prof = prof, steps = {}, say = say }
        if r then row.skill, row.max, row.capped = r.skill, r.max, r.skill >= r.max end
        for i, s in ipairs(steps) do row.steps[i] = s.text end
        rows[#rows + 1] = row
        local now = F.Current(steps, input.reached)
        -- Every profession's own current step, for F.Also (section 416).
        local c = candidate(prof, now, input, say)
        row.next = c
        if not row.capped or (now and now.kind == "train_tier") then
            if not best or better(c, best) then best = c end
        end
    end
    return { rows = rows, pick = best }
end

-- One line for another profession's step: its words, else short by kind.
local function alsoLine(c)
    local max = N.Waypoint and N.Waypoint.LABEL_MAX or 40
    if type(c.text) == "string" and #c.text <= max then return c.text end
    local words = F.KIND_WORDS[type(c.step) == "table" and c.step.kind or ""]
    if not words then return nil end
    local line = F.ALSO_SHORT:format(c.prof, words)
    if #line <= max then return line end
    return nil
end

-- F.Also(result) -> { line, ... }: one for each profession but the pick's,
-- in name order (one at its max only for its training); a line too long is
-- left out.
function F.Also(result)
    local out = {}
    local pick = type(result) == "table" and result.pick or nil
    local rows = type(result) == "table" and type(result.rows) == "table" and result.rows or {}
    for _, row in ipairs(rows) do
        -- A profession at its max says only its training (it gains no
        -- point any other way).
        local own = type(row.next) == "table" and not (type(pick) == "table" and row.prof == pick.prof)
        local stuck = row.capped and not (own and type(row.next.step) == "table" and row.next.step.kind == "train_tier")
        if own and not stuck then
            local line = alsoLine(row.next)
            if line then out[#out + 1] = line end
        end
    end
    return out
end

local function textStep(text, also)
    local step = { still = true, lines = { text } }
    for _, line in ipairs(also) do step.lines[#step.lines + 1] = line end
    if #text <= (N.Waypoint and N.Waypoint.LABEL_MAX or 40) then step.label = text end
    return step
end

function F.Step(result)
    local pick = type(result) == "table" and result.pick or nil
    if type(pick) ~= "table" then return nil end
    local also = F.Also(result)
    if pick.rank ~= 2 and pick.rank ~= 3 then return textStep(pick.text, also) end
    local to = pick.step.target
    local step = { place = { cont = pick.cont, map = to.map, x = to.x, y = to.y },
                   radius = N.PROF_NEAR or 10 }
    local max = N.Waypoint and N.Waypoint.LABEL_MAX or 40
    if #pick.text <= max then
        step.label = pick.text
    else
        step.detail = pick.text
        if #pick.prof <= max then step.label = pick.prof end
    end
    if #also > 0 then step.also = also end
    return step
end

function F.Lines(result)
    local out = {}
    local rows = type(result) == "table" and type(result.rows) == "table" and result.rows or {}
    if #rows == 0 then
        out[1] = "You have no profession yet: a trainer in a city teaches one."
        return out
    end
    for _, row in ipairs(rows) do
        if row.skill == nil then
            out[#out + 1] = row.prof .. ": " .. F.OPEN:format(row.prof)
        else
            out[#out + 1] = ("%s: %d of %d%s"):format(row.prof, row.skill, row.max,
                row.capped and ", at its max" or "")
            if #row.steps == 0 and not row.capped then
                out[#out + 1] = "  " .. (row.say or F.OPEN:format(row.prof))
            end
            for i, text in ipairs(row.steps) do out[#out + 1] = ("  %d. %s"):format(i, text) end
        end
    end
    local pick = result.pick
    if type(pick) ~= "table" then
        out[#out + 1] = "Next: every profession is at its max; train the next rank at its trainer."
        return out
    end
    local why = F.WHY[pick.rank]
    if pick.rank == 2 then why = why:format(math.floor(pick.seconds + 0.5)) end
    out[#out + 1] = ("Next: %s (%s): %s."):format(pick.text, pick.prof, why)
    return out
end

-- The planner's live read (Items/ProfPlan.lua's declared module), or nil.
local function planOf()
    local P = ns.profPlan
    if type(P) == "table" and type(P.plan) == "function" then return P.plan end
    return nil
end

function F.Declare(k, diag)
    local api = {}
    local ctx

    local function ask(name, ...)
        local client = ctx and ctx.client
        if type(client) ~= "table" then return nil end
        return call(client[name], ...)
    end

    function api.off()
        if not ctx or type(ctx.settings) ~= "table" or type(ctx.settings.get) ~= "function" then return false end
        local ok, v = pcall(ctx.settings.get, ctx.settings, F.SETTING)
        return ok and v == false
    end

    -- Seconds from the player to target: on this map, the player's own
    -- trips (Nav/Legs.lua) or the straight line; on another map, the
    -- straight line in the world. nil when not known.
    local function cost(target)
        local pos = ask("position")
        if type(pos) == "table" and pos.map == target.map and share(pos.x) and share(pos.y) then
            local size = ask("mapSize", pos.map)
            if type(size) ~= "table" or not (finite(size.w) and finite(size.h)) then return nil end
            local a = { x = pos.x * size.w, y = pos.y * size.h }
            local b = { x = target.x * size.w, y = target.y * size.h }
            local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
            local yards = d
            local legs = type(ctx.use) == "function" and call(ctx.use, "legs") or nil
            local planner = type(legs) == "table" and call(legs.Planner, pos.map) or nil
            if type(planner) == "function" then
                local ok, y, how = pcall(planner, a, b, d)
                if ok and finite(y) and y > 0 and (how == "exact" or how == "area") then
                    yards = how == "area" and math.max(d, y) or y
                end
            end
            return yards / F.RUN
        end
        local me = ask("worldPosition")
        local c = ask("mapCorners", target.map)
        if type(me) ~= "table" or type(c) ~= "table" or me.cont ~= c.cont then return nil end
        local wx = c.ox + target.x * (c.ex - c.ox) + target.y * (c.sx - c.ox)
        local wy = c.oy + target.x * (c.ey - c.oy) + target.y * (c.sy - c.oy)
        local d = math.sqrt((wx - me.wx) ^ 2 + (wy - me.wy) ^ 2)
        if not finite(d) then return nil end
        return d / F.RUN
    end

    -- Is the player standing at target (within the needle's own radius)?
    local function reached(target)
        local pos = ask("position")
        if type(pos) ~= "table" or pos.map ~= target.map or not (share(pos.x) and share(pos.y)) then return false end
        local size = ask("mapSize", pos.map)
        if type(size) ~= "table" or not (finite(size.w) and finite(size.h)) then return false end
        local d = math.sqrt(((pos.x - target.x) * size.w) ^ 2 + ((pos.y - target.y) * size.h) ^ 2)
        return d <= (N.PROF_NEAR or 10)
    end

    local function names()
        local out, has = {}, {}
        local function add(name)
            if type(name) == "string" and not has[name] then
                has[name] = true
                out[#out + 1] = name
            end
        end
        local list = ask("professions")
        if type(list) == "table" then
            for name in pairs(list) do
                if N.PROF_NAMES == nil or N.PROF_NAMES[name] then add(name) end
            end
        end
        local readings = api.readings()
        if type(readings) == "table" then
            for name in pairs(readings) do add(name) end
        end
        return out
    end

    function api.readings()
        if not ctx or type(ctx.store) ~= "table" then return nil end
        local ok, v = pcall(ctx.store.get, ctx.store, "char", "learned.facts.profSkill")
        if not ok then return nil end
        return v
    end

    function api.result()
        if not ctx then return nil end
        local zone = ask("zone")
        local cont = type(zone) == "table" and zone.cont or nil
        if cont == nil then
            local w = ask("worldPosition")
            cont = type(w) == "table" and w.cont or nil
        end
        return F.Pick({
            names = names(),
            readings = api.readings(),
            plan = planOf(),
            cont = cont,
            cost = cost,
            reached = reached,
            contOf = function(map)
                local got = ask("mapCont", map)
                if got ~= nil then return got end
                local c = ask("mapCorners", map)
                return type(c) == "table" and c.cont or nil
            end,
            contName = function(map) return ask("mapContName", map) end,
        })
    end

    -- The needle's step, or nil: off, no planner yet, or nothing below max.
    function api.step()
        if not ctx or api.off() or not planOf() then return nil end
        local result = api.result()
        return F.Step(result), type(result) == "table" and result.pick or nil
    end

    function api.lines()
        return F.Lines(api.result())
    end

    -- Lead section 387 R5: the picked step with a place on this continent
    -- is a labelled pin on the world map (client.mapPins, as
    -- UI/RouteTracker.lua draws its stop), while the world map shows that
    -- step's map. Cleared with no such step, or the tick off.
    local pins
    local function clearPin()
        if pins then pcall(pins.clear) end
    end
    function api.pin()
        if not ctx or api.off() or not planOf() then return clearPin() end
        local result = api.result()
        local pick = type(result) == "table" and result.pick or nil
        if type(pick) ~= "table" or (pick.rank ~= 2 and pick.rank ~= 3) then return clearPin() end
        if not pins then
            local h = ask("mapPins")
            if type(h) ~= "table" then return nil end
            pins = h
        end
        local to = pick.step.target
        local okMap, map = pcall(pins.map)
        if not okMap or map == nil or map ~= to.map then return clearPin() end
        pcall(pins.draw, { { name = pick.text, kind = F.PIN_KIND, role = F.PIN_ROLE, x = to.x, y = to.y } }, {})
        return nil
    end

    k:Setting({ key = F.SETTING, scope = "account", type = "bool", default = true,
        label = "Professions: show the next step", group = "professions",
        synonyms = { "profession", "professions", "coach", "arrow", "next step", "skill" } })

    k:Module({
        name = F.NAME,
        needs = { "client", "store", "settings" },
        provides = { Step = api.step, Off = api.off, Lines = api.lines },
        ticks = { { every = F.PIN_EVERY, when = "always", run = function() api.pin() end } },
        start = function(c) ctx = c end,
        stop = function()
            clearPin()
            ctx = nil
        end,
    })

    if type(diag) == "table" and type(diag.commands) == "table" then
        diag.commands[F.WORD] = function(rest)
            if not ctx then return end
            local say = function(line) ctx.client.print(ns.id.title .. ": " .. line) end
            if rest ~= "plan" then
                say("type " .. ns.id.slash .. " prof plan to see what your professions need next.")
                return
            end
            for _, line in ipairs(api.lines()) do say(line) end
        end
        if type(diag.help) == "table" then diag.help[F.WORD] = F.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.profFeed = F.Declare(ns, ns.diag)
