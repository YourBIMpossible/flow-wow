local _, ns = ...
-- Owner, 2026-11-23: "We need to separate the Leveling text on one side and
-- the profession text on the other." With a quest step and a profession
-- step both up, the profession step's words stand above the arrows, on the
-- needle's own frame, and the quest step's words below, on the quest
-- arrow's frame; neither frame carries the other's words. The same in the
-- top and the bottom half of the screen (lead section 387 R2). The whole
-- add-on loaded the way the game loads it (ns.offline.addon) on a fake
-- client; the entry is the player's: logging in with a waypoint set and a
-- profession below its max. Based on zflow-prof-feed-2, whose
-- Nav/ArrowView.lua places the text; this file adds the proof only.
-- Made-up places and names. Look only. Not tested in game.
local tests = {}

local FISH = { kind = "go_station", text = "Cook 4 Brilliant Smallfish at a fire", count = 4,
               target = { map = 1411, x = 0.45, y = 0.5 } }

-- arrows: the saved layout.arrows (nil: the default, stacked at the top).
local function start(arrows)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true, arrows = arrows } })
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = { Cooking = { skill = 40, max = 75 } } } } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapCont(1411, 1)
    c.setProfessions({ "Cooking" })
    c.setWaypoint(1411, 0.5, 0.3)
    local addon = ns.offline.addon(c)
    addon.profPlan = { plan = function(prof) return ({ Cooking = { FISH } })[prof] end }
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count()
end

local function says(h, text)
    for _, line in ipairs(type(h) == "table" and h.lines or {}) do
        if type(line) == "string" and line:find(text, 1, true) then return true end
    end
    return false
end

-- Both frames up, each with its own words only.
local function ownWords(t, c, what)
    local q, p = c.arrows[1], c.arrows[2]
    t.eq(q and q.shown, true, what .. ": the quest arrow is up")
    t.eq(p and p.shown, true, what .. ": the profession needle is up")
    t.eq(says(q, "Waypoint"), true, what .. ": the quest arrow says its step")
    t.eq(says(p, FISH.text), true, what .. ": the needle says the profession step")
    t.eq(says(q, FISH.text), false, what .. ": no profession words on the quest arrow")
    t.eq(says(p, "Waypoint"), false, what .. ": no quest words on the needle")
    return q, p
end

tests["text sides: stacked, the profession words are above the arrows and the quest words below"] = function(t)
    local low = { points = { quest = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } } }
    for what, arrows in pairs({ ["top half"] = false, ["bottom half"] = low }) do
        local c, addon, before = start(arrows or nil)
        local q, p = ownWords(t, c, what)
        if not (q and p and q.textPoint and p.textPoint) then t.ok(false, what .. ": both have a text point") return end
        t.eq({ p.textPoint[1], p.textPoint[2] }, { "BOTTOM", "TOP" }, what .. ": profession words hang above the needle")
        t.eq({ q.textPoint[1], q.textPoint[2] }, { "TOP", "BOTTOM" }, what .. ": quest words hang below the quest arrow")
        t.eq(addon.problems:count(), before)
    end
end

tests["text sides: separate arrows, each keeps its own words on its own frame"] = function(t)
    local c, addon, before = start({ mode = "separate" })
    local q, p = ownWords(t, c, "separate")
    t.ok(q and q.textPoint ~= nil, "the quest words have a place")
    t.ok(p and p.textPoint ~= nil, "the profession words have a place")
    t.eq(addon.problems:count(), before)
end

return tests
