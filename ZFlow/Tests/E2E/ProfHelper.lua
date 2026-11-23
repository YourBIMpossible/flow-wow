local _, ns = ...
-- The profession helper end to end (P-PROF, lead section 238: N22 the skill
-- goal and the recipes that give a point, N23 recipe colours seen in the
-- window), on the whole add-on loaded on a fake client. The player opens a
-- profession window; a panel beside it says the skill, the goal, what the
-- bags can make for points and the cheapest recipes that give one. The
-- player types a goal into the panel. It reads only; it never crafts.
-- Offline: the reads are the fake client ones, not the game. Not tested in game.
local tests = {}

local TAILORING = 197
local BOLT, BELT, CAP = 11, 12, 13
local CLOTH, THREAD = 2589, 2996

local function setWindow(c)
    c.setRecipes({ profession = TAILORING, skill = 40, max = 75, recipes = {
        { id = BOLT, name = "Linen Bolt", learned = true, difficulty = "optimal" },
        { id = BELT, name = "Linen Belt", learned = true, difficulty = "medium" },
        { id = CAP, name = "Linen Cap", learned = true, difficulty = "trivial" },
    } })
end

local function setSchematics(c)
    c.setRecipeSchematic(BOLT, { makes = 4000, yield = 1, mats = { [CLOTH] = 2 } })
    c.setRecipeSchematic(BELT, { makes = 4001, yield = 1, mats = { [THREAD] = 1 } })
    c.setRecipeSchematic(CAP, { makes = 4002, yield = 1, mats = { [CLOTH] = 1 } })
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {
        learned = { prices = { vendor = { [CLOTH] = { value = 10, basis = "observed", source = "merchant" } } } },
    })
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setBags({ { free = 4, total = 16, family = 0 } })
    if opts.recipes ~= false then setWindow(c) end
    if opts.schematic ~= false then setSchematics(c) end
    c.setItemCount(CLOTH, 6)
    c.setItemCount(THREAD, 1)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.open ~= false then
        c.fire("TRADE_SKILL_SHOW")
        c.fire("TRADE_SKILL_LIST_UPDATE")
    end
    return c, addon
end

local function panelOf(c)
    for _, p in ipairs(c.rowPanels or {}) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "ProfHelper" then return p end
    end
    return nil
end

local function rowOf(p, key)
    for _, r in ipairs(p and p.rows or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function infos(p)
    local out = {}
    for _, r in ipairs(p and p.rows or {}) do
        if r.kind == "info" then out[#out + 1] = r.text end
    end
    return out
end

local function has(list, text)
    for _, v in ipairs(list) do
        if v == text then return true end
    end
    return false
end

local function H() return ns.ProfHelper or {} end

tests["prof helper: beside the window, the skill, the bags and the recipes that give a point"] = function(t)
    local c = start()
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    t.eq(p.shown(), true)
    local lines = infos(p)
    t.ok(has(lines, string.format(H().SKILL or "", 40, 75)), "the skill line")
    t.ok(has(lines, string.format(H().BAGS or "", 1, 3)), "the bags line, one sure point with no colour span seen")
    t.ok(has(lines, string.format(H().ROW or "", "Linen Bolt", H().SURE or "", ns.Prices.Coin(20))), "the bolt row with its cost")
    t.ok(has(lines, string.format(H().ROW_NOCOST or "", "Linen Belt", H().MAYBE or "")), "the belt row, cost unknown")
    for _, line in ipairs(lines) do
        t.ok(not line:find("Linen Cap", 1, true), "a grey recipe is not listed")
    end
    local goal = rowOf(p, "goal")
    t.eq(goal and goal.kind, "number", "a goal box")
    t.eq(#c.crafts, 0, "the helper never crafts")
end

tests["prof helper: the goal the player types is kept for the profession"] = function(t)
    local c = start()
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    t.eq(p.press("goal", 60), true)
    t.ok(has(infos(p), string.format(H().TO_GOAL or "", 20, 60)), "points to the goal")
    local char = c.saved(ns.id.charDB)
    local goals = type(char.state) == "table" and char.state.profGoals or {}
    t.eq(goals[TAILORING], 60, "kept on the character")
    t.eq(rowOf(p, "goal") and rowOf(p, "goal").value, 60)
    p.press("goal", 30)
    t.ok(has(infos(p), string.format(H().AT_GOAL or "", 30)), "a goal already reached")
    p.press("goal", 80)
    t.ok(has(infos(p), string.format(H().OVER_CAP or "", 80, 75)), "a goal past the cap says train first")
    p.press("goal", 0)
    goals = type(char.state) == "table" and char.state.profGoals or {}
    t.eq(goals[TAILORING], nil, "zero clears the goal")
    t.eq(#c.crafts, 0)
end

tests["prof helper: a colour span seen before makes more of the bags sure"] = function(t)
    local c = start({ char = { learned = { recipeColors = { [BOLT] = { optimal = { lo = 30, hi = 45 } } } } } })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    t.ok(has(infos(p), string.format(H().BAGS or "", 3, 1)), "three bolts sure inside the span, the belt may")
end

tests["prof helper: the colours seen in the window are kept on the character"] = function(t)
    local c = start()
    local char = c.saved(ns.id.charDB)
    local seen = type(char.learned) == "table" and char.learned.recipeColors or {}
    t.eq(seen[BOLT], { optimal = { lo = 40, hi = 40 } })
    t.eq(seen[BELT], { medium = { lo = 40, hi = 40 } })
    t.eq(seen[CAP], { trivial = { lo = 40, hi = 40 } })
end

-- Section 236: data arriving late. The window opens before the recipes can
-- be read; the panel says it is reading, and fills when the list answers.
tests["prof helper: recipes that arrive late fill the panel on the list update"] = function(t)
    local c = start({ recipes = false })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    t.ok(has(infos(p), H().READING or "?"), "reading at first")
    setWindow(c)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.ok(has(infos(p), string.format(H().SKILL or "", 40, 75)), "filled on the update")
end

-- Section 236: a read that fails then recovers. The recipe mats can not be
-- read at first: the bags line says so, never that the bags make nothing.
tests["prof helper: mats that can not be read say so, then recover"] = function(t)
    local c = start({ schematic = false })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    local lines = infos(p)
    t.ok(has(lines, H().BAGS_UNREAD or "?"), "mats not read yet")
    t.ok(not has(lines, H().BAGS_NONE or "?"), "not said to make nothing")
    setSchematics(c)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.ok(has(infos(p), string.format(H().BAGS or "", 1, 3)), "recovered on the update")
end

-- Section 236: a reload in the middle. The goal and the colours seen are
-- read back from the saved tables.
tests["prof helper: a reload keeps the goal and the colours seen"] = function(t)
    local c = start()
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    p.press("goal", 60)
    local c2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    local p2 = panelOf(c2)
    if not p2 then t.ok(false, "no helper panel after the reload") return end
    t.eq(rowOf(p2, "goal") and rowOf(p2, "goal").value, 60)
    t.ok(has(infos(p2), string.format(H().TO_GOAL or "", 20, 60)), "the goal read back")
    local char2 = c2.saved(ns.id.charDB)
    local seen = type(char2.learned) == "table" and char2.learned.recipeColors or {}
    t.eq(seen[BOLT], { optimal = { lo = 40, hi = 40 } })
end

tests["prof helper: closing the window or the setting off hides it"] = function(t)
    local c, addon = start()
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    c.fire("TRADE_SKILL_CLOSE")
    t.eq(p.shown(), false, "hidden on close")
    c.fire("TRADE_SKILL_SHOW"); c.fire("TRADE_SKILL_LIST_UPDATE")
    t.eq(p.shown(), true)
    addon.settings:set("prof.helper", false)
    c.advance(1, 5)
    t.eq(p.shown(), false, "hidden when the setting is off")
    t.eq(#c.crafts, 0)
end

return tests
