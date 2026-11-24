local _, ns = ...
-- Lead section 467, lane A display words, against Flow (origin/zflow):
--   A1-14  the corpse run (Flow N:ShowCorpse): "Your corpse" over
--          "Release your spirit, then follow the red arrow" while not
--          released, over "On another map: follow the graveyard path"
--          when the corpse is elsewhere, over "Here: resurrect" at it.
--   A1-16  quests in the log and no Questie: "No directions yet" over
--          "Install Questie + QuestieDB for quest locations".
--   A1-09  an objective spread over several points: "You're in the area"
--          within 45 yd of the nearest one (Flow AREA), not the yards.
--   A1-38  the waypoint hint in chat the first two times the add-on
--          starts for this account, never on the third.
-- Whole add-on loaded the way the game loads it (ns.offline.addon) on a
-- fake client; made-up places, quests and names. Not tested in game.
-- Fails before (f31dd929): each of these lines is missing or worded
-- otherwise ("Corpse", "corpse is on another map", "you're here", "No
-- route known to this objective", "30 yd E", no hint).
local tests = {}
local A = ns.Arrow

local MAP = 1411

-- opts: account (saved), log, questie (QuestieDB stand-in), dead, ghost,
-- corpse ({ x, y } on MAP, or false).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account or { layout = { arrowIntroSeen = true, wayTips = 2 } }
    c.setSaved(ns.id.accountDB, account)
    c.setScreen(1024, 768)
    c.setZone(1, MAP); c.setFacing(0); c.setFaction("Horde")
    c.setPosition(MAP, 0.5, 0.5); c.setMapSize(MAP, 1000, 500)
    if opts.log then c.setQuestLog(opts.log) end
    if opts.questie then
        c.setQuestieModule("QuestieDB", opts.questie)
        c.setQuestieModule("ZoneDB", { GetUiMapIdByAreaId = function(_, area) return ({ [12] = MAP })[area] end })
    end
    if opts.dead ~= nil then c.setDead(opts.dead) end
    if opts.ghost ~= nil then c.setGhost(opts.ghost) end
    if opts.corpse == false then c.setCorpse(false)
    elseif opts.corpse then c.setCorpse(MAP, opts.corpse[1], opts.corpse[2]) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c) return c.arrows[1].lines end

-- Quest 101's boars: spawns at the given map shares (x, y in hundredths).
local function questie(spawns)
    local db = {}
    function db.GetQuest(id)
        if id == 101 then return { ObjectiveData = { { Type = "monster", Id = 9001 } } } end
        return nil
    end
    function db:GetNPC(id)
        if id == 9001 then return { name = "Young Boar", spawns = { [12] = spawns } } end
        return nil
    end
    return db
end

local BOARS = { { id = 101, title = "Boar Trouble", objectives = { { text = "Boars slain: 2/8" } } } }

tests["arrow words: dead, not released: your corpse, release, then follow the red arrow"] = function(t)
    local c = start({ dead = true, ghost = false })
    t.eq(said(c), { "Your corpse", "Release your spirit, then follow the red arrow" })
end

tests["arrow words: a ghost with the corpse on another map: follow the graveyard path"] = function(t)
    local c = start({ dead = true, ghost = true, corpse = false })
    t.eq(said(c), { "Your corpse", "On another map: follow the graveyard path" })
end

tests["arrow words: a ghost at the corpse: here, resurrect"] = function(t)
    local c = start({ dead = true, ghost = true, corpse = { 0.51, 0.5 } })
    t.eq(said(c), { "Your corpse", "Here: resurrect" })
end

tests["arrow words: quests and no Questie: no directions yet, install Questie"] = function(t)
    local c = start({ log = { { id = 101, title = "A Made-up Errand", objectives = {} } } })
    t.eq(said(c), { "No directions yet", "Install Questie + QuestieDB for quest locations" })
    t.eq(A.NO_DIRECTIONS, "No directions yet")
end

tests["arrow words: an empty log with no Questie still says no quest tracked"] = function(t)
    local c = start({ log = {} })
    t.eq(said(c), { A.NO_QUEST })
end

tests["arrow words: 30 yd from the nearest of several spawns: you're in the area"] = function(t)
    local c = start({ log = BOARS, questie = questie({ { 53, 50 }, { 90, 50 } }) })
    t.eq(said(c), { "Boar Trouble", "Boars slain: 2/8", "You're in the area" })
end

tests["arrow words: one spawn 30 yd away is a point, not an area: the yards"] = function(t)
    local c = start({ log = BOARS, questie = questie({ { 53, 50 } }) })
    local l = said(c)
    t.eq(l[3] ~= nil and l[3]:find("^30 yd") ~= nil, true, tostring(l[3]))
end

tests["arrow words: the waypoint hint the first two times, never the third"] = function(t)
    local function hinted(c)
        for _, line in ipairs(c.printed) do
            if tostring(line):find(ns.Nav.WayTips.TEXT, 1, true) then return true end
        end
        return false
    end
    local c1 = start({ account = { layout = { arrowIntroSeen = true } } })
    t.eq(hinted(c1), true, "first")
    t.eq(c1.saved(ns.id.accountDB).layout.wayTips, 1)
    local c2 = start({ account = { layout = { arrowIntroSeen = true, wayTips = 1 } } })
    t.eq(hinted(c2), true, "second")
    t.eq(c2.saved(ns.id.accountDB).layout.wayTips, 2)
    local c3 = start({ account = { layout = { arrowIntroSeen = true, wayTips = 2 } } })
    t.eq(hinted(c3), false, "third: not said")
    t.ok(ns.Nav.WayTips.TEXT:find("/way <x> <y>", 1, true) ~= nil, "it names the command")
end

return tests
