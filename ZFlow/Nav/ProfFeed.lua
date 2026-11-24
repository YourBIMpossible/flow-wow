local _, ns = ...
-- Z-Flow profession coach feed (lead section 382, C2 P-COACH): ONE step
-- across all the character's professions, for the profession needle.
-- LOOK ONLY: nothing here crafts, buys, trains or moves for the player.
--
-- The steps come from the planner (C1, Items/ProfPlan.lua, MyBuddy) through
-- one seam: ns.ProfPlan.Plan(profession) -> { step, ... }, each step
--   { kind, text, item, count, target }
--   kind    learn_recipe | train_tier | craft | make_part | take_bank |
--           gather | buy_vendor | buy_auction | go_station
--   text    the plain instruction the player reads
--   target  { map, x, y } (x, y shares 0..1 of map), or nil: text only
-- Until C1 lands there is no ns.ProfPlan and the needle keeps the step
-- Nav/ProfStep.lua's N.ProfNext gives. Tests put a stand-in at
-- ns.ProfPlan of the add-on they load. C1's contract was not on a pushed
-- branch when this was written; it is matched to the lead's text.
--
-- F.Pick(input) -> result. Pure: plain tables in, nothing changed.
--   input = { names = { profession, ... }, readings = { [p] = { skill, max } },
--             plan = function(p) -> steps, cont = the player's continent,
--             cost = function(target) -> seconds or nil,
--             contOf = function(map) -> continent or nil,
--             contName = function(map) -> its continent's name or nil }
--   result = { rows = { { prof, skill, max, capped, steps = { text, ... } } },
--              pick = { prof, step, rank, seconds, held, text } or nil }
--   Only a profession below its max is a candidate; its candidate is its
--   plan's first step. Ranks, lowest first:
--     1 a craft or part with no place: done where the player stands (0 s)
--     2 a place on this continent with a travel time (with 1, by seconds)
--     3 a place on this continent, how far not known
--     4 no place known
--     5 a place on another continent: held back, as text
--     6 nothing known (no reading, or no step): "Open your X window once"
--   Ties: the lower profession name. pick is nil when no profession is
--   below its max (or none is known).
-- F.Step(result) -> the step the needle takes (Nav/ProfStep.lua's shapes):
--   a place: { place = { cont, map, x, y }, radius, label, detail }
--   else text: { still = true, lines = { text }, label }
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
-- Yards a second on foot (Nav/Legs.lua's L.RUN); a first guess.
F.RUN = 7
-- Kinds done where the player stands when the step has no place.
F.HERE = { craft = true, make_part = true }

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

-- The usable steps of a plan answer: a table with non-empty text.
local function stepsOf(plan, prof)
    local got = call(plan, prof)
    local out = {}
    if type(got) ~= "table" then return out end
    for _, s in ipairs(got) do
        if type(s) == "table" and type(s.text) == "string" and s.text ~= "" then out[#out + 1] = s end
    end
    return out
end

local function placed(target)
    return type(target) == "table" and target.map ~= nil and share(target.x) and share(target.y)
end

-- One profession's candidate: { prof, step, rank, seconds, held, text }.
local function candidate(prof, first, input)
    if not first then return { prof = prof, rank = 6, text = F.OPEN:format(prof) } end
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
        local steps = r and stepsOf(input.plan, prof) or {}
        local row = { prof = prof, steps = {} }
        if r then row.skill, row.max, row.capped = r.skill, r.max, r.skill >= r.max end
        for i, s in ipairs(steps) do row.steps[i] = s.text end
        rows[#rows + 1] = row
        if not row.capped then
            local c = candidate(prof, steps[1], input)
            if not best or better(c, best) then best = c end
        end
    end
    return { rows = rows, pick = best }
end

local function textStep(text)
    local step = { still = true, lines = { text } }
    if #text <= (N.Waypoint and N.Waypoint.LABEL_MAX or 40) then step.label = text end
    return step
end

function F.Step(result)
    local pick = type(result) == "table" and result.pick or nil
    if type(pick) ~= "table" then return nil end
    if pick.rank ~= 2 and pick.rank ~= 3 then return textStep(pick.text) end
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
                out[#out + 1] = "  " .. F.OPEN:format(row.prof)
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

-- The planner, through its one seam; nil until C1 lands.
local function planOf()
    local P = ns.ProfPlan
    if type(P) == "table" and type(P.Plan) == "function" then return P.Plan end
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
        return F.Step(api.result())
    end

    function api.lines()
        return F.Lines(api.result())
    end

    k:Setting({ key = F.SETTING, scope = "account", type = "bool", default = true,
        label = "Professions: show the next step", group = "professions",
        synonyms = { "profession", "professions", "coach", "arrow", "next step", "skill" } })

    k:Module({
        name = F.NAME,
        needs = { "client", "store", "settings" },
        provides = { Step = api.step, Off = api.off, Lines = api.lines },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
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
