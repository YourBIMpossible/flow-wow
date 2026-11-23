local _, ns = ...

-- Skill boosters: books and other "+N skill" items (lead section 337 item
-- 2, P-INV G6; ported from Flow F-086, Modules/Items/SkillBoosters.lua).
-- Show and advise only: nothing is used, sold, moved or clicked here.
--
--   b      = SkillBoosters.Find(id, lines[, get])  { skill, amount, cap } or nil
--   b      = SkillBoosters.Parse(lines)            from English tooltip text
--   text   = SkillBoosters.Advice(b, rank, max)    when to use it
--   facts  = SkillBoosters.Facts(client, bag)      { [key] = { skill, amount,
--            cap, rank, max } } for Disposition's skillBooster rule, or nil
--
-- Found by item ID first (SkillBoosters.KNOWN, entries with where and when
-- they were read; none is recorded yet), else from the tooltip text on an
-- English client, e.g. "Use: Increases your Mining skill by 2, up to a
-- maximum of 15." An item neither registered nor readable is unknown: no
-- advice, not kept for this.
--
-- The skill read is client.skillRanks() (first guess, not seen in game);
-- the tooltip text is client.itemLines(). The tooltip line is added through
-- client.onItemTooltip.
local SB = {}
ns.SkillBoosters = SB

SB.NAME = "skillBoosters"
SB.COLOUR = { 1, 0.82, 0.25 } -- legacy Flow's line colour

SB.SKILLS = {
    "Mining", "Herbalism", "Skinning", "Blacksmithing", "Engineering", "Alchemy",
    "Leatherworking", "Tailoring", "Enchanting", "Jewelcrafting", "Inscription",
    "First Aid", "Cooking", "Fishing", "Lockpicking",
}

-- [item ID] = { skill, amount, cap, source, seen }: only items read on a
-- real client, each with where and when. Empty until one is read.
SB.KNOWN = {}

function SB.Known(id, get)
    local e = (get or function(k) return SB.KNOWN[k] end)(id)
    if type(e) == "table" and type(e.skill) == "string" and type(e.amount) == "number" and e.amount > 0
        and e.source and e.seen then
        return e
    end
    return nil
end

-- lines: { "text", ... } or { { left = "text" }, ... }.
function SB.Parse(lines)
    if type(lines) ~= "table" then return nil end
    for _, l in ipairs(lines) do
        local text = type(l) == "table" and l.left or l
        if type(text) == "string" then
            for _, s in ipairs(SB.SKILLS) do
                if text:find(s, 1, true) then
                    local amount = tonumber(text:match(s .. " skill by (%d+)"))
                        or tonumber(text:match("%+(%d+)%s+" .. s))
                    if amount then
                        local cap = tonumber(text:match("maximum of (%d+)")) or tonumber(text:match("up to (%d+)"))
                        return { skill = s, amount = amount, cap = cap }
                    end
                end
            end
        end
    end
    return nil
end

function SB.Find(id, lines, get)
    local known = SB.Known(id, get)
    if known then return known end
    return SB.Parse(lines)
end

-- "learn", "hold", "use", "late" or "capped"; the best rank to use it at.
function SB.Verdict(b, rank, max)
    if type(rank) ~= "number" then return "learn", nil end
    local cap = b.cap or max
    if type(cap) ~= "number" then return "hold", nil end
    local best = math.max(0, cap - b.amount)
    if rank >= cap then return "capped", best end
    if rank == best then return "use", best end
    if rank > best then return "late", best end
    return "hold", best
end

function SB.Advice(b, rank, max)
    local v, best = SB.Verdict(b, rank, max)
    if v == "learn" then return "Keep it: learn " .. b.skill .. " first" end
    if v == "use" then
        return string.format("Use it now: %s is %d, the best moment for +%d", b.skill, rank, b.amount)
    end
    if v == "late" then return string.format("Use it now: %s is %d; waiting wastes more of it", b.skill, rank) end
    if v == "capped" then return string.format("It does nothing now: %s %d is at its cap", b.skill, rank) end
    if best == nil then return "Keep it: " .. b.skill .. " can still rise" end
    return string.format("Keep it until %s is %d (now %d): the last points are the slow ones", b.skill, best, rank)
end

-- True while the skill can still rise from it (not learned counts).
function SB.CanRise(b, rank, max)
    return SB.Verdict(b, rank, max) ~= "capped"
end

local function ranks(client)
    if type(client) ~= "table" or type(client.skillRanks) ~= "function" then return nil end
    local ok, got = pcall(client.skillRanks)
    if ok and type(got) == "table" then return got end
    return nil
end

local function boosterOf(client, item)
    local id = ns.Items.Id(item)
    if id == nil then return nil end
    local lines = nil
    if type(client.itemLines) == "function" then
        local ok, got = pcall(client.itemLines, id)
        if ok then lines = got end
    end
    return SB.Find(id, lines)
end

-- The facts for the sell rules. bag: entries with .key. Skills not read:
-- nil (nothing is kept on a guess about the skill).
function SB.Facts(client, bag)
    local r = ranks(client)
    if r == nil or type(bag) ~= "table" then return nil end
    local out, any = {}, false
    for _, e in ipairs(bag) do
        if type(e) == "table" and e.key ~= nil and out[e.key] == nil then
            local b = boosterOf(client, e.key)
            if b then
                local s = type(r[b.skill]) == "table" and r[b.skill] or {}
                out[e.key] = { skill = b.skill, amount = b.amount, cap = b.cap, rank = s.rank, max = s.max }
                any = true
            end
        end
    end
    return any and out or nil
end

function SB.Declare(k)
    local api = {}
    local cancel = nil
    k:Module({
        name = SB.NAME,
        needs = { "client" },
        start = function(c)
            if type(c.client.onItemTooltip) ~= "function" then return end
            local got = c.client.onItemTooltip(function(link, add)
                if type(add) ~= "function" then return end
                local b = boosterOf(c.client, link)
                if not b then return end
                local s = (ranks(c.client) or {})[b.skill]
                s = type(s) == "table" and s or {}
                add(ns.id.title .. ": " .. SB.Advice(b, s.rank, s.max), SB.COLOUR[1], SB.COLOUR[2], SB.COLOUR[3])
            end)
            if type(got) == "function" then cancel = got end
        end,
        stop = function()
            if cancel then cancel() end
            cancel = nil
        end,
    })
    return api
end

ns.skillBoosters = SB.Declare(ns)
