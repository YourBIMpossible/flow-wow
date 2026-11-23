local _, ns = ...
-- The skill-up helper as a kit window, end to end (lead sections 287 and
-- 291), on the whole add-on loaded on a fake client. The player opens a
-- profession window; the helper's view (ProfHelper.View, UI/ProfHelper.lua)
-- is what the kit draws: the profession and skill as the header, the goal
-- with a button each way, the points the bags make, and each recipe that
-- gives a point as an item line. Pressing a goal button keeps the goal.
-- Offline: the reads are the fake client ones, not the game. Not tested in game.
-- Fails before the code: the helper answers no view, so every test fails
-- its first check ("the helper answers a view").
local tests = {}

local TAILORING = 197
local BOLT, BELT, CAP = 11, 12, 13
local CLOTH, THREAD = 2589, 2996

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {
        learned = { prices = { vendor = { [CLOTH] = { value = 10, basis = "observed", source = "merchant" } } } },
    })
    c.setSaved(ns.id.charDB, {})
    c.setBags({ { free = 4, total = 16, family = 0 } })
    if opts.recipes ~= false then
        c.setRecipes({ profession = TAILORING, skill = 40, max = 75, recipes = {
            { id = BOLT, name = "Linen Bolt", learned = true, difficulty = "optimal" },
            { id = BELT, name = "Linen Belt", learned = true, difficulty = "medium" },
            { id = CAP, name = "Linen Cap", learned = true, difficulty = "trivial" },
        } })
        c.setRecipeSchematic(BOLT, { makes = 4000, yield = 1, mats = { [CLOTH] = 2 } })
        c.setRecipeSchematic(BELT, { makes = 4001, yield = 1, mats = { [THREAD] = 1 } })
        c.setRecipeSchematic(CAP, { makes = 4002, yield = 1, mats = { [CLOTH] = 1 } })
    end
    c.setItemCount(CLOTH, 6)
    c.setItemCount(THREAD, 1)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.open ~= false then
        c.fire("TRADE_SKILL_SHOW")
        c.fire("TRADE_SKILL_LIST_UPDATE")
    end
    return c, addon
end

-- The helper's view now, or nil; fails the test when the helper answers none.
local function viewOf(t, addon)
    local api = addon.profHelper
    local ok = type(api) == "table" and type(api.view) == "function"
    t.ok(ok, "the helper answers a view")
    if not ok then return nil end
    return api.view()
end

local function keyed(view, key)
    for _, part in ipairs(view.children) do
        if part.key == key then return part end
    end
    return nil
end

local function lines(view)
    local out = {}
    for _, part in ipairs(view.children) do
        if part.kind == "itemLine" then out[#out + 1] = part end
    end
    return out
end

local H = ns.ProfHelper or {}

tests["prof helper view e2e: no window open, no view"] = function(t)
    local _, addon = start({ open = false })
    local api = addon.profHelper
    t.ok(type(api) == "table" and type(api.view) == "function", "the helper answers a view")
    if not (type(api) == "table" and type(api.view) == "function") then return end
    t.eq(api.view(), nil)
end

tests["prof helper view e2e: the open window is the header, the goal, the bags and the recipes"] = function(t)
    local _, addon = start()
    local view = viewOf(t, addon)
    if not view then return end
    t.eq(view.id, "ProfHelper")
    t.eq(view.children[1].title, "Skill 40 of 75", "a modern window names no profession in words")
    t.eq(keyed(view, "goal").label, H.NO_GOAL)
    t.eq(keyed(view, "bags").kind, "row")
    local got = lines(view)
    t.eq(#got, 2, "the trivial recipe gives no point and is not listed")
    t.eq(got[1].name, "Linen Bolt (" .. H.SURE .. ")")
    t.eq(got[1].money, 20, "two cloth at 10 copper")
    t.eq(got[1].color.hex, "ff8040")
    t.eq(got[2].name, "Linen Belt (" .. H.MAYBE .. ")")
    t.eq(got[2].money, nil, "thread has no price seen")
end

tests["prof helper view e2e: pressing Goal + keeps the goal and the next view says so"] = function(t)
    local c, addon = start()
    local view = viewOf(t, addon)
    if not view then return end
    keyed(view, "goalUp").onClick()
    local saved = c.saved(ns.id.charDB)
    t.eq(saved.state.profGoals[TAILORING], 40 + H.GOAL_STEP)
    view = addon.profHelper.view()
    t.eq(keyed(view, "goal").label, "Skill goal: 45. " .. H.TO_GOAL:format(5, 45))
    keyed(view, "goalDown").onClick()
    view = addon.profHelper.view()
    t.eq(keyed(view, "goal").label, "Skill goal: 40. " .. H.AT_GOAL:format(40))
end

tests["prof helper view e2e: a window the client does not answer is the reading state"] = function(t)
    local _, addon = start({ recipes = false })
    local view = viewOf(t, addon)
    if not view then return end
    t.eq({ view.children[2].kind, view.children[2].text }, { "empty", H.READING })
end

tests["prof helper view e2e: closing the window ends the view"] = function(t)
    local c, addon = start()
    if not viewOf(t, addon) then return end
    c.fire("TRADE_SKILL_CLOSE")
    t.eq(addon.profHelper.view(), nil)
end

tests["prof helper view e2e: the setting off answers no view"] = function(t)
    local c, addon = start({ open = false })
    addon.settings:set(H.SETTING, false)
    c.fire("TRADE_SKILL_SHOW")
    local api = addon.profHelper
    t.ok(type(api) == "table" and type(api.view) == "function", "the helper answers a view")
    if not (type(api) == "table" and type(api.view) == "function") then return end
    t.eq(api.view(), nil)
end

return tests
