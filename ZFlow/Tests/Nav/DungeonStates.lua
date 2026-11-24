-- The Dungeon Quests pane's data (lead section 303 item 6): each quest's
-- state (a port of legacy Flow's Modules/Nav/Dungeons.lua D.State), the
-- five groups, the chain line and the lines that say why nothing is shown.
-- Pure: plain quest tables in the shape Questie gives, no game client.
-- Made-up quests.
local _, ns = ...
local tests = {}

local S = ns.DungeonStates

-- A quest as Questie gives it: { Id, name, level, requiredLevel,
-- preQuestSingle, preQuestGroup, exclusiveTo, nextQuestInChain, ... }.
local function q(id, over)
    local out = { Id = id, name = "Quest " .. id, level = 20, requiredLevel = 15 }
    for k, v in pairs(over or {}) do out[k] = v end
    return out
end

-- ctx as S.State takes it; quests: { [id] = quest }.
local function ctx(quests, over)
    local c = {
        level = 20, done = {}, log = {},
        get = function(id) return quests[id] end,
        eligible = function() return true end,
        dungeonOf = function() return nil end,
        inside = function() return false end,
        atEntrance = function() return false end,
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

tests["dungeon states: in the log, done, and offered now"] = function(t)
    local a = q(1)
    t.eq(S.State(a, ctx({}, { log = { [1] = true } })), "ready")
    t.eq(S.State(a, ctx({}, { done = { [1] = true } })), "done")
    t.eq(S.State(a, ctx({})), "pickup")
end

tests["dungeon states: inside, a follow-up, the next run and too long"] = function(t)
    t.eq(S.State(q(1), ctx({}, { inside = function() return true end })), "inside")
    local first, second = q(1), q(2, { preQuestSingle = { 1 } })
    local same = function() return 7 end
    t.eq(S.State(second, ctx({ [1] = first }, { dungeonOf = same, atEntrance = function() return true end })),
        "followup", "an earlier part of this dungeon, its giver at the door")
    local state, why = S.State(second, ctx({ [1] = first }, { dungeonOf = same }))
    t.eq({ state, why }, { "nextrun", "after an earlier part" })
    state, why = S.State(q(3, { requiredLevel = 25 }), ctx({}))
    t.eq({ state, why }, { "nextrun", "from level 25" })
    local chain = { [1] = q(1), [2] = q(2, { preQuestSingle = { 1 } }), [3] = q(3, { preQuestSingle = { 2 } }),
        [4] = q(4, { preQuestSingle = { 3 } }) }
    state, why = S.State(q(5, { preQuestSingle = { 4 } }), ctx(chain))
    t.eq({ state, why }, { "toolong", "a long lead-in (4 quests)" })
end

tests["dungeon states: a short lead-in is an unlock, with its steps in order"] = function(t)
    local quests = { [1] = q(1, { name = "First" }) }
    local state, steps = S.State(q(2, { preQuestSingle = { 1 } }), ctx(quests))
    t.eq(state, "unlock")
    t.eq(steps[1].id, 1)
    t.eq(steps[1].name, "First")
end

tests["dungeon states: not for you, with the reason"] = function(t)
    local state, why = S.State(q(1), ctx({}, { eligible = function() return false, "for another class" end }))
    t.eq({ state, why }, { "notforyou", "for another class" })
    state, why = S.State(q(2, { exclusiveTo = { 9 } }), ctx({}, { done = { [9] = true } }))
    t.eq({ state, why }, { "notforyou", "ruled out by a quest you did" })
end

tests["dungeon states: who can take it, from race, class and the giver's faction"] = function(t)
    local me = { raceId = 2, classId = 1, faction = "Horde" }   -- an orc warrior
    t.eq({ S.Eligible(q(1), me) }, { true })
    t.eq({ S.Eligible(q(1, { requiredClasses = 2 }), me) }, { false, "for another class" })
    t.eq({ S.Eligible(q(1, { requiredClasses = 1 }), me) }, { true })
    t.eq({ S.Eligible(q(1, { requiredRaces = 1 }), me) }, { false, "for another race or faction" })
    t.eq({ S.Eligible(q(1, { requiredRaces = 2 }), me) }, { true })
    t.eq({ S.Eligible(q(1, { giverFaction = "A" }), me) }, { false, "the other faction's quest" })
    local ok, why = S.Eligible(q(1, { requiredClasses = 1 }), { faction = "Horde" })
    t.eq(ok, nil, "class not known: cannot tell, kept")
    t.ok(type(why) == "string" and why ~= "", "and says what it cannot check")
    ok = S.Eligible(q(1, { requiredSkill = { 186, 50 } }), me)
    t.eq(ok, nil, "a profession it cannot check: kept")
end

tests["dungeon states: the class token gives the class number"] = function(t)
    t.eq(S.CLASS_ID.WARRIOR, 1)
    t.eq(S.CLASS_ID.DRUID, 11)
    t.eq(S.CLASS_ID.SHAMAN, 7)
end

tests["dungeon pane: the five groups, in order, the last folded"] = function(t)
    local ids, titles = {}, {}
    for i, g in ipairs(S.GROUPS) do ids[i], titles[i] = g.id, g.title end
    t.eq(ids, { "log", "pickup", "inside", "later", "notforyou" })
    t.eq(titles, { "In your log", "Pick up before you go", "Inside", "Later", "Not for you" })
    t.eq(S.GROUPS[5].folded, true)
    t.eq(S.GroupOf("ready"), "log")
    t.eq(S.GroupOf("pickup"), "pickup")
    t.eq(S.GroupOf("unlock"), "pickup")
    t.eq(S.GroupOf("inside"), "inside")
    t.eq(S.GroupOf("followup"), "inside")
    t.eq(S.GroupOf("nextrun"), "later")
    t.eq(S.GroupOf("toolong"), "later")
    t.eq(S.GroupOf("notforyou"), "notforyou")
    t.eq(S.GroupOf("done"), nil, "a quest you did is not listed")
end

tests["dungeon pane: the chain line counts back and forward"] = function(t)
    local quests = {}
    for i = 1, 7 do
        quests[i] = q(i, { preQuestSingle = i > 1 and { i - 1 } or nil, nextQuestInChain = i < 7 and i + 1 or nil })
    end
    local get = function(id) return quests[id] end
    t.eq(S.ChainText(quests[3], get), "Step 3 of 7")
    t.eq(S.ChainText(quests[1], get), "Step 1 of 7")
    t.eq(S.ChainText(q(9), get), nil, "a quest on its own: no chain line")
    local loop = { [1] = q(1, { preQuestSingle = { 2 } }), [2] = q(2, { preQuestSingle = { 1 } }) }
    t.ok(S.ChainText(loop[1], function(id) return loop[id] end) ~= nil, "a loop ends")
end

tests["dungeon pane: rows are grouped, sorted by level, and level-locked ones say when"] = function(t)
    local quests = {
        [1] = q(1, { name = "In log", level = 22 }),
        [2] = q(2, { name = "Easy pickup", level = 18 }),
        [3] = q(3, { name = "Later one", level = 30, requiredLevel = 26 }),
        [4] = q(4, { name = "Other class", requiredClasses = 2 }),
        [5] = q(5, { name = "Done one" }),
        [6] = q(6, { name = "Hard pickup", level = 21 }),
    }
    local c = ctx(quests, { log = { [1] = true }, done = { [5] = true },
        eligible = function(x)
            if x.requiredClasses == 2 then return false, "for another class" end
            return true
        end })
    local pane = S.Pane({ available = true, dungeon = { key = 7, name = "The Deadmines" },
        quests = { quests[1], quests[2], quests[3], quests[4], quests[5], quests[6] }, ctx = c })
    t.eq(pane.title, "The Deadmines")
    t.eq(pane.why, nil)
    local byGroup = {}
    for _, g in ipairs(pane.groups) do
        local names = {}
        for i, r in ipairs(g.rows) do names[i] = r.name end
        byGroup[g.id] = names
    end
    t.eq(byGroup.log, { "In log" })
    t.eq(byGroup.pickup, { "Easy pickup", "Hard pickup" }, "lowest level first")
    t.eq(byGroup.later, { "Later one" })
    t.eq(byGroup.notforyou, { "Other class" })
    t.eq(byGroup.inside, {})
    local later = pane.groups[4].rows[1]
    t.eq(later.note, "Available at Level 26")
    t.eq(later.level, 30)
    t.eq(later.state, "nextrun")
    t.eq(pane.groups[5].rows[1].note, "for another class")
    t.eq(pane.count, 5, "the quest you did is not counted")
end

tests["dungeon pane: what is missing is said, never an empty pane"] = function(t)
    local p = S.Pane({ available = false })
    t.eq(p.why, S.WHY.noQuestie)
    t.eq(#p.why, 2, "what is missing, then how to get it")
    t.eq(S.Pane({ available = true }).why, S.WHY.noDungeon)
    t.eq(S.Pane({ available = true, dungeon = { key = 1, name = "X" }, quests = {}, ctx = ctx({}) }).why,
        S.WHY.noQuests)
    t.eq(S.Pane({ available = true, dungeon = { key = 1, name = "X" }, quests = {}, ctx = ctx({}) }).title, "X")
    for _, lines in pairs(S.WHY) do
        t.ok(type(lines[1]) == "string" and type(lines[2]) == "string", "two lines each")
    end
end

tests["dungeon pane: a state that raises is one quest the pane cannot place, not an error"] = function(t)
    local c = ctx({}, { eligible = function() error("boom") end })
    local pane = S.Pane({ available = true, dungeon = { key = 1, name = "X" }, quests = { q(1) }, ctx = c })
    t.eq(pane.unplaced, 1)
    t.eq(pane.count, 0)
end

tests["dungeon list: by the lowest quest level, then by name; no level known last"] = function(t)
    local list = S.Order({
        { key = 3, name = "Shadowfang Keep", minQ = 22 },
        { key = 1, name = "Ragefire Chasm", minQ = 13 },
        { key = 4, name = "Zul'Farrak" },
        { key = 2, name = "Deadmines", minQ = 17 },
        { key = 5, name = "Blackfathom Deeps", minQ = 22 },
    })
    local names = {}
    for i, d in ipairs(list) do names[i] = d.name end
    t.eq(names, { "Ragefire Chasm", "Deadmines", "Blackfathom Deeps", "Shadowfang Keep", "Zul'Farrak" })
end

tests["dungeon states 305: the one place all objectives share, or none"] = function(t)
    t.eq(S.ObjectivesTop({ 7, 7, nil }), 7)
    t.eq(S.ObjectivesTop({ 7, 8 }), nil, "two places")
    t.eq(S.ObjectivesTop({ 7, false }), nil, "one objective in more than one place")
    t.eq(S.ObjectivesTop({}), nil)
end

-- Lead DISPATCH 343 (the Dungeon Quests look): the level range and the
-- list text are worked out here, so the window computes nothing.
tests["dungeon list 343: the level range as the header and the list say it"] = function(t)
    t.eq(S.LevelText({ minQ = 18, maxQ = 22 }), "Levels 18-22")
    t.eq(S.LevelText({ minQ = 27, maxQ = 27 }), "Level 27", "one level")
    t.eq(S.LevelText({ name = "X" }), nil, "no level known")
    t.eq(S.ListText({ name = "The Deadmines", minQ = 18, maxQ = 22 }), "The Deadmines (18-22)")
    t.eq(S.ListText({ name = "Shadowfang Keep", minQ = 27, maxQ = 27 }), "Shadowfang Keep (27)")
    t.eq(S.ListText({ name = "Zul'Farrak" }), "Zul'Farrak", "no level known: the name alone")
    t.eq(S.CountText(1), "1 quest")
    t.eq(S.CountText(2), "2 quests")
    t.eq(S.CountText(0), "No quests")
end

tests["dungeon pane: every row says what the player does next"] = function(t)
    local quests = {
        [1] = q(1, { name = "In log", level = 22 }),
        [2] = q(2, { name = "Easy pickup", level = 18 }),
        [3] = q(3, { name = "Later one", level = 30, requiredLevel = 26 }),
    }
    local pane = S.Pane({ available = true, dungeon = { key = 7, name = "The Deadmines" },
        quests = { quests[1], quests[2], quests[3] }, ctx = ctx(quests, { log = { [1] = true } }) })
    local seen = 0
    for _, g in ipairs(pane.groups) do
        for _, r in ipairs(g.rows) do
            if g.id ~= "notforyou" then
                seen = seen + 1
                t.eq(r.next, S.NEXT[r.state], tostring(r.name) .. ": the line for its state")
                t.ok(type(r.next) == "string" and r.next ~= "", tostring(r.name) .. ": a next step")
            end
        end
    end
    t.eq(seen, 3, "all three rows")
    t.eq(pane.groups[1].rows[1].next, "Do it on this run.")
    for state, line in pairs(S.NEXT) do
        t.ok(type(line) == "string" and line:sub(-1) == ".", state .. ": a whole sentence")
    end
end


return tests
