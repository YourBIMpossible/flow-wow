-- UI/ProfHelper.lua on the shared kit (lead sections 287 and 291): what the
-- skill-up helper shows, as a kit window spec (UI/Kit.lua). The goal and
-- the points are the header; each recipe that gives a point is an item
-- line with its icon, its skill colour and what a craft costs; a state with
-- nothing to list says what is missing and how to get it. Pure: no client,
-- no kernel. Made-up names. Not tested in game.
-- Fails before the code: ProfHelper.View is absent, so every test fails
-- its first check ("ProfHelper.View is a function").
local _, ns = ...

local H = ns.ProfHelper or {}
local tests = {}

local function has(t)
    t.ok(type(H.View) == "function", "ProfHelper.View is a function")
    return type(H.View) == "function"
end

local ICON = "Interface\\Icons\\INV_Fabric_Linen_02"

-- A window read: tailoring 40 of 75, a goal of 50, three recipes.
local function model()
    return {
        profession = "Tailoring", skill = 40, max = 75, goal = 50,
        state = { need = 10, overCap = false },
        bags = { sure = 1, maybe = 3 },
        recipes = {
            { name = "Linen Bolt", chance = "sure", difficulty = "optimal", cost = 20, icon = ICON },
            { name = "Linen Belt", chance = "maybe", difficulty = "medium" },
            { name = "Odd Thing", chance = "unknown" },
        },
        notes = { "Next trainer recipe at skill 45." },
    }
end

local function ofKind(view, kind)
    local out = {}
    for _, part in ipairs(view.children) do
        if part.kind == kind then out[#out + 1] = part end
    end
    return out
end

local function keyed(view, key)
    for _, part in ipairs(view.children) do
        if part.key == key then return part end
    end
    return nil
end

tests["prof helper view: a kit window, with the profession and the skill as its header"] = function(t)
    if not has(t) then return end
    local view = H.View(model())
    t.eq(view.id, "ProfHelper")
    t.eq(view.title, "Skill-up helper")
    t.eq(view.children[1].kind, "header")
    t.eq(view.children[1].title, "Tailoring: skill 40 of 75")
end

tests["prof helper view: a profession the window gave no name for is still a header"] = function(t)
    if not has(t) then return end
    local m = model()
    m.profession = 197
    t.eq(H.View(m).children[1].title, "Skill 40 of 75")
end

tests["prof helper view: the goal and the points to it, with a button each way"] = function(t)
    if not has(t) then return end
    local view = H.View(model())
    t.eq(keyed(view, "goal").label, "Skill goal: 50. " .. H.TO_GOAL:format(10, 50))
    local said = {}
    local act = function(key, value) said[#said + 1] = { key, value } end
    view = H.View(model(), act)
    keyed(view, "goalUp").onClick()
    keyed(view, "goalDown").onClick()
    t.eq(said, { { "goal", 50 + H.GOAL_STEP }, { "goal", 50 - H.GOAL_STEP } })
end

tests["prof helper view: no goal says so and how to set one; the goal never goes below none"] = function(t)
    if not has(t) then return end
    local m = model()
    m.goal, m.state = nil, nil
    local said = {}
    local view = H.View(m, function(key, value) said[#said + 1] = { key, value } end)
    t.eq(keyed(view, "goal").label, H.NO_GOAL)
    t.ok(H.NO_GOAL:find("Goal +", 1, true), "names the button that sets one: " .. H.NO_GOAL)
    t.eq(keyed(view, "goalDown").enabled, false, "nothing to lower")
    keyed(view, "goalUp").onClick()
    t.eq(said, { { "goal", 40 + H.GOAL_STEP } }, "the first goal starts from the skill")
end

tests["prof helper view: a goal reached, and a goal past the cap"] = function(t)
    if not has(t) then return end
    local m = model()
    m.state = { need = 0, overCap = false }
    t.eq(keyed(H.View(m), "goal").label, "Skill goal: 50. " .. H.AT_GOAL:format(50))
    m.goal, m.state = 100, { need = 60, overCap = true }
    t.eq(keyed(H.View(m), "goal").label, "Skill goal: 100. " .. H.OVER_CAP:format(100, 75))
end

tests["prof helper view: the goal stops at its limits"] = function(t)
    if not has(t) then return end
    local m = model()
    m.goal = H.GOAL_MAX
    t.eq(keyed(H.View(m), "goalUp").enabled, false)
    m.goal = 3
    local said = {}
    keyed(H.View(m, function(_, value) said[#said + 1] = value end), "goalDown").onClick()
    t.eq(said, { 0 }, "below the step clears the goal")
end

tests["prof helper view: the points the bags make"] = function(t)
    if not has(t) then return end
    t.eq(keyed(H.View(model()), "bags").label, H.BAGS:format(1, 3))
end

tests["prof helper view: bags that make no point say what to get"] = function(t)
    if not has(t) then return end
    local m = model()
    m.bags = { sure = 0, maybe = 0 }
    local part = keyed(H.View(m), "bags")
    t.eq(part.kind, "empty")
    t.eq(part.text, H.BAGS_NONE)
    t.eq(part.how, H.BAGS_HOW)
end

tests["prof helper view: what each recipe takes not read yet is an empty state, not a blank"] = function(t)
    if not has(t) then return end
    local m = model()
    m.bags = nil
    local part = keyed(H.View(m), "bags")
    t.eq({ part.kind, part.text, part.how }, { "empty", H.BAGS_UNREAD, H.UNREAD_HOW })
end

tests["prof helper view: each recipe is an item line with its icon, skill colour, chance and cost"] = function(t)
    if not has(t) then return end
    local view = H.View(model())
    t.eq(ofKind(view, "section")[1].text, H.RECIPES)
    local lines = ofKind(view, "itemLine")
    t.eq(#lines, 3)
    t.eq(lines[1].name, "Linen Bolt (" .. H.SURE .. ")")
    t.eq(lines[1].icon, ICON)
    t.eq(lines[1].money, 20)
    t.eq(lines[1].color, H.COLOURS.optimal)
    t.eq(lines[1].color.hex, "ff8040", "orange")
    t.eq(lines[2].name, "Linen Belt (" .. H.MAYBE .. ")")
    t.eq(lines[2].color.hex, "ffff00", "yellow")
    t.eq(lines[2].money, nil, "a cost not known is no money, never 0")
    t.eq(lines[2].icon, nil)
    t.eq(lines[3].name, "Odd Thing (" .. H.UNKNOWN .. ")")
    t.eq(lines[3].color, nil, "a colour not read is left to the kit")
end

tests["prof helper view: the four skill colours"] = function(t)
    if not has(t) then return end
    local want = { optimal = "ff8040", medium = "ffff00", easy = "40c040", trivial = "808080" }
    for name, hex in pairs(want) do
        local col = H.COLOURS[name]
        t.eq(type(col) == "table" and col.hex, hex, name)
        t.ok(type(col) == "table" and type(col.r) == "number" and type(col.g) == "number"
            and type(col.b) == "number", name .. " has r, g, b")
    end
end

tests["prof helper view: a cost that is not whole copper is rounded, never refused by the kit"] = function(t)
    if not has(t) then return end
    local m = model()
    m.recipes[1].cost = 20.4
    t.eq(ofKind(H.View(m), "itemLine")[1].money, 20)
end

tests["prof helper view: no recipe gives a point: what is missing and how to get it"] = function(t)
    if not has(t) then return end
    local m = model()
    m.recipes = {}
    local view = H.View(m)
    t.eq(#ofKind(view, "itemLine"), 0)
    local part = keyed(view, "recipes")
    t.eq({ part.kind, part.text, part.how }, { "empty", H.NONE, H.NONE_HOW })
end

tests["prof helper view: the notes follow under their own heading, and none means no heading"] = function(t)
    if not has(t) then return end
    local view = H.View(model())
    local sections = ofKind(view, "section")
    t.eq(sections[#sections].text, H.NOTES)
    t.eq(view.children[#view.children].label, "Next trainer recipe at skill 45.")
    local m = model()
    m.notes = {}
    sections = ofKind(H.View(m), "section")
    t.eq(#sections, 1, "only the recipes heading")
end

tests["prof helper view: a window not read yet is one empty state under the header"] = function(t)
    if not has(t) then return end
    local view = H.View({ reading = true })
    t.eq(view.id, "ProfHelper")
    t.eq(view.children[1].kind, "header")
    t.eq(#view.children, 2)
    t.eq({ view.children[2].kind, view.children[2].text, view.children[2].how }, { "empty", H.READING, H.READING_HOW })
end

tests["prof helper view: every empty state says what is missing and how to get it"] = function(t)
    if not has(t) then return end
    for _, pair in ipairs({ { H.READING, H.READING_HOW }, { H.BAGS_NONE, H.BAGS_HOW }, { H.BAGS_UNREAD, H.UNREAD_HOW },
        { H.NONE, H.NONE_HOW } }) do
        t.ok(type(pair[1]) == "string" and pair[1] ~= "", "what is missing")
        t.ok(type(pair[2]) == "string" and pair[2] ~= "", "how to get it, for: " .. tostring(pair[1]))
    end
end

tests["prof helper view: the kit takes every view as a window"] = function(t)
    if not has(t) then return end
    local K = ns.Kit
    t.ok(type(K) == "table" and type(K.Window) == "function", "ns.Kit.Window is there (UI/Kit.lua, zflow-kit-api)")
    if type(K) ~= "table" or type(K.Window) ~= "function" then return end
    local empty = model()
    empty.recipes, empty.bags, empty.goal, empty.state, empty.notes = {}, nil, nil, nil, nil
    for label, m in pairs({ full = model(), reading = { reading = true }, empty = empty }) do
        local tree, why = K.Window(H.View(m))
        t.ok(type(tree) == "table", label .. ": " .. tostring(why))
    end
end

return tests
