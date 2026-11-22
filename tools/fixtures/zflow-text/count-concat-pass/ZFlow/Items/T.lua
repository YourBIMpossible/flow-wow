local T = {}
function T.A(n) return n .. (n == 1 and " price " or " prices ") .. "unknown—check vendor" end
function T.B(n, plural) return plural(n, "price", "prices") .. " unknown—check trainer" end
return T
