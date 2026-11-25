local _, ns = ...

-- The travel action (S33, Nav/TravelIcon.lua) on the quest arrow, on the
-- whole add-on loaded on a fake client. The real entry: the arrow's quest
-- step goes through Travel's Via, which asks N.TravelAction which of the
-- cast and the stone takes the arrow's place. A druid who knows
-- Teleport: Moonglade, with a quest in Moonglade, is told
-- "Cast Teleport: Moonglade", then the quest; the word "walk" turns it
-- off for this step (N.TravelSkip). A spell still to learn is no action.
-- Nothing casts. Made-up quests and names. Not tested in game.

local tests = {}
local N, Travel = ns.Nav, ns.Nav.Travel

local HERE, MOONGLADE = 1411, 1450
local SPELL, SPELL_ID = "Teleport: Moonglade", 18960
local CAST = "Cast " .. SPELL

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Moon Wolf", spawns = { [50] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [50] = MOONGLADE })[area] end
    return db, zones
end

-- opts.known: what the client says of the spell (nil: no answer);
-- opts.noId: the client gives no id for the spell's name.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, HERE); c.setPosition(HERE, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(HERE, 1000, 1000); c.setMapCont(HERE, 1)
    c.setMapSize(MOONGLADE, 1000, 1000); c.setMapCont(MOONGLADE, 1)
    c.setMapName(MOONGLADE, "Moonglade")
    c.setClass("DRUID"); c.setFaction("Horde"); c.setLevel(20)
    if not opts.noId then c.setSpellId(SPELL, SPELL_ID) end
    c.setSpell(SPELL_ID, { known = opts.known })
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function lines(c)
    local a = c.arrows[1]
    return a and a.lines or {}
end

local function has(list, text)
    for _, l in ipairs(list) do
        if l == text then return true end
    end
    return false
end

local function hasPrefix(list, prefix)
    for _, l in ipairs(list) do
        if type(l) == "string" and l:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

tests["travel icon: a known travel spell takes the arrow's place, then the quest"] = function(t)
    local c = boot({ known = true })
    t.eq(c.arrows[1] and c.arrows[1].shown, true, "the quest arrow is shown")
    t.eq(lines(c)[1], CAST)
    t.eq(lines(c)[2], Travel.THEN:format("Wolves"))
end

tests["travel icon: walk drops the cast for this step; said again brings it back"] = function(t)
    local c = boot({ known = true })
    c.slashes[ns.id.slash](Travel.WORD)
    c.advance(10, 40)
    t.ok(said(c, "you walk to this step"), "the walk is said")
    t.ok(not has(lines(c), CAST), "walking: no cast")
    t.eq(lines(c)[1], "Wolves", "walking: the quest itself")
    c.slashes[ns.id.slash](Travel.WORD)
    c.advance(10, 40)
    t.ok(said(c, "the shortcut is back"), "the shortcut is said back")
    t.eq(lines(c)[1], CAST)
end

tests["travel icon: a spell still to learn is no action"] = function(t)
    local c = boot({ known = false })
    t.eq(lines(c)[1], "Wolves")
    t.ok(not hasPrefix(lines(c), "Cast "), "no cast")
    c.slashes[ns.id.slash](Travel.WORD)
    t.ok(said(c, "no shortcut on this step"), "nothing to walk past")
end

tests["travel icon: unknown data says nothing wrong"] = function(t)
    -- The client does not say whether the spell is known: never taken as known.
    local c = boot({ known = nil })
    t.eq(lines(c)[1], "Wolves", "known unknown")
    t.ok(not hasPrefix(lines(c), "Cast "), "no cast")
    t.ok(not has(lines(c), N.TRAVEL_PLAIN), "no plain spell line")
    -- No id for the spell's name.
    c = boot({ known = true, noId = true })
    t.eq(lines(c)[1], "Wolves", "no id")
    t.ok(not hasPrefix(lines(c), "Cast "), "no cast")
end

return tests
