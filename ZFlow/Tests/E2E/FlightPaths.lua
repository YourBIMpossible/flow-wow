local _, ns = ...

-- Flight paths to learn as you pass (S30), on the whole add-on loaded on
-- a fake client. The real entry: the player talks to a flight master this
-- account learned of (GOSSIP_SHOW with the NPC read), and either a flight
-- map opens (the path is theirs: noted, no line) or none opens within
-- FlightPaths.WAIT seconds (one chat line, noted with the level, offered
-- again after a level). Made-up npcs and places. Not tested in game.

local tests = {}
local FP = ns.FlightPaths

local MAP = 1411
local MASTER = "Test Windrider"

local function masters(factions)
    return { learned = { places = { npcs = {
        [MASTER] = { map = MAP, x = 0.52, y = 0.5, roles = { flight = true }, kind = "flight",
                     factions = factions, seen = 100 },
    } } } }
end

-- opts.account: the account table (default: one Horde flight master).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or masters({ Horde = true }))
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setClock(500)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function count(c, text)
    local n = 0
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then n = n + 1 end
    end
    return n
end

local function charNote(c, path)
    local char = c.saved(ns.id.charDB)
    local l = type(char) == "table" and char.learned
    local f = type(l) == "table" and l.flights
    return type(f) == "table" and f[path] or nil
end

local function talk(c, name)
    c.setServiceNpc("Creature-0-0-0-0-9901-0", name)
    c.fire("GOSSIP_SHOW")
end

local NONE_LINE = " has no flight path for you yet."

tests["flight paths: a master this account met and this character has not is a goal and a step"] = function(t)
    local _, addon = boot()
    local use = addon.use(FP.NAME)
    t.ok(type(use) == "table", "the module is there")
    local goals = use.Goals()
    t.eq(#goals, 1, "one goal")
    t.eq(goals[1] and goals[1].text, "Learn the flight path: " .. MASTER)
    t.eq(goals[1] and goals[1].optional, nil, "20 yards away: not optional")
    local step = use.Step()
    t.eq(step and step.label, "Learn the flight path: " .. MASTER, "the step's label")
    t.eq(step and step.place and step.place.map, MAP)
end

tests["flight paths: talking with no flight map says so once, and waits a level"] = function(t)
    local c, addon = boot()
    talk(c, MASTER)
    c.advance(1, 4)
    t.eq(count(c, NONE_LINE), 0, "nothing said before the wait is over")
    c.advance(FP.WAIT + 1, 8)
    t.eq(count(c, ns.id.title .. ": " .. MASTER .. NONE_LINE), 1, "one line, with the title")
    local note = charNote(c, "none")
    t.eq(note and note[MASTER] and note[MASTER].level, 20, "noted with the level")
    t.eq(note and note[MASTER] and note[MASTER].at, 500, "and the clock")
    t.eq(#addon.use(FP.NAME).Goals(), 0, "no goal at this level")
    talk(c, MASTER)
    c.advance(FP.WAIT + 1, 8)
    t.eq(count(c, NONE_LINE), 1, "not a goal now: no second line")
    c.setLevel(21)
    t.eq(#addon.use(FP.NAME).Goals(), 1, "a level later it is offered again")
end

tests["flight paths: a flight map opening in time notes the path as yours and says nothing"] = function(t)
    local c, addon = boot()
    talk(c, MASTER)
    c.advance(1, 4)
    c.fire("TAXIMAP_OPENED")
    c.fire("TAXIMAP_CLOSED")
    c.advance(FP.WAIT + 2, 8)
    t.eq(count(c, NONE_LINE), 0, "no line")
    local talked = charNote(c, "talked")
    t.eq(talked and talked[MASTER], true, "the path is noted as yours")
    t.eq(charNote(c, "none"), nil, "no 'none' note")
    t.eq(#addon.use(FP.NAME).Goals(), 0, "no goal any more")
    t.eq(addon.use(FP.NAME).Step(), nil, "no step")
end

tests["flight paths: unknown data says nothing wrong"] = function(t)
    -- A master with no faction on record, and a talk with no NPC read.
    local c, addon = boot({ account = masters(nil) })
    t.eq(#addon.use(FP.NAME).Goals(), 0, "no faction on record: not a goal")
    talk(c, MASTER)
    c.advance(FP.WAIT + 2, 8)
    c.setServiceNpc(nil, nil)
    c.fire("GOSSIP_SHOW")
    c.advance(FP.WAIT + 2, 8)
    t.eq(count(c, NONE_LINE), 0, "no line")
    t.eq(count(c, MASTER), 0, "the master is not named in chat")
    t.eq(charNote(c, "none"), nil, "nothing noted")
    t.eq(addon.use(FP.NAME).Step(), nil, "no step")
end

tests["flight paths: the setting off gives no goal and writes nothing"] = function(t)
    local c, addon = boot()
    addon.settings:set(FP.SETTING, false)
    t.eq(#addon.use(FP.NAME).Goals(), 0, "no goals")
    talk(c, MASTER)
    c.advance(FP.WAIT + 2, 8)
    t.eq(count(c, NONE_LINE), 0, "no line")
    t.eq(charNote(c, "none"), nil, "nothing noted")
end

return tests
