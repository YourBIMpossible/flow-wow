local _, ns = ...

-- End to end (lead section 485, parity row A1-16): with no quest step and
-- no quest data (Questie's database not loaded) the quest arrow says Flow's
-- "No directions yet" and the Install Questie line; with Questie it keeps
-- its own why line. On the whole add-on with a fake client. Not tested in
-- game.
-- Fails before: the arrow says "No quest tracked" with or without Questie.

local tests = {}

local function start(withQuestie)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setZone(1, 1411); c.setFacing(0); c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500)
    if withQuestie then c.setQuestieModule("QuestieDB", {}) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function questLines(c)
    local q = c.arrows and c.arrows[1]
    return q and q.shown and q.lines or nil
end

tests["no directions e2e: no quest data says so and how to get it"] = function(t)
    local c = start(false)
    local ND = ns.Nav.NoDirections
    t.eq(questLines(c), { ND.TITLE, ND.SUB })
    t.eq(ND.TITLE, "No directions yet")
    t.eq(ND.SUB, "Install Questie + QuestieDB for quest locations")
end

tests["no directions e2e: with Questie the arrow's own why line stands"] = function(t)
    local c = start(true)
    t.eq(questLines(c), { ns.Arrow.NO_QUEST })
end

tests["no directions e2e: the pure words"] = function(t)
    local ND = ns.Nav.NoDirections
    t.eq(ND.Words(true), nil)
    t.eq(ND.Words(false), { title = ND.TITLE, sub = ND.SUB })
end

return tests
