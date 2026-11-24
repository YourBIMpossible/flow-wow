local _, ns = ...
-- Lead section 382 (C2 P-COACH, zflow-prof-feed): the profession coach
-- through the whole add-on. With a stand-in for the planner's live read
-- (the add-on's ns.profPlan.plan; the real planner is driven in
-- Tests/E2E/ProfFeedRealPlan.lua) the needle shows the one step picked across
-- the professions below their max: the nearest by travel time, a step on
-- another continent as text. The "Professions" tick in the route menu turns
-- it off. "/zflow prof plan" prints the plan. Loaded the way the game loads
-- it (ns.offline.addon) on a fake client; made-up places and names only.
-- Look only. Not tested in game.
--
-- Red before the code: no ProfPlan seam, no tick, no "prof" word.
local tests = {}

local FISH = { kind = "go_station", text = "Cook 4 Brilliant Smallfish at a fire", count = 4,
               target = { map = 1411, x = 0.45, y = 0.5 } }
local MINE = { kind = "gather", text = "Mine 5 Copper Ore", count = 5,
               target = { map = 1411, x = 0.9, y = 0.5 } }
local FAR = { kind = "learn_recipe", text = "Learn Spiced Wolf Meat at the cooking trainer",
              target = { map = 1453, x = 0.4, y = 0.4 } }

-- steps: { [profession] = { step, ... } }, what the fake Plan answers.
local function start(steps)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = {
        Cooking = { skill = 40, max = 75 }, Mining = { skill = 60, max = 75 } } } } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapCont(1411, 1)
    c.setMapCont(1453, 2)
    if type(c.setMapContName) == "function" then c.setMapContName(1453, "Eastern Kingdoms") end
    c.setProfessions({ "Cooking", "Mining" })
    local addon = ns.offline.addon(c)
    addon.profPlan = { plan = function(prof) return steps[prof] end }
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function rowAt(items, key)
    for _, r in ipairs(items or {}) do
        if r.key == key then return r end
    end
    return nil
end

tests["prof feed: the needle shows the step picked across professions, nearest first"] = function(t)
    local c = start({ Cooking = { FISH }, Mining = { MINE } })
    local p = c.arrows[2]
    t.eq(p and p.shown, true, "the profession needle is up")
    t.eq(p and p.lines and p.lines[1], FISH.text, "the fire 50 yd away beats the vein 400 yd away")
    c.advance(0.1, 2)
    t.ok(p and type(p.drawn) == "table" and p.drawn.body ~= 0, "the needle is drawn")
end

tests["prof feed: a step on another continent is text, never a needle"] = function(t)
    local c = start({ Cooking = { FAR } })
    local p = c.arrows[2]
    t.eq(p and p.lines, { "Next time you are in Eastern Kingdoms: " .. FAR.text })
    c.advance(0.1, 2)
    t.eq(p and type(p.drawn) == "table" and p.drawn.body, 0, "no needle")
end

tests["prof feed: the Professions tick in the route menu turns the profession step off"] = function(t)
    local c, addon = start({ Cooking = { FISH }, Mining = { MINE } })
    local q = c.arrows[1]
    t.ok(q ~= nil and type(q.enter) == "function", "the fake arrow has submenu rows")
    if not (q and type(q.enter) == "function") then return end
    q.click("right")
    t.eq(q.enter("show"), true)
    local row = rowAt(q.menuItems, "professions")
    t.ok(row ~= nil, "a Professions row")
    t.eq(row and row.text, "Professions")
    t.eq(row and row.checked, true, "on by default")
    t.eq(q.pickRow("professions"), true)
    t.eq(addon.settings:get("nav.professions"), false, "the tick is saved off")
    c.advance(5, 20)
    t.eq(c.arrows[2].shown, false, "off: no profession needle")
    q.click("right")
    q.enter("show")
    t.eq(rowAt(q.menuItems, "professions") and rowAt(q.menuItems, "professions").checked, false)
    t.eq(q.pickRow("professions"), true)
    c.advance(5, 20)
    t.eq(c.arrows[2].lines and c.arrows[2].lines[1], FISH.text, "on again: the step is back")
end

tests["prof feed: /zflow prof plan prints each profession, its steps and the pick"] = function(t)
    local c = start({ Cooking = { FISH, FAR }, Mining = { MINE } })
    local before = #c.printed
    c.slashes[ns.id.slash]("Prof Plan")
    local text = table.concat(c.printed, "\n", before + 1)
    t.ok(text:find("Cooking: 40 of 75", 1, true) ~= nil, "Cooking's skill and max: " .. text)
    t.ok(text:find("1. " .. FISH.text, 1, true) ~= nil, "its steps in order")
    t.ok(text:find("2. " .. FAR.text, 1, true) ~= nil)
    t.ok(text:find("Mining: 60 of 75", 1, true) ~= nil)
    t.ok(text:find("Next: " .. FISH.text .. " (Cooking): the nearest, about 7 seconds away.", 1, true) ~= nil,
        "the pick and why")
end

-- Lead section 387 R5: the picked step with a place is also a labelled pin
-- on the world map (client.mapPins), cleared with no step or the tick off.
local function pinSet(c)
    for _, h in ipairs(c.mapPinSets or {}) do
        if h.shown and h.pins[1] and h.pins[1].name == FISH.text then return h end
    end
    return nil
end

tests["prof feed: the picked step is a labelled pin on the world map; the tick off clears it"] = function(t)
    local c, addon = start({ Cooking = { FISH }, Mining = { MINE } })
    c.setWorldMap(1411)
    c.advance(2, 4)
    local h = pinSet(c)
    t.ok(h ~= nil, "a pin named with the step's own words")
    t.eq(h and h.pins[1].x, 0.45)
    t.eq(h and h.pins[1].y, 0.5)
    t.eq(addon.settings:set("nav.professions", false), true)
    c.advance(2, 4)
    t.eq(h and h.shown, false, "the tick off: the pin is gone")
end

tests["prof feed: no step with a place, no pin"] = function(t)
    local c = start({ Cooking = { FAR } })
    c.setWorldMap(1453)
    c.advance(2, 4)
    t.eq(c.arrows[2] and c.arrows[2].lines, { "Next time you are in Eastern Kingdoms: " .. FAR.text },
        "the step is held back as words")
    for _, h in ipairs(c.mapPinSets or {}) do
        t.ok(not (h.shown and h.pins[1] and h.pins[1].name == FISH.text), "no Cooking pin")
    end
end

return tests
