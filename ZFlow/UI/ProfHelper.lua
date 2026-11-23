local _, ns = ...

-- The profession helper (P-PROF, lead section 238: N22 the skill goal and
-- the recipes that give a point, N23 the recipe colours seen in the window):
-- a small panel beside the profession window. It says the skill and its
-- cap, how far the goal the player typed is, how many points what the bags
-- hold can make, and the cheapest recipes that give a point now. Each time
-- the window answers, the colour of each recipe at that skill is kept on
-- the character (learned.recipeColors), so later readings know how long a
-- recipe stays orange. It reads only: it never crafts, buys or moves an
-- item. Items/SkillUps.lua does the counting.
-- Lead section 245 item 2: a window the modern read does not answer (a
-- classic window) is read from the classic rows instead (c.tradeSkillRows,
-- c.tradeSkillSchematic by row index): the recipe and its colour are keyed
-- by the recipe name, the goal by the profession name, and a schematic the
-- client gave only in part counts as mats unknown. The setting turned on
-- with the window already open shows the panel at the next look.
-- Lead section 249 item 4 (PF-1): one key rule for the colour history in
-- both reads. A recipe is kept by its name, so the same recipe seen in a
-- classic window and a modern one keeps one history; a modern recipe the
-- client gave no name for is kept by its id. A history kept by the recipe
-- id before (zflow-prof) is folded into the name when the window shows
-- that recipe with both, and the id entry is removed.
-- Lead section 274 item 2, the rest of P-PROF (look only, no acting call):
--   A6   the first recipe listed is planned with the craft hint
--        (Items/CraftHint.lua): how many to make for the goal (one with no
--        goal) and how many the bags make now. Lines only: the hint button
--        is never drawn, so the panel never crafts.
--   N23  the trainer lists this character saw (learned.trainerLists, kept
--        by Spells/TrainerModule.lua) for this profession: how many recipes
--        not yet known each trainer teaches at the skill reached, and the
--        lowest skill a listed recipe still needs. Matched by profession
--        name, so a modern window (a profession number) matches none.
--   N24  a classic window row whose tool (c.tradeSkillTools) the bags do not
--        hold: a line, and one advisor prompt per profession. The prompt
--        goes only when every tool read answered and none is missing; a read
--        that does not answer keeps it. Shown only with the helper on.
-- Needs game test: the colour and skill up fields of the recipe read
-- (Core/Client.lua c.recipes; Diag capture fields recipeDifficulty and
-- recipeSkillUps), the trainer skill requirement, the tool read, and where
-- the panel sits beside the window.

local ProfHelper = ns.ProfHelper or {}
ns.ProfHelper = ProfHelper

-- Folds a colour history kept by the recipe id into the row key, for each
-- row { key =, id = } whose key is not its id: each colour span is widened
-- into seen[key] and seen[id] is removed. Returns seen.
function ProfHelper.Fold(seen, rows)
    if type(seen) ~= "table" or type(rows) ~= "table" then return seen end
    local U = ns.SkillUps
    for _, r in ipairs(rows) do
        local id = type(r) == "table" and r.id or nil
        if id ~= nil and r.key ~= nil and r.key ~= id and type(seen[id]) == "table" then
            for colour, span in pairs(seen[id]) do
                if type(span) == "table" and type(span.lo) == "number" and type(span.hi) == "number" then
                    U.Observe(seen, { { key = r.key, difficulty = colour } }, span.lo)
                    U.Observe(seen, { { key = r.key, difficulty = colour } }, span.hi)
                end
            end
            seen[id] = nil
        end
    end
    return seen
end

ProfHelper.NAME = "profHelper"
ProfHelper.SETTING = "prof.helper"
ProfHelper.WIDTH = 260
ProfHelper.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 700, -330 }
-- The kit window's size and place, at the right of the craft bar's. First
-- guess: not yet seen in the game.
ProfHelper.KIT_WIDTH, ProfHelper.KIT_HEIGHT = 340, 420
ProfHelper.KIT_POINT = { "TOPLEFT", "TOPLEFT", 1030, -120 }
-- Seconds between looks at the setting while the panel is up.
ProfHelper.EVERY = 1
-- How many recipes the panel lists.
ProfHelper.TOP = 5
ProfHelper.GOAL_MAX = 999
ProfHelper.GOALS_PATH = "state.profGoals"
ProfHelper.COLORS_PATH = "learned.recipeColors"
ProfHelper.PRICES_PATH = "learned.prices"

ProfHelper.READING = "Reading this profession window."
ProfHelper.SKILL = "Skill %d of %d."
ProfHelper.TO_GOAL = "%d points to your goal of %d."
ProfHelper.AT_GOAL = "Goal of %d reached."
ProfHelper.OVER_CAP = "Your goal of %d is past your cap of %d: train first."
ProfHelper.BAGS = "From your bags: %d sure points, %d more crafts that may give one."
ProfHelper.BAGS_NONE = "Your bags make no skill-up recipe now."
ProfHelper.BAGS_UNREAD = "Reading what each recipe takes."
ProfHelper.NONE = "No recipe here gives a point now."
ProfHelper.ROW = "%s: %s, %s a craft."
ProfHelper.ROW_NOCOST = "%s: %s, cost unknown."
ProfHelper.SURE = "sure point"
ProfHelper.MAYBE = "may give a point"
ProfHelper.UNKNOWN = "colour not read"
ProfHelper.TRAINER_MEETS = "Your skill meets %d recipes %s teaches."
ProfHelper.TRAINER_NEXT = "Next trainer recipe at skill %d."
ProfHelper.TRAINERS_PATH = "learned.trainerLists"
ProfHelper.TOOL_MISSING = "Missing tool: %s, for %s."
ProfHelper.TOOL_PROMPT = "Carry your %s for %s."
ProfHelper.TOOL_ID = "aps.prof.tool."
ProfHelper.TOOL_PRIORITY = 2

-- N23: what the trainer lists seen teach for this profession at this skill.
-- lists: the saved trainer lists; profession: the window profession name.
-- -> { { npc, count } } sorted by npc (count above zero only), and the
--    lowest skill above the current one a listed recipe needs, or nil.
-- A recipe already known, or with no skill read, is not counted.
function ProfHelper.Trainers(lists, profession, skill)
    local meets, nextSkill = {}, nil
    if type(lists) ~= "table" or type(profession) ~= "string" or type(skill) ~= "number" then
        return meets, nil
    end
    local by = {}
    for _, e in pairs(lists) do
        if type(e) == "table" and e.profession == profession and type(e.npc) == "string"
            and type(e.rows) == "table" then
            for _, r in ipairs(e.rows) do
                local need = nil
                if type(r) == "table" and r.state ~= "known" then need = r.skill end
                if type(need) == "number" then
                    if need <= skill then
                        by[e.npc] = (by[e.npc] or 0) + 1
                    elseif nextSkill == nil or need < nextSkill then
                        nextSkill = need
                    end
                end
            end
        end
    end
    for npc, n in pairs(by) do meets[#meets + 1] = { npc = npc, count = n } end
    table.sort(meets, function(a, b) return a.npc < b.npc end)
    return meets, nextSkill
end

local WORD = { sure = "SURE", maybe = "MAYBE", unknown = "UNKNOWN" }

-- The helper on the shared kit (lead sections 287 and 291): what it shows as
-- a kit window spec (UI/Kit.lua, K.Window). Pure: no client, no kernel.
ProfHelper.TITLE = "Skill-up helper"
ProfHelper.HEAD = "%s: skill %d of %d"
ProfHelper.HEAD_NONAME = "Skill %d of %d"
-- How far one press of a goal button moves the goal.
ProfHelper.GOAL_STEP = 5
ProfHelper.GOAL = "Skill goal: %d."
ProfHelper.GOAL_UP = "Goal +"
ProfHelper.GOAL_DOWN = "Goal -"
ProfHelper.NO_GOAL = "No skill goal set. Goal + sets one."
ProfHelper.RECIPES = "Recipes that give a point"
ProfHelper.NOTES = "Notes"
ProfHelper.READING_HOW = "Wait a moment, or close the profession window and open it again."
ProfHelper.BAGS_HOW = "Buy or gather what a recipe below takes."
ProfHelper.UNREAD_HOW = "Wait a moment: the game sends what each recipe takes after the window opens."
ProfHelper.NONE_HOW = "Learn a new recipe at your trainer: none you know gives a point at this skill."
-- The game's own recipe colours, by the difficulty the recipe read gives.
-- Carried over from the old add-on (orange, yellow, green) and grey for a
-- recipe that gives no point; not read from this client.
ProfHelper.COLOURS = {
    optimal = { hex = "ff8040", r = 1, g = 0.5, b = 0.25 },
    medium = { hex = "ffff00", r = 1, g = 1, b = 0 },
    easy = { hex = "40c040", r = 0.25, g = 0.75, b = 0.25 },
    trivial = { hex = "808080", r = 0.5, g = 0.5, b = 0.5 },
}

-- The goal as one line: the goal, then how far it is.
local function goalLabel(m)
    if type(m.goal) ~= "number" then return ProfHelper.NO_GOAL end
    local label = ProfHelper.GOAL:format(m.goal)
    local state = m.state
    if type(state) ~= "table" then return label end
    if state.overCap then return label .. " " .. ProfHelper.OVER_CAP:format(m.goal, m.max) end
    if type(state.need) == "number" and state.need > 0 then
        return label .. " " .. ProfHelper.TO_GOAL:format(state.need, m.goal)
    end
    return label .. " " .. ProfHelper.AT_GOAL:format(m.goal)
end

-- ProfHelper.View(model[, act]) -> a kit window spec
--   model  { reading = true }, or
--          { profession, skill, max, goal, state, bags, recipes, notes }:
--          profession  the window's name for it (a number names none)
--          goal        the goal kept, or nil
--          state       what SkillUps.Goal answered, or nil
--          bags        { sure, maybe }, or nil while no recipe's mats are read
--          recipes     { { name, chance, difficulty, cost, icon } }, best first
--          notes       lines of text, or nil
--   act    act("goal", value) when a goal button is pressed; 0 clears it.
-- Each part the tests and the module look up has a key.
function ProfHelper.View(model, act)
    local view = { id = "ProfHelper", title = ProfHelper.TITLE, children = {},
        width = ProfHelper.KIT_WIDTH, height = ProfHelper.KIT_HEIGHT, point = ProfHelper.KIT_POINT }
    local kids = view.children
    if type(model) ~= "table" or model.reading == true then
        kids[1] = { kind = "header", title = ProfHelper.TITLE }
        kids[2] = { kind = "empty", key = "reading", text = ProfHelper.READING, how = ProfHelper.READING_HOW }
        return view
    end

    if type(model.profession) == "string" and model.profession ~= "" then
        kids[1] = { kind = "header", title = ProfHelper.HEAD:format(model.profession, model.skill, model.max) }
    else
        kids[1] = { kind = "header", title = ProfHelper.HEAD_NONAME:format(model.skill, model.max) }
    end

    local function set(value)
        if type(act) == "function" then act("goal", value) end
    end
    local hasGoal = type(model.goal) == "number"
    -- The first goal starts from the skill.
    local from = model.skill
    if hasGoal then from = model.goal end
    local up = math.min(ProfHelper.GOAL_MAX, from + ProfHelper.GOAL_STEP)
    local down = math.max(0, from - ProfHelper.GOAL_STEP)
    kids[#kids + 1] = { kind = "row", key = "goal", label = goalLabel(model) }
    kids[#kids + 1] = { kind = "button", key = "goalDown", text = ProfHelper.GOAL_DOWN, enabled = hasGoal,
        tooltip = "Lower your skill goal by " .. ProfHelper.GOAL_STEP .. ". Below that, the goal is cleared.",
        onClick = function() if hasGoal then set(down) end end }
    kids[#kids + 1] = { kind = "button", key = "goalUp", text = ProfHelper.GOAL_UP, enabled = from < ProfHelper.GOAL_MAX,
        tooltip = "Raise your skill goal by " .. ProfHelper.GOAL_STEP .. ".",
        onClick = function() if from < ProfHelper.GOAL_MAX then set(up) end end }

    local recipes = model.recipes
    if type(recipes) ~= "table" then recipes = {} end
    if #recipes > 0 then
        local bags = model.bags
        if type(bags) ~= "table" then
            kids[#kids + 1] = { kind = "empty", key = "bags", text = ProfHelper.BAGS_UNREAD, how = ProfHelper.UNREAD_HOW }
        elseif bags.sure + bags.maybe == 0 then
            kids[#kids + 1] = { kind = "empty", key = "bags", text = ProfHelper.BAGS_NONE, how = ProfHelper.BAGS_HOW }
        else
            kids[#kids + 1] = { kind = "row", key = "bags", label = ProfHelper.BAGS:format(bags.sure, bags.maybe) }
        end
    end

    kids[#kids + 1] = { kind = "section", text = ProfHelper.RECIPES }
    if #recipes == 0 then
        kids[#kids + 1] = { kind = "empty", key = "recipes", text = ProfHelper.NONE, how = ProfHelper.NONE_HOW }
    end
    for _, r in ipairs(recipes) do
        local line = { kind = "itemLine", name = r.name .. " (" .. ProfHelper[WORD[r.chance] or "UNKNOWN"] .. ")" }
        -- The kit takes an icon as text only; a numbered icon is left out
        -- (kit ask).
        if type(r.icon) == "string" and r.icon ~= "" then line.icon = r.icon end
        -- The kit takes whole copper only; a cost not known is no money.
        if type(r.cost) == "number" and r.cost >= 0 then line.money = math.floor(r.cost + 0.5) end
        -- Kit ask: a line colour that is not an item quality (the skill colour).
        if type(r.difficulty) == "string" then line.color = ProfHelper.COLOURS[r.difficulty] end
        kids[#kids + 1] = line
    end

    if type(model.notes) == "table" and #model.notes > 0 then
        kids[#kids + 1] = { kind = "section", text = ProfHelper.NOTES }
        for _, text in ipairs(model.notes) do
            if type(text) == "string" and text ~= "" then kids[#kids + 1] = { kind = "row", label = text } end
        end
    end
    return view
end

function ProfHelper.Declare(k)
    local U = ns.SkillUps
    local api = {}
    -- The helper's kit window with the plain panel behind it
    -- (UI/KitHost.lua).
    local host
    -- What the open window reads as, for ProfHelper.View; nil while the
    -- helper shows nothing.
    local model
    local function hide()
        model = nil
        if host then host.show(false) end
    end

    k:Module({
        name = ProfHelper.NAME,
        needs = { "client", "store", "bus", "settings", "sched", "advisor" },
        settings = { {
            key = ProfHelper.SETTING, scope = "account", type = "bool", default = true,
            label = "Skill-up helper beside the profession window",
            help = "Shows your skill, a goal you type, how many points your bags can make, and the cheapest "
                .. "recipes that give a point now. It reads the window only and never crafts.",
            -- A topic of Settings/Topics.lua (N56).
            group = "professions",
            synonyms = { "skill", "skill-up", "leveling", "profession", "recipes", "helper" },
        } },
        start = function(ctx)
            local client = ctx.client
            local window

            local function pass(ok, ...)
                if not ok then return nil end
                return ...
            end
            -- A client read under pcall: nil when the call is missing or raised.
            local function read(name, ...)
                local fn = client[name]
                if type(fn) ~= "function" then return nil end
                return pass(pcall(fn, ...))
            end

            -- The saved recipe book entry with this recipe id, or nil
            -- (Items/RecipeBook.lua, read only here).
            local function saved(id)
                local RB = ns.RecipeBook
                if type(RB) ~= "table" or type(RB.Recipes) ~= "function" then return nil end
                local ok, all = pcall(RB.Recipes, k)
                if not ok or type(all) ~= "table" then return nil end
                for _, e in pairs(all) do
                    if type(e) == "table" and e.id == id then return e end
                end
                return nil
            end
            -- A recipe mats { [item] = n a craft }, from c.recipeSchematic,
            -- else the recipe book entry; nil when neither reads.
            local function mats(id)
                local sc = read("recipeSchematic", id)
                if type(sc) ~= "table" or type(sc.mats) ~= "table" then sc = saved(id) end
                if type(sc) ~= "table" or type(sc.mats) ~= "table" then return nil end
                return sc.mats
            end
            -- What one craft costs at the merchant buy prices seen; nil when
            -- the mats or any one price are not known.
            local function cost(m)
                if type(m) ~= "table" then return nil end
                local book = ctx.store:get("account", ProfHelper.PRICES_PATH)
                book = type(book) == "table" and book or nil
                local function info(item) return read("itemInfo", item) end
                local total = 0
                for item, n in pairs(m) do
                    local found = ns.PriceLookup.Find(item, info, book)
                    local unit = found and found.buy and found.buy.unit
                    if type(unit) ~= "number" or type(n) ~= "number" then return nil end
                    total = total + unit * n
                end
                return total
            end

            local function goals() return ctx.store:table("char", ProfHelper.GOALS_PATH) end

            -- The open window as { profession, skill, max, rows }, rows
            -- { key, name, difficulty, mats }: from the modern read, else
            -- the classic rows; nil when neither answers.
            local function readWindow()
                local w = read("recipes")
                if type(w) == "table" and type(w.recipes) == "table"
                    and type(w.skill) == "number" and type(w.max) == "number" then
                    local rows = {}
                    for _, r in ipairs(w.recipes) do
                        if type(r) == "table" and r.learned == true and type(r.id) == "number" then
                            local named = type(r.name) == "string"
                            rows[#rows + 1] = { key = named and r.name or r.id, id = r.id,
                                name = named and r.name or ("recipe " .. r.id),
                                difficulty = r.difficulty, mats = mats(r.id), icon = r.icon }
                        end
                    end
                    return { profession = w.profession, skill = w.skill, max = w.max, rows = rows }
                end
                -- Classic: every row listed is a recipe the player knows.
                w = read("tradeSkillRows")
                if type(w) ~= "table" or type(w.rows) ~= "table" or type(w.name) ~= "string"
                    or type(w.skill) ~= "number" or type(w.max) ~= "number" then
                    return nil
                end
                local rows = {}
                for _, r in ipairs(w.rows) do
                    if type(r) == "table" and type(r.name) == "string" and type(r.index) == "number" then
                        local sc = read("tradeSkillSchematic", r.index)
                        local m
                        if type(sc) == "table" and not sc.partial and type(sc.mats) == "table" then m = sc.mats end
                        rows[#rows + 1] = { key = r.name, name = r.name, difficulty = r.difficulty, mats = m,
                            index = r.index }
                    end
                end
                return { profession = w.name, skill = w.skill, max = w.max, rows = rows }
            end

            -- A6: the craft hint for one ranked row, as lines only. Nothing
            -- when the mats are not read or the plan cannot be made.
            local function plan(out, row, count)
                if type(row) ~= "table" or type(row.mats) ~= "table" or type(ns.CraftHint) ~= "table"
                    or type(ns.Resources) ~= "table" then
                    return
                end
                local key, made = "recipe:" .. row.name, "made:" .. row.name
                local snapshot = ns.Resources.Take({ items = function()
                    local have = {}
                    for item in pairs(row.mats) do
                        local n = read("itemCount", item)
                        if type(n) ~= "number" then return nil end
                        have[item] = n
                    end
                    return have
                end })
                local hint = ns.CraftHint.Build({ recipe = key, count = count }, {
                    recipes = { [key] = { makes = made, yield = 1, mats = row.mats } },
                    names = { [made] = row.name },
                    snapshot = snapshot, book = {}, sources = {}, useBank = false,
                })
                if type(hint) ~= "table" or hint.ok ~= true or type(hint.lines) ~= "table" then return end
                for _, line in ipairs(hint.lines) do
                    if type(line) == "string" then out[#out + 1] = { kind = "info", text = line } end
                end
            end

            -- N23: the trainers seen for this profession.
            local function trainers(out, w)
                local lists = ctx.store:get("char", ProfHelper.TRAINERS_PATH)
                local meets, nextSkill = ProfHelper.Trainers(lists, w.profession, w.skill)
                for _, m in ipairs(meets) do
                    out[#out + 1] = { kind = "info", text = ProfHelper.TRAINER_MEETS:format(m.count, m.npc) }
                end
                if nextSkill then
                    out[#out + 1] = { kind = "info", text = ProfHelper.TRAINER_NEXT:format(nextSkill) }
                end
            end

            -- N24: a tool a listed classic row needs and the bags do not hold.
            -- The prompt goes only when no tool is missing and each recipe
            -- that raised it answered again; a read that does not answer
            -- keeps it (unknown is not carried).
            local raisedBy = {}
            local function tools(out, w, ranked)
                if type(w.profession) ~= "string" then return end
                local first, answered, missingBy = nil, {}, {}
                for i = 1, math.min(ProfHelper.TOP, #ranked) do
                    local r = ranked[i]
                    if type(r.index) == "number" then
                        local list = read("tradeSkillTools", r.index)
                        if type(list) == "table" then
                            answered[r.name] = true
                            for _, tool in ipairs(list) do
                                if type(tool) == "table" and tool.has == false and type(tool.name) == "string" then
                                    out[#out + 1] = { kind = "info",
                                        text = ProfHelper.TOOL_MISSING:format(tool.name, r.name) }
                                    first = first or { tool = tool.name, recipe = r.name }
                                    missingBy[r.name] = true
                                end
                            end
                        end
                    end
                end
                local advisor = ctx.use("advisor")
                if type(advisor) ~= "table" then return end
                local id = ProfHelper.TOOL_ID .. w.profession
                if first then
                    advisor.Add(id, ProfHelper.TOOL_PROMPT:format(first.tool, first.recipe), ProfHelper.TOOL_PRIORITY)
                    raisedBy[id] = missingBy
                    return
                end
                for name in pairs(raisedBy[id] or {}) do
                    if not answered[name] then return end
                end
                raisedBy[id] = nil
                advisor.Remove(id)
            end

            local act
            local function draw()
                if not host then return end
                window = readWindow()
                if not window then
                    model = { reading = true }
                    host.draw(ProfHelper.View(model, act), { { kind = "info", text = ProfHelper.READING } }, act)
                    return
                end
                local skill, max = window.skill, window.max
                local rows, colours = {}, {}
                for _, r in ipairs(window.rows) do
                    rows[#rows + 1] = { key = r.key, name = r.name, difficulty = r.difficulty,
                        cost = cost(r.mats), mats = r.mats, index = r.index, icon = r.icon }
                    colours[#colours + 1] = { key = r.key, difficulty = r.difficulty }
                end
                local seen = ctx.store:table("char", ProfHelper.COLORS_PATH)
                if type(seen) == "table" then
                    ProfHelper.Fold(seen, window.rows)
                    U.Observe(seen, colours, skill)
                end

                local g = goals()
                local goal = type(g) == "table" and g[window.profession] or nil
                local out = {
                    { kind = "number", key = "goal", label = "Skill goal", value = type(goal) == "number" and goal or 0,
                        min = 0, max = ProfHelper.GOAL_MAX, enabled = true },
                    { kind = "info", text = ProfHelper.SKILL:format(skill, max) },
                }
                local state = U.Goal(skill, max, type(goal) == "number" and goal or nil)
                if state then
                    if state.overCap then
                        out[#out + 1] = { kind = "info", text = ProfHelper.OVER_CAP:format(goal, max) }
                    elseif state.need > 0 then
                        out[#out + 1] = { kind = "info", text = ProfHelper.TO_GOAL:format(state.need, goal) }
                    else
                        out[#out + 1] = { kind = "info", text = ProfHelper.AT_GOAL:format(goal) }
                    end
                end

                local ranked = U.Rank(rows)
                local shown = { profession = window.profession, skill = skill, max = max, state = state,
                    recipes = {}, notes = {} }
                if type(goal) == "number" then shown.goal = goal end
                if #ranked == 0 then
                    out[#out + 1] = { kind = "info", text = ProfHelper.NONE }
                else
                    local read_any = false
                    for _, r in ipairs(ranked) do
                        if r.chance ~= "unknown" and type(r.mats) == "table" then read_any = true end
                    end
                    if not read_any then
                        out[#out + 1] = { kind = "info", text = ProfHelper.BAGS_UNREAD }
                    else
                        local bags = U.FromBags(ranked, {
                            mats = function(row) return row.mats end,
                            have = function(item) return read("itemCount", item) end,
                            skill = skill, max = max, seen = type(seen) == "table" and seen or {},
                        })
                        shown.bags = { sure = bags.sure, maybe = bags.maybe }
                        if bags.sure + bags.maybe == 0 then
                            out[#out + 1] = { kind = "info", text = ProfHelper.BAGS_NONE }
                        else
                            out[#out + 1] = { kind = "info", text = ProfHelper.BAGS:format(bags.sure, bags.maybe) }
                        end
                    end
                    for i = 1, math.min(ProfHelper.TOP, #ranked) do
                        local r = ranked[i]
                        local word = ProfHelper[WORD[r.chance]]
                        local text = r.cost and ProfHelper.ROW:format(r.name, word, ns.Prices.Coin(r.cost))
                            or ProfHelper.ROW_NOCOST:format(r.name, word)
                        out[#out + 1] = { kind = "info", text = text }
                        shown.recipes[#shown.recipes + 1] = { name = r.name, chance = r.chance,
                            difficulty = r.difficulty, cost = r.cost, icon = r.icon }
                    end
                    local count = 1
                    if state and not state.overCap and state.need > 0 then count = state.need end
                    local before = #out
                    plan(out, ranked[1], count)
                    for i = before + 1, #out do shown.notes[#shown.notes + 1] = out[i].text end
                end
                local before = #out
                trainers(out, window)
                tools(out, window, ranked)
                for i = before + 1, #out do shown.notes[#shown.notes + 1] = out[i].text end
                model = shown
                host.draw(ProfHelper.View(shown, act), out, act)
            end

            -- The player typed a goal: kept per profession on the character;
            -- zero clears it. Nothing else is asked of the game.
            act = function(key, value)
                if key ~= "goal" or not window or type(value) ~= "number" then return end
                local g = goals()
                if type(g) ~= "table" then return end
                g[window.profession] = value > 0 and value or nil
                draw()
            end

            -- The helper as a kit window spec now, or nil while it shows
            -- nothing (the window closed, or the setting off).
            function api.view()
                if model == nil then return nil end
                return ProfHelper.View(model, act)
            end

            local function on() return ctx.settings:get(ProfHelper.SETTING) ~= false end
            -- The profession window is open: from its show to its close.
            local open = false
            -- The player closed the helper's kit window: it stays closed
            -- until the next profession window.
            local closed = false

            ctx.bus:on(ProfHelper.NAME, "TRADE_SKILL_SHOW", function()
                open = true
                closed = false
                if not on() then
                    hide()
                    return
                end
                draw()
                host.show(true)
            end)
            ctx.bus:on(ProfHelper.NAME, "TRADE_SKILL_LIST_UPDATE", function()
                if not host.shown() then return end
                draw()
            end)
            ctx.bus:on(ProfHelper.NAME, "TRADE_SKILL_CLOSE", function()
                open = false
                window = nil
                hide()
            end)
            -- The setting turned off while the window is up hides the panel;
            -- turned on while it is open, shows it (section 245 item 2).
            ctx.sched:every(ProfHelper.NAME, ProfHelper.EVERY, function()
                if host.dead() then return end
                if host.shown() and not on() then
                    hide()
                elseif open and on() and not closed and not host.shown() then
                    draw()
                    host.show(true)
                end
            end)

            local id = k.id or ns.id
            local panel
            if type(client.rowPanel) == "function" then
                panel = client.rowPanel({ name = id.framePrefix .. "ProfHelper", width = ProfHelper.WIDTH, height = 120 })
            end
            if panel then
                panel.show(false)
                panel.place(ProfHelper.DEFAULT_POINT)
            end
            host = ns.KitHost.New(k, client, { name = id.framePrefix .. "ProfHelperKit", panel = panel,
                onClose = function() closed = true end })
        end,
        stop = function()
            hide()
        end,
    })
    return api
end

ns.profHelper = ProfHelper.Declare(ns)
