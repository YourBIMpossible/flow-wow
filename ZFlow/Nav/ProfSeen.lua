local _, ns = ...

-- ProfSeen: the module that saves what this player's own client shows about
-- professions, for Nav/ProfStep.lua to read. Nothing is authored here and
-- nothing is printed.
--
-- Readings. When a profession window answers (client.recipes()), char
--   "learned.facts.profSkill"[name] = { line, skill, max, at }
-- name is the profession as the client spells it, line its skill line, at
-- client.clock() (left out when the clock is not known). A visit already
-- marked on the entry is kept. No answer, no name, or a skill or max that is
-- not a number: nothing is written.
--
-- Trainers. When a trainer window opens and client.trainer() names the npc
-- and its profession, and client.position() gives a map and x, y, account
--   "learned.places.npcs"[npc]
-- gets map, x, y, roles.trainer = true, trains[profession] = true,
-- factions[faction] = true (only when client.faction() is known), seen =
-- client.clock() (a date already saved stays when the clock is not known)
-- and n + 1. Everything else already on the entry is kept: this is the
-- shape of the entries imported from the predecessor, so both merge.
--
-- Visits. On the same trainer show, when the saved reading of that
-- profession is at its cap (skill >= max), its visitedAtCap = max.
--
-- A show with no trainer answer, no profession or no position writes
-- nothing at all. A store that refuses a write is left as it was.
--
--   ProfSeen.Reading(client, store) -> report   one profession window read
--   ProfSeen.Trainer(client, store) -> report   one trainer show read
--   ProfSeen.Declare(k)             -> api      declares the module on kernel k
--     api.last()   the report of the last event read, nil before the first
--   ns.use(ProfSeen.NAME) -> { Last = api.last }
--
--   report = { kind = "reading" / "trainer", ok, reason (when not ok),
--              name (the profession), npc, visited (trainer: was a visit
--              marked) }
--
-- Keys are names the client gave and may hold a dot, so the two tables are
-- written by key and never through a dotted path.
--
-- This only reads the client. Not tested in game: the two event names and
-- every client read used here are first guesses.

local ProfSeen = ns.ProfSeen or {}
ns.ProfSeen = ProfSeen

ProfSeen.NAME = "profSeen"
ProfSeen.RECIPES_EVENT = "TRADE_SKILL_LIST_UPDATE"
ProfSeen.TRAINER_EVENT = "TRAINER_SHOW"
ProfSeen.READINGS = "learned.facts.profSkill"
ProfSeen.NPCS = "learned.places.npcs"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function name(v)
    return type(v) == "string" and v ~= ""
end

-- One read of the client; nil when it has no such read. An error is not
-- caught: the kernel counts it against the module.
local function ask(client, read)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read]()
end

local function clock(client)
    local now = ask(client, "clock")
    return finite(now) and now or nil
end

-- A copy of an entry one level deep, with the named sub-tables copied too.
local function entryOf(old, ...)
    local e = {}
    if type(old) == "table" then
        for key, value in pairs(old) do e[key] = value end
    end
    for _, sub in ipairs({ ... }) do
        local was = e[sub]
        e[sub] = nil
        if type(was) == "table" then
            local t = {}
            for key, value in pairs(was) do t[key] = value end
            e[sub] = t
        end
    end
    return e
end

-- The saved table at path: the table, or nil and true when nothing is
-- saved there yet, or nil and false when it cannot be used.
local function tableAt(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then
        return nil, false
    end
    local cur = store:get(scope, path)
    if cur == nil then return nil, true end
    if type(cur) ~= "table" then return nil, false end
    return cur, true
end

-- Puts entry under key in the saved table at path. The store is asked
-- first, with the table as it is; only when it says yes is the key set.
local function put(store, scope, path, key, entry)
    local cur, usable = tableAt(store, scope, path)
    if not usable then return false end
    cur = cur or {}
    if store:set(scope, path, cur) ~= true then return false end
    cur[key] = entry
    return true
end

local function refuse(report, reason)
    report.ok, report.reason = false, reason
    return report
end

function ProfSeen.Reading(client, store)
    local report = { kind = "reading" }
    local r = ask(client, "recipes")
    if type(r) ~= "table" then return refuse(report, "no profession window answered") end
    if not name(r.name) then return refuse(report, "the profession has no name") end
    report.name = r.name
    if not (finite(r.skill) and finite(r.max)) then return refuse(report, "the skill is not known") end
    local now = clock(client)

    local cur, usable = tableAt(store, "char", ProfSeen.READINGS)
    if not usable then return refuse(report, "the readings cannot be saved") end
    local e = entryOf(cur and cur[r.name])
    e.line = finite(r.profession) and r.profession or nil
    e.skill, e.max, e.at = r.skill, r.max, now
    if not put(store, "char", ProfSeen.READINGS, r.name, e) then
        return refuse(report, "the readings cannot be saved")
    end
    report.ok = true
    return report
end

function ProfSeen.Trainer(client, store)
    local report = { kind = "trainer", visited = false }
    -- Every read comes before the first write.
    local tr = ask(client, "trainer")
    if type(tr) ~= "table" or not name(tr.npc) then return refuse(report, "no trainer answered") end
    report.npc = tr.npc
    if not name(tr.profession) then return refuse(report, "the trainer's profession is not known") end
    report.name = tr.profession
    local pos = ask(client, "position")
    if type(pos) ~= "table" or not (finite(pos.map) and finite(pos.x) and finite(pos.y)) then
        return refuse(report, "the position is not known")
    end
    local faction = ask(client, "faction")
    local now = clock(client)

    local npcs, usable = tableAt(store, "account", ProfSeen.NPCS)
    if not usable then return refuse(report, "the trainers cannot be saved") end
    local e = entryOf(npcs and npcs[tr.npc], "roles", "trains", "factions")
    e.map, e.x, e.y = pos.map, pos.x, pos.y
    e.roles = e.roles or {}
    e.roles.trainer = true
    e.trains = e.trains or {}
    e.trains[tr.profession] = true
    if name(faction) then
        e.factions = e.factions or {}
        e.factions[faction] = true
    end
    if now then e.seen = now end
    e.n = (finite(e.n) and e.n or 0) + 1
    if not put(store, "account", ProfSeen.NPCS, tr.npc, e) then
        return refuse(report, "the trainers cannot be saved")
    end
    report.ok = true

    local readings = tableAt(store, "char", ProfSeen.READINGS)
    local r = readings and readings[tr.profession]
    if type(r) == "table" and finite(r.skill) and finite(r.max) and r.skill >= r.max and r.visitedAtCap ~= r.max then
        local visit = entryOf(r)
        visit.visitedAtCap = r.max
        report.visited = put(store, "char", ProfSeen.READINGS, tr.profession, visit)
    elseif type(r) == "table" and finite(r.max) and r.visitedAtCap == r.max then
        report.visited = true
    end
    return report
end

-- Declares the module on kernel k. Usable at once: before the first event
-- last() is nil.
function ProfSeen.Declare(k)
    local api = {}
    local last
    function api.last() return last end
    k:Module({
        name = ProfSeen.NAME,
        needs = { "client", "store", "bus" },
        provides = { Last = api.last },
        -- Registered here, after watchTrainer(), and not in `events`, so the
        -- client hears the trainer show before this does (the same order
        -- and the same limit as Items/PriceWatch.lua).
        start = function(ctx)
            if type(ctx.client.watchTrainer) == "function" then ctx.client.watchTrainer() end
            ctx.bus:on(ProfSeen.NAME, ProfSeen.RECIPES_EVENT, function()
                last = ProfSeen.Reading(ctx.client, ctx.store)
            end)
            ctx.bus:on(ProfSeen.NAME, ProfSeen.TRAINER_EVENT, function()
                last = ProfSeen.Trainer(ctx.client, ctx.store)
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.profSeen = ProfSeen.Declare(ns)
