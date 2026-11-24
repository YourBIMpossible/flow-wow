-- P-PROF slice 4 (Lazy, zflow-prof-lz-4): the craft that gives a point,
-- with its mats short in the bags but there with the bank's, says to visit
-- the banker first, as Flow's SkillPlan UseBank. Pure: bag and bank counts
-- come in by item key (Items/HaveTip.lua).
local _, ns = ...
local N = ns.Nav
local MEAT = 2672

local function input(bags, bank)
    return {
        professions = { Cooking = true },
        readings = { Cooking = { skill = 50, max = 75 } },
        book = { ["Spiced Wolf Ribs"] = { profession = "Cooking", mats = { [MEAT] = 2 } } },
        colours = { ["Spiced Wolf Ribs"] = { optimal = { lo = 1, hi = 100 } } },
        bags = bags, bank = bank,
    }
end

return {
    ["prof bank: short in the bags, there with the bank: the banker first"] = function(t)
        local s = N.ProfNext(input({ [MEAT] = 1 }, { [MEAT] = 3 }))
        t.eq(s.lines[1], N.PROF_CRAFT_SURE:format("Spiced Wolf Ribs", "Cooking"))
        t.eq(#s.lines, 2, "two lines")
        t.eq(s.lines[2], N.PROF_BANK_NOTE)
        t.ok(type(N.PROF_BANK_NOTE) == "string", "a note")
    end,
    ["prof bank: enough in the bags, or not even with the bank: the line as before"] = function(t)
        t.eq(#N.ProfNext(input({ [MEAT] = 2 }, { [MEAT] = 3 })).lines, 1, "bags enough")
        t.eq(#N.ProfNext(input({}, { [MEAT] = 1 })).lines, 1, "not enough anywhere")
        t.eq(#N.ProfNext(input(nil, { [MEAT] = 3 })).lines, 1, "bags not read")
        t.eq(#N.ProfNext(input({}, nil)).lines, 1, "bank never seen")
    end,
}
