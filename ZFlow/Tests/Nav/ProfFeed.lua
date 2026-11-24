-- The profession coach's pick (lead section 382, C2 P-COACH): one step
-- across all the character's professions. Below max only; the nearest by
-- travel time wins; a step on another continent is held back as text, never
-- an arrow; with nothing known, the one thing to do so it will be known.
-- Pure: plain tables in, a pick out. A fake Plan (the C1 contract:
-- Plan(profession) -> { { kind, text, item, count, target } }). Made-up
-- names and places only. Not tested in game.
--
-- Red before the code: Nav/ProfFeed.lua does not exist, so every test here
-- fails.
local _, ns = ...

local N = ns.Nav
local T = {}

local function F() return N.ProfFeed end

local function has(t)
    local ok = type(F()) == "table" and type(F().Pick) == "function" and type(F().Step) == "function"
    t.ok(ok, "Nav/ProfFeed.lua gives Pick and Step")
    return ok
end

-- Map 1411 is on continent 1, map 1412 on continent 1, map 1453 on 2.
local CONT = { [1411] = 1, [1412] = 1, [1453] = 2 }
local NAMES = { [1453] = "Eastern Kingdoms" }

-- Seconds away, by map and x: made up, as the module's travel read would give.
local function cost(target)
    if target.map == 1411 then return math.floor(target.x * 100) end
    if target.map == 1412 then return 500 end
    return nil
end

local function input(steps, readings, names)
    return {
        names = names or { "Cooking", "Mining", "Tailoring" },
        readings = readings or {
            Cooking = { skill = 40, max = 75 },
            Mining = { skill = 60, max = 75 },
            Tailoring = { skill = 75, max = 75 },
        },
        plan = function(prof) return steps[prof] end,
        cont = 1,
        cost = cost,
        contOf = function(map) return CONT[map] end,
        contName = function(map) return NAMES[map] end,
    }
end

local MINE = { kind = "gather", text = "Mine 5 Copper Ore", item = 2770, count = 5,
               target = { map = 1411, x = 0.6, y = 0.5 } }
local FISH = { kind = "go_station", text = "Cook 4 Brilliant Smallfish at a fire", count = 4,
               target = { map = 1411, x = 0.2, y = 0.5 } }
local FAR = { kind = "learn_recipe", text = "Learn Spiced Wolf Meat at the cooking trainer",
              target = { map = 1453, x = 0.4, y = 0.4 } }
local SEW = { kind = "craft", text = "Make 3 Linen Bandage", count = 3 }

T["prof feed: the nearest step by travel time wins across professions"] = function(t)
    if not has(t) then return end
    local r = F().Pick(input({ Cooking = { FISH }, Mining = { MINE } }))
    t.eq(r.pick and r.pick.prof, "Cooking", "the fire is 20 s away, the vein 60 s")
    t.eq(r.pick and r.pick.step and r.pick.step.text, FISH.text)
    t.eq(r.pick and r.pick.seconds, 20)
    local step = F().Step(r)
    t.ok(type(step.place) == "table", "a step with a place on this continent is an arrow")
    t.eq(step.place and step.place.map, 1411)
    t.eq(step.label, FISH.text, "the step's own words under the needle")
end

T["prof feed: a step on another continent is held back as text, never an arrow"] = function(t)
    if not has(t) then return end
    local r = F().Pick(input({ Cooking = { FAR }, Mining = { MINE } }))
    t.eq(r.pick and r.pick.prof, "Mining", "the step here wins over the one across the sea")
    local held = F().Pick(input({ Cooking = { FAR } }))
    t.eq(held.pick and held.pick.prof, "Cooking")
    t.eq(held.pick and held.pick.held, true)
    local step = F().Step(held)
    t.eq(step.place, nil, "no place: no needle")
    t.eq(step.still, true)
    -- Lead section 416 item 2: then one line for each other profession;
    -- Mining has no step, Tailoring is at its max with no training step.
    t.eq(step.lines, { F().HELD:format("Eastern Kingdoms", FAR.text), "Open your Mining window once" })
    t.eq(step.lines[1], "Next time you are in Eastern Kingdoms: " .. FAR.text)
end

T["prof feed: only a profession below its max gives a step"] = function(t)
    if not has(t) then return end
    -- Tailoring is at 75 of 75: its step is never picked, near as it is.
    local near = { kind = "craft", text = "Make 1 Linen Bag", target = { map = 1411, x = 0.01, y = 0.5 } }
    local r = F().Pick(input({ Tailoring = { near }, Mining = { MINE } }))
    t.eq(r.pick and r.pick.prof, "Mining")
    local none = F().Pick(input({ Tailoring = { near } }, { Tailoring = { skill = 75, max = 75 } }, { "Tailoring" }))
    t.eq(none.pick, nil, "every profession at its max: no pick")
end

T["prof feed: a step with no place is text under the needle, and wins when it can be done here"] = function(t)
    if not has(t) then return end
    local r = F().Pick(input({ Tailoring = { SEW }, Mining = { MINE } },
        { Tailoring = { skill = 50, max = 75 }, Mining = { skill = 60, max = 75 } }))
    t.eq(r.pick and r.pick.prof, "Tailoring", "a craft is done where you stand")
    local step = F().Step(r)
    t.eq(step.place, nil)
    -- Lead section 416 item 2: then Cooking, not read, by name.
    t.eq(step.lines, { SEW.text, "Open your Cooking window once" })
end

T["prof feed: nothing known says the one thing to do so it will be known"] = function(t)
    if not has(t) then return end
    local r = F().Pick(input({}, { Mining = { skill = 60, max = 75 } }, { "Mining" }))
    t.eq(r.pick and r.pick.prof, "Mining")
    local step = F().Step(r)
    t.eq(step.lines, { "Open your Mining window once" })
    -- A profession with no reading at all: the same line.
    local fresh = F().Pick(input({ Cooking = { FISH } }, {}, { "Cooking" }))
    t.eq(F().Step(fresh).lines, { "Open your Cooking window once" })
end

T["prof feed: the plan lines name each profession, its skill and max, its steps, and the pick"] = function(t)
    if not has(t) then return end
    local r = F().Pick(input({ Cooking = { FISH, FAR }, Mining = { MINE } }))
    local lines = F().Lines(r)
    local text = table.concat(lines, "\n")
    t.ok(text:find("Cooking: 40 of 75", 1, true) ~= nil, "Cooking's skill and max")
    t.ok(text:find("  1. " .. FISH.text, 1, true) ~= nil, "its first step")
    t.ok(text:find("  2. " .. FAR.text, 1, true) ~= nil, "then its next")
    t.ok(text:find("Mining: 60 of 75", 1, true) ~= nil)
    t.ok(text:find("Tailoring: 75 of 75, at its max", 1, true) ~= nil)
    t.eq(lines[#lines], "Next: " .. FISH.text .. " (Cooking): the nearest, about 20 seconds away.")
    for _, line in ipairs(lines) do
        t.eq(line:find("%d%d%d%d"), nil, "no item number: " .. line)
    end
end

return T
