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
-- Needs game test: the colour and skill up fields of the recipe read
-- (Core/Client.lua c.recipes), and where the panel sits beside the window.

local ProfHelper = ns.ProfHelper or {}
ns.ProfHelper = ProfHelper

ProfHelper.NAME = "profHelper"
ProfHelper.SETTING = "prof.helper"
ProfHelper.WIDTH = 260
ProfHelper.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 700, -330 }
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

local WORD = { sure = "SURE", maybe = "MAYBE", unknown = "UNKNOWN" }

function ProfHelper.Declare(k)
    local U = ns.SkillUps
    local api = {}
    local panel
    local function hide()
        if panel then panel.show(false) end
    end

    k:Module({
        name = ProfHelper.NAME,
        needs = { "client", "store", "bus", "settings", "sched" },
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

            local act
            local function draw()
                if not panel then return end
                window = read("recipes")
                if type(window) ~= "table" or type(window.recipes) ~= "table"
                    or type(window.skill) ~= "number" or type(window.max) ~= "number" then
                    window = nil
                    panel.draw({ { kind = "info", text = ProfHelper.READING } }, act)
                    return
                end
                local skill, max = window.skill, window.max
                local rows, colours = {}, {}
                for _, r in ipairs(window.recipes) do
                    if type(r) == "table" and r.learned == true and type(r.id) == "number" then
                        local m = mats(r.id)
                        rows[#rows + 1] = { key = r.id, name = type(r.name) == "string" and r.name or ("recipe " .. r.id),
                            difficulty = r.difficulty, cost = cost(m), mats = m }
                        colours[#colours + 1] = { key = r.id, difficulty = r.difficulty }
                    end
                end
                local seen = ctx.store:table("char", ProfHelper.COLORS_PATH)
                if type(seen) == "table" then U.Observe(seen, colours, skill) end

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
                    end
                end
                panel.draw(out, act)
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

            local function on() return ctx.settings:get(ProfHelper.SETTING) ~= false end

            ctx.bus:on(ProfHelper.NAME, "TRADE_SKILL_SHOW", function()
                if not on() then
                    hide()
                    return
                end
                draw()
                if panel then panel.show(true) end
            end)
            ctx.bus:on(ProfHelper.NAME, "TRADE_SKILL_LIST_UPDATE", function()
                if not (panel and panel.shown()) then return end
                draw()
            end)
            ctx.bus:on(ProfHelper.NAME, "TRADE_SKILL_CLOSE", function()
                window = nil
                hide()
            end)
            -- The setting turned off while the window is up hides the panel.
            ctx.sched:every(ProfHelper.NAME, ProfHelper.EVERY, function()
                if panel and panel.shown() and not on() then hide() end
            end)

            local id = k.id or ns.id
            panel = type(client.rowPanel) == "function" and client.rowPanel({ name = id.framePrefix .. "ProfHelper",
                width = ProfHelper.WIDTH, height = 120 }) or nil
            if panel then
                panel.show(false)
                panel.place(ProfHelper.DEFAULT_POINT)
            end
        end,
        stop = function()
            hide()
        end,
    })
    return api
end

ns.profHelper = ProfHelper.Declare(ns)
