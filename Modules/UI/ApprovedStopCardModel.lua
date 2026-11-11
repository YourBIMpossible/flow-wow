-- Plain view data. No route mutation or Blizzard globals are replaced here.
local _, ns = ...
local M = {}
ns.approvedStopCardModel = M

local function clean(s) return type(s) == "string" and s ~= "" and s or nil end
local function samePoint(a, b)
    if not (a and b) then return false end
    if a.map and b.map and a.map == b.map and a.x and a.y and b.x and b.y then
        return math.abs(a.x - b.x) < 0.00001 and math.abs(a.y - b.y) < 0.00001
    end
    return a.cont ~= nil and a.cont == b.cont and type(a.wx) == "number" and type(b.wx) == "number"
        and type(a.wy) == "number" and type(b.wy) == "number"
        and math.abs(a.wx - b.wx) < 0.1 and math.abs(a.wy - b.wy) < 0.1
end
M.SamePoint = samePoint

-- The name must belong to the point the planner chose, never the first NPC.
function M.Destination(goal, point, pointsFor)
    if point and clean(point.npcName or point.npc) then return point.npcName or point.npc end
    if clean(goal.destinationName) then return goal.destinationName end
    if not (point and pointsFor) then return nil end
    for _, name in ipairs(goal.npcs or {}) do
        for _, p in ipairs(pointsFor(name) or {}) do
            if samePoint(point, p) then return name end
        end
    end
end

function M.Profession(goal)
    local key = tostring(goal.key or "")
    local p = clean(goal.profession) or key:match("^train:(.+)$") or key:match("^skill:(.+)$")
    return p ~= "class" and p or nil
end

function M.Build(goal, point, options)
    options = options or {}
    local profession = M.Profession(goal)
    local trainer = profession and tostring(goal.key or ""):find("^train:") ~= nil
    local task = clean(goal.text) or clean(goal.title) or "Next stop"
    if trainer then task = clean(goal.title) or ("Train " .. profession)
    elseif goal.title and task:sub(1, #goal.title + 2) == goal.title .. ": " then
        task = task:sub(#goal.title + 3)
    end
    local destination = M.Destination(goal, point, options.pointsFor)
    local alternatives, seen = {}, {}
    if trainer and options.pointsFor then
        for _, name in ipairs(goal.npcs or {}) do
            if name ~= destination and not seen[name] and #(options.pointsFor(name) or {}) > 0 then
                alternatives[#alternatives + 1], seen[name] = name, true
            end
        end
    end
    local legacy = trainer and goal.title and (goal.title .. " at " .. table.concat(goal.npcs or {}, " or ") .. ".")
    local details = {}
    for _, line in ipairs(goal.details or {}) do
        if type(line) == "string" and line ~= "" and line ~= legacy
            and line ~= task and line ~= goal.title
            and line ~= "Optional, so the arrow only picks it when you're close by."
            and not line:find("^Quest: ") and not line:find("^Objective: ") then
            details[#details + 1] = line
        end
    end
    return {
        key = goal.key,
        category = options.category or (trainer and "Profession trainer") or "Next stop",
        title = task,
        profession = profession,
        icon = goal.icon or options.icon,
        iconAtlas = goal.iconAtlas,
        distance = options.distance,
        destination = destination or (trainer and "Trainer not selected" or nil),
        note = goal.optional and "Optional stop · Included when nearby" or nil,
        blocked = clean(goal.blockedBy),
        details = details,
        alternatives = alternatives,
        actions = options.actions or {},
        fullTitle = task,
    }
end
