local _, ns = ...

-- Disposition: what to do with an item, with the reason and what the answer
-- rests on.
--
--   decision = Disposition.Decide(item, context)
--   -> { action, count, reason, rule, basis, reasons, rest }
--
-- It only decides. Nothing here sells, banks, mails, deletes or equips
-- anything, and nothing reads the game: everything a rule needs arrives in
-- `item` and `context`. Whether a decision is ever acted on without the
-- player is a setting elsewhere, and each such automation is off by default.
--
-- item (plain values; a field that isn't known is nil, never 0):
--   { key, name, count = how many the player has in the bags,
--     quality, sellPrice (copper each; 0 = the game says it can't be sold),
--     classID, bound }
-- context:
--   { grants     = what Resources.Resolve returned, or nil
--     choices    = { keep = { [key] = true }, never = { [key] = true } }
--     questItems = { [key] = { quest = "title", inLog = true, level = n } }
--     tools      = { [key] = "Mining" }      a tool of a profession you have or plan
--     classKeep  = { [key] = { why = "...", untilLevel = n } }
--     level      = the player's level
--     rules      = a rule list to use instead of the built-in one
--     onError    = fn(ruleKey, err)          told once per failing rule call }
--
-- A decision:
--   action   "keep", "sell", "auction", "disenchant" or "equip"
--   count    how many of item.count it applies to; nil when item.count isn't
--            known (then it applies to all of them)
--   reason   for the player, short
--   rule     the rule that decided
--   basis    what it rests on, exactly one of:
--              "choice"          the player said so
--              "fact"            something the game states (a quest item, a
--                                claim that holds it)
--              "recommendation"  Z-Flow's judgement
--              "unknown"         nothing was known, so it is kept
--   reasons  keep only: every keep reason that applies, the deciding one first
--   rest     when the deciding rule keeps only part (a claim holds 8 of 12):
--            the decision for the others, made by the rules after it
--
-- A rule: { key, order, generic = bool, check = fn(item, context) -> verdict }
--   verdict = nil (no opinion) or { action, reason, basis, count }
--   A rule that errors fails safe: the item is kept, with that as the reason,
--   and no later rule gets to sell it.
--   generic: its "keep" is a fallback, not worth listing among the reasons.

local Disposition = {}
ns.Disposition = Disposition

local ACTIONS = { keep = true, sell = true, auction = true, disenchant = true, equip = true }
local BASES = { choice = true, fact = true, recommendation = true, unknown = true }

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

Disposition.QUEST_CLASS = 12     -- the game's item class for quest items

-- The built-in rules whose facts can all be passed in. (Gear, recipes,
-- materials by profession, ammunition, reagents and spare bags come with the
-- modules that know those facts.)
Disposition.RULES = {
    { key = "yourChoice", order = 0.5, check = function(i, c)
        local keep = type(c.choices) == "table" and c.choices.keep
        if type(keep) == "table" and keep[i.key] then
            return { action = "keep", reason = "you chose to keep it", basis = "choice" }
        end
    end },
    { key = "neverSell", order = 1, check = function(i, c)
        local never = type(c.choices) == "table" and c.choices.never
        if type(never) == "table" and never[i.key] then
            return { action = "keep", reason = "you bought it back, so it's never sold", basis = "choice" }
        end
    end },
    { key = "unsellable", order = 2, check = function(i)
        if i.sellPrice == 0 then
            return { action = "keep", reason = "can't be sold to a merchant", basis = "fact" }
        end
    end },
    { key = "professionTool", order = 3, check = function(i, c)
        local prof = type(c.tools) == "table" and c.tools[i.key]
        if prof then return { action = "keep", reason = "tool for " .. tostring(prof), basis = "fact" } end
    end },
    -- What your steps hold of it (Resources): kept by count, not all or nothing.
    { key = "held", order = 4, check = function(i, c)
        local g = c.grants
        if type(g) ~= "table" or type(g.Held) ~= "function" then return nil end
        local held = g:Held(i.key)
        if not isCount(held) or held <= 0 then return nil end
        return { action = "keep", reason = held .. " held for your steps", basis = "fact", count = held }
    end },
    { key = "quest", order = 5, check = function(i)
        if i.classID == Disposition.QUEST_CLASS then
            return { action = "keep", reason = "quest item", basis = "fact" }
        end
    end },
    { key = "questNeeds", order = 6, check = function(i, c)
        local need = type(c.questItems) == "table" and c.questItems[i.key]
        if type(need) ~= "table" then return nil end
        if need.inLog then
            return { action = "keep", reason = "for your quest: " .. tostring(need.quest or "?"), basis = "fact" }
        end
        return { action = "keep", basis = "fact",
                 reason = string.format("for an upcoming quest: %s (level %s)", tostring(need.quest or "?"),
                                        tostring(need.level or "?")) }
    end },
    { key = "classKeep", order = 7, check = function(i, c)
        local k = type(c.classKeep) == "table" and c.classKeep[i.key]
        if type(k) ~= "table" then return nil end
        -- Past the level it's wanted until: no longer kept for this. A level
        -- that isn't known doesn't end it.
        if isCount(k.untilLevel) and isCount(c.level) and c.level >= k.untilLevel then return nil end
        return { action = "keep", reason = tostring(k.why or "kept for your class"), basis = "recommendation" }
    end },
    -- Grey items with a known price. A price that isn't known decides nothing.
    { key = "junk", order = 20, check = function(i)
        if i.quality == 0 and isCount(i.sellPrice) and i.sellPrice > 0 then
            return { action = "sell", reason = "junk", basis = "recommendation" }
        end
    end },
}

local function sortedRules(list)
    local out = {}
    for idx = 1, #list do
        local r = list[idx]
        if type(r) == "table" and type(r.check) == "function" then
            out[#out + 1] = { r = r, idx = idx, order = type(r.order) == "number" and r.order or 100 }
        end
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.idx < b.idx
    end)
    return out
end

-- One rule's verdict, or nil. An error, or a verdict that isn't one, keeps
-- the item (fail safe).
local function ask(e, item, context)
    local ok, v = pcall(e.r.check, item, context)
    if not ok then
        if type(context.onError) == "function" then pcall(context.onError, e.r.key, v) end
        return { action = "keep", basis = "unknown", failed = true,
                 reason = "a Z-Flow check failed (" .. tostring(e.r.key) .. "), so it's kept" }
    end
    if v == nil then return nil end
    if type(v) ~= "table" or not ACTIONS[v.action] then
        if type(context.onError) == "function" then pcall(context.onError, e.r.key, "not a verdict") end
        return { action = "keep", basis = "unknown", failed = true,
                 reason = "a Z-Flow check gave no clear answer (" .. tostring(e.r.key) .. "), so it's kept" }
    end
    return v
end

-- Decides for `count` of the item, starting at rule `from`.
local function decide(list, from, item, context, count)
    for idx = from, #list do
        local e = list[idx]
        local v = ask(e, item, context)
        if v then
            local d = {
                action = v.action, rule = e.r.key, reason = v.reason,
                basis = BASES[v.basis] and v.basis or "unknown",
                failed = v.failed, count = count,
            }
            if v.action == "keep" then
                -- Keeping it: list every reason, not just the first.
                local reasons, seen = {}, {}
                if v.reason then reasons[1], seen[v.reason] = v.reason, true end
                if not e.r.generic and not v.failed then
                    for j = idx + 1, #list do
                        local e2 = list[j]
                        if not e2.r.generic then
                            local ok, w = pcall(e2.r.check, item, context)
                            if ok and type(w) == "table" and w.action == "keep" and w.reason and not seen[w.reason] then
                                reasons[#reasons + 1], seen[w.reason] = w.reason, true
                            end
                        end
                    end
                end
                d.reasons = reasons
                d.reason = #reasons > 0 and table.concat(reasons, "; ") or nil
                -- A keep by count: the others are decided by the rules after it.
                if isCount(v.count) and isCount(count) and v.count < count then
                    d.count = v.count
                    d.rest = decide(list, idx + 1, item, context, count - v.count)
                end
            end
            return d
        end
    end
    return { action = "keep", rule = nil, reason = "no rule matched", basis = "unknown", count = count,
             reasons = { "no rule matched" } }
end

-- What to do with `item`. Always a decision: when nothing is known, or the
-- item isn't a table, the answer is keep.
function Disposition.Decide(item, context)
    context = type(context) == "table" and context or {}
    if type(item) ~= "table" then
        return { action = "keep", rule = nil, reason = "not an item Z-Flow can read", basis = "unknown",
                 reasons = { "not an item Z-Flow can read" } }
    end
    local list = sortedRules(type(context.rules) == "table" and context.rules or Disposition.RULES)
    return decide(list, 1, item, context, isCount(item.count) and item.count or nil)
end

-- How many of the item a decision (with its `rest`) puts under `action`.
-- nil when the count isn't known.
function Disposition.CountOf(decision, action)
    local n, d = 0, decision
    while type(d) == "table" do
        if d.action == action then
            if d.count == nil then return nil end
            n = n + d.count
        end
        d = d.rest
    end
    return n
end
