-- Weapon master step, a place with none saved (A2-07): the "visit a weapon
-- master" step (Nav/WeaponMasterStep.lua) had a place only from a weapon
-- master this account visited on the player's map. With none, it now asks
-- the profession feed (Nav/ProfFeed.lua, the one owner of the Questie
-- reader) for the nearest weapon master the player's own Questie knows
-- (Nav/ProfStep.lua N.ProfPlace: an NPC whose sub-name is
-- PP.WEAPON_MASTER, friendly to the player's faction, on this map, else on
-- another map of this continent). No Questie, or none found: words only,
-- as before. Made-up names and places, test only. Look only. Not seen in
-- game.
--
-- Red before the code: no weapon master is read from Questie, the feed
-- gives no Place and the step asks nobody.
local _, ns = ...

local T = {}
local N = ns.Nav

local STR = "ITEM_MOD_STRENGTH_SHORT"
local SWORD = "item:2001"
local HERE_MAP, NEXT_MAP, OVERSEA_MAP = 1454, 1411, 1453
local AREA, NEXT_AREA, OVERSEA_AREA = 21, 22, 23
local MASTER, THEIR_MASTER, MERCHANT, NEXT_MASTER, OVERSEA_MASTER = 8101, 8102, 8103, 8104, 8105

local function WM() return ns.WeaponMasterStep end
local function PP() return N.ProfPlace end

local function has(t)
    local S, P = WM(), PP()
    local ok = type(S) == "table" and type(P) == "table" and type(P.Pick) == "function"
        and type(P.WEAPON_MASTER) == "string" and type(S.ASK) == "string"
    t.ok(ok, "N.ProfPlace gives Pick and WEAPON_MASTER; the step names the kind it asks for")
    return ok
end

local function packs()
    return { WARRIOR = {
        weights = { dps = { evidence = "first guess", values = { [STR] = 1 } } },
        proficiency = { evidence = "first guess", [2] = { [0] = true, [7] = true } },
    } }
end

-- Questie's NPCs by id. only: the ids that are there (nil: every one).
local function npcsOf(only)
    local title = PP().WEAPON_MASTER
    local all = {
        [MASTER] = { name = "Master Test", subName = title, friendlyToFaction = "H",
                     spawns = { [AREA] = { { 60, 50 } } } },
        [THEIR_MASTER] = { name = "Their Master", subName = title, friendlyToFaction = "A",
                           spawns = { [AREA] = { { 51, 50 } } } },
        [MERCHANT] = { name = "Blade Seller", subName = title .. "s Guild", friendlyToFaction = "H",
                       spawns = { [AREA] = { { 50, 50 } } } },
        [NEXT_MASTER] = { name = "Next Master", subName = title, friendlyToFaction = "AH",
                          spawns = { [NEXT_AREA] = { { 30, 40 } } } },
        [OVERSEA_MASTER] = { name = "Oversea Master", subName = title, friendlyToFaction = "H",
                             spawns = { [OVERSEA_AREA] = { { 50, 50 } } } },
    }
    if not only then return all end
    local out = {}
    for _, id in ipairs(only) do out[id] = all[id] end
    return out
end

-- A stand-in for Questie's two modules. state.scans counts the times its
-- NPCs were gone through (as Tests/E2E/ProfPlaceArrow.lua).
local function questie(state, only)
    local npcs = npcsOf(only)
    local first
    for id in pairs(npcs) do
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
    function zones.GetUiMapIdByAreaId(a)
        return ({ [AREA] = HERE_MAP, [NEXT_AREA] = NEXT_MAP, [OVERSEA_AREA] = OVERSEA_MAP })[a]
    end
    return db, zones
end

-- ------------------------------------------------------------------ pure

local function known(over)
    local k = {
        here = { map = HERE_MAP, x = 0.5, y = 0.5, faction = "Horde" },
        contOf = function(map) return ({ [HERE_MAP] = 1, [NEXT_MAP] = 1, [OVERSEA_MAP] = 2 })[map] end,
    }
    for key, v in pairs(over or {}) do k[key] = v end
    return k
end

T["weapon master place: the step kind asked for is a place kind of its own"] = function(t)
    if not has(t) then return end
    local kind = PP().KIND[WM().ASK]
    t.ok(kind ~= nil, "the kind is known to N.ProfPlace")
    t.eq(PP().ROLE[kind], "weaponMaster", "its saved role is the one Nav/WeaponMasterSeen.lua writes")
end

T["weapon master place: Questie's NPCs with that exact sub-name are collected, no other"] = function(t)
    if not has(t) then return end
    local found, n = PP().Scan(questie({}, { MASTER, THEIR_MASTER, MERCHANT }))
    t.eq(found.weaponMaster, {
        { name = "Master Test", map = HERE_MAP, x = 0.6, y = 0.5, side = "H" },
        { name = "Their Master", map = HERE_MAP, x = 0.51, y = 0.5, side = "A" },
    }, "the two weapon masters; a longer sub-name is not one")
    t.eq(n, 2, "two places in all")
    t.eq(found.trainer, {}, "and they are no profession trainers")
end

T["weapon master place: Questie's of the player's faction on this map, with its name and where from"] = function(t)
    if not has(t) then return end
    local found = PP().Scan(questie({}))
    local step = { kind = WM().ASK }
    local k = known({ questie = function() return found end })
    local to, from = PP().Pick(step, nil, k)
    t.eq(to, { name = "Master Test", map = HERE_MAP, x = 0.6, y = 0.5 },
        "the player's faction's, not the nearer one of the other faction")
    t.eq(from, PP().QUESTIE, "and it says the place is Questie's")
    t.eq(PP().Of(step, nil, k), { map = HERE_MAP, x = 0.6, y = 0.5 }, "Of gives the same place, bare")
    t.eq(found.weaponMaster[1].name, "Master Test", "the kept answer is not changed")
end

T["weapon master place: a saved one on this map wins and Questie is not asked"] = function(t)
    if not has(t) then return end
    local found = PP().Scan(questie({}))
    local asked = 0
    local k = known({
        questie = function()
            asked = asked + 1
            return found
        end,
        npcs = {
            ["Saved Master"] = { map = HERE_MAP, x = 0.9, y = 0.5, roles = { weaponMaster = true } },
            ["A Trainer"] = { map = HERE_MAP, x = 0.5, y = 0.5, roles = { trainer = true } },
        },
    })
    local to, from = PP().Pick({ kind = WM().ASK }, nil, k)
    t.eq(to, { name = "Saved Master", map = HERE_MAP, x = 0.9, y = 0.5 }, "the saved one, farther as it is")
    t.eq(from, PP().SAVED, "and it says the place is a saved one")
    t.eq(asked, 0, "Questie is not asked at all")
end

T["weapon master place: none on this map, the one on another map of this continent"] = function(t)
    if not has(t) then return end
    local found = PP().Scan(questie({}, { THEIR_MASTER, NEXT_MASTER, OVERSEA_MASTER }))
    local k = known({ questie = function() return found end })
    local to, from = PP().Pick({ kind = WM().ASK }, nil, k)
    t.eq(to, { name = "Next Master", map = NEXT_MAP, x = 0.3, y = 0.4 },
        "the next zone's, never the other faction's here or the one across the sea")
    t.eq(from, PP().QUESTIE)
    local sea = PP().Scan(questie({}, { THEIR_MASTER, OVERSEA_MASTER }))
    k.questie = function() return sea end
    t.eq(PP().Pick({ kind = WM().ASK }, nil, k), nil, "only the other faction's and one across the sea: no place")
    k.questie = nil
    t.eq(PP().Pick({ kind = WM().ASK }, nil, k), nil, "no Questie: no place")
end

-- ---------------------------------------------------------------- module

-- opts: npcs (the account's learned.places.npcs), state (a table: the
-- made-up Questie is there and counts into it), only (its NPC ids),
-- combat, faction.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = {}
    if opts.npcs then account.learned = { places = { npcs = opts.npcs } } end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setFaction(opts.faction or "Horde")
    c.setPosition(HERE_MAP, 0.5, 0.5)
    c.setMapSize(HERE_MAP, 1000, 500)
    c.setMapCont(HERE_MAP, 1); c.setMapCont(NEXT_MAP, 1); c.setMapCont(OVERSEA_MAP, 2)
    c.setItem(SWORD, { kind = "INVTYPE_WEAPON", stats = { [STR] = 5 }, classID = 2, subclassID = 7,
                       minLevel = 1, unmet = { "Swords" } })
    c.setWorn(16, false); c.setWorn(17, false)
    c.setDualWield(false)
    c.setWeaponSkills({ "Axes", "Defense" })
    if opts.combat then c.setCombat(true) end
    if opts.state then
        local db, zones = questie(opts.state, opts.only)
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

-- The step once Questie had its frames: asked (so the read is wanted), a
-- few frames, asked again.
local function settled(c, api)
    api.step()
    c.advance(1, 20)
    return api.step()
end

local function wordsOnly()
    return WM().Lines(WM().Of({ subclassID = 7, skill = "Swords" }, nil, nil))
end

T["weapon master place module: Questie's weapon master of the player's faction gives the step a place"] = function(t)
    if not has(t) then return end
    local state = {}
    local k, c, api = start({ state = state })
    local before = k.problems:count()
    local first = api.step()
    t.eq(first and first.place, nil, "the first ask reads nothing itself: words only")
    c.advance(1, 20)
    local step = api.step()
    t.eq(step and step.place, { map = HERE_MAP, x = 0.6, y = 0.5 }, "then Questie's weapon master, of this faction")
    t.eq(step and step.name, "Master Test", "with its name")
    t.eq(step and step.skill, "Swords", "for the skill wanted")
    t.eq(step and step.kind, WM().KIND, "the same kind of step")
    t.eq(step and step.unvisited, true, "marked as one the player has not visited")
    t.eq(step and step.detail, WM().NOT_KNOWN, "the arrow's own line says what is not known")
    t.eq(api.lines(), { WM().UNVISITED:format("Swords", "Master Test"), WM().NOT_KNOWN },
        "the words say it too, never that the player has seen them")
    t.eq(k.use(WM().NAME).Step().place, { map = HERE_MAP, x = 0.6, y = 0.5 }, "others get the same by name")
    t.eq(k.problems:count(), before, "no problem raised")
end

T["weapon master place module: the other faction's weapon master is not pointed at"] = function(t)
    if not has(t) then return end
    local state = {}
    local _, c, api = start({ state = state, only = { THEIR_MASTER, MERCHANT } })
    local step = settled(c, api)
    t.ok(step ~= nil, "the step is still offered")
    t.eq(step and step.place, nil, "no place")
    t.eq(step and step.name, nil, "no name")
    t.eq(step and step.unvisited, nil, "nothing marked")
    t.eq(api.lines(), wordsOnly(), "words only, as with nothing known")
    -- The same Questie for the other faction: theirs is theirs to use.
    local _, c2, api2 = start({ state = {}, only = { THEIR_MASTER, MERCHANT }, faction = "Alliance" })
    local theirs = settled(c2, api2)
    t.eq(theirs and theirs.place, { map = HERE_MAP, x = 0.51, y = 0.5 }, "an Alliance player is pointed at it")
end

T["weapon master place module: a saved weapon master on this map still wins"] = function(t)
    if not has(t) then return end
    local state = {}
    local npcs = { ["Saved Master"] = { map = HERE_MAP, x = 0.9, y = 0.5, roles = { weaponMaster = true } } }
    local _, c, api = start({ state = state, npcs = npcs })
    local step = settled(c, api)
    t.eq(step and step.place, { map = HERE_MAP, x = 0.9, y = 0.5 }, "the saved one, farther as it is")
    t.eq(step and step.name, "Saved Master")
    t.eq(step and step.unvisited, nil, "not marked: the player has visited this one")
    t.eq(step and step.detail, nil, "no line more")
    t.eq(api.lines(), WM().Lines(WM().Of({ subclassID = 7, skill = "Swords" },
        { map = HERE_MAP, x = 0.5, y = 0.5 }, npcs)), "the words for a weapon master seen")
    c.advance(30, 120)
    t.eq(state.scans, nil, "and Questie was not gone through at all")
end

T["weapon master place module: a saved one on another map of this continent is one the player has seen"] = function(t)
    if not has(t) then return end
    local npcs = { ["Saved Next"] = { map = NEXT_MAP, x = 0.2, y = 0.2, roles = { weaponMaster = true } } }
    local _, c, api = start({ npcs = npcs })
    local step = settled(c, api)
    t.eq(step and step.place, { map = NEXT_MAP, x = 0.2, y = 0.2 }, "pointed at, in the next zone")
    t.eq(step and step.name, "Saved Next")
    t.eq(step and step.unvisited, nil, "not marked as not visited")
end

T["weapon master place module: no Questie leaves the step words only"] = function(t)
    if not has(t) then return end
    local k, c, api = start()
    local before = k.problems:count()
    local step = settled(c, api)
    t.ok(step ~= nil, "the step is still offered")
    t.eq(step and step.place, nil, "no place: none is made up")
    t.eq(step and step.label, WM().LABEL, "the plain label")
    t.eq(api.lines(), wordsOnly(), "the words as before")
    t.eq(k.problems:count(), before, "no problem raised")
end

T["weapon master place module: Questie's NPCs are gone through once, not on every ask"] = function(t)
    if not has(t) then return end
    local state = {}
    local _, c, api = start({ state = state })
    settled(c, api)
    t.eq(state.scans, 1, "gone through once")
    for _ = 1, 5 do
        api.step()
        api.lines()
        c.advance(6, 24)
    end
    t.eq(state.scans, 1, "still once, after many asks and frames")
    t.eq(api.step().place, { map = HERE_MAP, x = 0.6, y = 0.5 }, "and the step keeps its place")
end

T["weapon master place module: Questie is not read in combat, and is read once combat ends"] = function(t)
    if not has(t) then return end
    local state = {}
    local _, c, api = start({ state = state, combat = true })
    api.step()
    c.advance(30, 120)
    t.eq(state.scans, nil, "in combat: Questie's NPCs are not gone through")
    t.eq(api.step().place, nil, "and the step stays in words")
    c.setCombat(false)
    c.advance(1, 20)
    t.eq(state.scans, 1, "combat over: gone through once")
    t.eq(api.step().place, { map = HERE_MAP, x = 0.6, y = 0.5 }, "and the step has its place")
end

T["weapon master place module: nothing wanted, or the step off, and Questie is never read"] = function(t)
    if not has(t) then return end
    local state = {}
    local k, c, api = start({ state = state })
    k.settings:set(WM().SETTING, false)
    t.eq(api.step(), nil, "off: no step")
    c.advance(30, 120)
    t.eq(state.scans, nil, "and Questie was not gone through")
end

return T
