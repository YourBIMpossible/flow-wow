local _, ns = ...

-- Tests for ZFlow/Nav/DungeonFirst.lua (FLOW-PARITY A1-31): with a
-- dungeon run prepared its pick-ups and entrance come first; inside a
-- dungeon only its quests are routed. Pure. Made-up quests and dungeons.

local tests = {}

local function DF() return ns.Nav.DungeonFirst end

local function stop(label, more)
    local s = { label = label, place = { map = 1, x = 0.5, y = 0.5 } }
    for k, v in pairs(more or {}) do s[k] = v end
    return s
end

local ROUTE = {
    stop("Boars", { quest = 1, objective = 1 }),
    stop("Pick up: Red Silk", { kind = "pickup", quest = 101 }),
    stop("Bags full", { kind = "sell" }),
    stop("Herbs", { quest = 2, objective = 1 }),
}

local RUN = {
    stop("Pick up: Red Silk", { kind = "giver", quest = 101 }),
    stop("Pick up: Oil", { kind = "giver", quest = 102 }),
    stop("Get ready: repair", { kind = "ready" }),
    stop("The Mines", { kind = "entrance" }),
}

local function labels(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = s.label end
    return out
end

tests["dungeon first: the prepared run's pick-ups, then its entrance, before the rest"] = function(t)
    local out = DF().First(ROUTE, RUN)
    t.eq(labels(out), { "Pick up: Red Silk", "Pick up: Oil", "The Mines", "Boars", "Bags full", "Herbs" },
        "the route's own pick-up of the same quest is not said twice; get-ready steps are not the run's")
end

tests["dungeon first: no run prepared, the route as it was"] = function(t)
    t.eq(labels(DF().First(ROUTE, nil)), labels(ROUTE))
    t.eq(labels(DF().First(ROUTE, {})), labels(ROUTE))
end

tests["dungeon first: inside a dungeon only its quests"] = function(t)
    local dungeonOf = function(id) return ({ [101] = 7, [2] = 7 })[id] end
    local out, why = DF().Inside(ROUTE, dungeonOf, 7)
    t.eq(labels(out), { "Pick up: Red Silk", "Herbs" })
    t.eq(why, nil)
end

tests["dungeon first: inside a dungeon none of your quests belong to, the whole route, with why"] = function(t)
    local out, why = DF().Inside(ROUTE, function() return nil end, 7)
    t.eq(labels(out), labels(ROUTE))
    t.eq(why, DF().NONE_HERE)
end

tests["dungeon first: outside a dungeon, nothing is cut"] = function(t)
    local out, why = DF().Inside(ROUTE, function() return 7 end, nil)
    t.eq(labels(out), labels(ROUTE))
    t.eq(why, nil)
end

-- Section 708 (Twin's CHANGES-1).
tests["dungeon first: a step or tour the player picked keeps the route as it is"] = function(t)
    t.eq(labels(DF().First(ROUTE, RUN, { picked = true })), labels(ROUTE), "Flow Nav.lua:3398")
end

tests["dungeon first: the run's optional steps are not put first"] = function(t)
    local run = {
        stop("Pick up: Red Silk", { kind = "giver", quest = 101 }),
        stop("Pick up: Maybe", { kind = "giver", quest = 103, optional = true }),
        stop("The Mines", { kind = "entrance" }),
    }
    t.eq(labels(DF().First({}, run)), { "Pick up: Red Silk", "The Mines" }, "Flow Nav.lua:3400")
end

tests["dungeon first: inside, with the dungeon's quests not read yet, the route stays and says so"] = function(t)
    local out, why = DF().Inside(ROUTE, function() return nil end, 7, false)
    t.eq(labels(out), labels(ROUTE))
    t.eq(why, DF().NOT_READ)
    local _, whyNone = DF().Inside(ROUTE, function() return nil end, 7, true)
    t.eq(whyNone, DF().NONE_HERE, "read, and none of yours: the other reason")
end

return tests
