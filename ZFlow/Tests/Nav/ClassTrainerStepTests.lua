-- Class trainer step (G44): when the class pack names spells at or below
-- the player's level that the player has not learned, the route gets a
-- "visit your class trainer" step. A saved class trainer on this map gets
-- a place; one on another map or none saved: words only, no made-up place.
-- Made-up packs and places, test only. Nothing trains or buys.
local _, ns = ...

local T = {}

local function S() return ns.ClassTrainerStep end

local PACK = { spells = {
    ["Charge"] = { level = 4 },
    ["Rend"] = { level = 4 },
    ["Hamstring"] = { level = 8 },
    ["Taunt"] = { level = 10, note = "from a class quest" },
    ["Cleave"] = { level = 20 },
} }
local HERE = { map = 1453, x = 0.5, y = 0.5 }
local NPCS = {
    ["Ander Germaine"] = { map = 1453, x = 0.6, y = 0.5, roles = { classTrainer = true },
                           classes = { WARRIOR = true } },
    ["Far Trainer"] = { map = 1429, x = 0.4, y = 0.4, roles = { classTrainer = true },
                        classes = { WARRIOR = true } },
    ["Mage Teacher"] = { map = 1453, x = 0.51, y = 0.5, roles = { classTrainer = true },
                         classes = { MAGE = true } },
}

local function none() return false end
local function knows(set) return function(name) return set[name] == true end end

T["class trainer step: the names agreed"] = function(t)
    local M = S()
    t.ok(type(M) == "table", "the module is there")
    if type(M) ~= "table" then return end
    t.eq(M.NAME, "classTrainerStep")
    t.eq(M.SETTING, "nav.classTrainerStep")
    t.eq(M.KIND, "classTrainer")
end

T["class trainer step: new spells and a trainer here - a step with a place"] = function(t)
    local M = S()
    if type(M) ~= "table" then return t.ok(false, "no module") end
    local step = M.Of(M.Count(PACK, 10, none), "WARRIOR", HERE, NPCS)
    t.eq(step.kind, "classTrainer")
    t.eq(step.count, 3, "Charge, Rend, Hamstring; not the quest spell, not above the level")
    t.eq(step.name, "Ander Germaine", "the warrior trainer, not the nearer mage trainer")
    t.eq(step.place, { map = 1453, x = 0.6, y = 0.5 })
    t.eq(M.Lines(step), { "Visit your class trainer Ander Germaine: 3 new spells to learn." })
end

T["class trainer step: one spell says spell"] = function(t)
    local M = S()
    if type(M) ~= "table" then return t.ok(false, "no module") end
    local step = M.Of(M.Count(PACK, 10, knows({ Charge = true, Rend = true })), "WARRIOR", HERE, NPCS)
    t.eq(M.Lines(step), { "Visit your class trainer Ander Germaine: 1 new spell to learn." })
end

T["class trainer step: nothing new - no step"] = function(t)
    local M = S()
    if type(M) ~= "table" then return t.ok(false, "no module") end
    local all = knows({ Charge = true, Rend = true, Hamstring = true })
    t.eq(M.Count(PACK, 10, all), 0)
    t.eq(M.Of(0, "WARRIOR", HERE, NPCS), nil)
end

T["class trainer step: level or spells not read - nothing"] = function(t)
    local M = S()
    if type(M) ~= "table" then return t.ok(false, "no module") end
    t.eq(M.Count(PACK, nil, none), nil, "level not known")
    t.eq(M.Count(nil, 10, none), nil, "no pack")
    t.eq(M.Count(PACK, 10, function() return nil end), 0, "spells not read are not counted")
    t.eq(M.Of(nil, "WARRIOR", HERE, NPCS), nil)
end

T["class trainer step: none saved - words only, no place"] = function(t)
    local M = S()
    if type(M) ~= "table" then return t.ok(false, "no module") end
    local step = M.Of(2, "WARRIOR", HERE, nil)
    t.eq(step.place, nil)
    t.eq(step.name, nil)
    local lines = M.Lines(step)
    t.eq(#lines, 1)
    t.ok(lines[1]:find("2 new spells to learn", 1, true) ~= nil, "the count")
    t.ok(lines[1]:find("open its window once", 1, true) ~= nil, "what to do")
end

T["class trainer step: a trainer on another map - named, no place"] = function(t)
    local M = S()
    if type(M) ~= "table" then return t.ok(false, "no module") end
    local step = M.Of(2, "WARRIOR", { map = 1429, x = 0.1, y = 0.1 },
        { ["Ander Germaine"] = NPCS["Ander Germaine"] })
    t.eq(step.place, nil)
    t.eq(step.name, "Ander Germaine")
    t.eq(M.Lines(step), { "Visit your class trainer Ander Germaine (on another map): 2 new spells to learn." })
end

T["class trainer step: a trainer window is a class trainer when it lists a class spell"] = function(t)
    local M = S()
    if type(M) ~= "table" then return t.ok(false, "no module") end
    t.eq(M.IsClassTrainer({ services = { { name = "Rend", state = "available" } } }, PACK), true)
    t.eq(M.IsClassTrainer({ services = { { name = "Bandage", state = "available" } } }, PACK), false)
    t.eq(M.IsClassTrainer({ npc = "x" }, PACK), false)
end

T["class trainer step: look only - nothing trains, buys or clicks"] = function(t)
    local M = S()
    if type(M) ~= "table" then return t.ok(false, "no module") end
    for name in pairs(M) do
        local n = tostring(name):lower()
        t.ok(not (n:find("^train") or n:find("buy") or n:find("click") or n:find("auto")),
            "no acting function: " .. n)
    end
end

return T
