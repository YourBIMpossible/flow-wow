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
--     boosters   = { [key] = { skill, amount, cap, rank, max } }  skill
--                  boosters (Items/SkillBoosters.lua, P-INV G6)
--     level      = the player's level
--     the keep rules ported from Flow (L6-B) read, each only when given:
--     sets       = { [key] = { "Feral", ... } }     sets you keep it in
--     materials  = { [key] = { { prof, what }, ... } }  professions that use it
--     everMaterials = { [key] = "Tailoring" }  a material of a profession
--                  you ever had: never sold
--     bagSize    = { [key] = slots }; wornBags = { slots, ... } (0: empty slot)
--     recipes    = { [key] = { prof, rank, need, known } }
--     gearRead   = true once gear is read; gear = { [key] = { canUse,
--                  needsTraining, skill, diffs = { [role] = n } } }
--     role       = your levelling role; keptRoles = { [role] = true };
--                  roleNames = { [role] = "Balance" }
--     classScored = false when your class has no stat weights
--     rules      = a rule list to use instead of the built-in one
--     onError    = fn(ruleKey, err)          told once per failing rule call;
--                                            err is "not a verdict" when a
--                                            check gave something that isn't one }
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

-- A fact the context gives for one item: context[field][key], or nil.
local function factOf(c, field, key)
    local t = type(c) == "table" and c[field] or nil
    if type(t) ~= "table" or key == nil then return nil end
    return t[key]
end

local function isList(v)
    return type(v) == "table"
end

-- How much better gear is for a role (gear.diffs[role]); nil when not known.
local function diffFor(g, role)
    if role == nil or type(g.diffs) ~= "table" then return nil end
    local d = g.diffs[role]
    if type(d) ~= "number" or d ~= d or d == math.huge or d == -math.huge then return nil end
    return d
end

Disposition.QUEST_CLASS = 12     -- the game's item class for quest items
-- G4: the reason laterOrOtherRole gives an upgrade whose level you have
-- reached (Items/BagMarks.lua marks it as an upgrade).
Disposition.UPGRADE_NOW = "an upgrade you can wear now"
-- Lead section 418 item 4 (b): a kept material held past the steps' need.
Disposition.SPARE = " (spare %d: sell at the auction house)"

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
            -- The list is filled by hand too (<slash> keep), so the reason
            -- claims no buyback.
            return { action = "keep", reason = "on your never-sell list", basis = "choice" }
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
    -- P-INV G6 (lead section 337 item 2): a skill booster is kept while its
    -- skill can still rise from it; at the cap it may be sold.
    { key = "skillBooster", order = 8, check = function(i, c)
        local b = factOf(c, "boosters", i.key)
        if type(b) ~= "table" or type(b.skill) ~= "string" or type(b.amount) ~= "number" then return nil end
        local SB = ns.SkillBoosters
        if type(SB) ~= "table" or not SB.CanRise(b, b.rank, b.max) then return nil end
        return { action = "keep", reason = "skill booster for " .. b.skill .. ": " .. SB.Advice(b, b.rank, b.max),
                 basis = "recommendation" }
    end },
    -- The eight keep rules ported from Flow (L6-B, G5), at Flow's order: this
    -- one before junk, the other seven after it. Only their keep: where
    -- Flow's rule also sells or sends to the auction house, that half is not
    -- ported. Each takes its facts from the context (below each rule); a fact
    -- that is missing or the wrong shape decides nothing. The list stays in
    -- rising order.

    -- Flow Modules/Items/Disposition.lua:637-648. context.sets[key] = the
    -- names of the sets you keep it in ({ "Feral", "Balance" }).
    { key = "inSet", order = 15, check = function(i, c)
        local names = factOf(c, "sets", i.key)
        if not isList(names) then return nil end
        local out = {}
        for idx = 1, #names do
            if type(names[idx]) == "string" and names[idx] ~= "" then out[#out + 1] = names[idx] end
        end
        if #out == 0 then return nil end
        return { action = "keep", reason = "in your " .. table.concat(out, " / ") .. " set", basis = "fact" }
    end },
    -- Grey items with a known price. A price that isn't known decides nothing.
    -- A material of any profession you have, or ever had, is never sold:
    -- it goes to the auction house (owner 11-20, DISPATCH 382).
    -- everMaterials = { [key] = "Tailoring" } covers professions past it.
    { key = "junk", order = 20, check = function(i, c)
        if factOf(c, "materials", i.key) ~= nil or factOf(c, "everMaterials", i.key) ~= nil then
            return nil
        end
        if i.quality == 0 and isCount(i.sellPrice) and i.sellPrice > 0 then
            return { action = "sell", reason = "junk", basis = "recommendation" }
        end
    end },
    -- Flow Modules/Items/Disposition.lua:431-469. context.materials[key] =
    -- the professions you have or plan that still use it (not past it), in
    -- order: { { prof = "First Aid", what = "Linen Bandage" or nil }, ... }.
    { key = "professionMaterial", order = 25, check = function(i, c)
        local uses = factOf(c, "materials", i.key)
        if not isList(uses) then return nil end
        local parts = {}
        for idx = 1, #uses do
            local u = uses[idx]
            if type(u) == "table" and type(u.prof) == "string" and u.prof ~= "" then
                local what = type(u.what) == "string" and u.what ~= "" and (": " .. u.what) or ""
                parts[#parts + 1] = "for " .. u.prof .. what
            end
        end
        if #parts == 0 then return nil end
        -- Lead section 418 item 4 (b): held past what the steps need (each
        -- use's need known), the spare goes to the auction house. Words only.
        local need = 0
        for idx = 1, #uses do
            local u = uses[idx]
            if type(u) ~= "table" or not isCount(u.need) then need = nil break end
            need = need + u.need
        end
        local spare = ""
        if need ~= nil and isCount(i.count) and i.count > need then
            spare = string.format(Disposition.SPARE, i.count - need)
        end
        return { action = "keep", reason = table.concat(parts, "; ") .. spare, basis = "fact" }
    end },
    -- Flow Modules/Items/Disposition.lua:807-841, the keep half. A bag (class
    -- 1) bigger than one you wear, or with a bag slot empty. context.bagSize[key]
    -- = its slots; context.wornBags = the worn bags' slots, 0 for an empty slot.
    { key = "spareBag", order = 28, check = function(i, c)
        if i.classID ~= 1 then return nil end
        local size, worn = factOf(c, "bagSize", i.key), type(c.wornBags) == "table" and c.wornBags or nil
        if not isCount(size) or size <= 0 or not isList(worn) or #worn == 0 then return nil end
        for idx = 1, #worn do
            if not isCount(worn[idx]) then return nil end
        end
        for idx = 1, #worn do
            if worn[idx] < size then
                return { action = "keep", basis = "fact",
                         reason = string.format("a %d-slot bag, bigger than one you wear (or a bag slot is empty): put it on", size) }
            end
        end
        return nil
    end },
    -- Flow Modules/Items/Disposition.lua:762-805, the keep branches. A recipe
    -- (class 9). context.recipes[key] = { prof, rank = your skill (nil: you
    -- don't have it), need = the skill it asks (nil: not read), known = the
    -- game says you know it }.
    { key = "recipe", order = 29.5, check = function(i, c)
        if i.classID ~= 9 then return nil end
        local r = factOf(c, "recipes", i.key)
        if type(r) ~= "table" or type(r.prof) ~= "string" or r.prof == "" then return nil end
        local prof, rank, need = r.prof, isCount(r.rank) and r.rank or nil, isCount(r.need) and r.need or nil
        local why
        if rank == nil then
            why = string.format("a %s recipe, and you don't have %s", prof, prof)
        elseif r.known == true then
            why = string.format("a %s recipe you already know", prof)
        elseif need and rank > 0 and rank < need then
            return { action = "keep", basis = "fact",
                     reason = string.format("a %s recipe: learn it at %s %d (you have %d)", prof, prof, need, rank) }
        else
            return { action = "keep", basis = "fact", reason = string.format("a %s recipe you can learn: right-click it", prof) }
        end
        -- No use to you: Flow sells it or sends it to the auction house (not
        -- ported), except one that is bound and that vendors won't take.
        if i.bound == true and isCount(i.sellPrice) and i.sellPrice <= 0 then
            return { action = "keep", basis = "fact", reason = why .. ", and vendors won't take it" }
        end
        return nil
    end },
    -- Flow Modules/Items/Disposition.lua:843-847. Not gear: kept. Only once the
    -- gear read has run (context.gearRead = true, context.gear a table of the
    -- gear facts by key): an item it did not list is not gear. A fallback.
    { key = "notGear", order = 30, generic = true, check = function(i, c)
        if c.gearRead ~= true or type(c.gear) ~= "table" then return nil end
        if c.gear[i.key] ~= nil then return nil end
        return { action = "keep", reason = "not gear (materials, food, potions...)", basis = "fact" }
    end },
    -- Flow Modules/Items/Disposition.lua:849-858. context.gear[key] =
    -- { needsTraining, skill, diffs = { [role] = n } }; context.role = your
    -- levelling role.
    { key = "needsTraining", order = 35, check = function(i, c)
        local g = factOf(c, "gear", i.key)
        if type(g) ~= "table" or g.needsTraining ~= true then return nil end
        local diff = diffFor(g, c.role)
        if diff == nil or diff < 0.5 then return nil end
        local skill = type(g.skill) == "string" and g.skill ~= "" and g.skill or "its weapon skill"
        return { action = "keep", basis = "recommendation",
                 reason = "upgrade once you train " .. skill .. " (weapon master)" }
    end },
    -- Flow Modules/Items/Disposition.lua:860-874. An upgrade you can use at a
    -- later level, or better for another role whose set you keep
    -- (context.keptRoles = { [role] = true }, context.roleNames = { [role] = "Balance" }).
    { key = "laterOrOtherRole", order = 40, check = function(i, c)
        local g = factOf(c, "gear", i.key)
        if type(g) ~= "table" or g.canUse ~= true then return nil end
        local main = diffFor(g, c.role)
        if main ~= nil and main >= 0.5 then
            -- Flow's own "wear it now" rule (equip, order 10) is not ported, so
            -- an upgrade whose level you have reached is said as that, not as
            -- "later". A level that is not known is not guessed.
            local at
            if isCount(i.minLevel) and isCount(c.level) and i.minLevel <= c.level then
                at = Disposition.UPGRADE_NOW
            elseif isCount(i.minLevel) then
                at = "upgrade at level " .. i.minLevel
            else
                at = "upgrade at a later level"
            end
            return { action = "keep", reason = at, basis = "recommendation" }
        end
        if type(c.keptRoles) ~= "table" then return nil end
        local roles = {}
        for role, kept in pairs(c.keptRoles) do
            if kept == true and role ~= c.role then roles[#roles + 1] = role end
        end
        table.sort(roles, function(a, b) return tostring(a) < tostring(b) end)
        for idx = 1, #roles do
            local d = diffFor(g, roles[idx])
            if d ~= nil and d >= 0.5 then
                local names = type(c.roleNames) == "table" and c.roleNames or {}
                local name = type(names[roles[idx]]) == "string" and names[roles[idx]] or tostring(roles[idx])
                return { action = "keep", reason = "better for " .. name, basis = "recommendation" }
            end
        end
        return nil
    end },
    -- Flow Modules/Items/Disposition.lua:876-897. Gear your class can wear (or
    -- train for) but no stat weights score for it: kept, never sold as "not
    -- better". context.classScored = false when the class has no weights;
    -- nil (not known) decides nothing.
    { key = "unscoredClass", order = 45, check = function(i, c)
        if c.classScored ~= false then return nil end
        local g = factOf(c, "gear", i.key)
        if type(g) ~= "table" or not (g.canUse == true or g.needsTraining == true) then return nil end
        return { action = "keep", basis = "recommendation",
                 reason = "gear for your class can't be scored yet, so it's kept: decide yourself" }
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
                 reason = "a check failed (" .. tostring(e.r.key) .. "), so it's kept" }
    end
    if v == nil then return nil end
    if type(v) ~= "table" or not ACTIONS[v.action] then
        if type(context.onError) == "function" then pcall(context.onError, e.r.key, "not a verdict") end
        return { action = "keep", basis = "unknown", failed = true,
                 reason = "a check gave no clear answer (" .. tostring(e.r.key) .. "), so it's kept" }
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
                            if type(context.onError) == "function" then
                                if not ok then
                                    pcall(context.onError, e2.r.key, w)
                                elseif w ~= nil and (type(w) ~= "table" or not ACTIONS[w.action]) then
                                    pcall(context.onError, e2.r.key, "not a verdict")
                                end
                            end
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
        return { action = "keep", rule = nil, reason = "not a readable item", basis = "unknown",
                 reasons = { "not a readable item" } }
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
