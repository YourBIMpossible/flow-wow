-- Profession nodes near you: where ore and herbs you can gather spawn around
-- you and your next step. So "mine Iron while you're in this quest's area"
-- is right there, without making it a step of its own:
--   * soft clouds on the minimap where they spawn (Mining tan, Herbalism green)
--   * a line in the Flow Tracker: "Nearby: Iron Deposit x3, Kingsblood x2"
-- Only professions you've learned, and only nodes your skill can gather;
-- "+skill" when a node still raises your skill. Spawn spots come from
-- Questie's object data (a spot where a node CAN appear, not one that's up
-- right now: the game's Find Minerals / Find Herbs shows those).
-- Setting: "Profession nodes near you" in /flow settings (on by default).

local _, ns = ...
local NB = {}
ns.nearby = NB

NB.RADIUS = 120          -- yards around you (and around your next step) for the Tracker line
NB.MINIMAP_YARDS = 15    -- cloud size around each spawn spot on the minimap
NB.COLOR = { Mining = { 0.85, 0.65, 0.35 }, Herbalism = { 0.35, 0.9, 0.4 } }
NB.ICON = { Mining = "Interface\\Icons\\Trade_Mining", Herbalism = "Interface\\Icons\\Trade_Herbalism" }

-- Nodes: the skill to gather them and Questie object IDs. An ID whose Questie
-- name doesn't match is ignored, so a wrong one does no harm.
-- Origin not established: no record says where these skill numbers (or the
-- "+100" in NB.SkillUp below) came from, and Flow never read them from the
-- game. Kept because the node filter, the zone targets and the pick names
-- have nothing else to go on; a node's own tooltip is the truth in game.
-- Extend with ns:Register("gatherNode", "<name>", { prof, skill, objects }).
local function node(name, prof, skill, objects)
    ns:Register("gatherNode", name, { prof = prof, skill = skill, objects = objects })
end
node("Copper Vein", "Mining", 1, { 1731, 2055, 3763, 103713 })
node("Tin Vein", "Mining", 65, { 1732, 2054, 3764, 103711 })
node("Incendicite Mineral Vein", "Mining", 65, { 1610 })
node("Silver Vein", "Mining", 75, { 1733, 105569 })
node("Lesser Bloodstone Deposit", "Mining", 75, { 2653 })
node("Iron Deposit", "Mining", 125, { 1735 })
node("Indurium Mineral Vein", "Mining", 150, { 19903 })
node("Gold Vein", "Mining", 155, { 1734 })
node("Mithril Deposit", "Mining", 175, { 2040 })
node("Truesilver Deposit", "Mining", 230, { 2047 })
node("Dark Iron Deposit", "Mining", 230, { 165658 })
node("Small Thorium Vein", "Mining", 245, { 324 })
node("Rich Thorium Vein", "Mining", 275, { 175404 })
node("Peacebloom", "Herbalism", 1, { 1618, 3724 })   -- (Kalimdor nodes have their own IDs)
node("Silverleaf", "Herbalism", 1, { 1617, 3725 })
node("Earthroot", "Herbalism", 15, { 1619, 3726 })
node("Mageroyal", "Herbalism", 50, { 1620, 3727 })
node("Briarthorn", "Herbalism", 70, { 1621, 3729 })
node("Stranglekelp", "Herbalism", 85, { 2045 })
node("Bruiseweed", "Herbalism", 100, { 1622, 3730 })
node("Wild Steelbloom", "Herbalism", 115, { 1623 })
node("Grave Moss", "Herbalism", 120, { 1628 })
node("Kingsblood", "Herbalism", 125, { 1624 })
node("Liferoot", "Herbalism", 150, { 2041 })
node("Fadeleaf", "Herbalism", 160, { 2042 })
node("Goldthorn", "Herbalism", 170, { 2046 })
node("Khadgar's Whisker", "Herbalism", 185, { 2043 })
node("Wintersbite", "Herbalism", 195, { 2044 })
node("Firebloom", "Herbalism", 205, { 2866 })
node("Purple Lotus", "Herbalism", 210, { 142140 })
node("Arthas' Tears", "Herbalism", 220, { 142141 })
node("Sungrass", "Herbalism", 230, { 142142 })
node("Blindweed", "Herbalism", 235, { 142143 })
node("Ghost Mushroom", "Herbalism", 245, { 142144 })
node("Gromsblood", "Herbalism", 250, { 142145 })
node("Golden Sansam", "Herbalism", 260, { 176583 })
node("Dreamfoil", "Herbalism", 270, { 176584 })
node("Mountain Silversage", "Herbalism", 280, { 176586 })
node("Plaguebloom", "Herbalism", 285, { 176587 })
node("Icecap", "Herbalism", 290, { 176588 })
node("Black Lotus", "Herbalism", 300, { 176589 })

-- A node still raises your skill until about 100 points past where it opens
-- (origin not established, as above).
function NB.SkillUp(skill, rank) return rank < skill + 100 end

function NB.Enabled() return ns.db.nav.nearbyNodes ~= false end

-- Your gathering professions: { Mining = rank, Herbalism = rank } (read at
-- most every 5 s: the minimap asks several times a second).
local ranksAt, ranks_ = -10, {}
local function myRanks()
    if GetTime() - ranksAt < 5 then return ranks_ end
    ranksAt = GetTime()
    local out = {}
    for prof in pairs(NB.COLOR) do
        local rank = ns.api.Skill and ns.api.Skill(prof)
        if rank and rank > 0 then out[prof] = rank end
    end
    ranks_ = out
    return out
end

-------------------------------------------------------------------------------
-- Spawn spots on a map (cached: they never move)
-------------------------------------------------------------------------------

local cache = { key = nil, spots = {} }
NB.version = 0

local function sameName(a, b)
    return type(a) ~= "string" or a:lower() == b:lower()
end

-- Every spot on `map` for the nodes your skills can gather:
-- { { name, prof, skill, cont, wx, wy } }.
function NB.Spots(map, ranks)
    ranks = ranks or myRanks()
    local key = tostring(map)
    for prof, rank in pairs(ranks) do key = key .. ":" .. prof .. rank end
    if cache.key == key then return cache.spots end
    local spots = {}
    if map and next(ranks) then
        for name, n in ns:Each("gatherNode") do
            local rank = ranks[n.prof]
            if rank and rank >= n.skill then
                for _, id in ipairs(n.objects) do
                    local o = ns.quests:QuestieGet("GetObject", id)
                    if o and o.spawns and sameName(o.name, name) then
                        for area, list in pairs(o.spawns) do
                            if ns.quests:UiMapForArea(area) == map then
                                for _, c in ipairs(list) do
                                    if c[1] and c[1] >= 0 and #spots < 1500 then
                                        local cont, wx, wy = ns.nav:ToWorld(map, c[1] / 100, c[2] / 100)
                                        if wx then
                                            spots[#spots + 1] = { name = name, prof = n.prof, skill = n.skill,
                                                                  cont = cont, wx = wx, wy = wy }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    cache.key, cache.spots = key, spots
    NB.version = NB.version + 1
    return spots
end

-- Spots within `radius` yards of any of the centres ({ wx, wy, cont }),
-- counted by node: { { name, prof, n, skillUp } }, most first.
function NB.Count(spots, centres, radius, ranks)
    local by, out = {}, {}
    local r2 = radius * radius
    for _, s in ipairs(spots) do
        for _, c in ipairs(centres) do
            if c.cont == s.cont and (s.wx - c.wx) ^ 2 + (s.wy - c.wy) ^ 2 <= r2 then
                local e = by[s.name]
                if not e then
                    e = { name = s.name, prof = s.prof, n = 0,
                          skillUp = NB.SkillUp(s.skill, (ranks or {})[s.prof] or 0) }
                    by[s.name] = e
                    out[#out + 1] = e
                end
                e.n = e.n + 1
                break
            end
        end
    end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    return out
end

-- "Nearby: [icon] Iron Deposit x3 +skill, [icon] Kingsblood x2" (or nil).
-- drop: a quest that starts from a drop near you ({ item, mob }), shown
-- first: one line instead of Questie's "!" at every spawn of those mobs.
local DROP_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
function NB.Line(counts, max, drop)
    if #counts == 0 and not drop then return nil end
    local parts = {}
    if drop then
        parts[#parts + 1] = string.format("|T%s:12:12|t |cffffd200quest drop:|r %s%s", DROP_ICON, drop.item,
            drop.mob and (" (" .. drop.mob .. ")") or "")
    end
    for i, e in ipairs(counts) do
        if i > (max or 3) then parts[#parts + 1] = "..." break end
        parts[#parts + 1] = string.format("|T%s:12:12|t %s x%d%s", NB.ICON[e.prof] or "", e.name, e.n,
            e.skillUp and " |cff40ff40+skill|r" or "")
    end
    return "|cffd0b070Nearby:|r " .. table.concat(parts, ", ")
end

-------------------------------------------------------------------------------
-- Now: around you and your next step (refreshed every 2 s at most)
-------------------------------------------------------------------------------

local last = { at = -10 }
function NB.Now()
    if not NB.Enabled() then return nil end
    if GetTime() - last.at < 2 then return last.line, last.counts, last.drop end
    last.at = GetTime()
    last.line, last.counts = nil, nil
    local p = ns.nav and ns.nav:PlayerPos()
    if not p then return nil end
    local ranks = myRanks()
    local spots = NB.Spots(p.map, ranks)
    local centres = { p }
    local s = ns.nav.plan and ns.nav.plan[1]
    local pt = s and s.point
    if pt and pt.wx and pt.cont == p.cont then centres[2] = pt end
    -- A quest that starts from a drop of mobs near you (QuestData.lua).
    local okD, drop = pcall(ns.quests.DropNear, ns.quests, p.map, centres, NB.RADIUS)
    last.counts = NB.Count(spots, centres, NB.RADIUS, ranks)
    last.drop = okD and drop or nil
    last.line = NB.Line(last.counts, nil, last.drop)
    return last.line, last.counts, last.drop
end

-- Spots of one profession that the minimap shows (within `yards` of you),
-- nearest 40, as goal-like point lists for the minimap clouds.
function NB.MinimapGroups(p, yards)
    if not (NB.Enabled() and p) then return {} end
    local spots = NB.Spots(p.map)
    local by = {}
    local y2 = yards * yards
    for _, s in ipairs(spots) do
        if s.cont == p.cont then
            local d = (s.wx - p.wx) ^ 2 + (s.wy - p.wy) ^ 2
            if d <= y2 then
                by[s.prof] = by[s.prof] or {}
                local list = by[s.prof]
                list[#list + 1] = { wx = s.wx, wy = s.wy, cont = s.cont, d = d }
            end
        end
    end
    local out = {}
    for prof, list in pairs(by) do
        table.sort(list, function(a, b) return a.d < b.d end)
        for i = #list, 41, -1 do list[i] = nil end
        out[#out + 1] = { prof = prof, color = NB.COLOR[prof], points = list, area = true }
    end
    return out
end

ns:On("SKILL_LINES_CHANGED", function() cache.key = nil; ranksAt = -10 end)
ns:On("ZONE_CHANGED_NEW_AREA", function() last.at = -10 end)
