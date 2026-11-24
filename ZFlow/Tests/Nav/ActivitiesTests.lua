local _, ns = ...
-- S38 activities and route lanes (Nav/Activities.lua): each trip stop's
-- lane, and the one summary line. A stop with no known lane says nothing.
local A = ns.Nav.Activities

local T = {}

local function stop(kind, label, map)
    return { kind = kind, label = label, place = { map = map or 1, x = 0.5, y = 0.5 } }
end

T["activities: each trip kind has its lane"] = function(t)
    t.eq(A.LaneOf(stop("giver")), "quest")
    t.eq(A.LaneOf(stop("trainer")), "trainer")
    t.eq(A.LaneOf(stop("vendor")), "service")
    t.eq(A.LaneOf(stop("repair")), "service")
    t.eq(A.LaneOf(stop("dungeon")), "dungeon")
end

T["activities: unknown or odd stops have no lane"] = function(t)
    t.eq(A.LaneOf(stop("here")), nil)
    t.eq(A.LaneOf(stop("flight")), nil)
    t.eq(A.LaneOf(nil), nil)
    t.eq(A.LaneOf({ kind = 7 }), nil)
end

T["activities: groups keep the lane order and the stop numbers"] = function(t)
    local groups = A.Group({ stop("vendor"), stop("giver"), stop("here"), stop("giver") })
    t.eq(#groups, 2)
    t.eq(groups[1].lane, "quest")
    t.eq(groups[1].label, A.LABELS.quest)
    t.eq(#groups[1].stops, 2)
    t.eq(groups[1].stops[1], 2)
    t.eq(groups[1].stops[2], 4)
    t.eq(groups[2].lane, "service")
end

T["activities: gathering counts only own professions on the trip's maps"] = function(t)
    local nodes = {
        [1] = { { prof = "Herbalism" }, { prof = "Herbalism" }, { prof = "Mining" }, { name = "old" } },
        [2] = { { prof = "Herbalism" } },
    }
    local g = A.Gather(nodes, { [1] = true }, { Herbalism = true })
    t.eq(#g, 1)
    t.eq(g[1].prof, "Herbalism")
    t.eq(g[1].n, 2)
    t.eq(#A.Gather(nil, { [1] = true }, { Herbalism = true }), 0)
    t.eq(#A.Gather(nodes, { [1] = true }, nil), 0)
end

T["activities: the summary line names each lane"] = function(t)
    local groups = A.Group({ stop("giver"), stop("giver"), stop("giver"), stop("repair") })
    local line = A.Summary(groups, { { prof = "Herbalism", n = 4 } })
    t.eq(line, "Questing: 3 stops" .. A.SEP .. "Gathering: 4 Herbalism nodes on the way"
        .. A.SEP .. "Repair and vendor: 1 stop")
end

T["activities: nothing known, no summary"] = function(t)
    t.eq(A.Summary(A.Group({ stop("here") }), {}), nil)
    t.eq(A.Summary(A.Group(nil), nil), nil)
end

T["activities: lines tag each stop with its lane, unknown untagged"] = function(t)
    local lines = A.Lines({ stop("giver", "Hand in: Wolves"), stop("here", "Camp") }, {})
    t.eq(lines[1], "Questing: 1 stop")
    t.eq(lines[2], "1. Hand in: Wolves - Questing")
    t.eq(lines[3], "2. Camp")
end

T["activities: an empty trip says so"] = function(t)
    local lines = A.Lines({}, {})
    t.eq(#lines, 1)
    t.eq(lines[1], A.EMPTY)
end

return T
