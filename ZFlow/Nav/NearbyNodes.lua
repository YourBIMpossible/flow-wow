local _, ns = ...

-- Parity rows E-64 and E-63, the data halves (lead section 784): gathering
-- nodes near you, as Flow's Modules/Crafting/Nearby.lua:
--   NB.Count / NB.Line (:140-180)  a tracker line of the nodes within RADIUS
--                                  yards of you and of your next step
--   NB.MinimapGroups (:209)        clouds on the minimap where they are,
--                                  per profession
-- Spots come only from the player's own GatherMate2 read (Nav/AddonSources
-- Nodes(), client.gatherMateNodes: { kind, x, y, node } on your map); none
-- of Flow's node table is copied (owner section 611), so Flow's "+skill"
-- mark (it needs a skill per node) is not here. Only the professions you
-- have: GatherMate2's "Mining" is Mining, "Herb Gathering" Herbalism;
-- fishing and treasure are left out. Our own words (section 757).
--   NN.Count(nodes, centres, radius, size, profs) -> { { name, prof, count } }
--     centres: places { x, y } on the same map (you, your next step);
--     size: the map in yards { w, h } (nil: nothing, distances unknown);
--     profs: { Mining = true, Herbalism = true } as you have them
--   NN.Line(counts[, max]) -> "Gather near you: ..." | nil
--   NN.Groups(nodes, here, cloud, near, size, profs) -> { { prof, x, y, count } }
--     spots within `near` yards of you, grouped when within `cloud` yards
-- Pure: no client read, nothing drawn. The tracker line and the minimap
-- clouds are the drawing lane's (two MUSE NEEDs). Not tested in game.
ns.Nav = ns.Nav or {}
local NN = {}
ns.Nav.NearbyNodes = NN

NN.RADIUS = 120      -- yards, as Flow's NB.RADIUS
NN.CLOUD = 15        -- yards, as Flow's NB.MINIMAP_YARDS
NN.MAX = 3           -- nodes named in the line
NN.PROF = { Mining = "Mining", ["Herb Gathering"] = "Herbalism" }
NN.LINE = "Gather near you: %s"
NN.MORE = ", and %d more"

local function number(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function sized(size)
    return type(size) == "table" and number(size.w) and number(size.h) and size.w > 0 and size.h > 0
end

local function yards(a, b, size)
    local dx, dy = (a.x - b.x) * size.w, (a.y - b.y) * size.h
    return math.sqrt(dx * dx + dy * dy)
end

-- The node's profession when you have it, and the node is placed.
local function usable(nd, profs)
    if type(nd) ~= "table" or not number(nd.x) or not number(nd.y) then return nil end
    local prof = NN.PROF[nd.kind]
    if not prof or type(profs) ~= "table" or profs[prof] ~= true then return nil end
    if type(nd.node) ~= "string" or nd.node == "" then return nil end
    return prof
end

function NN.Count(nodes, centres, radius, size, profs)
    local out = {}
    if type(nodes) ~= "table" or type(centres) ~= "table" or not sized(size) then return out end
    radius = tonumber(radius) or NN.RADIUS
    local by = {}
    for _, nd in ipairs(nodes) do
        local prof = usable(nd, profs)
        if prof then
            local near = false
            for _, c in ipairs(centres) do
                if type(c) == "table" and number(c.x) and number(c.y) and yards(nd, c, size) <= radius then
                    near = true
                    break
                end
            end
            if near then
                local e = by[nd.node]
                if not e then
                    e = { name = nd.node, prof = prof, count = 0 }
                    by[nd.node] = e
                    out[#out + 1] = e
                end
                e.count = e.count + 1
            end
        end
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return out
end

function NN.Line(counts, max)
    if type(counts) ~= "table" or #counts == 0 then return nil end
    max = tonumber(max) or NN.MAX
    local parts = {}
    for i = 1, math.min(#counts, max) do
        parts[i] = tostring(counts[i].name) .. " x" .. tostring(counts[i].count)
    end
    local text = table.concat(parts, ", ")
    if #counts > max then text = text .. NN.MORE:format(#counts - max) end
    return NN.LINE:format(text)
end

function NN.Groups(nodes, here, cloud, near, size, profs)
    local out = {}
    if type(nodes) ~= "table" or type(here) ~= "table" or not number(here.x) or not number(here.y)
        or not sized(size) then
        return out
    end
    cloud = tonumber(cloud) or NN.CLOUD
    near = tonumber(near) or NN.RADIUS
    for _, nd in ipairs(nodes) do
        local prof = usable(nd, profs)
        if prof and yards(nd, here, size) <= near then
            local into = nil
            for _, g in ipairs(out) do
                if g.prof == prof and yards(nd, g, size) <= cloud then
                    into = g
                    break
                end
            end
            if into then
                into.x = (into.x * into.count + nd.x) / (into.count + 1)
                into.y = (into.y * into.count + nd.y) / (into.count + 1)
                into.count = into.count + 1
            else
                out[#out + 1] = { prof = prof, x = nd.x, y = nd.y, count = 1 }
            end
        end
    end
    return out
end
