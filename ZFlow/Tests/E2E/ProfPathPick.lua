local _, ns = ...
-- P-PATH-2 follow-up (lead section 450, "Selected", "Task", "Arrow"): the
-- range the player picks in the path panel is part of the one live plan
-- (Items/ProfPath.lua): it is kept for the character, it counts in the rev,
-- the plan's tasks are that range's steps in ProfPlan's kinds, and the
-- arrow's feed (Nav/ProfFeed.lua) follows them. The whole add-on on a fake
-- client with the real ProfPath; the pure tests use made-up recipes.
-- Look only. Offline test, fake client lines. Not tested in game.
--
-- Red before the code: the plan has no pick, its tasks are empty, the panel
-- has no pick of its own to call and ProfPlan.Plan knows no wanted recipe.
local tests = {}

local KINDS = { learn_recipe = true, train_tier = true, make_part = true, take_bank = true,
    go_station = true, craft = true, gather_skill = true, buy_vendor = true, buy_auction = true,
    find_material = true, open_window = true, no_point = true }

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
    c.fire("TRADE_SKILL_SHOW")
    c.advance(1, 5)
    return c, addon
end

-- A range other than the selected one, with a recipe of its own.
local function other(path)
    local now = path.ranges[path.selected]
    for i, r in ipairs(path.ranges) do
        if i ~= path.selected and type(r.recipe) == "string" and r.recipe ~= (now and now.recipe) then
            return i, r
        end
    end
    return nil
end

tests["prof pick: with nothing picked the plan's tasks are the planner's own steps"] = function(t)
    local _, addon = start()
    local path = addon.profFeed.path("Blacksmithing")
    t.ok(type(path) == "table", "there is a path")
    if type(path) ~= "table" then return end
    t.ok(path.picked ~= true, "nothing picked yet")
    t.ok(type(path.ranges[path.selected]) == "table"
        and type(path.ranges[path.selected].recipe) == "string", "the default range has a recipe")
    local steps, why, say = addon.profPlan.plan("Blacksmithing")
    t.eq(#path.tasks, #steps, "as many tasks as the planner has steps")
    t.ok(path.taskWhy == why and path.say == say and (why ~= nil or #steps > 0),
        "and the planner's own reason and words when it has no step")
    for i, s in ipairs(steps) do
        t.eq(path.tasks[i] and path.tasks[i].kind, s.kind, "task " .. i .. " is the planner's step")
    end
end

tests["prof pick: a click in the panel picks the range in the plan, once in the rev, and it stays"] = function(t)
    local c, addon = start()
    local feed, panel = addon.profFeed, addon.profPathPanel
    t.eq(type(panel.pick), "function", "the panel has a pick to click")
    if type(panel.pick) ~= "function" then return end
    local path = feed.path("Blacksmithing")
    local i, range = other(path)
    t.ok(i ~= nil, "the real path has another range to pick")
    if not i then return end
    local before = path.rev
    local ok, err = pcall(panel.pick, i)
    t.ok(ok, "the click does not error: " .. tostring(err))
    local after = feed.path("Blacksmithing")
    t.eq(after.selected, i, "the plan holds the pick")
    t.eq(after.picked, true, "and says it is the player's")
    t.eq(after.rev, before + 1, "one pick: one more rev")
    t.eq(feed.rev("Blacksmithing"), before + 1, "asking again does not bump it")
    local model = panel.model()
    t.ok(type(model) == "table" and type(model.plan) == "table" and model.plan.selected == i,
        "the panel shows the plan's pick")
    -- The same pick again changes nothing.
    pcall(panel.pick, i)
    t.eq(feed.rev("Blacksmithing"), before + 1, "the same click again: same rev")
    -- It is kept for the character: the window closing and opening keeps it.
    c.fire("TRADE_SKILL_CLOSE"); c.advance(1, 5)
    c.fire("TRADE_SKILL_SHOW"); c.advance(1, 5)
    local again = feed.path("Blacksmithing")
    t.eq(again.ranges[again.selected] and again.ranges[again.selected].recipe, range.recipe,
        "still the picked range")
end

tests["prof pick: the tasks are the picked range's steps, in the planner's kinds"] = function(t)
    local _, addon = start()
    local feed, panel = addon.profFeed, addon.profPathPanel
    if type(panel.pick) ~= "function" then return t.ok(false, "the panel has no pick") end
    local i, range = other(feed.path("Blacksmithing"))
    if not i then return t.ok(false, "no other range") end
    panel.pick(i)
    local path = feed.path("Blacksmithing")
    t.ok(#path.tasks > 0, "the picked range has tasks")
    local named = false
    for n, task in ipairs(path.tasks) do
        t.ok(KINDS[task.kind] == true, "task " .. n .. " is a planner kind: " .. tostring(task.kind))
        t.ok(type(task.text) == "string" and task.text ~= "", "task " .. n .. " has words")
        if task.recipe == range.recipe then named = true end
    end
    t.ok(named, "a task is for the picked range's recipe")
    -- The book is empty, so the recipe is to learn first; where is not known.
    local first = path.tasks[1]
    t.eq(first and first.kind, "learn_recipe", "an unknown recipe is learned first")
    t.eq(first and first.recipe, range.recipe)
    t.eq(first and first.target, nil, "no place known: none made up")
end

tests["prof pick: the arrow's feed follows the picked range"] = function(t)
    local _, addon = start()
    local feed, panel = addon.profFeed, addon.profPathPanel
    if type(panel.pick) ~= "function" then return t.ok(false, "the panel has no pick") end
    local i, range = other(feed.path("Blacksmithing"))
    if not i then return t.ok(false, "no other range") end
    panel.pick(i)
    local _, pick = feed.step()
    t.ok(type(pick) == "table" and type(pick.step) == "table", "the feed has a step")
    if type(pick) ~= "table" or type(pick.step) ~= "table" then return end
    t.eq(pick.prof, "Blacksmithing")
    t.eq(pick.step.recipe, range.recipe, "the step is for the picked range")
    t.eq(pick.rev, feed.rev("Blacksmithing"), "and carries the plan's rev")
end

-- Pure --------------------------------------------------------------------

tests["prof pick: ProfPath.Path takes the pick by recipe, and falls back when it is gone"] = function(t)
    local PP = ns.ProfPath
    local base = { prof = "Blacksmithing", skill = 1, max = 75, bags = {}, bank = {}, prices = {} }
    local plain = PP.Path(base)
    local i, range = other(plain)
    t.ok(i ~= nil, "another range to pick")
    if not i then return end
    local with = { pick = { recipe = range.recipe, from = range.from } }
    for k, v in pairs(base) do with[k] = v end
    local picked = PP.Path(with)
    t.eq(picked.selected, i, "the picked range is selected")
    t.eq(picked.picked, true)
    t.ok(picked.rev ~= plain.rev, "a pick is a change a reader sees")
    local gone = { pick = { recipe = "No Such Recipe", from = 5 } }
    for k, v in pairs(base) do gone[k] = v end
    local back = PP.Path(gone)
    t.eq(back.selected, plain.selected, "a pick that is not on the path: the default range")
    t.ok(back.picked ~= true, "and it is not called the player's")
end

tests["prof pick: ProfPlan.Plan makes the wanted recipe when it gives a point"] = function(t)
    local P = ns.ProfPlan
    local book = {
        ["Test Buckle"] = { profession = "Blacksmithing", makes = 50, mats = { [2] = 2 } },
        ["Test Nail"] = { profession = "Blacksmithing", makes = 51, mats = { [2] = 1 } },
    }
    local colours = {
        ["Test Buckle"] = { optimal = { lo = 45, hi = 55 } },
        ["Test Nail"] = { medium = { lo = 48, hi = 60 } },
    }
    local function input(want)
        return { prof = "Blacksmithing", skill = 50, max = 75, book = book, colours = colours,
            bags = { [2] = 10 }, bank = {}, want = want,
            name = function(item) return "Test Bar " .. item end }
    end
    local function crafted(steps)
        for _, s in ipairs(steps or {}) do
            if s.kind == "craft" then return s.recipe end
        end
        return nil
    end
    t.eq(crafted(P.Plan(input(nil))), "Test Buckle", "by itself: the sure point")
    t.eq(crafted(P.Plan(input("Test Nail"))), "Test Nail", "the wanted recipe comes first")
    t.eq(crafted(P.Plan(input("No Such Recipe"))), "Test Buckle", "a recipe that gives no point is not wanted")
end

return tests
