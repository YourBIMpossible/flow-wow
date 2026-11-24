local _, ns = ...

-- The hearthstone step (G46) on the quest arrow, on the whole add-on
-- loaded on a fake client. The real entry: the arrow's quest step goes
-- through Travel's Via, which asks N.HearthStepFrom with the bind name the
-- client gives, the saved bind place and the stone's cooldown. When the
-- stone is ready and lands much nearer the step, the arrow says
-- "Hearth to <place>" and "Then: <step>". Made-up quests, places and
-- names. Not tested in game.
--
-- Map 1411 is 1000 x 1000 yards. The wolves are at (0.9, 0.5); the player
-- at (0.1, 0.5) is 800 yards from them; the inn at (0.85, 0.5) is 50
-- yards from them: the stone saves 750 yards.

local tests = {}
local N, Travel = ns.Nav, ns.Nav.Travel

local MAP, INN = 1411, "Test Inn"

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Near Wolf", spawns = { [12] = { { 90, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = MAP })[area] end
    return db, zones
end

local function bindAt(map, x, y, name)
    return { learned = { places = { bind = { name = name or INN, map = map, x = x, y = y, seen = 10 } } } }
end

-- opts.char: the character table; opts.bind: the bind name the client
-- gives; opts.cooldown: the stone's cooldown (nil: not known).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, opts.char or bindAt(MAP, 0.85, 0.5))
    c.setZone(1, MAP); c.setPosition(MAP, 0.1, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setBindLocation(opts.bind)
    c.setHearthCooldown(opts.cooldown)
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

tests["hearth step: a ready stone that saves the walk says hearth to the inn, then the quest"] = function(t)
    local c = boot({ bind = INN, cooldown = 0 })
    local l = lines(c)
    t.eq(c.arrows[1] and c.arrows[1].shown, true, "the quest arrow is shown")
    t.eq(l[1], "Hearth to " .. INN)
    t.eq(l[2], Travel.THEN:format("Wolves"))
end

tests["hearth step: the stone on cooldown is not offered"] = function(t)
    local c = boot({ bind = INN, cooldown = 0 })
    t.eq(lines(c)[1], "Hearth to " .. INN, "ready first")
    c.setHearthCooldown(900)
    c.advance(10, 40)
    t.eq(lines(c)[1], "Wolves", "on cooldown: the quest itself")
    t.ok(not hasPrefix(lines(c), "Hearth to"), "no hearth line")
    c.setHearthCooldown(0)
    c.advance(10, 40)
    t.eq(lines(c)[1], "Hearth to " .. INN, "ready again")
end

tests["hearth step: an inn near the player saves nothing and is not offered"] = function(t)
    local c = boot({ bind = INN, cooldown = 0, char = bindAt(MAP, 0.15, 0.5) })
    t.eq(lines(c)[1], "Wolves")
    t.ok(not hasPrefix(lines(c), "Hearth to"), "no hearth line")
end

tests["hearth step: walk skips the stone and says so; said again brings it back"] = function(t)
    local c = boot({ bind = INN, cooldown = 0 })
    c.slashes[ns.id.slash]("walk")
    c.advance(10, 40)
    t.ok(said(c, "you walk to this step"), "the walk is said")
    t.eq(lines(c)[1], "Wolves", "walking: the quest itself")
    c.slashes[ns.id.slash]("walk")
    c.advance(10, 40)
    t.ok(said(c, "the shortcut is back"), "the shortcut is said back")
    t.eq(lines(c)[1], "Hearth to " .. INN)
end

tests["hearth step: unknown data says nothing wrong"] = function(t)
    -- The cooldown not known: never taken as ready.
    local c = boot({ bind = INN, cooldown = nil })
    t.eq(lines(c)[1], "Wolves", "cooldown unknown")
    t.ok(not hasPrefix(lines(c), "Hearth to"), "no hearth line")
    t.ok(not hasPrefix(lines(c), N.HEARTH_PLAIN), "no plain stone line")
    -- The client's bind name is not the saved one: the place is not known,
    -- so no saving is claimed.
    c = boot({ bind = "Other Inn", cooldown = 0 })
    t.eq(lines(c)[1], "Wolves", "bind place unknown")
    t.ok(not hasPrefix(lines(c), "Hearth to"), "no hearth line")
    -- No bind name at all and nothing saved.
    c = boot({ char = {}, cooldown = 0 })
    t.eq(lines(c)[1], "Wolves", "nothing known")
    t.ok(not hasPrefix(lines(c), N.HEARTH_PLAIN), "no plain stone line")
end

tests["hearth step: the inn on another map is not offered"] = function(t)
    local c = boot({ bind = INN, cooldown = 0, char = bindAt(1420, 0.5, 0.5) })
    t.eq(lines(c)[1], "Wolves")
    t.ok(not hasPrefix(lines(c), "Hearth to"), "no hearth line")
end

return tests
