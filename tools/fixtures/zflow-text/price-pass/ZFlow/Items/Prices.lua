local _, ns = ...
-- Prices.lua is where coin text is built and labelled.
local P = {}
function P.Coin(g, s) return g .. "g " .. s .. "s" end
function P.Text(v) return "about " .. P.Coin(v, 0) .. " (estimate)" end
return P
