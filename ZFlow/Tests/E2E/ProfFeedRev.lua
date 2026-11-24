local _, ns = ...
-- P-PATH-2 follow-up (lead section 450, "Revision rules"): the arrow's feed
-- (Nav/ProfFeed.lua) and the path panel (UI/ProfPathPanel.lua) read ONE plan,
-- made in one place (ProfPath.Live), and compare its rev. The whole add-on on
-- a fake client, the real Items/ProfPath.lua, nothing stands in for the plan.
-- Look only. Offline test, fake client lines. Not tested in game.
--
-- Red before the code: ns.profFeed has no rev and its pick carries none.
local tests = {}

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = {
        facts = { profSkill = { Blacksmithing = { skill = 50, max = 75 } } },
    } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapCont(1411, 1)
    c.setBagItems({})
    c.setProfessions({ "Blacksmithing" })
    c.setRecipes({ profession = 164, name = "Blacksmithing", skill = 50, max = 75, recipes = {} })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

tests["prof rev: the feed gives the path's rev, and its pick carries it"] = function(t)
    local _, addon = start()
    local feed = addon.profFeed
    t.eq(type(feed.rev), "function", "the feed has a rev")
    if type(feed.rev) ~= "function" then return end
    local rev = feed.rev("Blacksmithing")
    t.eq(type(rev), "number", "a number for a profession with a path")
    local path = feed.path("Blacksmithing")
    t.ok(type(path) == "table" and path.rev == rev, "the same plan the rev came from")
    local _, pick = feed.step()
    t.ok(type(pick) == "table" and pick.rev == rev, "the arrow's pick carries the rev of its profession")
    t.eq(feed.rev("Tailoring"), nil, "no reading: no rev, never 0")
end

tests["prof rev: a bag change bumps it once; asking again does not"] = function(t)
    local c, addon = start()
    local feed = addon.profFeed
    if type(feed.rev) ~= "function" then return t.ok(false, "the feed has no rev") end
    local path = feed.path("Blacksmithing")
    local mat = path and path.materials and path.materials[1]
    t.ok(type(mat) == "table" and mat.item ~= nil, "the real path needs a material")
    if type(mat) ~= "table" then return end
    local before = feed.rev("Blacksmithing")
    t.eq(feed.rev("Blacksmithing"), before, "nothing changed: the same rev")
    c.setBagItems({ { item = mat.item, count = 1 } })
    t.eq(feed.rev("Blacksmithing"), before + 1, "one more in the bags: one more rev")
    t.eq(feed.rev("Blacksmithing"), before + 1, "and it stays")
end

tests["prof rev: the panel and the feed read one plan, so neither bumps the other"] = function(t)
    local c, addon = start()
    local feed = addon.profFeed
    if type(feed.rev) ~= "function" then return t.ok(false, "the feed has no rev") end
    local before = feed.rev("Blacksmithing")
    c.fire("TRADE_SKILL_SHOW")
    t.eq(feed.rev("Blacksmithing"), before, "the panel drew: same rev")
    c.fire("TRADE_SKILL_LIST_UPDATE")
    c.advance(5, 20)
    t.eq(feed.rev("Blacksmithing"), before, "panel and arrow took turns: same rev")
    -- The open window is the newest reading for both readers.
    c.setRecipes({ profession = 164, name = "Blacksmithing", skill = 51, max = 75, recipes = {} })
    c.fire("TRADE_SKILL_LIST_UPDATE")
    local after = feed.rev("Blacksmithing")
    t.eq(after, before + 1, "a skill point in the open window: one more rev")
    c.fire("TRADE_SKILL_LIST_UPDATE")
    c.advance(5, 20)
    t.eq(feed.rev("Blacksmithing"), after, "and both stay on it")
end

return tests
