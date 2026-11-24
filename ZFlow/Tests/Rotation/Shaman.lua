local _, ns = ...

-- N58 (lead section 241): the Shaman pack keeps no choice of yours yet.
-- P-SELFBUFF added the imbue steps (read against your weapon enchant), but
-- the imbue you cast is not kept: the first one you know is asked for.
-- Classes/Shaman.lua says what the own-choice row waits for.

local tests = {}

tests["N58 shaman pack: no own-choice row; the imbue steps are buff rules"] = function(t)
    local options = ns.Packs.SHAMAN.options
    t.eq(options.sticky, nil, "no sticky rows")
    local imbues = 0
    for _, rule in ipairs(ns.Packs.SHAMAN.lists.default) do
        if string.find(rule.spell, " Weapon", 1, true) then
            imbues = imbues + 1
            t.eq(rule.kind, "buff", "an imbue step is a buff rule: " .. rule.spell)
        end
    end
    t.eq(imbues, 3, "Windfury, Flametongue and Rockbiter")
end

return tests
