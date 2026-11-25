local _, ns = ...

-- Tests for ZFlow/Nav/ProfSeen.lua (R1-R5): the recorder over the fake
-- client. Not tested in game.

local S = ns.ProfSeen
local tests = {}

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

-- opts: account, char (saved tables), date (false: the client will not
-- say), predecessor, wrap (gives the client the kernel is built over).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    if opts.date ~= false then c.setClock(opts.date or 5000) end
    if opts.predecessor then c.setLoaded(ns.id.predecessor, true) end
    local k = ns.Kernel({}, opts.wrap and opts.wrap(c) or c)
    ns.Diag.Start(k)
    local w = S.Declare(k)
    k:Boot()
    return k, c, w
end

local function login(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

local function at(root, ...)
    for _, key in ipairs({ ... }) do
        if type(root) ~= "table" then return nil end
        root = root[key]
    end
    return root
end

local function readings(c) return at(c.saved(ns.id.charDB), "learned", "facts", "profSkill") end
local function npcs(c) return at(c.saved(ns.id.accountDB), "learned", "places", "npcs") end

-- Everything saved, both scopes, as it is now, less the diag module's own
-- record (it keeps a snapshot per event it hears; that is not this module).
local function all(c)
    local account, char = copy(c.saved(ns.id.accountDB)), copy(c.saved(ns.id.charDB))
    if type(account) == "table" then account.diag = nil end
    if type(char) == "table" then char.diag = nil end
    return { account = account, char = char }
end

local function smithing(skill, max)
    return { profession = 164, name = "Blacksmithing", skill = skill, max = max, recipes = {} }
end

local function recipesSeen(c, r)
    c.setRecipes(r)
    c.fire(S.RECIPES_EVENT)
end

local function trainerSeen(c, r)
    c.setTrainer(r)
    c.fire(S.TRAINER_EVENT)
end

-- R1 ------------------------------------------------------------------

tests["prof seen R1: a recipes answer writes the reading"] = function(t)
    local _, c, w = start()
    login(c)
    recipesSeen(c, smithing(60, 75))
    t.eq(readings(c), { Blacksmithing = { line = 164, skill = 60, max = 75, at = 5000, maxAt = 5000 } })
    t.eq(w.last().ok, true, tostring(w.last().reason))
    t.eq(npcs(c), nil, "a reading wrote a trainer")
end

tests["prof seen R1: a later reading replaces the numbers and keeps the visit"] = function(t)
    local _, c = start({ char = { learned = { facts = { profSkill = {
        Blacksmithing = { line = 164, skill = 75, max = 75, at = 100, visitedAtCap = 75 } } } } } })
    login(c)
    c.setClock(7000)
    recipesSeen(c, smithing(80, 150))
    t.eq(readings(c), { Blacksmithing = { line = 164, skill = 80, max = 150, at = 7000, maxAt = 7000,
        visitedAtCap = 75 } })
end

-- C-50 (lead section 700): when the max was first read is kept, so a
-- trainer list saved before it can be told stale. Fails before: no maxAt.
tests["prof seen R1: a max read again keeps the time it was first read; a new max starts its own"] = function(t)
    local _, c = start({ char = { learned = { facts = { profSkill = {
        Blacksmithing = { line = 164, skill = 60, max = 75, at = 100, maxAt = 90 } } } } } })
    login(c)
    c.setClock(7000)
    recipesSeen(c, smithing(70, 75))
    t.eq(readings(c).Blacksmithing.maxAt, 90, "the same max: its first time")
    c.setClock(8000)
    recipesSeen(c, smithing(80, 150))
    t.eq(readings(c).Blacksmithing.maxAt, 8000, "the max rose: now")
end

tests["prof seen R1: with no clock the reading is written with no date"] = function(t)
    local _, c = start({ date = false, char = { learned = { facts = { profSkill = {
        Blacksmithing = { line = 164, skill = 10, max = 75, at = 100 } } } } } })
    login(c)
    recipesSeen(c, smithing(60, 75))
    t.eq(readings(c), { Blacksmithing = { line = 164, skill = 60, max = 75 } }, "an old date was kept for a new reading")
end

tests["prof seen R1: a name with a dot in it is one key"] = function(t)
    local _, c = start()
    login(c)
    recipesSeen(c, { profession = 7, name = "A.B", skill = 1, max = 75, recipes = {} })
    t.eq(readings(c), { ["A.B"] = { line = 7, skill = 1, max = 75, at = 5000 } })
end

tests["prof seen R1: no answer, or no name, writes nothing"] = function(t)
    local _, c, w = start()
    login(c)
    local before = all(c)
    recipesSeen(c, nil)
    t.eq(all(c), before, "no answer wrote something")
    t.eq(w.last().ok, false)
    recipesSeen(c, { profession = 164, skill = 60, max = 75, recipes = {} })
    t.eq(all(c), before, "a reading with no name wrote something")
    recipesSeen(c, { profession = 164, name = "", skill = 60, max = 75, recipes = {} })
    t.eq(all(c), before, "a reading with an empty name wrote something")
    recipesSeen(c, { profession = 164, name = "Blacksmithing", skill = "60", max = 75, recipes = {} })
    t.eq(all(c), before, "a skill that is not a number was written")
    recipesSeen(c, { profession = 164, name = "Blacksmithing", skill = 60, recipes = {} })
    t.eq(all(c), before, "a reading with no max was written")
end

tests["prof seen A3: a reading whose max is not above zero writes nothing"] = function(t)
    local saved = { line = 164, skill = 60, max = 75, at = 100 }
    local _, c, w = start({ char = { learned = { facts = { profSkill = { Blacksmithing = copy(saved) } } } } })
    login(c)
    recipesSeen(c, smithing(0, 0))
    t.eq(readings(c), { Blacksmithing = saved }, "a max of 0 was written")
    t.eq(w.last().ok, false, "a max of 0")
    recipesSeen(c, smithing(5, -1))
    t.eq(readings(c), { Blacksmithing = saved }, "a max below 0 was written")
    t.eq(w.last().ok, false, "a max below 0")
    recipesSeen(c, smithing(0, 75))
    t.eq(readings(c).Blacksmithing.skill, 0, "a skill of 0 under a real max is still a reading")
    t.eq(w.last().ok, true, tostring(w.last().reason))
end

-- R2 ------------------------------------------------------------------

tests["prof seen R2: a trainer show adds the trainer"] = function(t)
    local _, c, w = start()
    login(c)
    c.setFaction("Horde")
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    t.eq(npcs(c), { ["Saru Steelfury"] = {
        map = 1454, x = 0.25, y = 0.75,
        roles = { trainer = true },
        trains = { Blacksmithing = true },
        factions = { Horde = true },
        seen = 5000, n = 1,
    } })
    t.eq(w.last().ok, true, tostring(w.last().reason))
    t.eq(readings(c), nil, "a trainer show wrote a reading")
end

tests["prof seen R2: a trainer show merges and keeps what it does not know"] = function(t)
    local _, c = start({ account = { learned = { places = { npcs = {
        ["Saru Steelfury"] = {
            map = 1, x = 0.5, y = 0.5, id = 3355, note = "kept",
            roles = { trainer = true, vendor = true },
            trains = { Mining = true },
            factions = { Horde = true },
            seen = 100, n = 4,
        },
        ["Someone Else"] = { map = 2, x = 0.1, y = 0.1, n = 1 },
    } } } } })
    login(c)
    c.setFaction("Horde")
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    t.eq(npcs(c), {
        ["Saru Steelfury"] = {
            map = 1454, x = 0.25, y = 0.75, id = 3355, note = "kept",
            roles = { trainer = true, vendor = true },
            trains = { Mining = true, Blacksmithing = true },
            factions = { Horde = true },
            seen = 5000, n = 5,
        },
        ["Someone Else"] = { map = 2, x = 0.1, y = 0.1, n = 1 },
    })
end

tests["prof seen R2: a faction that is not known writes no factions key"] = function(t)
    local _, c = start()
    login(c)
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Cooking", npc = "Zamja" })
    local e = npcs(c).Zamja
    t.eq(e.factions, nil, "a faction was made up")
    t.eq(e.trains, { Cooking = true })
end

tests["prof seen R2: a faction that is not known keeps the factions already saved"] = function(t)
    local _, c = start({ account = { learned = { places = { npcs = {
        Zamja = { map = 1454, x = 0.2, y = 0.2, factions = { Horde = true }, trains = { Cooking = true }, n = 1 },
    } } } } })
    login(c)
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Cooking", npc = "Zamja" })
    t.eq(npcs(c).Zamja.factions, { Horde = true })
    t.eq(npcs(c).Zamja.n, 2)
end

tests["prof seen R2: with no clock the date already saved stays"] = function(t)
    local _, c = start({ date = false, account = { learned = { places = { npcs = {
        Zamja = { map = 1454, x = 0.2, y = 0.2, seen = 100, n = 1 },
    } } } } })
    login(c)
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Cooking", npc = "Zamja" })
    t.eq(npcs(c).Zamja.seen, 100)
    t.eq(npcs(c).Zamja.x, 0.25)
end

-- R3 ------------------------------------------------------------------

local function twoReadings()
    return { learned = { facts = { profSkill = {
        Blacksmithing = { line = 164, skill = 75, max = 75, at = 100 },
        Mining = { line = 186, skill = 75, max = 75, at = 100 },
        Cooking = { line = 185, skill = 40, max = 75, at = 100 },
    } } } }
end

tests["prof seen R3: a trainer show at the cap marks the visit, for that profession only"] = function(t)
    local _, c, w = start({ char = twoReadings() })
    login(c)
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    t.eq(readings(c), {
        Blacksmithing = { line = 164, skill = 75, max = 75, at = 100, visitedAtCap = 75 },
        Mining = { line = 186, skill = 75, max = 75, at = 100 },
        Cooking = { line = 185, skill = 40, max = 75, at = 100 },
    })
    t.eq(w.last().visited, true)
end

tests["prof seen R3: below the cap, or with no reading, no visit is marked"] = function(t)
    local _, c, w = start({ char = twoReadings() })
    login(c)
    c.setPosition(1454, 0.25, 0.75)
    local before = copy(readings(c))
    trainerSeen(c, { profession = "Cooking", npc = "Zamja" })
    t.eq(readings(c), before, "a visit below the cap was marked")
    t.eq(w.last().visited, false)
    c.setTrainer(nil)
    trainerSeen(c, { profession = "Tailoring", npc = "Magar" })
    t.eq(readings(c), before, "a visit was marked for a profession never read")
    t.ok(npcs(c).Zamja ~= nil and npcs(c).Magar ~= nil, "the trainers were not saved")
end

tests["prof seen R3: the step is gone after the visit and back at a higher cap"] = function(t)
    local _, c = start({ char = twoReadings() })
    login(c)
    c.setFaction("Horde")
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    local r = readings(c).Blacksmithing
    t.eq(r.visitedAtCap == r.max, true)
    recipesSeen(c, smithing(150, 150))
    r = readings(c).Blacksmithing
    t.eq(r.visitedAtCap, 75)
    t.eq(r.visitedAtCap == r.max, false, "the old visit still counts at the new cap")
end

-- R4 ------------------------------------------------------------------

tests["prof seen R4: no trainer answer, or no position, leaves the store unchanged"] = function(t)
    local k, c, w = start({ char = twoReadings() })
    login(c)
    c.setFaction("Horde")
    local before = all(c)

    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, nil)
    t.eq(all(c), before, "no trainer answer wrote something")
    t.eq(w.last().ok, false)

    c.setPosition(nil)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    t.eq(all(c), before, "a show with no position wrote something")

    c.setPosition(1454, nil, 0.75)
    c.fire(S.TRAINER_EVENT)
    t.eq(all(c), before, "a show with half a position wrote something")

    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { npc = "Saru Steelfury" })
    t.eq(all(c), before, "a trainer with no profession wrote something")

    t.eq((k:ModuleState(S.NAME)), "started")
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    t.ok(npcs(c)["Saru Steelfury"] ~= nil, "the show after those was not read")
end

tests["prof seen R4: a store that refuses the write is left unchanged"] = function(t)
    local k, c, w = start({ char = twoReadings() })
    login(c)
    c.setFaction("Horde")
    c.setPosition(1454, 0.25, 0.75)
    local before = all(c)

    k.store.blocked.account = "refused in a test"
    k.store.blocked.char = "refused in a test"
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    t.eq(all(c), before, "a refused trainer write changed the store")
    t.eq(w.last().ok, false)
    recipesSeen(c, smithing(150, 150))
    t.eq(all(c), before, "a refused reading write changed the store")
    t.eq((k:ModuleState(S.NAME)), "started", "a refusal switched the module off")

    k.store.blocked.account, k.store.blocked.char = nil, nil
    c.fire(S.TRAINER_EVENT)
    t.ok(npcs(c)["Saru Steelfury"] ~= nil, "the show after the refusal was not read")
    t.eq(readings(c).Blacksmithing.visitedAtCap, 75)
end

tests["prof seen R4: saved data of another shape is not written over"] = function(t)
    local _, c = start({ account = { learned = { places = { npcs = "broken" } } },
        char = { learned = { facts = { profSkill = 7 } } } })
    login(c)
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    recipesSeen(c, smithing(60, 75))
    t.eq(npcs(c), "broken")
    t.eq(readings(c), 7)
end

-- A client whose named read errors while broken.on is true.
local function breakable(broken, read)
    return function(real)
        return setmetatable({}, { __index = function(_, name)
            if name == read and broken.on then
                return function() error("the read broke") end
            end
            return real[name]
        end })
    end
end

tests["prof seen R4: an error inside one show loses that show only"] = function(t)
    local broken = { on = false }
    local k, c, w = start({ wrap = breakable(broken, "position") })
    login(c)
    c.setPosition(1454, 0.25, 0.75)
    broken.on = true
    local before = all(c)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    t.eq(all(c), before, "a show that failed wrote something")
    t.eq((k:ModuleState(S.NAME)), "started", "one error switched the module off")
    broken.on = false
    c.fire(S.TRAINER_EVENT)
    t.eq(npcs(c)["Saru Steelfury"].n, 1)
    t.eq(w.last().ok, true)
end

-- R5 ------------------------------------------------------------------

tests["prof seen R5: declared, nothing is read before login"] = function(t)
    local k, c, w = start()
    t.eq((k:ModuleState(S.NAME)), "declared")
    t.eq(w.last(), nil)
    c.setPosition(1454, 0.25, 0.75)
    local before = all(c)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    recipesSeen(c, smithing(60, 75))
    t.eq(all(c), before, "something was recorded before the module started")
    t.eq(w.last(), nil)
    login(c)
    t.eq((k:ModuleState(S.NAME)), "started")
    local provided = k.use(S.NAME)
    t.ok(type(provided) == "table" and provided.Last == w.last, "the kept report is not what the module provides")
    t.ok(type(ns.profSeen) == "table" and type(ns.profSeen.last) == "function", "the addon's own is not declared")
end

tests["prof seen R5: beside the predecessor nothing is watched or recorded"] = function(t)
    local k, c, w = start({ predecessor = true })
    login(c)
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    recipesSeen(c, smithing(60, 75))
    t.eq((k:ModuleState(S.NAME)), "declared")
    t.eq(w.last(), nil)
    t.eq(npcs(c), nil)
    t.eq(readings(c), nil)
end

tests["prof seen R5: switched off, nothing more is read or recorded"] = function(t)
    local broken = { on = false }
    local k, c, w = start({ wrap = breakable(broken, "recipes") })
    login(c)
    broken.on = true
    for _ = 1, ns.FAULT_LIMIT do c.fire(S.RECIPES_EVENT) end
    t.eq((k:ModuleState(S.NAME)), "off", "repeated errors did not switch the module off")
    broken.on = false
    c.setPosition(1454, 0.25, 0.75)
    trainerSeen(c, { profession = "Blacksmithing", npc = "Saru Steelfury" })
    recipesSeen(c, smithing(60, 75))
    t.eq(npcs(c), nil, "a trainer was recorded after the switch-off")
    t.eq(readings(c), nil, "a reading was recorded after the switch-off")
    t.eq(w.last(), nil)
end

-- Without the kernel ---------------------------------------------------

tests["prof seen: one reading and one show, without the kernel"] = function(t)
    local saved = { char = {}, account = {} }
    local store = {}
    function store:get(scope, path)
        return saved[scope][path]
    end
    function store:set(scope, path, value)
        saved[scope][path] = value
        return true
    end
    local client = {
        clock = function() return 42 end,
        recipes = function() return smithing(75, 75) end,
        trainer = function() return { profession = "Blacksmithing", npc = "Saru Steelfury" } end,
        position = function() return { map = 1454, x = 0.25, y = 0.75 } end,
        faction = function() return "Horde" end,
    }
    t.eq(S.Reading(client, store).ok, true)
    local report = S.Trainer(client, store)
    t.eq(report.ok, true, tostring(report.reason))
    t.eq(report.visited, true)
    t.eq(saved.char[S.READINGS].Blacksmithing, { line = 164, skill = 75, max = 75, at = 42, visitedAtCap = 75 })
    t.eq(saved.account[S.NPCS]["Saru Steelfury"].factions, { Horde = true })
    t.eq(S.Reading(nil, store).ok, false)
    t.eq(S.Trainer(client, nil).ok, false)
    t.eq(S.Trainer({}, store).ok, false)
end

return tests
