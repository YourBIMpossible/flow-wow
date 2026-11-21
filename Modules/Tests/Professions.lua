-- Lane W4 self-tests: professions, crafting goals, acquisition.
-- Same harness as Modules/Tests.lua (ns:Register("test", ...)); they stand in
-- only for Flow's own functions, never for the game's, and put back what they
-- change.

local _, ns = ...

local function with(tbl, key, value, fn)
    local old = tbl[key]
    tbl[key] = value
    local ok, err = pcall(fn)
    tbl[key] = old
    if not ok then error(err, 0) end
end

-------------------------------------------------------------------------------
-- F-081: Professions off still keeps the skill a quest asks for.
-------------------------------------------------------------------------------

local QUEST_LOG = { { title = "Bleeding Hearts", objectives = {
    { text = "Raise your first aid skill to 40", finished = false } } } }
local function profsOff(_, kind) return kind ~= "professions" end

ns:Register("test", "professions: off, a quest's skill keeps its target and nothing else does", function(t)
    local SP = ns.skillPlan
    with(ns.nav, "Includes", profsOff, function()
    with(ns.quests, "LogEntries", function() return QUEST_LOG end, function()
    with(ns, "ProfessionPlan", function() return { { name = "Herbalism" } } end, function()
        local targets = SP:Targets()
        local fa = targets["First Aid"]
        t:ok(fa ~= nil, "the quest's skill keeps its target")
        t:eq(fa and fa.target, 40, "to the skill the quest asks for")
        t:eq(fa and fa.quest, "Bleeding Hearts", "named for its quest")
        t:ok(fa and fa.required, "and required, not optional")
        t:eq(targets.Herbalism, nil, "a planned profession behind your level gets nothing while off")
    end) end) end)
end)

ns:Register("test", "professions: off, the route keeps a step a quest needs and drops a plain skill-up", function(t)
    local N = ns.nav
    local function inc(kind) return profsOff(nil, kind) end
    local list = {
        { key = "skillplan:First Aid", provider = "skillplan", forQuest = "Bleeding Hearts", points = {} },
        { key = "skillplan:Herbalism", provider = "skillplan", points = {} },
    }
    local kept = N.FilterKinds(list, inc, 20)
    t:eq(#kept, 1, "one step kept")
    t:eq(kept[1] and kept[1].key, "skillplan:First Aid", "the quest's one")
    t:eq(kept[1] and kept[1].routeKind, "quests", "counted as the quest's step")
    t:eq(list[2].routeKind, "professions", "the plain skill-up is still a profession stop")
end)

ns:Register("test", "professions: a quest's skill step reads 'needed for quest' and names it", function(t)
    local SP = ns.skillPlan
    with(ns.api, "Skill", function(name) if name == "First Aid" then return 10, 75 end end, function()
        local out = {}
        local ok, err = pcall(SP._planProfession, "First Aid",
            { target = 40, quest = "Bleeding Hearts", required = true }, out)
        t:ok(ok, "planning it runs: " .. tostring(err))
        t:ok(#out > 0, "it has at least one step")
        local g = out[1]
        t:eq(g and g.forQuest, "Bleeding Hearts", "the step says which quest needs it")
        local first = g and g.details and g.details[1] or ""
        t:ok(first:find("needed for quest Bleeding Hearts", 1, true) ~= nil, "its reason reads 'needed for quest': " .. first)
        out = {}
        pcall(SP._planProfession, "First Aid", { target = 40, optional = true }, out)
        t:eq(out[1] and out[1].forQuest, nil, "a skill-up for your level isn't marked for a quest")
    end)
end)
