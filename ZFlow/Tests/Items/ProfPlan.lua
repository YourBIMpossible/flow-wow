local _, ns = ...

-- Tests for ZFlow/Items/ProfPlan.lua (lead section 382, P-COACH C1): the
-- ordered steps toward the next skill point of one profession, from the
-- recipe book, the colours the window showed, the bags, the bank and the
-- trainer lists seen. Pure: every recipe, item, price, trainer and place here
-- is made up.
--
-- Contract (CODE-zflow-prof-plan-contract.md): ProfPlan.Plan(input) ->
-- steps, reason. A step is { kind, text, item, count, target, recipe, npc,
-- station }; kind is learn_recipe, train_tier, make_part, take_bank,
-- go_station or craft; target is { map, x, y } or nil (never guessed).
--
-- Red before the code: ns.ProfPlan does not exist, so every test fails.

local tests = {}

local function P() return ns.ProfPlan end

-- Items: 1 Test Ore, 2 Test Bar, 3 Test Cloth, 4 Test Thread.
local NAMES = { [1] = "Test Ore", [2] = "Test Bar", [3] = "Test Cloth", [4] = "Test Thread" }
local PRICES = { [2] = 100, [3] = 10, [4] = 5 }

local BOOK = {
    ["Test Buckle"] = { profession = "Blacksmithing", makes = 50, mats = { [2] = 2 } },
    ["Test Nail"] = { profession = "Blacksmithing", makes = 51, mats = { [2] = 1 } },
    ["Test Old Rod"] = { profession = "Blacksmithing", makes = 52, mats = { [2] = 1 } },
    ["Smelt Test Bar"] = { profession = "Mining", makes = 2, mats = { [1] = 2 } },
    ["Test Bolt"] = { profession = "Tailoring", makes = 53, mats = { [3] = 2, [4] = 1 } },
    ["Test Patch"] = { profession = "Tailoring", makes = 54, mats = { [3] = 1 } },
}
-- At 50: Buckle orange to 55, Nail yellow, Old Rod grey; Bolt orange, Patch
-- yellow.
local COLOURS = {
    ["Test Buckle"] = { optimal = { lo = 45, hi = 55 } },
    ["Test Nail"] = { medium = { lo = 48, hi = 60 } },
    ["Test Old Rod"] = { trivial = { lo = 40, hi = 60 } },
    ["Test Bolt"] = { optimal = { lo = 50, hi = 52 } },
    ["Test Patch"] = { medium = { lo = 50, hi = 60 } },
}

local function input(over)
    local i = {
        prof = "Blacksmithing", skill = 50, max = 75,
        book = BOOK, colours = COLOURS,
        bags = {}, bank = {},
        price = function(item) return PRICES[item] end,
        name = function(item) return NAMES[item] end,
    }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

local function kinds(steps)
    local out = {}
    for i, s in ipairs(steps or {}) do out[i] = s.kind end
    return out
end

tests["prof plan: the module and its words exist"] = function(t)
    t.eq(type(P()), "table", "ns.ProfPlan")
    if type(P()) ~= "table" then return end
    t.eq(type(P().Plan), "function", "ProfPlan.Plan")
    t.eq(type(P().Candidates), "function", "ProfPlan.Candidates")
    t.eq(P().NAME, "profPlan")
end

tests["prof plan: orange and yellow give a point, sure first, then the cheapest; grey never"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local list = P().Candidates(input())
    local names = {}
    for i, c in ipairs(list) do names[i] = c.recipe end
    t.eq(names, { "Test Buckle", "Test Nail" }, "Old Rod is grey; Mining and Tailoring are other professions")
    t.eq(list[1].chance, "sure")
    t.eq(list[2].chance, "maybe")
    t.eq(list[1].cost, 200, "two bars at 100")
    local cheap = P().Candidates(input({ prof = "Tailoring" }))
    t.eq(cheap[1].recipe, "Test Bolt", "sure before a cheaper maybe")
    local both = P().Candidates(input({ colours = {
        ["Test Buckle"] = { medium = { lo = 45, hi = 55 } }, ["Test Nail"] = { medium = { lo = 45, hi = 55 } } } }))
    t.eq(both[1].recipe, "Test Nail", "two maybes: the cheaper first")
end

tests["prof plan: craft here, as many as the bags make and the orange span gives"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local steps = P().Plan(input({ prof = "Tailoring", bags = { [3] = 20, [4] = 20 } }))
    t.eq(kinds(steps), { "craft" })
    local s = steps[1] or {}
    t.eq(s.recipe, "Test Bolt")
    t.eq(s.item, 53)
    t.eq(s.count, 3, "orange from 50 to 52: three sure points")
    t.eq(s.target, nil, "no place: text only")
    t.eq(s.text, "Make 3 Test Bolt (Tailoring 50 of 75)")
    steps = P().Plan(input({ prof = "Tailoring", bags = { [3] = 3, [4] = 1 } }))
    t.eq(steps[1] and steps[1].count, 1, "the bags make one")
    steps = P().Plan(input({ prof = "Tailoring", skill = 74, colours = { ["Test Bolt"] = { optimal = { lo = 70, hi = 90 } } },
        bags = { [3] = 20, [4] = 20 } }))
    t.eq(steps[1] and steps[1].count, 1, "points stop at the cap")
end

tests["prof plan: a craft at a station: go there first, then make it"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local steps = P().Plan(input({ station = "anvil", bags = { [2] = 4 } }))
    t.eq(kinds(steps), { "go_station", "craft" })
    t.eq(steps[1] and steps[1].station, "anvil")
    t.eq(steps[1] and steps[1].target, nil, "no anvil seen: text only")
    t.eq(steps[1] and steps[1].text, "Go to an anvil")
    t.eq(steps[2] and steps[2].count, 2)
    t.eq(steps[2] and steps[2].text, "Make 2 Test Buckle at an anvil (Blacksmithing 50 of 75)")
    local seen = { map = 1429, x = 0.5, y = 0.25 }
    steps = P().Plan(input({ station = "anvil", stationTarget = seen, bags = { [2] = 4 } }))
    t.eq(steps[1] and steps[1].target, seen, "an anvil seen: its place")
    steps = P().Plan(input({ station = "anvil", atStation = true, bags = { [2] = 4 } }))
    t.eq(kinds(steps), { "craft" }, "already at one")
end

tests["prof plan: ore in the bags and a known smelt: make the part first"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local steps = P().Plan(input({ station = "anvil", atStation = true, bags = { [1] = 9 } }))
    t.eq(kinds(steps), { "make_part", "craft" })
    local s = steps[1] or {}
    t.eq(s.station, "forge")
    t.eq(s.recipe, "Smelt Test Bar")
    t.eq(s.item, 2)
    t.eq(s.count, 4, "nine ore make four bars")
    t.eq(s.text, "Smelt 4 Test Bar at a forge, for Test Buckle")
    t.eq(steps[2] and steps[2].count, 2, "four bars make two buckles")
    steps = P().Plan(input({ book = { ["Test Buckle"] = BOOK["Test Buckle"] }, bags = { [1] = 9 } }))
    t.eq(kinds(steps), { "find_material" }, "no smelt recipe known: no part step, the short bar is the step")
end

tests["prof plan: what the bags lack and the bank holds: take it from the bank"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local steps = P().Plan(input({ prof = "Tailoring", bags = { [3] = 1 }, bank = { [3] = 10, [4] = 5 } }))
    t.eq(kinds(steps), { "take_bank", "take_bank", "craft" })
    t.eq(steps[1] and steps[1].item, 3)
    t.eq(steps[1] and steps[1].count, 5, "for three crafts: 6 cloth less 1")
    t.eq(steps[1] and steps[1].text, "Take 5 Test Cloth from your bank, for Test Bolt")
    t.eq(steps[2] and steps[2].item, 4)
    t.eq(steps[2] and steps[2].count, 3)
    t.eq(steps[3] and steps[3].count, 3)
end

tests["prof plan: nothing gives a point: learn a recipe the trainer lists at this skill"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local lists = {
        a = { profession = "Blacksmithing", npc = "Test Smith", rows = {
            { name = "Test Hinge", state = "available", skill = 50 },
            { name = "Test Later", state = "unavailable", skill = 60 },
            { name = "Test Buckle", state = "known", skill = 1 } } },
        b = { profession = "Tailoring", npc = "Test Tailor", rows = { { name = "Test Hat", state = "available", skill = 1 } } },
    }
    local npcs = { ["Test Smith"] = { map = 1429, x = 0.4, y = 0.6, trains = "Blacksmithing" } }
    local grey = { ["Test Buckle"] = { trivial = { lo = 40, hi = 60 } } }
    local steps = P().Plan(input({ colours = grey, trainerLists = lists, npcs = npcs }))
    t.eq(kinds(steps), { "learn_recipe" })
    local s = steps[1] or {}
    t.eq(s.recipe, "Test Hinge")
    t.eq(s.npc, "Test Smith")
    t.eq(s.target, { map = 1429, x = 0.4, y = 0.6 })
    t.eq(s.text, "Learn Test Hinge at Test Smith (Blacksmithing 50 of 75)")
    steps = P().Plan(input({ colours = grey, trainerLists = lists }))
    t.eq(steps[1] and steps[1].target, nil, "trainer place not seen: text only")
    -- Lead section 422 item 1 (b): nothing to learn at this skill yet names
    -- the next skill the trainer teaches at, as one plain line.
    local none = P().Plan(input({ colours = grey, trainerLists = { a = { profession = "Blacksmithing", npc = "Test Smith",
        rows = { { name = "Test Later", state = "unavailable", skill = 60 } } } } }))
    t.eq(kinds(none), { "no_point" }, "nothing to learn at this skill yet")
    t.eq(none[1] and none[1].text, "No point yet; next rank at 60")
end

tests["prof plan: at the cap: train the next rank"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local lists = { a = { profession = "Blacksmithing", npc = "Test Smith", rows = {} } }
    local steps = P().Plan(input({ skill = 75, max = 75, bags = { [2] = 9 }, trainerLists = lists }))
    t.eq(kinds(steps), { "train_tier" })
    t.eq(steps[1] and steps[1].npc, "Test Smith")
    t.eq(steps[1] and steps[1].text, "Train the next Blacksmithing rank at Test Smith (75 of 75)")
    steps = P().Plan(input({ skill = 75, max = 75 }))
    t.eq(steps[1] and steps[1].text, "Train the next Blacksmithing rank at a trainer (75 of 75)", "no trainer seen")
    t.eq(steps[1] and steps[1].target, nil)
end

tests["prof plan: gives a point but no materials anywhere: no steps and the reason"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    -- Review of section 405 item 4: no source seen is a step naming the material.
    local steps = P().Plan(input())
    t.eq(steps[1] and steps[1].kind, "find_material")
    t.ok(steps[1] and steps[1].text:find(": no source seen yet$") ~= nil, tostring(steps[1] and steps[1].text))
    t.eq(select(2, P().Plan(nil)), "no reading")
    t.eq(select(2, P().Plan(input({ skill = "50" }))), "no reading")
    t.eq(select(2, P().Plan(input({ max = 0 }))), "no reading")
end

tests["prof plan: a recipe read in part, or with no materials, is no candidate"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local book = {
        ["Test Buckle"] = { profession = "Blacksmithing", mats = { [2] = 2 }, partial = true },
        ["Test Nail"] = { profession = "Blacksmithing" },
    }
    t.eq(P().Candidates(input({ book = book })), {})
end

-- Section 383 (owner): never silent, no item numbers. An empty plan says the
-- one thing to do so Z-Flow will know; a name not read yet is never a number.
tests["prof plan: an empty plan says the one thing to do next"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local _, why, say = P().Plan(input({ skill = "50" }))
    t.eq(why, "no reading")
    t.eq(say, "Open your Blacksmithing window once")
    _, _, say = P().Plan(nil)
    t.eq(say, "Open a profession window once")
    -- Review of section 405 item 4: these two are steps now.
    local open = P().Plan(input({ colours = {} }))
    t.eq(open[1] and open[1].text, "Open your Blacksmithing window", "no recipe colour read for this profession")
    local find = P().Plan(input())
    t.eq(find[1] and find[1].kind, "find_material")
    local grey = { ["Test Buckle"] = { trivial = { lo = 40, hi = 60 } } }
    -- Review of section 405 item 4: no trainer list seen is a step to one.
    local steps = P().Plan(input({ colours = grey }))
    t.eq(steps[1] and steps[1].kind, "learn_recipe")
end

tests["prof plan: a material whose name is not read yet is never a number"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local steps = P().Plan(input({ prof = "Tailoring", bags = { [3] = 1 }, bank = { [3] = 10, [4] = 5 },
        name = function() return nil end }))
    t.eq(steps[1] and steps[1].text, "Take 5 of the materials from your bank, for Test Bolt")
    for _, s in ipairs(steps) do
        t.eq(s.text:find("item %d"), nil, s.text)
    end
end

tests["prof plan: the craft step lists each material: bags, bank, smelt (section 388 a)"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local steps = P().Plan(input({ station = "anvil", atStation = true,
        bags = { [1] = 5, [2] = 1 }, bank = { [2] = 1 } }))
    t.eq(kinds(steps), { "make_part", "take_bank", "craft" })
    t.eq(steps[1] and steps[1].from, { item = 1, count = 4 }, "two bars from four ore")
    local craft = steps[3] or {}
    t.eq(craft.count, 2)
    t.eq(craft.mats, { { item = 2, need = 4, bags = 1, bank = 1, smelt = 2, ore = 1, oreCount = 4,
        text = "Test Bar x4: 1 in your bags, 1 from your bank, smelt 2 from 4 Test Ore" } })
end

tests["prof plan: the craft step says the skill it reaches and what comes after"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local steps = P().Plan(input({ bags = { [2] = 20 } }))
    local craft = steps[#steps] or {}
    t.eq(craft.recipe, "Test Buckle")
    t.eq(craft.reach, 56, "orange to 55: six sure points from 50")
    t.eq(craft.after, "Test Nail")
    t.eq(craft.thenText, "Blacksmithing 50 -> 56, then Test Nail")
    steps = P().Plan(input({ colours = { ["Test Nail"] = { medium = { lo = 48, hi = 60 } } }, bags = { [2] = 20 } }))
    craft = steps[#steps] or {}
    t.eq(craft.reach, nil, "yellow: only some give a point; no sure skill")
    t.eq(craft.after, nil, "nothing else gives a point")
    t.eq(craft.thenText, nil)
end

-- Lead section 418 item 5: every recipe on the seen trainer list is known
-- and none gives a point. The arrow names the known recipe most likely to
-- give one, never "Visit <trainer>": the latest colour seen first, then
-- materials held, then the cheapest by known prices. One say line, not one
-- per step, tells that recipes from vendors and drops are not known.
tests["prof plan: trainer done: the known recipe most likely to give a point (section 418 item 5)"] = function(t)
    if type(P()) ~= "table" then return t.ok(false, "ns.ProfPlan") end
    local book = {
        ["Test Gone Sash"] = { profession = "Tailoring", makes = 60, mats = { [4] = 1 } },
        ["Test Late Robe"] = { profession = "Tailoring", makes = 61, mats = { [3] = 2 } },
        ["Test Late Cap"] = { profession = "Tailoring", makes = 62, mats = { [4] = 1 } },
        ["Test Late Belt"] = { profession = "Tailoring", makes = 63, mats = { [3] = 1 } },
    }
    -- Lead section 419: each seen green or grey below the skill, so none
    -- gives a point (a colour only last seen orange or yellow would).
    local colours = {
        ["Test Gone Sash"] = { trivial = { lo = 60, hi = 90 } },
        ["Test Late Robe"] = { medium = { lo = 80, hi = 100 }, easy = { lo = 101, hi = 105 } },
        ["Test Late Cap"] = { medium = { lo = 80, hi = 100 }, easy = { lo = 101, hi = 105 } },
        ["Test Late Belt"] = { medium = { lo = 80, hi = 100 }, easy = { lo = 101, hi = 105 } },
    }
    local rows = {}
    for name in pairs(book) do rows[#rows + 1] = { name = name, skill = 1, state = "known" } end
    local lists = { a = { profession = "Tailoring", npc = "Test Tailor", rows = rows } }
    local base = { prof = "Tailoring", skill = 110, max = 150, book = book, colours = colours,
        trainerLists = lists, bags = { [3] = 1 } }
    local steps, _, say = P().Plan(input(base))
    t.eq(kinds(steps), { "maybe_craft" }, "one step")
    local s = steps[1] or {}
    t.eq(s.recipe, "Test Late Belt", "latest colour, materials held (before the cheaper Cap)")
    t.eq(s.count, 1)
    t.eq(s.text, "Make 1 Test Late Belt: may give a point (Tailoring 110 of 150)")
    t.eq(s.why, nil, "the say line is not on the step")
    t.eq(say, P().SAY_KNOWN_ONLY, "said once")
    t.eq(say, "This add-on does not know recipes sold by vendors or found as drops")
    base.bags = {}
    steps = P().Plan(input(base))
    -- By the prices above: the Cap's one of item 4 (5) is under the Belt's one of item 3 (10).
    t.eq(steps[1] and steps[1].recipe, "Test Late Cap", "none held: the cheapest")
    t.eq(steps[1] and steps[1].text, "Make 1 Test Late Cap: may give a point (Tailoring 110 of 150)")
    -- A recipe on the list not learned yet (later skill) is not trainer done.
    lists.a.rows = { { name = "Test Later", skill = 120, state = "unavailable" } }
    local none, why = P().Plan(input(base))
    t.eq(none, {}, "still waiting on the trainer")
    t.eq(why, "no recipe")
end

return tests
