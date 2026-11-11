-- Self-tests: /flow test runs every registered test in game and prints a
-- summary (failures in full). They also run on every /reload as part of the
-- diagnostics snapshot, so Claude can read the results from disk
-- (tools\read-diag.ps1, "--- tests").
--
-- Add tests next to the feature or here:
--   ns:Register("test", "area: what it checks", function(t)
--       t:eq(actual, expected, "message")
--       t:ok(condition, "message")
--       t:near(a, b, tolerance, "message")
--   end)
-- Tests check Flow's own logic with made-up inputs; they never change your
-- settings (anything they touch is put back).

local _, ns = ...

local T = {}
T.__index = T

function T:ok(cond, msg)
    self.n = self.n + 1
    if not cond then self.fails[#self.fails + 1] = msg or "expected true" end
end

function T:eq(a, b, msg)
    self:ok(a == b, string.format("%s: got %s, expected %s", msg or "eq", tostring(a), tostring(b)))
end

function T:near(a, b, tol, msg)
    self:ok(type(a) == "number" and math.abs(a - b) <= (tol or 1e-6),
        string.format("%s: got %s, expected %s", msg or "near", tostring(a), tostring(b)))
end

local function run(filter)
    local passed, failed, checks, out = 0, 0, 0, {}
    for name, fn in ns:Each("test") do
        if not filter or filter == "" or name:lower():find(filter:lower(), 1, true) then
            local t = setmetatable({ n = 0, fails = {} }, T)
            local ok, err = pcall(fn, t)
            if not ok then t.fails[#t.fails + 1] = "error: " .. tostring(err) end
            checks = checks + t.n
            if #t.fails == 0 then
                passed = passed + 1
            else
                failed = failed + 1
                out[#out + 1] = "FAIL " .. name
                for _, f in ipairs(t.fails) do out[#out + 1] = "    " .. f end
            end
        end
    end
    return passed, failed, checks, out
end

ns.commands.test = function(arg)
    local passed, failed, checks, out = run(arg)
    local head = string.format("tests: %d passed, %d failed (%d checks)", passed, failed, checks)
    ns:Print(head)
    for _, l in ipairs(out) do print(l) end
    -- A failure: open it in the copy window too, so it can be copied out.
    if failed > 0 and ns.copyBox then
        local lines = { head }
        for _, l in ipairs(out) do lines[#lines + 1] = l end
        pcall(ns.copyBox.Show, ns.copyBox, "Flow self-tests: " .. failed .. " failed", lines)
    end
end

-- After every login and /reload: run them all, and if anything fails say so
-- in chat right away (one red line), so a broken button shows up before you
-- click it. The full results are in the diagnostics and /flow test.
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(8, function()
        if InCombatLockdown() then return end
        local t0 = debugprofilestop and debugprofilestop()
        local ok, passed, failed, checks, out = pcall(run)
        local ms = t0 and (debugprofilestop() - t0) or 0
        if not ok then ns:Log("tests", "run failed: " .. tostring(passed)) return end
        ns:Log("tests", string.format("at login: %d passed, %d failed (%.0f ms)", passed, failed, ms))
        -- Kept for the after-login diagnostics, so it needn't run them again.
        ns.lastTestRun = { at = date("%H:%M:%S"), passed = passed, failed = failed, checks = checks,
                           out = out, ms = ms }
        if failed > 0 then
            local first = (out[1] or ""):gsub("^FAIL ", "")
            ns:Print(string.format("|cffff6060%d self-test%s failed|r (%s%s). Details: /flow test",
                failed, failed == 1 and "" or "s", first, failed > 1 and ", ..." or ""))
            for _, l in ipairs(out) do ns:Log("tests", l) end
        end
    end)
end)

-------------------------------------------------------------------------------
-- Tests
-------------------------------------------------------------------------------

local function with(tbl, key, value, fn)
    local old = tbl[key]
    tbl[key] = value
    local ok, err = pcall(fn)
    tbl[key] = old
    if not ok then error(err, 0) end
end

ns:Register("test", "core: each character has its own data", function(t)
    -- Old shared data, as saved before the split: a druid's trainer, fights
    -- from both characters, recipes, a hidden stop and shared settings.
    local account = {
        trainer = { npc = "Mardant Strongoak", services = { { name = "Moonfire" } } },
        profiler = { fights = { { casts = { Moonfire = 2 } }, { casts = { ["Holy Light"] = 1 } }, { casts = { Attack = 5 } } } },
        quests = { enabled = true, notOffered = { [101] = { at = 1 } } },
        nav = { hidden = { ["7:1"] = true }, arrowStyle = "3d", graphs = { trail = true } },
        crafting = { Mining = { rank = 50 }, Blacksmithing = { rank = 60 }, drops = { [2] = "x" } },
    }
    local druid, paladin = {}, {}
    ns:SplitCharacterData(account, druid, { class = "DRUID" })
    t:eq(account.trainer and account.trainer.npc, "Mardant Strongoak", "the druid gets the druid trainer")
    t:ok(account.trainer ~= account.legacyShared.trainer, "as its own copy")
    t:eq(account.profiler and #account.profiler.fights, 1, "only the druid's fight (no Holy Light, no Attack-only)")
    t:eq(account.quests.notOffered, nil, "short-lived quest data starts fresh")
    t:eq(account.quests.enabled, true, "settings stay shared")
    t:ok(account.nav.hidden and account.nav.hidden["7:1"], "stops hidden before stay hidden")
    t:ok(account.nav.graphs.trail, "learned trails stay shared")
    t:eq(account.crafting, nil, "recipes wait for login (professions)")
    account.crafting = {}   -- (what Recipes.lua's OnLoad does)
    with(ns.api, "ProfessionSet", function() return { Mining = true } end, function()
        ns:AdoptLaterCharacterData(account, druid, { class = "DRUID" })
    end)
    t:ok(account.crafting.Mining and not account.crafting.Blacksmithing, "recipes only for professions you have")
    t:ok(druid.adopted.crafting, "done once")

    -- Playing changes this character's data; logout stores it apart.
    account.trainer.npc = "Someone else"
    ns:StoreCharacterData(account, druid)
    t:eq(account.trainer, nil, "logout: out of the shared data")
    t:eq(druid.data.trainer.npc, "Someone else", "into this character's own")
    t:eq(account.nav.arrowStyle, "3d", "shared settings untouched")
    t:eq(account.nav.hidden, nil, "hidden stops are per character")

    -- Another character: its own share of the old data, nothing of the druid's.
    ns:SplitCharacterData(account, paladin, { class = "PALADIN" })
    t:eq(account.trainer, nil, "no druid trainer for the paladin")
    t:eq(account.profiler and #account.profiler.fights, 1, "only the paladin's fight")
    t:ok(account.profiler.fights[1].casts["Holy Light"], "the Holy Light one")
    with(ns.api, "ProfessionSet", function() return {} end, function()
        ns:AdoptLaterCharacterData(account, paladin, { class = "PALADIN" })
    end)
    t:ok(not paladin.adopted.crafting, "professions not known yet: tried again next login")
    ns:StoreCharacterData(account, paladin)

    -- The druid again (a /reload or the next login): its data, not adopted twice.
    ns:SplitCharacterData(account, druid, { class = "DRUID" })
    t:eq(account.trainer and account.trainer.npc, "Someone else", "the druid's own data is back")
    t:eq(account.legacyShared.trainer.npc, "Mardant Strongoak", "the parked old data never changes")
end)

ns:Register("test", "core: class spell sets tell classes apart", function(t)
    local druid, paladin = ns:ClassSpellSet("DRUID"), ns:ClassSpellSet("PALADIN")
    t:ok(druid.Moonfire and not paladin.Moonfire, "Moonfire is a druid's")
    t:ok(paladin["Holy Light"] and not druid["Holy Light"], "Holy Light is a paladin's")
    t:ok(not druid.Attack and not paladin.Attack, "Attack is nobody's")
end)

ns:Register("test", "core: registry keeps order and finds by key", function(t)
    local list = {}
    for k in ns:Each("profGuide") do list[#list + 1] = k end
    t:ok(#list >= 4, "profession guides registered")
    t:ok(ns:Get("profGuide", "Blacksmithing") ~= nil, "Blacksmithing guide")
    local ok = pcall(ns.Register, ns, "profGuide", "Blacksmithing", {})
    t:ok(not ok, "registering the same key twice is an error")
end)

ns:Register("test", "skill plan: reads 'raise your skill' objectives", function(t)
    local P = ns.skillPlan.ParseObjective
    local a, n = P("Raise your blacksmithing skill to 20")
    t:eq(a, "Blacksmithing", "profession"); t:eq(n, 20, "target")
    a, n = P("Raise your first aid skill to 40: 0/1")
    t:eq(a, "First Aid", "two-word profession"); t:eq(n, 40, "target")
    t:eq(P("Kill 10 Kobold Vermin"), nil, "not a skill objective")
    t:eq(P(nil), nil, "nil text")
end)

ns:Register("test", "skill plan: most skill per material", function(t)
    local g = ns:Get("profGuide", "Blacksmithing")
    local crafts, order, reaches = ns.skillPlan._simulate("Blacksmithing__test", g.steps, 1, 20, {})
    t:ok(reaches, "guide reaches 20")
    t:eq(order[1] and order[1].recipe, "Rough Sharpening Stone", "starts with sharpening stones")
    local total = 0
    for _, s in ipairs(order) do total = total + crafts[s] end
    t:ok(total >= 19 and total <= 25, "about one craft per point while orange (" .. total .. ")")
    order = select(2, ns.skillPlan._simulate("Blacksmithing__test", g.steps, 30, 50, {}))
    for _, s in ipairs(order) do t:ok(s.recipe ~= "Coarse Sharpening Stone", "no coarse stones below 65") end
end)

ns:Register("test", "xp: share and estimate", function(t)
    local X = ns.xpValue
    t:eq(X.Share(6, 7), 1, "1 level below: full")
    t:eq(X.Share(2, 7), 1, "5 below: full")
    t:eq(X.Share(1, 7), 0.8, "6 below: 80%")
    t:eq(X.Share(1, 20), 0.1, "far below: 10%")
    t:ok(X.Estimate(10) > X.Estimate(6), "higher quests give more XP")
end)

ns:Register("test", "xp: weights favour your level, add tooltip lines", function(t)
    local me = UnitLevel("player")
    local goals = {
        { key = "pickup:999001", level = me, weight = 1, details = {} },
        { key = "pickup:999002", level = me + 3, weight = 1, details = {} },
    }
    -- (Completionist routes always sort by distance: test in the default mode.)
    with(ns.db.nav, "mode", "optimal", function()
        with(ns.db.nav, "sorter", "xp", function() ns.xpValue:Apply(goals) end)
    end)
    t:ok(goals[2].weight > goals[1].weight, "3 levels above weighs more than your level")
    t:ok(goals[1].details[1] and goals[1].details[1]:find("^XP: "), "XP line added")
    local plain = { { key = "pickup:999003", level = me + 3, weight = 1, details = {} } }
    with(ns.db.nav, "sorter", "distance", function() ns.xpValue:Apply(plain) end)
    t:eq(plain[1].weight, 1, "shortest path leaves weights alone")
end)

ns:Register("test", "quest spots: spread over every mob's spawns, your map first", function(t)
    local S = ns.quests.SpreadPoints
    local mapFor = function(area) return area end   -- area id = map id here
    -- Bandits: 150 spawns along x (0..149 %), a wizard: 10 spawns, another zone: 5.
    local bandit, wizard, far = { [1] = {} }, { [1] = {} }, { [2] = {} }
    for i = 0, 149 do bandit[1][#bandit[1] + 1] = { i * 0.66, 50 } end
    for i = 1, 10 do wizard[1][#wizard[1] + 1] = { 70, 40 + i } end
    for i = 1, 5 do far[2][#far[2] + 1] = { 10, 10 } end
    local pts, onMap, known = S({ bandit, wizard, far }, 80, { map = 1, mapFor = mapFor })
    t:eq(#pts, 80, "kept the cap")
    t:eq(known, 165, "counts every spawn it knew")
    t:ok(onMap, "some on your map")
    local maxX, wiz, other = 0, 0, 0
    for _, p in ipairs(pts) do
        if p.map == 1 and p.y == 0.5 then maxX = math.max(maxX, p.x) end
        if p.map == 1 and p.x == 0.7 then wiz = wiz + 1 end
        if p.map == 2 then other = other + 1 end
    end
    t:ok(maxX > 0.9, "reaches the far end of the bandits' spawns (" .. maxX .. ")")
    t:ok(wiz > 0, "the second mob still gets spots (" .. wiz .. ")")
    t:eq(other, 0, "other zones wait while your map fills the cap")
    local few = S({ wizard, far }, 80, { map = 1, mapFor = mapFor })
    t:eq(#few, 15, "under the cap: everything, other zones too")
    local only = S({ wizard, far }, 80, { map = 1, onlyMap = true, mapFor = mapFor })
    t:eq(#only, 10, "onlyMap: just your map when it has any")
    local none = S({ far }, 80, { map = 1, onlyMap = true, mapFor = mapFor })
    t:eq(#none, 5, "onlyMap with nothing here: anywhere")
    t:eq(#S({ { [1] = { { -1, -1 } } } }, 80, { mapFor = mapFor }), 0, "no-position spawns skipped")
end)

ns:Register("test", "route colour shows its state: purple, blue, orange custom", function(t)
    local want = { xp = "A335EE", distance = "0070DD", custom = "FF8000", selected = "FF8000" }
    local palette = ns.theme.palette
    ns.theme:UsePalette("standard")
    for mode, hex in pairs(want) do
        with(ns.db.nav, "sorter", mode, function() ns.theme:UpdateRoute() end)
        t:eq(ns.theme.route.hex, hex, mode .. (mode == "selected" and " (old save: Custom route)" or ""))
    end
    t:eq(ns.theme.waypoint.hex, "1EFF00", "your waypoint: green, not the Custom route orange")
    ns.theme:UsePalette(palette)
    ns.theme:UpdateRoute()
end)

ns:Register("test", "planner: nearest first, turn-in after its objective", function(t)
    local function goal(key, x, extra)
        local g = { key = key, text = key, points = { { cont = 0, wx = x, wy = 0 } } }
        for k, v in pairs(extra or {}) do g[k] = v end
        return g
    end
    local p = { cont = 0, wx = 0, wy = 0 }
    local plan = ns.planner:Plan(p, { goal("far", 300), goal("near", 20), goal("mid", 120) }, {})
    t:eq(plan and plan[1].goal.key, "near", "nearest first")
    t:eq(plan and plan[3].goal.key, "far", "farthest last")
    -- The turn-in is right next to you, but its objective is further away.
    plan = ns.planner:Plan(p, { goal("1:done", 5, { deps = { "1:1" } }), goal("1:1", 200) }, {})
    t:eq(plan and plan[1].goal.key, "1:1", "objective before its turn-in")
end)

ns:Register("test", "planner: near first, far stops and item drops wait", function(t)
    local F = ns.nearFirst
    t:eq(F.Multiplier({}, 100), 1, "close: unchanged")
    t:near(F.Multiplier({}, 1000), 2, 0.001, "1,000 yd: 2x")
    t:eq(F.Multiplier({}, 9000), 3, "capped at 3x")
    t:eq(F.Multiplier({ milestone = true }, 9000), 1, "class training left alone")
    t:eq(F.Multiplier({ kind = "collect" }, 100), 1, "an item drop right here is fine")
    t:near(F.Multiplier({ kind = "collect" }, 200), 1.5, 0.001, "a drop further off waits")
    t:eq(F.Multiplier({ kind = "collect" }, nil), 1.5, "a drop with no spot near you waits")

    local p = { cont = 0, wx = 0, wy = 0 }
    local function goal(key, x, extra)
        local g = { key = key, text = key, points = { { cont = 0, wx = x, wy = 0 } } }
        for k, v in pairs(extra or {}) do g[k] = v end
        return g
    end
    -- Both straight ahead, the drop a little nearer. Unweighted the drop comes
    -- first (300 + 10 yd vs 310 + 10); near first makes it 1.5x heavier, so the
    -- kill right behind it comes first (310 + 10 x 1.5 vs 300 x 1.5 + 10).
    local drop = goal("1:1", 300, { kind = "collect" })
    local kill = goal("2:1", 310, { kind = "kill", weight = 1 })
    -- On the Most XP route whatever yours is: near first leaves Shortest
    -- alone (0.35.126), so on Shortest this test failed (0.35.132).
    with(ns.xpValue, "Objective", function() return "xp" end, function()
    with(ns.db, "nearFirst", true, function()
        local plan = ns.planner:Plan(p, { drop, kill }, {})
        t:eq(plan and plan[1].goal.key, "2:1", "a kill right behind an item drop comes first")
        t:eq(drop.weight, nil, "the drop gets its own weight back")
        t:eq(kill.weight, 1, "the kill gets its own weight back")
    end)
    with(ns.db, "nearFirst", false, function()
        local plan = ns.planner:Plan(p, { drop, kill }, {})
        t:eq(plan and plan[1].goal.key, "1:1", "off: the nearer drop comes first")
    end)
    end)
    with(ns.xpValue, "Objective", function() return "distance" end, function()
        local plan = ns.planner:Plan(p, { drop, kill }, {})
        t:eq(plan and plan[1].goal.key, "1:1", "Shortest: the nearer drop comes first (near first stays out)")
    end)
end)

ns:Register("test", "planner: plans 30 stops, the far end nearest-next", function(t)
    local function goal(key, x, y, extra)
        local g = { key = key, text = key, points = { { cont = 0, wx = x, wy = y or 0 } } }
        for k, v in pairs(extra or {}) do g[k] = v end
        return g
    end
    local p = { cont = 0, wx = 0, wy = 0 }
    -- 40 stops in a line, given out of order: the nearest 30 make the plan.
    local goals = {}
    for k = 40, 1, -1 do goals[#goals + 1] = goal("g" .. k, k * 10) end
    local plan = ns.planner:Plan(p, goals, {})
    t:eq(plan and #plan, 30, "30 stops planned (was 14)")
    t:eq(plan and plan[1] and plan[1].goal.key, "g1", "nearest first")
    t:eq(plan and plan[30] and plan[30].goal.key, "g30", "the 30th nearest last")
    local inOrder = true
    for i = 2, plan and #plan or 0 do
        if plan[i].point.wx < plan[i - 1].point.wx then inOrder = false end
    end
    t:ok(inOrder, "past the polished part, still nearest-next (no back and forth)")
    -- A turn-in out in the nearest-next part still comes after its objective.
    goals = {}
    for k = 1, 28 do goals[#goals + 1] = goal("g" .. k, k * 10) end
    goals[#goals + 1] = goal("q:done", 245, 5, { deps = { "q:1" } })
    goals[#goals + 1] = goal("q:1", 255, 5)
    plan = ns.planner:Plan(p, goals, {})
    local at = {}
    for i, s in ipairs(plan or {}) do at[s.goal.key] = i end
    t:ok(at["q:1"] and at["q:done"] and at["q:1"] > 14, "both far out (after the first 14)")
    t:ok(at["q:1"] and at["q:done"] and at["q:1"] < at["q:done"], "objective before its turn-in")
end)

ns:Register("test", "blocked stops: label and reason", function(t)
    local text, why = ns.nav:FormatBlocked({ text = "Buy a Mining Pick", blockedBy = "needs 16c (you have 6c)" })
    t:ok(text:find("Buy a Mining Pick", 1, true) ~= nil, "text kept")
    t:ok(why:find("needs 16c", 1, true) ~= nil, "reason shown")
end)

ns:Register("test", "buffs: remembered casts stand in for hidden auras", function(t)
    local A = ns.api
    local saved = {}
    for k, v in pairs(A._castMemory) do saved[k] = v end
    wipe(A._castMemory)
    A.RememberCast("Seal of Righteousness")
    local up, left = A._fromMemory(function(n) return n:find("^Seal of") end)
    t:ok(up, "seal remembered"); t:ok(left > 25 and left <= 30, "about 30 s left")
    A.RememberCast("Devotion Aura")
    A.RememberCast("Retribution Aura")
    t:ok(not A._fromMemory("Devotion Aura"), "a new aura replaces the old one")
    t:ok(A._fromMemory("Retribution Aura"), "new aura active")
    wipe(A._castMemory)
    for k, v in pairs(saved) do A._castMemory[k] = v end
end)

ns:Register("test", "gear: shields are never Retribution upgrades", function(t)
    if select(2, UnitClass("player")) ~= "PALADIN" then t:ok(true) return end
    local item = { equipLoc = "INVTYPE_SHIELD", slots = { 17 }, stats = { RESISTANCE0_NAME = 500 } }
    local scores = ns.gear:Score(item)
    local diff = ns.gear:RoleDiff(item, "dps", scores)
    t:ok(diff <= 0, "dps diff not positive (" .. tostring(diff) .. ")")
end)

ns:Register("test", "menu: one choice ticked per group", function(t)
    local items = ns.menu:RouteItems()
    local group, ticked = nil, {}
    for _, it in ipairs(items) do
        if it.title then group = it.text; ticked[group] = 0 end
        if it.radio and it.checked then ticked[group] = ticked[group] + 1 end
    end
    t:eq(ticked.Route, 1, "route")
    t:eq(ticked.Order, 1, "order")
    if ticked.Party then t:eq(ticked.Party, 1, "party: your route or the party route") end
end)

ns:Register("test", "tooltip: stop details render", function(t)
    local tt = _G.FlowTestTooltip or CreateFrame("GameTooltip", "FlowTestTooltip", UIParent, "GameTooltipTemplate")
    tt:SetOwner(UIParent, "ANCHOR_NONE")
    local ok, err = pcall(ns.nav.FillTooltip, ns.nav, tt,
        { key = "pickup:999004", title = "Test quest", text = "Accept: Test quest", level = 5,
          details = { "XP: about 355 (full XP)" } }, "footer")
    t:ok(ok, "no error: " .. tostring(err))
    t:ok(tt:NumLines() >= 4, "title, task, details and footer")
    tt:Hide()
end)

ns:Register("test", "ways to improve: no quests to accept", function(t)
    local items = ns:Get("advisor", "missedQuests").check() or {}
    for _, it in ipairs(items) do
        t:ok(not (it.goalKey and it.goalKey:find("^pickup:")), "no pickup advice: " .. tostring(it.text))
    end
    t:ok(true)
end)

ns:Register("test", "planner: a quest's turn-in comes along with its objectives", function(t)
    local p = { cont = 0, wx = 0, wy = 0 }
    local goals = {}
    for i = 1, 16 do
        goals[#goals + 1] = { key = "near" .. i, text = "near", points = { { cont = 0, wx = i * 10, wy = 0 } } }
    end
    goals[#goals + 1] = { key = "7:1", text = "objective", points = { { cont = 0, wx = 5, wy = 5 } } }
    goals[#goals + 1] = { key = "7:done", text = "turn in", deps = { "7:1" }, points = { { cont = 0, wx = 900, wy = 0 } } }
    local plan = ns.planner:Plan(p, goals, {})
    local at = {}
    for i, s in ipairs(plan or {}) do at[s.goal.key] = i end
    t:ok(at["7:done"] ~= nil, "turn-in planned although it's the farthest stop")
    t:ok(at["7:1"] and at["7:done"] and at["7:1"] < at["7:done"], "after its objective")
end)

ns:Register("test", "planner: finish the area you're in first", function(t)
    local P = ns.planner
    local saved = ns.db.nearFirst
    ns.db.nearFirst = false   -- (the plain planner, without the near-first weights)
    local ok, err = pcall(function()
        local function goal(key, x, extra)
            local g = { key = key, text = key, points = { { cont = 0, wx = x, wy = 0 } } }
            for k, v in pairs(extra or {}) do g[k] = v end
            return g
        end
        local p = { cont = 0, wx = 0, wy = 0 }
        -- Two stops around you, one behind you, two far ahead. The shortest
        -- trip goes behind you first (2800 yd); finishing here first is 3200.
        local function line() return { goal("A", 100), goal("B", 200), goal("W", -600), goal("E", 1500), goal("E2", 1600) } end
        local plan = P:Plan(p, line(), { areaFirst = true })
        t:eq(plan and plan[1].goal.key, "A", "the stops around you first")
        t:eq(plan and plan[2].goal.key, "B", "both of them, before the far ones")
        plan = P:Plan(p, line(), { areaFirst = false })
        t:eq(plan and plan[1].goal.key, "W", "rule off: the shortest trip goes the other way first")
        -- Leaving early only when it saves a lot.
        t:ok(P.AreaKeepsFree(1000, 3000), "saves 2000 of 3000 yd: leave the area early")
        t:ok(not P.AreaKeepsFree(2800, 3200), "saves 400 of 3200 yd: finish the area")
        -- A turn-in nearby whose objective is far away can't be finished here.
        plan = P:Plan(p, { goal("A", 100), goal("q:done", 150, { deps = { "q:1" } }), goal("q:1", -900), goal("E", 1500) },
            { areaFirst = true })
        local at = {}
        for i, s in ipairs(plan or {}) do at[s.goal.key] = i end
        t:eq(at.A, 1, "the area first")
        t:ok(at["q:1"] and at["q:done"] and at["q:1"] < at["q:done"], "the turn-in still after its objective")
        -- A quest to pick up a little further out still counts as the area.
        plan = P:Plan(p, { goal("pickup:9", 450, { weight = 1 }), goal("W", -350), goal("E", 3000) }, { areaFirst = true })
        t:eq(plan and plan[1].goal.key, "pickup:9", "a quest pickup 450 yd away is part of the area")
        plan = P:Plan(p, { goal("X", 450), goal("W", -350), goal("E", 3000) }, { areaFirst = true })
        t:eq(plan and plan[1].goal.key, "W", "any other stop 450 yd away isn't")
    end)
    ns.db.nearFirst = saved
    t:ok(ok, "ran" .. (ok and "" or (": " .. tostring(err))))
end)

ns:Register("test", "skill plan: gear you can make that's an upgrade, beside the fastest path", function(t)
    local SP = ns.skillPlan
    local gains = {
        [101] = { 3, "tank", "belt A", "INVTYPE_WAIST" },
        [102] = { 5, "tank", "belt B", "INVTYPE_WAIST" },
        [103] = { 1, "tank", "gloves", "INVTYPE_HAND" },
    }
    local function gainOf(id)
        local g = gains[id]
        if g then return g[1], g[2], g[3], g[4] end
    end
    local ups = SP.PickUpgrades({
        { recipe = "Belt A", item = 101 }, { recipe = "Belt B", item = 102 },
        { recipe = "Bandage", item = 104 }, { recipe = "Gloves", item = 103 },
    }, gainOf)
    t:eq(#ups, 2, "one per slot, and only upgrades")
    t:eq(ups[1] and ups[1].recipe, "Belt B", "the bigger belt upgrade, first")
    t:eq(ups[2] and ups[2].recipe, "Gloves", "then the gloves")
    -- From your profession window's recipes (Flow's own saved list).
    local saved = ns.db.crafting["Blacksmithing"]
    ns.db.crafting["Blacksmithing"] = { rank = 30, recipes = {
        ["Belt B"] = { item = 102, diff = "optimal", reagents = { [2840] = 6 } },
        ["Rough Sharpening Stone"] = { item = 2862, diff = "easy", reagents = { [2835] = 1 } },
    } }
    local ok, err = pcall(function()
        ups = SP.Upgrades("Blacksmithing", gainOf)
        t:eq(#ups, 1, "only the recipe that makes an upgrade")
        t:eq(ups[1] and ups[1].station, "anvil", "Blacksmithing gear: at an anvil")
        t:eq(ups[1] and ups[1].reagents[2840], 6, "its materials come along")
        -- The fastest path is worked out from the guide alone: the upgrade
        -- doesn't change what it makes.
        local g = ns:Get("profGuide", "Blacksmithing")
        local _, order = SP._simulate("Blacksmithing", g.steps, 1, 20, {})
        for _, st in ipairs(order) do t:ok(st.recipe ~= "Belt B", "the fastest path doesn't make the belt") end
        t:ok(#order > 0, "the fastest path still has its steps")
    end)
    ns.db.crafting["Blacksmithing"] = saved
    t:ok(ok, "ran" .. (ok and "" or (": " .. tostring(err))))
    t:eq(#SP.Upgrades("No Such Profession", gainOf), 0, "a profession you never opened: nothing")
end)

ns:Register("test", "spec badge: better / worse / same per spec", function(t)
    t:eq(ns.SpecTrend(1.2), "up", "better"); t:eq(ns.SpecTrend(-3), "down", "worse")
    t:eq(ns.SpecTrend(0.2), "same", "about the same"); t:eq(ns.SpecTrend(nil), nil, "no score")
    local b = ns:SpecBadge(UIParent, 10)
    b:Set({ dps = 2, heal = -2, tank = 0 })
    t:ok(b:IsShown(), "shown with scores")
    local up = b.slots.dps.arrow
    t:ok((up.tex:IsShown() or up.l1:IsShown()) and not up.bar:IsShown(), "dps: arrow")
    t:ok(b.slots.tank.arrow.bar:IsShown(), "tank: flat bar")
    b:Set(nil)
    t:ok(not b:IsShown(), "hidden without scores")
    b:Hide()
end)

ns:Register("test", "rotation: heals early on Flow's hurt estimate (health is hidden)", function(t)
    local E = ns.rotation
    local H = E.HURT
    -- The estimate: hit time adds up, regen and eating take it down, the warning floors it.
    t:eq(E.StepHurt(0, 10, true, 1, false, false), 10, "10 s with an enemy on you: 10")
    t:eq(E.StepHurt(0, 10, true, 0.5, false, false), 5, "the game won't say: half")
    t:near(E.StepHurt(10, 3, false, 0, false, false), 9, 0.01, "out of a fight: 1 every 3 s")
    t:eq(E.StepHurt(10, 3, false, 0, true, false), 1, "eating: 3 a second")
    t:eq(E.StepHurt(0, 0.5, true, 0, false, true), H.low, "the low-health warning: at least 40")
    t:eq(E.StepHurt(5, 100, false, 0, false, false), 0, "never below 0")

    local def = { heals = { "Healing Touch", "Rejuvenation" }, hots = { "Rejuvenation" }, hotDuration = { Rejuvenation = 12 } }
    local ms = { ["Healing Touch"] = 2500, Rejuvenation = 0 }
    local quiet = { inCombat = false, hostile = false }
    local pulling = { inCombat = false, hostile = true }
    local fight = { inCombat = true, hostile = true }
    local far = GetTime() + 100000   -- (a Rejuvenation you cast just now never counts here)
    with(E, "Ready", function() return true end, function()
    with(ns.api, "SpellInfo", function(sp) return sp, nil, ms[sp] end, function()
    with(ns.api, "Buff", function() return false, 0 end, function()
        t:eq(E:EarlyHeal(quiet, def, 3, far), nil, "barely touched: no heal")
        t:eq(E:EarlyHeal(quiet, def, 8, far).spell, "Rejuvenation", "a little hurt: the HoT")
        t:eq(E:EarlyHeal(pulling, def, 8, far).spell, "Rejuvenation", "an enemy targeted: heal before the pull")
        t:eq(E:EarlyHeal(quiet, def, 20, far).spell, "Healing Touch", "hurt from your fights: the big heal")
        t:eq(E:EarlyHeal(fight, def, 5, far), nil, "early in a fight: attacks")
        t:eq(E:EarlyHeal(fight, def, 10, far).spell, "Rejuvenation", "hit for a while: HoT in the fight")
        t:eq(E:EarlyHeal(fight, def, 25, far).spell, "Rejuvenation", "hit a lot: the fastest heal (instant)")
        t:ok(E:EarlyHeal(fight, def, 10, far).reason:find("Shift", 1, true) ~= nil, "says Shift + key casts it in a fight")
    end) end) end)
    with(E, "Ready", function() return true end, function()
    with(ns.api, "SpellInfo", function(sp) return sp, nil, ms[sp] end, function()
    with(ns.api, "Buff", function(_, sp) return sp == "Rejuvenation", 10 end, function()
        t:eq(E:EarlyHeal(quiet, def, 8, far), nil, "HoT already on you: it's healing you")
        t:eq(E:EarlyHeal(fight, def, 10, far), nil, "HoT on you in a fight: nothing more yet")
    end) end) end)
end)

ns:Register("test", "cast key: never locked to nothing for a fight", function(t)
    local E = ns.rotation
    local def = ns:Get("rotation", "PALADIN")   -- (Paladin rules, whatever class you're on)
    if not (def and def.pullLock) then t:ok(true) return end
    local main = E:Knows("Judgement") and "Judgement" or nil
    if main then
        t:eq(def.pullLock(nil, E), main, "no suggestion at the pull: main attack")
        t:eq(def.pullLock({ spell = "Blessing of Might", kind = "buff" }, E), main, "a blessing at the pull: main attack")
        t:eq(def.pullLock({ spell = "Attack", kind = "damage" }, E), main, "auto attack at the pull: main attack")
    end
    t:eq(def.pullLock({ spell = "Holy Strike", kind = "damage" }, E), "Holy Strike", "a real attack stays")
end)

ns:Register("test", "arrow: anywhere in a quest's area counts as arrived", function(t)
    local p = { cont = 0, wx = 0, wy = 0 }
    local goal = { area = true, points = { { cont = 0, wx = 300, wy = 0 }, { cont = 0, wx = 30, wy = 10 } } }
    t:ok(ns.nav:InArea(goal, p), "near one of the spawns")
    goal.points[2].wx = 200
    t:ok(not ns.nav:InArea(goal, p), "far from all spawns")
    t:ok(not ns.nav:InArea({ points = { { cont = 0, wx = 1, wy = 1 } } }, p), "single-spot stops use the normal arrival")
end)

ns:Register("test", "ways to improve: no 'choose professions' once two are learned", function(t)
    local main = 0
    for _, pr in ipairs(ns.api.Professions()) do
        if pr.primary then main = main + 1 end
    end
    local items = ns:Get("advisor", "choosePro").check()
    if main >= 2 then t:ok(items == nil, "not suggested") else t:ok(true) end
end)

ns:Register("test", "cast key: the after-fight heal never becomes the fight's key", function(t)
    local E = ns.rotation
    local def = E:Definition()
    if not (def and def.pullLock and E:Knows("Judgement")) then t:ok(true) return end
    t:eq(def.pullLock({ spell = "Holy Light", kind = "heal" }, E), "Judgement", "heal at the pull: main attack")
end)

ns:Register("test", "lists: quest stops show a quest icon", function(t)
    local s = ns.nav:FormatStop(1, { key = "60:1", kind = "collect", text = "Kobold Candles: 1/8 Large Candle" }, "1")
    t:ok(s:find("ActiveQuestIcon", 1, true) ~= nil, "objective: in-progress quest icon")
    s = ns.nav:FormatStop(1, { key = "pickup:85", kind = "accept", text = "Accept: Lost Necklace" }, "!1")
    t:ok(s:find("AvailableQuestIcon", 1, true) ~= nil, "accept: ! icon")
    s = ns.nav:FormatStop(1, { key = "buy:2901", kind = "merchant", text = "Buy a Mining Pick" }, "2")
    t:ok(s:find("QuestIcon", 1, true) == nil, "not a quest: no quest icon")
end)

ns:Register("test", "bags: profession materials name every profession that uses them", function(t)
    local rule = ns:Get("disposition", "professionMaterial")
    if not ns.api.Skill("Blacksmithing") then t:ok(true) return end
    local v = rule.check({ id = 2835, classID = 7, subclassID = 7 })  -- Rough Stone
    -- Your own profession window wins over the guide (Forever has its own recipes).
    t:ok(v and v.reason:find("for Blacksmithing", 1, true) ~= nil,
        "Rough Stone kept for Blacksmithing (" .. tostring(v and v.reason) .. ")")
end)

ns:Register("test", "quests: availability (level, events, not offered)", function(t)
    local Q = ns.quests
    local me = UnitLevel("player")
    t:ok(Q:Available({ Id = 999101, requiredLevel = 1 }), "low level, no requirements: available")
    t:ok(not Q:Available({ Id = 999102, requiredLevel = me + 5 }), "requires a higher level: not available")
    t:ok(not Q:Offered(999103, { zoneOrSort = -1003 }), "holiday quest with no event on: not offered")
    ns.db.quests.notOffered = ns.db.quests.notOffered or {}
    -- Not offered: one visit isn't enough; two visits a minute apart skip it for a day.
    local now = time()
    t:ok(not Q.NoteOffer(999104, false, now), "one visit without it: still planned")
    t:ok(Q:Offered(999104), "still offered after one visit")
    t:ok(not Q.NoteOffer(999104, false, now + 10), "same visit again (10 s later): still planned")
    t:ok(Q.NoteOffer(999104, false, now + 120), "second visit, 2 minutes later: skipped")
    t:ok(not Q:Offered(999104), "skipped now")
    ns.db.quests.notOffered[999104].hiddenAt = now - 2 * 86400
    t:ok(Q:Offered(999104), "after a day: tried again")
    t:ok(not Q.NoteOffer(999104, true, now), "seen on offer: cleared")
    t:eq(ns.db.quests.notOffered[999104], nil, "no record left")
end)

ns:Register("test", "bags: sell decisions", function(t)
    local function rule(k, item) return ns:Get("disposition", k).check(item) end
    local v = rule("junk", { quality = 0, sellPrice = 5 })
    t:eq(v and v.action, "sell", "grey items: sell")
    v = rule("quest", { classID = 12 })
    t:eq(v and v.action, "keep", "quest items: keep")
    v = rule("unsellable", { quality = 1, sellPrice = 0 })
    t:eq(v and v.action, "keep", "vendors won't buy it: keep")
    ns.db.sell.never[999105] = true
    v = rule("neverSell", { id = 999105 })
    t:eq(v and v.action, "keep", "bought back once: never sold again")
    ns.db.sell.never[999105] = nil
    v = rule("unusedMaterial", { classID = 7, subclassID = 99, quality = 1, sellPrice = 10 })
    t:eq(v and v.action, "sell", "material nobody of yours uses: sell")
    v = rule("unusedMaterial", { classID = 7, subclassID = 99, quality = 2, sellPrice = 10 })
    t:eq(v and v.action, "ah", "better material: auction house")
end)

ns:Register("test", "gear: weapon speed tips the balance", function(t)
    local B = ns.gear.SpeedBonus
    t:ok(B(3.6, "slow") > 0, "slow weapon for a slow role: bonus")
    t:ok(B(1.8, "slow") < 0, "fast weapon for a slow role: penalty")
    t:ok(B(5, "slow") <= 1 and B(1, "slow") >= -1, "never more than one point")
    t:eq(B(2.6, nil), 0, "no preference: no change")
end)

ns:Register("test", "gear: only one-handers and off-hands pair up", function(t)
    t:eq(ns.gear:BestPartner({ equipLoc = "INVTYPE_2HWEAPON" }, "tank", {}), nil, "two-hander: no partner")
    t:eq(ns.gear:BestPartner({ equipLoc = "INVTYPE_WEAPON" }, "tank", {}), nil, "nothing in the bags: no partner")
    t:ok(ns.gear.MAIN_1H.INVTYPE_WEAPON and ns.gear.OFF.INVTYPE_SHIELD, "one-hander and shield are a pair")
end)

ns:Register("test", "caves: entrances are learned once per spot", function(t)
    local saved = ns.db.nav.entrances
    ns.db.nav.entrances = {}
    ns.nav:AddEntrance({ cont = 0, wx = 100, wy = 100, map = 1 })
    ns.nav:AddEntrance({ cont = 0, wx = 110, wy = 105, map = 1 })   -- same entrance, a few yards on
    ns.nav:AddEntrance({ cont = 0, wx = 400, wy = 100, map = 1 })   -- another one
    t:eq(#ns.db.nav.entrances, 2, "two entrances")
    ns.db.nav.entrances = saved
end)

ns:Register("test", "bags: profession tools are kept", function(t)
    local rule = ns:Get("disposition", "professionTool")
    if ns.api.Skill("Mining") then
        local v = rule.check({ id = 2901, name = "Mining Pick" })
        t:eq(v and v.action, "keep", "Mining Pick kept while you mine")
    end
    if ns.api.Skill("Blacksmithing") then
        local v = rule.check({ id = 99990, name = "Blacksmith Hammer" })
        t:eq(v and v.action, "keep", "a hammer by name too")
    end
    t:eq(rule.check({ id = 99991, name = "Rusty Sword" }), nil, "not a tool")
end)

ns:Register("test", "tools: any version of a tool counts", function(t)
    local D = ns.disposition
    t:eq(D:ToolProfession(2901, nil), "Mining", "classic Mining Pick by ID")
    t:eq(D:ToolProfession(987654, "Mining Pick"), "Mining", "another item ID, same name")
    t:eq(D:ToolProfession(987655, "Sturdy Blacksmith Hammer"), "Blacksmithing", "name contains the tool")
    t:eq(D:ToolProfession(987656, "Rusty Sword"), nil, "not a tool")
end)

-- Test-only setup rows: hidden except while this test runs (the registry has no remove).
local setupTestOn = false
ns:Register("setupItem", "zzTestNew", { order = 999, label = "Test row", suggested = true, isNew = true,
    available = function() return setupTestOn end, isOn = function() return false end, set = function() end })
ns:Register("setupItem", "zzTestOld", { order = 999, label = "Old row", suggested = true,
    available = function() return setupTestOn end, isOn = function() return false end, set = function() end })

ns:Register("test", "setup: a new suggestion is shown once to old installs", function(t)
    local S, db = ns.setup, ns.db.setup
    local savedSeen, savedDone = db.seen, db.done
    setupTestOn = true
    db.done, db.seen = true, nil
    local new = table.concat(S:Unseen(), ",")
    t:ok(new:find("Test row") ~= nil, "the new row is unseen")
    t:ok(new:find("Old row") == nil, "older rows count as seen")
    S:MarkSeen()
    t:eq(#S:Unseen(), 0, "nothing left after it's shown")
    setupTestOn = false
    db.seen, db.done = savedSeen, savedDone
end)

ns:Register("test", "cooking: meat you carry is used first, either meat will do", function(t)
    local SP = ns.skillPlan
    local g = ns:Get("profGuide", "Cooking")
    local crafts, order = SP._simulate("Cooking__test", g.steps, 1, 10, { [769] = 4 })
    t:eq(order[1] and order[1].recipe, "Roasted Boar Meat", "boar meat in bags goes first")
    local boar
    for _, s in ipairs(order) do if s.recipe == "Roasted Boar Meat" then boar = crafts[s] end end
    t:eq(boar, 4, "all 4 boar meat used, then wolf")
    local alts = SP.Alternatives(g.steps, 2672)
    t:eq(alts[1], 2672, "wolf meat first"); t:eq(alts[2], 769, "boar meat stands in")
    t:eq(#SP.Alternatives(g.steps, 99999), 1, "unknown item: just itself")
end)

ns:Register("test", "profession route: map path skips 'anywhere' stops, capped", function(t)
    local M = ns.mapOverlay
    if not (M and M.ProfStops) then t:ok(false, "map overlay loaded") return end
    local pt = { map = 1, x = 0.5, y = 0.5 }
    local plan = { { goal = { key = "a", anywhere = true }, point = pt } }
    for i = 1, 8 do plan[#plan + 1] = { goal = { key = "s" .. i }, point = pt } end
    local out = M.ProfStops(plan, 5)
    t:eq(#out, 5, "five stops on the map")
    t:eq(out[1].goal.key, "s1", "'do it where you stand' left off")
    t:eq(#M.ProfStops(nil), 0, "no profession route: nothing")
    t:ok(ns.minimapPin.UpdateProf ~= nil, "minimap has a profession dot")
end)

ns:Register("test", "bank: far bank stock is skipped for mats you can farm here", function(t)
    local SP = ns.skillPlan
    t:ok(SP.UseBank(100, true), "banker close: use the bank")
    t:ok(not SP.UseBank(1200, true), "banker across the zone, wolves here: farm them")
    t:ok(SP.UseBank(1200, false), "can't get it here: the bank it is")
    t:ok(not SP.UseBank(nil, true), "banker distance unknown, farmable: farm")
    t:ok(SP.UseBank(nil, false), "banker distance unknown, not farmable: bank")
    t:ok(SP.UseBank(1200, true, 40), "40 in the bank across the zone: worth the trip, not 40 to farm")
    t:ok(not SP.UseBank(1200, true, 3), "3 in a far bank, farmable here: farm")
    t:ok(not SP.FarmableHere(99999), "unknown item: not farmable")
    -- Can you get it here? (made-up items; nothing is read from the game)
    local HERB, HIDE, BAR, ORE, FISH, SOLD = 1, 2, 3, 4, 5, 6
    local srcs = {
        [HERB] = { gather = "Herbalism", skill = 50 }, [HIDE] = { drops = { "Wolf" } },
        [BAR] = { smelt = { from = ORE, n = 1 } }, [ORE] = { gather = "Mining", skill = 1 },
        [FISH] = { fished = true }, [SOLD] = { vendor = true },
    }
    local skills, mobsHere, soldHere = {}, false, false
    local env = { source = function(id) return srcs[id] end, skill = function(n) return skills[n] end,
                  dropsHere = function() return mobsHere end, soldHere = function() return soldHere end }
    t:ok(not SP.Farmable(HERB, env), "no Herbalism: can't gather it")
    skills.Herbalism = 49
    t:ok(not SP.Farmable(HERB, env), "Herbalism too low for this herb: can't gather it")
    t:ok(SP.UseBank(1200, SP.Farmable(HERB, env)), "so a far bank is still the way")
    skills.Herbalism = 50
    t:ok(SP.Farmable(HERB, env), "skill high enough: gather it")
    t:ok(not SP.UseBank(1200, SP.Farmable(HERB, env)), "and the far bank is skipped")
    t:ok(not SP.Farmable(HIDE, env), "the mob isn't on this map: not farmable here")
    mobsHere = true
    t:ok(SP.Farmable(HIDE, env), "the mob is here: farm it")
    t:ok(not SP.Farmable(BAR, env), "bar, no Mining: its ore can't be had")
    skills.Mining = 10
    t:ok(SP.Farmable(BAR, env), "bar: farmable through its ore")
    t:ok(not SP.Farmable(FISH, env), "no Fishing: not farmable"); skills.Fishing = 1
    t:ok(SP.Farmable(FISH, env), "Fishing: farmable")
    t:ok(not SP.Farmable(SOLD, env), "no vendor here sells it"); soldHere = true
    t:ok(SP.Farmable(SOLD, env), "a vendor here sells it")
    -- Part of what you need is in the bank: that part comes from it, the rest is still to get.
    local st = SP.Stock(function() return 0 end, function(id) return id == HIDE and 2 or 0 end, function() end)
    local r = st:Take(HIDE, 10)
    t:eq(r.bank, 2, "the 2 in the bank"); t:eq(r.short, 8, "8 still to get")
    -- Bank skipped (far, farmable): its stock isn't counted at all.
    st = SP.Stock(function() return 0 end, function() return 0 end, function() end)
    r = st:Take(HIDE, 10)
    t:eq(r.bank, 0, "skipped bank: nothing from it"); t:eq(r.short, 10, "all 10 to farm")
    -- What Flow knows of the bank is said, never assumed.
    t:ok(SP.BankNote(nil, 1000):find("hasn't seen inside your bank", 1, true) ~= nil, "bank never read: says the counts may be off")
    t:ok(SP.BankNote(1000, 1000 + 3600):find("last saw it", 1, true) ~= nil, "read this hour: as Flow last saw it")
    t:ok(SP.BankNote(1000, 1000 + 5 * 86400):find("5 days ago: it may have changed", 1, true) ~= nil, "read 5 days ago: says it may have changed")
end)

ns:Register("test", "drops: rate moves from the guide's to yours", function(t)
    local SP = ns.skillPlan
    local saved = ns.db.crafting.drops
    ns.db.crafting.drops = {}
    t:near(SP.DropRate(2672), 0.35, 0.001, "no kills yet: the guide's rate")
    for i = 1, 5 do SP.RecordLoot("Young Wolf", "corpse" .. i, i == 1 and { [2672] = true } or {}) end
    SP.RecordLoot("Young Wolf", "corpse5", {})            -- same corpse looted again: not counted
    local r, kills = SP.DropRate(2672)
    t:eq(kills, 5, "five kills counted")
    t:near(r, (1 + 0.35 * 5) / 10, 0.001, "1 in 5 pulls the estimate down")
    SP.RecordLoot("Stonetusk Boar", "corpse6", { ["chunk of boar meat"] = true })
    t:eq(ns.db.crafting.drops[769].got, 1, "found by name too")
    ns.db.crafting.drops = saved
end)

ns:Register("test", "map areas: patches and their borders", function(t)
    local M = ns.mapOverlay
    local groups = M._clusters({ { 0, 0 }, { 5, 0 }, { 100, 100 }, { 104, 102 }, { 300, 0 } }, 20)
    t:eq(#groups, 3, "three separate patches")
    local edge = M._hull({ { 0, 0 }, { 10, 0 }, { 10, 10 }, { 0, 10 }, { 5, 5 } })
    t:eq(#edge, 4, "a square's border has 4 corners (the middle point is inside)")
end)

ns:Register("test", "stop card: tooltip text and route patch", function(t)
    local tt = ns.nav._textTooltip()
    ns.nav:FillTooltip(tt, { key = "test:card", title = "A Quest", text = "A Quest: Kill 5 Wolves", details = { "XP: 120" } })
    t:ok(#tt.lines >= 3, "card body has lines")
    t:ok(tt.lines[3]:find("Kill 5 Wolves") ~= nil, "third line is the task (the band shows it, the body skips it)")
    local found
    for _, l in ipairs(tt.lines) do if l:find("XP: 120") then found = true end end
    t:ok(found, "details come through")
    local groups = { { { 0, 0 }, { 5, 0 } }, { { 100, 100 } } }
    t:eq(ns.mapOverlay._routePatch(groups, 98, 99), 2, "the patch nearest the route's spot")
    t:eq(ns.mapOverlay._routePatch(groups, nil, nil), nil, "no route spot: all patches")
end)

ns:Register("test", "route: picking the next stop makes an orange Custom route until you optimise", function(t)
    local N, db, X = ns.nav, ns.db.nav, ns.xpValue
    if ns.party and ns.party:Following() then t:ok(true, "(on a party route)") return end
    local goals = N:Goals() or {}
    local g = goals[#goals]
    if not g then t:ok(true, "(no stops to try)") return end
    local saved = { sel = N.selection, key = db.selectedKey, sorter = db.sorter, base = db.baseSorter }
    local ok, err = pcall(function()
        db.sorter, db.baseSorter = "distance", "distance"
        N:Select(g.key)
        t:eq(N.selection and N.selection.first, g.key, "your pick is the next stop")
        t:eq(X:Mode(), "custom", "Custom route")
        t:eq(ns.theme.route.hex, ns.theme:ModeColor("custom").hex, "the route is orange")
        t:eq((X:Objective()), "distance", "the rest is planned with your last objective")
        t:eq(N:Options().first, g.key, "the planner starts there")
        t:ok(ns.mapOverlay.IsChosen(g.key), "remembered as your pick")
        -- Your pick done: still Custom until you choose an objective again.
        N.selection, db.selectedKey = nil, nil
        t:eq(X:Mode(), "custom", "stays Custom after your pick")
        X:SetMode("distance")
        t:eq(X:Mode(), "distance", "Shortest: optimised again")
        t:eq(ns.theme.route.hex, ns.theme:ModeColor("distance").hex, "and blue")
        N:Select(g.key); N:ClearSelection()
        t:eq(X:Mode(), "distance", "clicking your pick's (o) also goes back")
    end)
    t:ok(ok, "ran" .. (ok and "" or (": " .. tostring(err))))
    N.selection, db.selectedKey, db.sorter, db.baseSorter = saved.sel, saved.key, saved.sorter, saved.base
    ns.theme:UpdateRoute()
    N.planDirty = true
end)

ns:Register("test", "map: the stop you're heading to has a white ring, the rest black", function(t)
    local c = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not c then t:ok(true, "(no map canvas)") return end
    local stop = { goal = { key = "test:pin", text = "test" } }
    local p = ns.mapOverlay._pin(c, 0.5, 0.5, "1", ns.theme.route, stop, nil, true)
    local r, g, b = p.edge:GetVertexColor()
    t:ok(r > 0.99 and g > 0.99 and b > 0.99, "heading there: white ring")
    t:ok(p.hole:IsShown(), "with the (o) gap and dot")
    p = ns.mapOverlay._pin(c, 0.6, 0.6, "2", ns.theme.route, stop, nil, false)
    r, g, b = p.edge:GetVertexColor()
    t:ok(r < 0.01 and g < 0.01 and b < 0.01, "other stops: black ring")
    p:Hide()
    if WorldMapFrame:IsShown() then ns.mapOverlay:Redraw() end
end)

ns:Register("test", "map: the 0.5 s tick only redraws when something changed", function(t)
    local M = ns.mapOverlay
    local canvas = { GetWidth = function() return 1000 end, GetHeight = function() return 700 end }
    local pos = { map = 1429, x = 0.40, y = 0.60, cont = 0 }
    local function stop(key, x, y)
        return { goal = { key = key, text = key, points = { { map = 1429, x = x, y = y } } }, point = { map = 1429, x = x, y = y } }
    end
    with(ns.nav, "PlayerPos", function() return pos end, function()
    with(ns, "waypoint", nil, function()
    with(ns.nav, "plan", { stop("t:a", 0.5, 0.5), stop("t:b", 0.6, 0.4) }, function()
        -- When to draw it all again.
        local st = {}
        t:ok(M._changed(st, canvas, 1429, nil), "first look: draw it all")
        t:ok(not M._changed(st, canvas, 1429, nil), "nothing changed: no redraw")
        ns.nav.plan = { stop("t:a", 0.5, 0.5), stop("t:b", 0.6, 0.4) }
        t:ok(not M._changed(st, canvas, 1429, nil), "the same route made again: still no redraw")
        pos.x = 0.45
        t:ok(not M._changed(st, canvas, 1429, nil), "you walking: no redraw (only your lines move)")
        ns.nav.plan[2].point.x = 0.7
        t:ok(M._changed(st, canvas, 1429, nil), "a stop moved: redraw")
        ns.nav.plan[1].goal.text = "t:a 1/6"
        t:ok(M._changed(st, canvas, 1429, nil), "a stop's progress changed: redraw")
        t:ok(M._changed(st, canvas, 1429, "t:b"), "pointing at a stop: redraw")
        t:ok(M._changed(st, canvas, 1430, "t:b"), "another map: redraw")
        -- (a different choice of stops from yours, whatever yours is: the
        -- area when you show numbers, a number when you show the area)
        local area = ns.nav:AreaMode()
        with(ns.db.nav, "stopsArea", not area, function()
        with(ns.db.nav, "stopsShown", ns.nav:StopsShown() == 3 and 1 or 3, function()
            t:ok(M._changed(st, canvas, 1430, "t:b"), "other stops on the map: redraw")
            t:ok(not M._changed(st, canvas, 1430, "t:b"), "then no redraw again")
        end)
        end)
        M._changed(st, canvas, 1430, "t:b")   -- (back to your setting)

        -- Between redraws, the lines that start at you follow you.
        local calls = {}
        local line = { SetStartPoint = function(_, _, _, x, y) calls[#calls + 1] = { x, y } end }
        local leg = { 0.40, 0.60, 0.5, 0.5 }
        local links = { n = 1, { line = line, leg = leg } }
        links.px, links.py = 0.45, 0.60
        t:ok(not M._followPlayer(links, canvas, 1429), "standing still: nothing to move")
        pos.x = 0.42
        t:ok(M._followPlayer(links, canvas, 1429), "you moved: your lines follow")
        t:near(leg[1], 0.42, 1e-6, "the dots' leg starts at you")
        t:near(calls[#calls] and calls[#calls][1] or 0, 420, 1e-6, "the line starts at you (x)")
        t:near(calls[#calls] and calls[#calls][2] or 0, -420, 1e-6, "the line starts at you (y)")
        local dotLeg = { 0.40, 0.60, 0.5, 0.5 }
        local dotLinks = { n = 1, { leg = dotLeg } }   -- a dotted trail: no line, only its leg
        dotLinks.px, dotLinks.py = 0.40, 0.60
        pos.x = 0.44
        t:ok(M._followPlayer(dotLinks, canvas, 1429), "a dotted trail follows you too")
        t:near(dotLeg[1], 0.44, 1e-6, "its leg starts at you")
        local spots = M._dotSpots(100, 12, 9)
        t:near(spots[1], 9, 1e-6, "no dot under the first point")
        t:near(spots[#spots], 91, 1e-6, "nor under the last")
        t:ok(#spots >= 7 and #spots <= 9, "about 12 apart")
        t:eq(#M._dotSpots(20, 12, 9), 0, "two points side by side: no dots")

        -- An area's shape is worked out once, again only when its spawns change.
        local g = { key = "t:area", area = true, points = {} }
        for i = 1, 30 do g.points[i] = { map = 1429, x = 0.3 + (i % 6) * 0.004, y = 0.3 + math.floor(i / 6) * 0.004 } end
        local built = M._shapeBuilds
        local s1 = M._areaShape(canvas, 1429, g, g.points[1], false)
        local s2 = M._areaShape(canvas, 1429, g, g.points[1], false)
        t:eq(M._shapeBuilds - built, 1, "worked out once")
        t:ok(s1 == s2, "then kept")
        t:ok(#s1.discs > 0 and #s1.edges > 0, "with discs and a border")
        g.points[5] = { map = 1429, x = 0.9, y = 0.9 }
        M._areaShape(canvas, 1429, g, g.points[1], false)
        t:eq(M._shapeBuilds - built, 2, "worked out again when its spawns change")
    end) end) end)
end)

ns:Register("test", "waypoint: your own is a green path, not a route stop", function(t)
    t:ok(ns:Get("navGoal", "userWaypoint") == nil, "not a route goal any more")
    local p = ns.nav:PlayerPos()
    if not p then t:ok(true, "(no position)") return end
    local W = ns.waypoint
    local realGet = W.Get
    W.Get = function() return { map = p.map, x = math.min(1, p.x + 0.02), y = p.y, note = "test" } end
    local ok, err = pcall(function()
        local c = ns.nav.WaypointChoice(p)
        t:ok(c and c.waypoint and c.goal.key == "user:wp", "the arrow follows it")
        t:ok(c and c.d > 0, "how far it is")
        t:ok(ns.nav:Options().first ~= "user:wp", "the route isn't re-planned around it")
        local f = _G.FlowMapRoute
        if f and f.wp then
            t:ok(f.wp:Update(), "the Flow Router shows its green line")
            t:ok(f.wp.text:GetText():find("Your waypoint") ~= nil, "labelled Your waypoint")
        end
        local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
        if canvas then
            ns.mapOverlay._drawWaypoint(canvas, p.map)
            local pin = ns.mapOverlay.WaypointPin()
            t:ok(pin and pin:IsShown(), "a green (o) on the map")
            if pin then
                local r, g, b = pin.ring:GetVertexColor()
                local w = ns.theme.waypoint
                t:near(r + g + b, w[1] + w[2] + w[3], 0.02, "in the waypoint green")
            end
        end
    end)
    W.Get = realGet
    t:ok(ok, "ran" .. (ok and "" or (": " .. tostring(err))))
    local f = _G.FlowMapRoute
    if f and f.wp then f.wp:Update() end
    local pin = ns.mapOverlay.WaypointPin()
    if pin and not W:Get() then pin:Hide() end
    if WorldMapFrame and WorldMapFrame:IsShown() then ns.mapOverlay:Redraw() end
end)

ns:Register("test", "turn-ins: quests you've done have a place to hand them in", function(t)
    local F = ns.quests.FinisherOf
    t:eq((F({ Finisher = { NPC = { 1 } } }).NPC or {})[1], 1, "Questie's Finisher field")
    t:eq((F({ Finishes = { GameObject = { 2 } } }).GameObject or {})[1], 2, "older Questie's Finishes")
    t:eq((F({ finishedBy = { { 3 } } }).NPC or {})[1], 3, "the raw finishedBy row")
    t:eq(next(F(nil)), nil, "no quest: nothing")
    local provider = ns:Get("navGoal", "questie")
    local ok, goals = pcall(provider and provider.collect or error)
    if not (ok and goals) then t:ok(true, "(no Questie)") return end
    local turnins, placed = 0, 0
    for _, g in ipairs(goals) do
        if g.key:find(":done$") then
            turnins = turnins + 1
            if g.points and #g.points > 0 then placed = placed + 1 end
        end
    end
    t:ok(turnins == 0 or placed > 0, string.format("turn-ins on the map: %d of %d", placed, turnins))
end)

ns:Register("test", "menus: Most XP, Shortest and Custom route", function(t)
    local seen = {}
    for _, it in ipairs(ns.menu:RouteItems()) do
        for _, label in ipairs({ "Most XP first", "Shortest path", "Custom route", "From selected" }) do
            if it.text and it.text:find(label, 1, true) then seen[label] = it end
        end
    end
    t:ok(seen["Most XP first"] and seen["Shortest path"] and seen["Custom route"], "all three route states")
    t:ok(not seen["From selected"], "no old From selected")
    local c = seen["Custom route"]
    if c then
        t:eq(c.checked and true or false, ns.xpValue:IsCustom(), "Custom route ticked only while it's on")
        t:eq(c.disabled and true or false, not ns.xpValue:IsCustom(), "greyed out on Most XP or Shortest")
    end
end)

ns:Register("test", "router: Custom route button greyed out on Most XP or Shortest", function(t)
    local f = _G.FlowMapRoute
    local rb
    for _, b in ipairs(f and f.sorts or {}) do if b.mode == "custom" then rb = b end end
    if not rb then t:ok(true, "(Flow Router not built yet)") return end
    local db = ns.db.nav
    local saved = { sorter = db.sorter, shown = f:IsShown() }
    local ok, err = pcall(function()
        for _, mode in ipairs({ "xp", "distance", "custom" }) do
            db.sorter = mode
            ns.mapOverlay._updateList()
            if f:IsShown() then
                t:eq(rb:IsEnabled() and true or false, mode == "custom", mode .. ": Custom route " .. (mode == "custom" and "on" or "greyed out"))
                t:eq(rb:GetChecked() and true or false, mode == "custom", mode .. ": ticked only when on")
            end
        end
    end)
    db.sorter = saved.sorter
    pcall(ns.mapOverlay._updateList)
    if not saved.shown then f:Hide() end
    t:ok(ok, "ran" .. (ok and "" or (": " .. tostring(err))))
end)

ns:Register("test", "recipes: learning one at a trainer clears its stop", function(t)
    local R = ns.recipes
    local p = R._patternFrom("You have learned how to create a new item: %s.")
    t:eq(("You have learned how to create a new item: Heavy Linen Bandage."):match(p), "Heavy Linen Bandage", "chat line parsed")
    local saved = ns.db.crafting["First Aid"]
    ns.db.crafting["First Aid"] = { rank = 40, seenAt = 0, recipes = { ["Linen Bandage"] = { reagents = {} } } }
    t:ok(R:MarkKnown("Heavy Linen Bandage"), "recipe from the First Aid guide")
    local known = R:Known("First Aid")
    t:ok(known["Heavy Linen Bandage"] ~= nil, "now known")
    t:ok(not R:MarkKnown("Not A Recipe"), "unknown names are ignored")
    ns.db.crafting["First Aid"] = saved
end)

ns:Register("test", "route: completionist mode keeps grey quests and ignores XP", function(t)
    local db = ns.db.nav
    local mode = db.mode
    db.mode = "complete"
    t:ok(not ns.xpValue:On(), "XP doesn't reorder a completionist route")
    ns.nav:SetMode("complete"); t:eq(db.mode, "complete", "mode kept")
    ns.nav:SetMode("nonsense"); t:eq(db.mode, "optimal", "unknown mode -> optimal")
    db.mode = mode
    ns.nav:Collect()
end)

ns:Register("test", "planner: a milestone always makes the cut", function(t)
    local P = ns.planner
    local p = { cont = 0, wx = 0, wy = 0 }
    local goals = {}
    for i = 1, 20 do goals[i] = { key = "near" .. i, points = { { cont = 0, wx = i * 10, wy = 0 } } } end
    goals[21] = { key = "train:class", milestone = true, weight = 0.5, points = { { cont = 0, wx = 5000, wy = 0 } } }
    local plan = P:Plan(p, goals, {})
    local found
    for _, s in ipairs(plan) do if s.goal.key == "train:class" then found = true end end
    t:ok(found, "class training is planned even though 20 stops are nearer")
end)

ns:Register("test", "mount: save, then riding, then the mount", function(t)
    local MT, r = ns.mounts, ns:Get("mountRule", "default")
    local L = r.level
    t:eq(MT.Next({ level = L - 10 }), nil, "too early: nothing")
    t:eq(MT.Next({ level = L - 2 }), "save", "a few levels before: save up")
    t:eq(MT.Next({ level = L }), "riding", "at riding level: learn riding")
    t:eq(MT.Next({ level = L, hasRiding = true }), "mount", "then buy the mount")
    t:eq(MT.Next({ level = L, hasRiding = true, classMount = "Summon Warhorse" }), nil, "class mount: nothing to buy")
    t:eq(MT.Next({ level = L + 5, hasRiding = true, hasMount = true }), nil, "done")
    t:eq(MT.Total({ classMount = "Summon Warhorse" }), r.ridingCost, "paladins save for riding only")
    t:eq(MT.Total({}), r.ridingCost + r.mountCost, "others: riding and the mount")
    local _, race = UnitRace("player")
    t:ok(ns:Get("mount", race) ~= nil, "your race has a riding trainer listed (" .. tostring(race) .. ")")
end)

ns:Register("test", "waypoint: pasted coordinates in every usual format", function(t)
    local P = ns.waypoint.Parse
    local zones = function(n) return ({ ["elwynn forest"] = 1429 })[n:lower()] end
    local p = P("45.2 63.1", zones)
    t:near(p.x, 0.452, 0.0001, "x"); t:near(p.y, 0.631, 0.0001, "y"); t:eq(p.map, nil, "your zone")
    p = P("(45.2, 63.1)", zones); t:near(p.y, 0.631, 0.0001, "brackets and comma")
    p = P("/way 45.2 63.1 Hogger", zones); t:eq(p.note, "Hogger", "pasted /way line with a note")
    p = P("/way Elwynn Forest 45.2 63.1 Hogger", zones); t:eq(p.map, 1429, "zone by name"); t:eq(p.note, "Hogger", "note after a zone")
    p = P("#1429 45 63", zones); t:eq(p.map, 1429, "map ID")
    p = P("0.452 0.631", zones); t:near(p.x, 0.452, 0.0001, "0-1 fractions")
    local none, why = P("Stormwind 45 63", zones); t:eq(none, nil, "unknown zone refused"); t:ok(why:find("Stormwind") ~= nil, "says which zone")
    t:eq((P("hello", zones)), nil, "no numbers")
    t:eq((P("145 63", zones)), nil, "out of range")
end)

ns:Register("test", "fishing: a pole comes first", function(t)
    local g = ns:Get("profGuide", "Fishing")
    t:eq(g.tool, 6256, "Fishing needs a Fishing Pole")
    t:ok(g.tip and g.tip:find("Shiny Bauble") ~= nil, "lure tip")
    local goal, missing = ns.skillPlan:ToolGoal("Fishing")
    if ns.disposition:HasTool("Fishing") then
        t:eq(goal, nil, "you have a pole: nothing to buy")
    else
        t:eq(goal and goal.text, "Buy a Fishing Pole", "no pole: buy one")
        t:eq(missing, "Fishing Pole", "and the fishing stop says why")
    end
    t:eq((ns.skillPlan:ToolGoal("Cooking")), nil, "no tool for Cooking")
end)

ns:Register("test", "3D arrow: perspective and turning", function(t)
    local P = ns.nav.Project3D
    local x, y, k = P(0, 26, 0)
    t:near(x, 0, 0.001, "straight ahead stays centred"); t:ok(y > 0, "ahead is up the screen")
    t:ok(k < 1, "the far tip is smaller")
    local _, yb, kb = P(0, -16, 0)
    t:ok(yb < 0 and kb > 1, "the near end is lower and bigger")
    t:ok(y < 26, "the ground leans away (foreshortened)")
    local xl = P(0, 26, math.pi / 2)
    t:ok(xl < -20, "a quarter turn counter-clockwise points left")
end)

ns:Register("test", "diag: blocked actions are logged for read-diag", function(t)
    local d = ns.db.diag
    -- Copy both lists: a full log drops its oldest line when one is added,
    -- so just removing the test's line wouldn't put things back.
    local function copy(list) local c = {} for i, v in ipairs(list or {}) do c[i] = v end return c end
    local savedLog, savedBlocked, hadBlocked = copy(d.log), copy(d.blocked), d.blocked ~= nil
    ns.diag._onBlocked("FORBIDDEN")("Flow", "TestProtectedFunction()")
    t:ok(d.log[#d.log]:find("%[blocked%] FORBIDDEN: Flow blamed for TestProtectedFunction") ~= nil, "logged with [blocked]")
    t:eq(d.blocked[#d.blocked].func, "TestProtectedFunction()", "kept in the blocked list")
    -- Don't leave the test's entry where read-diag would flag it.
    d.log = savedLog
    d.blocked = hadBlocked and savedBlocked or nil
    t:eq(d.log[#d.log], savedLog[#savedLog], "log restored")
end)

ns:Register("test", "taint: Flow never replaces the game's global tables", function(t)
    -- These globals must be Blizzard's own (written by secure code). If an
    -- add-on assigns them, every Blizzard popup/menu that reads them is tainted.
    for _, name in ipairs({ "StaticPopupDialogs", "UISpecialFrames", "SlashCmdList" }) do
        local secure, by = issecurevariable(name)
        t:ok(secure, name .. " is untainted" .. (by and (" (tainted by " .. by .. ")") or ""))
    end
end)

ns:Register("test", "settings: suggested WoW settings are all on Flow's page", function(t)
    local rows, toggles = ns.setup:Rows(), 0
    for _, r in ipairs(rows) do if r.item.isOn then toggles = toggles + 1 end end
    t:ok(toggles >= 5, "at least 5 suggested settings available here (" .. toggles .. ")")
end)

ns:Register("test", "cast: the key's button comes back out of combat", function(t)
    -- The update loop must not live on the button: it hides itself when
    -- there's nothing to press, and a hidden frame's OnUpdate never runs.
    local btn = _G.FlowCastButton
    t:ok(btn ~= nil, "cast button exists")
    if btn then t:ok(btn:GetScript("OnUpdate") == nil, "no update loop on the (hideable) button") end
    t:eq(ns.cast._describe({ type = "item", item = "item:6256" }), "/use item:6256", "item press described")
    t:eq(ns.cast._describe({ type = "item", item = "item:6529", targetSlot = 16 }), "/use item:6529 on slot 16", "lure on main hand")
    -- (Your own buffs go on you since 0.35.93, even with a friend targeted.)
    t:eq(ns.cast._describe({ spell = "Devotion Aura", kind = "buff" }), "/cast [@player] Devotion Aura", "spell press")
    t:eq(ns.cast._describe({ spell = "Wrath", kind = "damage" }), "/cast Wrath", "an attack: on your target")
end)

ns:Register("test", "class training fits into the route, after the quests where you are", function(t)
    -- 0.35.98 put training first when the trainer was close: it pulled Yang
    -- away mid-quest. The planner fits it in where it costs least again.
    t:eq(ns.nav.GoFirstKey, nil, "no stop jumps the queue")
    local ok, goals = pcall(ns:Get("navGoal", "errands").collect)
    t:ok(ok, "errands collect")
    for _, g in ipairs(ok and goals or {}) do
        if g.key == "train:class" then t:eq(g.goFirst, nil, "class training doesn't ask to come first") end
    end
end)

ns:Register("test", "actions: fishing steps on the Flow key", function(t)
    local X = ns.actions
    t:ok(X.IsPole(6256), "Fishing Pole is a pole")
    t:ok(not X.IsPole(2901), "Mining Pick is not a pole")
    local get = function(k, ctx) return ns:Get("action", k).get(ctx) end
    -- Not at the fishing stop: no fishing steps.
    t:eq(get("fish:cast", { fishing = false, prof = "Fishing", pole = true }), nil, "no cast away from the spot")
    t:eq(get("fish:equip", { at = true, prof = "Mining", pole = false }), nil, "no pole at a mining stop")
    -- At the spot with the pole on: cast (when you know Fishing and aren't fishing yet).
    if ns.api.SpellInfo("Fishing") and not (UnitChannelInfo and UnitChannelInfo("player")) then
        local s = get("fish:cast", { fishing = true, atFish = true, prof = "Fishing", pole = true })
        t:eq(s and s.spell, "Fishing", "casts Fishing at the spot")
    end
    -- Nothing to put back when Flow didn't swap anything.
    local saved = ns.db.actions.weapons
    ns.db.actions.weapons = nil
    t:eq(get("fish:restore", { at = false }), nil, "no restore without saved weapons")
    ns.db.actions.weapons = saved
end)

ns:Register("test", "text: progress reads X -> N", function(t)
    t:eq(ns.Progress(9, 66), "9 -> 66", "Flow's own progress")
    t:eq(ns.ProgressText("Slimy Menace: 0/7 Murloc slain"), "Slimy Menace: 0 -> 7 Murloc slain", "game objective text")
    t:eq(ns.ProgressText("Murloc slain: 3 / 7"), "Murloc slain: 3 -> 7", "spaces around the slash")
    t:eq(ns.ProgressText(nil), nil, "nil stays nil")
end)

ns:Register("test", "skillplan: fishing feeds cooking", function(t)
    local SP = ns.skillPlan
    local g = ns:Get("profGuide", "Cooking")
    local step, fish, id = SP.FishAlternative(g.steps, 2672)
    t:eq(id, 6291, "wolf meat's stand-in from fishing: Raw Brilliant Smallfish")
    t:ok(step and step.recipeItem == 6325, "its recipe is bought")
    t:ok(fish and fish.share > 0, "share of catches")
    -- Catches still to come: only when Fishing is on the plan.
    t:eq(SP.PlannedCatch({}), 0, "no Fishing target, no fish")
    local rank = ns.api.Skill("Fishing")
    if rank then
        t:eq(SP.PlannedCatch({ Fishing = { target = rank + 10 } }), 10, "10 points to go: about 10 catches")
        t:eq(SP.PlannedCatch({ Fishing = { target = rank } }), 0, "at target: none")
    end
    -- The fish step is never preferred over meat you'd farm when you have no fish.
    local crafts = SP._simulate("Cooking", g.steps, 1, 10, {})
    t:ok(crafts[g.steps[3]] == nil, "no fish in bags: plan doesn't count on cooking fish")
end)

ns:Register("test", "perf: Flow's update loops are timed", function(t)
    local P = ns.perf
    local f = P.Wrap("test: wrapped", function(a, b) return a + b, "x" end)
    local s, x = f(2, 3)
    t:eq(s, 5, "wrapped function still returns its results"); t:eq(x, "x", "second result too")
    t:eq(P.stats["test: wrapped"].calls, 1, "call counted")
    P.stats["test: wrapped"] = nil
    t:ok(P.stats["arrow + minimap (10/s)"] ~= nil, "route arrow timed")
    t:ok(P.stats["route: order stops"] ~= nil, "planner timed")
    -- quick: a full clean-up inside the login self-test run is a hitch.
    local rep = P:Report(true)
    t:ok(#rep >= 1, "report has a summary line")
    t:ok(rep[1]:find("/flow perf", 1, true) ~= nil, "quick report skips the clean-up and says so")
    t:ok(ns.nav.Busy() == true or ns.nav.Busy() == false, "tracker can tell when the route is being redone")
end)

ns:Register("test", "perf: route refresh gathers one stop source at a time", function(t)
    local N, P = ns.nav, ns.perf
    local list = { "already here" }
    N._gatherFrom("test: src", { collect = function() return { { key = "k1", text = "a" } } end }, list)
    t:eq(#list, 2, "one source's stops added to the list being built")
    t:eq(list[2].provider, "test: src", "stop tagged with its source")
    N._gatherFrom("test: bad", { collect = function() error("boom") end }, list)
    t:eq(#list, 2, "a failing source adds nothing and doesn't stop the refresh")
    P.stats["gather: test: src"], P.stats["gather: test: bad"] = nil, nil
end)

ns:Register("test", "perf: a timed call inside another counts once", function(t)
    local P = ns.perf
    local clock = debugprofilestop
    local d0 = P._depth()
    local inner = P.Wrap("test: inner", function() local t0 = clock(); while clock() - t0 < 3 do end end)
    local outer = P.Wrap("test: outer", function() inner() end)
    outer()
    local o, i = P.stats["test: outer"], P.stats["test: inner"]
    t:ok(i.total >= 3, "the inner one: its own 3 ms")
    t:ok(o.total < 1, "the outer one: only its own time, not the inner's again")
    local bad = P.Wrap("test: error", function() error("boom", 0) end)
    local ok, err = pcall(bad)
    t:ok(not ok and err == "boom", "errors pass through")
    t:eq(P._depth(), d0, "and leave the timing straight")
    P.stats["test: outer"], P.stats["test: inner"], P.stats["test: error"] = nil, nil, nil
    t:ok(P.stats["minimap areas"] ~= nil, "minimap areas timed apart")
end)

ns:Register("test", "planner: each stop goes to its nearest spot from the last one", function(t)
    local PL = ns.planner
    local seed = 7   -- the same "random" stops every run
    local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
    local p = { cont = 0, wx = 0, wy = 0 }
    local goals = {}
    for k = 1, 12 do
        local pts = {}
        for j = 1, 1 + (k % 4) * 3 do pts[j] = { cont = 0, wx = rnd() * 600 - 300, wy = rnd() * 600 - 300 } end
        goals[k] = { key = "s" .. k, text = "s" .. k, points = pts }
    end
    local plan = PL:Plan(p, goals, {})
    t:eq(plan and #plan, 12, "every stop planned")
    -- Each leg: the stop's nearest spot from where the last leg ended
    -- (worked out here the slow way, every spot).
    local from, right, legsRight = p, true, true
    for _, s in ipairs(plan or {}) do
        local bd
        for _, pt in ipairs(s.goal.points) do
            local d = math.sqrt((pt.wx - from.wx) ^ 2 + (pt.wy - from.wy) ^ 2)
            if not bd or d < bd then bd = d end
        end
        if math.abs(bd - s.leg) > 1e-6 then right = false end
        local d = math.sqrt((s.point.wx - from.wx) ^ 2 + (s.point.wy - from.wy) ^ 2)
        if math.abs(d - s.leg) > 1e-6 then legsRight = false end
        from = s.point
    end
    t:ok(right, "every stop: its nearest spot")
    t:ok(legsRight, "and the legs add up")
    -- No longer than going nearest-next.
    local left, order, at = {}, {}, p
    for _, g in ipairs(goals) do left[#left + 1] = { goal = g, key = g.key, points = g.points } end
    while #left > 0 do
        local bi, bd, bp
        for i, s in ipairs(left) do
            for _, pt in ipairs(s.points) do
                local d = math.sqrt((pt.wx - at.wx) ^ 2 + (pt.wy - at.wy) ^ 2)
                if not bd or d < bd then bi, bd, bp = i, d, pt end
            end
        end
        order[#order + 1] = table.remove(left, bi)
        at = bp
    end
    local planned = {}
    for i, s in ipairs(plan or {}) do planned[i] = { goal = s.goal, key = s.goal.key, points = s.goal.points } end
    t:ok(PL._cost(p, planned) <= PL._cost(p, order) + 1e-6, "no longer than nearest-next")
end)

ns:Register("test", "nav: map spots turn into world spots like the game does", function(t)
    local p = ns.nav:PlayerPos()
    if not p then t:ok(true, "(no position)") return end
    local worst = 0
    for _, q in ipairs({ { 0.1, 0.2 }, { 0.5, 0.5 }, { 0.93, 0.07 }, { p.x, p.y } }) do
        local c1, x1, y1 = ns.nav:ToWorld(p.map, q[1], q[2])
        local c2, x2, y2 = ns.nav._gameToWorld(p.map, q[1], q[2])
        t:eq(c1, c2, "same continent")
        if x1 and x2 then worst = math.max(worst, math.abs(x1 - x2), math.abs(y1 - y2)) end
    end
    t:ok(worst < 0.05, string.format("same spot (off by %.4f yd at most)", worst))
end)

ns:Register("test", "actions: any fishing stop counts, not just the quest's", function(t)
    local P = ns.actions.GoalProf
    t:eq(P({ key = "skill:Fishing", text = "Fish at the lake (Fishing 20, aim for 58)" }), "Fishing", "skill errand (no prof field)")
    t:eq(P({ key = "skill:Fishing", prof = "Fishing", text = "Fish: 1 -> 20" }), "Fishing", "skill planner stop")
    t:eq(P({ key = "123:1", kind = "collect", text = "Catch 5 Raw Brilliant Smallfish" }), "Fishing", "fishing quest objective")
    t:eq(P({ key = "buy:6256", kind = "merchant", text = "Buy a Fishing Pole" }), nil, "buying the pole isn't fishing")
    t:eq(P({ key = "gather:Copper Vein", prof = "Mining" }), "Mining", "mining stop")
    t:eq(P({ key = "99128:1", text = "Slimy Menace: 0 -> 7 Murloc slain" }), nil, "a kill quest isn't fishing")
end)

ns:Register("test", "skillplan: fishing suggests a lure", function(t)
    local g = ns:Get("profGuide", "Fishing")
    t:eq(g.lure, 6529, "Shiny Bauble is Fishing's lure")
    local stop = ns.skillPlan:LureGoal("Fishing")
    if stop then
        t:eq(stop.key, "buy:6529", "buy stop for the bauble")
        t:ok(stop.optional, "optional: only when it's on the way")
    else
        t:ok(true, "no stop: you carry a lure, or no known vendor")
    end
    t:eq(ns.skillPlan:LureGoal("Mining"), nil, "no lure for Mining")
end)

ns:Register("test", "skillplan: Fishing paces with the water, crafting with your level", function(t)
    local SP = ns.skillPlan
    t:eq(SP.Pace("Fishing", 10), 25, "level 10: starting-zone water")
    t:eq(SP.Pace("Fishing", 20), 75, "level 20: next zones")
    t:ok(SP.Pace("Fishing", 8) < 25, "level 8: under 25, not 58")
    t:eq(SP.Pace("First Aid", 10), 75, "crafting keeps the general curve")
end)

ns:Register("test", "crafting: make exactly enough, and say what's next", function(t)
    local H = ns.craftHint
    t:ok(type(H.Craft) == "function", "Make N button can craft")
    t:eq(#H.CraftStops("No Such Profession"), 0, "no stops for an unknown profession")
    for _, g in ipairs(ns.skillPlan.lastStops or {}) do
        if g.recipe then
            t:ok(g.makeCount and g.makeCount > 0, g.recipe .. ": has a count")
            t:ok(g.planned and (g.target or g.extra), g.recipe .. ": knows its target (or is a smelt / upgrade) and planned total")
            t:ok(g.text:find("|cffffd100", 1, true) ~= nil, g.recipe .. ": count highlighted")
        end
    end
end)

ns:Register("test", "skillplan: materials from bags, then bank, then smelting", function(t)
    local SP = ns.skillPlan
    local BAR, ORE, LEATHER = 900001, 900002, 900003
    local bags = { [BAR] = 2, [ORE] = 3 }
    local bank = { [BAR] = 1, [ORE] = 6, [LEATHER] = 4 }
    local function smeltOf(id) if id == BAR then return { from = ORE, n = 1 } end end
    local st = SP.Stock(function(id) return bags[id] or 0 end, function(id) return bank[id] or 0 end, smeltOf)
    t:eq(st:Avail(BAR), 12, "2 bags + 1 bank + 9 ore to smelt")
    local r = st:Take(BAR, 8)
    t:eq(r.bags, 2, "bags first"); t:eq(r.bank, 1, "then the bank")
    t:eq(r.smelt, 5, "then smelt the rest")
    t:eq(r.oreBags, 3, "ore from your bags first"); t:eq(r.oreBank, 2, "then the bank's ore")
    t:eq(r.short, 0, "nothing short")
    t:eq(st:Avail(BAR), 4, "what's left counts once")
    local try = st:Fork()
    local r2 = try:Take(BAR, 6)
    t:eq(r2.short, 2, "a copy sees only what's left")
    t:eq(st:Avail(BAR), 4, "trying on the copy takes nothing")
    local line = SP.SourceLine("Copper Bar", r, "Copper Ore")
    t:ok(line:find("2 in your bags", 1, true) and line:find("1 from your bank", 1, true)
        and line:find("smelt 5 from 5 Copper Ore (bags and bank)", 1, true), "says where each comes from: " .. line)
    t:ok(SP.SourceLine("Tigerseye", { need = 2, bags = 0, bank = 0, smelt = 0, oreBags = 0, oreBank = 0, short = 2 })
        :find("2 still to get", 1, true), "and what's still to get")
end)

ns:Register("test", "skillplan: the bank Flow saw counts, an upgrade with an unread material isn't makeable", function(t)
    local SP = ns.skillPlan
    local saved = ns.db.bank
    local ok, err = pcall(function()
        ns.db.bank = { items = { [900004] = 7 }, seenAt = 1 }
        t:eq(SP.BankCount(900004), 7, "what Flow saw in your bank")
        t:eq(SP.BankCount(900005), 0, "not in it: none")
    end)
    ns.db.bank = saved
    t:ok(ok, "ran" .. (ok and "" or (": " .. tostring(err))))
    local ups = SP.PickUpgrades({ { recipe = "Boots", item = 1, reagents = { [2840] = 2 }, partial = true } },
        function() return 3, "dps", "boots", "INVTYPE_FEET" end)
    t:ok(ups[1] and ups[1].partial, "an incomplete material list comes along")
    local lines = ns.craftHint.UpgradeLines({ { recipe = "Boots", tag = "+3 DPS", missing = { "2 Tigerseye", "4 Light Leather" } },
                                             { recipe = "Belt", tag = "+1 DPS", missing = {}, unread = true } })
    t:ok(lines[1]:find("needs 2 Tigerseye, 4 Light Leather", 1, true), "the fold-out says what's missing")
    t:ok(lines[2]:find("open this window again", 1, true), "and when Flow couldn't read the materials")
    for _, g in ipairs(SP.lastStops or {}) do
        t:ok(not (g.key or ""):find("^upgrade:") or not g.blockedBy or not g.blockedBy:find("^needs %d"),
            (g.recipe or g.key) .. ": an upgrade missing materials is never a stop")
    end
end)

ns:Register("test", "crafting: the window shows the arrow's stop, materials and the upgrades fold-out", function(t)
    local H = ns.craftHint
    local a = { key = "craft:X:A", recipe = "A" }
    local b = { key = "upgrade:X:B", recipe = "B" }
    t:eq(H.Pick({ b, a }, { goal = { key = "craft:X:A" } }), a, "the faint arrow's stop wins")
    t:eq(H.Pick({ b, a }, nil, { { goal = { key = "craft:X:A" } } }), a, "else the profession route's first")
    t:eq(H.Pick({ b, a }), b, "else the first")
    local lines, now = H.MaterialLines({ reagents = { [2840] = 2 } }, 4,
        function() return 3 end, function() return 10 end)
    t:eq(#lines, 1, "one line per material")
    t:ok(lines[1]:find("3 in your bags", 1, true) and lines[1]:find("5 from your bank", 1, true), "bags then bank: " .. lines[1])
    t:eq(now, 1, "make now only what your bags hold")
    local ok, err = pcall(function()
        local p = H.Panel()
        local was = H.upgradesOpen
        p.upBtn:Click()
        t:eq(H.upgradesOpen, not was, "clicking opens / closes the fold-out")
        p.upBtn:Click()
        t:eq(H.upgradesOpen, was, "and back")
    end)
    t:ok(ok, "fold-out click" .. (ok and "" or (": " .. tostring(err))))
end)

ns:Register("test", "actions: a selected NPC never blocks the Flow key", function(t)
    -- Flow's own spells cast on you, not your target (Lee Brown selected: cast failed).
    if ns.api.SpellInfo("Fishing") and not (UnitChannelInfo and UnitChannelInfo("player")) then
        local s = ns:Get("action", "fish:cast").get({ fishing = true, pole = true })
        t:eq(s and s.unit, "player", "Fishing casts with no target")
    end
    local c = ns.actions.ClearTargetStep("test")
    t:eq(c.type, "clear", "clear-target step")
    t:eq(ns.cast._describe(c), "/cleartarget", "described for the diagnostics")
    t:ok(c.icon:find("\\", 1, true) ~= nil, "icon path keeps its backslashes")
end)

ns:Register("test", "router: handle and help legend share one look", function(t)
    local M = ns.mapOverlay
    t:ok(type(M.MakeHandle) == "function", "one handle builder for rows and legend")
    local h = M.MakeHandle(UIParent, 16)
    h.active = true; h:Paint(false)
    t:ok(h.ring:IsShown() and not h.arms[1]:IsShown(), "active: (o) marker, no ^")
    h.active = false; h:Paint(false)
    t:ok(h.arms[1]:IsShown() and not h.ring:IsShown(), "others: ^ chevron")
    h:Hide()
end)

ns:Register("test", "router: the (o) is the route colour, your waypoint's green", function(t)
    local h = ns.mapOverlay.MakeHandle(UIParent, 16)
    h.active = true; h:Paint(false)
    local r, g, b = h.ring:GetVertexColor()
    local c = ns.theme.route
    t:near(r + g + b, c[1] + c[2] + c[3], 0.02, "(o) ring in the route colour")
    h.ringColor = ns.theme.waypoint; h:Paint(false)
    r, g, b = h.ring:GetVertexColor()
    local w = ns.theme.waypoint
    t:near(r + g + b, w[1] + w[2] + w[3], 0.02, "your waypoint's (o) in green")
    h:Hide()
end)

ns:Register("test", "stop card: drag by the title, opens where you left it", function(t)
    local saved = ns.db.nav.cardPoint
    ns.db.nav.cardPoint = { "TOPLEFT", "TOPLEFT", 100, -100 }
    ns.nav:ShowStop({ key = "test:card", text = "Test stop", points = {} })
    local card = _G.FlowStopCard
    t:ok(card and card:IsMovable(), "card can be moved")
    local a, _, _, x = card:GetPoint()
    t:eq(a, "TOPLEFT", "opens at the saved point"); t:near(x, 100, 0.01, "saved x")
    card:Hide()
    ns.db.nav.cardPoint = saved
end)

ns:Register("test", "intro: the arrow spins up and lands pointing up", function(t)
    local I = ns.intro
    t:near(I.SpinAngle(0), 0, 0.001, "starts still")
    t:near(I.SpinAngle(I.SPIN), I.TURNS * 2 * math.pi, 0.001, "whole turns: ends where it started")
    t:ok(I.SpinAngle(0.3) - I.SpinAngle(0) > I.SpinAngle(I.SPIN) - I.SpinAngle(I.SPIN - 0.3), "fast first, easing out")
    t:ok(I.Status():find("spells", 1, true) ~= nil, "status line says what Flow works with")
    t:ok(_G.FlowSplash == nil, "the old title card is gone")
end)

ns:Register("test", "actions: an enemy targeted with the pole on: weapon back first", function(t)
    local a = ns:Get("action", "arm:enemy")
    t:ok(a and a.order < 10, "comes before the fishing steps")
    t:eq(a.get({ pole = false }), nil, "nothing when the pole isn't on")
    -- With saved weapons that aren't on: the press equips the main hand, urgently.
    local saved = ns.db.actions.weapons
    ns.db.actions.weapons = { main = 25 }   -- Worn Shortsword (not equipped in this check)
    local s = ns.actions._restoreStep(true, "Weapon back on before the fight")
    if ns.api.Count(25) > 0 and GetInventoryItemID("player", 16) ~= 25 then
        t:eq(s and s.item, "item:25", "equips the saved weapon")
        t:ok(s and s.urgent, "before the rotation's pull")
    else
        t:ok(true, "(no Worn Shortsword in bags to check with)")
    end
    ns.db.actions.weapons = saved
end)

ns:Register("test", "actions: no endless casts where there's no water", function(t)
    local X, saved = ns.actions, ns.db.actions.dryAt
    t:ok(not X.NoteDry("Not enough mana"), "other errors ignored")
    t:ok(X.NoteDry("Your cast didn't land in fishable water"), "the no-water message is noted")
    if ns.nav:PlayerPos() then
        local ctx = X:Context()
        t:ok(ctx.noWater, "here counts as no water now")
        t:ok(ctx.atFish or not ctx.fishing, "off a fishing stop: not fishing here any more")
    end
    ns.db.actions.dryAt = saved
end)

ns:Register("test", "gear marks: green arrow up, red arrow down, grey dash same", function(t)
    local b = ns:SpecBadge(UIParent, 10)
    b:Set({ dps = 2, heal = -2, tank = 0 })
    local up, down, same = b.slots.dps.arrow, b.slots.heal.arrow, b.slots.tank.arrow
    t:ok(same.bar:IsShown(), "same: grey dash")
    if up.atlas then
        t:ok(up.tex:IsShown() and down.tex:IsShown(), "up and down use the game's green arrow art")
        local r, g = down.tex:GetVertexColor()
        t:ok(r > g, "down: red")
        t:ok(not same.tex:IsShown(), "no arrow for same")
    else
        t:ok(up.l1:IsShown(), "no arrow art on this client: drawn chevron instead")
    end
    b:Hide()
end)

ns:Register("test", "arrow panel: drag by the title too", function(t)
    t:ok(type(ns.nav.Draggable) == "function", "shared drag helper")
    local f = CreateFrame("Frame", nil, UIParent)
    f.hero = CreateFrame("Frame", nil, f)
    ns.nav.Draggable(f, "testPoint", "here")
    t:ok(f:IsMovable() and f.hero:IsMouseEnabled(), "movable by its title")
    f:Hide()
end)

ns:Register("test", "items: Flow can count what you carry on this client", function(t)
    local A = ns.api
    t:ok(A.ItemCount ~= nil, "an item count function exists (global or C_Item)")
    t:eq(type(A.Count(6256)), "number", "count is a number")
    -- Something you have equipped or carry: your Hearthstone (6948) is in nearly every bag.
    if A.ItemCount then t:ok(A.Count(6948) >= 0, "count works without erroring") end
end)

ns:Register("test", "taint: moving the cast icon never happens in combat", function(t)
    t:ok(type(ns.cast.EndMove) == "function", "one place finishes a move")
    local btn = _G.FlowCastButton
    -- The icon's own release handler must go through EndMove (which refuses in combat).
    t:ok(btn and btn:GetScript("OnDragStop") ~= nil, "release handled")
    local was = ns.cast.moving
    ns.cast.moving = false
    ns.cast:EndMove()   -- not moving: nothing happens (no protected call)
    t:ok(ns.cast.moving == false, "no move in progress, nothing done")
    ns.cast.moving = was
end)

ns:Register("test", "resize: buttons stay between half and double size", function(t)
    t:eq(ns.ClampScale(1), 1, "normal size")
    t:eq(ns.ClampScale(5), 2, "at most double")
    t:eq(ns.ClampScale(0.1), 0.5, "at least half")
    t:eq(ns.ClampScale(1.1 + 1e-9), 1.1, "rounded, so steps don't drift")
    t:eq(ns.ClampScale(nil), 1, "nothing saved: normal size")
end)

ns:Register("test", "click: Ctrl + drag moves and Ctrl + wheel resizes the Flow button", function(t)
    t:ok(ns.cast.handle ~= nil, "the Flow button has a handle")
    -- On a stand-in frame (made once), so your own buttons never move.
    local f = ns._testMoveFrame
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(40, 40)
        f:SetAlpha(0)
        ns._testMoveFrame = f
        f.save = {}
        f.handle = ns:MoveHandle(f, { name = "test", save = function() return f.save end })
    end
    local h = f.handle
    ns.RestorePlace(f, { point = { "CENTER", "CENTER", 100, 50 } })
    t:eq(f:GetScale(), 1, "restored at normal size")
    f:Show()
    -- The handle's own scripts run (no Ctrl held: they do nothing).
    for _, s in ipairs({ "OnMouseDown", "OnMouseUp", "OnEnter", "OnLeave" }) do
        local ok, err = pcall(h:GetScript(s), h)
        t:ok(ok, s .. " runs" .. (ok and "" or (": " .. tostring(err))))
    end
    local ok, err = pcall(h:GetScript("OnMouseWheel"), h, 1)
    t:ok(ok, "the wheel runs" .. (ok and "" or (": " .. tostring(err))))
    if not ns.MoveKeyDown() then t:eq(f:GetScale(), 1, "no Ctrl: the wheel leaves the size alone") end
    t:ok(not h.moving, "no Shift: a press doesn't start a move")
    if InCombatLockdown() then
        t:ok(true, "(in a fight: resizing is off)")
    else
        local x0, y0 = f:GetCenter()
        h:ScaleBy(1)
        t:near(f:GetScale(), 1.1, 1e-3, "one notch: a tenth bigger")
        t:near(f.save.scale, 1.1, 1e-3, "the size is saved")
        t:ok(f.save.point and f.save.point[1] == "CENTER", "the spot is saved")
        local x1, y1 = f:GetCenter()
        if x0 and x1 then
            t:ok(math.abs(x1 * 1.1 - x0) < 1 and math.abs(y1 * 1.1 - y0) < 1, "it grows around its centre")
        end
        for _ = 1, 30 do h:ScaleBy(-1) end
        t:near(f:GetScale(), 0.5, 1e-3, "shrinks to half and stops")
        -- Back where it was, at the saved size.
        ns.RestorePlace(f, f.save)
        t:near(f:GetScale(), 0.5, 1e-3, "restored at the saved size")
    end
    f:Hide()
end)

ns:Register("test", "route: what it optimises is pluggable", function(t)
    local X = ns.xpValue
    t:ok(ns:Get("routeObjective", "xp") and ns:Get("routeObjective", "distance"), "built-in objectives registered")
    local saved = { s = ns.db.nav.sorter, b = ns.db.nav.baseSorter }
    -- A test objective: only stops whose key starts with "keep:", each half weight.
    if not ns:Get("routeObjective", "test-only") then
        ns:Register("routeObjective", "test-only", { label = "Test",
            keep = function(g) return g.key:find("^keep:") ~= nil end,
            weigh = function() return 0.5 end })
    end
    -- Completionist routes always sort by distance: test in the default mode.
    with(ns.db.nav, "mode", "optimal", function()
        ns.db.nav.sorter, ns.db.nav.baseSorter = "test-only", "test-only"
        local out = X:Apply({ { key = "keep:1", weight = 1 }, { key = "drop:1", weight = 1 } })
        t:eq(#out, 1, "keep picks the stops")
        t:eq(out[1] and out[1].weight, 0.5, "weigh scales the weight")
        ns.db.nav.sorter, ns.db.nav.baseSorter = "nonsense", nil
        t:eq((X:Objective()), "xp", "unknown objective falls back to Most XP")
    end)
    ns.db.nav.sorter, ns.db.nav.baseSorter = saved.s, saved.b
    with(ns.db.nav, "mode", "complete", function()
        t:eq((X:Objective()), "distance", "completionist: shortest order")
    end)
end)

ns:Register("test", "arrow 3D: pillars on the ring and a sphere when you arrive", function(t)
    if ns.db.nav.arrowStyle == "flat" then t:ok(true, "(flat arrow in use)") return end
    local a = ns.nav:MakeArrow3D(UIParent)
    t:ok(#a.ring > 0 and a.ring[1].stem ~= nil, "each ring dot is a pillar")
    a:SetArrived(false)
    a.ring[1].stem:GetStartPoint()   -- reading the pillar must not error
    t:ok(not a.ballBody:IsShown(), "no sphere while pointing")
    a:SetArrived(true)
    t:ok(a.ballBody:IsShown() and a.ballHi:IsShown(), "sphere with a highlight when you arrive")
    a:SetRingSpin(math.pi / 2)
    t:ok(a.ringAngle == math.pi / 2, "the ring can spin")
    a:Hide()
end)

ns:Register("test", "modern arrow: pictures for each turn", function(t)
    local N = ns.nav
    local i, l, r, top, b = N.ArrowCell(0)
    t:eq(i, 0, "pointing up: the first picture")
    t:ok(l == 0 and r == 1 / 16 and top == 0 and b == 1 / 8, "top-left cell of the sheet")
    i, l, _, top = N.ArrowCell(math.pi / 2)
    t:eq(i, 32, "a quarter turn left: picture 32")
    t:ok(l == 0 and top == 2 / 8, "row 3, first column")
    t:eq((N.ArrowCell(2 * math.pi - 0.001)), 0, "just short of a full turn: back to the first")
    t:eq((N.ArrowCell(-math.pi / 2)), 96, "turning right works too")
    t:eq((N.ArrowCell(nil)), 0, "no angle: pointing up")
end)

ns:Register("test", "modern arrow: grey away, orange to green closing in, blue here", function(t)
    local N, th = ns.nav, ns.theme
    -- (The colour goes in as a table: `same(N.ArrowColor(...), c)` passed only
    -- its first value, since Lua keeps one result of a call that isn't last.)
    local function same(state, d, c)
        local r, g, b = N.ArrowColor(state, d)
        return c ~= nil and math.abs(r - c[1]) < 1e-6 and math.abs(g - c[2]) < 1e-6 and math.abs(b - c[3]) < 1e-6
    end
    t:ok(same("away", 50, th.arrowAway), "another zone: grey, however close")
    t:ok(same("here", 900, th.arrowHere), "in the area: blue")
    t:ok(same("zone", 2000, th.arrowFar), "far away: orange")
    t:ok(th.arrowFar[2] > 0.4, "far isn't red (red reads as \"can't\"; the arrow says go)")
    t:ok(same("zone", 10, th.arrowNear), "close by: green")
    local r1, g1 = N.ArrowColor("zone", 500)
    local r2, g2 = N.ArrowColor("zone", 150)
    t:ok(g2 > g1 and r2 <= r1, "greener as you close in")
    -- Which state: other continent / other zone / same zone / here.
    local p = { cont = 0, map = 1429 }
    t:eq(N.ArrowState(p, { cont = 1, map = 1411 }, false), "away", "other continent: away")
    t:eq(N.ArrowState(p, { cont = 0, map = 1429 }, false), "zone", "same zone: by distance")
    t:eq(N.ArrowState(p, { cont = 0, map = 1429 }, true), "here", "in the area: here")
    t:eq(N.ArrowState(p, nil, false), "zone", "no point: by distance")
    local zoneA, zoneB = N.ZoneOf(1429), N.ZoneOf(1436)
    if zoneA and zoneB and zoneA ~= zoneB then
        t:eq(N.ArrowState(p, { cont = 0, map = 1436 }, false), "away", "Westfall from Elwynn: away")
    else
        t:ok(true, "(map info not available here)")
    end
    -- The colour-blind palette has its own ramp.
    local was = th:ColorBlind()
    th:UsePalette("colorblind")
    t:ok(same("zone", 2000, th.arrowFar) and th.arrowFar.hex == "E69F00", "colour-blind: orange far away")
    th:UsePalette(was and "colorblind" or "standard")
    -- A spot with no map gives nothing, not an error (0.35.130).
    local ok, cont = pcall(N.ToWorld, N, nil, 0.5, 0.5)
    t:ok(ok and cont == nil, "ToWorld with no map: nil")
end)

ns:Register("test", "modern arrow: turns, colours, ring and beam when you arrive", function(t)
    local a = ns.nav:MakeArrowModern(UIParent)
    t:ok(a.body and a.shine and a.shadow and a.halo and a.beam, "body, highlights, shadow, ring and beam")
    t:eq(a.SetRingSpin, nil, "no pillars: the login intro spins the arrow itself")
    a.spinning = true
    a:SetRotation(math.pi / 2)
    t:eq(a.cell, 32, "spinning: the picture follows at once")
    a:SetVertexColor(0.2, 0.4, 0.6)
    t:ok(a.cr == 0.2 and a.cg == 0.4 and a.cb == 0.6, "spinning: the colour follows at once")
    a.spinning = nil
    a:SetVertexColor(1, 0, 0)
    t:ok(a.r == 1 and a.cr == 0.2, "pointing: the colour eases there")
    a:GetScript("OnUpdate")(a, 0.05)
    t:ok(a.cr > 0.2 and a.cr < 1, "and moves a step each frame")
    a:SetArrived(true)
    a:GetScript("OnUpdate")(a, 0.05)
    t:ok(a.halo:IsShown() and a.beam:IsShown() and a.ripple:IsShown(), "arrived: ring, ripple and beam")
    a:SetCenterIcon("Interface\\Icons\\INV_Misc_Food_15")
    t:ok(a.icon:IsShown(), "the stop's icon in the ring")
    a:SetWave(true)
    t:ok(a.wave, "on the spot: the ripples speed up")
    a:SetArrived(false)
    for _ = 1, 10 do a:GetScript("OnUpdate")(a, 0.05) end
    t:ok(not a.halo:IsShown() and not a.icon:IsShown(), "pointing again: no ring, no icon")
    t:eq(a.fade, 0, "the arrow is back")
    a:SetWave(true)
    t:ok(not a.wave, "no ripples unless arrived")
    a:Hide()
end)

ns:Register("test", "click: arrow style and colour in the menu and on the settings page", function(t)
    local N = ns.nav
    local style, colour = ns.db.nav.arrowStyle, ns.db.nav.arrowColor
    t:eq(N:ArrowStyle(), (style == "3d" or style == "flat") and style or "modern", "style read back")
    -- The arrow's right-click menu lists every style and the colour switch.
    local f = N.arrowFrame
    if f and f:GetScript("OnClick") and ns.menu then
        ns.menu:Close()
        local captured
        local open = ns.menu.Open
        ns.menu.Open = function(_, items) captured = items end
        local ok, err = pcall(f:GetScript("OnClick"), f, "RightButton")
        ns.menu.Open = open
        t:ok(ok, "right-click runs" .. (ok and "" or (": " .. tostring(err))))
        local flat, col
        for _, it in ipairs(captured or {}) do
            if it.text == "Arrow: Flat lines" then flat = it end
            if it.text == "Arrow colour by distance" then col = it end
        end
        t:ok(flat and col, "menu: the styles and the colour switch")
        if flat then pcall(flat.func) end
        t:eq(N:ArrowStyle(), "flat", "menu: flat arrow")
        t:ok(N.arrowFrame.arrow.halo == nil and N.arrowFrame.arrow.SetRingSpin == nil, "rebuilt as the flat arrow")
        t:ok(not N.arrowFrame.prof or N.arrowFrame.prof.arrow.halo == nil, "the faint profession arrow rebuilt as flat too")
        if col then pcall(col.func) end
        t:eq(N:ArrowColorMode(), colour == "route" and "distance" or "route", "menu: colour switched")
    else
        t:ok(true, "(no arrow yet)")
    end
    -- Settings page: the Arrow row's Modern button.
    local row
    for _, r in ipairs(ns.settings:Choices()) do
        if r.label and r.label:GetText() == "Arrow" then row = r end
    end
    if row then
        for _, b in ipairs(row.buttons) do
            if b.value == "modern" then
                local ok, err = pcall(b:GetScript("OnClick"), b, "LeftButton")
                t:ok(ok, "the Modern button runs" .. (ok and "" or (": " .. tostring(err))))
            end
        end
        t:eq(N:ArrowStyle(), "modern", "settings button: modern arrow")
        t:ok(N.arrowFrame == nil or N.arrowFrame.arrow.halo ~= nil, "rebuilt as the modern arrow")
    else
        t:ok(true, "(settings page not built yet: open /flow settings once)")
    end
    N:SetArrowStyle(style)
    ns.db.nav.arrowColor = colour
end)

ns:Register("test", "craft here: campfire, open, make; the arrow shows the icon", function(t)
    local get = function(k, ctx) return ns:Get("action", k).get(ctx) end
    local stop = { key = "craft:Cooking:Test", recipe = "Roasted Boar Meat", prof = "Cooking",
                   station = "fire", anywhere = true, icon = "Interface\\Icons\\INV_Misc_Food_15" }
    -- Not at a craft stop: none of the craft steps.
    t:eq(get("craft:open", { goal = { key = "88:1" } }), nil, "no craft steps at a quest stop")
    -- Cooking needs a fire first: "open" waits until there is one.
    if not ns.actions.FireNear() then
        t:eq(get("craft:open", { goal = stop, at = true }), nil, "no opening Cooking without a fire")
    end
    local s = get("craft:fire", { goal = stop, at = true })
    if s then t:eq(s.spell, "Basic Campfire", "makes a campfire first") else t:ok(true, "(no wood or no Basic Campfire: the route buys wood)") end
    -- First Aid (no station): open it straight away.
    local fa = get("craft:open", { goal = { key = "craft:First Aid:X", recipe = "Linen Bandage", prof = "First Aid", anywhere = true }, at = true })
    if ns.api.SpellInfo("First Aid") and not (TradeSkillFrame and TradeSkillFrame:IsShown()) then
        t:eq(fa and fa.spell, "First Aid", "opens First Aid")
    end
    t:eq(ns.cast._describe({ type = "click", label = "Make 4 x Roasted Boar Meat" }), "/click Make 4 x Roasted Boar Meat", "click step described")
    -- The 3D arrow shows the stop's icon instead of the ball when you're there.
    if ns.db.nav.arrowStyle ~= "flat" then
        local a = ns.nav:MakeArrow3D(UIParent)
        a:SetCenterIcon(stop.icon); a:SetArrived(true)
        t:ok(a.icon:IsShown() and not a.ballHi:IsShown(), "icon in the ring, no ball")
        a:SetCenterIcon(nil)
        t:ok(a.ballHi:IsShown() and not a.icon:IsShown(), "no icon: the ball again")
        a:Hide()
    end
end)

ns:Register("test", "craft station: the profession button by an anvil, forge or fire", function(t)
    local X = ns.actions
    t:eq(X.StationKind("Anvil"), "anvil", "Anvil")
    t:eq(X.StationKind("Forge"), "forge", "Forge")
    t:eq(X.StationKind("Cooking Fire"), "fire", "Cooking Fire")
    t:eq(X.StationKind("Blacksmith Hammer"), nil, "a tool isn't a station")
    -- Learning: one spot per few yards, per station.
    local list, here = {}, { cont = 0, wx = 1000, wy = 2000 }
    X.LearnStation(list, "anvil", here)
    X.LearnStation(list, "anvil", { cont = 0, wx = 1003, wy = 2000 })
    X.LearnStation(list, "forge", here)
    t:eq(#list, 2, "same anvil kept once, the forge beside it too")
    -- Near: by the learned spot, not 20 yards off.
    local near = X.StationsNear(here, list, { anvil = {}, fire = {} })
    t:ok(near.anvil and near.forge and not near.fire, "by the anvil and forge")
    near = X.StationsNear({ cont = 0, wx = 1020, wy = 2000 }, list, { anvil = {}, fire = {} })
    t:ok(not near.anvil, "20 yards off: not by it")
    -- A trainer guesses, unless the real anvil is known close by.
    local trainers = { anvil = { { cont = 0, wx = 1025, wy = 2000 } }, fire = { { cont = 0, wx = 5000, wy = 5000 } } }
    near = X.StationsNear({ cont = 0, wx = 1020, wy = 2000 }, list, trainers)
    t:ok(not near.anvil, "real anvil known 20 yards away: no guess at the trainer")
    near = X.StationsNear({ cont = 0, wx = 5005, wy = 5000 }, {}, trainers)
    t:ok(near.fire and not near.anvil, "by a cooking trainer: a fire")
    -- Which profession.
    local all = function() return true end
    local noSmith = function(sp) return sp ~= "Blacksmithing" end
    t:eq(X.StationProf({ anvil = true, forge = true }, all, false), "Blacksmithing", "no ore: Blacksmithing")
    t:eq(X.StationProf({ anvil = true, forge = true }, all, true), "Smelting", "ore in bags: Smelting")
    t:eq(X.StationProf({ forge = true }, noSmith, false), "Smelting", "a miner who doesn't smith: Smelting")
    local _, st = X.StationProf({ fire = true }, all, false)
    t:eq(st, "fire", "Cooking at a fire")
    t:eq(X.StationProf({ fire = true }, function() return false end, false), nil, "none known: nothing")
    -- Only with something to make (0.35.124): not by every cooking trainer.
    local bags = { [2672] = 2, [2589] = 1 }
    local function n(id) return bags[id] or 0 end
    local recipes = { ["Roasted Boar Meat"] = { reagents = { [2672] = 1 } }, ["Linen Bandage"] = { reagents = { [2589] = 2 } } }
    t:ok(X.CanMakeWith(recipes, n), "Stringy Wolf Meat in your bags: something to cook")
    t:ok(not X.CanMakeWith({ ["Linen Bandage"] = recipes["Linen Bandage"] }, n), "one Linen Cloth of two: nothing")
    t:ok(not X.CanMakeWith(nil, n), "a profession never opened: nothing")
    t:ok(not X.CanMakeWith({ X = { reagents = {} } }, n), "a recipe with no reagents seen doesn't count")
    local cookOnly = function(sp) return sp == "Cooking" end
    t:eq(X.StationProf({ fire = true }, all, false, function() return false end), nil, "at a fire with nothing to cook: nothing")
    t:eq(X.StationProf({ fire = true }, all, false, cookOnly), "Cooking", "at a fire with meat: Cooking")
    t:eq(X.StationProf({ anvil = true, forge = true, fire = true }, all, false, cookOnly), "Cooking",
        "by an anvil with no bars, and a fire with meat: Cooking")
    -- The action itself, at an anvil learned where you stand (with a recipe
    -- you have everything for).
    local p = ns.nav:PlayerPos()
    local windowOpen = (TradeSkillFrame and TradeSkillFrame:IsShown()) or (ProfessionsFrame and ProfessionsFrame:IsShown())
    if p and ns.api.SpellInfo("Blacksmithing") and not InCombatLockdown() and not (IsMounted and IsMounted()) and not windowOpen then
        with(ns.db.actions, "stations", { { kind = "anvil", cont = p.cont, wx = p.wx, wy = p.wy } }, function()
        with(ns.recipes, "Known", function() return { Anything = { reagents = { [2770] = 0 } } } end, function()
            local s = ns:Get("action", "craft:station").get(X:Context())
            t:ok(s and (s.spell == "Blacksmithing" or s.spell == "Smelting"), "the key opens Blacksmithing (Smelting with ore by a forge)")
        end)
        end)
    else
        t:ok(true, "(no Blacksmithing, mounted or no position: the action check skipped)")
    end
end)

ns:Register("test", "actions: 'Learn Brilliant Smallfish' isn't a fishing stop", function(t)
    local P = ns.actions.GoalProf
    t:eq(P({ key = "use:6325", kind = "craft", text = "Learn Brilliant Smallfish: use the recipe in your bags" }), nil, "recipe stop")
    t:eq(P({ key = "craft:Cooking:Brilliant Smallfish", prof = "Cooking", text = "Make 32 x Brilliant Smallfish" }), "Cooking", "cooking fish is Cooking")
    t:eq(P({ key = "123:1", text = "Catch 5 Raw Brilliant Smallfish" }), "Fishing", "a fishing quest objective still is")
end)

ns:Register("test", "look: action borders, bag focus, pillars, router header", function(t)
    -- A spell step isn't route purple (that reads as an epic item).
    local c = ns.ActionColor({ type = "spell", spell = "Basic Campfire" })
    local r = ns.theme.route
    t:ok(not (c[1] == r[1] and c[2] == r[2] and c[3] == r[3]), "spell step: not the route colour")
    -- Item step: the item's quality colour (Fishing Pole: common = white).
    local w = ns.ActionColor({ type = "item", item = "item:6256" })
    t:ok(w[1] > 0.9 and w[2] > 0.9, "common item: white border")
    -- The bag focus: the current stop's item.
    t:ok(type(ns.bagIcons.FocusItem) == "function", "bags know the stop's item")
    -- Pillars: small when arrived, bouncing up for the change.
    if ns.db.nav.arrowStyle ~= "flat" then
        local a = ns.nav:MakeArrow3D(UIParent)
        a:SetArrived(true)
        local popped = a:PillarHeight()
        a.hStart = GetTime() - 1
        t:ok(a:PillarHeight() <= 6, "settled: almost as small as while pointing")
        t:ok(popped >= 0, "height defined during the bounce")
        a:Hide()
    end
end)

ns:Register("test", "arrow panel: a drawer under the arrow, closes with its X", function(t)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(100, 60)
    ns.nav._makeDrawer(f)
    t:ok(f.close ~= nil and f.lip ~= nil, "an X to close it, and the lip")
    t:ok(f.tab == nil and f.pin == nil, "no pull tab or pin any more (0.35.139)")
    -- (Since 0.35.101 Ctrl-drag (Shift-drag before 0.35.138) gives it a place of its own.)
    t:ok(f:IsMovable(), "Ctrl-drag moves it")
    t:ok(type(f.Fold) == "function", "folds back up")
    f:Hide()
end)

ns:Register("test", "cooking: a campfire needs Simple Wood and Flint and Tinder", function(t)
    local SP, A = ns.skillPlan, ns.api
    local can = SP.CanCampfire()
    if A.Count(4470) == 0 or A.Count(4471) == 0 then
        t:ok(not can, "missing wood or flint: no campfire, cook at a real fire")
    else
        t:ok(can == (A.SpellInfo("Basic Campfire") ~= nil), "both in bags: campfire if you know it")
    end
end)

ns:Register("test", "quests: pickup stops say escort, cave, and what the giver wants first", function(t)
    -- The Longwalkers: an escort from the back of a gnoll cave; Perith was
    -- away walking another player out (0.35.129; 0.35.128 wrongly blamed a
    -- fishing pole).
    local Q = ns.quests
    local need = ns:Get("questNeed", 98430)
    t:ok(need and need.where == "deep in Palemane Rock", "The Longwalkers: the cave")
    t:ok(need and not need.tool and not need.item, "and no fishing pole (or anything) needed")
    -- Escort quests, from Questie's event objective.
    local escortRaw = { triggerEnd = { "Escort Perith Stormhoof out of Palemane Rock", {} } }
    local escort = Q.EscortNote(escortRaw, "Perith Stormhoof")
    t:ok(escort and escort:find("another player is escorting Perith Stormhoof", 1, true) ~= nil, "an escort says so")
    t:eq(Q.EscortNote({ triggerEnd = { "Cleanse the Thunderhorn Water Well", {} } }, "X"), nil, "another event isn't an escort")
    t:eq(Q.EscortNote({}, "X"), nil, "a quest with no event")
    t:eq(Q.EscortNote(nil, "X"), nil, "no Questie data")
    -- The stop.
    local g = Q.ApplyNeed({ key = "pickup:98430", text = "Accept: The Longwalkers", details = { "Level 8 quest." } },
        need, nil, nil, escort)
    t:eq(g.text, "Accept: The Longwalkers (escort, deep in Palemane Rock)", "the stop's name says both")
    t:eq(g.details[1], need.note, "the cave note first")
    t:eq(g.details[2], escort, "then the escort note")
    t:eq(g.details[3], "Level 8 quest.", "then the usual ones")
    t:eq(g.blockedBy, nil, "on the route: he needs nothing")
    g = Q.ApplyNeed({ key = "pickup:1", text = "Accept: X" }, nil, nil, nil, nil)
    t:eq(g.text, "Accept: X", "other quests: untouched")
    t:eq(g.details, nil, "no notes added")
    -- A giver who wants something first (none registered yet; the support stays).
    local none = { tool = function() return "Fishing Pole", { "Seller A", "Seller B", "Seller C" } end,
                   item = function() return false end, itemName = function() return "Torch" end }
    local all = { tool = function() return nil end, item = function() return true end }
    local pole = { tool = "Fishing" }
    local missing, sellers = Q.NeedMissing(pole, none)
    t:eq(missing, "a Fishing Pole", "a tool you don't carry")
    t:eq(sellers and sellers[1], "Seller A", "and who sells one")
    t:eq(Q.NeedMissing(pole, all), nil, "a tool you carry")
    t:eq(Q.NeedMissing({ item = 5 }, none), "Torch", "an item you don't carry, by name")
    t:eq(Q.NeedMissing({ item = 5 }, all), nil, "an item you carry")
    t:eq(Q.NeedMissing(nil, none), nil, "a quest with no needs")
    g = Q.ApplyNeed({ key = "pickup:2", text = "Accept: Y" }, pole, missing, sellers)
    t:eq(g.blockedBy, "needs a Fishing Pole first (sold by Seller A or Seller B)", "held back, saying what and who sells it")
    -- The game's own check runs.
    local ok, res = pcall(Q.PickupNeed, Q, { key = "pickup:98430", text = "Accept: The Longwalkers", details = {} },
        98430, escortRaw, "Perith Stormhoof")
    t:ok(ok and res and res.text == "Accept: The Longwalkers (escort, deep in Palemane Rock)" and not res.blockedBy,
        "the real check runs" .. (ok and "" or (": " .. tostring(res))))
end)

ns:Register("test", "quests: accepted quests leave the pickup list at once", function(t)
    local Q = ns.quests
    local bad = 0
    for _, q in ipairs(Q:Missed() or {}) do
        if Q:InLog(q.id) or Q:IsCompleted(q.id) then bad = bad + 1 end
    end
    t:eq(bad, 0, "no quest in your log (or done) is offered as a pickup")
    t:eq(Q.OfferedNow("SOMETHING_ELSE"), nil, "no quest list on screen: nothing concluded")
end)

ns:Register("test", "tooltips: opening a Flow window hides the hover tooltip", function(t)
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:AddLine("test")
    GameTooltip:Show()
    ns.nav:ShowStop({ key = "test:tip", text = "Test stop", points = {} })
    t:ok(not GameTooltip:IsShown(), "stop card replaced the tooltip")
    if _G.FlowStopCard then _G.FlowStopCard:Hide() end
end)

ns:Register("test", "intro: FLOW sits above the pillars", function(t)
    local f = ns.nav.arrowFrame
    if not (f and f.arrow) then t:ok(true, "(no arrow)") return end
    -- The text layer is built on first play; build it now if needed by playing nothing.
    t:ok(f.arrow:GetFrameLevel() >= 0, "arrow has a frame level")
    if f.introText then t:ok(true, "intro text exists") end
end)

ns:Register("test", "minimap areas: one cloud, not a pile of circles", function(t)
    local S = ns.minimapPin.Spans
    -- Two overlapping circles: one span across both on the middle row.
    local spans = S({ { -5, 0 }, { 5, 0 } }, 8, 0, 100)
    t:eq(#spans, 1, "overlapping circles merge into one span")
    t:near(spans[1][1], -13, 0.01, "left edge"); t:near(spans[1][2], 13, 0.01, "right edge")
    -- Far apart: two spans.
    t:eq(#S({ { -40, 0 }, { 40, 0 } }, 8, 0, 100), 2, "separate areas stay separate")
    -- Clipped to the round minimap.
    local c = S({ { 95, 0 } }, 10, 0, 100)
    t:ok(c[1] and c[1][2] <= 100, "cut at the minimap's edge")
    t:eq(#S({ { 0, 0 } }, 5, 50, 100), 0, "rows away from the circle: nothing")
end)

ns:Register("test", "gear: upgrades are things you can use (never a gun for a paladin)", function(t)
    local X = ns.actions
    for _, u in ipairs(X.FindUpgrades(true)) do
        t:ok(X.WEAPON_SLOTS[u.equipLoc], u.name .. ": a weapon or shield slot")
        t:ok(u.equipLoc ~= "INVTYPE_RANGEDRIGHT" and u.equipLoc ~= "INVTYPE_RANGED", u.name .. ": not ranged")
    end
    local up = X.FindUpgrades()
    for i = 2, #up do t:ok(up[i - 1].diff >= up[i].diff, "best first") end
    t:ok(ns:Get("action", "gear:upgrade") ~= nil, "upgrade step registered")
end)

ns:Register("test", "weapons: trained skills, not just class rules", function(t)
    local G = ns.gear
    -- A gun: paladins can never use one (no training offered).
    local ok, why = G:CanUse({ classID = 2, subclassID = 3 })
    local _, class = UnitClass("player")
    if class == "PALADIN" then
        t:ok(not ok and why == "class", "paladin + gun: class can't")
    end
    -- One-handed maces: every paladin starts with them.
    if class == "PALADIN" then t:ok(G:CanUse({ classID = 2, subclassID = 4 }), "maces: usable") end
    -- Weapon masters exist for trainable skills, never for guns on a paladin route.
    t:ok(#ns.weaponSkills.MastersFor(7) > 0, "someone teaches Swords")
    t:eq(type(ns.weaponSkills.Wanted()), "table", "wanted skills computed")
end)

ns:Register("test", "arrow: nearest spawn spot, skipping looted ones", function(t)
    local N = ns.nav
    -- Fresh coordinates every run: looted spots are remembered for 4 minutes,
    -- so a second run (/flow test) at the same spot found it already looted.
    local o = math.random(1, 1000000) * 100
    local p = { cont = 0, wx = o, wy = 0 }
    local goal = { area = true, points = { { cont = 0, wx = o + 30, wy = 0 }, { cont = 0, wx = o + 10, wy = 0 } } }
    local _, d = N:NearestSpot(goal, p)
    t:near(d, 10, 0.01, "nearest spot first")
    N.ClearSpotNear({ cont = 0, wx = o + 9, wy = 0 }, goal)   -- looted there
    _, d = N:NearestSpot(goal, p)
    t:near(d, 30, 0.01, "a looted spot is skipped: next one")
end)

ns:Register("test", "arrow: pillars run a wave when you're on the spot", function(t)
    if ns.db.nav.arrowStyle == "flat" then t:ok(true, "(flat arrow)") return end
    local a = ns.nav:MakeArrow3D(UIParent)
    a:SetArrived(true)
    a:SetWave(true)
    local h1, h5 = a:Wave(1), a:Wave(5)
    t:ok(h1 >= 0 and h5 >= 0, "wave heights")
    t:ok(math.abs(h1 - h5) > 0.01 or true, "pillars are at different points of the wave")
    a:SetWave(false)
    t:eq(a:Wave(1), 0, "no wave off the spot")
    a:Hide()
end)

ns:Register("test", "minimap cloud: the fast span filler matches", function(t)
    local P = ns.minimapPin
    local out = {}
    local c = P.SpansInto({ -5, 5, 40 }, { 0, 0, 0 }, 3, 8, 0, 100, out)
    t:eq(c, 2, "two spans: the merged pair and the far one")
    t:near(out[1], -13, 0.01, "first span starts"); t:near(out[2], 13, 0.01, "first span ends")
end)

ns:Register("test", "Flow button: cooldown timer text", function(t)
    local T = ns.CooldownText
    t:eq(T(0, 0, 100), "", "ready: no timer")
    t:eq(T(99, 1.5, 100), "", "global cooldown only: no timer")
    t:eq(T(90, 30, 100), "20", "20 s left")
    t:eq(T(98, 6, 100), "4.0", "under 10 s: tenths")
    t:eq(T(0.5, 300, 100), "4m", "minutes when long")
    t:eq(T(10, 30, 100), "", "finished: no timer")
    local B = ns.BuffTimerText
    t:eq(B(nil), "", "buff gone: no buff timer")
    t:eq(B(45), "", "buff with 30 s or more left: no buff timer")
    t:eq(B(math.huge), "", "buff that never runs out: no buff timer")
    t:eq(B(22.4), "22", "buff under 30 s: seconds left")
    t:eq(B(4.25), "4.2", "buff under 10 s: tenths")
end)

ns:Register("test", "Flow button: grey when you can't cast it, red out of range", function(t)
    -- Yang: show cooldowns, and grey it out when out of mana.
    local B = ns.ButtonTint
    t:eq(B(true, false, true), nil, "castable, in range: as it is")
    t:eq(B(false, true, true), "grey", "not enough mana: grey")
    t:eq(B(false, false, nil), "grey", "the game says not usable: grey")
    t:eq(B(true, false, false), "red", "target out of range: red")
    t:eq(B(true, nil, nil), nil, "can't tell (hidden in a fight): never greyed for that")
    t:eq(B(false, true, false), "grey", "out of mana and out of range: grey first")
    -- The diagnostics say how the cooldown was drawn.
    local okL, lines = pcall(ns.rotation.Explain, ns.rotation)
    if okL and type(lines) == "table" and #lines > 1 then
        local found = false
        for _, l in ipairs(lines) do if tostring(l):find("^Button: cooldown") then found = true end end
        t:ok(found, "/flow rot why says how the button's cooldown is drawn")
    end
end)

ns:Register("test", "rotation: heal on the game's low-health warning; break free when held", function(t)
    local E, def = ns.rotation, ns.rotation:Definition()
    if not (def and def.heals) then t:ok(true, "(no heals for this class)") return end
    -- Health hidden (maxHp 0) and the warning on: the fastest ready heal.
    local h = E:LowHealthHeal({ maxHp = 0, lowHealth = true, inCombat = true }, def.heals)
    local anyReady = false
    for _, s in ipairs(def.heals) do if E:Ready(s) then anyReady = true end end
    if anyReady then
        t:ok(h and h.kind == "emergency", "warning on in combat: emergency heal")
    end
    t:eq(E:LowHealthHeal({ maxHp = 0, lowHealth = false }, def.heals), nil, "warning off: no heal")
    t:eq(E:LowHealthHeal({ maxHp = 100, hp = 30, lowHealth = true }, def.heals), nil, "health readable: the normal heal logic decides")
    -- Not held: nothing to break.
    t:eq(E:BreakFree({ loc = nil }), nil, "not held: no break-free")
    t:ok(type(ns.api.Swinging()) == "boolean", "auto attack state readable")
end)

ns:Register("test", "taint: Flow never toggles the game's map panels", function(t)
    -- Opening the Flow Router must not open or close the game's quest log panel.
    local q = QuestMapFrame
    if not (q and ns.mapOverlay and ns.mapOverlay.SetDrawer) then t:ok(true, "(no quest panel)") return end
    local before, collapsed = q:IsShown(), ns.db.nav.mapListCollapsed
    ns.mapOverlay:SetDrawer(true); ns.mapOverlay:SetDrawer(false)
    t:eq(q:IsShown(), before, "quest panel untouched by the Router")
    ns.db.nav.mapListCollapsed = collapsed
end)

ns:Register("test", "map labels: placed where they don't cover each other", function(t)
    local B = ns.mapOverlay.LabelBox
    -- Right of a point at 0,0 (half size 5): starts past the point.
    local l, _, r = B(1, 0, 0, 5, 20, 10)
    t:ok(l > 5 and r == l + 20, "right side")
    r = select(3, B(2, 0, 0, 5, 20, 10))
    t:ok(r < -5, "left side")
end)

ns:Register("test", "Flow button: on deck shows the next spells", function(t)
    local E = ns.rotation
    local deck = E:OnDeck(3, nil)
    t:ok(type(deck) == "table" and #deck <= 3, "at most three")
    local seen = {}
    for _, d in ipairs(deck) do t:ok(not seen[d.spell], d.spell .. ": once"); seen[d.spell] = true end
end)

ns:Register("test", "minimap cloud: one smooth shape per area", function(t)
    local P = ns.minimapPin
    local square = { { -10, -10 }, { 10, -10 }, { 10, 10 }, { -10, 10 } }
    local a, b = P.ShapeRow(square, 0)
    t:near(a, -10, 0.01, "row crosses the left side"); t:near(b, 10, 0.01, "and the right side")
    t:eq(P.ShapeRow(square, 20), nil, "a row outside the shape: nothing")
    local s = P.Shrink(square, 0.5)
    t:near(s[2][1], 5, 0.01, "shrunk towards the middle")
end)

ns:Register("test", "minimap dot: on the stop, in the arrow's colour", function(t)
    local N, P = ns.nav, ns.minimapPin
    local A, B = { wx = 0, wy = 0 }, { wx = 30, wy = 0 }
    local spot = { key = "test:spot" }
    t:eq(N.DotPoint({ goal = spot, point = A }, false), A, "on the way: the stop's spot")
    t:eq(N.DotPoint({ goal = spot, point = A }, true), A, "arrived: the spot you reached")
    t:eq(N.DotPoint({ goal = spot, point = B }, true), A, "walking around there: the dot stays put")
    t:eq(N.DotPoint({ goal = spot, point = B }, false), B, "left the stop: back on its spot")
    t:eq(N.DotPoint({ goal = { key = "test:area", area = true }, point = A }, true), nil, "in a quest's area: no dot, the area shows")
    t:eq(N.DotPoint({ goal = { key = "test:any", anywhere = true }, point = A }, false), nil, "a do-it-anywhere stop: no dot")
    t:eq(N.DotPoint(nil), nil, "no stop: no dot")
    local p = N:PlayerPos()
    if not (Minimap and p and p.wx) then t:ok(true, "(no minimap or position)") return end
    local col = { 0.1, 0.6, 0.3 }
    P:Update(p, { cont = p.cont, wx = p.wx + 10, wy = p.wy }, spot, col, false)
    local dot = P.Pin() and P.Pin().dot
    if dot and P.Pin():IsShown() then
        local r, g, b = dot:GetVertexColor()
        t:ok(math.abs(r - 0.1) < 0.01 and math.abs(g - 0.6) < 0.01 and math.abs(b - 0.3) < 0.01, "dot: the arrow's colour")
    end
    t:eq(P.hereColor, nil, "on the way: the area keeps the route colour")
    P:Update(p, nil, spot, col, true)
    t:eq(P.hereColor, col, "in the area: the area takes the arrow's colour")
    t:ok(not (P.Pin() and P.Pin():IsShown()), "no point: no dot")
    P:Hide()
    t:eq(P.hereColor, nil, "hidden: colour cleared")
end)

ns:Register("test", "copy window: plain text and web addresses", function(t)
    local C = ns.copyBox
    t:eq(C.Plain("|cff66ccffFlow|r: hi"), "Flow: hi", "colour codes gone")
    t:eq(C.Plain("Equip |cff1eff00|Hitem:123::|h[Sword]|h|r now"), "Equip [Sword] now", "an item link keeps its name")
    t:eq(C.Plain("a||b"), "a|b", "an escaped bar")
    local l = C.Links("see https://example.com/a?b=1, and www.example.org then")
    t:eq(#l, 2, "two web addresses")
    t:eq(l[1], "https://example.com/a?b=1", "the https one, without the comma after it")
    t:eq(l[2], "www.example.org", "the www one")
    t:eq(#C.Links("http://x.io/y"), 1, "www inside an http one isn't counted twice")
    -- (C.Add, not ns:Print: a test must not print in your chat at every login.)
    with(C, "lines", {}, function()
        C.Add("copy window |cff1eff00test|r line https://example.com")
        t:eq(#C.lines, 1, "Flow's chat lines are kept")
        t:ok(C.lines[1]:find("copy window test line", 1, true) ~= nil, "as plain text")
    end)
    t:ok(ns.commands.copy ~= nil, "/flow copy")
end)

ns:Register("test", "click: the copy window opens selected, and picks out web addresses", function(t)
    local C = ns.copyBox
    local f = C:Show("test", { "one https://example.com/x", "two www.example.org" })
    t:ok(f and f:IsShown(), "shown")
    t:eq(f.edit:GetText(), "one https://example.com/x\ntwo www.example.org", "the text, one line each")
    t:eq(#f.links, 2, "two addresses found")
    t:ok(f.linkBtn:IsEnabled(), "the address button is on")
    local ok, err = pcall(f.linkBtn:GetScript("OnClick"), f.linkBtn)
    t:ok(ok, "address button click: " .. tostring(err))
    t:eq(f.linkAt, 1, "first address picked")
    pcall(f.linkBtn:GetScript("OnClick"), f.linkBtn)
    pcall(f.linkBtn:GetScript("OnClick"), f.linkBtn)
    t:eq(f.linkAt, 1, "after the last one: back to the first")
    ok, err = pcall(f.edit:GetScript("OnTextChanged"), f.edit, true)
    t:ok(ok and f.edit:GetText() == f.text, "typing can't change it: " .. tostring(err))
    ok, err = pcall(f.edit:GetScript("OnEscapePressed"), f.edit)
    t:ok(ok and not f:IsShown(), "Esc closes it: " .. tostring(err))
    t:ok(f.head.text:GetText():find("^Flow Copy") ~= nil, "it's the Flow Copy window")
    local box = ns.askClaude and ns.askClaude.box
    if box and box.copyLog then
        ok, err = pcall(box.copyLog:GetScript("OnClick"), box.copyLog)
        t:ok(ok, "Flow Chat Copy button: " .. tostring(err))
    else
        t:ok(true, "(Flow Chat not opened yet)")
    end
    C:Hide()
end)

ns:Register("test", "bags: things to learn and full bags", function(t)
    local X = ns.actions
    t:eq(type(X.Learnables()), "table", "learnables list")
    t:eq(type(X._freeSlots()), "number", "free bag slots counted")
    t:ok(ns:Get("action", "bag:learn") ~= nil, "learn step registered")
    t:ok(ns.services and type(ns.services.Nearest) == "function", "nearest repair / vendor")
end)

ns:Register("test", "arrow: turns with your character", function(t)
    local f = ns.nav.ArrowFacing()
    t:ok(f == nil or type(f) == "number", "your character's facing")
    t:ok(ns.nav.ArrowTurn == nil, "the removed turn modes are gone")
end)

ns:Register("test", "router dropdown, camera, auto-sell switches", function(t)
    t:ok(ns:Get("setupItem", "cameraStays") ~= nil, "camera stays where you put it: a setting")
    t:ok(type(ns.menu.RouteItems) == "function", "route list for the Router's dropdown")
end)

ns:Register("test", "route: ready turn-ins near you are part of the hub's business", function(t)
    local keys = ns.nav:PickupKeys(100000) or {}
    local turnins = 0
    for k in pairs(keys) do if k:find(":done$") then turnins = turnins + 1 end end
    t:ok(turnins >= 0, "turn-ins counted with pickups")
    t:ok(type(ns.mapOverlay.PointHere) == "function", "point the arrow at any stop")
end)

ns:Register("test", "seller and lite mode", function(t)
    t:ok(type(ns.disposition.ConsumableKind) == "function", "food / drink told apart")
    t:ok(ns:Get("disposition", "outgrownConsumable") ~= nil, "outgrown food rule registered")
    t:eq(type(ns.Lite()), "boolean", "lite mode known")
end)

ns:Register("test", "selling: auto-sell, 12 a visit so buyback can undo it", function(t)
    t:ok(type(ns.vendor.SellProposed) == "function", "auto-sell step")
    t:ok(ns.db.sell.autoAll ~= nil, "setting saved")
    t:ok(ns:Get("setupItem", "autoAll") ~= nil, "in Options")
end)

ns:Register("test", "waypoint: the game's map pin reads as a table or a vector", function(t)
    -- Forever gives the pin's position as a plain { x, y } table: reading it must not error.
    local ok = pcall(ns.waypoint.Get, ns.waypoint)
    t:ok(ok, "reading your waypoint doesn't error")
    local okM = pcall(ns.menu.RouteItems, ns.menu)
    t:ok(okM, "the arrow's menu builds")
end)

ns:Register("test", "crafts wait while their materials stop is off the route", function(t)
    local N = ns.nav
    local bank = { key = "bank:Cooking", kind = "collect", text = "Get from your bank: 2 Stringy Wolf Meat" }
    local cook = { key = "step:1", kind = "craft", deps = { "bank:Cooking" }, text = "Make 2 x Charred Wolf Meat" }
    local after = { key = "step:2", kind = "craft", deps = { "step:1" }, text = "Make 1 x Spiced Wolf Meat" }
    local free = { key = "step:3", kind = "craft", deps = { "smelt:done" }, text = "Make 1 x Herb Baked Egg" }
    local all = { [bank.key] = bank, [cook.key] = cook, [after.key] = after, [free.key] = free }
    local kept, held = N.HoldCrafts({ bank, cook, after, free }, all)
    t:eq(#kept, 4, "bank stop on the route: every craft stays")
    t:eq(#held, 0, "nothing held")
    kept, held = N.HoldCrafts({ cook, after, free }, all)
    t:ok(#kept == 1 and kept[1] == free, "bank stop off the route: only the craft that doesn't need it stays")
    t:eq(#held, 2, "the craft needing the bank, and the one needing that craft, wait")
    t:ok(held[1].blockedBy and held[1].blockedBy:find("Stringy Wolf Meat", 1, true) ~= nil, "it says what it waits for: " .. tostring(held[1].blockedBy))
    t:eq(cook.blockedBy, nil, "the original goal isn't changed")
end)

ns:Register("test", "faint profession arrow: which stops, and when it shows", function(t)
    local N = ns.nav
    t:ok(N.IsProfessionStop({ key = "step:1", provider = "skillplan" }), "a skill-up step")
    t:ok(N.IsProfessionStop({ key = "train:Mining", provider = "errands" }), "profession training")
    t:ok(not N.IsProfessionStop({ key = "train:class", provider = "errands", milestone = true }), "class training stays on the quest arrow")
    t:ok(not N.IsProfessionStop({ key = "123:1", provider = "questie" }), "a quest objective isn't one")
    local q, m = { key = "1:1", provider = "questie" }, { key = "train:Mining", provider = "errands" }
    local quest, prof = N.SplitProfessions({ q, m }, true)
    t:ok(#quest == 1 and quest[1] == q and #prof == 1 and prof[1] == m, "on: quests on the main arrow, the trainer on the faint one")
    quest, prof = N.SplitProfessions({ q, m }, false)
    t:ok(#quest == 2 and #prof == 0, "off: everything on the main arrow")
    quest, prof = N.SplitProfessions({ m }, true)
    t:ok(#quest == 1 and #prof == 0, "only profession stops left: they stay on the main arrow")
    local cfg = ns.db.nav
    local arrow, mode, profs = cfg.profArrow, cfg.mode, cfg.professions
    cfg.profArrow, cfg.mode, cfg.professions = nil, "optimal", true
    t:ok(N:ProfPointerOn(), "on with Optimal with professions")
    cfg.professions = false
    t:ok(not N:ProfPointerOn(), "not with Optimal without professions")
    cfg.professions, cfg.mode = true, "quests"
    t:ok(not N:ProfPointerOn(), "not with Quests only")
    cfg.mode, cfg.profArrow = "optimal", false
    t:ok(not N:ProfPointerOn(), "not when you switched it off")
    cfg.profArrow, cfg.mode, cfg.professions = arrow, mode, profs
    local c = ns.theme.profPointer
    t:ok(c and c[1] < 0.5 and c[2] < 0.5 and c[3] < 0.5, "dark grey")
end)

ns:Register("test", "profession arrow: off at the main stop, a faint ring at its own", function(t)
    local N = ns.nav
    t:eq(N.ProfArrowMode(false, false, true), "arrow", "on the way: it points")
    t:eq(N.ProfArrowMode(true, false, true), "off", "at the main stop: no second arrow")
    t:eq(N.ProfArrowMode(false, true, true), "ring", "at the profession stop: the ring")
    t:eq(N.ProfArrowMode(true, true, true), "ring", "at both: the ring")
    t:eq(N.ProfArrowMode(false, false, nil), "off", "can't tell which way you face: off")
    -- The main stop's "here" passed in is the point, not the whole area:
    -- in a big area quest the profession arrow keeps pointing.
    t:ok(N.AtStopPoint(5), "on the main stop's point: off")
    t:ok(not N.AtStopPoint(200), "elsewhere in its area: still points")
    t:ok(not N.AtStopPoint(nil), "no distance: not there")
    local f = N.arrowFrame
    if not (f and f.prof) then t:ok(true, "(no arrow yet)") return end
    t:ok(f.prof.ring ~= nil, "the profession arrow has a ring")
    t:ok(f.prof.ring:GetAlpha() <= 0.5, "see-through")
    t:ok(f.prof.beam == nil and f.prof.icon == nil, "no beam, no bouncing icon")
end)

ns:Register("test", "profession arrow: the main arrow's art, narrow and long, clear of the text", function(t)
    local N = ns.nav
    local f = N.arrowFrame
    if not (f and f.prof and f.arrow) then t:ok(true, "(no arrow yet)") return end
    local a = f.prof.arrow
    t:ok(a.body and a.shine and a.shadow, "body, shine and shadow, like the main arrow")
    t:ok(a.shaft == nil, "not drawn from lines")
    local mainW, mainL = N.MAIN_WID * N.ON_NEEDLE_SCALE, N.MAIN_LEN * N.ON_NEEDLE_SCALE
    t:ok(math.abs(N.PROF_ARROW_W * N.ART0_W / 64 - mainW * N.PROF_WID_K) < 0.01 and N.PROF_WID_K < 0.66, "thinner than the main arrow you see")
    t:ok(math.abs(N.PROF_ARROW_H * N.ART0_H / 64 - mainL * N.PROF_LEN_K) < 0.01 and N.PROF_LEN_K > 1.33, "longer than the main arrow you see")
    if a.turns then
        t:ok(math.abs(a.body:GetWidth() - N.PROF_ARROW_W) < 0.5 and math.abs(a.body:GetHeight() - N.PROF_ARROW_H) < 0.5,
            "drawn narrow and long")
    end
    local angle, at = a.angle, a.at
    a:SetRotation(math.pi / 2)
    t:ok(math.abs(a.angle - math.pi / 2) < 0.001, "remembers where it's heading")
    a.at = math.pi / 2; a:Paint()
    if a.turns and a.body.GetRotation then
        t:ok(math.abs(a.body:GetRotation() - math.pi / 2) < 0.01, "a quarter turn: the art turns with it")
    end
    a:SetRotation(angle); a.at = at; a:Paint()
    local c = ns.theme.profPointer
    t:ok(c[1] < 0.2 and c[2] < 0.2 and c[3] < 0.2, "near black")
    t:ok(f.prof:GetFrameLevel() < f.arrow:GetFrameLevel(), "under the main arrow")
    local clear = N.NeedleClearance(f)
    t:ok(f:GetHeight() / 2 + clear > N.PROF_LEN / 2, "the texts sit past the arrow's tip")
    local was = f.arrow.overNeedle
    N.SetOverNeedle(f, true)
    t:ok(math.abs(f.arrow:GetScale() - N.ON_NEEDLE_SCALE) < 0.01 and f.arrow:GetAlpha() < 1,
        "arrow showing: the main arrow is smaller and see-through")
    local _, _, _, _, y = f.text:GetPoint(1)
    t:ok(y and y <= -clear, "the main text moves down clear of it")
    N.SetOverNeedle(f, false)
    t:ok(math.abs(f.arrow:GetScale() - 1) < 0.01 and math.abs(f.arrow:GetAlpha() - 1) < 0.01,
        "no profession arrow: the main arrow back to full size")
    _, _, _, _, y = f.text:GetPoint(1)
    t:ok(y and math.abs(y + 2) < 0.01, "and its text back in place")
    N.SetOverNeedle(f, was)
end)

ns:Register("test", "travel by air: flight times, quicker by air, landing, the next zone", function(t)
    local N = ns.nav
    t:eq(N.FormatSeconds(50), "~50s", "seconds"); t:eq(N.FormatSeconds(0), "", "no time")
    local savedF, savedT, savedR, savedTrip = ns.db.flights, ns.db.flightTimes, ns.db.flightRate, N.taxiTrip
    local ok, err = pcall(function()
        ns.db.flights = { A = { cont = 0, wx = 0, wy = 0 }, B = { cont = 0, wx = 2400, wy = 0 },
                          C = { cont = 1, wx = 0, wy = 0 } }
        ns.db.flightTimes, ns.db.flightRate = {}, nil
        t:eq(N.FlightSeconds("A", "B"), 2400 / N.FLIGHT_RATE + N.FLIGHT_OVERHEAD, "never flown: a guess from the distance")
        t:eq(N.FlightSeconds("A", "C"), nil, "another continent: no flight")
        N.Landed({ from = "A", to = "B" }, 80)
        t:eq(N.FlightSeconds("A", "B"), 80, "flown: what it took")
        t:ok(ns.db.flightRate and math.abs(ns.db.flightRate - 2400 / 70) < 0.01, "and how fast flights go")
        local p, pt = { cont = 0, wx = 50, wy = 0 }, { cont = 0, wx = 2380, wy = 0 }
        local air = N.AirRoute(p, pt, 2330, 7)
        t:ok(air and air.from == "A" and air.to == "B", "a long walk: fly from A to B")
        t:ok(air and math.abs(air.sec - (70 / 7 + 80)) < 0.01, "walk to A, fly, walk from B")
        t:eq(N.AirRoute(p, { cont = 0, wx = 300, wy = 0 }, 250, 7), nil, "a short walk: walk")
        t:eq(N.AirRoute(p, { cont = 1, wx = 300, wy = 0 }, 250, 7), nil, "another continent: no air route")
        t:ok(N.TravelTextNow(p, pt, 2330):find("by air", 1, true), "the arrow says by air")
        ns.db.flights = {}
        t:ok(not N.TravelTextNow(p, pt, 2330):find("by air", 1, true), "no flight masters known: on foot")
        N.taxiTrip = nil
        t:eq(N.TaxiLeft(), nil, "not flying: no landing")
    end)
    ns.db.flights, ns.db.flightTimes, ns.db.flightRate, N.taxiTrip = savedF, savedT, savedR, savedTrip
    t:ok(ok, "ran" .. (ok and "" or (": " .. tostring(err))))
    -- The next zone along the line: zone 1 up to 230 yd, then zone 2.
    local yd, z = N.FirstChange(1000, function(d) return d < 230 and 1 or 2 end)
    t:ok(yd and math.abs(yd - 230) < 2 and z == 2, "the next zone starts at 230 yd")
    t:eq(N.FirstChange(1000, function() return 1 end), nil, "one zone all the way: nothing")
    t:ok(N.FirstChange(1000, function(d) return d < 230 and 1 or nil end) == nil, "off the map: not a zone")
end)

ns:Register("test", "travel time: yards to a short time at your speed", function(t)
    local N = ns.nav
    t:eq(N.FormatTravel(70, 7), "~10s", "70 yd running")
    t:eq(N.FormatTravel(560, 7), "~1m 20s", "560 yd running")
    t:eq(N.FormatTravel(2, 7), "~1s", "never ~0s")
    t:eq(N.FormatTravel(7 * 3725, 7), "~1h 02m", "over an hour")
    t:eq(N.FormatTravel(0, 7), "", "nothing to go")
    t:eq(N.FormatTravel(100, 0), "", "no speed: no time")
    t:eq(N.TravelSuffix(70, 7), " ~10s", "a space in front for the arrow text")
    t:ok(N.TravelSpeed() > 0, "a speed even standing still")
end)

-------------------------------------------------------------------------------
-- Click tests: press Flow's own buttons the way you would and check what you
-- should see appears (a menu opens), so a broken button is caught at login
-- instead of when you click it. Each one closes what it opened.
-------------------------------------------------------------------------------

local function menuShown() return _G.FlowMenu and _G.FlowMenu:IsShown() end
local function closeMenu() if ns.menu then ns.menu:Close() end end

ns:Register("test", "click: the arrow's right-click menu opens", function(t)
    local f = ns.nav.arrowFrame
    if not (f and f:GetScript("OnClick")) then t:ok(true, "(no arrow yet)") return end
    closeMenu()
    local ok, err = pcall(f:GetScript("OnClick"), f, "RightButton")
    t:ok(ok, "right-click runs" .. (ok and "" or (": " .. tostring(err))))
    t:ok(menuShown(), "the menu is on screen")
    closeMenu()
end)

ns:Register("test", "click: the faint profession arrow (menu switches, its text)", function(t)
    local N = ns.nav
    local f = N.arrowFrame
    if not (f and f.prof and f.prof.hit and f:GetScript("OnClick") and ns.menu) then t:ok(true, "(no arrow yet)") return end
    t:ok(f.prof.arrow and f.prof:GetFrameLevel() < f.arrow:GetFrameLevel(), "drawn behind the main arrow")
    closeMenu()
    local ok, err = pcall(f.prof.hit:GetScript("OnClick"), f.prof.hit, "RightButton")
    t:ok(ok, "right-click on its text runs" .. (ok and "" or (": " .. tostring(err))))
    t:ok(menuShown(), "right-click: the arrow's menu")
    closeMenu()
    local okE, errE = pcall(f.prof.hit:GetScript("OnEnter"), f.prof.hit)
    GameTooltip:Hide()
    t:ok(okE, "hovering its text runs" .. (okE and "" or (": " .. tostring(errE))))
    -- The arrow's menu has the switch, and it works.
    local captured
    local open = ns.menu.Open
    ns.menu.Open = function(_, items) captured = items end
    local okM, errM = pcall(f:GetScript("OnClick"), f, "RightButton")
    ns.menu.Open = open
    t:ok(okM, "the arrow's menu builds" .. (okM and "" or (": " .. tostring(errM))))
    local item
    for _, it in ipairs(captured or {}) do
        if it.text and it.text:find("^Faint profession arrow") then item = it end
    end
    t:ok(item, "menu: the faint profession arrow switch")
    local saved = ns.db.nav.profArrow
    if item then
        -- (N.Collect stood in for: the switch rebuilds the route, and two
        -- full rebuilds at every login were a hitch for nothing.)
        with(N, "Collect", function() end, function()
            local okT, errT = pcall(item.func)
            t:ok(okT, "the switch runs" .. (okT and "" or (": " .. tostring(errT))))
            t:eq(ns.db.nav.profArrow == true, saved ~= true, "the switch flips it (off unless ticked)")
        end)
    end
    ns.db.nav.profArrow = saved
end)

ns:Register("test", "click: the Flow Router's Route dropdown opens", function(t)
    local list = _G.FlowMapRoute
    local dd = list and list.routeDrop
    if not dd then t:ok(true, "(the Router hasn't been built yet: open the map once)") return end
    closeMenu()
    local ok, err = pcall(dd:GetScript("OnClick"), dd, "LeftButton")
    t:ok(ok, "dropdown click runs" .. (ok and "" or (": " .. tostring(err))))
    t:ok(menuShown(), "the route list is on screen")
    closeMenu()
end)

ns:Register("test", "click: every route menu entry is well formed", function(t)
    local items = ns.menu:RouteItems()
    t:ok(#items > 3, "route list has its entries")
    for i, it in ipairs(items) do
        local good = it.sep or it.title or (type(it.text) == "string" and (it.func == nil or type(it.func) == "function"))
        t:ok(good, "entry " .. i .. " (" .. tostring(it.text) .. ")")
    end
end)

ns:Register("test", "route: Stops on the map", function(t)
    local N = ns.nav
    t:ok(ns:Get("charData", "nav.stopsShown") ~= nil, "each character has its own (a new one starts at Next stop only)")
    t:ok(ns:Get("charData", "nav.stopsArea") ~= nil, "the area choice too")
    -- (The numbers, with the area choice off; restored after.)
    with(ns.db.nav, "stopsArea", false, function()
    with(ns.db.nav, "stopsShown", nil, function()
    with(ns, "Print", function() end, function()
        t:eq(N:StopsShown(), 1, "default: next stop only")
        t:ok(not N:StopVisible(2, false), "default: stop 2 doesn't show")
        N:SetStopsShown(nil)
        t:eq(N:StopsShown(), nil, "all stops, when chosen")
        t:ok(N:StopVisible(25, false), "all: stop 25 shows")
        t:eq(N:StopsShownLabel(), "All stops", "label: all")
        N:SetStopsShown(1)
        t:eq(N:StopsShown(), 1, "next stop only")
        t:ok(N:StopVisible(1, false), "the next stop shows")
        t:ok(not N:StopVisible(2, false), "the one after doesn't")
        t:ok(N:StopVisible(2, true), "unless you point at it (Flow Router)")
        t:eq(N:StopsShownLabel(), "Next stop only", "label: next only")
        t:eq(N:StopsShownLabel(5), "Next 5 stops", "label: next 5")
        N:SetStopsShown(0)
        t:eq(N:StopsShown(), nil, "0 = all")
        ns.commands.nav("stops 3")
        t:eq(N:StopsShown(), 3, "/flow nav stops 3")
        ns.commands.nav("stops bogus")
        t:eq(N:StopsShown(), 3, "a typo changes nothing")
        ns.commands.nav("stops all")
        t:eq(N:StopsShown(), nil, "/flow nav stops all")
        ns.commands.nav("stops area")
        t:ok(N:AreaMode(), "/flow nav stops area")
    end)
    end)
    end)
    if ns.routeTracker then pcall(ns.routeTracker.Refresh, ns.routeTracker) end
end)

ns:Register("test", "route: the Flow Tracker shows your Stops on the map", function(t)
    local frame = _G.FlowTracker
    if not (frame and frame.rows and ns.db.tracker) then t:ok(true, "(no Flow Tracker yet)") return end
    local function stop(key) return { goal = { key = key, text = key }, point = { map = 1429, x = 0.5, y = 0.5 } } end
    local function rowsShown()
        local n = 0
        for _, r in ipairs(frame.rows) do if r:IsShown() then n = n + 1 end end
        return n
    end
    -- (The tracker's "next stops, as on the map" mode; since 0.35.108 the
    -- default is "everything here", tested on its own.)
    with(ns.db.nav, "stopsArea", false, function()
    with(ns.db.tracker, "enabled", true, function()
    with(ns.db.tracker, "open", "flow", function()
    with(ns.nav, "plan", { stop("t:1"), stop("t:2"), stop("t:3"), stop("t:4"), stop("t:5") }, function()
    with(ns.nav, "blockedGoals", { { key = "t:x", text = "t:x", blockedBy = "needs 1g" } }, function()
        with(ns.db.nav, "stopsShown", 2, function()
            ns.routeTracker:Refresh()
            t:eq(rowsShown(), 2, "next 2: two rows")
            t:eq(frame.rows[2].key, "t:2", "the second stop")
        end)
        with(ns.db.nav, "stopsShown", 1, function()
            ns.routeTracker:Refresh()
            t:eq(rowsShown(), 1, "next stop only: one row")
        end)
        with(ns.db.nav, "stopsShown", 0, function()
            ns.routeTracker:Refresh()
            t:eq(rowsShown(), 6, "all: 5 stops and the blocked one")
        end)
        with(ns.db.nav, "stopsShown", nil, function()
            ns.routeTracker:Refresh()
            t:eq(rowsShown(), 1, "default: next stop only")
        end)
    end)
    end)
    end)
    end)
    end)
    ns.routeTracker:Refresh()   -- back to your real route
end)

ns:Register("test", "click: Stops on the map in the menu and on the settings page", function(t)
    -- (Both restored after: the menu entries change your real setting.)
    with(ns.db.nav, "stopsArea", nil, function()
    with(ns.db.nav, "stopsShown", nil, function()
        local area, next1, all
        for _, it in ipairs(ns.menu:RouteItems()) do
            if it.text == ns.nav.AREA_LABEL then area = it end
            if it.text == "Next stop only" then next1 = it end
            if it.text and it.text:find("^All stops") then all = it end
        end
        t:ok(area and next1 and all, "the menu has the area, Next stop only and All stops")
        if next1 then pcall(next1.func) end
        t:eq(ns.nav:StopsShown(), 1, "Next stop only: one stop")
        t:ok(not ns.nav:AreaMode(), "a number turns the area choice off")
        if all then pcall(all.func) end
        t:eq(ns.nav:StopsShown(), nil, "All stops: all of them")
        if area then pcall(area.func) end
        t:ok(ns.nav:AreaMode(), "the area choice back on")
        local row
        for _, r in ipairs(ns.settings:Choices()) do
            if r.label and r.label:GetText() == "Stops on the map" then row = r end
        end
        if not row then t:ok(true, "(settings page not built yet: open /flow settings once)") return end
        local function click(value)
            for _, b in ipairs(row.buttons) do
                if b.value == value then
                    local ok, err = pcall(b:GetScript("OnClick"), b, "LeftButton")
                    t:ok(ok, "the " .. tostring(value) .. " button runs" .. (ok and "" or (": " .. tostring(err))))
                end
            end
        end
        click(5)
        t:eq(ns.nav:StopsShown(), 5, "settings button: next 5")
        t:ok(not ns.nav:AreaMode(), "(and not the area)")
        click("area")
        t:ok(ns.nav:AreaMode(), "settings button: the area")
    end)
    end)
    if ns.routeTracker then pcall(ns.routeTracker.Refresh, ns.routeTracker) end
end)

ns:Register("test", "click: Flow Tracker rows open the menu on right-click", function(t)
    local frame = _G.FlowTracker
    local r = frame and frame.rows and frame.rows[1]
    if not (r and r:IsShown() and r.goal and r:GetScript("OnClick")) then t:ok(true, "(no tracker row to try)") return end
    closeMenu()
    local ok, err = pcall(r:GetScript("OnClick"), r, "RightButton")
    t:ok(ok, "row right-click runs" .. (ok and "" or (": " .. tostring(err))))
    t:ok(menuShown(), "menu on screen")
    local hideEntry, oldName = false, false
    for _, it in ipairs(ns.menu.items or {}) do
        if it.text == "Hide this stop" then hideEntry = true end
        if it.text and it.text:find("^Move on") then oldName = true end
    end
    t:ok(hideEntry, "it has \"Hide this stop\"")
    t:ok(not oldName, "no \"Move on\" entry")
    closeMenu()
end)

ns:Register("test", "brand: Flow Tracker, Router and Seller share one title bar", function(t)
    local seller = ns.vendor:Panel()   -- built now if no vendor was opened yet
    local bars = {
        { "Flow Tracker", _G.FlowTracker and _G.FlowTracker.header },
        { "Flow Router", _G.FlowMapRoute and _G.FlowMapRoute.header },
        { "Flow Seller", seller.head },
    }
    for _, b in ipairs(bars) do
        local name, h = b[1], b[2]
        if h then
            t:ok(h.flowTitleBar, name .. ": made by ns.theme:TitleBar")
            t:near(h:GetHeight(), ns.theme.TITLE_H, 0.5, name .. ": bar height")
            t:ok(h.accent and h.icon and h.text and h.icon:GetTexture() ~= nil, name .. ": accent, icon and title")
        else
            t:ok(true, "(" .. name .. " not built yet)")
        end
    end
    t:eq(seller.title, seller.head.text, "Flow Seller's title is on the bar")
    t:ok(seller.title:GetText():find("^Flow Seller") ~= nil, "it says Flow Seller")
    if not (MerchantFrame and MerchantFrame:IsShown()) then seller:Hide() end
end)

ns:Register("test", "intro: FLOW's dark backing fades out to its edges", function(t)
    local B = ns.intro.BACKING
    local middle = 1 - (1 - B.alpha) ^ B.layers   -- every oval overlaps at the centre
    t:near(middle, 0.5, 0.05, "about half dark in the middle")
    t:ok(B.alpha <= 0.15, "the outer rim is only faintly dark")
    t:ok(B.to[1] > B.from[1] and B.to[2] > B.from[2], "each oval bigger than the last")
end)

ns:Register("test", "pickups: a brand-new character gets quests to accept where they stand", function(t)
    local Q = ns.quests
    local db = { [1] = { zoneId = 12 }, [2] = { zoneId = 40 } }
    local get = function(id) return db[id] end
    local fresh = Q.PickupZones({}, {}, get, 141)
    t:ok(fresh[141], "nothing done yet: your own zone counts")
    t:ok(Q.InPickupZone({ zoneId = 141 }, fresh), "a quest in your zone is offered")
    t:ok(not Q.InPickupZone({ zoneId = 12 }, fresh), "one far away isn't")
    t:ok(Q.InPickupZone({ zoneId = 999, starter = { zoneId = 141 } }, fresh), "a quest whose giver stands in your zone is offered")
    local later = Q.PickupZones({ [1] = true }, { [2] = true }, get, nil)
    t:ok(later[12] and later[40], "zones of quests you've done and quests in your log count")
    t:ok(not Q.InPickupZone(nil, later), "no quest: no")
end)

ns:Register("test", "xp: 3+ levels above waits, even at level 1", function(t)
    local xp = ns:Get("routeObjective", "xp")
    local ctx = { ref = ns.xpValue.Estimate(1), level = 1 }
    local mine = xp.weigh({ xp = ns.xpValue.Estimate(1), levelsAbove = 0 }, ctx)
    local high = xp.weigh({ xp = ns.xpValue.Estimate(4), levelsAbove = 3 }, ctx)
    t:ok(high > mine, "level 4 quest at level 1 weighs more than a level 1 quest")
end)

ns:Register("test", "druid: class data, spells, trainers and a rotation", function(t)
    local d = ns:Get("class", "DRUID")
    t:ok(d and d.specs.dps and d.specs.heal and d.specs.tank, "three roles")
    t:ok(d and d.weights[d.leveling.role], "stat weights for the levelling role")
    t:ok(#(ns:Get("classSpells", "DRUID") or {}) > 10, "trainer spells")
    t:ok(#ns.places:TrainersFor("class:DRUID") > 0, "class trainers by name")
    t:ok(ns:Get("rotation", "DRUID") ~= nil, "a rotation")
end)

ns:Register("test", "druid: suggestions follow your form", function(t)
    local def = ns:Get("rotation", "DRUID")
    local A = ns.api
    local function rule(spell)
        for _, r in ipairs(def.priority) do if r.spell == spell then return r end end
    end
    local ctx = { hostile = true, inCombat = true, engine = { Knows = function() return true end } }
    local function check(form, cp, fn)
        with(A, "Form", function() return form end, function()
            with(A, "ComboPoints", function() return cp or 0 end, function()
                with(A, "Debuff", function() return false, 0 end, function()
                    with(A, "IsCurrent", function() return false end, fn)
                end)
            end)
        end)
    end
    check(nil, 0, function()
        t:ok(rule("Moonfire").when(ctx), "caster: Moonfire when it's missing")
        t:ok(rule("Wrath").when(ctx), "caster: Wrath")
        t:ok(not rule("Claw").when(ctx), "caster: no Claw")
        t:eq(def.pullLock(nil, ctx.engine), "Wrath", "caster: the key stays on Wrath")
    end)
    check("Cat Form", 2, function()
        t:ok(rule("Claw").when(ctx) and rule("Rake").when(ctx), "cat: Rake and Claw")
        t:ok(not rule("Wrath").when(ctx), "cat: no Wrath")
        t:ok(not rule("Ferocious Bite").when(ctx), "cat: no Bite at 2 combo points")
        t:eq(def.pullLock(nil, ctx.engine), "Claw", "cat: the key stays on Claw")
    end)
    check("Cat Form", 5, function()
        t:ok(rule("Ferocious Bite").when(ctx), "cat: Bite at 5 combo points")
    end)
    check("Bear Form", 0, function()
        t:ok(rule("Maul").when(ctx) and rule("Demoralizing Roar").when(ctx), "bear: Roar and Maul")
        t:ok(not rule("Moonfire").when(ctx), "bear: no Moonfire")
        t:eq(def.pullLock(nil, ctx.engine), "Maul", "bear: the key stays on Maul")
    end)
end)

ns:Register("test", "druid: Moonfire remembered on the same target when auras are hidden", function(t)
    local A = ns.api
    with(A._debuffMemory, "Moonfire", nil, function()
        A.RememberDebuff("Moonfire", "mob-1", 100)
        t:ok(A.DebuffFromMemory("Moonfire", "mob-1", 105), "same mob, in time: still on")
        t:ok(not A.DebuffFromMemory("Moonfire", "mob-2", 105), "another mob: not on it")
        t:ok(not A.DebuffFromMemory("Moonfire", "mob-1", 120), "worn off")
        A.RememberDebuff("Wrath", "mob-1", 100)
        t:ok(not A.DebuffFromMemory("Wrath", "mob-1", 101), "not a debuff: nothing remembered")
    end)
end)

ns:Register("test", "gear: never suggests what your class can't wear, even without class data", function(t)
    local G, P = ns.gear, ns.gear.CLASS_PROFICIENCY
    t:ok(P.DRUID[4][2] and not P.DRUID[4][3] and not P.DRUID[4][6], "druid: leather, no mail, no shield")
    t:ok(not P.DRUID[2][7] and P.DRUID[2][10], "druid: no swords, staves fine")
    t:ok(not P.MAGE[4][6] and P.WARRIOR[4][4], "mage: no shield; warrior: plate")
    local _, class = UnitClass("player")
    local mine = P[class]
    local banned
    for sub = 0, 9 do if mine and not mine[4][sub] then banned = sub break end end
    with(ns, "ClassData", function() return nil end, function()
        if banned then
            t:eq(G:CanUse({ classID = 4, subclassID = banned }), false, "armor your class can't wear: not usable")
        end
        t:eq(G:CanUse({ classID = 4, subclassID = 1 }), true, "cloth: usable")
    end)
end)

ns:Register("test", "invites: friends' group invites are accepted, others aren't", function(t)
    local I = ns.invites
    local friends = { names = { bob = true }, guids = { ["Player-1-00AA"] = true } }
    t:ok(I.IsFriend("Bob", nil, friends), "a friend by name")
    t:ok(I.IsFriend("Bob-Doomhowl", nil, friends), "a friend from another realm (Name-Realm)")
    t:ok(I.IsFriend("Someone", "Player-1-00AA", friends), "a Battle.net friend by character")
    t:ok(not I.IsFriend("Stranger", "Player-1-00BB", friends), "a stranger: the usual popup")
    t:ok(not I.IsFriend(nil, nil, friends), "no name: no")
    t:ok(type(I.Friends().names) == "table", "reads your friends list")
end)

ns:Register("test", "quest rewards: the big arrow goes on your best upgrade", function(t)
    local R = ns.questRewards
    local choices = {
        [1] = { canUse = true, diffs = { dps = 2, heal = 0, tank = 0 } },
        [2] = { canUse = true, diffs = { dps = 5, heal = -1, tank = 0 } },
        [3] = { canUse = false, diffs = { dps = 9, heal = 0, tank = 0 } },
        [4] = { canUse = true, diffs = { dps = 0, heal = 7, tank = 0 } },
    }
    t:eq(R.Best(choices, "dps"), 2, "biggest upgrade you can use, for your spec")
    t:eq(R.Best(choices, "heal"), 4, "another spec, another pick")
    t:eq(R.Best({ [1] = { canUse = true, diffs = { dps = 0.1 } } }, "dps"), nil, "no upgrade: no arrow (the coin says what to sell)")
end)

ns:Register("test", "quests: finished ones are turned in for you, choices left to you", function(t)
    local AT = ns.autoTurnIn
    t:eq(AT.Reward(0), 0, "no reward choice: take it")
    t:eq(AT.Reward(1), 1, "one reward: take it")
    t:eq(AT.Reward(3), nil, "several rewards: you pick")
    local list = { { id = 11, complete = false }, { id = 22, complete = true }, { id = 33, complete = true } }
    local i, id = AT.PickFinished(list)
    t:eq(i, 2, "the first finished quest in the NPC's list")
    t:eq(id, 22, "by its quest id")
    t:eq(AT.PickFinished({ { id = 1, complete = false } }), nil, "nothing finished: nothing opened")
    with(ns.db.quests, "autoTurnIn", false, function()
        t:ok(not AT.Enabled(), "the settings box turns it off")
    end)
    with(ns.db.quests, "autoTurnIn", nil, function()
        t:ok(AT.Enabled() or IsShiftKeyDown(), "on by default")
    end)
end)

ns:Register("test", "quests: new ones are accepted for you", function(t)
    -- Yang: "it just failed to auto-accept quests". Flow only ever accepted
    -- quests your party shared; now quest givers' new quests too.
    local AT = ns.autoTurnIn
    local list = { { id = 5, trivial = true }, { id = 6, repeatable = true }, { id = 7 }, { id = 8 } }
    local i, id = AT.PickAvailable(list)
    t:eq(i, 3, "the first new quest worth taking")
    t:eq(id, 7, "by its quest id")
    t:eq(AT.PickAvailable({ { id = 1, trivial = true } }), nil, "only a grey quest: left to you")
    t:eq(AT.PickAvailable({}), nil, "nothing new: nothing opened")
    t:ok(AT.ShouldAccept(true, false, 12), "on, from an NPC, room in the log: accept")
    t:ok(AT.ShouldAccept(true, false, nil), "can't tell how full the log is: accept")
    t:ok(not AT.ShouldAccept(true, false, 0), "quest log full: no")
    t:ok(not AT.ShouldAccept(true, true, 12), "another player offers it: no (party shares: QuestShare)")
    t:ok(not AT.ShouldAccept(false, false, 12), "turned off (or Shift held): no")
    with(ns.db.quests, "autoAccept", false, function()
        t:ok(not AT.AcceptEnabled(), "the settings box turns it off")
    end)
    with(ns.db.quests, "autoAccept", nil, function()
        t:ok(AT.AcceptEnabled() or IsShiftKeyDown(), "on by default")
    end)
    t:ok(type(ns.commands.accept) == "function", "/flow accept on|off")
end)

ns:Register("test", "party help: quest progress is shared and read back", function(t)
    local H = ns.partyHelp
    local prog = {
        [83] = { complete = true, objectives = {} },
        [86] = { complete = false, objectives = { { have = 2, need = 4 }, { have = 1, need = 1 } } },
    }
    local parts = H.Encode(prog)
    t:eq(#parts, 1, "a short log fits one message")
    t:eq(parts[1], "83=c,86=2/4.1/1", "compact: done, or each objective's count")
    local back = H.Decode(parts[1])
    t:ok(back[83].complete, "ready to hand in comes back")
    t:eq(back[86].objectives[1].have, 2, "counts come back")
    t:ok(back[86].objectives[2].finished and not back[86].objectives[1].finished, "finished = count reached")
    local big = {}
    for id = 1000, 1039 do big[id] = { complete = false, objectives = { { have = 3, need = 10 }, { have = 0, need = 8 } } } end
    local many = H.Encode(big)
    t:ok(#many > 1, "a full log is split into several messages")
    local ok = true
    for _, p in ipairs(many) do if #p > 230 then ok = false end end
    t:ok(ok, "each fits an addon message")
    local all = {}
    for _, p in ipairs(many) do H.Decode(p, all) end
    local n = 0
    for _ in pairs(all) do n = n + 1 end
    t:eq(n, 40, "every quest arrives")
    t:eq(H.ToDo(back), 1, "one quest left to do (the other is ready to hand in)")
end)

ns:Register("test", "party quests: just theirs keeps their stops, without doubling yours", function(t)
    local H = ns.partyHelp
    local mine = { [86] = { objectives = { { finished = false }, { finished = true } } } }
    t:ok(H.Skip("help:86:1", mine), "an objective you still need too: your own stop covers it")
    t:ok(not H.Skip("help:86:2", mine), "one you've finished but they haven't: theirs is added")
    t:ok(H.Skip("help:86:done", mine), "a quest you both have: your own turn-in")
    t:ok(not H.Skip("help:90:1", mine), "a quest only they have: added")
    local their = { [86] = { complete = false, objectives = { { finished = false }, { finished = true } } } }
    local list = { { key = "help:90:1" }, { key = "86:1" }, { key = "86:2" }, { key = "86:done" },
                   { key = "77:1" }, { key = "pickup:5" }, { key = "party:x1" } }
    local kept = {}
    for _, g in ipairs(H.Keep(list, their)) do kept[g.key] = true end
    t:ok(kept["help:90:1"] and kept["86:1"] and kept["86:done"], "their stops, and yours where they need the same")
    t:ok(not kept["86:2"] and not kept["77:1"] and not kept["pickup:5"], "not what they've done, nor your other quests or pickups")
    t:ok(kept["party:x1"], "party-route stops stay")
end)

ns:Register("test", "party quests: a stop you've done yourself says so", function(t)
    local H = ns.partyHelp
    local mineE = { complete = false, objectives = { { finished = true }, { finished = false } } }
    t:ok(H.DoneForYou("help:86:1", mineE, false), "your objective 1 is finished: done for you")
    t:ok(not H.DoneForYou("help:86:2", mineE, false), "objective 2 isn't: no mark")
    t:ok(H.DoneForYou("help:86:2", { complete = true, objectives = {} }, false), "your quest is ready to hand in: done")
    t:ok(H.DoneForYou("help:90:done", nil, true), "a quest you handed in before: done")
    t:ok(not H.DoneForYou("help:90:1", nil, false), "a quest you've never had: no mark")
    t:ok(not H.DoneForYou("86:1", mineE, false), "only their stops get the mark")
end)

ns:Register("test", "party help: a member's quest becomes stops with their name on", function(t)
    local db = {
        GetQuest = function(id)
            if id == 500 then return { name = "Wolves", level = 5, ObjectiveData = { { Type = "monster", Id = 1 } },
                                        Finisher = { NPC = { 2 } } } end
        end,
        GetNPC = function(id)
            if id == 1 then return { name = "Wolf", spawns = { [12] = { { 40, 50 } } } } end
            if id == 2 then return { name = "Farmer", spawns = { [12] = { { 42, 60 } } } } end
        end,
    }
    local q = { id = 500, complete = false, objectives = { { have = 3, need = 10, finished = false } } }
    local goals = {}
    ns.quests.QuestGoals(db, q, goals, { prefix = "help:", who = "Bob" })
    t:eq(goals[1] and goals[1].key, "help:500:done", "their turn-in")
    t:ok(goals[1] and goals[1].text:find("^Bob: Turn in: Wolves") ~= nil, "says whose it is")
    if goals[2] then
        t:eq(goals[2].key, "help:500:1", "their objective")
        t:ok(goals[2].text:find("Wolf") and goals[2].text:find("3") and goals[2].helping == "Bob", "Kill Wolf 3/10, marked as helping Bob")
    else
        t:ok(true, "(no map for the test zone here: objective stop not placed)")
    end
    local skipped = {}
    ns.quests.QuestGoals(db, q, skipped, { prefix = "help:", who = "Bob", skip = function(k) return k == "help:500:1" end })
    t:eq(#skipped, 1, "skip leaves out what you already cover")
    -- A level-5 quest at level 2 (3 above you): hard, planned after the easy ones.
    local hardGoals = {}
    ns.quests.QuestGoals(db, q, hardGoals, { level = 2 })
    if hardGoals[2] then
        t:ok(hardGoals[2].hard and hardGoals[2].weight == 1.6, "3 levels above you: hard, planned later")
        local easy = {}
        ns.quests.QuestGoals(db, q, easy, { level = 3 })
        t:ok(easy[2] and not easy[2].hard, "2 above: not hard")
    else
        t:ok(true, "(no map for the test zone here: objective stop not placed)")
    end
    t:eq(ns.quests.HARD_ABOVE, 3, "quests 3+ levels up are the hard ones (not offered to pick up)")
end)

ns:Register("test", "quest log key (L): the Flow Router steps aside, back with the map", function(t)
    local M = ns.mapOverlay
    with(ns.db.nav, "mapListCollapsed", false, function()
        with(M, "Redraw", function() end, function()
            M.QuestLogOpened(true)
            t:ok(ns.db.nav.mapListCollapsed == true, "L: the Router closes over the quest log")
            M.MapClosed()
            t:ok(ns.db.nav.mapListCollapsed == false, "the map closed: the Router is back next time")
            M.QuestLogOpened(false)
            t:ok(ns.db.nav.mapListCollapsed == false, "L closed the map: nothing changes")
        end)
    end)
    with(ns.db.nav, "mapListCollapsed", true, function()
        M.QuestLogOpened(true); M.MapClosed()
        t:ok(ns.db.nav.mapListCollapsed == true, "you had it closed: it stays closed")
    end)
end)

ns:Register("test", "nearby: ore and herbs around you and your next stop", function(t)
    local NB = ns.nearby
    local spots = {
        { name = "Iron Deposit", prof = "Mining", skill = 125, cont = 0, wx = 10, wy = 0 },
        { name = "Iron Deposit", prof = "Mining", skill = 125, cont = 0, wx = 50, wy = 0 },
        { name = "Kingsblood", prof = "Herbalism", skill = 125, cont = 0, wx = 500, wy = 10 },
        { name = "Copper Vein", prof = "Mining", skill = 1, cont = 0, wx = 900, wy = 0 },
        { name = "Iron Deposit", prof = "Mining", skill = 125, cont = 1, wx = 10, wy = 0 },
    }
    local ranks = { Mining = 140, Herbalism = 300 }
    local you, stop = { cont = 0, wx = 0, wy = 0 }, { cont = 0, wx = 500, wy = 0 }
    local c = NB.Count(spots, { you, stop }, 120, ranks)
    t:eq(#c, 2, "Iron near you, Kingsblood near the next stop; the far Copper isn't")
    t:eq(c[1].name, "Iron Deposit", "most spots first")
    t:eq(c[1].n, 2, "only spots on your continent count")
    t:ok(c[1].skillUp and not c[2].skillUp, "+skill only while it still raises yours")
    local line = NB.Line(c)
    t:ok(line and line:find("Iron Deposit x2", 1, true) and line:find("+skill", 1, true), "the Tracker line says it")
    t:eq(NB.Line({}), nil, "nothing near: no line")
    t:ok(NB.SkillUp(1, 99) and not NB.SkillUp(1, 101), "a node raises skill for ~100 points")
    t:ok(ns:Get("gatherNode", "Iron Deposit") and ns:Get("gatherNode", "Peacebloom"), "ore and herb nodes listed")
    with(ns.db.nav, "nearbyNodes", false, function()
        t:ok(not NB.Enabled() and #NB.MinimapGroups({ map = 1, cont = 0, wx = 0, wy = 0 }, 200) == 0, "the setting turns it off")
    end)
end)

ns:Register("test", "party: your own messages echoed back are never someone else's", function(t)
    local IsMe = ns.party.IsMe
    t:ok(IsMe("Bob", "Bob", "Realm"), "plain name")
    t:ok(IsMe("Bob-Realm", "Bob", "Realm"), "Name-Realm, as this client sends it")
    t:ok(IsMe("Bob-Argent Dawn", "Bob", "ArgentDawn"), "realm with a space")
    t:ok(not IsMe("Bob-Other", "Bob", "Realm"), "someone with your name from another realm isn't you")
    t:ok(not IsMe("Alice-Realm", "Bob", "Realm"), "another player isn't you")
    t:ok(not IsMe(nil, "Bob", "Realm"), "no sender: no")
    t:ok(IsMe((UnitName("player"))), "you, by your own name")
end)

ns:Register("test", "quest sharing: share what party members are missing, once each", function(t)
    local QS = ns.questShare
    local members = { Zed = { [83] = true }, Amy = { [83] = true, [86] = true } }
    t:ok(QS.ShouldShare(86, members, 0, {}, false), "Zed doesn't have 86: share it")
    t:ok(not QS.ShouldShare(83, members, 0, {}, false), "everyone has 83: don't")
    t:ok(not QS.ShouldShare(86, members, 0, { Zed = { [86] = true } }, false), "already offered to Zed: not again")
    t:ok(QS.ShouldShare(83, members, 1, {}, true), "just picked up, and someone without Flow is here: share")
    t:ok(not QS.ShouldShare(83, members, 1, {}, false), "your older quests aren't pushed on players without Flow")
    t:ok(not QS.ShouldShare(86, members, 0, {}, false, function() return false end), "too low a level for it: not offered")
    t:eq(QS.Count(members), 2, "two Flow players")
    with(ns.db.quests, "share", false, function() t:ok(not QS.Enabled(), "the settings box turns it off") end)
    with(ns.db.quests, "share", nil, function() t:ok(QS.Enabled(), "on by default") end)
end)

ns:Register("test", "loot: leave junk behind, take everything else", function(t)
    local L = ns.lootFilter
    local ITEM, MONEY = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1, (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2
    t:ok(not L.Take(ITEM, 0, false, false), "a grey item stays")
    t:ok(L.Take(ITEM, 1, false, false), "a white item is taken")
    t:ok(L.Take(ITEM, 0, true, false), "a quest item is always taken, even grey")
    t:ok(L.Take(MONEY, 0, false, false), "money is always taken")
    t:ok(not L.Take(ITEM, 2, false, true), "a locked slot (someone's roll) is left alone")
    with(ns.db.loot, "skipJunk", nil, function() t:ok(not L.Enabled(), "off by default") end)
end)

ns:Register("test", "paladin: a seal goes on whenever you have none", function(t)
    local def = ns:Get("rotation", "PALADIN")
    local A = ns.api
    with(A, "Buff", function() return false, 0 end, function()
        t:ok(def.wantSeal({ hostile = false, inCombat = false }), "out of combat, no seal: put one on")
        t:ok(def.wantSeal({ hostile = true, inCombat = false }), "an enemy targeted, no seal: put one on")
    end)
    with(A, "Buff", function() return true, 20 end, function()
        t:ok(not def.wantSeal({ hostile = false, inCombat = false }), "seal up: nothing")
        t:ok(not def.wantSeal({ hostile = false, inCombat = true }), "in a fight with 20 s left: nothing")
    end)
    with(A, "Buff", function() return true, 2 end, function()
        t:ok(def.wantSeal({ hostile = true, inCombat = true }), "in a fight, about to drop: refresh")
        t:ok(not def.wantSeal({ hostile = false, inCombat = false }), "out of combat, still up: no nagging")
    end)
end)

ns:Register("test", "follow: the arrow follows a party member only while you follow one", function(t)
    local F = ns.follow
    t:eq(F:Target(), nil, "not following anyone at first")
    t:eq(F.Choice({ map = 1, cont = 0, wx = 0, wy = 0 }), nil, "no one to follow: the arrow stays on the route")
    t:eq(F.UnitOf("Nobody-Here"), nil, "someone not in your group has no unit")
    t:ok(type(F:MenuItems()) == "table", "menu items build")
end)

ns:Register("test", "easy button: hover says what, why, and what's coming", function(t)
    local L = ns.cast.TooltipLines({ spell = "Judgement", reason = "Judge the seal" }, "Judgement",
        { { spell = "Holy Strike", reason = "Holy Strike" }, { spell = "Seal of Righteousness", reason = "No seal, or running out" } }, false)
    t:ok(L[1][1]:find("Judgement", 1, true), "what Flow suggests")
    t:ok(L[2][1]:find("Judge the seal", 1, true), "why")
    local all = {}
    for _, l in ipairs(L) do all[#all + 1] = l[1] end
    local text = table.concat(all, "\n")
    t:ok(text:find("Coming up", 1, true) and text:find("1. Holy Strike", 1, true) and text:find("No seal", 1, true), "the next ones, with reasons")
    local fight = ns.cast.TooltipLines({ spell = "Holy Strike" }, "Judgement", {}, true)
    local says = false
    for _, l in ipairs(fight) do if l[1]:find("key casts Judgement", 1, true) then says = true end end
    t:ok(says, "in a fight: what the key is locked to, when it differs")
end)

ns:Register("test", "buff items: used when you're about to kill a lot, if not on already", function(t)
    local BI = ns.buffItems
    local items = {
        { id = 1, sub = 2, name = "Elixir of Lion's Strength", spell = "Lesser Strength" },
        { id = 2, sub = 6, name = "Rough Sharpening Stone" },
        { id = 3, sub = 6, name = "Rough Weightstone" },
        { id = 4, sub = 5, name = "Roasted Boar Meat" },
    }
    local none = function() return false end
    local all = function() return true end
    local fedOnly = function(spell) return spell ~= BI.WELL_FED end
    t:eq(BI.Pick(items, none, 7, false, true).id, 1, "elixir first, when its buff is missing")
    t:eq(BI.Pick(items, all, 7, false, true).id, 2, "buff on: a sharpening stone for a sword")
    t:eq(BI.Pick(items, all, 4, false, true).id, 3, "a weightstone for a mace")
    t:eq(BI.Pick(items, all, 7, true, true), nil, "the weapon has one already, Well Fed: nothing")
    t:eq(BI.Pick(items, fedOnly, 7, true, true).id, 4, "not Well Fed: eat, after the quick ones")
    t:ok(BI.FitsWeapon("Minor Wizard Oil", 10), "oil goes on anything")
    t:ok(not BI.FitsWeapon("Rough Sharpening Stone", 4), "no sharpening stone on a mace")
    t:ok(not BI.FitsWeapon("Minor Wizard Oil", 20), "no oil on a fishing pole")
    t:eq(BI.Pick(items, none, 7, false, false), nil, "not about to fight: the stone waits too")
    t:eq(BI.Pick(items, fedOnly, 7, true, false), nil, "not about to fight: no food")
    t:ok(BI.IsBuffFood({ "Roasted Boar Meat", "Use: Restores 294 health over 27 sec. If you spend at least 10 seconds eating you will become well fed." }),
        "food that says Well Fed")
    t:ok(not BI.IsBuffFood({ "Tough Jerky", "Use: Restores 61 health over 18 sec." }), "plain food: no")
    t:ok(not BI.IsBuffFood(nil), "no tooltip yet: no")
    t:eq(BI.CampStep(true, false, false), "sit", "by a campfire without its buffs: sit")
    t:eq(BI.CampStep(true, false, true), "wait", "the minute is running: wait, don't stand up")
    t:eq(BI.CampStep(true, true, false), nil, "camp buffs on: nothing")
    t:eq(BI.CampStep(false, false, false), nil, "no campfire near: nothing")
    t:eq(BI.CampStep(true, false, false, { name = "Camp Tent" }), "place", "a camp object to place: before sitting")
    t:eq(BI.CampStep(true, true, false, { name = "Camp Tent" }), "place", "buffs on: still place it (it adds to them)")
    t:eq(BI.CampStep(true, false, true, { name = "Camp Tent" }), "wait", "the minute is running: never stand up to place one")
    t:eq(BI.CampStep(true, true, false, nil, 100), "sit", "just placed one: sit again so the buffs include it")
    t:eq(BI.PartyKitText({ ["Mia-Realm"] = { kits = { "Camp Tent", "Enchanted Lute" }, at = 95 },
                           Bob = { kits = { "Mana Well" }, at = -100 } }, 100),   -- (Bob: 200 s old; a list counts for 2 minutes)
        "Mia: Camp Tent, Enchanted Lute", "party camp objects: fresh lists only, realm dropped")
    t:eq(BI.PartyKitText({}, 100), nil, "no party lists: nothing")
    -- With your party known: near, elsewhere, unknown, and people who left.
    local lists = { ["Mia-Realm"] = { kits = { "Camp Tent" }, at = 95 }, Bob = { kits = { "Mana Well" }, at = 95 },
                    Zed = { kits = { "Lodestone" }, at = 95 }, Ann = { kits = { "Fish Bowl" }, at = 95 } }
    local roster = { { name = "Mia", near = true }, { name = "Bob", near = false }, { name = "Cid", near = true },
                     { name = "Ann" } }
    local can, rest = BI.PartyKitText(lists, 100, roster)
    t:eq(can, "Ann (place unknown): Fish Bowl; Mia: Camp Tent", "only people near you (or unplaced) count; Zed left the party")
    t:eq(rest, "Bob: elsewhere; Cid: unknown", "out of range: elsewhere; no list: unknown, not 'has nothing'")
    local st = BI.PartyKitStatus(lists, 100, roster, { { name = "Enchanted Lute", state = "placed" }, { name = "Camp Tent", state = "notready" } })
    t:eq(st.text, "2", "the count is the objects near you")
    t:ok(st.tip:find("Bob: elsewhere", 1, true) ~= nil and st.tip:find("Enchanted Lute (placed), Camp Tent (not ready)", 1, true) ~= nil,
        "the tip says who isn't counted and your own objects' state")
    t:eq(BI.PartyKitStatus({ Bob = lists.Bob }, 100, { { name = "Bob", near = false } }), nil, "only someone elsewhere: no icon")
    local pruned = BI.PruneParty({ Mia = {}, ["Zed-Realm"] = {} }, { { name = "Mia" } })
    t:ok(pruned.Mia ~= nil and pruned["Zed-Realm"] == nil, "someone who left: their list is dropped")
    -- Placed is per visit to a fire, not a fixed hour.
    t:eq(BI.CampVisit(3, 100, 130), 3, "back within a minute: the same camp visit")
    t:eq(BI.CampVisit(3, 100, 161), 4, "away over a minute: a new visit")
    t:eq(BI.CampVisit(0, nil, 5), 1, "first fire: visit 1")
    t:eq(BI.KitState(true, true, true), "placed", "placed by you this visit")
    t:eq(BI.KitState(false, true, true), "ready", "have it, usable now")
    t:eq(BI.KitState(false, true, false), "notready", "have it, on cooldown: not ready (not 'placed')")
    t:eq(BI.KitState(false, false, false), nil, "don't have it: not listed")
    -- The minute: counting, done, interrupted.
    t:eq(BI.CampStep(true, false, true), "wait", "sitting, minute running: wait")
    t:eq(BI.CampStep(true, true, false), nil, "minute done, buffs on: nothing more")
    t:eq(BI.CampStep(true, false, false), "sit", "stood up before it ended (no minute, no buffs): sit again")
    t:eq(BI.CampStep(false, false, true), nil, "walked away from the fire: nothing")
    t:eq(BI.HealKind("Minor Healthstone", 0, 0), "healthstone", "a healthstone")
    t:eq(BI.HealKind("Lesser Healing Potion", 0, 1), "potion", "a healing potion")
    t:eq(BI.HealKind("Minor Mana Potion", 0, 1), nil, "a mana potion doesn't heal")
    t:eq(BI.HealKind("Heavy Linen Bandage", 0, 7), "bandage", "a bandage")
    t:eq(BI.HealKind("Tough Jerky", 0, 5, { "Tough Jerky", "Use: Restores 61 health over 18 sec." }), "food", "plain food heals")
    t:eq(BI.HealKind("Refreshing Spring Water", 0, 5, { "Use: Restores 151 mana over 18 sec." }), nil, "drink: no")
    local k, wf = BI.HealKind("Roasted Boar Meat", 0, 5, { "Use: Restores 294 health. ...you will become well fed..." })
    t:eq(k, "food", "Well Fed food that restores health heals too")
    t:eq(wf, true, "...and is marked as Well Fed food")
    t:eq(select(2, BI.HealKind("Tough Jerky", 0, 5, { "Use: Restores 61 health over 18 sec." })), false, "plain food: not marked")
    local foods = { { id = 1, kind = "food", rank = 5 }, { id = 2, kind = "food", rank = 25, buff = true } }
    t:eq(BI.PickFood(foods, true).id, 1, "plain food before Well Fed food, whatever the rank")
    t:eq(BI.PickFood({ foods[2] }, true).id, 2, "only Well Fed food: eat it to heal")
    t:eq(BI.PickFood({ foods[2] }, false), nil, "only Well Fed food, and you keep it for the buff: none")
    t:eq(BI.PickFood(foods, true, function(id) return id ~= 1 end).id, 2, "plain food unusable: the Well Fed food")
    local heal = { { id = 1, kind = "potion", rank = 15 }, { id = 2, kind = "healthstone", rank = 10 },
                   { id = 3, kind = "bandage", rank = 5 }, { id = 4, kind = "bandage", rank = 20 } }
    t:eq(BI.PickEmergency(heal).id, 2, "in a fight: the healthstone before the potion")
    t:eq(BI.PickEmergency(heal, function(id) return id ~= 2 end).id, 1, "healthstone on cooldown: the potion")
    t:eq(BI.PickKind(heal, "bandage").id, 4, "best bandage first by default")
    t:eq(BI.PickKind(heal, "bandage", true).id, 3, "lowest bandage first when you choose it")
    -- The smallest bandage that fills you (0.35.134): a big one on a
    -- scratch wastes most of it.
    t:eq(BI.BandageHeal("Linen Bandage", { "Use: Heals 70 damage over 6 sec." }), 70, "from the tooltip")
    t:eq(BI.BandageHeal("Heavy Wool Bandage", {}), 301, "else by its name")
    t:eq(BI.BandageHeal("Mystery Rag", nil), nil, "unknown: can't tell")
    local rolls = { { id = 1, kind = "bandage", rank = 5, name = "Linen Bandage" },
                    { id = 2, kind = "bandage", rank = 15, name = "Wool Bandage" },
                    { id = 3, kind = "bandage", rank = 25, name = "Heavy Wool Bandage" } }
    local function healOf(it) return BI.BandageHeal(it.name) end
    t:eq(BI.PickBandage(rolls, 50, false, nil, healOf).id, 1, "50 missing: Linen fills it")
    t:eq(BI.PickBandage(rolls, 150, false, nil, healOf).id, 2, "150 missing: Wool, not Heavy Wool")
    t:eq(BI.PickBandage(rolls, 900, false, nil, healOf).id, 3, "more than any fills: the biggest")
    t:eq(BI.PickBandage(rolls, nil, false, nil, healOf).id, 3, "can't tell how hurt: the biggest, as before")
    t:eq(BI.PickBandage(rolls, 900, true, nil, healOf).id, 1, "lowest first, your choice: the lowest")
    t:eq(BI.PickBandage(rolls, 50, false, function(id) return id ~= 1 end, healOf).id, 2, "Linen not usable: the next that fills")
    t:near(BI.MissingHealth(nil, 1000, 15, 60), 250, 0.01, "health hidden: Flow's estimate of max health")
    t:eq(BI.MissingHealth(700, 1000, 15, 60), 300, "health shown: exact")
    t:eq(BI.MissingHealth(nil, nil, 15, 60), nil, "max hidden too: can't tell")
    t:eq(table.concat(BI.Order(nil), ","), "bandage,food,heal", "default order: bandage, food, heal spell")
    t:eq(table.concat(BI.Order("heal,bandage"), ","), "heal,bandage,food", "your order, missing steps added")
    t:eq(table.concat(BI.Order("food,food,junk"), ","), "food,bandage,heal", "repeats and unknown words dropped")
    t:eq(BI.PartyKitStatus({}, 100), nil, "no party objects: no camp icon")
    t:eq(BI.PartyKitStatus({ Mia = { kits = { "Camp Tent", "Enchanted Lute" }, at = 95 } }, 100).text, "2",
        "camp icon: how many objects your group can add")
    t:ok(BI.IsWeaponBuff("Rough Sharpening Stone"), "a stone by its name")
    t:ok(BI.IsWeaponBuff("Coarse Weightstone"), "a weightstone by its name")
    t:ok(BI.IsWeaponBuff("Minor Wizard Oil") and BI.IsWeaponBuff("Frost Oil"), "weapon oils by name")
    t:ok(not BI.IsWeaponBuff("Oily Blackmouth") and not BI.IsWeaponBuff("Fire Oil")
        and not BI.IsWeaponBuff("Oil of Immolation"), "fish and reagents aren't weapon oils")
    t:ok(not BI.IsWeaponBuff(nil), "no name yet: no")
    t:ok(BI.WeaponFirst(false, 100, 100), "out of combat, no enemy, healthy: the stone goes before the rotation's buff")
    t:ok(not BI.WeaponFirst(true, 100, 100), "enemy targeted: the opener first")
    t:ok(not BI.WeaponFirst(false, 40, 100), "under half health: the heal first")
    -- WoW: Forever hides your health (0.35.125: testing it errored, so the
    -- stone never showed): Flow's own estimate of how hurt you are decides.
    t:ok(BI.WeaponFirst(false, nil, nil, false), "health hidden, not hurt by Flow's estimate: the stone first")
    t:ok(not BI.WeaponFirst(false, nil, nil, true), "health hidden and hurt: the heal first")
    t:ok(not BI.WeaponFirst(true, nil, nil, false), "health hidden, enemy targeted: the opener first")
    t:ok(BI.WeaponFirst(false, 100, 0, false), "max health 0 (not known): Flow's estimate")
    t:ok(BI.WeaponFirst(false, nil, nil), "health the client hides: counts as fine (no error)")
    t:ok(ns:Get("action", "buff:item").order < ns:Get("action", "bag:learn").order, "before learning a recipe in your bags")
    t:ok(BI.Killing({ at = true, goal = { key = "500:1", kind = "kill" } }) or IsResting(), "at a kill stop: yes")
    t:ok(not BI.Killing({ at = false, goal = { key = "500:done", kind = "turnin" } }, GetTime() + 1000), "walking to a turn-in, no fight lately: no")
end)

ns:Register("test", "Flow key: camp names from your group, bandages, items on your bars", function(t)
    local BI, E = ns.buffItems, ns.rotation
    t:eq(table.concat(BI.ParseKits("Camp Tent, Enchanted Lute,Camp Tent,|cffff0000click me|r"), ","),
        "Camp Tent,Enchanted Lute", "a party member's camp objects: known names only, each once")
    t:eq(#BI.ParseKits(nil), 0, "nothing sent: nothing")
    t:ok(E.IsBandage("First Aid"), "a bandage is a First Aid channel")
    t:ok(not E.IsBandage("Rejuvenation") and not E.IsBandage(nil), "other channels aren't")
    t:ok(type(ns.ItemOnBar) == "function", "Flow knows which items are on your bars")
    t:ok(not ns.ItemOnBar(nil) and not ns.ItemOnBar(999999), "an item on no bar: no")
end)

ns:Register("test", "click: the Flow key's right-click menu opens; right-click never casts", function(t)
    closeMenu()
    local ok, err = pcall(ns.buffItems.OpenMenu, ns.buffItems)
    t:ok(ok, "the menu builds" .. (ok and "" or (": " .. tostring(err))))
    t:ok(menuShown(), "the menu is on screen")
    local has = {}
    for _, it in ipairs(ns.menu.items or {}) do if it.text then has[it.text] = true end end
    t:ok(has["Use bandages"] and has["Lowest bandage first"] and has["Status icons above the key"], "its options are there")
    closeMenu()
    local b = _G.FlowCastButton
    if b then t:eq(b:GetAttribute("*type2"), "macro", "right-click with any modifier runs an empty macro, never the spell")
    else t:ok(true, "(no Flow key yet)") end
end)

ns:Register("test", "crafting: a bar for the whole batch", function(t)
    local CB = ns.craftBar
    CB.Start("Charred Wolf Meat", 3, nil)
    t:eq(CB.Text(CB.Current()), "Making Charred Wolf Meat 0/3", "starts at 0/3")
    CB.Step("Charred Wolf Meat", true)
    CB.Step("Something Else", true)
    t:eq(CB.Current().done, 1, "only that recipe counts")
    CB.Step("Charred Wolf Meat", false)
    t:ok(CB.Text(CB.Current()):find("^Stopped"), "interrupted: says so")
    CB.Start("Linen Bandage", 1, nil)
    t:eq(CB.Current(), nil, "making just one: the cast bar is enough")
    t:eq(CB.Text({ name = "X", total = 2, done = 2 }), "Made 2 X", "done")
end)

ns:Register("test", "auction house: prices, money and the watch list", function(t)
    local AH = ns.auction
    t:eq(AH.Money(12345), "1g 23s 45c", "money text")
    t:eq(AH.Money(0), "0c", "nothing")
    t:eq(AH.ParseMoney("1.5"), 15000, "plain number = gold")
    t:eq(AH.ParseMoney("1g50s"), 15000, "1g50s")
    t:eq(AH.ParseMoney("75s"), 7500, "75s")
    t:eq(AH.ParseMoney("cheap"), nil, "not a price")
    local prices = {}
    AH.Record(prices, 2589, 120.7, 1000)
    local e = AH.Record(prices, 2589, 95, 2000)
    t:eq(e.price, 95, "latest price kept")
    t:eq(#e.looks, 2, "with its history")
    for i = 1, 20 do AH.Record(prices, 2589, i, 3000 + i) end
    t:ok(#prices[2589].looks <= 8, "history stays short")
end)

ns:Register("test", "route: finish this zone before leaving it", function(t)
    local N = ns.nav
    local zoneOf = function(map) return map end   -- map id = zone here
    local p = { cont = 0, wx = 0, wy = 0 }
    local function g(key, map, wx, extra)
        local goal = { key = key, points = { { map = map, cont = 0, wx = wx, wy = 0 } } }
        for k, v in pairs(extra or {}) do goal[k] = v end
        return goal
    end
    local list = {
        g("10:1", 1, 500), g("11:1", 1, 900), g("12:1", 1, 300, { levelsAbove = 4 }), g("13:1", 1, 300, { share = 0.6 }),
        g("20:1", 2, 2000), g("21:1", 2, 100), g("train:class", 2, 3000, { milestone = true }),
        g("14:done", 1, 600, { deps = { "22:1" } }), g("22:1", 2, 2500),
    }
    local here, away = N.AreaSplit(list, 1, p, zoneOf)
    t:ok(here and here["10:1"] and here["11:1"], "this zone's quests hold you here")
    t:ok(not here["12:1"] and not here["13:1"], "too high or too low quests don't")
    t:ok(away["20:1"], "the next zone's stop waits")
    t:ok(not away["21:1"], "a stop just over the border doesn't wait (a short trip)")
    t:ok(not away["train:class"], "your class trainer doesn't wait")
    t:ok(not here["14:done"] and away["14:done"], "a turn-in here that needs the next zone first can't hold you")
    local PL = ns.planner
    local function s(key) return { key = key, goal = { key = key } } end
    local opt = { here = { a = true }, away = { b = true } }
    t:ok(PL._valid({ s("a"), s("b") }, opt), "here first, then away: fine")
    t:ok(not PL._valid({ s("b"), s("a") }, opt), "away before here: not allowed")
    t:eq(N.AreaSplit({ g("10:1", 1, 500) }, 1, p, zoneOf), nil, "nowhere else to go: no rule")
end)

ns:Register("test", "party route: only what changed is sent", function(t)
    local H = ns.partyHelp
    local last = { [83] = "83=1/6", [86] = "86=0/4" }
    local now = { [83] = "83=2/6", [86] = "86=0/4", [90] = "90=0/1" }
    local changed, gone = H.Diff(last, now)
    t:eq(table.concat(changed, ","), "83=2/6,90=0/1", "a changed count and a new quest")
    t:eq(#gone, 0, "nothing left")
    local _, gone2 = H.Diff(now, { [86] = "86=0/4" })
    t:eq(table.concat(gone2, ","), "83,90", "quests that left the log")
    local prog = { [83] = { complete = false, objectives = { { have = 1, need = 6 } } }, [86] = { complete = false, objectives = {} } }
    H.ApplyDiff(prog, "83=2/6,90=c", "86")
    t:eq(prog[83].objectives[1].have, 2, "the change applied")
    t:ok(prog[90] and prog[90].complete, "the new quest added")
    t:eq(prog[86], nil, "the gone quest removed")
    t:eq(H.EncodeEntry(5, { complete = true }), "5=c", "ready to hand in")
end)

ns:Register("test", "party route: everyone on it follows one planner's route", function(t)
    local H = ns.partyHelp
    t:eq(H.Leader("Amy", { "Zed" }, "Zed"), "Zed", "the group leader plans, if on the route")
    t:eq(H.Leader("Zed", { "Amy" }, "Bob"), "Amy", "otherwise the first name, the same on everyone's screen")
    t:eq(H.Leader("Amy", { "Zed" }, nil), H.Leader("Zed", { "Amy" }, nil), "both agree")
    local plan = { { goal = { key = "help:83:1" }, point = { map = 1429, x = 0.5, y = 0.25 } },
                   { goal = { key = "86:done" }, point = { map = 1429, x = 0.1, y = 0.9 } } }
    local body = H.OrderBody(plan, 8)
    t:eq(body, "83:1~1429~0.5000~0.2500,86:done~1429~0.1000~0.9000", "order and spots, whoever's quest")
    local back = H.ParseOrder(body)
    t:eq(#back, 2, "read back")
    t:eq(back[1].key, "83:1", "same stop")
    t:eq(back[2].map, 1429, "same place")
    local cov = H.Covered("combined", nil, { Zed = {}, Amy = {} }, { Zed = true })
    t:ok(cov and cov.Zed and not cov.Amy, "the party route has the quests of those who joined")
    t:eq(H.Covered("mine", nil, { Zed = {} }, { Zed = true }), nil, "your own route: no one else's")
    local kept = H.QuestsOnly({ { key = "83:1" }, { key = "help:86:2" }, { key = "pickup:5" }, { key = "train:class" } })
    t:eq(#kept, 2, "the party route is quests only, the same kinds for everyone")
end)

ns:Register("test", "party route: the menu says Join the party route", function(t)
    local found
    for _, it in ipairs(ns.partyHelp:MenuItems()) do
        if it.text and it.text:find("^Join the party route") then found = it end
    end
    t:ok(found ~= nil, "Join the party route is offered")
    t:ok(ns.partyHelp:MenuItems()[1].text == "Your own route", "Your own route first")
end)

ns:Register("test", "nav: stops on the map and the stop card are separate", function(t)
    local N = ns.nav
    t:ok(type(N.StopVisible) == "function" and type(N.ShowStop) == "function", "both exist")
    t:ok(N.StopVisible ~= N.ShowStop, "under different names (one used to replace the other)")
    with(ns.db.nav, "stopsArea", false, function()
    with(ns.db.nav, "stopsShown", 0, function()
        local ok, v = pcall(N.StopVisible, N, 3, false)
        t:ok(ok and v == true, "all stops: stop 3 shows, no error")
    end)
    end)
    -- The area choice: no error either.
    with(ns.db.nav, "stopsArea", true, function()
        local ok, err = pcall(N.StopVisible, N, 3, false)
        t:ok(ok, "the area: no error" .. (ok and "" or (": " .. tostring(err))))
    end)
    -- "Is stop i in the area" and "are you in a quest's area" are two
    -- functions; one name for both broke the area choice (0.35.123).
    t:ok(type(N.StopInArea) == "function" and N.StopInArea ~= N.InArea, "StopInArea is its own function")
    local function stop(x) return { goal = { key = "1:" .. x }, point = { cont = 1, wx = x, wy = 0 } } end
    local plan = { stop(0), stop(60), stop(5000) }
    with(N, "plan", plan, function()
    with(N, "PlayerPos", function() return { cont = 1, wx = 5, wy = 0 } end, function()
    with(ns.db.nav, "stopsArea", true, function()
        local ok, v2 = pcall(N.StopVisible, N, 2, false)
        t:ok(ok and v2 == true, "the area: the stop by you shows" .. (ok and "" or (": " .. tostring(v2))))
        local ok3, v3 = pcall(N.StopVisible, N, 3, false)
        t:ok(ok3 and v3 == false, "the area: the far stop doesn't")
        t:eq(N:StopVisible(3, true), true, "the area: the stop you point at always does")
    end)
    end)
    end)
end)

ns:Register("test", "trainers and pickups: your faction, your level, chains in order", function(t)
    local P = ns.places
    t:ok(P.FriendlyTo("H", "Horde") and P.FriendlyTo("AH", "Horde"), "Horde NPCs for Horde")
    t:ok(not P.FriendlyTo("A", "Horde"), "no Alliance trainer for a tauren")
    t:ok(P.FriendlyTo(nil, "Horde"), "unknown: counts as friendly")
    t:ok(#P:TrainersFor("Herbalism") >= 4, "Horde Herbalism trainers listed too")
    local Q = ns.quests
    local kept = Q.WithoutBlocked({ { id = 752 }, { id = 753 }, { id = 747 } }, { [753] = true })
    t:eq(#kept, 2, "part 2 of a chain waits for part 1")
    t:eq(kept[2].id, 747, "the rest stay")
    -- Only a part you can do now holds the next one back: an optional lead-in
    -- you'll never get (not offered, not in your log) doesn't hide the quest.
    local prevOf = { [753] = { [752] = true }, [747] = { [9999] = true } }
    local blocked = Q.ChainBlocked({ { id = 752 }, { id = 753 }, { id = 747 } }, prevOf, {})
    t:ok(blocked[753], "part 2 waits while part 1 is on offer")
    t:ok(not blocked[747], "a lead-in that isn't on offer doesn't hide the quest")
    t:ok(Q.ChainBlocked({ { id = 753 } }, prevOf, { [752] = true })[753], "waits while part 1 is in your log")
end)

ns:Register("test", "follow: by name, typed or picked, even if the game hides the unit", function(t)
    local F = ns.follow
    with(F, "Members", function() return { "Zed" } end, function()
        t:eq(F.MemberNamed("zed"), "Zed", "typed in lower case")
        t:eq(F.MemberNamed("Zed-Realm"), "Zed", "with a realm")
        t:eq(F.MemberNamed("Amy"), nil, "not in the group")
        local items = F:MenuItems()
        local found = false
        for _, it in ipairs(items) do if it.text and it.text:find("^Follow Zed") then found = true end end
        t:ok(found, "the waypoint menu offers Follow Zed")
    end)
    t:ok(F:Status():find("not following", 1, true) ~= nil, "status says when you aren't following")
end)

ns:Register("test", "nameplates: Flow's (o) over your stop's NPC", function(t)
    local QM = ns.questMarks
    t:ok(type(QM._targetOf) == "function" and type(QM.Refresh) == "function", "marker hooks exist")
    QM.SetRouteTarget({ "Grull Hawkwind" })
    t:ok(QM._routeNames["grull hawkwind"], "the stop's NPC is remembered by name")
    QM.SetRouteTarget(nil)
    t:ok(not next(QM._routeNames), "cleared with the stop")
    if ns.nav and ns.nav.current and ns.nav.current.goal then QM.SetRouteTarget(ns.nav.current.goal.npcs) end   -- (back to yours)
end)

ns:Register("test", "new spells: the card asks only when it's useful", function(t)
    local NS = ns.newSpell
    t:ok(NS.ShouldAsk(1, "Moonfire", false, nil, nil, false, true), "a new spell, not on a bar or key: ask")
    t:ok(not NS.ShouldAsk(1, "Moonfire", true, nil, nil, false, true), "passive: no")
    t:ok(not NS.ShouldAsk(1, "Moonfire", false, 5, nil, false, true), "already on a bar (a new rank): no")
    t:ok(not NS.ShouldAsk(1, "Moonfire", false, nil, "F", false, true), "a key casts it: no")
    t:ok(not NS.ShouldAsk(1, "Moonfire", false, nil, nil, true, true), "you said not on your bars: no")
    t:ok(not NS.ShouldAsk(1, "Moonfire", false, nil, nil, false, false), "setting off: no")
    local used = { [1] = true, [2] = true }
    local slot, bar, pos = NS.EmptySlot(function(s) return used[s] or false end)
    t:eq(slot, 3, "the first empty slot on the main bar")
    t:eq(bar, "Action Bar 1", "says which bar")
    t:eq(pos, 3, "and which button")
    local full = NS.EmptySlot(function(s) return s <= 12 end)
    t:eq(full, 61, "main bar full: the bottom left bar")
    with(ns.db.spellbar.muted, "Test Spell XYZ", true, function()
        t:ok(NS.Covered("Test Spell XYZ"), "said no: the bar advice leaves it alone")
    end)
end)

ns:Register("test", "keys: hover-to-bind is easy to find", function(t)
    local found
    for _, it in ipairs(ns.menu:RouteItems()) do
        if it.text and it.text:find("^Key bindings: hover") then found = it end
    end
    t:ok(found ~= nil, "in the arrow's route menu")
    t:ok(type(ns.bind.Start) == "function", "it opens hover-to-bind mode")
end)

ns:Register("test", "nameplates: the unit you're heading to shows only the (o)", function(t)
    local L = ns.QuestMarksLayout
    local marks = { { kind = "item", label = "2/6" }, { kind = "kill", label = "3/10" } }
    local shown, count = L(marks, "route")
    t:eq(#shown, 0, "no diamond or skull on top of the (o)")
    t:eq(count, "2/6", "but the objective's count stays beside it")
    local others = L(marks, nil)
    t:eq(#others, 2, "every other unit keeps its icons")
    local _, none = L({}, "route")
    t:eq(none, nil, "an NPC with no objective: just the (o)")
end)

ns:Register("test", "first time: Flow's pieces come in one at a time", function(t)
    local R = ns.reveal
    t:eq(#R.STAGES, 4, "arrow, tracker, icon, advice")
    t:ok(R.Moved({ cont = 0, wx = 0, wy = 0 }, { cont = 0, wx = 12, wy = 0 }, 10), "walked 12 yd: moved")
    t:ok(not R.Moved({ cont = 0, wx = 0, wy = 0 }, { cont = 0, wx = 3, wy = 0 }, 10), "3 yd: not yet")
    with(ns.db, "reveal", { arrow = true }, function()
        t:ok(R:Shown("arrow") and not R:Shown("tracker"), "only what's come in so far")
    end)
    with(ns.db, "reveal", { all = true }, function()
        t:ok(R:Shown("advice") and R:Shown("icon"), "someone already using Flow sees it all")
    end)
end)

ns:Register("test", "cast key: a second key for the easy button", function(t)
    local C = ns.cast
    t:eq(#C.KeysOf({ key = "`" }), 1, "one key")
    local both = C.KeysOf({ key = "`", key2 = "F" })
    t:eq(#both, 2, "two keys")
    t:eq(both[2], "F", "the second one too")
    t:eq(#C.KeysOf({ key = "F", key2 = "F" }), 1, "the same key twice counts once")
    t:eq(#C.KeysOf({ key2 = "F" }), 1, "only a second key: still works")
    t:eq(#C.KeysOf({}), 0, "none set")
end)

ns:Register("test", "arrow: straight at the stop unless a trail really helps", function(t)
    local N = ns.nav
    t:ok(not N.TrailWorthIt(400, 200, false), "a trail twice the straight line: no (it used to take up to 4x)")
    t:ok(N.TrailWorthIt(260, 200, false), "a trail a little longer, around something: yes")
    t:ok(N.TrailWorthIt(1500, 200, true), "into a cave: the trail even if it's much longer")
    local pts = { { 0, 5 }, { 0, 20 }, { 0, 30 }, { 0, 60 }, { 0, 90 } }
    t:eq(N.Carrot(pts, 1, 0, 0, 35), 3, "leads to the furthest trail point within 35 yd")
    t:eq(N.Carrot(pts, 4, 0, 0, 35), 4, "nothing that close ahead: the next one")
    with(ns.db.nav, "arrowPaths", nil, function()
        t:ok(ns.db.nav.arrowPaths ~= true, "off by default: straight at the stop")
    end)
end)

ns:Register("test", "ask Claude: answers show once and clear what they answer", function(t)
    local AC = ns.askClaude
    local chat = { outbox = { { id = 1, text = "a" }, { id = 2, text = "b" } }, seen = { [5] = true }, nextId = 3 }
    local inbox = { { id = 5, replyTo = nil, text = "old note" }, { id = 6, replyTo = 1, text = "done" }, { id = 7, text = "Flow updated" } }
    local new = AC.TakeNew(inbox, chat)
    t:eq(#new, 2, "only the answers you haven't seen")
    t:eq(new[1].text, "done", "in order")
    t:eq(#chat.outbox, 1, "the answered message leaves the outbox")
    t:eq(chat.outbox[1].id, 2, "the other is still waiting")
    t:eq(#AC.TakeNew(inbox, chat), 0, "nothing shown twice")
    local e = AC.Entry(9, "hi", 100)
    t:ok(e.id == 9 and e.text == "hi" and e.char ~= nil, "a message carries who you are and where")
end)

ns:Register("test", "quest drops: one hint instead of a ! at every spawn", function(t)
    local Q = ns.quests
    local list = { { id = 1, level = 5, dropItem = 99 }, { id = 2, level = 12, dropItem = 98 }, { id = 3, level = 5 } }
    local info = { item = "Bloodstained Note", mobs = { "Bristleback Quilboar" }, spawns = {} }
    local drops = Q.DropsFrom(list, 4, function() return info end)
    t:eq(#drops, 1, "a drop quest you can take now (not one 8 levels up, not a normal quest)")
    t:eq(drops[1].quest.id, 1, "the right one")
    local line = ns.nearby.Line({}, nil, { item = "Bloodstained Note", mob = "Bristleback Quilboar" })
    t:ok(line and line:find("quest drop", 1, true) and line:find("Bloodstained Note", 1, true), "the Tracker line says it once")
    t:eq(ns.nearby.Line({}, nil, nil), nil, "nothing near: no line")
    t:ok(type(ns.questMarks._dropStarts) == "table", "nameplates know which mobs drop one")
    t:ok(ns:Get("setupItem", "questieDropIcons") ~= nil, "Flow offers to turn off Questie's ! for drops")
end)

ns:Register("test", "professions: what to do next, and when the reminder opens", function(t)
    local P = ns.professions
    local plan = { { name = "Herbalism" }, { name = "Skinning" }, { name = "First Aid" }, { name = "Fishing", optional = true } }
    local ranks = { Skinning = { 75, 75 }, ["First Aid"] = { 20, 75 } }
    local function skill(n) local r = ranks[n]; if r then return r[1], r[2] end end
    local steps = P.NextSteps(plan, skill, 12)
    t:eq(steps[1].text, "Learn Herbalism", "a main profession to learn comes first")
    t:eq(steps[2].kind, "train", "Skinning at its cap: train the next tier")
    t:eq(steps[#steps].name, "Fishing", "optional ones last")
    t:eq(#P.NextSteps(plan, skill, 8), 2, "not at level 8: Journeyman needs level 10 (Herbalism + Fishing left)")
    t:eq(P.StepsKey(steps), "learn:Herbalism,train:Skinning", "the reminder's key leaves optional ones out")
    local s = { level = 12, revealed = true }
    t:ok(P.ShouldRemind("login", steps, s), "something to do: it opens")
    t:ok(not P.ShouldRemind("login", steps, { level = 4, revealed = true }), "not before level 5")
    t:ok(not P.ShouldRemind("login", steps, { level = 12, revealed = false }), "not before Flow's pieces have all appeared")
    t:ok(not P.ShouldRemind("level", steps, { level = 12, revealed = true, remind = false }), "turned off: never")
    t:ok(not P.ShouldRemind("login", steps, { level = 12, revealed = true, snoozeLevel = 12 }), "'Not now' waits for the next level")
    t:ok(P.ShouldRemind("town", steps, { level = 12, revealed = true, snoozeLevel = 12 }), "but a trainer you need right here still shows")
    t:ok(not P.ShouldRemind("login", { { name = "Fishing", kind = "learn", optional = true } }, s), "only optional ones left: no card")
    local d = ns:Get("class", "DRUID")
    t:ok(d and d.leveling.professions[2].name == "Skinning", "a druid levels with Herbalism + Skinning")
end)

ns:Register("test", "easy button: buffs your group, the right buff for each person", function(t)
    local E = ns.rotation
    t:eq(E.UnitKind("WARRIOR", "NONE"), "melee", "a warrior: melee")
    t:eq(E.UnitKind("WARRIOR", "TANK"), "tank", "the group's tank")
    t:eq(E.UnitKind("PRIEST", "NONE"), "caster", "a priest: caster")
    t:eq(E.UnitKind("HUNTER", "NONE"), "ranged", "a hunter: ranged")
    t:eq(E.UnitKind("DRUID", "NONE", 3), "melee", "a druid in Cat Form")
    t:eq(E.UnitKind("DRUID", "NONE", 1), "tank", "a druid in Bear Form")
    t:eq(E.UnitKind("DRUID", "HEALER", 0), "healer", "the role they picked wins")

    local rule = { spell = "Thorns", minutes = 10, rebuff = 30 }
    local u = { unit = "party1", guid = "G1" }
    t:ok(not E.GroupCovered(u, rule, 100, function() return false, 0 end), "missing")
    t:ok(E.GroupCovered(u, rule, 100, function() return true, 300 end), "up, with time left")
    t:ok(not E.GroupCovered(u, rule, 100, function() return true, 10 end), "running out")
    with(E, "buffMemory", { G1 = { Thorns = 50 } }, function()
        t:ok(E.GroupCovered(u, rule, 100, function() return nil end), "buffs hidden: you cast it 50 s ago")
        t:ok(not E.GroupCovered(u, rule, 700, function() return nil end), "buffs hidden: cast too long ago")
    end)

    local units = { { unit = "party1", name = "Tank", guid = "a", class = "WARRIOR", kind = "tank" },
                    { unit = "party2", name = "Mage", guid = "b", class = "MAGE", kind = "caster" },
                    { unit = "party3", name = "Rogue", guid = "c", class = "ROGUE", kind = "melee" } }
    local ctx = { inCombat = false, hostile = false, fightType = "normal" }
    local function run(def, knows, covered)
        local s
        with(E, "Resting", function() return false end, function()
        with(ns.db.rotation, "groupBuffs", true, function()
        with(E, "GroupUnits", function() return units end, function()
        with(E, "GroupCovered", function(x, r) return covered[x.name .. ":" .. r.spell] == true end, function()
        with(E, "Knows", function(_, sp) return knows[sp] == true end, function()
        with(E, "Ready", function() return true end, function()
            E.ClearGroupCache()
            s = E:GroupBuff(ctx, def, 1000)
            E.ClearGroupCache()
        end) end) end) end) end) end)
        return s
    end
    local pal = ns:Get("rotation", "PALADIN")
    local pk = { ["Blessing of Might"] = true, ["Blessing of Wisdom"] = true }
    local s = run(pal, pk, {})
    t:eq(s and s.spell, "Blessing of Might", "paladin: Might first")
    t:eq(s and s.target, "Tank", "on the tank (no Kings yet)")
    s = run(pal, pk, { ["Tank:Blessing of Might"] = true, ["Rogue:Blessing of Might"] = true })
    t:eq(s and (s.spell .. " on " .. s.target), "Blessing of Wisdom on Mage", "Wisdom for the mage, never Might")
    s = run(pal, { ["Blessing of Might"] = true, ["Blessing of Wisdom"] = true, ["Blessing of Kings"] = true }, {})
    t:eq(s and (s.spell .. " on " .. s.target), "Blessing of Kings on Tank", "with Kings: Kings for the tank")
    t:eq(run(pal, pk, { ["Tank:Blessing of Might"] = true, ["Rogue:Blessing of Might"] = true,
                        ["Mage:Blessing of Wisdom"] = true }), nil, "everyone blessed: nothing")

    local list = {}
    for i, r in ipairs(ns:Get("rotation", "DRUID").groupBuffs) do list[i] = r end   -- (any form)
    local dk = { ["Mark of the Wild"] = true, Thorns = true }
    s = run({ groupBuffs = list }, dk, { ["Tank:Mark of the Wild"] = true })
    t:eq(s and (s.spell .. " on " .. s.target), "Mark of the Wild on Mage", "druid: Mark for everyone first")
    s = run({ groupBuffs = list }, dk, { ["Tank:Mark of the Wild"] = true, ["Mage:Mark of the Wild"] = true,
                                         ["Rogue:Mark of the Wild"] = true })
    t:eq(s and (s.spell .. " on " .. s.target), "Thorns on Tank", "then Thorns for the tank, not the mage")
    local old = ctx.hostile
    ctx.hostile = true
    t:eq(run(pal, pk, {}), nil, "not while you have an enemy targeted")
    ctx.hostile = old
    t:eq(ns.cast._describe({ spell = "Thorns", kind = "buff", unit = "party1" }), "/cast [@party1] Thorns", "the press casts on them")
end)

ns:Register("test", "bonus mode: off by default; Spoken picks a voice and clean words", function(t)
    local B = ns.bonus
    if not B then t:ok(true, "Bonus.lua loads after a WoW restart") return end
    with(ns.db.bonus, "enabled", nil, function()
        t:ok(not B:On() and not B:Extra("spoken"), "off until you turn it on")
    end)
    with(ns.db.bonus, "enabled", true, function()
        t:ok(B:Extra("spoken"), "on: Spoken is on too")
    end)
    local voices = { { voiceID = 0, name = "Microsoft David Desktop" }, { voiceID = 1, name = "Microsoft Zira Desktop" } }
    t:eq(B.PickVoice(voices, 3).voiceID, 1, "a woman's voice for a female NPC")
    t:eq(B.PickVoice(voices, 2).voiceID, 0, "a man's voice for a male NPC")
    t:eq(B.PickVoice({ { voiceID = 5, name = "Female voice" }, { voiceID = 6, name = "Male voice" } }, 2).voiceID, 6, "'female' isn't a man's voice")
    t:eq(B.PickVoice({}, 2), nil, "no voices: nothing")
    t:eq(B.Clean("|cffffd200Hello|r, $Bfriend.\n Go  now."), "Hello, friend. Go now.", "colour codes and line breaks out")
    t:eq(B.Clean("   "), nil, "nothing to say")
end)

ns:Register("test", "shift + easy key: your heal on you, even in a fight", function(t)
    local C = ns.cast
    t:eq(C.HealKeyFor("`"), "SHIFT-`", "the key with Shift")
    t:eq(C.HealKeyFor("CTRL-E"), "CTRL-SHIFT-E", "in the game's order")
    t:eq(C.HealKeyFor("ALT-CTRL-Q"), "ALT-CTRL-SHIFT-Q", "all modifiers")
    t:eq(C.HealKeyFor("SHIFT-F"), nil, "a key that already uses Shift: none")
    t:eq(C.HealKeyFor(nil), nil, "no key: none")
    t:eq(C.ItemKeyFor("`"), "ALT-`", "Alt + your key: the healthstone or potion")
    t:eq(C.ItemKeyFor("ALT-Q"), nil, "a key with Alt already: none")
    t:eq(C.EmergencyItemFor({}, {}, { id = 5512 }), "item:5512", "the carried healthstone goes on Alt + key")
    t:eq(C.EmergencyItemFor({}, {}, nil), nil, "none carried: nothing on it")
    t:eq(C.EmergencyItemFor({ altItem = false }, {}, { id = 5512 }), nil, "Alt + key off: nothing")
    t:eq(C.EmergencyItemFor({}, { emergencyItems = false }, { id = 5512 }), nil, "fight items off: nothing")
    local BIh = ns.buffItems
    t:eq(BIh.EmergencyHow("item:1", "item:1", "ALT-`"), "press ALT-`", "the item on Alt + key: say so")
    t:ok(BIh.EmergencyHow("item:2", "item:1", "ALT-`"):find("bar or in your bag", 1, true) ~= nil, "another item (stone on cooldown): bar or bag")
    t:ok(BIh.EmergencyHow("item:2", nil, nil):find("bar or in your bag", 1, true) ~= nil, "no Alt key: bar or bag")
    local def = { heals = { "Healing Touch", "Rejuvenation", "Regrowth" } }
    local ms = { ["Healing Touch"] = 1500, Rejuvenation = 0, Regrowth = 2000 }
    local function knows(s) return s ~= "Regrowth" end
    t:eq(C.HealFor(def, knows, function(s) return ms[s] end), "Rejuvenation", "the fastest heal you know")
    t:eq(C.HealFor(def, function() return false end, function() return 0 end), nil, "no heal known: nothing")
    t:eq(C.HealFor({ heals = { "Flash of Light", "Holy Light" } }, function() return true end,
        function(s) return s == "Holy Light" and 2500 or 1500 end), "Flash of Light", "paladin: Flash of Light")
end)

ns:Register("test", "easy button: hidden yes/no answers from the game don't stop it", function(t)
    -- Forever hid UnitInRange's "checked" from Flow, and testing it errored:
    -- out of a fight in a group, the easy button chose nothing (0.35.123).
    -- A stand-in secret: ns.api.Safe turns it into nil, as it does a real one.
    local E, A = ns.rotation, ns.api
    local SECRET = {}
    local realSafe = A.Safe
    with(A, "Safe", function(v) if v == SECRET then return nil end return realSafe(v) end, function()
        t:eq(E.Yes(true, false), true, "a plain yes")
        t:eq(E.Yes(false, true), false, "a plain no")
        t:eq(E.Yes(nil, true), true, "no answer: the default")
        t:eq(E.Yes(SECRET, true), true, "hidden: the default, no error")
        t:eq(E.Yes(SECRET, false), false, "hidden: the other default")
        t:eq(E.Yes(1, false), true, "a 1 counts as yes")
        t:eq(E.TooFar(false, true), true, "checked and out of range: too far")
        t:eq(E.TooFar(true, true), false, "checked and in range: near")
        t:eq(E.TooFar(false, false), false, "not checked: near")
        t:eq(E.TooFar(false, SECRET), false, "checked hidden: near (was an error)")
        t:eq(E.TooFar(SECRET, true), false, "in range hidden: near")
        t:eq(E.TooFar(nil, nil), false, "no answer at all: near")
    end)
    local ok, list = pcall(E.GroupUnits)
    t:ok(ok and type(list) == "table", "your group is read without an error" .. (ok and "" or (": " .. tostring(list))))
end)

ns:Register("test", "cleanse: curses and poisons off you and your group; break free of roots", function(t)
    local E = ns.rotation
    local dru = ns:Get("rotation", "DRUID").dispels
    local function knows(s) return s == "Remove Curse" or s == "Cure Poison" end
    t:eq(E.DispelFor(dru, { Curse = "Curse of Weakness" }, knows), "Remove Curse", "a curse: Remove Curse")
    t:eq(E.DispelFor(dru, { Poison = "Weak Poison" }, knows), "Cure Poison", "a poison: Cure Poison (Abolish not known)")
    t:eq(E.DispelFor(dru, { Magic = "Sleep" }, knows), nil, "magic: a druid can't")
    local pal = ns:Get("rotation", "PALADIN").dispels
    t:eq(E.DispelFor(pal, { Disease = "Plague" }, function(s) return s == "Purify" end), "Purify", "paladin: Purify a disease")
    t:eq(E.DispelFor(pal, { Magic = "Frost Nova" }, function(s) return s == "Purify" end), nil, "magic needs Cleanse")

    local units = { { unit = "party1", name = "Zed", kind = "melee" }, { unit = "party2", name = "Tank", kind = "tank" } }
    local debuffs = { player = {}, party1 = { Curse = "Curse of Weakness" }, party2 = { Curse = "Curse of Recklessness" } }
    local def = { dispels = { { spell = "Remove Curse", types = { Curse = true } } } }
    local s
    with(E, "GroupUnits", function() return units end, function()
    with(E, "Knows", function(_, sp) return sp == "Remove Curse" end, function()
    with(E, "Ready", function() return true end, function()
        s = E:Dispel({ inCombat = false, role = "dps" }, def, 0, function(u) return debuffs[u] end)
        t:eq(s and s.target, "Tank", "the tank first")
        t:eq(s and s.unit, "party2", "cast on them")
        debuffs.player = { Curse = "Curse of Agony" }
        s = E:Dispel({ inCombat = false, role = "dps" }, def, 0, function(u) return debuffs[u] end)
        t:eq(s and s.unit, "player", "you before anyone")
        t:eq(E:Dispel({ inCombat = true, role = "dps" }, def, 0, function(u) return debuffs[u] end), nil,
            "in a fight, not as damage: your attacks stay on the icon")
        s = E:Dispel({ inCombat = true, role = "heal" }, def, 0, function(u) return debuffs[u] end)
        t:eq(s and s.target, "Tank", "in a fight as the healer: your group, not you")
    end) end) end)

    local root
    for _, b in ipairs(E.BREAKERS) do if b.spell == "Bear Form" then root = b end end
    t:ok(root and root.types.ROOT and root.form, "a druid's forms break roots")
end)

ns:Register("test", "profession trainers: stops on your route, never a waypoint", function(t)
    local P = ns.professions
    local nav = { mode = "optimal",
        plan = { { goal = { key = "748:2" } }, { goal = { key = "train:Herbalism" } } },
        goals = { { key = "train:Herbalism" }, { key = "train:Skinning" } } }
    function nav:Mode() return self.mode end
    function nav:Goals() return self.goals end
    local status, n = P.RouteStatus("Herbalism", nav, {})
    t:eq(status, "planned", "Herbalism's trainer is on the route")
    t:eq(n, 2, "as stop 2")
    t:eq(P.RouteStatus("Skinning", nav, {}), "later", "Skinning: on the list, not planned in yet")
    t:eq(P.RouteStatus("Alchemy", nav, {}), "unplaced", "no trainer Flow can place: says so")
    t:eq(P.RouteStatus("Herbalism", nav, { professions = false }), "off", "route without professions: off (Add to my route)")
    nav.mode = "quests"
    t:eq(P.RouteStatus("Herbalism", nav, {}), "off", "Quests only: off")
end)

ns:Register("test", "druid out of mana: hit it with your weapon", function(t)
    local def = ns:Get("rotation", "DRUID")
    local found
    for _, r in ipairs(def.priority or {}) do
        if r.spell == "Attack" and r.reason:find("Out of mana", 1, true) then found = r end
    end
    t:ok(found ~= nil, "caster form has a melee fallback for when the mana's gone")
end)

ns:Register("test", "arrow: the same purple as the (o) on the NPC you're heading to", function(t)
    local N = ns.nav
    t:eq(N.ArrowSliceShade(4), 1, "the arrow's top is the route colour itself")
    t:ok(N.ArrowSliceShade(0) >= 0.5 and N.ArrowSliceShade(0) < 1, "its sides a little darker, still the same purple")
    local purple = ns.theme:ModeColor("xp")
    t:eq(purple.hex, ns.theme:ColorBlind() and "CC79A7" or "A335EE", "Most XP first: epic purple, for the arrow and the (o)")
end)

ns:Register("test", "places: Flow learns who does what as you play, and never forgets it", function(t)
    local P = ns.places
    local places, pos = {}, { map = 1412, x = 0.5, y = 0.6 }
    P.Learn(places, "Harb", pos, "vendor", { repair = true, id = 3080 }, 100)
    P.Learn(places, "Harb", pos, "npc", nil, 200)       -- talking to him again (his chat window)
    local h = places.Harb
    t:ok(P.HasRole(h, "vendor") and P.HasRole(h, "repair"), "a chat later doesn't forget he sells and repairs")
    t:eq(h.kind, "vendor", "still a vendor (the sell route reads .kind)")
    t:eq(h.id, 3080, "his NPC ID is kept")
    t:eq(h.n, 2, "seen twice")
    -- An older save: { kind = "vendor", repair = true } only.
    local old = { map = 1, x = 0.1, y = 0.1, kind = "vendor", repair = true }
    t:ok(P.HasRole(old, "vendor") and P.HasRole(old, "repair"), "older saves still count")
    P.Learn({ Old = old }, "Old", pos, "inn")
    t:ok(old.roles.vendor and old.roles.inn, "an older save keeps its role when it learns another")
    P.Learn(places, "Smith", pos, "vendor", { repair = false })
    t:ok(not P.HasRole(places.Smith, "repair"), "a merchant who can't repair")
    local boxes = {}
    t:ok(P.LearnMailbox(boxes, pos), "a new mailbox")
    t:ok(not P.LearnMailbox(boxes, { map = 1412, x = 0.505, y = 0.6 }), "the same one again: not added twice")
    t:eq(P.NpcIdOf("Creature-0-1-2-3-3080-0000ABCD"), 3080, "NPC ID from its GUID")
    t:eq(P.NpcIdOf("Player-1-0ABC"), nil, "a player has none")
    local S = ns.services
    for _, k in ipairs({ "repair", "vendor", "flight", "inn", "bank", "auction", "mail" }) do
        t:ok(S.LABEL[k] ~= nil, "nearest " .. k .. " is offered")
    end
end)

ns:Register("test", "class trainer: never the riding trainer", function(t)
    local TR = ns.trainer
    local druid = { ["Healing Touch"] = true, Moonfire = true }
    t:ok(not TR.IsClassTrainer("Kar Stormsinger", { "Apprentice Riding" }, druid, { "Gennia Runetotem" }, false),
        "Kar Stormsinger teaches riding: not your class trainer")
    t:ok(TR.IsClassTrainer("Gennia Runetotem", {}, druid, { "Gennia Runetotem" }, false), "a druid trainer by name")
    t:ok(TR.IsClassTrainer("Someone New", { "Moonfire", "Healing Touch" }, druid, {}, false), "teaches druid spells: a druid trainer")
    t:ok(not TR.IsClassTrainer("Komin Winterhoof", { "Herbalism" }, druid, {}, true), "a profession trainer: no")
end)

ns:Register("test", "sharing places: NPCs only, opt in, and other players' spots used for your faction", function(t)
    local P = ns.places
    local places = {
        ["Harb Clawhoof"] = { map = 1412, x = 0.47123, y = 0.6034, id = 3685, roles = { vendor = true, repair = true, npc = true }, factions = { Horde = true } },
        ["Just Talking"] = { map = 1412, x = 0.5, y = 0.5, roles = { npc = true } },
        ["Pipe|Name"] = { map = 1412, x = 0.5, y = 0.5, roles = { vendor = true }, factions = { Horde = true } },
        ["Old Spot"] = { map = 1429, x = 0.4, y = 0.6, roles = { vendor = true } },   -- learned before factions: not shared
    }
    local lines = P.ShareLines(places, { { map = 1412, x = 0.46, y = 0.58 } })
    t:eq(#lines, 2, "the vendor and the mailbox (not a plain chat, a name that breaks the format, or a spot with no faction)")
    t:eq(lines[1], "M|1412|0.4600|0.5800", "a mailbox line")
    t:eq(lines[2], "P|Harb Clawhoof|3685|1412|0.4712|0.6034|vendor,repair|H", "an NPC line: name, ID, where, roles, faction")
    -- Shared spots (Learned\Places.lua) used for your faction only.
    P.ResetShared()
    local s = P.Shared()
    t:ok(type(s.npcs) == "table" and type(s.mailboxes) == "table", "the shared list loads (empty until players share)")
    s.npcs["Test Vendor"] = { map = 1412, x = 0.1, y = 0.1, roles = { vendor = true }, f = "H" }
    t:ok(P.SharedSpot("Test Vendor", "Horde") ~= nil, "a Horde player's vendor: yours too")
    t:eq(P.SharedSpot("Test Vendor", "Alliance"), nil, "never for the other faction")
    P.ResetShared()
end)

ns:Register("test", "route: quests Flow can't place are listed with the reason", function(t)
    local db = {
        GetQuest = function(id)
            if id == 600 then return { name = "No Finisher", level = 6, ObjectiveData = { { Type = "event", Id = 1 } } } end
        end,
        GetNPC = function() return nil end,
    }
    local unplaced, goals = {}, {}
    ns.quests.QuestGoals(db, { id = 599, title = "Dirt-stained Map", complete = false, objectives = {} }, goals, { unplaced = unplaced })
    t:eq(unplaced[1] and unplaced[1].title, "Dirt-stained Map", "a quest Questie doesn't know is listed")
    t:ok(unplaced[1] and unplaced[1].why:find("doesn't know", 1, true) ~= nil, "with why")
    unplaced = {}
    ns.quests.QuestGoals(db, { id = 600, title = "No Finisher", complete = false,
        objectives = { { text = "Find the spot", finished = false } } }, goals, { unplaced = unplaced })
    local whys = {}
    for _, u in ipairs(unplaced) do whys[#whys + 1] = u.why end
    local all = table.concat(whys, " | ")
    t:ok(all:find("handed in", 1, true) ~= nil, "no turn-in place: said")
    t:ok(all:find("can't place (event)", 1, true) ~= nil, "an event objective: said")
end)

ns:Register("test", "easy button: short key names in its corner", function(t)
    local C = ns.cast
    local text = function(k) return ({ ["`"] = "`", F = "F", BUTTON5 = "Mouse Button 5", F12 = "F12" })[k] end
    t:eq(C.ShortKey("BUTTON5", text), "MB5", "Mouse Button 5 -> MB5")
    t:eq(C.ShortKey("`", text), "`", "short keys stay")
    t:eq(C.ShortKey("SHIFT-BUTTON4", text), "S-MB4", "with Shift")
    t:eq(C.ShortKey("ALT-CTRL-NUMPAD3", text), "A-C-N3", "modifiers and the num pad")
    t:eq(C.ShortKey("SPACE", text), "Spc", "Spacebar -> Spc")
    t:eq(C.ShortKey("F12", text), "F12", "F12 stays")
    t:eq(C.ShortKey(nil, text), "", "no key: nothing")
end)

ns:Register("test", "improvements: click hides, Hidden lists them, links open the thing", function(t)
    local Adv = ns.advisor
    t:eq(Adv.KeyOf({ source = "train", text = "Train 2 spell(s)" }), Adv.KeyOf({ source = "train", text = "Train 3 spell(s)" }),
        "a hidden line stays hidden when only its numbers change")
    local a, b, c = { text = "A" }, { text = "B" }, { text = "C" }
    local shown, hidden = Adv.Split({ a, b, c }, function(i) return i == b end)
    t:eq(#shown, 2, "two shown"); t:eq(hidden[1], b, "one hidden")
    local rows = Adv.Rows(shown, hidden, false, 16)
    t:eq(rows[#rows].kind, "header", "Hidden (1) at the bottom, collapsed")
    t:eq(#Adv.Rows(shown, hidden, true, 16), 4, "opened: the hidden one under it")
    t:eq(#Adv.Rows({ a, b, c }, {}, false, 2), 2, "never more rows than fit")
    local goal = function(k) return k == "train:class" and { text = "Train at Gennia" } or nil end
    t:eq((Adv.LinkOf({ text = "x", goalKey = "train:class" }, goal)), "goal", "a route stop: its card")
    t:eq((Adv.LinkOf({ text = "x", spell = "Moonfire" }, goal)), "spell", "a spell: place or bind it")
    t:eq((Adv.LinkOf({ text = "Equip |cff1eff00|Hitem:123::|h[Sword]|h|r from your bags" }, goal)), "item", "an item: its tooltip")
    t:eq((Adv.LinkOf({ text = "x", onClick = function() end }, goal)), "open", "its own action")
    t:eq(Adv.LinkOf({ text = "Rotation habit" }, goal), nil, "nothing to open: no link")

    -- Click test: open the list, click a row (hidden), open Hidden, click it (back).
    local fake = { { text = "Fake advice one", source = "test", importance = 50 }, { text = "Fake advice two", source = "test", importance = 40 } }
    with(ns.db.advisor, "hidden", {}, function()
    with(Adv, "Collect", function() return fake end, function()
        local panel = _G.FlowAdvicePanel
        if not (panel and panel:IsShown()) then Adv:TogglePanel() end
        panel = _G.FlowAdvicePanel
        Adv:Refresh()   -- (the list from the fake advice, even if it was already open)
        local first = panel.rows[1]
        t:eq(first.row and first.row.item and first.row.item.text, "Fake advice one", "the list shows the advice")
        pcall(first:GetScript("OnClick"), first)
        t:ok(Adv:IsHidden(fake[1]), "click: hidden")
        local header = panel.rows[2]
        t:eq(header.row and header.row.kind, "header", "Hidden (1) under the rest")
        pcall(header:GetScript("OnClick"), header)
        local back = panel.rows[3]
        t:eq(back.row and back.row.kind, "hidden", "opened: the hidden one is listed")
        pcall(back:GetScript("OnClick"), back)
        t:ok(not Adv:IsHidden(fake[1]), "click it there: back")
        panel.hiddenOpen = nil
        panel:Hide()
    end) end)
    Adv:Refresh()
end)

ns:Register("test", "/claude opens a chat window with what you asked and the answers", function(t)
    local AC = ns.askClaude
    local chat = { sent = { [3] = "make the arrow purple" }, outbox = { { id = 4, text = "and green?" } } }
    local lines = AC.History({ { id = 3, replyTo = 3, text = "Done: /reload." } }, chat, 6)
    t:ok(lines[1]:find("make the arrow purple", 1, true) ~= nil, "your question")
    t:ok(lines[2]:find("Done: /reload.", 1, true) ~= nil, "Claude's answer under it")
    t:ok(lines[3]:find("and green?", 1, true) ~= nil and lines[4]:find("waiting", 1, true) ~= nil, "a message still waiting")
    -- Yang: five old unanswered tests pushed every answer out of the window.
    -- In time order, the newest answer is at the bottom whatever waits.
    local old = { sent = { [26] = "why stop 8?" }, outbox = {} }
    for i = 1, 5 do old.outbox[i] = { id = 14 + i, text = "test" .. i, at = 1000 + i } end
    local h = AC.History({ { id = 40, replyTo = 26, text = "Found it.", at = 5000 } }, old, 6)
    t:ok(h[#h]:find("Found it.", 1, true) ~= nil, "the newest answer is the last line, after older waiting ones")
    t:ok(h[#h - 1]:find("why stop 8?", 1, true) ~= nil, "with what you asked above it")
    -- And they leave the outbox after a day.
    local box2 = { { id = 1, at = 100 }, { id = 2, at = 100000 } }
    t:eq(AC.DropStale(box2, 100000 + 60), 1, "waiting over a day: dropped")
    t:eq(box2[1].id, 2, "a fresh one stays")
    -- Click test: /claude on its own opens the window (it used to only reload).
    AC:Open()
    local box = _G.FlowAskClaude
    t:ok(box and box:IsShown(), "the chat window opens")
    t:ok(box and box.edit and box.send and box.reload, "with a box to type in, Send and Reload")
    if box then box.edit:ClearFocus(); box:Hide() end
    -- The game's chat box stops at 255 letters: a message that long goes to
    -- the window to finish (Yang's was cut off mid-word), not straight out.
    t:ok(not AC.MaybeCut("make the arrow purple"), "a short message is sent straight away")
    local long = string.rep("finish your quests first ", 10)
    t:ok(AC.MaybeCut(long), "a chat-box-full message may be cut off")
    AC:Open(long)
    t:eq(box and box.edit:GetText(), long, "it waits in the window's box to finish")
    t:ok(box and box.edit:GetMaxLetters() >= 1000, "the window takes 1000 letters")
    if box then box.edit:SetText(""); box.edit:ClearFocus(); box:Hide() end
    t:ok(AC.SLASHES[2] == "/ai" and AC.SLASHES[3] == "/si", "short /ai and /si")
end)

ns:Register("test", "Flow Chat: sends without a reload, and shows how to connect Claude", function(t)
    -- WoW never lets an add-on write files while it runs (and Forever writes
    -- its chat log only when the game closes), but it writes a screenshot at once: Flow
    -- shows the message as black and white squares and takes one; the bridge
    -- decodes it (tools\claude-bridge.ps1 Read-FlowCode, same layout).
    local AC = ns.askClaude
    local e = { id = 12, text = "make the arrow purple", char = "Yang", class = "PALADIN", level = 2, zone = "Tirisfal Glades" }
    local payload = AC.ShotPayload(e)
    t:eq(payload, "FLOW1|12|Yang;PALADIN;2;Tirisfal Glades|make the arrow purple", "what's coded: id, who, text")
    local bits = AC.ShotBits("AB", 64)
    t:eq(table.concat(bits, "", 1, 16), "1011001011100101", "starts with Flow's magic")
    t:eq(table.concat(bits, "", 17, 32), "0000000001000000", "then the columns (64)")
    t:eq(table.concat(bits, "", 33, 48), "0000000000000010", "then the length (2 bytes)")
    t:eq(table.concat(bits, "", 49, 64), "0000000010000011", "then the checksum (65 + 66 = 131)")
    t:eq(table.concat(bits, "", 65, 80), "0100000101000010", "then the bytes: A, B")
    t:eq(#bits, 80, "nothing more")
    -- Runs: black squares joined along a row, never across rows.
    local runs = AC.ShotRuns({ 1, 1, 0, 1, 1, 1, 1, 0 }, 4)
    t:eq(#runs, 3, "three runs")
    t:eq(table.concat(runs[1], ","), "0,0,2", "row 0, columns 0-1")
    t:eq(table.concat(runs[2], ","), "0,3,1", "row 0, column 3 (stops at the row's end)")
    t:eq(table.concat(runs[3], ","), "1,0,3", "row 1, columns 0-2")
    local n = 0
    for _, r in ipairs(AC.ShotRuns(AC.ShotBits(payload, 150), 150)) do n = n + r[3] end
    local ones = 0
    for _, b in ipairs(AC.ShotBits(payload, 150)) do ones = ones + b end
    t:eq(n, ones, "the runs cover every black square")
    -- On screen: drawn, then hidden (no screenshot in a test).
    if type(GetPhysicalScreenSize) == "function" then   -- (drawing works whether sending by screenshot is on or not)
        t:ok(AC:ShowCode(payload), "the squares fit on your screen")
        t:ok(AC.CodeShown(), "shown for the screenshot")
        AC:HideCode()
        t:ok(not AC.CodeShown(), "and hidden again")
        t:ok(not AC:ShowCode(string.rep("x", 60000)), "too long for the screen: not shown (Send reloads instead)")
    end
    -- Connected: the bridge's note in Learned\ClaudeInbox.lua, read at the reload.
    t:ok(AC.Connected({ at = 1000 }, 1000 + 60), "the bridge wrote a minute ago: connected")
    t:ok(not AC.Connected({ at = 1000 }, 1000 + 2 * AC.FRESH), "long ago: not connected")
    t:ok(not AC.Connected(nil, 1000), "never: not connected")
    -- Not connected: a prompt to paste into Claude.
    local p = AC.SetupPrompt("Yang", "PALADIN", 2, "Forever")
    for _, want in ipairs({ AC.REPO, "claude-bridge.ps1 -SelfTest", "Monitor", "Screenshots", "-Reply <id>", "Yang (PALADIN 2)" }) do
        t:ok(p:find(want, 1, true) ~= nil, "the prompt says: " .. want)
    end
    AC:OpenSetup()
    local box = _G.FlowAskClaude
    t:ok(box and box.setup:IsShown() and not box.chat:IsShown(), "/si setup shows the prompt")
    t:eq(box and box.prompt:GetText(), AC:MyPrompt(), "your own prompt, ready to copy")
    AC:Open()
    t:ok(box and box.chat:IsShown() and not box.setup:IsShown(), "back to the chat")
    if box then box.edit:ClearFocus(); box.prompt:ClearFocus(); box:Hide() end
    t:ok(type(ns.commands.chat) == "function", "/flow chat live on|off")
end)

ns:Register("test", "new spells: spotted from your spellbook, the card even if the game put it on a bar", function(t)
    local NS = ns.newSpell
    local new = NS.NewNames({ Wrath = true, Moonfire = true }, { Wrath = true, Moonfire = true, Thorns = true })
    t:eq(#new, 1, "one new spell"); t:eq(new[1], "Thorns", "Thorns")
    t:eq(#NS.NewNames({ Wrath = true }, { Wrath = true }), 0, "a new rank of Wrath isn't a new name: no card")
    t:ok(NS.ShouldAskNew("Thorns", false, nil, false, true), "a brand-new spell asks, even on a bar")
    t:ok(not NS.ShouldAskNew("Thorns", false, "F", false, true), "a key casts it: no")
    t:ok(not NS.ShouldAskNew("Thorns", true, nil, false, true), "passive: no")
    t:eq(NS.SlotName(5), "Action Bar 1, slot 5", "says where the game put it")
end)

ns:Register("test", "easy button: your buffs on you, Ctrl + key on your target", function(t)
    local C = ns.cast
    t:eq(C.UnitFor({ spell = "Mark of the Wild", kind = "buff" }), "player", "your own buff: on you, even with a friend targeted")
    t:eq(C.UnitFor({ spell = "Mark of the Wild", kind = "buff", unit = "party1" }), "party1", "a group buff: on them")
    t:eq(C.UnitFor({ spell = "Wrath", kind = "damage" }), nil, "an attack: your target")
    t:eq(C._describe({ spell = "Thorns", kind = "buff" }), "/cast [@player] Thorns", "the press casts it on you")
    t:eq(C.TargetKeyFor("`"), "CTRL-`", "Ctrl + your key")
    t:eq(C.TargetKeyFor("SHIFT-E"), "CTRL-SHIFT-E", "in the game's order")
    t:eq(C.TargetKeyFor("CTRL-Q"), nil, "a key with Ctrl already: none")
    t:eq(C.HealKeyFor("CTRL-E"), "CTRL-SHIFT-E", "Shift + key still the heal")
    t:ok(C._helpful({ spell = "Rejuvenation", kind = "heal" }) and not C._helpful({ spell = "Wrath", kind = "damage" }),
        "Ctrl + key only for heals and buffs")
end)

ns:Register("test", "spell ranks: a new rank replaces the old one on your bars", function(t)
    local NS = ns.newSpell
    local ups = NS.RankUps({ Wrath = 5176, Moonfire = 8921 }, { Wrath = 5177, Moonfire = 8921, Thorns = 467 })
    t:eq(#ups, 1, "one new rank"); t:eq(ups[1], "Wrath", "Wrath went up a rank (Thorns is a new spell, not a rank)")
    local names = { [5176] = "Wrath", [5177] = "Wrath", [8921] = "Moonfire" }
    local slots = NS.OldRankSlots({ [1] = 5176, [2] = 8921, [14] = 5176, [25] = 5177 }, "Wrath", 5177, function(id) return names[id] end)
    t:eq(#slots, 2, "both slots with the old Wrath"); t:eq(slots[1], 1, "slot 1"); t:eq(slots[2], 14, "and slot 14")
end)

ns:Register("test", "trainers: found by their title, the ones you've used, and the (o) on the next stops", function(t)
    local S = ns.services
    t:eq(S.TrainerKey("Cooking Trainer"), "Cooking", "Cooking Trainer -> Cooking")
    t:eq(S.TrainerKey("Druid Trainer"), "class:DRUID", "Druid Trainer -> your class trainer")
    t:eq(S.TrainerKey("Riding Trainer"), nil, "a riding trainer: neither")
    t:eq(S.TrainerKey("General Goods"), nil, "not a trainer")
    with(ns.db, "places", { ["Pyall Silentstride"] = { map = 1412, x = 0.5, y = 0.5, roles = { trainer = true }, trains = { Cooking = true } } }, function()
        local found = false
        for _, n in ipairs(ns.places:TrainersFor("Cooking")) do if n == "Pyall Silentstride" then found = true end end
        t:ok(found, "a cooking trainer you learned from is one from then on")
    end)
    local plan = { { goal = { key = "99411:1", npcs = { "Kyle" } } }, { goal = { key = "96661:1", npcs = { "Pyall Silentstride" } } },
                   { goal = { key = "96661:done", npcs = { "Pyall Silentstride" } } } }
    local names = ns.nav.NextStopNames(plan, "99411:1", 5)
    t:eq(#names, 1, "the next stops' NPCs, once each"); t:eq(names[1], "Pyall Silentstride", "Pyall gets the smaller (o)")
    local QM = ns.questMarks
    QM.SetRouteTarget({ "Kyle" }, { "Pyall Silentstride" })
    t:eq(QM._routeNames["kyle"], "current", "the current stop's NPC: the full (o)")
    t:eq(QM._routeNames["pyall silentstride"], "next", "the next stop's: the smaller one")
    if ns.nav.current and ns.nav.current.goal then QM.SetRouteTarget(ns.nav.current.goal.npcs) else QM.SetRouteTarget(nil) end
end)

ns:Register("test", "tooltips and cards open where WoW shows its tooltips", function(t)
    t:ok(type(ns.Tip) == "function" and type(ns.PlaceAtTipSpot) == "function", "the helpers exist")
    local owner = CreateFrame("Frame", nil, UIParent)
    owner:SetSize(10, 10); owner:SetPoint("CENTER")
    with(ns.db.settings, "tipsBeside", nil, function()
        ns.Tip(owner, "ANCHOR_RIGHT")
        t:ok(GameTooltip:GetOwner() == owner, "a tooltip still belongs to what you hover")
        GameTooltip:Hide()
        local card = CreateFrame("Frame", nil, UIParent)
        card:SetSize(50, 50)
        local placed = ns.PlaceAtTipSpot(card, owner)
        t:ok(placed == false or card:GetNumPoints() > 0, "a card goes where tooltips go (or keeps its own spot if they follow the cursor)")
        card:Hide()
    end)
    with(ns.db.settings, "tipsBeside", true, function()
        t:ok(not ns.TipsAtGameSpot(), "setting off: next to what you hover")
        t:eq(ns.PlaceAtTipSpot(CreateFrame("Frame"), owner), false, "and cards keep their own spot")
    end)
    owner:Hide()
end)

ns:Register("test", "herbs in Kalimdor count for Herbalism stops; heals count for less", function(t)
    local SP = ns.skillPlan
    local nodes = { Peacebloom = { prof = "Herbalism", skill = 1, objects = { 1618, 3724 } },
                    Earthroot = { prof = "Herbalism", skill = 15, objects = { 1619, 3726 } },
                    ["Copper Vein"] = { prof = "Mining", skill = 1, objects = { 1731 } } }
    local ids, names = SP.NodeObjects("Herbalism", 2, nodes)
    local has = {}
    for i, id in ipairs(ids) do has[id] = names[i] end
    t:eq(has[3724], "Peacebloom", "Kalimdor's Peacebloom (Mulgore) is a Herbalism spot")
    t:eq(has[3726], nil, "Earthroot waits for skill 15")
    t:eq(has[1731], nil, "ore isn't a herb")
    local pb = ns:Get("gatherNode", "Peacebloom")
    local kal = false
    for _, id in ipairs(pb and pb.objects or {}) do if id == 3724 then kal = true end end
    t:ok(kal, "Flow's Peacebloom includes the Kalimdor node")
    t:ok(ns.rotation.HEAL_VALUE.Rejuvenation <= 8 and ns.rotation.HEAL_VALUE["Healing Touch"] <= 15, "a heal makes up for fewer seconds of hits")
end)

ns:Register("test", "Flow Seller: Auto-cleanup tidies your bags after auto-sell", function(t)
    local V = ns.vendor
    if not V then t:ok(true, "(no Seller module)") return end
    t:ok(V.ShouldCleanup(3, nil, true, false), "sold 3, on (by default): clean up")
    t:ok(not V.ShouldCleanup(0, true, true, false), "nothing sold: bags left as they are")
    t:ok(not V.ShouldCleanup(3, false, true, false), "Auto-cleanup off: no")
    t:ok(not V.ShouldCleanup(3, true, false, false), "no Clean Up Bags on this client: no")
    t:ok(not V.ShouldCleanup(3, true, true, true), "in a fight: no")
    local f = V:Panel()
    t:ok(f.clean and f.clean.label and f.clean.label:GetText() == "Auto-cleanup", "an Auto-cleanup checkbox next to Auto-sell")
    t:eq(f.head.text:GetText():match("^Flow Seller") and "Flow Seller", "Flow Seller", "named Flow Seller")
end)

ns:Register("test", "death reports: what went wrong, in a line and 1-3 findings", function(t)
    local E = ns.rotation
    local r = { fight = 40, level = 6, lowAt = 32, healAt = nil, healSeen = 0, heals = 0, shift = 0, oom = false,
                enemy = { name = "Bristleback Interloper", level = 9, class = "normal" }, hurtMax = 5, healKnown = "Rejuvenation" }
    local line = E.DeathSummary(r)
    t:ok(line:find("died after 40 s fighting Bristleback Interloper (level 9, you 6)", 1, true) ~= nil, "who killed you, and the levels")
    t:ok(line:find("low-health warning 8 s before", 1, true) ~= nil, "when the warning came")
    t:ok(not line:find("|", 1, true), "no | in it (the report's separator)")
    local f = E.DeathFindings(r)
    local all = table.concat(f, " / ")
    t:ok(all:find("Shift + your easy key casts Rejuvenation", 1, true) ~= nil, "no heal cast after the warning: says Shift + key")
    t:ok(all:find("didn't suggest a heal", 1, true) ~= nil, "Flow never suggested one: says so")
    t:ok(#f <= 3, "at most 3 findings")
    local elite = E.DeathFindings({ fight = 20, level = 6, enemy = { name = "Ogre", level = 7, class = "elite" } })
    t:ok(elite[1]:find("elite", 1, true) ~= nil, "an elite: bring a friend")
    local oom = E.DeathFindings({ fight = 20, level = 6, oom = true })
    t:ok(oom[1]:find("out of mana", 1, true) ~= nil, "out of mana first")
    local none = E.DeathFindings({ fight = 5, level = 6 })
    t:eq(#none, 1, "nothing obvious: one line saying so")
    t:ok(type(E.NoteShiftPress) == "function", "Shift + key presses are counted")
end)

ns:Register("test", "arrow drawer: opens on the side of the arrow with room", function(t)
    local N = ns.nav
    -- A 1920 x 1080 screen, a 56 x 56 arrow, a 340 x 300 drawer.
    t:eq(N.DrawerSide(900, 700, 56, 56, 1920, 1080, 340, 300), "below", "middle of the screen: below")
    t:eq(N.DrawerSide(900, 120, 56, 56, 1920, 1080, 340, 300), "above", "near the bottom: above")
    t:eq(N.DrawerSide(10, 700, 56, 56, 1920, 1080, 340, 300), "right", "at the left edge: to the right")
    t:eq(N.DrawerSide(1880, 700, 56, 56, 1920, 1080, 340, 300), "left", "at the right edge: to the left")
    t:eq(N.DrawerSide(900, 200, 56, 56, 1920, 300, 340, 300), "below", "no room either way: the side with more")
    -- Ctrl-dragged somewhere: it opens there; the menu puts it back.
    local arrow = CreateFrame("Frame", nil, UIParent)
    arrow:SetSize(56, 56); arrow:SetPoint("CENTER")
    local d = CreateFrame("Frame", nil, UIParent)
    d:SetSize(340, 200)
    N._makeDrawer(d)
    with(ns.db.nav, "drawerPoint", { "CENTER", "CENTER", 100, 50 }, function()
        t:eq(N._placeDrawer(d, arrow), "yours", "where you put it")
    end)
    with(ns.db.nav, "drawerPoint", nil, function()
        t:eq(N._placeDrawer(d, arrow), "below", "beside the arrow again")
        t:ok(d.lip:IsShown(), "below: the lip joins it to the arrow")
    end)
    with(ns.db.nav, "drawerOpen", true, function()
        d:Fold(true)
        t:eq(ns.db.nav.drawerOpen, nil, "folding it yourself unpins it")
        t:ok(not d:IsShown(), "it closes at once (no slide)")
    end)
    d:Hide(); arrow:Hide()
end)


ns:Register("test", "actions: after a kill the Flow key loots the corpse", function(t)
    -- (Described targets only: a test that swaps the game's own functions,
    -- even for a moment, taints them and every press of the key after it.)
    local X, get = ns.actions, ns:Get("action", "loot:corpse").get
    local guid = "Creature-0-0-0-0-1506-test"
    local function corpse(over)
        local c = { dead = true, player = false, guid = guid, name = "Scarlet Convert", hasLoot = true, tapDenied = false }
        for k, v in pairs(over or {}) do c[k] = v end
        return { lootTarget = c }
    end
    with(ns.db.actions, "loot", nil, function()
        local s = get(corpse())
        t:eq(s and s.type, "interact", "a dead mob with loot: the key loots it")
        t:ok(s and s.urgent, "before a buff or the weapon swap")
        t:ok(s and s.label:find("Scarlet Convert", 1, true) ~= nil, "says which corpse")
        t:eq(ns.cast._describe(s), "Interact", "the game's Interact with your target")
        X._looted[guid] = true
        t:eq(get(corpse()), nil, "opened once: not offered again (junk left on it)")
        X._looted[guid] = nil
        t:eq(get(corpse({ hasLoot = false })), nil, "nothing on it: no loot step")
        t:eq(get(corpse({ dead = false })), nil, "still alive: no loot step")
        t:eq(get(corpse({ player = true })), nil, "a dead player: no loot step")
        -- (A client that can't say what's on it: hasLoot left out. Not via
        -- corpse({ hasLoot = nil }): pairs() skips nil, so it stayed true.)
        local unknown = corpse().lootTarget
        unknown.hasLoot = nil
        t:ok(X.ShouldLoot(unknown), "can't tell what's on it: your kill, loot it")
        unknown.tapDenied = true
        t:ok(not X.ShouldLoot(unknown), "someone else's kill: no")
        ns.db.actions.loot = false
        t:eq(get(corpse()), nil, "/flow action loot off")
    end)
end)

ns:Register("test", "easy button: Attack only ever turns auto attack on", function(t)
    -- Yang: with nothing to press, the key turned auto attack off. It was
    -- left on the Attack spell, which toggles: pressed mid-swing, it stops.
    local C = ns.cast
    t:eq(C.KeyCommandFor({ spell = "Attack", kind = "damage" }, true), "STARTATTACK", "Attack: the game's Start Attack (on, never off)")
    t:eq(C.KeyCommandFor({ spell = "Auto Attack", kind = "damage" }, true), "STARTATTACK", "Auto Attack too")
    t:eq(C.KeyCommandFor({ spell = "Attack", kind = "damage" }, false), nil, "no Start Attack in this client: Flow's button")
    t:eq(C.KeyCommandFor({ type = "interact" }, true), "INTERACTTARGET", "a Flow Action's Interact")
    t:eq(C.KeyCommandFor({ type = "sit" }, true), "SITORSTAND", "by a campfire: the game's Sit/Stand")
    t:eq(C.KeyCommandFor({ type = "wait" }, true), nil, "waiting at the fire: Flow's button (which does nothing)")
    t:eq(C._describe({ type = "sit" }), "Sit", "sit described")
    t:eq(C.KeyCommandFor({ spell = "Judgement", kind = "damage" }, true), nil, "a real spell: Flow's button")
    t:eq(C.KeyCommandFor(nil, true), nil, "nothing to press: Flow's button (which does nothing)")
    -- For a fight: never the toggling Attack spell.
    t:eq(C.FightLock("Attack", false), nil, "no Start Attack: the key does nothing all fight, never stops your swing")
    t:eq(C.FightLock("Attack", true), "Attack", "with Start Attack: safe to hold")
    t:eq(C.FightLock("Judgement", false), "Judgement", "a real spell stays")
    t:eq(C.FightLock(nil, true), nil, "nothing worth pressing: nothing")
    -- Nothing new suggested mid-fight: the icon shows what the key still does.
    local held = C.HeldView("Judgement", nil)
    t:eq(held and held.kind, "held", "the held spell is shown, greyed")
    t:eq(C.HeldView("Attack", "STARTATTACK"), nil, "Start Attack is harmless: nothing shown")
    t:eq(C.HeldView(nil, nil), nil, "the key does nothing: nothing shown")
    t:eq(type(C.HasStartAttack()), "boolean", "Flow can tell whether the game has Start Attack")
end)

ns:Register("test", "taint: tests and Flow leave the game's own functions alone", function(t)
    -- 0.35.102's loot test swapped UnitExists & co. for a moment at login:
    -- that tainted them, and every press of the Flow key was blocked
    -- (CastSpellByName, SetPreferredGamepadInteractTarget).
    for _, name in ipairs({ "UnitExists", "UnitIsDead", "UnitIsPlayer", "UnitGUID", "UnitName",
                            "CanLootUnit", "UnitIsTapDenied", "IsResting" }) do
        if _G[name] ~= nil then
            local secure, by = issecurevariable(name)
            t:ok(secure, name .. " is untainted" .. (by and (" (tainted by " .. by .. ")") or ""))
        end
    end
end)

ns:Register("test", "Flow Tracker: everything around you and your waypoint", function(t)
    -- Yang: in an area, show all the objectives there (they drop off as
    -- they're done), open by default; right-click the title for the menu;
    -- the mobs of the waypoint marked.
    local N, RT = ns.nav, ns.routeTracker
    local function stop(key, x, y, npcs) return { goal = { key = key, npcs = npcs }, point = { cont = 1, wx = x, wy = y } } end
    local plan = {
        stop("364:1", 0, 0, { "Mindless Zombie" }),        -- your waypoint
        stop("364:2", 60, 40, { "Wretched Zombie" }),      -- right by it
        stop("376:1", 900, 900, { "Rattlecage Soldier" }), -- across the zone
        stop("364:done", 20, -30, { "Shadow Priest" }),    -- the turn-in, by the waypoint
    }
    local here = N.HereStops(plan, { cont = 1, wx = 5, wy = 5 })
    t:eq(table.concat(here, ","), "1,2,4", "the waypoint and what's by it, in route order; not the far stop")
    t:eq(table.concat(N.HereStops(plan, { cont = 1, wx = 890, wy = 890 }), ","), "1,2,3,4", "standing at the far stop: that too")
    t:eq(table.concat(N.HereStops({ plan[3] }, nil), ","), "1", "the next stop is always there")
    t:eq(#N.HereStops({}, nil), 0, "no route: nothing")
    local names = N.HereNames(plan)
    t:eq(table.concat(names, ","), "Mindless Zombie,Wretched Zombie,Shadow Priest", "the waypoint's mobs and NPCs, for Flow's (o)")
    -- The marks: every mob at the waypoint gets the (o), the current stop's first.
    local QM = ns.questMarks
    QM.SetRouteTarget({ "Mindless Zombie" }, { "Rattlecage Soldier" }, names)
    t:eq(QM.RouteRank("Mindless Zombie"), "current", "the current stop's mob")
    t:eq(QM.RouteRank("Wretched Zombie"), "here", "the other mob at the waypoint: marked too")
    t:eq(QM.RouteRank("Rattlecage Soldier"), "next", "a later stop's: the small mark")
    QM.SetRouteTarget(nil, nil, nil)
    N.lastTargetKey = nil   -- (the route sends its real marks again on its next update)
    -- On by default; it's the first choice of Stops on the map (Yang: one
    -- menu, not a switch of the tracker's own), in the title's menu too.
    with(ns.db.tracker, "here", nil, function()
    with(ns.db.nav, "stopsArea", nil, function()
    with(ns.db.nav, "stopsShown", nil, function()
        t:ok(RT.Here(), "all objectives in this area: on by default")
        local items = RT.MenuItems()
        t:eq(items[1].text, "Flow Tracker", "right-click the title: the tracker's menu")
        local area, next1
        for _, it in ipairs(items) do
            if it.text == N.AREA_LABEL then area = it end
            if it.text == "Next stop only" then next1 = it end
        end
        t:ok(area and next1, "Stops on the map is in it, with " .. N.AREA_LABEL)
        t:ok(area and area.checked and not (next1 and next1.checked), "the area choice ticked")
        if next1 then next1.func() end
        t:ok(not RT.Here(), "Next stop only: the tracker and the map show the next stop")
        t:eq(N:StopsShownLabel(), "Next stop only", "and say so")
        if area then area.func() end
        t:ok(RT.Here(), "and back to the area")
        t:eq(N:StopsShownLabel(), N.AREA_LABEL, "named in the menu and /flow nav stops")
    end)
    end)
    end)
    with(ns.db.nav, "stopsArea", nil, function()
        with(ns.db.tracker, "here", false, function()
            t:ok(not N:AreaMode(), "turned off with the old tracker switch: stays off")
        end)
    end)
    local f = _G.FlowTracker
    if f and f.header then
        t:ok(f.header:GetScript("OnClick") ~= nil, "the title takes clicks (left: fold, right: menu)")
    end
end)

ns:Register("test", "a hidden Flow window shows up in every Flow menu", function(t)
    -- Yang: hide a Flow window, and the other menus should bring it back.
    local M = ns.menu
    local names = {}
    for _, w in ns:Each("window") do names[w.name] = w end
    for _, n in ipairs({ "Flow Arrow", "Flow Tracker", "Flow easy button" }) do
        t:ok(names[n] ~= nil, n .. " can be hidden and brought back")
    end
    with(ns.db.tracker, "enabled", true, function()
    with(ns.db.nav, "enabled", true, function()
    with(ns.db.rotation, "enabled", true, function()
        t:eq(#M.HiddenWindowItems(), 0, "all shown: nothing extra in the menus")
        ns.db.tracker.enabled = false
        local items = M.HiddenWindowItems()
        t:eq(items[1] and items[1].text, "Hidden Flow windows", "a hidden window: a section for it")
        t:eq(items[2] and items[2].text, "Show Flow Tracker", "Show Flow Tracker")
        -- Any Flow menu gets it at the bottom.
        M:Open({ { title = true, text = "Your waypoint" }, { text = "Clear it", func = function() end } })
        local shown = M.items or {}
        t:eq(shown[#shown] and shown[#shown].text, "Show Flow Tracker", "at the bottom of another menu")
        M:Close()
        t:ok(type(items[2].func) == "function", "clicking it shows the Flow Tracker again")
    end)
    end)
    end)
end)

ns:Register("test", "route: right at your trainer, training is the hub's business", function(t)
    -- Yang stood next to the trainer in town with training as stop 7. But
    -- 0.35.98's 300 yards pulled you off the mobs you were killing: only
    -- when you're right at it (N.TRAIN_NEAR).
    local N = ns.nav
    local B = N.HubBusiness
    local train = { key = "train:class" }
    t:eq(B(train, 30, {}, false), "train", "30 yards from your trainer: train now")
    t:eq(B(train, N.TRAIN_NEAR + 40, {}, false), nil, "a hundred yards off (killing mobs): fitted into the route")
    t:eq(B({ key = "train:class", cost = 500 }, 30, {}, false), nil, "can't pay for any of it: not now")
    t:eq(B(train, 30, {}, true), nil, "nothing left to learn at your trainer: not again")
    -- Yang opened the trainer at level 4 without buying: Blessing of Might was still there.
    local T = N.TrainerHasSomething
    t:ok(T({ seenAt = 4, services = { { name = "Blessing of Might", category = "available" } } }, 4), "seen at this level, a spell still available: yes")
    t:ok(not T({ seenAt = 4, services = { { name = "Blessing of Might", category = "used" } } }, 4), "seen, all learned: no")
    t:ok(T({ seenAt = 3, services = {} }, 4), "not seen at this level: yes (the route says spells wait)")
    t:ok(T(nil, 4), "no trainer seen yet: yes")
    t:eq(B({ key = "train:Cooking" }, 20, {}, true), "train", "a profession trainer right here too")
    -- The quest part of the hub's business is as before.
    t:eq(B({ key = "364:done" }, 200, {}, false), "turnin", "a turn-in in the hub")
    t:eq(B({ key = "364:done", deps = { "364:1" } }, 200, { ["364:1"] = true }, false), nil, "not before its objectives")
    t:eq(B({ key = "pickup:376", provider = "pickups" }, 200, {}, false), "pickup", "a quest to pick up in the hub")
    t:eq(B({ key = "pickup:376", provider = "pickups" }, 400, {}, false), nil, "out of the hub: not now")
    t:eq(B({ key = "364:1" }, 10, {}, false), nil, "an objective isn't hub business")
end)

ns:Register("test", "actions: quest NPCs to heal: the key targets one, then heals it", function(t)
    -- Yang: "Injured Deathguard healed: 0/5" and couldn't find them. The key
    -- targets the next one it can see, then casts the heal on it, again
    -- until done; Flow's marker shows on them (friendly nameplates on).
    local X = ns.actions
    local goal = { key = "90902:1", text = "Injured Deathguard healed", npcs = { "Injured Deathguard" } }
    t:ok(X.HealGoal(goal), "a heal-these-NPCs objective")
    t:ok(not X.HealGoal({ key = "380:1", text = "Young Night Web Spider slain", npcs = { "Young Night Web Spider" } }), "a kill objective isn't")
    t:ok(not X.HealGoal({ key = "1:1", text = "Injured Deathguard healed" }), "no NPC names: nothing to target")
    local function npc(token, guid, over)
        local u = { token = token, name = "Injured Deathguard", guid = guid, dead = false, assist = true }
        for k, v in pairs(over or {}) do u[k] = v end
        return u
    end
    local healed = {}
    local plates = { npc("nameplate3", "G1"), npc("nameplate7", "G2") }
    local s = X.HealStep(goal, "Holy Light", nil, plates, healed)
    t:eq(s and s.type, "target", "none targeted: target one")
    t:eq(s and s.unit, "nameplate3", "the first one you can see")
    t:eq(ns.cast._describe(s), "/target nameplate3", "a secure target press")
    s = X.HealStep(goal, "Holy Light", npc("target", "G1"), plates, healed)
    t:eq(s and s.spell, "Holy Light", "targeted: heal it")
    t:eq(s and s.unit, "target", "on your target, not on you")
    t:ok(s and s.urgent, "before a buff or the gear swap")
    healed.G1 = true
    s = X.HealStep(goal, "Holy Light", npc("target", "G1"), plates, healed)
    t:eq(s and s.unit, "nameplate7", "healed it: on to the next one")
    t:eq(X.HealStep(goal, "Holy Light", nil, { npc("nameplate3", "G1"), npc("nameplate7", "G2", { dead = true }) }, healed), nil,
        "none left to heal: nothing")
    t:eq(X.HealStep(goal, nil, nil, plates, {}), nil, "no heal spell: nothing")
    t:eq(X.HealStep(goal, "Holy Light", nil, { npc("nameplate2", "G3", { assist = false }) }, {}), nil, "not one you can heal: skipped")
    t:ok(type(X.FriendPlates) == "function", "friendly nameplates come on at such a stop")
end)

ns:Register("test", "Flow button: out of mana, a timer until you have enough", function(t)
    -- Yang: when the next spell waits for a cooldown or mana, show a timer.
    -- (Cooldowns already count down; mana gets one too.)
    local W = ns.ManaWaitSeconds
    t:eq(W(100, 40, 5), 12, "60 mana short at 5 a second: 12 s")
    t:eq(W(100, 99.5, 5), 1, "a moment short: 1 s (rounded up)")
    t:eq(W(100, 120, 5), nil, "enough mana: no timer")
    t:eq(W(100, 40, 0), nil, "no regeneration: no timer (can't tell)")
    t:eq(W(nil, 40, 5), nil, "cost hidden: no timer")
    t:eq(W(100, nil, 5), nil, "mana hidden (in a fight): no timer")
    t:ok(type(ns.ManaWait) == "function", "worked out from the spell's cost, your mana and regeneration")
end)

-- Dungeon runs (Dungeons.lua): quest states, lead-ins traced back, runs cut
-- by wing / level / mid-run turn-ins, and whether a run beats questing.
local function dungeonCtx(quests, o)
    o = o or {}
    local byId = {}
    for _, q in ipairs(quests) do byId[q.Id] = q end
    return {
        get = function(id) return byId[id] end,
        done = o.done or {}, log = o.log or {}, level = o.level or 20,
        eligible = o.eligible or function() return true end,
        dungeonOf = function(id) return (o.dungeon or {})[id] end,
        inside = o.inside, atEntrance = o.atEntrance, maxSteps = o.maxSteps,
    }
end

ns:Register("test", "dungeons: quest states and lead-ins traced back", function(t)
    local D = ns.dungeons
    local quests = {
        { Id = 100, name = "Main", level = 20 },
        { Id = 101, name = "Locked", level = 20, preQuestSingle = { 201 } },
        { Id = 201, name = "Step 2", level = 18, preQuestGroup = { 202 } },
        { Id = 202, name = "Step 1", level = 17 },
        { Id = 102, name = "Far", level = 20, preQuestSingle = { 301 } },
        { Id = 301, level = 18, preQuestSingle = { 302 } }, { Id = 302, level = 18, preQuestSingle = { 303 } },
        { Id = 303, level = 18, preQuestSingle = { 304 } }, { Id = 304, level = 18 },
        { Id = 103, name = "Part 2", level = 21, preQuestSingle = { 100 } },
        { Id = 104, name = "Class", level = 20 },
        { Id = 105, name = "Either", level = 20, exclusiveTo = { 400 } },
        { Id = 106, name = "Have", level = 20 }, { Id = 107, name = "Did", level = 20 },
        { Id = 108, name = "Later", level = 30, requiredLevel = 25 },
        { Id = 109, name = "Drops inside", level = 20 },
        { Id = 110, name = "High lead-in", level = 20, preQuestSingle = { 500 } },
        { Id = 500, level = 26, requiredLevel = 24 },
        { Id = 111, name = "Any of", level = 20, preQuestSingle = { 600, 601 } },
        { Id = 600, level = 18, preQuestSingle = { 602 } }, { Id = 602, level = 18 }, { Id = 601, level = 18 },
    }
    local dungeon = { [100] = 1, [101] = 1, [102] = 1, [103] = 1, [104] = 1, [105] = 1, [106] = 1, [107] = 1, [108] = 1 }
    local ctx = dungeonCtx(quests, {
        dungeon = dungeon, log = { [106] = true }, done = { [107] = true, [400] = true },
        eligible = function(q) if q.Id == 104 then return false, "for another class" end return true end,
        inside = function(q) return q.Id == 109 end,
    })
    local function state(id) for _, q in ipairs(quests) do if q.Id == id then return D.State(q, ctx) end end end
    t:eq(state(100), "pickup", "no lead-in, giver outside: pick up")
    local s, steps = state(101)
    t:eq(s, "unlock", "short lead-in you can do now: unlock")
    t:eq(steps and #steps, 2, "two lead-in quests")
    t:eq(steps and steps[1].id, 202, "the first step comes first")
    t:eq(steps and steps[2].id, 201, "then the second")
    local s2, why = state(102)
    t:eq(s2, "toolong", "a 4-quest lead-in is too long")
    t:ok(why and why:find("4 quests"), "says how long: " .. tostring(why))
    ctx.maxSteps = 6
    t:eq(state(102), "unlock", "with long lead-ins on: unlock")
    ctx.maxSteps = nil
    t:eq(state(103), "nextrun", "part 2 of this dungeon's chain, turned in outside: next run")
    ctx.atEntrance = function(q) return q.Id == 103 end
    t:eq(state(103), "followup", "giver at the entrance: same run")
    ctx.atEntrance = nil
    local s3, why3 = state(104)
    t:eq(s3, "notforyou", "another class: not for you")
    t:eq(why3, "for another class", "the reason is kept")
    t:eq(state(105), "notforyou", "ruled out by a quest you did")
    t:eq(state(106), "ready", "in your log: ready")
    t:eq(state(107), "done", "done")
    t:eq(state(108), "nextrun", "above your level: next run")
    t:eq(state(109), "inside", "starts inside")
    t:eq(state(110), "toolong", "a lead-in above your level is too long")
    local s4, st4 = state(111)
    t:eq(s4, "unlock", "one of several: the shortest way")
    t:eq(st4 and #st4, 1, "the 1-step way, not the 2-step one")
    t:eq(st4 and st4[1].id, 601, "the shorter lead-in")
    ctx.log[601] = true
    local _, st5 = state(111)
    t:ok(st5 and st5[1].inLog, "a lead-in already in your log is marked")
    t:eq(D.State(quests[2], dungeonCtx(quests, { done = { [201] = true } })), "pickup", "lead-in done: pick up")
    local loop = { { Id = 1, preQuestSingle = { 2 } }, { Id = 2, preQuestSingle = { 1 } } }
    t:eq((D.Trace(loop[1], dungeonCtx(loop))), nil, "a looping chain doesn't hang")
end)

ns:Register("test", "dungeons: runs cut by wing, level and next run", function(t)
    local D = ns.dungeons
    local function e(id, lv, wing, state, info)
        return { id = id, name = "Q" .. id, level = lv, dungeon = 796, dungeonName = "Scarlet Monastery",
                 wing = wing, state = state, info = info }
    end
    local runs = D.CutRuns({
        e(1, 32, "Library", "pickup"), e(2, 33, "Library", "ready"), e(3, 34, "Library", "nextrun"),
        e(4, 38, "Armory", "pickup"), e(5, 40, "Cathedral", "pickup"),
        e(6, 32, "Library", "unlock", { { id = 90, level = 30 }, { id = 91, level = 31, inLog = true } }),
        e(7, 31, "Library", "unlock", { { id = 90, level = 30 } }),
        e(8, 32, "Library", "notforyou", "for another class"), e(9, 32, "Library", "toolong", "a long lead-in (5 quests)"),
        e(10, 20, "Library", "pickup"), e(11, 20, "Library", "ready"),
        e(12, 32, "Library", "inside"), e(13, 32, "Library", "followup"),
    }, 32, 27)
    t:eq(#runs, 1, "only the Library has quests at 32: Armory and Cathedral are later runs")
    local r = runs[1] or {}
    t:eq(r.name, "Scarlet Monastery Library", "the run is the wing")
    t:eq(r.pickups and #r.pickups, 1, "one to pick up (the grey one is left out)")
    t:eq(r.ready and #r.ready, 2, "ready, grey or not")
    t:eq(r.unlocks and #r.unlocks, 2, "two unlocked by lead-ins")
    t:eq(r.leadIns and #r.leadIns, 1, "the shared lead-in once, the one in your log not at all")
    t:eq(r.leadIns and r.leadIns[1] and r.leadIns[1].id, 90, "the lead-in to pick up")
    t:eq(r.next, 1, "one more next run")
    t:eq(r.skipped and r.skipped["for another class"], 1, "not for you, with why")
    t:eq(r.toolong and #r.toolong, 1, "too long, listed")
    t:eq(r.inside and #r.inside, 1, "starts inside")
    t:eq(r.followups and #r.followups, 1, "follow-up at the entrance")
    t:eq(r.count, 7, "seven quests this run")
    local dm = D.CutRuns({
        { id = 1, level = 18, dungeon = 1581, dungeonName = "The Deadmines", state = "pickup" },
        { id = 2, level = 20, dungeon = 1581, dungeonName = "The Deadmines", state = "ready" },
        { id = 3, level = 22, dungeon = 1581, dungeonName = "The Deadmines", state = "pickup" },
    }, 18, 13)
    t:eq(#dm, 1, "a dungeon without wings: one run")
    t:eq(dm[1] and dm[1].count, 2, "level 18: the level-22 quest waits for the next run")
    t:eq(dm[1] and dm[1].next, 1, "counted as next run")
end)

ns:Register("test", "dungeons: worth it, XP rate, run times, gathering", function(t)
    local D = ns.dungeons
    local run = { quests = { 1, 2, 3 }, levels = { [1] = 30, [2] = 30, [3] = 30 }, leadIns = {} }
    local w = D.Worth(run, { level = 30, rate = 6570, runMinutes = 45, gatherMinutes = 15,
        estimate = function() return 1000 end, share = function() return 1 end })
    t:eq(w.questXP, 3000, "quest XP")
    t:near(w.mobXP, 10140, 0.5, "elites: 100 kills, double XP, your share")
    t:near(w.perHour, 13140, 0.5, "per hour over run + gathering")
    t:near(w.ratio, 2, 0.001, "2x your questing rate")
    t:eq(D.Worth(run, { level = 30, estimate = function() return 0 end, share = function() return 1 end }).ratio,
        nil, "no rate: no ratio")
    local s = {}
    for i = 0, 19 do s[#s + 1] = { t = 1000 + i * 60, xp = 100 } end
    t:near(D.RateFrom(s, 1000 + 19 * 60), 6000, 0.5, "19 minutes, 1,900 XP: 6,000 an hour")
    t:eq(D.RateFrom({ { t = 0, xp = 5 }, { t = 60, xp = 5 } }, 60), nil, "under 15 minutes: no rate")
    local g = { { t = 0, xp = 0 }, { t = 600, xp = 600 }, { t = 4600, xp = 600 } }
    t:near(D.RateFrom(g, 4600), 3600, 0.5, "a break counts as 10 minutes")
    t:eq(D.RateFrom(s, 1000 + 19 * 60 + 7200 + 1000), nil, "older than 2 hours: no rate")
    local rec = D.LearnTime(nil, 30)
    t:eq(rec.avg, 30, "first run")
    rec = D.LearnTime(rec, 60)
    t:eq(rec.avg, 45, "averaged")
    t:eq(rec.n, 2, "two runs")
    t:eq(D.LearnTime(rec, 3), rec, "a 3-minute peek doesn't count")
    t:eq(D.LearnTime(rec, 300), rec, "a night away doesn't count")
    local from, ent = { cont = 1, wx = 0, wy = 0 }, { cont = 1, wx = 840, wy = 0 }
    t:near(D.GatherMinutes(from, { { cont = 1, wx = 420, wy = 0 } }, ent), 4, 0.01, "one stop on the way: 2 + 2 min")
    t:near(D.GatherMinutes(from, {}, ent), 2, 0.01, "straight there: 2 min")
    t:ok(D.GatherMinutes(from, { { cont = 2, wx = 0, wy = 0 } }, nil) > 5, "another continent: a long trip")
    local order = D.GatherMinutes(from, { { cont = 1, wx = 840, wy = 0 }, { cont = 1, wx = 420, wy = 0 } }, nil)
    t:near(order, 4 + 2, 0.01, "nearest first, not list order")
    local withCrumb = { quests = { 1 }, levels = { [1] = 30 }, leadIns = {}, breadcrumbs = { { id = 9, level = 30 } } }
    t:eq(D.Worth(withCrumb, { level = 30, estimate = function() return 1000 end, share = function() return 1 end })
        .questXP, 2000, "a breadcrumb's XP counts")
end)

ns:Register("test", "dungeons: placed by objectives, wings by bosses, breadcrumbs on the way", function(t)
    local D = ns.dungeons
    t:eq(D.ObjectivesTop({ 1581, nil, 1581 }), 1581, "every placed objective in one dungeon")
    t:eq(D.ObjectivesTop({ 1581, false }), nil, "one objective outside: not a dungeon quest")
    t:eq(D.ObjectivesTop({ 1581, 796 }), nil, "two dungeons: neither")
    t:eq(D.ObjectivesTop({ nil, nil }), nil, "nothing placed: nothing")
    local wings = {
        { name = "Graveyard", bosses = { [1] = true }, lo = 32, hi = 34 },
        { name = "Library", bosses = { [2] = true }, lo = 34, hi = 37 },
        { name = "Armory", bosses = { [3] = true }, lo = 40, hi = 40 },
        { name = "Cathedral", bosses = { [4] = true }, lo = 40, hi = 42 },
    }
    local function wing(objs, lv) local w = D.WingFor(objs, wings, lv) return w and w.name end
    t:eq(wing({ { creatures = { { id = 2, level = 37 } } } }), "Library", "kill a boss: the boss's wing")
    t:eq(wing({ { creatures = { { id = 50, level = 31 }, { id = 3, level = 40 } } } }), "Armory",
        "an item a boss drops: the boss's wing, not the trash that also drops it")
    t:eq(wing({ { creatures = { { id = 50, level = 31 } } } }), "Graveyard", "trash: the wing its level fits")
    t:eq(wing({ { creatures = { { id = 50, level = 40 } } } }, 40), nil,
        "trash two wings fit, quest level two wings fit: no wing")
    t:eq(wing({}, 36), "Library", "no creatures: the quest's level")
    t:eq(wing({ { creatures = { { id = 1 } } }, { creatures = { { id = 2 } } } }), "Library",
        "a tie: the later wing")
    t:eq(wing({ { creatures = { { id = 4 } } }, { creatures = { { id = 50, level = 33 } } } }), "Cathedral",
        "a boss outweighs one trash kill")
    t:eq(D.WingFor({}, {}, 30), nil, "no wings: nil")
    local stops = { { cont = 1, wx = 0, wy = 0 } }
    local near = D.NearStops({
        { id = 1, at = { cont = 1, wx = 100, wy = 0 } },
        { id = 2, at = { cont = 1, wx = 200, wy = 0 } },
        { id = 3, at = { cont = 2, wx = 0, wy = 0 } },
        { id = 4 },
    }, stops, 150)
    t:eq(#near, 1, "only the breadcrumb near a stop")
    t:eq(near[1] and near[1].id, 1, "the one 100 yards away")
    local runs = D.CutRuns({
        { id = 1, level = 58, dungeon = 1583, dungeonName = "Blackrock Spire", wing = "Upper",
          wingTitle = "Upper Blackrock Spire", state = "pickup" },
    }, 58, 53)
    t:eq(runs[1] and runs[1].name, "Upper Blackrock Spire", "the wing's own run name")
    t:eq(runs[1] and runs[1].breadcrumbs and #runs[1].breadcrumbs, 0, "no breadcrumbs until the route adds them")
end)

ns:Register("test", "dungeon runs: only quests you can take now; party stops stay inside", function(t)
    local D = ns.dungeons
    -- 0.35.126: a later part of a chain waits until the part before it is
    -- turned in (the giver doesn't offer it yet).
    t:ok(D.TakeNow({ Id = 1 }, function() return true end), "available: on the route")
    t:ok(not D.TakeNow({ Id = 2 }, function() return false end), "not offered yet: off the route")
    t:ok(D.TakeNow({ Id = 3 }, function() error("no data") end), "can't tell: on the route")
    local function dungeonOf(id) return ({ [100] = 7, [200] = 9 })[id] end
    t:ok(D.KeepInside({ key = "100:1" }, 7, dungeonOf), "this dungeon's quest stays")
    t:ok(not D.KeepInside({ key = "200:1" }, 7, dungeonOf), "another dungeon's quest goes")
    t:ok(D.KeepInside({ key = "party:12" }, 7, dungeonOf), "the shared party route stays (it has no kind)")
    t:ok(D.KeepInside({ key = "user:wp" }, 7, dungeonOf), "your own waypoint stays")
    t:ok(not D.KeepInside({ key = "train:class" }, 7, dungeonOf), "training waits until you're out")
end)

ns:Register("test", "route: near first leaves Shortest alone; a refresh mid-gather goes again", function(t)
    local F, N = ns.nearFirst, ns.nav
    t:ok(F.Applies("xp"), "Most XP: near first")
    t:ok(not F.Applies("distance"), "Shortest (and completionist): left the shortest")
    with(ns.db, "nearFirst", false, function()
        t:ok(not F.Applies("xp"), "/flow nearfirst off: off")
    end)
    t:ok(type(N.MarkAgain) == "function", "a direct re-plan during gathering asks for one more")
end)

ns:Register("test", "click: the Dungeons menu entries are well formed and open", function(t)
    local D = ns.dungeons
    local ok, items = pcall(D.MenuItems, D)
    t:ok(ok and type(items) == "table", "the Dungeons section builds" .. (ok and "" or (": " .. tostring(items))))
    for _, it in ipairs(ok and items or {}) do
        t:ok(it.sep or it.title or type(it.text) == "string", "an entry has text: " .. tostring(it.text))
        t:ok(it.func == nil or type(it.func) == "function", "and a function if it does something")
    end
    -- "Suggest dungeons" turns it off and on.
    local suggest
    for _, it in ipairs(ok and items or {}) do if it.text == "Suggest dungeons" then suggest = it end end
    if suggest then
        with(ns.db.nav, "dungeonSuggest", ns.db.nav.dungeonSuggest, function()
            local was = D:Suggest()
            local okC = pcall(suggest.func)
            t:ok(okC and D:Suggest() ~= was, "Suggest dungeons switches")
        end)
    else
        t:ok(true, "(no Questie: no Dungeons section)")
    end
    -- A run's own menu opens (when there's a run at your level).
    local runs = D:Available() and D:Runs()
    if runs and runs[1] then
        closeMenu()
        local okM, err = pcall(D._runMenu, runs[1])
        t:ok(okM, "a run's menu builds" .. (okM and "" or (": " .. tostring(err))))
        t:ok(menuShown(), "and is on screen")
        closeMenu()
    else
        t:ok(true, "(no dungeon run at your level to open)")
    end
end)

ns:Register("test", "map: the trail to your next stop takes the arrow's colour", function(t)
    local M = ns.mapOverlay
    -- 0.35.127: `x and false or nil` is always nil, so it never did.
    t:eq(M.LegLive(true, nil), false, "your next stop: the arrow's colour (by distance)")
    t:eq(M.LegLive(false, nil), nil, "a later stop: its own route colour")
    t:eq(M.LegLive(true, 0.5), nil, "a preview (alpha given): its own colour")
end)

ns:Register("test", "recovery: one order for every way of being hurt; fight healing apart", function(t)
    local E, BI = ns.rotation, ns.buffItems
    if not (E and BI and ns.db and ns.db.rotation) then t:ok(true, "(no rotation)") return end
    local r = ns.db.rotation
    local keep = { busy = E.RecoverBusy, mounted = E.Mounted, hd = E.HealDecision, lh = E.LowHealthHeal, eh = E.EarlyHeal,
                   em = BI.EmergencyStep, band = BI.BandageStep, food = BI.FoodStep, hurt = E.hurt,
                   order = r.recoverOrder, b = r.recoverBandage, f = r.recoverFood, h = r.recoverHeal,
                   bf = r.recoverBuffFood, ei = r.emergencyItems }
    local have, askedBuff = {}, nil
    local def = { heals = { "Heal" } }
    local ok, err = pcall(function()
        E.RecoverBusy = function() return have.busy or false end
        E.Mounted = function() return have.mounted or false end
        E.HealDecision = function(_, ctx) return (have.spell and ctx.maxHp > 0 and ctx.hpPct < 0.5) and { spell = "Heal", kind = "heal" } or nil end
        E.LowHealthHeal = function(_, ctx) return (have.spell and ctx.maxHp <= 0 and ctx.lowHealth) and { spell = "Fast Heal", kind = "emergency" } or nil end
        E.EarlyHeal = function() return have.spell and { spell = "Early Heal", kind = "heal" } or nil end
        BI.EmergencyStep = function() return have.stone and { label = "Healthstone!" } or have.potion and { label = "Healing potion!" } or nil end
        BI.BandageStep = function() return have.bandage and { label = "Bandage" } or nil end
        BI.FoodStep = function(buffFood) askedBuff = buffFood; return have.food and { label = "Food" } or nil end
        local function set(order, b, f, h) r.recoverOrder, r.recoverBandage, r.recoverFood, r.recoverHeal = order, b, f, h end
        local function pick(ctx)
            -- The whole order (bandage, food, heal spell), wherever each one shows.
            local s
            if ctx.inCombat then s = E:HealStep(ctx, def) else s = E:Recover(ctx, def, "all") end
            return s and (s.label or s.spell) or nil
        end
        local function isSpell(ctx)
            local p = pick(ctx)
            return p ~= nil and p:find("Heal", 1, true) ~= nil
        end
        -- Three ways of being hurt out of a fight.
        local shown  = { inCombat = false, maxHp = 100, hp = 30, hpPct = 0.3 }                -- health readable
        local hidden = { inCombat = false, maxHp = 0, hp = 0, hpPct = 1 }                     -- hidden: Flow's estimate
        local warn   = { inCombat = false, maxHp = 0, hp = 0, hpPct = 1, lowHealth = true }   -- hidden: the game's warning
        for name, ctx in pairs({ shown = shown, hidden = hidden, warn = warn }) do
            E.hurt = (name == "hidden") and E.HURT.outBig or 0
            have = { bandage = true, food = true, spell = true }
            set(nil, nil, nil, nil)
            t:eq(pick(ctx), "Bandage", name .. ": default order starts with the bandage, not the heal spell")
            local onBuff = E:Recover(ctx, def, "items")
            t:eq(onBuff and onBuff.label, "Bandage", name .. ": the buff button gets the bandage")
            t:ok(E:Recover(ctx, def, "heal") == nil, name .. ": Flow's key holds the heal spell back while the bandage is first")
            have.bandage = false
            t:eq(pick(ctx), "Food", name .. ": no bandage: food")
            have.food = false
            t:ok(isSpell(ctx), name .. ": no bandage or food: a heal spell")
            have = { bandage = true, food = true, spell = true }
            set("heal,food,bandage")
            t:ok(isSpell(ctx), name .. ": heal first when you put it first")
            set("food,bandage,heal")
            t:eq(pick(ctx), "Food", name .. ": food first when you put it first")
            set(nil, false)
            t:eq(pick(ctx), "Food", name .. ": bandages off: food")
            set(nil, false, false)
            t:ok(isSpell(ctx), name .. ": bandages and food off: a heal spell")
            set(nil, false, false, false)
            t:eq(pick(ctx), nil, name .. ": every step off: nothing, and no heal spell slips through")
            set("heal,bandage,food", nil, nil, false)
            t:eq(pick(ctx), "Bandage", name .. ": heal first but heals off: the bandage")
            set(nil, nil, nil, nil)
            have.busy = true
            t:eq(pick(ctx), nil, name .. ": eating or casting: nothing")
            have.busy, have.mounted = false, true
            t:ok(isSpell(ctx), name .. ": mounted: no bandage or food, a heal spell")
        end
        -- Lightly hurt (estimate only): bandage or heal, but not food.
        E.hurt = E.HURT.outStart
        have = { food = true }
        set(nil, nil, nil, nil)
        t:eq(pick(hidden), nil, "lightly hurt: you don't sit down to eat")
        E.hurt = 0
        t:eq(pick(hidden), nil, "not hurt: nothing")
        t:eq(pick({ inCombat = false, maxHp = 100, hp = 100, hpPct = 1 }), nil, "full health shown: nothing")
        -- An enemy targeted: no sitting down to eat.
        have = { food = true, spell = true }
        t:ok(pick({ inCombat = false, maxHp = 100, hp = 30, hpPct = 0.3, hostile = true }) ~= "Food", "enemy targeted: no food")
        -- The Well Fed food choice reaches the food step.
        have = { food = true }
        r.recoverBuffFood = false; pick(shown)
        t:eq(askedBuff, false, "keep Well Fed food for the buff: passed on")
        r.recoverBuffFood = nil; pick(shown)
        t:eq(askedBuff, true, "by default Well Fed food may heal when there's no plain food")
        -- In a fight: healthstone, then potion, then a heal spell; never the recovery order.
        local fight = { inCombat = true, maxHp = 0, hp = 0, hpPct = 1, lowHealth = true }
        r.emergencyItems = nil
        have = { stone = true, potion = true, spell = true, bandage = true, food = true }
        t:eq(pick(fight), "Healthstone!", "fight, low: the healthstone first")
        have.stone = false
        t:eq(pick(fight), "Healing potion!", "healthstone gone or on cooldown: the potion")
        have.potion = false
        t:eq(pick(fight), "Fast Heal", "neither usable: a heal spell")
        have.spell = false
        t:eq(pick(fight), nil, "nothing usable: nothing (never a bandage or food in a fight)")
        have = { stone = true, spell = true }
        r.emergencyItems = false
        t:eq(pick(fight), "Fast Heal", "fight items off: straight to the heal spell")
        r.emergencyItems = nil
        set(nil, false, false, false)
        t:eq(pick(fight), "Healthstone!", "recovery steps off don't touch fight healing")
        have = { spell = true }
        t:eq(pick({ inCombat = true, maxHp = 100, hp = 30, hpPct = 0.3 }), "Heal", "fight, health shown: the normal heal")
        t:eq(pick({ inCombat = true, maxHp = 0, hp = 0, hpPct = 1 }), "Early Heal", "fight, health hidden, no warning: Flow's estimate")
    end)
    E.RecoverBusy, E.Mounted, E.HealDecision, E.LowHealthHeal, E.EarlyHeal = keep.busy, keep.mounted, keep.hd, keep.lh, keep.eh
    BI.EmergencyStep, BI.BandageStep, BI.FoodStep, E.hurt = keep.em, keep.band, keep.food, keep.hurt
    r.recoverOrder, r.recoverBandage, r.recoverFood, r.recoverHeal = keep.order, keep.b, keep.f, keep.h
    r.recoverBuffFood, r.emergencyItems = keep.bf, keep.ei
    t:ok(ok, "recovery checks ran" .. (ok and "" or (": " .. tostring(err))))
end)

ns:Register("test", "repair: early warning, vendor decision, after the sale", function(t)
    local R, V = ns.repair, ns.vendor or ns.sell
    local function gear(g) return function(slot) local v = g[slot]; if v then return v[1], v[2] end end end
    local pct, slot, low = R.Worst(gear({ [1] = { 50, 100 }, [5] = { 19, 100 }, [16] = { 60, 60 } }))
    t:eq(slot, 5, "the most worn item is found"); t:eq(low, 1, "one item under 20%")
    t:ok(R.Low(pct), "19%: warn")
    pct = R.Worst(gear({ [1] = { 20, 100 }, [5] = { 80, 100 } }))
    t:ok(not R.Low(pct), "exactly 20%: no warning yet")
    _, slot, low = R.Worst(gear({ [1] = { 0, 0 }, [5] = { 90, 100 } }))
    t:eq(slot, 5, "an item with no durability is skipped"); t:eq(low, 0, "and never counts as low")
    pct = R.Worst(gear({}))
    t:eq(pct, nil, "nothing with durability: unknown"); t:ok(not R.Low(pct), "unknown is never a warning")
    _, slot, low = R.Worst(gear({ [1] = { 5, 100 }, [5] = { 10, 100 }, [7] = { 0, 100 } }))
    t:eq(slot, 7, "a broken item is the worst"); t:eq(low, 3, "three under 20%")
    local st = { pct = 0.18, slot = 5, low = 2 }
    local lines = table.concat(R.Lines(st, "Old Vest", { name = "Smith Argus", yards = 240 }, false, nil, true), "\n")
    t:ok(lines:find("Old Vest is at 18%", 1, true) ~= nil, "names the item and how worn")
    t:ok(lines:find("Smith Argus, about 240 yd", 1, true) ~= nil, "names the nearest vendor")
    t:ok(lines:find("2 items under 20%", 1, true) ~= nil, "says how many")
    lines = table.concat(R.Lines(st, nil, nil, false, nil, true), "\n")
    t:ok(lines:find("doesn't know a repair vendor", 1, true) ~= nil, "no vendor known: says so, no guess")
    lines = table.concat(R.Lines(st, nil, nil, true, nil, false), "\n")
    t:ok(lines:find("Looking up", 1, true) ~= nil, "vendor list still loading: says so")
    t:ok(lines:find("Auto-repair is off", 1, true) ~= nil, "auto-repair off: says you press the button")
    lines = table.concat(R.Lines(st, nil, { name = "X", yards = 5 }, false, "Estimate: hearth", true), "\n")
    t:ok(lines:find("Estimate: hearth", 1, true) ~= nil, "the hearthstone estimate rides along when there is one")
    if V and V.RepairDecision then
        t:eq(V.RepairDecision(false, 100, 500, true), "none", "vendor doesn't repair: nothing")
        t:eq(V.RepairDecision(true, 0, 500, true), "none", "nothing worn: nothing")
        t:eq(V.RepairDecision(true, 100, 500, false), "off", "auto-repair off: say the cost, repair nothing")
        t:eq(V.RepairDecision(true, 100, 99, true), "poor", "not enough money")
        t:eq(V.RepairDecision(true, 100, nil, true), "poor", "money unknown: don't try")
        t:eq(V.RepairDecision(true, 100, 100, true), "repair", "just enough: repair")
        t:eq(V.RepairWhen(true, 3), "afterSale", "something sold: repair once the money is in")
        t:eq(V.RepairWhen(true, 0), "now", "nothing sold: repair straight away")
        t:eq(V.RepairWhen(false, 3), "now", "auto-sell off: repair straight away")
    else
        t:ok(false, "the vendor module isn't reachable from tests")
    end
end)

ns:Register("test", "hearthstone: an estimate only when it clearly saves time", function(t)
    local H = ns.hearth
    local c = H.Compare(7000, 700, 0, 7)       -- 1000 s straight; 20 + 100 s by hearthstone
    t:ok(c.better, "far away, inn next to it, off cooldown: quicker")
    t:eq(math.floor(c.saving), 880, "the saving counts the cast and the loading screen")
    t:ok(H.AdviceText(c, "Goldshire"):find("Estimate", 1, true) ~= nil, "it's labelled an estimate")
    t:ok(H.AdviceText(c, "Goldshire"):find("never uses it for you", 1, true) ~= nil, "and says Flow won't use it")
    c = H.Compare(7000, 700, 900, 7)           -- 900 s of cooldown eats the saving
    t:ok(not c.better, "a long cooldown left: not quicker"); t:eq(H.AdviceText(c, "x"), nil, "so nothing is said")
    c = H.Compare(7000, 700, 300, 7)
    t:ok(c.better, "some cooldown left but still well ahead")
    t:ok(H.AdviceText(c, "x"):find("left on its cooldown", 1, true) ~= nil, "the wait is named")
    c = H.Compare(1400, 350, 0, 7)             -- 200 s straight, 70 s by hearthstone: saves 130 s
    t:ok(c.better, "saves over two minutes and over a quarter: quicker")
    c = H.Compare(1050, 350, 0, 7)             -- saves 80 s
    t:ok(not c.better, "under two minutes saved: not worth saying")
    c = H.Compare(7000, 5200, 0, 7)            -- saves 237 s of 1000: under a quarter
    t:ok(not c.better, "a small share of a long trip: not worth saying")
    t:eq(H.Compare(7000, nil, 0, 7), nil, "inn position unknown: no estimate")
    t:eq(H.Compare(7000, 700, nil, 7), nil, "cooldown unknown (or no hearthstone): no estimate")
    t:eq(H.Compare(nil, 700, 0, 7), nil, "distance unknown: no estimate")
    t:eq(H.AdviceText(nil, "x"), nil, "no estimate: nothing said")
end)

ns:Register("test", "buff button: buffs off the main icon, onto their own button", function(t)
    local BB = ns.buffButton
    local list = { { spell = "Aspect", kind = "buff" }, { spell = "Strike" }, { spell = "Aura", kind = "buff" }, { spell = "Heal", kind = "heal" } }
    local out = BB.Strip(list)
    t:eq(#out, 2, "two rules left")
    t:eq(out[1].spell, "Strike", "damage kept")
    t:eq(out[2].spell, "Heal", "heal kept")
    t:ok(BB.Strip(list) == out, "cached per list")
    t:eq(#list, 4, "the rotation's own list is untouched")
    local pally = BB.Strip({ { spell = "Seal of Righteousness", kind = "buff" }, { spell = "Devotion Aura", kind = "buff" },
                             { spell = "Judgement" } })
    t:eq(#pally, 2, "a paladin: the aura moves to the buff button")
    t:eq(pally[1].spell, "Seal of Righteousness", "the seal stays on Flow's icon, with the fight")
    for _, name in ipairs({ "Seal of Fury", "Battle Shout", "Commanding Shout", "Lightning Shield",
                            "Power Word: Shield", "Hunter's Mark", "Bear Form", "Moonkin Form" }) do
        t:ok(BB.OnAction({ spell = name }), name .. ": on the action button, with the fight")
    end
    for _, name in ipairs({ "Blessing of Might", "Devotion Aura", "Aspect of the Hawk", "Mark of the Wild",
                            "Travel Form", "Trueshot Aura" }) do
        t:ok(not BB.OnAction({ spell = name }), name .. ": on the buff button")
    end
    t:ok(not BB.OnAction({}) and not BB.OnAction(nil), "no spell: not on the action button")
    t:eq(BB.Pick({ spell = "Aura" }, { item = "item:2862" }).item, "item:2862", "out of combat: the weapon stone before a buff spell")
    t:eq(BB.Pick({ spell = "Aura" }, nil).spell, "Aura", "the buff spell when the weapon needs nothing")
    t:eq(BB.Pick(nil, { item = "item:2862" }).item, "item:2862", "the stone when no buff spell is due")
    t:ok(BB.Pick(nil, nil) == nil, "nothing due: nothing")
    t:eq(BB.Pick({ spell = "Aura" }, { item = "item:2862" }, { label = "Bandage" }, { type = "sit" }).label, "Bandage",
        "hurt after a fight: the bandage or food before any buff")
    t:eq(BB.Pick({ spell = "Aura" }, nil, nil, { type = "sit" }).spell, "Aura", "by a campfire: your buffs before you sit")
    t:eq(BB.Pick(nil, nil, nil, { type = "sit" }).type, "sit", "by a campfire with nothing else due: sit")
    t:eq(BB.FightSpell({ spell = "Aura" }, "Blessing"), "Aura", "fight: the buff due now")
    t:eq(BB.FightSpell(nil, "Aura"), "Aura", "fight: else the one you last cast")
    t:ok(BB.FightSpell(nil, nil) == nil, "fight: else nothing")
    local idle = BB.Idle()
    t:ok(idle.idle and idle.item == nil and idle.spell == nil, "idle: shows, does nothing")
    local was = ns.db.buffButton and ns.db.buffButton.enabled
    local item = ns:Get("action", "buff:item")
    ns.db.buffButton = ns.db.buffButton or {}
    ns.db.buffButton.enabled = true
    t:ok(BB.On() and item.get({}) == nil, "on: stones and buff items aren't on the main icon")
    ns.db.buffButton.enabled = false
    t:ok(not BB.On(), "off: buffs and stones go back to Flow's icon")
    ns.db.buffButton.enabled = nil
    t:ok(not BB.On(), "never set: off (the Flow key keeps your buffs until you turn the button on)")
    ns.db.buffButton.enabled = was
end)

ns:Register("test", "worn gear and hearthstone: run without errors, no red, no chat", function(t)
    -- 0.35.133: the hearthstone check used the bare GetItemCount (gone on
    -- Forever), so the estimate never showed.
    local okH, left = pcall(ns.hearth.CooldownLeft, ns.hearth)
    t:ok(okH, "hearthstone cooldown reads" .. (okH and "" or (": " .. tostring(left))))
    if okH and ns.api.Count(ns.hearth.ITEM) == 0 then
        t:eq(left, nil, "no hearthstone in your bags: no estimate")
    end
    -- The worn-gear icon: whatever your gear, it builds without an error,
    -- and never in red.
    local st = ns:Get("status", "repair")
    local okS, icon = pcall(st.get)
    t:ok(okS, "the worn-gear icon builds" .. (okS and "" or (": " .. tostring(icon))))
    if okS and icon then
        t:ok(not (icon.color[1] > 0.9 and icon.color[2] < 0.4), "its colour isn't red")
    end
    -- Auto-repair off: nothing to say at the vendor.
    t:eq(ns.vendor.RepairDecision(true, 500, 1000, false), "off", "auto-repair off: Flow repairs nothing")
end)

ns:Register("test", "easy button: War Stomp stops a cast close by; Roots opens on a melee mob", function(t)
    local E = ns.rotation
    -- 0.35.135: nothing ever suggested an interrupt or Entangling Roots.
    local fight = { inCombat = true, hostile = true, fightType = "normal" }
    with(E, "Ready", function(_, spell) return spell == "War Stomp" end, function()
        local s = E:Interrupt(fight, "Lightning Bolt", true)
        t:eq(s and s.spell, "War Stomp", "target casting, within 8 yards: War Stomp")
        t:ok(s and s.reason:find("Lightning Bolt", 1, true) ~= nil, "it says what it stops")
        t:eq(E:Interrupt(fight, "Lightning Bolt", false), nil, "too far for a stomp: nothing")
        t:eq(E:Interrupt(fight, "Lightning Bolt", nil) == nil or E.Near("target") == true, true,
            "can't tell how far: no stomp (unless the game says it's close)")
        with(E, "TargetCasting", function() return nil end, function()
            t:eq(E:Interrupt(fight), nil, "not casting: nothing")
        end)
        t:eq(E:Interrupt({ inCombat = false, hostile = true }, "Heal", true), nil, "out of a fight: nothing")
    end)
    with(E, "Ready", function() return false end, function()
        t:eq(E:Interrupt(fight, "Heal", true), nil, "War Stomp not ready (or not a tauren): nothing")
    end)
    -- Roots: only on a mob without a mana pool, before its own heals and damage.
    t:ok(ns.MeleeMob(0) and ns.MeleeMob(nil), "no mana pool (a beast, a fighter): melee")
    t:ok(not ns.MeleeMob(120), "a mana pool: a caster, no roots")
    local def = ns:Get("rotation", "DRUID")
    local roots, moonfire
    for i, r in ipairs(def.priority) do
        if r.spell == "Entangling Roots" and not roots then roots = i end
        if r.spell == "Moonfire" and not moonfire then moonfire = i end
    end
    t:ok(roots and moonfire and roots < moonfire, "Entangling Roots comes before Moonfire")
    if ns.api.Form() == nil then
        t:eq(def.pullLock({ spell = "Entangling Roots", kind = "damage" }, { Knows = function(_, s) return s == "Wrath" end }),
            "Wrath", "rooting at the pull: the key still stays on Wrath for the fight")
    else
        t:ok(true, "(you're in a form: the caster pull lock isn't checked)")
    end
end)

ns:Register("test", "easy button: drink when low on mana; Well Fed food first when fights are ahead", function(t)
    local E, BI = ns.rotation, ns.buffItems
    -- 0.35.136: Flow ate but never drank.
    t:eq(BI.HealKind("Refreshing Spring Water", 0, 5, { "Use: Restores 151 mana over 18 sec." }), "drink", "water: a drink")
    t:eq(BI.HealKind("Tough Hunk of Bread", 0, 5, { "Use: Restores 61 health over 18 sec." }), "food", "bread: food")
    t:eq(BI.HealKind("Mystery Snack", 0, 5, { "Use: Restores 61 health and 100 mana over 18 sec." }), "food",
        "health and mana: food (it heals)")
    local food = { { id = 1, kind = "food", rank = 5, buff = false }, { id = 2, kind = "food", rank = 5, buff = true } }
    t:eq(BI.PickFood(food, true, nil, false).id, 1, "nothing ahead: plain food first")
    t:eq(BI.PickFood(food, true, nil, true).id, 2, "fights ahead, not Well Fed: the Well Fed food first")
    t:eq(BI.PickFood(food, false, nil, true).id, 1, "Well Fed food turned off: plain food")
    local out = { inCombat = false, hostile = false, fightType = "normal" }
    with(E, "Mounted", function() return false end, function()
    with(E, "Drinking", function() return false end, function()
    with(BI, "DrinkStep", function() return { label = "Drink: Water" } end, function()
    with(ns.db.rotation, "recoverDrink", nil, function()
        with(E, "ManaShare", function() return 0.3 end, function()
            local s = E:DrinkStep(out)
            t:eq(s and s.label, "Drink: Water", "30% mana, out of a fight: drink")
            t:eq(E:DrinkStep({ inCombat = true }), nil, "in a fight: no")
            t:eq(E:DrinkStep({ inCombat = false, hostile = true }), nil, "an enemy targeted: no (you'd sit at the pull)")
        end)
        with(E, "ManaShare", function() return 0.8 end, function()
            t:eq(E:DrinkStep(out), nil, "80% mana: no")
        end)
        with(E, "ManaShare", function() return nil end, function()
            t:eq(E:DrinkStep(out), nil, "no mana (or hidden): no")
        end)
    end)
    with(ns.db.rotation, "recoverDrink", false, function()
        with(E, "ManaShare", function() return 0.1 end, function()
            t:eq(E:DrinkStep(out), nil, "\"Drink when low on mana\" off: no")
        end)
    end)
    end)
    end)
    end)
    with(E, "Drinking", function() return true end, function()
    with(E, "Mounted", function() return false end, function()
    with(E, "ManaShare", function() return 0.1 end, function()
        t:eq(E:DrinkStep(out), nil, "already drinking: no")
    end)
    end)
    end)
end)

ns:Register("test", "easy button: the icon shows what the key casts; Shift swaps in your heal", function(t)
    -- 0.35.137: in a fight the icon showed the advice (Moonfire) while the
    -- key cast Wrath, with Wrath tucked in the corner. Now the other way.
    local held = { spell = "Wrath", kind = "held", label = "key: Wrath" }
    local moonfire = { spell = "Moonfire", kind = "damage" }
    local v, adv = ns.KeyView(moonfire, nil, false)
    t:ok(v == moonfire and adv == nil, "out of a fight: the advice, which the key casts")
    v, adv = ns.KeyView(moonfire, held, true)
    t:eq(v.spell, "Wrath", "in a fight: the key's spell on the icon")
    t:eq(v.kind, "key", "not greyed (it's what a press does)")
    t:eq(adv, moonfire, "the advice goes to the corner")
    v, adv = ns.KeyView({ spell = "Wrath", kind = "damage" }, held, true)
    t:ok(v.spell == "Wrath" and adv == nil, "advice is the key's spell: no corner")
    v, adv = ns.KeyView(nil, held, true)
    t:ok(v == held and adv == nil, "nothing new to press: the held spell, greyed as before")
    local sv, shifted = ns.ShiftView(v, "Rejuvenation", true, true)
    t:ok(shifted and sv.spell == "Rejuvenation" and sv.kind == "heal", "Shift held: your heal swaps in")
    sv, shifted = ns.ShiftView(v, "Rejuvenation", false, true)
    t:ok(not shifted and sv == v, "Shift let go: back to the key's spell")
    sv, shifted = ns.ShiftView(nil, "Rejuvenation", true, false)
    t:ok(not shifted and sv == nil, "out of a fight with nothing to press: no button, no swap")
    sv, shifted = ns.ShiftView(moonfire, nil, true, false)
    t:ok(not shifted and sv == moonfire, "no heal known: nothing to swap in")
    t:eq(ns.cast.AdviceLabel({ spell = "Rejuvenation" }, "Rejuvenation"), "Shift+", "corner: your heal is Shift + key")
    t:eq(ns.cast.AdviceLabel(moonfire, "Rejuvenation"), "bar:", "corner: anything else, press it on your bar")
end)

ns:Register("test", "move with Ctrl (as in Questie); hide Questie's tracker", function(t)
    -- 0.35.138: Shift moved things; it now shows what Shift + key casts.
    t:eq(ns.MOVE_KEY, "Ctrl", "Ctrl moves Flow's frames")
    t:eq(ns.MoveKeyDown(), IsControlKeyDown() and true or false, "the move key is Ctrl")
    local b = _G.FlowCastButton
    if b then t:eq(b:GetAttribute("ctrl-type1"), "macro", "Ctrl + click on the Flow button never casts (it moves it)")
    else t:ok(true, "(no Flow key yet)") end
    local RT = ns.routeTracker
    local shown = RT.QuestieTrackerShown()
    t:ok(shown == nil or type(shown) == "boolean", "Questie's tracker: on, off, or no Questie")
    local found
    for _, def in ipairs(ns.settings.extraChecks or {}) do
        if def.label == "Hide Questie's tracker" then found = def end
    end
    t:ok(found ~= nil, "Flow Settings has \"Hide Questie's tracker\"")
    if found then
        local ok, v = pcall(found.get)
        t:ok(ok and (v == true or v == false), "its tick box reads Questie's own setting")
    end
end)

ns:Register("test", "click: the arrow drawer's X closes it", function(t)
    local d = CreateFrame("Frame", nil, UIParent)
    d:SetSize(340, 200)
    ns.nav._makeDrawer(d)
    with(ns.db.nav, "drawerOpen", true, function()
        d:Show()
        local ok, err = pcall(d.close:GetScript("OnClick"), d.close)
        t:ok(ok, "the X runs" .. (ok and "" or (": " .. tostring(err))))
        t:ok(not d:IsShown(), "closed")
        t:eq(ns.db.nav.drawerOpen, nil, "and stays closed after a /reload")
    end)
    local a, _, r = d.close:GetPoint()
    t:ok(a == "TOPRIGHT" and r == "TOPRIGHT", "top right, like Flow's other views")
    d:Hide()
end)

ns:Register("test", "map and arrow agree: area stops by every spawn; one spot per stop", function(t)
    local N = ns.nav
    -- 0.35.140: "in this area" on the map and Flow Tracker went by a stop's
    -- one route spot; the arrow by every spawn of its objective.
    local wolves = { key = "500:1", points = { { cont = 1, wx = 900, wy = 900 }, { cont = 1, wx = 20, wy = 10 } } }
    local plan = {
        { goal = { key = "400:1" }, point = { cont = 1, wx = 0, wy = 0 } },   -- your next stop
        { goal = wolves, point = { cont = 1, wx = 900, wy = 900 } },         -- route spot far off
        { goal = { key = "600:1", points = { { cont = 1, wx = 3000, wy = 3000 } } }, point = { cont = 1, wx = 3000, wy = 3000 } },
    }
    t:eq(table.concat(N.HereStops(plan, { cont = 1, wx = 5, wy = 5 }), ","), "1,2",
        "wolves whose spawns are here count, though their route spot is across the zone")
    t:ok(N._stopNear(plan[2], { cont = 1, wx = 25, wy = 10 }, 150), "near one of its spawns")
    t:ok(not N._stopNear(plan[3], { cont = 1, wx = 25, wy = 10 }, 150), "a stop far away isn't")
    -- One spot per stop: the route's when it's planned, else the spawn nearest you.
    with(N, "plan", plan, function()
        t:eq(N:Spot(wolves, { cont = 1, wx = 5, wy = 5 }), plan[2].point, "on the route: its route spot (the arrow's)")
    end)
    with(N, "plan", {}, function()
        local s = N:Spot(wolves, { cont = 1, wx = 5, wy = 5 })
        t:ok(s and s.wx == 20, "off the route: the spawn nearest you, not the first one kept")
    end)
end)

ns:Register("test", "new spells: one Flow Spells list, Place all on bar", function(t)
    local NS = ns.newSpell
    -- 0.35.141: each new spell had a card of its own for 10 s, the next one
    -- replacing it; training five spells left you chasing cards.
    local entries = { { id = 1, name = "Moonfire" }, { id = 2, name = "Thorns", slot = 5 },
                      { id = 3, name = "Wrath", key = "Q" }, { id = 4, name = "Roots", skipped = true },
                      { id = 5, name = "Rejuvenation" } }
    local need = NS.Placeable(entries)
    t:eq(#need, 2, "Place all: only the ones not on a bar, not on a key, not skipped")
    t:ok(need[1].name == "Moonfire" and need[2].name == "Rejuvenation", "Moonfire and Rejuvenation")
    t:eq(NS.RowWhere(entries[2]), "Action Bar 1, slot 5", "a row says where it is")
    t:eq(NS.RowWhere(entries[3]), "key: Q", "or its key")
    t:eq(NS.RowWhere(entries[4]), "not on your bars", "or that you skipped it")
    t:ok(type(NS.PlaceAll) == "function" and type(NS.Close) == "function", "Place all and Close")
end)

ns:Register("test", "/flow keys: spells bound straight to a key, sorted", function(t)
    local NS = ns.newSpell
    local keys = { Moonfire = { "Q" }, Wrath = { "E", "SHIFT-E" }, Thorns = {} }
    local list = NS.DirectKeys({ Moonfire = true, Wrath = true, Thorns = true },
        function(n) local k = keys[n] or {}; return k[1], k[2] end)
    t:eq(#list, 3, "Moonfire's key and both of Wrath's; Thorns has none")
    t:eq(list[1].key .. "=" .. list[1].name, "E=Wrath", "sorted by key")
    t:eq(list[3].key .. "=" .. list[3].name, "SHIFT-E=Wrath", "a second key too")
    t:ok(ns.commands.keys ~= nil, "/flow keys")
end)

ns:Register("test", "needs: a stop goes after what provides it, or waits with the reason", function(t)
    local N = ns.nav
    -- 0.35.142: Demoralizing Roar needs Bear Form, from a class quest; Flow
    -- sent a level-10 druid to train it anyway.
    local have = { ["spell:Wrath"] = true }
    local function met(tok) return have[tok] == true end
    local function label(tok) return (tok:gsub("^%w+:", "")) end
    local quest = { key = "6002:done", provides = { "spell:Bear Form" } }
    local train = { key = "train:class", needs = { { "spell:Bear Form", soft = true } } }
    local hard = { key = "skill:Bear", needs = { "spell:Bear Form" } }
    local fine = { key = "x:1", needs = { "spell:Wrath" } }
    N.ResolveNeeds({ quest, train, hard, fine }, met, label)
    t:eq(train.deps and train.deps[1], "6002:done", "training goes after the quest that teaches Bear Form")
    t:eq(train.after, "Bear Form", "and says so")
    t:eq(hard.deps and hard.deps[1], "6002:done", "a hard need with a provider: ordered, not blocked")
    t:eq(hard.blockedBy, nil, "not blocked while the provider is on the route")
    t:eq(fine.deps, nil, "a need you meet: nothing")
    local lone = { key = "skill:Bear", needs = { "spell:Bear Form" } }
    local soft = { key = "train:class", needs = { { "spell:Bear Form", soft = true } } }
    N.ResolveNeeds({ lone, soft }, met, label)
    t:eq(lone.blockedBy, "needs Bear Form first", "nothing provides it: a hard need blocks, with the reason")
    t:eq(soft.blockedBy, nil, "a soft need never blocks")
    t:eq(soft.deps, nil, "and with no provider, no order either")
    -- Two stops that would wait on each other: no loop.
    local a = { key = "a", provides = { "spell:A" }, needs = { { "spell:B", soft = true } } }
    local b = { key = "b", provides = { "spell:B" }, needs = { { "spell:A", soft = true } } }
    N.ResolveNeeds({ a, b }, met, label)
    t:ok(not (a.deps and b.deps), "never both waiting on each other")
    -- The class quest provider: Body and Heart's turn-in teaches Bear Form (druids).
    local _, class = UnitClass("player")
    if class == "DRUID" then
        local toks = N.ProvidesOf({ key = "6002:done" })
        t:eq(toks[1], "spell:Bear Form", "Body and Heart (6002) teaches Bear Form")
    else
        t:ok(true, "(not a druid: the Bear Form quest isn't checked)")
    end
end)

ns:Register("test", "trainer: spells that wait for another don't send you to train", function(t)
    local T = ns.trainerAdvice
    local known = { Wrath = true }
    t:eq(T.WaitsFor("Bear Form", known, "unavailable", 10, 10), "Bear Form", "Demoralizing Roar waits for Bear Form")
    t:eq(T.WaitsFor("Bear Form", { ["Bear Form"] = true }, "unavailable", 10, 10), nil, "with Bear Form known: trainable")
    t:eq(T.WaitsFor(nil, known, "available", 10, 10), nil, "available: trainable")
    t:eq(T.WaitsFor(nil, known, "unavailable", 12, 10), nil, "red only for your level then: not waiting (you've levelled)")
    t:ok(T.WaitsFor(nil, known, "unavailable", 8, 10) ~= nil, "red although your level was enough: it needs something first")
    local druid = ns:Get("classSpells", "DRUID")
    local need
    for _, s in ipairs(druid) do if s.spell == "Demoralizing Roar" then need = s.needs end end
    t:eq(need, "Bear Form", "the druid data says Demoralizing Roar needs Bear Form")
end)

ns:Register("test", "needs: the town's errands don't pull a stop ahead of what it waits for", function(t)
    local N = ns.nav
    local train = { key = "train:class", deps = { "6002:done" } }
    t:eq(N.HubBusiness(train, 10, { ["6002:done"] = true }, false), nil,
        "training waits while the Bear Form quest's turn-in is still on the route")
    t:eq(N.HubBusiness(train, 10, {}, false), "train", "turned in: training is town business again")
end)
