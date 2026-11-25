local _, ns = ...
-- R-06 (lead section 777): the arrow's "Also here" named a quest once per
-- objective (two nearby objectives of one quest read as the same title
-- twice; Plexy's route-a4 review, Nav/StepTip.lua:147-148). Each quest is
-- named once. Flow lists each other goal in the area once
-- (Modules/Nav/Nav.lua:4447-4457). Pure; made-up stops. Fails before: no
-- ST.Also.
local tests = {}

local function ST() return ns.Nav.StepTip end
local function near() return 10 end

tests["step tip: also here names each quest once"] = function(t)
    t.eq(type(ST().Also), "function", "ST.Also")
    if type(ST().Also) ~= "function" then return end
    local stops = {
        { quest = 7, label = "Wolves", place = { map = 1 } },
        { quest = 8, label = "Boars", place = { map = 1 } },
        { quest = 8, label = "Boars", place = { map = 1 } },
        { quest = 9, label = "Kobolds", place = { map = 1 } },
        { kind = "sell", label = "Sell", place = { map = 1 } },
        { kind = "sell", label = "Sell", place = { map = 1 } },
    }
    t.eq(ST().Also(stops, 7, near), { "Boars", "Kobolds", "Sell" }, "this quest left out, the rest once each")
    t.eq(ST().Also(stops, nil, function() return 999 end), {}, "none near")
    t.eq(ST().Also(nil, 7, near), {})
end

return tests
