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
--   text   = SkillBoosters.Card(name, b, rank, max) the advisor prompt's line
--   cards  = SkillBoosters.Cards(client[, find])   { { id, text }, ... } for
--            the skill books in the bags, or nil when skills or bags are
--            not read
--
-- Found by item ID first (SkillBoosters.KNOWN, entries with where and when
-- they were read; none is recorded yet), else from the tooltip text on an
-- English client, e.g. "Use: Increases your Mining skill by 2, up to a
-- maximum of 15." An item neither registered nor readable is unknown: no
-- advice, not kept for this. An item in the list is found by its ID alone:
-- its tooltip text is not read.
--
-- The skill read is client.skillRanks() (first guess, not seen in game);
-- the tooltip text is client.itemLines(). The tooltip line is added through
-- client.onItemTooltip.
--
-- The advisor prompt (E-48; UI/Advisor.lua: Add(id, text, priority),
-- Remove(id)): one line for each skill book in the bags, the item's name
-- and then the tooltip's own words (SkillBoosters.Advice), e.g.
-- "Angler's Notes: Use it now: Fishing is 70, the best moment for +5".
-- WORDS ONLY: the advisor's prompt has nothing to press, and nothing here
-- uses the item. Skills, bags or the item's name not read: no line.
-- Looked at again when the bags change and every SkillBoosters.EVERY
-- seconds out of combat (the skill may have risen). No setting of its own:
-- the advisor panel's setting turns the panel off.
-- Reads (existing): bagItems, itemInfo, itemLines, skillRanks.
-- Not tested in game.
local SB = {}
ns.SkillBoosters = SB

SB.NAME = "skillBoosters"
SB.COLOUR = { 1, 0.82, 0.25 } -- legacy Flow's line colour
-- The advisor prompt of one skill book is SB.PROMPT .. its item ID.
SB.PROMPT = "items.skillBook."
SB.PRIORITY = 2
SB.MAX_CARDS = 3
SB.EVERY = 5

SB.SKILLS = {
    "Mining", "Herbalism", "Skinning", "Blacksmithing", "Engineering", "Alchemy",
    "Leatherworking", "Tailoring", "Enchanting", "Jewelcrafting", "Inscription",
    "First Aid", "Cooking", "Fishing", "Lockpicking",
}

-- [item ID] = { skill, amount, cap, source, seen }: only items read on a
-- real client, each with where and when. Empty until one is read.
-- E-47: legacy Flow has no list to bring over. Its module (flow-wow a529eea
-- Modules/Items/SkillBoosters.lua:27-33) registers no item and says "None
-- is recorded yet"; no other Flow file registers a "skillBooster". So no
-- row is guessed here: a row is added when a book is read in game.
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

-- The booster an item is, or nil; and whether that answer is settled (the
-- item is in the list, or its tooltip text was read). An item in the list
-- is found by its ID alone: its text is not asked for.
local function boosterOf(client, item)
    local id = ns.Items.Id(item)
    if id == nil then return nil, true end
    local known = SB.Known(id)
    if known then return known, true end
    local lines = nil
    if type(client.itemLines) == "function" then
        local ok, got = pcall(client.itemLines, id)
        if ok then lines = got end
    end
    return SB.Parse(lines), type(lines) == "table"
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
    if not any then return nil end
    return out
end

-- An item's name: the client's, else the one inside its link, else nil.
local function nameOf(client, item)
    if type(client.itemInfo) == "function" then
        local ok, facts = pcall(client.itemInfo, item)
        if ok and type(facts) == "table" and type(facts.name) == "string" and facts.name ~= "" then
            return facts.name
        end
    end
    if type(item) == "string" then
        local name = item:match("|h%[(.-)%]|h")
        if name and name ~= "" then return name end
    end
    return nil
end

-- The advisor prompt's line: the item's name, then the tooltip's words.
function SB.Card(name, b, rank, max)
    return name .. ": " .. SB.Advice(b, rank, max)
end

-- The prompts for the skill books in the bags, in bag order, one for each
-- item, at most SB.MAX_CARDS: { { id, text }, ... }. nil when the skills or
-- the bags are not read (no advice on a guess). find(client, item) stands
-- in for the item lookup (the module's keeps what it has read).
function SB.Cards(client, find)
    local r = ranks(client)
    if r == nil or type(client.bagItems) ~= "function" then return nil end
    local ok, stacks = pcall(client.bagItems)
    if not ok or type(stacks) ~= "table" then return nil end
    find = find or boosterOf
    local out, seen = {}, {}
    for _, stack in ipairs(stacks) do
        local item = nil
        if type(stack) == "table" then item = stack.item end
        local id = ns.Items.Id(item)
        if id ~= nil and not seen[id] and #out < SB.MAX_CARDS then
            seen[id] = true
            local b = find(client, item)
            local name = nil
            if b then name = nameOf(client, item) end
            if b and name then
                local s = type(r[b.skill]) == "table" and r[b.skill] or {}
                out[#out + 1] = { id = SB.PROMPT .. tostring(id), text = SB.Card(name, b, s.rank, s.max) }
            end
        end
    end
    return out
end

function SB.Declare(k)
    local api = {}
    local cancel = nil
    local refresh, clear
    k:Module({
        name = SB.NAME,
        needs = { "client", "bus", "advisor" },
        ticks = { { every = SB.EVERY, when = "outOfCombat", run = function() if refresh then refresh() end end } },
        start = function(c)
            local client = c.client
            if type(client.onItemTooltip) == "function" then
                local got = client.onItemTooltip(function(link, add)
                    if type(add) ~= "function" then return end
                    local b = boosterOf(client, link)
                    if not b then return end
                    -- Skills not read: say nothing (never "learn first" to a
                    -- player who may have the skill), as SB.Facts does.
                    local all = ranks(client)
                    if not all then return end
                    local s = all[b.skill]
                    s = type(s) == "table" and s or {}
                    add(ns.id.title .. ": " .. SB.Advice(b, s.rank, s.max), SB.COLOUR[1], SB.COLOUR[2], SB.COLOUR[3])
                end)
                if type(got) == "function" then cancel = got end
            end

            -- E-48: the advisor prompts. Words only; the advisor's Add takes
            -- an id, a text and a priority, nothing that acts.
            local advisor = c.use("advisor")
            if type(advisor) ~= "table" or type(advisor.Add) ~= "function"
                or type(advisor.Remove) ~= "function" then return end
            local shown = {}   -- prompt id -> the text now in the advisor
            local read = {}    -- item ID -> its booster, or false: no booster
            -- Keeps a settled answer, so a bag change does not read every
            -- item's tooltip text again. An item not yet read is asked again.
            local function find(cl, item)
                local id = ns.Items.Id(item)
                if id ~= nil and read[id] ~= nil then return read[id] or nil end
                local b, settled = boosterOf(cl, item)
                if id ~= nil and settled then read[id] = b or false end
                return b
            end
            clear = function()
                for id in pairs(shown) do
                    advisor.Remove(id)
                    shown[id] = nil
                end
            end
            refresh = function()
                local now = {}
                for _, card in ipairs(SB.Cards(client, find) or {}) do
                    now[card.id] = true
                    if shown[card.id] ~= card.text and advisor.Add(card.id, card.text, SB.PRIORITY) then
                        shown[card.id] = card.text
                    end
                end
                for id in pairs(shown) do
                    if not now[id] then
                        advisor.Remove(id)
                        shown[id] = nil
                    end
                end
            end
            c.bus:on(SB.NAME, "BAG_UPDATE", refresh)
            refresh()
        end,
        stop = function()
            if cancel then cancel() end
            cancel = nil
            if clear then clear() end
            refresh, clear = nil, nil
        end,
    })
    return api
end

ns.skillBoosters = SB.Declare(ns)
