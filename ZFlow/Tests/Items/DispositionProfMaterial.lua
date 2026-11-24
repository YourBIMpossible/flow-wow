local _, ns = ...

-- P-COACH C4 (owner 11-20, DISPATCH 382): no material of a profession the
-- character has ever had is given a sell or vendor disposition; they go to
-- the auction house. Pure: items and context are made up.

local D = ns.Disposition
local tests = {}

local function grey(key)
    return { key = key, name = "Cheap Thread", count = 3, quality = 0, sellPrice = 5, classID = 7 }
end

local function sold(d)
    return d.action == "sell" or d.action == "vendor"
end

tests["prof material: a grey material of a profession you have is not sold as junk"] = function(t)
    local d = D.Decide(grey(901), { materials = { [901] = { { prof = "Tailoring" } } } })
    t.eq(sold(d), false, "not sold")
    t.eq(d.action, "keep", "kept")
end

tests["prof material: a material of a profession you are past, or once had, is not sold"] = function(t)
    local d = D.Decide(grey(902), { everMaterials = { [902] = "Tailoring" } })
    t.eq(sold(d), false, "not sold")
    t.eq(d.action, "keep", "kept for the auction house")
end

tests["prof material: a grey item of no profession is still junk"] = function(t)
    local d = D.Decide(grey(903), { everMaterials = { [902] = "Tailoring" } })
    t.eq(d.action, "sell", "junk is still sold")
end

return tests
