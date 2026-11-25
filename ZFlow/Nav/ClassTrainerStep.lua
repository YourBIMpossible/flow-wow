local _, ns = ...

-- ClassTrainerStep (G44, lead dispatch section 397 item 14): when the
-- player has class spells to learn at their level, a route step "Visit
-- your class trainer <name>: N new spells to learn". The count is
-- Spells/TrainAdvice.lua's prompts (one count, not a second one): pack
-- spells at or below the level, not from a class quest, read as not known.
--
-- Where: a class trainer this player has opened is saved (account
-- "learned.places.npcs", roles.classTrainer = true, classes[class] = true,
-- map, x, y) when its window lists a spell of the player's class pack.
-- Before any is saved, the class trainers the player's own Questie places
-- (Spells/ClassQuestList.lua L.Trainers, asked at runtime) stand in (C-54).
-- The nearest saved one of the player's class on the map they are on gets
-- a place; one on another map is named with no place; none saved: words
-- that say what to do, and no made-up place.
--
-- LOOK ONLY. Nothing here trains, buys, clicks or opens anything.
--
-- Pure parts:
--   n     = ClassTrainerStep.Count(pack, level, known)   nil: level or pack not known
--   step  = ClassTrainerStep.Of(n, class, here, npcs)    nil when n is not above 0
--   lines = ClassTrainerStep.Lines(step)
--   yes   = ClassTrainerStep.IsClassTrainer(trainer, pack)
-- Module: ns.use("classTrainerStep") -> { Step, Lines }. Setting
-- "nav.classTrainerStep" (bool, default true). Not seen in game.

local C = {}
ns.ClassTrainerStep = C

C.NAME = "classTrainerStep"
C.SETTING = "nav.classTrainerStep"
C.KIND = "classTrainer"
C.NPCS = "learned.places.npcs"
C.RADIUS = 10
C.LABEL = "Class trainer"
C.TRIES = 6
C.RETRY = 10

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function text(v)
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

local function labelMax()
    local N = ns.Nav
    return N and N.Waypoint and N.Waypoint.LABEL_MAX or 40
end

local function spells(n)
    if n == 1 then return "1 new spell to learn" end
    return tostring(n) .. " new spells to learn"
end

function C.Count(pack, level, known)
    if type(pack) ~= "table" or type(pack.spells) ~= "table" or not finite(level) then return nil end
    if type(known) ~= "function" then return nil end
    local TA = ns.TrainAdvice
    if type(TA) ~= "table" or type(TA.Prompts) ~= "function" then return nil end
    return #TA.Prompts(pack, level, known)
end

function C.IsClassTrainer(trainer, pack)
    if type(trainer) ~= "table" or type(trainer.services) ~= "table" then return false end
    if type(pack) ~= "table" or type(pack.spells) ~= "table" then return false end
    for _, row in ipairs(trainer.services) do
        if type(row) == "table" and text(row.name) and pack.spells[row.name] ~= nil then return true end
    end
    return false
end

-- The nearest saved class trainer of `class`: on the map of `here` first
-- (by shares of the map), else any, the lower name first.
local function nearest(class, here, npcs)
    if type(npcs) ~= "table" or not text(class) then return nil end
    local hereOk = type(here) == "table" and here.map ~= nil and share(here.x) and share(here.y)
    local best, bestName, bestD, other, otherName
    for name, e in pairs(npcs) do
        if type(name) == "string" and type(e) == "table" and type(e.roles) == "table"
            and e.roles.classTrainer == true and type(e.classes) == "table" and e.classes[class] == true then
            if hereOk and e.map == here.map and share(e.x) and share(e.y) then
                local dx, dy = e.x - here.x, e.y - here.y
                local d = dx * dx + dy * dy
                if bestD == nil or d < bestD or (d == bestD and name < bestName) then
                    best, bestName, bestD = e, name, d
                end
            elseif otherName == nil or name < otherName then
                other, otherName = e, name
            end
        end
    end
    if best then return bestName, { map = best.map, x = best.x, y = best.y } end
    if other then return otherName, nil end
    return nil
end

function C.Of(n, class, here, npcs)
    if not finite(n) or n <= 0 then return nil end
    local step = { kind = C.KIND, label = C.LABEL, count = n, radius = C.RADIUS }
    local name, place = nearest(class, here, npcs)
    if name then
        step.name = name
        step.place = place
        local long = C.LABEL .. ": " .. name
        if #long <= labelMax() then step.label = long end
    end
    return step
end

function C.Lines(step)
    if type(step) ~= "table" or not finite(step.count) or step.count <= 0 then return {} end
    if text(step.name) and type(step.place) == "table" then
        return { "Visit your class trainer " .. step.name .. ": " .. spells(step.count) .. "." }
    end
    if text(step.name) then
        return { "Visit your class trainer " .. step.name .. " (on another map): " .. spells(step.count) .. "." }
    end
    local title = ns.id and ns.id.title or "this add-on"
    return { "You have " .. spells(step.count) .. ". Go to your class trainer in a capital city and"
        .. " open its window once; " .. title .. " then remembers where it is." }
end

function C.Declare(k)
    local api = {}
    local ctx

    local function ask(read, ...)
        if not ctx or type(ctx.client[read]) ~= "function" then return nil end
        local ok, v = pcall(ctx.client[read], ...)
        if not ok then return nil end
        return v
    end

    local function on()
        if not ctx or not ctx.settings then return true end
        return ctx.settings:get(C.SETTING) ~= false
    end

    local function packOf(class)
        if not text(class) or type(ns.Packs) ~= "table" then return nil end
        return ns.Packs[class]
    end

    -- A trainer window that lists a spell of the player's class: saved as
    -- a class trainer (read first, then one write).
    local function seen()
        if not ctx or not ctx.store then return end
        local tr = ask("trainer")
        local class = ask("class")
        if type(tr) ~= "table" or not text(tr.npc) or not C.IsClassTrainer(tr, packOf(class)) then return end
        local pos = ask("position")
        if type(pos) ~= "table" or not (finite(pos.map) and share(pos.x) and share(pos.y)) then return end
        local okGet, npcs = pcall(ctx.store.get, ctx.store, "account", C.NPCS)
        if not okGet or (npcs ~= nil and type(npcs) ~= "table") then return end
        npcs = npcs or {}
        local e = {}
        if type(npcs[tr.npc]) == "table" then
            for key, v in pairs(npcs[tr.npc]) do e[key] = v end
        end
        local roles, classes = {}, {}
        if type(e.roles) == "table" then for key, v in pairs(e.roles) do roles[key] = v end end
        if type(e.classes) == "table" then for key, v in pairs(e.classes) do classes[key] = v end end
        roles.classTrainer = true
        classes[class] = true
        e.roles, e.classes = roles, classes
        e.map, e.x, e.y = pos.map, pos.x, pos.y
        local okSet, yes = pcall(ctx.store.set, ctx.store, "account", C.NPCS, npcs)
        if okSet and yes == true then npcs[tr.npc] = e end
    end

    -- The class trainers of the player's own Questie, read once for the
    -- session and class. An answer with no trainer (Questie still loading,
    -- or a read that failed) is asked again, but no sooner than C.RETRY
    -- seconds later and C.TRIES times in all: the arrow asks for this step
    -- on every frame, and one ask reads every NPC Questie knows. A client
    -- with no time answers now() as 0 (Core/Client.lua): 0, or anything that
    -- is not a number above 0, is read as "not known", and with no time to
    -- wait by the C.TRIES asks come in a row (lead section 493).
    local asked, questie, tries, last = nil, nil, 0, nil
    local function fromQuestie(class)
        if asked == class then return questie end
        local L = ns.ClassQuestList
        local db = ask("questieModule", "QuestieDB")
        if type(L) ~= "table" or type(db) ~= "table" then return nil end
        local now = ask("now")
        if not finite(now) or now <= 0 then now = nil end
        if now and last and now >= last and now - last < C.RETRY then return nil end
        local ok, found = pcall(L.Trainers, db, ask("questieModule", "ZoneDB"), class, ask("faction"))
        if not ok or type(found) ~= "table" then found = {} end
        tries = tries + 1
        last = now
        if next(found) ~= nil or tries >= C.TRIES then asked, questie = class, found end
        return found
    end

    function api.step()
        if not ctx or not on() then return nil end
        local class = ask("class")
        local n = C.Count(packOf(class), ask("level"), ns.TrainAdvice and ns.TrainAdvice.Known(ctx.client))
        if not n or n <= 0 then return nil end
        local npcs
        if ctx.store and type(ctx.store.get) == "function" then
            local ok, v = pcall(ctx.store.get, ctx.store, "account", C.NPCS)
            if ok then npcs = v end
        end
        local here = ask("position")
        -- C-54: the class trainers the player's own Questie places are
        -- added to the ones the player has opened.
        -- A trainer the player opened wins over one of the same name.
        local guess = fromQuestie(class)
        if type(guess) == "table" and next(guess) ~= nil then
            local all = {}
            for name, e in pairs(guess) do all[name] = e end
            for name, e in pairs(type(npcs) == "table" and npcs or {}) do all[name] = e end
            npcs = all
        end
        return C.Of(n, class, here, npcs)
    end

    function api.lines()
        return C.Lines(api.step())
    end

    k:Setting({ key = C.SETTING, scope = "account", type = "bool", default = true,
        label = "Class trainer step", group = "travel.route",
        help = "When you have class spells to learn at your level, add a step to your class trainer. It trains nothing.",
        synonyms = { "trainer", "class trainer", "train", "spells", "route", "step" } })

    k:Module({
        name = C.NAME,
        needs = { "client", "store", "settings", "bus" },
        provides = { Step = api.step, Lines = api.lines },
        start = function(c)
            ctx = c
            if type(c.client.watchTrainer) == "function" then pcall(c.client.watchTrainer) end
            c.bus:on(C.NAME, "TRAINER_SHOW", seen)
        end,
        stop = function()
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads.
ns.classTrainerStep = C.Declare(ns)
