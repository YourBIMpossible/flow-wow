local _, ns = ...
-- Lead section 447 item 5 (finding F3): the profession arrow stood on the
-- quest arrow at load and moved to its place only after a restack or a
-- move. Through the real entry: the whole add-on on a fake client, a
-- second login with the saved data of the first. While the game gives no
-- facing (at load, or for a moment after) the profession arrow could not
-- point, its room in the stack was dropped and its frame took the quest
-- arrow's place. The player now sees two arrows from the first frame of
-- the login, and they stay there when the facing comes. Since lead section
-- 476 the profession arrow is the quest arrow's echo: behind it and below
-- it. The quest is north and the anvil east, so the echo is slid straight
-- down, one arrow and a gap; with no facing it stands there too.
-- Made-up recipes, items and places. Offline test only: Needs game test.
local tests = {}
local N = ns.Nav

local ORE, BAR, BELT_ITEM = 1, 2, 50
local HERE = 1411

local function setup(c, account, char)
    c.setSaved(ns.id.accountDB, account); c.setSaved(ns.id.charDB, char)
    c.setScreen(1024, 768); c.setZone(1, HERE); c.setFacing(0); c.setFaction("Horde")
    c.setPosition(HERE, 0.5, 0.5); c.setMapSize(HERE, 1000, 500); c.setMapCont(HERE, 1)
    c.setItemInfo({ [ORE] = { name = "Test Ore" }, [BAR] = { name = "Test Bar" }, [BELT_ITEM] = { name = "Test Belt" } })
    c.setBagItems({ { item = BAR, count = 6 } })
    c.setProfessions({ "Blacksmithing" })
    c.setSkillRanks({ Blacksmithing = { rank = 50, max = 75 } })
    c.setRecipeSchematic(901, { makes = BELT_ITEM, yield = 1, mats = { [BAR] = 2 } })
    local db = {}
    function db.GetQuest(id) if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end end
    function db.GetNPC(id) if id == 9002 then return { name = "Far Wolf", spawns = { [12] = { { 50, 30 } } } } end end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return ({ [12] = HERE })[a] end
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
end

-- A first session: an anvil seen earlier, the profession window opened
-- once. -> the saved tables a second login starts from.
local function firstSession()
    local c = ns.make.fakeClient()
    setup(c, { learned = { keyStations = { { kind = "anvil", map = HERE, x = 0.6, y = 0.5 } } } }, {})
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    c.setRecipes({ profession = 164, name = "Blacksmithing", skill = 50, max = 75,
        recipes = { { id = 901, name = "Test Belt", learned = true, difficulty = "optimal" } } })
    c.fire("TRADE_SKILL_SHOW"); c.fire("TRADE_SKILL_LIST_UPDATE"); c.advance(2, 8)
    c.setRecipes(nil); c.fire("TRADE_SKILL_CLOSE"); c.advance(1, 4)
    return c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
end

local DROP = 56 + N.ARROW_GAP

local function stacked(t, c, when)
    local q, p = c.arrows[1], c.arrows[2]
    t.eq(q.shown, true, when .. ": the quest arrow")
    t.eq(p.shown, true, when .. ": the profession arrow")
    t.eq(p.point[3], q.point[3], when .. ": same column")
    t.eq(q.point[4] - p.point[4], DROP, when .. ": the echo one arrow and a gap below, not on it")
    t.eq(q.under, false, when .. ": the quest arrow in front")
    t.eq(p.under, true, when .. ": the echo behind it")
    t.ok(p.lookIs ~= "needle", when .. ": no needle")
end

tests["arrow load: no facing yet at login: two arrows, stacked, from the first frame"] = function(t)
    local account, char = firstSession()
    local c = ns.make.fakeClient()
    setup(c, account, char)
    c.setFacing(nil)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN")
    local before = addon.problems:count()
    c.advance(2, 8)
    stacked(t, c, "no facing")
    t.ok((c.arrows[2].lines or {})[1] ~= nil, "the profession step is said")
    c.fire("PLAYER_ENTERING_WORLD")
    c.setFacing(0)
    c.advance(2, 8)
    stacked(t, c, "facing back")
    t.ok(c.arrows[2].drawn.body ~= 0, "the echo is drawn once it can point")
    t.eq(addon.problems:count(), before)
end

tests["arrow load: facing lost for a moment: the profession arrow keeps its place"] = function(t)
    local account, char = firstSession()
    local c = ns.make.fakeClient()
    setup(c, account, char)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    local before = addon.problems:count()
    stacked(t, c, "loaded")
    c.setFacing(nil); c.advance(2, 8)
    stacked(t, c, "facing lost")
    c.setFacing(0); c.advance(2, 8)
    stacked(t, c, "facing back")
    t.eq(addon.problems:count(), before)
end

return tests
