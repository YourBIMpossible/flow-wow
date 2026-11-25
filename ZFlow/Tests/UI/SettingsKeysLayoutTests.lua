local _, ns = ...

-- Tests for the self button key in the Combined button layout (lead section
-- 624 Step 5; UI/SettingsKeys.lua): the key is refused, with the agreed
-- words, while the layout is Combined. Pure part.

local tests = {}

local function SK() return ns.SettingsKeys end

tests["keys: the self button key is refused in the Combined layout"] = function(t)
    t.eq(SK().CombinedWhy("selfButton", "combined"), "Combined layout: the Flow button's key casts your buffs too.")
end

tests["keys: the self button key is taken in the Separate layout or with no layout"] = function(t)
    t.eq(SK().CombinedWhy("selfButton", "separate"), nil)
    t.eq(SK().CombinedWhy("selfButton", nil), nil)
end

tests["keys: the Flow button key is taken in either layout"] = function(t)
    t.eq(SK().CombinedWhy("flowButton", "combined"), nil)
    t.eq(SK().CombinedWhy("careKey", "combined"), nil)
end

return tests
