local _, ns = ...
-- R-09 (section 835): the other route steps in the area, for the arrow's
-- hover once the player has arrived (Nav/AlsoHere.lua). Ported from Flow's
-- arrow hover (b657e6e5 Modules/Nav/Nav.lua:4385-4405) and N:InArea
-- (:4438-4445, AREA = 45 yards). Made-up stops and places; not tested in game.

local tests = {}

local function AH() return ns.Nav.AlsoHere end

-- A 1000 x 1000 yard map: a share of 0.01 is 10 yards.
local HERE = { map = 1, x = 0.5, y = 0.5 }
local SIZE = { w = 1000, h = 1000 }

local function obj(label, quest, objective, map, x, y, detail)
    return { label = label, quest = quest, objective = objective, detail = detail,
             place = { map = map, x = x, y = y } }
end

tests["also here: the same quest's other objective at 20 yd is listed"] = function(t)
    local cur = obj("Wolves", 7, 1, 1, 0.5, 0.5, "Kill 0/8")
    local other = obj("Wolves", 7, 2, 1, 0.52, 0.5, "Loot 2/6")
    local out = AH().Lines({ cur, other }, cur, HERE, SIZE)
    t.ok(out ~= nil, "an answer")
    t.eq(out.header, AH().HEADER)
    t.eq(out.lines, { "Wolves - Loot 2/6" })
end

tests["also here: the current step is never listed, by identity or by quest and objective"] = function(t)
    local cur = obj("Wolves", 7, 1, 1, 0.5, 0.5)
    t.eq(AH().Lines({ cur }, cur, HERE, SIZE), nil)
    local copy = obj("Wolves", 7, 1, 1, 0.5, 0.5)
    t.eq(AH().Lines({ copy }, cur, HERE, SIZE), nil)
end

tests["also here: a step at 50 yd is not listed, one at 45 is"] = function(t)
    local cur = obj("Now", 1, 1, 1, 0.5, 0.5)
    t.eq(AH().Lines({ cur, obj("Far", 2, 1, 1, 0.55, 0.5) }, cur, HERE, SIZE), nil)
    local out = AH().Lines({ cur, obj("Edge", 3, 1, 1, 0.545, 0.5) }, cur, HERE, SIZE)
    t.eq(out and out.lines, { "Edge" })
end

tests["also here: a step on another map is not listed"] = function(t)
    local cur = obj("Now", 1, 1, 1, 0.5, 0.5)
    t.eq(AH().Lines({ cur, obj("Other", 2, 1, 2, 0.5, 0.5) }, cur, HERE, SIZE), nil)
end

tests["also here: a hand-in, a pick-up or an errand is not an area step"] = function(t)
    local cur = obj("Now", 1, 1, 1, 0.5, 0.5)
    local steps = {
        cur,
        { label = "Hand in", quest = 2, turnIn = true, place = { map = 1, x = 0.5, y = 0.5 } },
        { label = "Pick up", quest = 3, kind = "pickup", place = { map = 1, x = 0.5, y = 0.5 } },
        { label = "Sell", kind = "sell", place = { map = 1, x = 0.5, y = 0.5 } },
    }
    t.eq(AH().Lines(steps, cur, HERE, SIZE), nil)
end

tests["also here: at most the cap, then how many more"] = function(t)
    local cur = obj("Now", 1, 1, 1, 0.5, 0.5)
    local steps = { cur }
    for i = 1, AH().MAX + 2 do steps[#steps + 1] = obj("S" .. i, 10 + i, 1, 1, 0.5, 0.5) end
    local out = AH().Lines(steps, cur, HERE, SIZE)
    t.eq(#out.lines, AH().MAX + 1)
    t.eq(out.lines[AH().MAX], "S" .. AH().MAX)
    t.eq(out.lines[AH().MAX + 1], AH().MORE:format(2))
end

tests["also here: nil with nothing to list or nothing known"] = function(t)
    t.eq(AH().Lines({}, nil, HERE, SIZE), nil)
    t.eq(AH().Lines(nil, nil, nil, nil), nil)
    local cur = obj("Now", 1, 1, 1, 0.5, 0.5)
    t.eq(AH().Lines({ cur, obj("Near", 2, 1, 1, 0.5, 0.5) }, cur, HERE, nil), nil)
    t.eq(AH().Lines({ cur, obj("Near", 2, 1, 1, 0.5, 0.5) }, cur, { map = 1 }, SIZE), nil)
end

tests["also here: the module answers nil with no route and does not error"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    k:Module({ name = "tripRoute", provides = { Current = function() return nil end } })
    local api = AH().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    local ok, v = pcall(api.Lines)
    t.ok(ok, "no error")
    t.eq(v, nil)
    local ok2, v2 = pcall(k.use("alsoHere").Lines)
    t.ok(ok2, "no error through the kernel")
    t.eq(v2, nil)
end

return tests
