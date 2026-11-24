local _, ns = ...

-- Parity row A1-09 (lead section 485): inside a wide arrival radius but
-- 24 yd or more from the middle, the words say "You're in the area".
-- Pure; made-up distances. Not tested in game.
-- Fails before: there is no Nav/AreaWords.lua.

local tests = {}

tests["area words: near the middle there are no area words"] = function(t)
    local AW = ns.Nav.AreaWords
    t.eq(AW.Words(0), nil)
    t.eq(AW.Words(23.9), nil)
end

tests["area words: 24 yd and more is the area"] = function(t)
    local AW = ns.Nav.AreaWords
    t.eq(AW.Words(24), "You're in the area")
    t.eq(AW.Words(80), "You're in the area")
end

tests["area words: an unknown distance says nothing"] = function(t)
    local AW = ns.Nav.AreaWords
    t.eq(AW.Words(nil), nil)
    t.eq(AW.Words(0 / 0), nil)
    t.eq(AW.Words(math.huge), nil)
end

return tests
