local _, ns = ...
-- Lead section 400 item 1. Owner: "He's supposed to walk me through getting
-- all my Professions all the way up." For every profession, walk skill 1 to
-- the cap one point at a time through the real planner entry
-- (addon.profPlan.plan, Items/ProfPlan.lua, read from the client and the
-- store) and fail on any skill value with no next step. A failure names the
-- profession and the skill ranges with no step: that is the gap list.
--
-- The character has learned the profession and opened its window once (the
-- skill reading is saved, its book and colours read empty) and has seen
-- nothing else: no recipe known, no trainer list, nothing in the bags or bank. That is where a
-- new player starts. Ranks end at 75, 150, 225 and 300; at a rank's end the
-- reading's max is that end. Loaded the way the game loads it
-- (ns.offline.addon) on a fake client. Not tested in game.
local tests = {}

local CRAFT = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
    "First Aid", "Leatherworking", "Tailoring" }
local GATHER = { "Fishing", "Herbalism", "Mining", "Skinning" }
local CAP = 300

local function rankMax(skill)
    for _, top in ipairs({ 75, 150, 225, 300 }) do
        if skill <= top then return top end
    end
    return CAP
end

local function start(prof)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    -- The window was opened once: its book and colours were read, empty.
    c.setSaved(ns.id.charDB, { learned = { facts = { recipeBook = {} }, recipeColors = {} } })
    c.setZone(1, 1411); c.setFaction("Horde"); c.setLevel(20)
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setBagItems({})
    c.setProfessions({ prof })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- "a-b" ranges of the skill values with no step, e.g. { "1-74", "76-149" }.
local function ranges(list)
    local out, from, last = {}, nil, nil
    local function close()
        if from then out[#out + 1] = from == last and tostring(from) or (from .. "-" .. last) end
    end
    for _, s in ipairs(list) do
        if last and s == last + 1 then
            last = s
        else
            close()
            from, last = s, s
        end
    end
    close()
    return out
end

local function walk(t, prof)
    local _, addon = start(prof)
    local plan = addon.profPlan and addon.profPlan.plan
    if type(plan) ~= "function" then return t.ok(false, "addon.profPlan.plan") end
    local gaps, why = {}, {}
    for skill = 1, CAP do
        addon.store:set("char", "learned.facts.profSkill", { [prof] = { skill = skill, max = rankMax(skill) } })
        local ok, steps, reason = pcall(plan, prof)
        if not ok or type(steps) ~= "table" or steps[1] == nil then
            gaps[#gaps + 1] = skill
            why[ok and tostring(reason) or ("error: " .. tostring(steps))] = true
        end
    end
    local reasons = {}
    for r in pairs(why) do reasons[#reasons + 1] = r end
    table.sort(reasons)
    t.eq(ranges(gaps), {}, prof .. ": skill values with no next step (" .. table.concat(reasons, ", ") .. ")")
end

for _, prof in ipairs(CRAFT) do
    tests["prof walk: " .. prof .. " 1 to 300, a next step at every skill"] = function(t) walk(t, prof) end
end
for _, prof in ipairs(GATHER) do
    tests["prof walk: " .. prof .. " 1 to 300, a next step at every skill"] = function(t) walk(t, prof) end
end

-- 300 is the last rank's end in Classic: there is no rank past it to train.
tests["prof walk: at 300 of 300 no step says to train a next rank"] = function(t)
    for _, prof in ipairs({ "Tailoring", "Mining" }) do
        local _, addon = start(prof)
        addon.store:set("char", "learned.facts.profSkill", { [prof] = { skill = CAP, max = CAP } })
        local steps = addon.profPlan.plan(prof)
        t.ok(not (steps and steps[1] and steps[1].kind == "train_tier"), prof .. ": no rank past 300")
    end
end

tests["prof walk: the gap ranges read plainly"] = function(t)
    t.eq(ranges({ 1, 2, 3, 5, 7, 8 }), { "1-3", "5", "7-8" })
    t.eq(ranges({}), {})
end

return tests
