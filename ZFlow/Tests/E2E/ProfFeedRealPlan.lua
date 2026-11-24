local _, ns = ...
-- Lead section 382 (C2 P-COACH, zflow-prof-feed-2): the profession arrow fed
-- by the REAL planner (Items/ProfPlan.lua with Items/ProfSources.lua), through
-- the whole add-on: nothing here stands in for the plan. What the character
-- saved (its skill, its recipe book, the colours its window showed, its bags
-- and bank, a station it walked past) goes in; the profession arrow's line and
-- needle, and "/zflow prof plan", come out. Loaded the way the game loads it
-- (ns.offline.addon) on a fake client; every recipe, item and place is made
-- up. Look only. Not tested in game.
local tests = {}

-- Items: 2 Test Bar. Recipe: Test Buckle, 2 bars each, orange at 50.
local BAR = 2
local BOOK = { ["Test Buckle"] = { profession = "Blacksmithing", makes = 50, mats = { [BAR] = 2 } } }
local COLOURS = { ["Test Buckle"] = { optimal = { lo = 45, hi = 55 } } }
local ANVIL = { kind = "anvil", map = 1411, x = 0.6, y = 0.5 }

-- opts: skill, max, bars (in the bags), bank (bars in the bank), stations
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true },
        learned = { keyStations = opts.stations } })
    c.setSaved(ns.id.charDB, { learned = {
        facts = { profSkill = { Blacksmithing = { skill = opts.skill or 50, max = opts.max or 75 } },
                  recipeBook = BOOK },
        recipeColors = COLOURS,
        bankCounts = opts.bank and { at = 1000, counts = { [BAR] = opts.bank } } or nil,
    } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapCont(1411, 1)
    c.setItemInfo({ [BAR] = { name = "Test Bar" } })
    c.setBagItems(opts.bars and { { item = BAR, count = opts.bars } } or {})
    c.setProfessions({ "Blacksmithing" })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function text(p)
    return table.concat(p and p.lines or {}, " | ")
end

local function has(p, words)
    return text(p):find(words, 1, true) ~= nil
end

tests["real plan: the planner itself is the feed's plan, not a stand-in"] = function(t)
    local _, addon = start({ bars = 4 })
    t.eq(type(addon.ProfPlan and addon.ProfPlan.Plan), "function", "Items/ProfPlan.lua is loaded")
    t.eq(type(addon.profPlan and addon.profPlan.plan), "function", "its live read")
    local steps = addon.profPlan.plan("Blacksmithing")
    t.eq(steps[#steps] and steps[#steps].kind, "craft", "the real plan ends in the craft")
end

tests["real plan: bars in the bags and an anvil seen: the arrow walks to the anvil, then says the craft"] = function(t)
    local c = start({ bars = 4, stations = { ANVIL } })
    local p = c.arrows[2]
    t.eq(p and p.shown, true, "the profession arrow is up")
    c.advance(0.1, 2)
    t.ok(p and type(p.drawn) == "table" and p.drawn.body ~= 0, "it points: the anvil is 100 yd away")
    t.ok(has(p, "anvil"), "its line names the anvil: " .. text(p))
    -- The player walks to the anvil: that step is done, the craft is next.
    c.setPosition(1411, 0.6, 0.5)
    c.advance(5, 20)
    t.ok(has(p, "Make 2 Test Buckle at an anvil (Blacksmithing 50 of 75)"),
        "at the anvil the line is the craft: " .. text(p))
    -- The bars are used up and the skill went up: the plan moves on.
    c.setBagItems({})
    c.advance(5, 20)
    t.ok(not has(p, "Make 2 Test Buckle"), "the craft is no longer asked for: " .. text(p))
    t.ok(has(p, "Test Buckle") or has(p, "Blacksmithing"), "the next thing to do is said: " .. text(p))
end

tests["real plan: bars only in the bank: the line says to take them out first"] = function(t)
    local c = start({ bank = 6 })
    local p = c.arrows[2]
    t.eq(p and p.shown, true)
    t.ok(has(p, "Take 6 Test Bar from your bank, for Test Buckle"), "the bank step: " .. text(p))
    t.eq(text(p):find("%d%d%d%d"), nil, "no item number in the line")
end

tests["real plan: nothing to make it from says what to get, never silence"] = function(t)
    local c = start({})
    local p = c.arrows[2]
    t.eq(p and p.shown, true)
    t.ok(#text(p) > 0, "a line is shown")
end

tests["real plan: /zflow prof plan prints the real steps in order and the pick"] = function(t)
    local c = start({ bars = 4, stations = { ANVIL } })
    local before = #c.printed
    c.slashes[ns.id.slash]("prof plan")
    local out = table.concat(c.printed, "\n", before + 1)
    t.ok(out:find("Blacksmithing: 50 of 75", 1, true) ~= nil, out)
    t.ok(out:find("1. Go to an anvil", 1, true) ~= nil, out)
    t.ok(out:find("2. Make 2 Test Buckle at an anvil (Blacksmithing 50 of 75)", 1, true) ~= nil, out)
    t.ok(out:find("Next: Go to an anvil (Blacksmithing)", 1, true) ~= nil, out)
end

tests["real plan: at its max the plan's step is the next rank at a trainer"] = function(t)
    local c, addon = start({ skill = 75, max = 75, bars = 4 })
    local steps = addon.profPlan.plan("Blacksmithing")
    t.eq(steps[1] and steps[1].kind, "train_tier")
    local p = c.arrows[2]
    t.eq(p and p.shown, true)
    t.ok(has(p, "rank") or has(p, "trainer") or has(p, "Train"), "training is said: " .. text(p))
end

return tests
