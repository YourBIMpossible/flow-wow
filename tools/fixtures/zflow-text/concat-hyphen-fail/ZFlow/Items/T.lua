local T = {}
function T.A(n, plural) return plural(n, "price", "prices") .. " unknown - check vendor" end
return T
