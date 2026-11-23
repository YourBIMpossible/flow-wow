local _, ns = ...
-- The rest of P-PROF end to end (lead section 274 item 2), on the whole
-- add-on loaded on a fake client, through the real entry point:
--   A6   the first recipe on the panel planned with the craft hint: how
--        many to make for the goal and how many the bags make now. Lines
--        only: the hint button is never drawn.
--   N23  what the trainers this character saw teach at the skill reached,
--        and the skill of the next one.
--   N24  a tool the classic window says a listed recipe needs and the bags
--        do not hold: a line on the panel and one advisor prompt, gone
--        when a later read says it is carried.
-- It reads only; it never crafts, trains or buys. Made-up data; not tested
-- in game.
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
    c.setRecipeSchematic(BOLT, { makes = 4000, yield = 1, mats = { [CLOTH] = 2 } })
    c.setRecipeSchematic(BELT, { makes = 4001, yield = 1, mats = { [THREAD] = 1 } })
    c.setRecipeSchematic(CAP, { makes = 4002, yield = 1, mats = { [CLOTH] = 1 } })
end

local function setClassic(c)
    c.setTradeSkillRows({ name = "Tailoring", skill = 40, max = 75, rows = {
        { index = 2, name = "Linen Bolt", difficulty = "optimal" },
        { index = 3, name = "Linen Belt", difficulty = "medium" },
        { index = 4, name = "Linen Cap", difficulty = "trivial" },
    } })
    c.setTradeSkillSchematic(2, { name = "Linen Bolt", difficulty = "optimal", makes = 4000, yield = 1,
        mats = { [CLOTH] = 2 } })
    c.setTradeSkillSchematic(3, { name = "Linen Belt", difficulty = "medium", makes = 4001, yield = 1,
        mats = { [THREAD] = 1 } })
    c.setTradeSkillSchematic(4, { name = "Linen Cap", difficulty = "trivial", makes = 4002, yield = 1,
        mats = { [CLOTH] = 1 } })
end

-- opts.classic: the classic window, not the modern one; opts.char: the
-- character saved data; opts.tools: { [row index] = tools } for the
-- classic rows.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    -- These cases are the plain panel: the kit window is refused, so the
    -- panel behind it draws (lead section 297 item 5, the fallback).
    if type(c.setKitFails) == "function" then c.setKitFails(math.huge) end
    c.setSaved(ns.id.accountDB, {
        learned = { prices = { vendor = { [CLOTH] = { value = 10, basis = "observed", source = "merchant" } } } },
    })
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setBags({ { free = 4, total = 16, family = 0 } })
    if opts.classic then setClassic(c) else setWindow(c) end
    for index, list in pairs(opts.tools or {}) do
        if type(c.setTradeSkillTools) == "function" then c.setTradeSkillTools(index, list) end
    end
    c.setItemCount(CLOTH, 6)
    c.setItemCount(THREAD, 1)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    c.fire("TRADE_SKILL_SHOW")
    c.fire("TRADE_SKILL_LIST_UPDATE")
    return c, addon
end

local function panelOf(c)
    for _, p in ipairs(c.rowPanels or {}) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "ProfHelper" then return p end
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

local function prompts(addon, prefix)
    local out = {}
    local advisor = addon.use("advisor")
    if type(advisor) ~= "table" or type(advisor.List) ~= "function" then return out end
    for _, p in ipairs(advisor.List()) do
        if p.id:sub(1, #prefix) == prefix then out[#out + 1] = p end
    end
    return out
end

-- A6: the craft hint for the first recipe.

tests["prof helper A6: the first recipe planned, one to make and what the bags make now"] = function(t)
    local c = start()
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    local lines = infos(p)
    t.ok(has(lines, "Make 1 x Linen Bolt"), "the plan title for the first recipe")
    t.ok(has(lines, "You can make 1 now"), "what the bags make now")
    t.eq(#c.crafts, 0, "the helper never crafts")
end

tests["prof helper A6: with a goal, the plan is the points still to go"] = function(t)
    local c = start()
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    t.eq(p.press("goal", 60), true)
    local lines = infos(p)
    t.ok(has(lines, "Make 20 x Linen Bolt"), "twenty to the goal")
    t.ok(has(lines, "You can make 3 now"), "six cloth make three")
    t.ok(not has(lines, "Make 1 x Linen Bolt"), "the old plan is gone")
end

tests["prof helper A6: the panel holds lines and the goal box only, never a button"] = function(t)
    local c = start({ classic = true, tools = { [2] = { { name = "Sewing Kit", has = false } } } })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    t.ok(#p.rows > 0, "rows drawn")
    for _, r in ipairs(p.rows) do
        t.ok(r.kind == "info" or r.kind == "number", "row kind " .. tostring(r.kind))
    end
    t.eq(#c.crafts, 0)
end

tests["prof helper A6: mats not read: no plan is said"] = function(t)
    local c = start({ classic = true })
    c.setTradeSkillSchematic(2, { name = "Linen Bolt", difficulty = "optimal", makes = 4000, yield = 1,
        mats = { [CLOTH] = 2 }, partial = true })
    c.fire("TRADE_SKILL_LIST_UPDATE")
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    for _, line in ipairs(infos(p)) do
        t.ok(not line:find("Make %d+ x Linen Bolt"), "no plan for a recipe whose mats are not read: " .. line)
    end
end

-- N23: the trainers this character saw.

local function seen(lists)
    local T = ns.TrainerList or { Key = function(a, b) return tostring(a) .. "|" .. tostring(b) end }
    local out = {}
    for _, e in ipairs(lists) do
        out[T.Key(e.npc, e.profession)] = { npc = e.npc, profession = e.profession, faction = "Alliance",
            seen = 1, shown = { available = true, unavailable = true, known = true }, complete = true,
            rows = e.rows }
    end
    return { learned = { trainerLists = out } }
end

local BRENDA = { npc = "Brenda", profession = "Tailoring", rows = {
    { name = "Linen Shirt", state = "available", skill = 35 },
    { name = "Red Linen Robe", state = "unavailable", skill = 40 },
    { name = "Linen Bag", state = "unavailable", skill = 55 },
    { name = "Linen Bolt", state = "known", skill = 1 },
    { name = "Linen Cloak", state = "available" },
} }
local OSWALD = { npc = "Oswald", profession = "Tailoring", rows = {
    { name = "Brown Linen Pants", state = "available", skill = 30 },
    { name = "Woolen Cape", state = "unavailable", skill = 70 },
} }
local SMITH = { npc = "Grun", profession = "Blacksmithing", rows = {
    { name = "Copper Bracers", state = "available", skill = 1 },
} }

tests["prof helper N23: what the trainers seen teach at this skill, and the next one"] = function(t)
    local c = start({ classic = true, char = seen({ BRENDA, OSWALD, SMITH }) })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    local lines = infos(p)
    t.ok(has(lines, string.format(H().TRAINER_MEETS or "", 2, "Brenda")), "two at Brenda (known and no skill left out)")
    t.ok(has(lines, string.format(H().TRAINER_MEETS or "", 1, "Oswald")), "one at Oswald")
    t.ok(has(lines, string.format(H().TRAINER_NEXT or "", 55)), "the next skill a trainer recipe needs")
    for _, line in ipairs(lines) do
        t.ok(not line:find("Grun", 1, true), "another profession is not counted")
    end
end

tests["prof helper N23: a trainer whose recipes are all above the skill says only the next one"] = function(t)
    local c = start({ classic = true, char = seen({ { npc = "Brenda", profession = "Tailoring", rows = {
        { name = "Linen Bag", state = "unavailable", skill = 55 } } } }) })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    local lines = infos(p)
    t.ok(has(lines, string.format(H().TRAINER_NEXT or "", 55)), "the next one")
    t.ok(not has(lines, string.format(H().TRAINER_MEETS or "", 0, "Brenda")), "no zero line")
end

tests["prof helper N23: no trainer seen, or a modern window with a profession number: nothing said"] = function(t)
    local c = start({ classic = true })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    local prefixes = { H().TRAINER_MEETS, H().TRAINER_NEXT }
    for _, line in ipairs(infos(p)) do
        for _, f in ipairs(prefixes) do
            if type(f) == "string" then t.ok(line:sub(1, 10) ~= f:sub(1, 10), "nothing from trainers: " .. line) end
        end
    end
    local m = start({ char = seen({ BRENDA }) })
    local q = panelOf(m)
    if not q then t.ok(false, "no helper panel") return end
    t.ok(not has(infos(q), string.format(H().TRAINER_NEXT or "", 55)),
        "the modern window names the profession by number: no trainer list matches it")
end

-- N24: a tool the recipe needs.

tests["prof helper N24: a tool not carried: a line and one advisor prompt"] = function(t)
    local c, addon = start({ classic = true, tools = { [2] = { { name = "Sewing Kit", has = false } } } })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    t.ok(has(infos(p), string.format(H().TOOL_MISSING or "", "Sewing Kit", "Linen Bolt")), "the line")
    local got = prompts(addon, "aps.prof.tool.")
    t.eq(#got, 1, "one prompt")
    t.eq(got[1] and got[1].id, "aps.prof.tool.Tailoring")
    t.eq(got[1] and got[1].text, string.format(H().TOOL_PROMPT or "", "Sewing Kit", "Linen Bolt"))
    c.fire("TRADE_SKILL_CLOSE")
    t.eq(#prompts(addon, "aps.prof.tool."), 1, "the prompt stays after the window closes")
end

tests["prof helper N24: the tool carried at the next read: the line and the prompt go"] = function(t)
    local c, addon = start({ classic = true, tools = { [2] = { { name = "Sewing Kit", has = false } } } })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    c.setTradeSkillTools(2, { { name = "Sewing Kit", has = true } })
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.ok(not has(infos(p), string.format(H().TOOL_MISSING or "", "Sewing Kit", "Linen Bolt")), "no line")
    t.eq(#prompts(addon, "aps.prof.tool."), 0, "no prompt")
end

tests["prof helper N24: a tool read that does not answer says nothing and keeps any prompt"] = function(t)
    local c, addon = start({ classic = true, tools = { [2] = { { name = "Sewing Kit", has = false } } } })
    if not panelOf(c) then t.ok(false, "no helper panel") return end
    t.eq(#prompts(addon, "aps.prof.tool."), 1)
    c.setTradeSkillTools(2, nil)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.eq(#prompts(addon, "aps.prof.tool."), 1, "unknown is not carried: the prompt stays")
    for _, line in ipairs(infos(panelOf(c))) do
        t.ok(not line:find("Sewing Kit", 1, true), "no line from an unread tool")
    end
end

tests["prof helper N24: a modern window has no tool read: nothing said"] = function(t)
    local c, addon = start({ tools = { [2] = { { name = "Sewing Kit", has = false } } } })
    local p = panelOf(c)
    if not p then t.ok(false, "no helper panel") return end
    for _, line in ipairs(infos(p)) do
        t.ok(not line:find("Sewing Kit", 1, true), "no tool line")
    end
    t.eq(#prompts(addon, "aps.prof.tool."), 0, "no prompt")
end

tests["prof helper N24: the helper turned off: no tool prompt"] = function(t)
    local c, addon = start({ classic = true })
    c.setTradeSkillTools(2, { { name = "Sewing Kit", has = false } })
    addon.settings:set("prof.helper", false)
    c.fire("TRADE_SKILL_CLOSE")
    c.fire("TRADE_SKILL_SHOW"); c.fire("TRADE_SKILL_LIST_UPDATE")
    t.eq(#prompts(addon, "aps.prof.tool."), 0)
    t.eq(#c.crafts, 0)
end

return tests
