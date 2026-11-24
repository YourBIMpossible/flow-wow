local _, ns = ...
-- Lead review of section 405 item 4: the walk of Tests/E2E/ProfWalk.lua with
-- recipes learned. For every profession, walk skill 1 to 299 through the
-- real planner entry (addon.profPlan.plan) in five learned states and list
-- the skill values where the plan names no step, with its reason. Each test
-- pins the gap list of one state, so the list here is the coverage table:
--   ladder, mats:   a learned recipe sure at every skill, materials in the bags
--   ladder, none:   the same recipes, nothing in the bags, no source seen
--   outgrown:       one learned recipe, grey past 24, materials in the
--                   bags; no trainer list seen
--   trainer done:   as outgrown, with a trainer list seen and all of it known
--   no colours:     recipes learned, their colours never read
-- Ranks end at 75, 150, 225 and 300; at a rank's end the step is the next
-- rank. Every recipe, item, trainer and skill span is made up (section 406:
-- no recipe data from anywhere). Loaded the way the game loads it
-- (ns.offline.addon) on a fake client. Not tested in game.
local tests = {}

local CRAFT = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
    "First Aid", "Leatherworking", "Tailoring" }
local GATHER = { "Fishing", "Herbalism", "Mining", "Skinning" }
local CAP = 300
local MAT = 9001
local NPC = "Test Trainer"

local function rankMax(skill)
    for _, top in ipairs({ 75, 150, 225, 300 }) do
        if skill <= top then return top end
    end
    return CAP
end

-- A made-up recipe sure from each multiple of 25 for 25 points; outgrown
-- keeps only the first.
local function book(prof, outgrown)
    local b, colours = {}, {}
    for lo = 1, CAP - 1, 25 do
        local name = string.format("Test %s %d", prof, lo)
        b[name] = { profession = prof, makes = 9100 + lo, mats = { [MAT] = 1 } }
        colours[name] = { optimal = { lo = lo, hi = lo + 24 } }
        if outgrown then break end
    end
    return b, colours
end

local function start(prof, state)
    local b, colours = book(prof, state == "outgrown" or state == "trainer done")
    local learned = { facts = { recipeBook = b } }
    if state ~= "no colours" then learned.recipeColors = colours end
    if state == "trainer done" then
        local rows = {}
        for name in pairs(b) do rows[#rows + 1] = { name = name, skill = 1, state = "known" } end
        learned.trainerLists = { [NPC] = { profession = prof, npc = NPC, rows = rows } }
    end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, { learned = learned })
    c.setZone(1, 1411); c.setFaction("Horde"); c.setLevel(20)
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setBagItems(state ~= "ladder, none" and { { item = MAT, count = 999 } } or {})
    c.setProfessions({ prof })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return addon
end

-- "a-b" ranges of a sorted skill list.
local function ranges(list)
    local out, from, last = {}, nil, nil
    local function close()
        if from then out[#out + 1] = from == last and tostring(from) or (from .. "-" .. last) end
    end
    for _, s in ipairs(list) do
        if last and s == last + 1 then last = s else close(); from, last = s, s end
    end
    close()
    return out
end

-- { [reason] = { "a-b", ... } } of the skill values 1 to 299 with no step.
local function walk(prof, state)
    local addon = start(prof, state)
    local plan = addon.profPlan and addon.profPlan.plan
    if type(plan) ~= "function" then return { ["no plan"] = { "1-299" } } end
    local gaps = {}
    for skill = 1, CAP - 1 do
        addon.store:set("char", "learned.facts.profSkill", { [prof] = { skill = skill, max = rankMax(skill) } })
        local ok, steps, reason = pcall(plan, prof)
        if not ok or type(steps) ~= "table" or steps[1] == nil then
            local why = ok and tostring(reason) or "error"
            gaps[why] = gaps[why] or {}
            table.insert(gaps[why], skill)
        end
    end
    local out = {}
    for why, list in pairs(gaps) do out[why] = ranges(list) end
    return out
end

-- The craft skill values that are not a rank's end, as ranges.
local OUTGROWN = { "25-74", "76-149", "151-224", "226-299" }

-- The coverage table: per state, the craft gaps. Gathering professions never
-- end without a step (the gather line), so their gaps are none in every state.
local CRAFT_GAPS = {
    ["ladder, mats"] = {},
    -- Review: no source seen for the short material is a step naming it.
    ["ladder, none"] = {},
    -- Fixed: no trainer list seen, so the next step is a new recipe at one.
    ["outgrown"] = {},
    -- Measured limit: every recipe on the seen trainer's list is known; the
    -- plan says "Visit <trainer> for new <prof> recipes" (no vendor or drop
    -- recipes are known to the addon; section 406).
    ["trainer done"] = { ["no recipe"] = OUTGROWN },
    -- Review: colours never read is a step to open the window.
    ["no colours"] = {},
}

for _, state in ipairs({ "ladder, mats", "ladder, none", "outgrown", "trainer done", "no colours" }) do
    for _, prof in ipairs(CRAFT) do
        tests["prof walk learned: " .. prof .. ", " .. state] = function(t)
            t.eq(walk(prof, state), CRAFT_GAPS[state], prof .. ", " .. state)
        end
    end
    for _, prof in ipairs(GATHER) do
        tests["prof walk learned: " .. prof .. ", " .. state] = function(t)
            t.eq(walk(prof, state), {}, prof .. ", " .. state)
        end
    end
end

tests["prof walk learned: outgrown with no trainer seen names a new recipe at a trainer"] = function(t)
    local addon = start("Tailoring", "outgrown")
    addon.store:set("char", "learned.facts.profSkill", { Tailoring = { skill = 40, max = 75 } })
    local steps = addon.profPlan.plan("Tailoring")
    t.eq(steps[1] and steps[1].kind, "learn_recipe")
    t.eq(steps[1] and steps[1].recipe, nil, "no recipe is named: none was seen")
end

tests["prof walk learned: rank ends train the next rank in every state"] = function(t)
    local addon = start("Tailoring", "ladder, none")
    for _, skill in ipairs({ 75, 150, 225 }) do
        addon.store:set("char", "learned.facts.profSkill", { Tailoring = { skill = skill, max = skill } })
        local steps = addon.profPlan.plan("Tailoring")
        t.eq(steps[1] and steps[1].kind, "train_tier", tostring(skill))
    end
end

-- Lead section 407 item 1: a short material with no vendor or node seen is
-- bought at the auction house; finding it is for no source read at all.
tests["prof walk learned: no materials and no vendor seen buys at the auction house"] = function(t)
    local addon = start("Tailoring", "ladder, none")
    addon.store:set("char", "learned.facts.profSkill", { Tailoring = { skill = 40, max = 75 } })
    local steps = addon.profPlan.plan("Tailoring")
    t.eq(steps[1] and steps[1].kind, "buy_auction")
    t.eq(steps[1] and steps[1].item, MAT)
end

tests["prof walk learned: colours never read: open the window"] = function(t)
    local addon = start("Tailoring", "no colours")
    addon.store:set("char", "learned.facts.profSkill", { Tailoring = { skill = 40, max = 75 } })
    local steps = addon.profPlan.plan("Tailoring")
    t.eq(steps[1] and steps[1].kind, "open_window")
    t.eq(steps[1] and steps[1].text, "Open your Tailoring window")
end

return tests
