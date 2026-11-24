local _, ns = ...

-- Queue item A2: every profession end to end. For each of the twelve the
-- plan (Items/ProfPlan.lua) gives one sensible next thing from skill 1 to
-- the cap of the rank, and where the add-on holds no data it says how the
-- player teaches it. Pure and offline: every recipe, item, trainer, node
-- and place here is made up; none of this was looked at in game.

local tests = {}

local function P() return ns.ProfPlan end

local CRAFTS = { "Cooking", "First Aid", "Blacksmithing", "Leatherworking", "Tailoring", "Alchemy",
    "Engineering", "Enchanting" }
local GATHERS = { "Mining", "Herbalism", "Skinning", "Fishing" }
local NODE_KIND = { Mining = "Mining", Herbalism = "Herb Gathering", Fishing = "Fishing" }

-- Items: 1 Test Part (the material), 2 Test Ore, 3 Test Bar.
local NAMES = { [1] = "Test Part", [2] = "Test Ore", [3] = "Test Bar" }

-- One made-up recipe per crafting profession: orange from 1 to 30.
local function craftInput(prof, over)
    local recipe = "Test " .. prof .. " Thing"
    local i = {
        prof = prof, skill = 1, max = 75,
        book = { [recipe] = { profession = prof, makes = 90, mats = { [1] = 1 } } },
        colours = { [recipe] = { optimal = { lo = 1, hi = 30 } } },
        bags = { [1] = 5 }, bank = {},
        name = function(item) return NAMES[item] end,
        price = function() return nil end,
    }
    for k, v in pairs(over or {}) do i[k] = v end
    return i, recipe
end

local function gatherInput(prof, over)
    local i = { prof = prof, skill = 1, max = 75, bags = {}, bank = {},
        name = function(item) return NAMES[item] end }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

local function plain(t, text, what)
    t.ok(type(text) == "string" and text ~= "", what .. ": there is a line")
    t.ok(not tostring(text):find("%%"), what .. ": no unfilled slot")
    t.ok(not tostring(text):find("nil"), what .. ": no nil in the line")
end

for _, prof in ipairs(CRAFTS) do
    tests["every profession: " .. prof .. " at skill 1 says to make the recipe"] = function(t)
        local input, recipe = craftInput(prof)
        local steps, why = P().Plan(input)
        local last = steps[#steps]
        t.eq(why, nil, "there is a plan")
        t.eq(last.kind, "craft", "the last step is the craft")
        t.eq(last.recipe, recipe, "of the one recipe")
        t.eq(last.count, 5, "as many as the bags allow")
        plain(t, last.text, prof)
        t.ok(last.text:find(prof .. " 1 of 75", 1, true) ~= nil, "the line carries the reading")
    end

    tests["every profession: " .. prof .. " one point under the cap still gives one craft"] = function(t)
        local recipe = "Test " .. prof .. " Thing"
        local steps = P().Plan(craftInput(prof, { skill = 74,
            colours = { [recipe] = { medium = { lo = 60, hi = 80 } } } }))
        t.eq(steps[#steps].kind, "craft", "a craft")
        t.eq(steps[#steps].count, 1, "never past the cap")
    end

    tests["every profession: " .. prof .. " at the cap says to train the next rank"] = function(t)
        local steps, why = P().Plan(craftInput(prof, { skill = 75 }))
        t.eq(why, nil, "there is a plan")
        t.eq(#steps, 1, "one step")
        t.eq(steps[1].kind, "train_tier", "train the next rank")
        plain(t, steps[1].text, prof)
        t.ok(steps[1].text:find(prof, 1, true) ~= nil, "the line names the profession")
    end

    tests["every profession: " .. prof .. " short of materials names where they come from"] = function(t)
        local steps = P().Plan(craftInput(prof, { bags = {}, nodes = {},
            vendorPrice = function() return 5 end }))
        t.eq(steps[1].kind, "buy_vendor", "the material first, from a vendor (section 402 item 4)")
        t.eq(steps[1].item, 1, "the short material")
        t.eq(steps[#steps].kind, "craft", "then the craft")
        plain(t, steps[1].text, prof)
    end

    tests["every profession: " .. prof .. " short of materials, no vendor price: never the auction house"] = function(t)
        local steps = P().Plan(craftInput(prof, { bags = {}, nodes = {},
            vendorPrice = function() return nil end }))
        t.eq(#steps, 1, "one step")
        t.eq(steps[1] and steps[1].kind, "find_material", "no source seen: find it")
        t.eq(steps[1] and steps[1].item, 1)
    end

    tests["every profession: " .. prof .. " never opened says to open its window"] = function(t)
        local steps, why, say = P().Plan({ prof = prof })
        t.eq(#steps, 0, "no step")
        t.eq(why, "no reading", "no reading")
        t.eq(say, "Open your " .. prof .. " window once", "how the player teaches it")
    end

    tests["every profession: " .. prof .. " with colours never read says to open its window"] = function(t)
        local steps = P().Plan(craftInput(prof, { colours = {} }))
        t.eq(#steps, 1, "one step")
        t.eq(steps[1] and steps[1].kind, "open_window")
        t.eq(steps[1] and steps[1].text, "Open your " .. prof .. " window", "how the player teaches it")
    end

    tests["every profession: " .. prof .. " with nothing left to make says to see a trainer"] = function(t)
        local recipe = "Test " .. prof .. " Thing"
        local grey = { [recipe] = { trivial = { lo = 1, hi = 75 } } }
        -- Review of section 405 item 4: no trainer list seen is a step.
        local steps = P().Plan(craftInput(prof, { skill = 40, colours = grey }))
        t.eq(steps[1] and steps[1].kind, "learn_recipe", "no trainer seen: a step to any trainer")
        t.eq(steps[1] and steps[1].text, "Learn a " .. prof .. " recipe at a trainer (" .. prof .. " 40 of 75)")
        local lists = { a = { profession = prof, npc = "Test Trainer", rows = {} } }
        local none, why, named = P().Plan(craftInput(prof, { skill = 40, colours = grey, trainerLists = lists }))
        t.eq(#none, 0, "no step")
        t.eq(why, "no recipe", "no recipe")
        t.eq(named, "Visit Test Trainer for new " .. prof .. " recipes", "a trainer seen is named")
    end

    tests["every profession: " .. prof .. " with a recipe to learn says which and where"] = function(t)
        local recipe = "Test " .. prof .. " Thing"
        local grey = { [recipe] = { trivial = { lo = 1, hi = 75 } } }
        local lists = { a = { profession = prof, npc = "Test Trainer",
            rows = { { name = "Test New " .. prof, skill = 40, state = "available" } } } }
        local steps = P().Plan(craftInput(prof, { skill = 40, colours = grey, trainerLists = lists }))
        t.eq(#steps, 1, "one step")
        t.eq(steps[1].kind, "learn_recipe", "learn the recipe")
        t.eq(steps[1].recipe, "Test New " .. prof, "the one the trainer showed")
        t.eq(steps[1].npc, "Test Trainer", "at the trainer seen")
        t.eq(steps[1].target, nil, "no place guessed")
    end
end

for _, prof in ipairs(GATHERS) do
    tests["every profession: " .. prof .. " at skill 1 says to gather"] = function(t)
        local steps, why = P().Plan(gatherInput(prof))
        t.eq(why, nil, "there is a plan")
        t.eq(#steps, 1, "one step")
        t.eq(steps[1].kind, "gather_skill", "the gather step")
        t.eq(steps[1].gather, prof, "of this profession")
        t.eq(steps[1].target, nil, "no node seen: no place guessed")
        t.eq(steps[1].text, P().GATHER[prof].text .. " (" .. prof .. " 1 of 75)", "the line and the reading")
        plain(t, steps[1].text, prof)
    end

    tests["every profession: " .. prof .. " one point under the cap still says to gather"] = function(t)
        local steps = P().Plan(gatherInput(prof, { skill = 74, book = {} }))
        t.eq(steps[1].kind, "gather_skill", "the gather step")
    end

    tests["every profession: " .. prof .. " at the cap says to train the next rank"] = function(t)
        local steps = P().Plan(gatherInput(prof, { skill = 75 }))
        t.eq(#steps, 1, "one step")
        t.eq(steps[1].kind, "train_tier", "train the next rank")
        plain(t, steps[1].text, prof)
    end

    tests["every profession: " .. prof .. " with no skill read says to learn it"] = function(t)
        local steps, why, say = P().Plan({ prof = prof })
        t.eq(#steps, 0, "no step")
        t.eq(why, "no reading", "no reading")
        t.eq(say, "Learn " .. prof .. " from a trainer, then gather once", "it has no window to open")
    end

    tests["every profession: " .. prof .. " points at the nearest node seen on this map"] = function(t)
        local kind = NODE_KIND[prof]
        local nodes = {
            { kind = "Treasure", node = "Test Chest", map = 7, x = 0.5, y = 0.5 },
            { kind = kind or "Mining", node = "Test Far", map = 7, x = 0.9, y = 0.9 },
            { kind = kind or "Mining", node = "Test Near", map = 7, x = 0.52, y = 0.5 },
            { kind = kind or "Mining", node = "Test Other Map", map = 8, x = 0.5, y = 0.5 },
        }
        local steps = P().Plan(gatherInput(prof, { here = { map = 7, x = 0.5, y = 0.5 }, nodes = nodes }))
        local s = steps[1]
        if kind then
            t.eq(s.node, "Test Near", "the nearest of its own kind")
            t.eq(s.target.map, 7, "on this map")
            t.eq(s.target.x, 0.52, "at the node")
            t.ok(s.text:find("the nearest seen is Test Near", 1, true) ~= nil, "the line names it")
        else
            t.eq(s.target, nil, "no node kind: no place")
            t.eq(s.node, nil, "and no node named")
        end
    end
end

tests["every profession: Mining smelts for a point before it says to mine"] = function(t)
    local book = { ["Smelt Test Bar"] = { profession = "Mining", makes = 3, mats = { [2] = 2 } } }
    local colours = { ["Smelt Test Bar"] = { optimal = { lo = 1, hi = 25 } } }
    local steps = P().Plan(gatherInput("Mining", { book = book, colours = colours, bags = { [2] = 4 } }))
    t.eq(steps[#steps].kind, "craft", "the smelt")
    t.eq(steps[#steps].count, 2, "two from four ore")
    local none = P().Plan(gatherInput("Mining", { book = book, colours = colours, bags = {},
        nodes = {}, vendorPrice = function() return nil end }))
    t.eq(none[1].kind, "gather_skill", "no ore: mine, never buy ore at the auction house")
end

-- Whole add-on: a profession with no window has no saved reading, so the
-- skill comes from the skill lines.
tests["every profession: Herbalism reads its skill from the skill lines"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setSkillRanks({ Herbalism = { rank = 12, max = 75 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    t.ok(addon ~= nil, "the add-on started")
    local steps, why = P().Plan(P().Input(c, addon.store, "Herbalism"))
    t.eq(why, nil, "there is a plan")
    t.eq(steps[1].kind, "gather_skill", "the gather step")
    t.ok(steps[1].text:find("Herbalism 12 of 75", 1, true) ~= nil, "with the live reading")
end

tests["every profession: a saved reading wins over the skill lines"] = function(t)
    local c = ns.make.fakeClient()
    c.setSkillRanks({ Mining = { rank = 3, max = 75 } })
    local store = { get = function(_, scope, path)
        if scope == "char" and path == "learned.facts.profSkill" then
            return { Mining = { skill = 20, max = 75 } }
        end
        return nil
    end }
    local input = P().Input(c, store, "Mining")
    t.eq(input.skill, 20, "the reading the window saved")
    local bare = P().Input(c, { get = function() return nil end }, "Mining")
    t.eq(bare.skill, 3, "the skill line when no window was read")
    t.eq(bare.max, 75, "and its cap")
end

return tests
