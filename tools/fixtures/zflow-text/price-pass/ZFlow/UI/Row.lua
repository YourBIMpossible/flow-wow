local _, ns = ...
local R = {}
function R.Line(name, price) return name .. ": " .. ns.Prices.Text(price) end
R.WAIT = "try again in 5s"
R.EST = "about 12s 40c (estimate)"
return R
