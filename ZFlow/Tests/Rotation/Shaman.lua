local _, ns = ...

-- N58 (lead section 241): the Shaman pack keeps no choice of yours yet. No
-- rule suggests an imbue or a totem (no read shows either), so a kept one
-- would change nothing. Classes/Shaman.lua says what the row waits for.

local tests = {}

tests["N58 shaman pack: no own-choice row while no rule suggests an imbue"] = function(t)
    local options = ns.Packs.SHAMAN.options
    t.eq(options.sticky, nil, "no sticky rows")
    for _, rule in ipairs(ns.Packs.SHAMAN.lists.default) do
        t.ok(not string.find(rule.spell, " Weapon", 1, true), "no imbue step: " .. rule.spell)
    end
end

return tests
