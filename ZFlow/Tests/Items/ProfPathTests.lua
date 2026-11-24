local _, ns = ...

-- Tests for ZFlow/Items/ProfPath.lua (lead section 449, P-PATH-1): the
-- profession path from the current skill to 300, read from the shipped rows
-- (Items/ProfData.lua, first guesses from Flow) and the colours the player
-- saw (Items/RecipeColours.lua). Offline: the bags, bank, prices and colours
-- here are made up; the recipes are the shipped rows. Not tested in game.
--
-- Red before the code: ns.ProfPath does not exist, so every test fails.

local tests = {}

local function PP() return ns.ProfPath end
local function D() return ns.ProfData end

local DASH = "\226\128\147"
local TIMES = "\195\151"

local PROFS = { "Blacksmithing", "Mining", "First Aid", "Cooking", "Fishing", "Herbalism",
    "Tailoring", "Leatherworking", "Alchemy", "Enchanting", "Engineering" }
-- Professions whose path crafts (so has materials to net).
local CRAFTS = { "Blacksmithing", "First Aid", "Cooking", "Tailoring", "Leatherworking",
    "Alchemy", "Enchanting", "Engineering" }

local function path(prof, over)
    local input = { prof = prof, skill = 1, max = 75, bags = {}, bank = {}, prices = {} }
    for k, v in pairs(over or {}) do input[k] = v end
    return PP().Path(input)
end

local function matRow(p, item)
    for _, m in ipairs(p.mats) do
        if m.item == item then return m end
    end
    return nil
end

tests["prof path: every profession of section 449 has shipped rows"] = function(t)
    for _, prof in ipairs(PROFS) do
        t.ok(type(D().PROFS[prof]) == "table", prof .. " has a row")
    end
    t.ok(D().NOTE:find("needs a game check", 1, true) ~= nil, "the rows say they are first guesses")
end

tests["prof path: no shipped row carries Flow's guide path"] = function(t)
    for prof, g in pairs(D().PROFS) do
        for _, r in ipairs(g.steps or {}) do
            t.eq(r.use, nil, prof .. ": " .. tostring(r.recipe))
        end
    end
end

for _, prof in ipairs(PROFS) do
    tests["prof path: " .. prof .. " has brackets from the skill to 300"] = function(t)
        local p = path(prof)
        t.ok(type(p) == "table" and #p.brackets > 0, "brackets present")
        if type(p) ~= "table" or #p.brackets == 0 then return end
        t.eq(p.brackets[1].from, 1, "starts at the skill")
        t.eq(p.brackets[#p.brackets].to, 300, "ends at 300")
        t.eq(p.to, 300)
        for i, b in ipairs(p.brackets) do
            t.ok(b.to > b.from, prof .. " bracket " .. i .. " gains points")
            if i > 1 then t.eq(b.from, p.brackets[i - 1].to, prof .. " bracket " .. i .. " follows on") end
            t.ok(type(b.text) == "string" and b.text:find("^skill %d+" .. DASH .. "%d+: .+ " .. TIMES .. "%d+$") ~= nil,
                prof .. " line: " .. tostring(b.text))
        end
        t.eq(p.trains, { { at = 75, cap = 150 }, { at = 150, cap = 225 }, { at = 225, cap = 300 } }, "tier caps")
    end
end

for _, prof in ipairs(CRAFTS) do
    tests["prof path: " .. prof .. " materials are netted against bags and bank"] = function(t)
        local first = path(prof)
        t.ok(type(first) == "table" and #first.mats > 0, "materials listed")
        if type(first) ~= "table" or #first.mats == 0 then return end
        local item = first.mats[1].item
        local need = first.mats[1].need
        t.eq(first.mats[1].short, need, "nothing held: all of it is short")
        local p = path(prof, { bags = { [item] = 1 }, bank = { [item] = 2 } })
        local m = matRow(p, item)
        t.eq(m and m.bags, 1)
        t.eq(m and m.bank, 2)
        t.eq(m and m.need, need, "the need does not change")
        t.eq(m and m.short, math.max(0, need - 3), "short = need minus bags and bank")
        local full = path(prof, { bags = { [item] = need + 5 } })
        t.eq(matRow(full, item).short, 0, "more held than needed is never below 0")
        t.ok(type(m and m.source) == "table" and type(m.source.kind) == "string"
            and type(m.source.text) == "string", "each material has a source")
    end
end

for _, prof in ipairs(PROFS) do
    if prof ~= "Fishing" then
        tests["prof path: " .. prof .. " a colour seen in game wins over the table"] = function(t)
            local p = path(prof)
            local b = p and p.brackets[1]
            t.ok(b and type(b.recipe) == "string", "a first recipe")
            if not (b and b.recipe) then return end
            t.eq(b.seen, false, "from the table")
            local seen = path(prof, { colours = { [b.recipe] = { trivial = { lo = 1, hi = 1 } } } })
            t.ok(seen.brackets[1].recipe ~= b.recipe, "seen grey at the skill: not picked")
        end
    end
end

tests["prof path: Cooking at 1 picks the cheapest orange, and a seen colour moves it"] = function(t)
    local p = path("Cooking")
    t.eq(p.brackets[1].recipe, "Brilliant Smallfish", "all free and orange: by name")
    local seen = path("Cooking", { colours = {
        ["Brilliant Smallfish"] = { trivial = { lo = 1, hi = 5 } },
        ["Charred Wolf Meat"] = { easy = { lo = 1, hi = 5 } },
    } })
    t.eq(seen.brackets[1].recipe, "Roasted Boar Meat")
    t.eq(seen.brackets[1].seen, false)
end

tests["prof path: a seen orange beats a table grey"] = function(t)
    local p = path("First Aid", { skill = 100, max = 150,
        colours = { ["Linen Bandage"] = { optimal = { lo = 100, hi = 104 } } } })
    t.eq(p.brackets[1].recipe, "Linen Bandage")
    t.eq(p.brackets[1].seen, true)
    t.eq(p.brackets[1].colour, "optimal")
    t.eq(p.brackets[1].from, 100)
    t.eq(p.trains, { { at = 150, cap = 225 }, { at = 225, cap = 300 } })
end

tests["prof path: a known price picks the cheaper recipe"] = function(t)
    -- Cooking 1: all three free; price the smallfish dear and the boar cheap.
    local p = path("Cooking", { prices = { [6291] = 500, [2672] = 300, [769] = 1 } })
    t.eq(p.brackets[1].recipe, "Roasted Boar Meat")
end

tests["prof path: a faction keeps the other side's recipes out"] = function(t)
    local p = path("Cooking", { faction = "Alliance", skill = 50, max = 75 })
    for _, b in ipairs(p.brackets) do
        t.ok(b.recipe ~= "Strider Stew" and b.recipe ~= "Roasted Kodo Meat", tostring(b.recipe))
    end
end

tests["prof path: an unknown recipe is marked to learn, a known one is not"] = function(t)
    local p = path("First Aid")
    t.eq(p.brackets[1].learn, true)
    local k = path("First Aid", { known = { ["Linen Bandage"] = true } })
    t.eq(k.brackets[1].learn, false)
end

tests["prof path: crafts per point by colour"] = function(t)
    local row = { learn = 1, yellow = 10, green = 20, grey = 30 }
    t.eq(PP().CraftsPerPoint(row, "optimal", 5), 1)
    t.eq(PP().CraftsPerPoint(row, "medium", 20), 2, "(grey - yellow) / (grey - skill)")
    t.eq(PP().CraftsPerPoint(row, "medium", 10), 1)
end

tests["prof path: the colour at a skill, seen first"] = function(t)
    local row = { recipe = "R", learn = 1, yellow = 10, green = 20, grey = 30 }
    t.eq(PP().Colour(row, 5), "optimal")
    t.eq(PP().Colour(row, 15), "medium")
    t.eq(PP().Colour(row, 25), "easy")
    t.eq(PP().Colour(row, 30), "trivial")
    t.eq(PP().Colour({ learn = 40, yellow = 50, green = 60, grey = 70 }, 30), nil, "not learnable yet")
    local c, seen = PP().Colour(row, 25, { R = { optimal = { lo = 20, hi = 26 } } })
    t.eq(c, "optimal")
    t.eq(seen, true)
end

tests["prof path: bracket line"] = function(t)
    t.eq(PP().Text({ from = 1, to = 30, recipe = "Linen Bandage", count = 30 }),
        "skill 1" .. DASH .. "30: Linen Bandage " .. TIMES .. "30")
end

tests["prof path: material sources"] = function(t)
    t.eq(PP().Source(2770).kind, "gather")
    t.eq(PP().Source(2589).kind, "kill")
    t.eq(PP().Source(6291).kind, "fish")
    t.eq(PP().Source(2880).kind, "vendor")
    t.eq(PP().Source(2880).price, 100)
    t.eq(PP().Source(2880, 90).price, 90, "a price read wins over the table's")
    t.eq(PP().Source(2841).kind, "auction")
    t.eq(PP().Source(2841).text, PP().AUCTION)
end

tests["prof path: no data and the top"] = function(t)
    local p, why = PP().Path({ prof = "Nope", skill = 1, max = 75 })
    t.eq(p, nil)
    t.eq(why, "no data")
    local q, why2 = PP().Path({ prof = "Cooking", skill = 300, max = 300 })
    t.eq(q, nil)
    t.eq(why2, "at the top")
    local r, why3 = PP().Path({ prof = "Cooking" })
    t.eq(r, nil)
    t.eq(why3, "no reading")
end

tests["prof path: the profession plan's input reads into a path input"] = function(t)
    local i = PP().FromPlanInput({ prof = "Cooking", skill = 10, max = 75,
        book = { ["Charred Wolf Meat"] = { profession = "Cooking" }, Other = { profession = "Tailoring" } },
        colours = { X = {} }, bags = { [1] = 2 }, bank = { [3] = 4 },
        price = function(item) return item == 769 and 7 or nil end })
    t.eq(i.prof, "Cooking")
    t.eq(i.skill, 10)
    t.eq(i.max, 75)
    t.eq(i.known, { ["Charred Wolf Meat"] = true })
    t.eq(i.colours, { X = {} })
    t.eq(i.bags, { [1] = 2 })
    t.eq(i.bank, { [3] = 4 })
    t.eq(type(i.prices), "function")
    t.eq(i.prices(769), 7)
end

-- Lead section 450: the contract fields. Red before 2026-11-24's fix: the
-- path had brackets and mats only, so UI/ProfPathPanel.lua drew nothing.
for _, prof in ipairs(PROFS) do
    tests["prof path contract: " .. prof .. " has the section 450 fields"] = function(t)
        local p = path(prof)
        t.ok(type(p) == "table", "a path")
        if type(p) ~= "table" then return end
        t.eq(p.id, prof); t.eq(p.prof, prof); t.eq(p.skill, 1); t.eq(p.max, 75); t.eq(p.status, "ok")
        t.ok(type(p.rev) == "number" and p.rev >= 1, "a rev")
        t.eq(p.selected, 1, "the first bracket is the current one")
        t.eq(#p.ranges, #p.brackets, "one range for each bracket")
        t.eq(type(p.tasks), "table")
        for i, r in ipairs(p.ranges) do
            local b = p.brackets[i]
            t.eq(r.from, b.from); t.eq(r.to, b.to); t.eq(r.recipe, b.recipe); t.eq(r.crafts, b.count)
            t.eq(type(r.sure), "boolean")
            t.ok(r.colourFrom == "seen" or r.colourFrom == "table", "colourFrom")
            t.ok(type(r.learnAt) == "table" and (r.learnAt.kind == "known" or r.learnAt.kind == "trainer"
                or r.learnAt.kind == "recipe"), "learnAt is a table with a kind")
        end
        local trained = 0
        for _, r in ipairs(p.ranges) do
            if r.prereq then
                trained = trained + 1
                t.eq(r.prereq.skill, r.from, "the training comes before the bracket")
                t.ok(r.prereq.tier > r.prereq.skill, "and names the next tier")
            end
        end
        t.eq(trained, #p.trains, "one prereq for each training")
    end
end

tests["prof path contract: net is need less bags and bank, never below 0"] = function(t)
    local base = path("Blacksmithing")
    local m = base.materials[1]
    t.ok(m ~= nil and m.need > 2, "a material to net")
    if not m then return end
    t.eq(m.bankSeen, true); t.eq(m.allocated, 0); t.eq(m.net, m.need)
    local p = path("Blacksmithing", { bags = { [m.item] = 1 }, bank = { [m.item] = 1 } })
    t.eq(p.materials[1].net, m.need - 2)
    p = path("Blacksmithing", { bags = { [m.item] = m.need + 5 } })
    t.eq(p.materials[1].net, 0, "never below 0")
end

tests["prof path contract: a bank never seen gives no bank count and an unknown net"] = function(t)
    local p = path("Blacksmithing", { bank = {}, bankSeen = false })
    local m = p.materials[1]
    t.eq(m.bankSeen, false); t.eq(m.bank, nil); t.eq(m.net, "unknown")
    p = path("Blacksmithing", { bankSeen = false, bags = { [m.item] = m.need } })
    t.eq(p.materials[1].net, 0, "the bags alone cover it, so the bank does not matter")
    local mapped = PP().FromPlanInput({ prof = "Blacksmithing", skill = 1, bank = {}, bankSeen = false })
    t.eq(mapped.bankSeen, false, "the plan input's word is carried")
end

tests["prof path contract: rev stays for the same answer and bumps when it changes"] = function(t)
    local a = path("Cooking")
    local b = path("Cooking")
    t.eq(b.rev, a.rev, "nothing changed")
    local item = a.materials[1] and a.materials[1].item
    if item == nil then
        t.ok(false, "Cooking has no material to change")
        return
    end
    local c = path("Cooking", { bags = { [item] = 1 } })
    t.eq(c.rev, a.rev + 1, "the bags changed")
    local d = path("Cooking", { skill = 2 })
    t.eq(d.rev, c.rev + 1, "the skill changed")
end

return tests
