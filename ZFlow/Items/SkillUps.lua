local _, ns = ...

-- SkillUps: which recipes in a profession window give a skill point, how
-- sure each point is, and how many points what the bags hold can make
-- (P-PROF, lead section 238 rows N22, N23).
--
--   chance = SkillUps.Chance(difficulty)
--   seen   = SkillUps.Observe(seen, rows, skill)
--   left   = SkillUps.SureLeft(seen, key, skill)
--   ranked = SkillUps.Rank(rows)
--   bags   = SkillUps.FromBags(ranked, opts)
--   goal   = SkillUps.Goal(skill, max, goal)
--
-- Everything here comes from what the player saw in their own profession
-- window: the colour the window gave each recipe at the skill it was read
-- at. No recipe tables, no guide data. Pure: no frame, nothing read from the
-- game. A colour never seen stays unknown; a span is only what was seen.
local SkillUps = {}

-- The window colours (relative difficulty) and how sure a point is from a
-- craft at that colour. Orange always gives one; yellow and green may; grey
-- never. "difficult" (red) can not be made, so it gives none.
local CHANCE = {
    optimal = "sure",
    medium = "maybe",
    easy = "maybe",
    trivial = "none",
    difficult = "none",
}

function SkillUps.Chance(difficulty)
    return CHANCE[difficulty] or "unknown"
end

-- Widens seen[key][difficulty] = { lo =, hi = } to take in skill, for each
-- row { key =, difficulty = } the window showed at that skill. A row with no
-- key or a colour the window never gives is left out. Returns seen.
function SkillUps.Observe(seen, rows, skill)
    if type(seen) ~= "table" or type(rows) ~= "table" or type(skill) ~= "number" then return seen end
    for _, row in ipairs(rows) do
        local key, colour = type(row) == "table" and row.key or nil, type(row) == "table" and row.difficulty or nil
        if key ~= nil and CHANCE[colour] then
            local byColour = seen[key]
            if type(byColour) ~= "table" then
                byColour = {}
                seen[key] = byColour
            end
            local span = byColour[colour]
            if type(span) ~= "table" or type(span.lo) ~= "number" or type(span.hi) ~= "number" then
                byColour[colour] = { lo = skill, hi = skill }
            else
                if skill < span.lo then span.lo = skill end
                if skill > span.hi then span.hi = skill end
            end
        end
    end
    return seen
end

-- How many points from skill up are known orange for this recipe: from
-- skill to the top of the orange span seen. nil when skill is outside what
-- was seen orange, or nothing was.
function SkillUps.SureLeft(seen, key, skill)
    if type(seen) ~= "table" or type(skill) ~= "number" then return nil end
    local byColour = seen[key]
    local span = type(byColour) == "table" and byColour.optimal or nil
    if type(span) ~= "table" or type(span.lo) ~= "number" or type(span.hi) ~= "number" then return nil end
    if skill < span.lo or skill > span.hi then return nil end
    return span.hi - skill + 1
end

local ORDER = { sure = 1, maybe = 2, unknown = 3 }

-- The recipes that may give a point, best first: sure, then maybe, then a
-- colour not read; within each the cheapest craft first (an unknown cost
-- last), then by name. Grey and red are dropped. Each row is copied with
-- its chance added; the rows given are not changed.
function SkillUps.Rank(rows)
    local out = {}
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local chance = SkillUps.Chance(row.difficulty)
        if ORDER[chance] then
            local copy = {}
            for k, v in pairs(row) do copy[k] = v end
            copy.chance = chance
            out[#out + 1] = copy
        end
    end
    table.sort(out, function(a, b)
        if ORDER[a.chance] ~= ORDER[b.chance] then return ORDER[a.chance] < ORDER[b.chance] end
        if a.cost ~= b.cost then
            if a.cost == nil then return false end
            if b.cost == nil then return true end
            return a.cost < b.cost
        end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    return out
end

-- How many crafts of one recipe the bags still make, given what is left.
local function craftable(mats, left)
    if type(mats) ~= "table" then return 0 end
    local n
    for item, per in pairs(mats) do
        if type(per) ~= "number" or per <= 0 then return 0 end
        local can = math.floor((left[item] or 0) / per)
        if n == nil or can < n then n = can end
    end
    return n or 0
end

-- What the bags make for points, in rank order, each mat used once:
--   { sure = n, maybe = n, crafts = { { key =, n =, chance = }, ... } }
-- opts: mats(row) -> { [item] = n a craft } or nil when not read;
-- have(item) -> count in the bags; skill, max: the skill now and its cap;
-- seen: the colour spans (Observe).
-- An orange craft is sure at the skill the window was read at, and after
-- that only while the skill it would reach is inside the orange span seen;
-- past that it may give a point. Points stop at the cap. A recipe whose
-- colour was not read is left out: its point is not known either way.
function SkillUps.FromBags(ranked, opts)
    local out = { sure = 0, maybe = 0, crafts = {} }
    if type(opts) ~= "table" or type(opts.skill) ~= "number" or type(opts.max) ~= "number" then return out end
    local room = opts.max - opts.skill
    local cur = opts.skill
    local left = {}
    for _, row in ipairs(type(ranked) == "table" and ranked or {}) do
        if room <= 0 then break end
        if row.chance == "sure" or row.chance == "maybe" then
            local mats = opts.mats(row)
            if type(mats) == "table" then
                for item in pairs(mats) do
                    if left[item] == nil then left[item] = tonumber(opts.have(item)) or 0 end
                end
                local n = math.min(craftable(mats, left), room)
                if n > 0 then
                    for item, per in pairs(mats) do left[item] = left[item] - per * n end
                    for _ = 1, n do
                        if row.chance == "sure"
                            and (cur == opts.skill or SkillUps.SureLeft(opts.seen, row.key, cur) ~= nil) then
                            out.sure = out.sure + 1
                            cur = cur + 1
                        else
                            out.maybe = out.maybe + 1
                        end
                    end
                    room = room - n
                    out.crafts[#out.crafts + 1] = { key = row.key, n = n, chance = row.chance }
                end
            end
        end
    end
    return out
end

-- The player goal against the skill now and its cap: { need = points still
-- to go, overCap = the goal is past what this rank can reach }. nil when the
-- goal or the skill is not known.
function SkillUps.Goal(skill, max, goal)
    if type(skill) ~= "number" or type(goal) ~= "number" then return nil end
    return { need = math.max(0, goal - skill), overCap = type(max) == "number" and goal > max or false }
end

ns.SkillUps = SkillUps
