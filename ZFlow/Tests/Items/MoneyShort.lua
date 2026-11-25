local _, ns = ...

-- E-49 (lead section 674): money reads short, about three figures in its
-- biggest coin ("1.36g"), at every copper/silver/gold edge.

local P = ns.Prices
local tests = {}

tests["money short: zero and copper"] = function(t)
    t.eq(P.Coin(0), "0c", "nothing")
    t.eq(P.Coin(1), "1c", "one copper")
    t.eq(P.Coin(99), "99c", "the most copper below a silver")
    t.eq(P.Coin(0.4), "under 1c", "less than a copper is never 0c")
end

tests["money short: silver"] = function(t)
    t.eq(P.Coin(100), "1s", "one silver")
    t.eq(P.Coin(552), "5.52s", "two places under ten silver")
    t.eq(P.Coin(4550), "45.5s", "one place under a hundred silver")
    t.eq(P.Coin(1240), "12.4s", "trailing zero dropped")
    t.eq(P.Coin(9999), "1g", "99s 99c rounds up to a whole gold")
end

tests["money short: gold"] = function(t)
    t.eq(P.Coin(10000), "1g", "one gold")
    t.eq(P.Coin(13552), "1.36g", "the lead's example")
    t.eq(P.Coin(10203), "1.02g", "1g 2s 3c")
    t.eq(P.Coin(136000), "13.6g", "one place under a hundred gold")
    t.eq(P.Coin(1240000), "124g", "whole gold from a hundred")
    t.eq(P.Coin(12400000), "1240g", "past 999 gold: whole gold")
end

tests["money short: rounding"] = function(t)
    t.eq(P.Coin(98.6), "99c", "to the copper")
    t.eq(P.Coin(99.6), "1s", "copper carries into silver")
    t.eq(P.Coin(13549), "1.35g", "rounded down")
    t.eq(P.Coin(13550), "1.36g", "half rounds up")
    t.eq(P.Coin(99960), "10g", "9.996g reads 10g")
    t.eq(P.Coin(999600), "100g", "99.96g reads 100g")
end

tests["money short: large sums are plain digits"] = function(t)
    t.eq(P.Coin(2147483647), "214748g", "the old 32-bit money cap")
    t.eq(P.Coin(2e18), "200000000000000g", "never 2e+14g")
    t.ok(not P.Coin(5e19):find("e", 1, true), "no exponent")
end

tests["money short: not a count has no text"] = function(t)
    t.eq(P.Coin(-1), nil, "negative is not a count")
    t.eq(P.Coin(nil), nil, "nothing given")
    t.eq(P.Coin("12"), nil, "text")
end

return tests
