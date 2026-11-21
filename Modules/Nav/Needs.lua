local _, ns = ...

-------------------------------------------------------------------------------
-- Steps that need something first (0.35.142).
--
-- A step says what it needs as tokens, "kind:arg":
--   goal.needs    = { "spell:Bear Form", { "level:20", soft = true } }
--   goal.provides = { "spell:Bear Form" }   (or a needProvider below)
-- Before each plan (N:Collect), N.ResolveNeeds goes through them:
--   * a need you already meet: nothing to do;
--   * a step on the route provides it: this step goes after that one
--     (goal.deps, which the planner keeps; goal.after names it, "after Bear
--     Form", on the map, the Flow Tracker and the arrow; a soft need's dep
--     is also in goal.softDeps, { [key] = true }: it orders, never holds);
--   * nothing on the route provides it: a hard need blocks the step, with
--     the reason (listed with a lock, like a step you can't pay for yet); a
--     soft need only orders, it never blocks.
-- Example: Demoralizing Roar and Maul need Bear Form, which a druid gets from
-- a class quest, not the trainer. The training step needs Bear Form softly:
-- with the quest's turn-in on the route, training comes after it, so one
-- trip trains everything.
--
-- Registry kinds (extend by registering):
--   ns:Register("need", kind, { met = fn(arg) -> bool, label = fn(arg) -> text })
--   ns:Register("needProvider", key, { provides = fn(goal) -> { token, ... } })
-------------------------------------------------------------------------------

local N = ns.nav

function N.ParseNeed(token)
    local kind, arg = tostring(token or ""):match("^(%w+):(.+)$")
    return kind, arg
end

function N.NeedMet(token)
    local kind, arg = N.ParseNeed(token)
    local def = kind and ns:Get("need", kind)
    if not def then return true end   -- (a need Flow can't check never blocks)
    local ok, met = pcall(def.met, arg)
    return not ok or met == true
end

function N.NeedLabel(token)
    local kind, arg = N.ParseNeed(token)
    local def = kind and ns:Get("need", kind)
    if def and def.label then
        local ok, text = pcall(def.label, arg)
        if ok and text then return text end
    end
    return arg or tostring(token)
end

-- Everything step g provides: its own `provides`, and what the providers say.
function N.ProvidesOf(g)
    local out = {}
    for _, t in ipairs(g.provides or {}) do out[#out + 1] = t end
    for _, p in ns:Each("needProvider") do
        local ok, list = pcall(p.provides, g)
        for _, t in ipairs(ok and list or {}) do out[#out + 1] = t end
    end
    return out
end

-- Does `from` (a goal) depend on `key`, directly or through its deps?
-- (A few steps deep: enough to keep two steps from waiting on each other.)
local function dependsOn(from, key, byKey, depth)
    if depth > 6 or not from then return false end
    for _, d in ipairs(from.deps or {}) do
        if d == key or dependsOn(byKey[d], key, byKey, depth + 1) then return true end
    end
    return false
end

function N.ResolveNeeds(list, met, label)
    met, label = met or N.NeedMet, label or N.NeedLabel
    local providers, byKey = {}, {}
    for _, g in ipairs(list or {}) do
        byKey[g.key] = g
        for _, t in ipairs(N.ProvidesOf(g)) do providers[t] = providers[t] or g end
    end
    for _, g in ipairs(list or {}) do
        if g.needs then
            local after = {}
            for _, n in ipairs(g.needs) do
                local token, soft = n, false
                if type(n) == "table" then token, soft = n[1], n.soft == true end
                if not met(token) then
                    local p = providers[token]
                    if p and p ~= g and not dependsOn(p, g.key, byKey, 0) then
                        g.deps = g.deps or {}
                        local has = false
                        for _, d in ipairs(g.deps) do if d == p.key then has = true end end
                        if not has then g.deps[#g.deps + 1] = p.key end
                        -- A soft need only orders: goal.softDeps names the deps
                        -- that are there for no other reason, so a step that's
                        -- off the route never holds this one back
                        -- (N.HoldForDropped). A hard need, or a dep the step had
                        -- already, binds.
                        if soft then
                            if not has then
                                g.softDeps = g.softDeps or {}
                                g.softDeps[p.key] = true
                            end
                        elseif g.softDeps then
                            g.softDeps[p.key] = nil
                        end
                        after[#after + 1] = label(token)
                    elseif not soft and not g.blockedBy then
                        g.blockedBy = "needs " .. label(token) .. " first"
                    end
                end
            end
            g.after = #after > 0 and table.concat(after, ", ") or nil
        end
    end
end

-------------------------------------------------------------------------------
-- The kinds of need Flow can check
-------------------------------------------------------------------------------

ns:Register("need", "spell", {
    met = function(name) return ns.rotation:KnownSpells()[name] == true or ns.api.SpellInfo(name) ~= nil end,
    label = function(name) return name end,
})
ns:Register("need", "level", {
    met = function(n) return UnitLevel("player") >= (tonumber(n) or 0) end,
    label = function(n) return "level " .. n end,
})
ns:Register("need", "quest", {
    met = function(id) return ns.quests and ns.quests:IsCompleted(tonumber(id)) == true end,
    label = function(id)
        local q = ns.quests and ns.quests.QuestieGet and ns.quests:QuestieGet("GetQuest", tonumber(id))
        return q and q.name and ("\"" .. q.name .. "\"") or ("quest " .. id)
    end,
})
ns:Register("need", "item", {
    met = function(id) return ns.api.Count(tonumber(id)) > 0 end,
    label = function(id)
        local name = ns.api.ItemInfo and ns.api.ItemInfo(tonumber(id))
        return name or ("item " .. id)
    end,
})

-- A class quest that teaches a spell (classSpells data: quest = { ids },
-- questName = "..."): its turn-in provides that spell.
local function classQuestSpells()
    local _, token = UnitClass("player")
    local out = {}
    for _, s in ipairs(ns:Get("classSpells", token) or {}) do
        if s.quest or s.questName then out[#out + 1] = s end
    end
    return out
end
ns:Register("needProvider", "classQuest", {
    provides = function(g)
        local id = g.key and tonumber(g.key:match("^(%d+):done$"))
        if not id then return nil end
        local out
        for _, s in ipairs(classQuestSpells()) do
            local match = false
            for _, q in ipairs(s.quest or {}) do if q == id then match = true end end
            if not match and s.questName and g.title == s.questName then match = true end
            if match then out = out or {}; out[#out + 1] = "spell:" .. s.spell end
        end
        return out
    end,
})
