-- Weapon master step, the master who teaches the kind (A2-07, lead section
-- 602): with Nav/WeaponMasterNames.lua (approximate, from Flow: which
-- weapon master teaches which weapon kinds) the step in words asks the
-- profession feed for a weapon master whose name the table has with the
-- wanted kind, on this map, else on this continent. A master the table
-- has without that kind is never pointed at; one the table does not have
-- stays "not known which weapons", as before. The masters' names are the
-- table's; every place, map and number here is made up, test only. Look
-- only. Not seen in game.
--
-- Red before the code: no table, and the step asks for any weapon master.
local _, ns = ...

local T = {}
local N = ns.Nav

local STR = "ITEM_MOD_STRENGTH_SHORT"
local SWORD = "item:2001"
local SWORDS, NOBODYS = 7, 19
local HERE_MAP, NEXT_MAP, OVERSEA_MAP = 1454, 1411, 1453
local AREA, NEXT_AREA, OVERSEA_AREA = 21, 22, 23
local AREAS = { [AREA] = HERE_MAP, [NEXT_AREA] = NEXT_MAP, [OVERSEA_AREA] = OVERSEA_MAP }
local UNLISTED = "Master Test"

local function WM() return ns.WeaponMasterStep end
local function PP() return N.ProfPlace end

-- teacher: the lowest name the table has with swords; other: the lowest
-- it has without them. nil (and a failed check) before the code.
local function names(t)
    local S, P, list = WM(), PP(), N.WeaponMasterNames
    local ok = type(S) == "table" and type(P) == "table" and type(list) == "table"
        and type(S.Teachers) == "function" and type(S.Elsewhere) == "function"
        and type(S.LISTED) == "string" and type(P.Pick) == "function"
    t.ok(ok, "the weapon master names, and the step's Teachers and Elsewhere")
    if not ok then return nil end
    local teach, all = S.Teachers(SWORDS)
    if type(teach) ~= "table" or type(all) ~= "table" then
        t.ok(false, "the table has a master who teaches swords")
        return nil
    end
    local teacher, other
    for name in pairs(all) do
        if teach[name] then
            if teacher == nil or name < teacher then teacher = name end
        elseif other == nil or name < other then
            other = name
        end
    end
    if teacher == nil or other == nil then
        t.ok(false, "the table has a master with swords and one without")
        return nil
    end
    return teacher, other
end

-- A stand-in for Questie's two modules. rows = { [id] = { name, area, x,
-- side } }, each a weapon master by its sub-name. state.scans counts the
-- times its NPCs were gone through (as Tests/E2E/ProfPlaceArrow.lua).
local function questie(state, rows)
    local npcs, first = {}, nil
    for id, r in pairs(rows) do
        npcs[id] = { name = r.name, subName = PP().WEAPON_MASTER, friendlyToFaction = r.side or "H",
                     spawns = { [r.area or AREA] = { { r.x, 50 } } } }
        if first == nil or id < first then first = id end
    end
    local db = { QuestPointers = {}, NPCPointers = {} }
    for id in pairs(npcs) do db.NPCPointers[id] = true end
    function db.QueryQuestSingle() return nil end
    function db.QueryNPCSingle(id, field)
        if id == first and field == "npcFlags" then state.scans = (state.scans or 0) + 1 end
        return npcs[id] and npcs[id][field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return AREAS[a] end
    return db, zones
end

local function known(rows, npcs)
    local found = rows and PP().Scan(questie({}, rows)) or nil
    return {
        here = { map = HERE_MAP, x = 0.5, y = 0.5, faction = "Horde" },
        contOf = function(map) return ({ [HERE_MAP] = 1, [NEXT_MAP] = 1, [OVERSEA_MAP] = 2 })[map] end,
        questie = function() return found end,
        npcs = npcs,
    }
end

-- The feed's Place, on made-up answers.
local function placeOf(rows, npcs)
    local k = known(rows, npcs)
    return function(ask) return PP().Pick(ask, nil, k) end
end

local function words(sub)
    return WM().Of({ subclassID = sub, skill = "Swords" }, nil, nil)
end

-- ------------------------------------------------------------------ pure

T["weapon master taught: the table says who teaches a kind"] = function(t)
    local teacher, other = names(t)
    if not teacher then return end
    local teach, all = WM().Teachers(SWORDS)
    t.eq(N.WeaponMasterNames[teacher].skills[SWORDS], true, "a teacher is one the table has with that kind")
    t.eq(N.WeaponMasterNames[other].skills[SWORDS], nil, "the other is one it has without")
    local inAll = true
    for name in pairs(teach) do
        if all[name] ~= true then inAll = false end
    end
    t.ok(inAll, "every teacher is among all the table's names")
    t.eq(all[other], true, "and so is one who does not teach it")
    local none, every = WM().Teachers(NOBODYS)
    t.eq(none, nil, "a kind no listed master teaches: no teacher")
    t.eq(every, all, "the table's names all the same")
    t.eq((WM().Teachers(nil)), nil, "no kind: no teacher")
end

T["weapon master taught: a place is asked for among some names only, or without some"] = function(t)
    local teacher, other = names(t)
    if not teacher then return end
    local k = known({
        [1] = { name = other, x = 51 },
        [2] = { name = UNLISTED, x = 60 },
        [3] = { name = teacher, x = 80 },
    })
    local ask = WM().ASK
    t.eq(PP().Pick({ kind = ask }, nil, k), { name = other, map = HERE_MAP, x = 0.51, y = 0.5 },
        "asked plainly: the nearest, as before")
    t.eq(PP().Pick({ kind = ask, only = { [teacher] = true } }, nil, k),
        { name = teacher, map = HERE_MAP, x = 0.8, y = 0.5 }, "only that name: the farther one")
    t.eq(PP().Pick({ kind = ask, skip = { [other] = true, [teacher] = true } }, nil, k),
        { name = UNLISTED, map = HERE_MAP, x = 0.6, y = 0.5 }, "without those names: the one left")
    t.eq(PP().Pick({ kind = ask, only = { ["Nobody Here"] = true } }, nil, k), nil, "a name not there: no place")
    t.eq(PP().Of({ kind = ask, only = { [teacher] = true } }, nil, k), { map = HERE_MAP, x = 0.8, y = 0.5 },
        "Of gives the same place, bare")
end

T["weapon master taught: the master who teaches the kind is picked over a nearer one who does not"] = function(t)
    local teacher, other = names(t)
    if not teacher then return end
    local step = WM().Elsewhere(words(SWORDS), placeOf({
        [1] = { name = other, x = 51 },
        [2] = { name = UNLISTED, x = 55 },
        [3] = { name = teacher, x = 80 },
    }))
    t.eq(step.place, { map = HERE_MAP, x = 0.8, y = 0.5 }, "the one who teaches swords, farthest as it is")
    t.eq(step.name, teacher, "with the name")
    t.eq(step.unvisited, true, "one the player has not visited")
    t.eq(step.listed, true, "marked as one from the list")
    t.eq(step.detail, WM().LISTED, "the arrow's line says the list is where it is from")
    t.eq(WM().Lines(step), { WM().UNVISITED:format("Swords", teacher), WM().LISTED },
        "the words say it too, never that nothing is known")
end

T["weapon master taught: the teacher on another map of this continent, before a nearer one who does not teach"] = function(t)
    local teacher, other = names(t)
    if not teacher then return end
    local step = WM().Elsewhere(words(SWORDS), placeOf({
        [1] = { name = other, x = 51 },
        [3] = { name = teacher, x = 30, area = NEXT_AREA },
    }))
    t.eq(step.place, { map = NEXT_MAP, x = 0.3, y = 0.5 }, "the teacher, in the next zone")
    t.eq(step.listed, true)
end

T["weapon master taught: a kind no listed master teaches"] = function(t)
    local teacher, other = names(t)
    if not teacher then return end
    -- Only masters the table has, none with this kind: nobody to point at.
    local bare = WM().Elsewhere(words(NOBODYS), placeOf({
        [1] = { name = other, x = 51 },
        [3] = { name = teacher, x = 80 },
    }))
    t.eq(bare.place, nil, "no place")
    t.eq(bare.name, nil, "no name")
    t.eq(bare.unvisited, nil, "nothing marked")
    t.eq(WM().Lines(bare), WM().Lines(words(NOBODYS)), "words only, as with nothing known")
    -- One the table does not have: what they teach is not known, as before.
    local step = WM().Elsewhere(words(NOBODYS), placeOf({
        [1] = { name = other, x = 51 },
        [2] = { name = UNLISTED, x = 70 },
        [3] = { name = teacher, x = 80 },
    }))
    t.eq(step.name, UNLISTED, "the one the table says nothing about, never a nearer one it has without the kind")
    t.eq(step.unvisited, true, "not visited")
    t.eq(step.listed, nil, "not marked as from the list")
    t.eq(step.detail, WM().NOT_KNOWN, "what they teach is said to be not known")
end

T["weapon master taught: the teacher out of reach, and a master who does not teach is not pointed at"] = function(t)
    local teacher, other = names(t)
    if not teacher then return end
    local sea = WM().Elsewhere(words(SWORDS), placeOf({
        [1] = { name = other, x = 51 },
        [3] = { name = teacher, x = 80, area = OVERSEA_AREA },
    }))
    t.eq(sea.place, nil, "the teacher across the sea: no place")
    t.eq(WM().Lines(sea), WM().Lines(words(SWORDS)), "words only")
    local theirs = WM().Elsewhere(words(SWORDS), placeOf({
        [1] = { name = other, x = 51 },
        [3] = { name = teacher, x = 80, side = "A" },
    }))
    t.eq(theirs.place, nil, "the teacher of the other faction: no place")
end

T["weapon master taught: a teacher the player has seen on another map is one visited"] = function(t)
    local teacher, other = names(t)
    if not teacher then return end
    local npcs = {
        [teacher] = { map = NEXT_MAP, x = 0.2, y = 0.2, roles = { weaponMaster = true } },
        [other] = { map = NEXT_MAP, x = 0.4, y = 0.4, roles = { weaponMaster = true } },
    }
    local step = WM().Elsewhere(words(SWORDS), placeOf(nil, npcs))
    t.eq(step.place, { map = NEXT_MAP, x = 0.2, y = 0.2 }, "the saved teacher")
    t.eq(step.name, teacher)
    t.eq(step.unvisited, nil, "not marked as not visited")
    t.eq(step.listed, nil, "and no line about the list")
    t.eq(step.detail, nil)
end

T["weapon master taught: nobody to ask, or no answer, leaves the step in words"] = function(t)
    if not names(t) then return end
    t.eq(WM().Elsewhere(words(SWORDS), nil), words(SWORDS), "nobody to ask")
    t.eq(WM().Elsewhere(words(SWORDS), function() return nil end), words(SWORDS), "no place known")
    t.eq(WM().Elsewhere(words(SWORDS), function() error("not there") end), words(SWORDS), "the ask failing")
    t.eq(WM().Elsewhere(words(SWORDS), placeOf(nil)), words(SWORDS), "no Questie and nothing saved")
end

-- ---------------------------------------------------------------- module

local function packs()
    return { WARRIOR = {
        weights = { dps = { evidence = "first guess", values = { [STR] = 1 } } },
        proficiency = { evidence = "first guess", [2] = { [0] = true, [7] = true } },
    } }
end

-- As Tests/Nav/WeaponMasterPlaceTests.lua: a Horde warrior shown a sword
-- not trained. opts: rows (the made-up Questie's weapon masters; nil: no
-- Questie), state, npcs (the account's saved npcs).
local function start(opts)
    local c = ns.make.fakeClient()
    local account = {}
    if opts.npcs then account.learned = { places = { npcs = opts.npcs } } end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setFaction("Horde")
    c.setPosition(HERE_MAP, 0.5, 0.5)
    c.setMapSize(HERE_MAP, 1000, 500)
    c.setMapCont(HERE_MAP, 1); c.setMapCont(NEXT_MAP, 1); c.setMapCont(OVERSEA_MAP, 2)
    c.setItem(SWORD, { kind = "INVTYPE_WEAPON", stats = { [STR] = 5 }, classID = 2, subclassID = SWORDS,
                       minLevel = 1, unmet = { "Swords" } })
    c.setWorn(16, false); c.setWorn(17, false)
    c.setDualWield(false)
    c.setWeaponSkills({ "Axes", "Defense" })
    if opts.rows then
        local db, zones = questie(opts.state or {}, opts.rows)
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    N.ProfFeed.Declare(k)
    local api = WM().Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    c.showItemTooltip(SWORD)
    return k, c, api
end

local function settled(c, api)
    api.step()
    c.advance(1, 20)
    return api.step()
end

T["weapon master taught module: the step points at the master who teaches the kind, and Questie is read once"] = function(t)
    local teacher, other = names(t)
    if not teacher then return end
    local state = {}
    local k, c, api = start({ state = state, rows = {
        [1] = { name = other, x = 51 },
        [2] = { name = UNLISTED, x = 55 },
        [3] = { name = teacher, x = 80 },
    } })
    local before = k.problems:count()
    local first = api.step()
    t.eq(first and first.place, nil, "the first ask reads nothing itself: words only")
    c.advance(1, 20)
    local step = api.step()
    t.eq(step and step.place, { map = HERE_MAP, x = 0.8, y = 0.5 }, "the one who teaches swords")
    t.eq(step and step.name, teacher, "with the name")
    t.eq(step and step.skill, "Swords", "for the skill wanted")
    t.eq(step and step.listed, true, "marked as one from the list")
    t.eq(step and step.detail, WM().LISTED, "the arrow's line says so")
    t.eq(api.lines(), { WM().UNVISITED:format("Swords", teacher), WM().LISTED }, "and so do the words")
    t.eq(state.scans, 1, "Questie's NPCs were gone through once")
    for _ = 1, 5 do
        api.step()
        api.lines()
        c.advance(6, 24)
    end
    t.eq(state.scans, 1, "still once, after many asks and frames")
    t.eq(k.problems:count(), before, "no problem raised")
end

T["weapon master taught module: only masters who do not teach the kind, and the step stays in words"] = function(t)
    local teacher, other = names(t)
    if not teacher then return end
    local _, c, api = start({ rows = { [1] = { name = other, x = 51 } } })
    local step = settled(c, api)
    t.ok(step ~= nil, "the step is still offered")
    t.eq(step and step.place, nil, "no place")
    t.eq(step and step.name, nil, "no name")
    t.eq(api.lines(), WM().Lines(words(SWORDS)), "words only, as with nothing known")
end

T["weapon master taught module: a saved weapon master on this map still wins over the list"] = function(t)
    local teacher = names(t)
    if not teacher then return end
    local state = {}
    local npcs = { ["Saved Master"] = { map = HERE_MAP, x = 0.9, y = 0.5, roles = { weaponMaster = true } } }
    local _, c, api = start({ state = state, npcs = npcs, rows = { [3] = { name = teacher, x = 80 } } })
    local step = settled(c, api)
    t.eq(step and step.name, "Saved Master", "the one the player visited")
    t.eq(step and step.listed, nil, "no line about the list")
    c.advance(30, 120)
    t.eq(state.scans, nil, "and Questie was not gone through at all")
end

T["weapon master taught module: no Questie leaves the step words only"] = function(t)
    if not names(t) then return end
    local k, c, api = start({})
    local before = k.problems:count()
    local step = settled(c, api)
    t.ok(step ~= nil, "the step is still offered")
    t.eq(step and step.place, nil, "no place: none is made up")
    t.eq(step and step.label, WM().LABEL, "the plain label")
    t.eq(api.lines(), WM().Lines(words(SWORDS)), "the words as before")
    t.eq(k.problems:count(), before, "no problem raised")
end

-- Zen's review of e71c26a6 (lead section 616): a weapon master the player
-- has visited on this map is not pointed at when the table has that name
-- without the wanted kind; the step then has no place of its own and
-- Elsewhere picks the one who teaches it. Names as the table has them
-- (Bixi Wobblebonk: no axes; Buliwyf Stonehand: axes); the places are made
-- up. Red before: WM.Of points at the visited master whatever they teach.
T["weapon master taught: a visited master listed without the kind is passed over for the one who teaches it"] = function(t)
    if not names(t) then return end
    local S = WM()
    local AXES, DAGGERS = 0, 15
    local BIXI, BULIWYF = "Bixi Wobblebonk", "Buliwyf Stonehand"
    local list = N.WeaponMasterNames
    local fits = type(list[BIXI]) == "table" and type(list[BULIWYF]) == "table"
        and list[BIXI].skills[AXES] ~= true and list[BIXI].skills[DAGGERS] == true
        and list[BULIWYF].skills[AXES] == true
    t.ok(fits, "the table has Bixi without axes and with daggers, and Buliwyf with axes")
    if not fits then return end
    local here = { map = HERE_MAP, x = 0.5, y = 0.5 }
    local visited = { [BIXI] = { map = HERE_MAP, x = 0.51, y = 0.5, roles = { weaponMaster = true } } }
    local step = S.Of({ subclassID = AXES, skill = "Axes" }, here, visited)
    t.ok(type(step) == "table", "a step for axes")
    if type(step) ~= "table" then return end
    t.eq(step.place, nil, "the visited master who does not teach axes is not pointed at")
    t.eq(step.name, nil, "nor named")
    local function place(ask)
        if type(ask) == "table" and type(ask.only) == "table" and ask.only[BULIWYF] == true
            and ask.only[BIXI] ~= true then
            return { name = BULIWYF, map = HERE_MAP, x = 0.6, y = 0.5 }, PP().QUESTIE
        end
        return nil
    end
    step = S.Elsewhere(step, place)
    t.eq(step.name, BULIWYF, "Elsewhere picks the one who teaches axes")
    t.eq(step.place, { map = HERE_MAP, x = 0.6, y = 0.5 })
    -- The same visited master still wins for a kind the table has them with.
    local daggers = S.Of({ subclassID = DAGGERS, skill = "Daggers" }, here, visited)
    t.eq(daggers and daggers.name, BIXI, "wanted daggers: the visited master is pointed at")
    -- One the table does not name stays allowed, whatever is wanted.
    local own = S.Of({ subclassID = AXES, skill = "Axes" }, here,
        { [UNLISTED] = { map = HERE_MAP, x = 0.52, y = 0.5, roles = { weaponMaster = true } } })
    t.eq(own and own.name, UNLISTED, "a visited master the table does not name is still pointed at")
    -- With no kind read, nothing is left out.
    local any = S.Of({ skill = "Axes" }, here, visited)
    t.eq(any and any.name, BIXI, "no kind known: as before")
end

return T
