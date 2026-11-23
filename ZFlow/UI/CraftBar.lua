local _, ns = ...

-- The craft bar (P-CRAFT, lead section 226: #34 Smelt All, G21 the craft
-- bar, craft controls): a small panel beside the profession window with a
-- count for each learned recipe, Start or Stop, Smelt all on the mining
-- window, and Clear. One click on Start makes the ticked counts one craft
-- at a time, the next started when the last one finished, until the counts
-- are made or something stops them (Items/CraftQueue.lua says what).
-- Nothing crafts without the click; a stopped run waits for the next one.
-- Needs game test: the events, the spell of a finished craft being the
-- recipe id, and a craft started from the finish of the last one.

local CraftBar = ns.CraftBar or {}
ns.CraftBar = CraftBar

CraftBar.NAME = "craftBar"
CraftBar.SETTING = "craft.queue"
CraftBar.WIDTH = 240
CraftBar.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 700, -120 }
-- Seconds a craft may take to finish before the run stops as not started.
CraftBar.WATCHDOG = 10
CraftBar.HINT = "Tick a count, then click Start."
CraftBar.NOTHING = "Tick a count first."
CraftBar.NOTHING_TO_SMELT = "Nothing to smelt: no ore for a learned recipe."
-- Section 231: From goals found no goal still to craft in this window.
CraftBar.NO_GOALS = "No goal to craft in this window."

function CraftBar.Declare(k)
    local Q = ns.CraftQueue
    local api = {}
    local running, status = false, nil
    function api.running() return running end
    function api.status() return status end

    local panel, cancelWatch
    local function hide()
        if panel then panel.show(false) end
    end
    local function unwatch()
        if cancelWatch then
            pcall(cancelWatch)
            cancelWatch = nil
        end
    end

    k:Module({
        name = CraftBar.NAME,
        needs = { "client", "store", "bus", "settings", "sched" },
        settings = { {
            key = CraftBar.SETTING, scope = "account", type = "bool", default = true,
            label = "Craft bar beside the profession window",
            help = "Tick how many of each recipe to make and click Start once: the crafts run one after another "
                .. "until the counts are made, and stop on combat, moving, full bags or a missing reagent. "
                .. "Nothing crafts without your click.",
            group = "Other",
        } },
        provides = { Running = api.running, Status = api.status },
        start = function(ctx)
            local client = ctx.client
            local book = { recipes = {} }
            local counts = {}
            local q

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
            -- ACTING: one craft of the recipe (Core/Client.lua craftRecipe),
            -- only from the player click on Start or Smelt all and the
            -- finish of the craft that click started.
            local function craft(recipe)
                if type(client.craftRecipe) ~= "function" then return nil, "noCall" end
                local ok, done, why = pcall(client.craftRecipe, recipe, 1)
                if not ok then return nil, "noCall" end
                return done, why
            end

            local function readBook()
                local r = read("recipes")
                book = (type(r) == "table" and type(r.recipes) == "table") and r or { recipes = {} }
            end
            -- The saved recipe book entry with this recipe id, or nil. The
            -- book (Items/RecipeBook.lua, read only here) is filled from
            -- the open window, by the classic row read c.tradeSkillSchematic
            -- where the client has no GetRecipeSchematic (section 234).
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
            -- A recipe reagents as the craft queue reads them,
            -- { { item, count } } by item, from c.recipeSchematic (the read
            -- the recipe book uses; section 231), else from the recipe
            -- book entry for that id. nil when neither reads.
            local function reagents(id)
                local sc = read("recipeSchematic", id)
                if type(sc) ~= "table" or type(sc.mats) ~= "table" then sc = saved(id) end
                if type(sc) ~= "table" or type(sc.mats) ~= "table" then return nil end
                local out = {}
                for item, n in pairs(sc.mats) do out[#out + 1] = { item = item, count = n } end
                table.sort(out, function(a, b) return a.item < b.item end)
                return out
            end
            local function learned()
                local out = {}
                for _, r in ipairs(book.recipes) do
                    if type(r) == "table" and r.learned == true and type(r.id) == "number" then
                        out[#out + 1] = r
                    end
                end
                return out
            end
            -- Free slots in plain bags (family 0 or not given): a special
            -- bag holds no bar. nil when the bags or a bag were not read.
            local function freeSlots()
                local bags = read("bags")
                if type(bags) ~= "table" then return nil end
                local free = 0
                for _, b in ipairs(bags) do
                    if type(b) ~= "table" or type(b.free) ~= "number" or b.free < 0 then return nil end
                    if b.family == nil or b.family == 0 then free = free + b.free end
                end
                return free
            end
            local function itemName(item)
                local info = read("itemInfo", item)
                if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
                return "item " .. tostring(item)
            end
            local function reads(row)
                local usable, why = read("recipeUsable", row.id)
                return {
                    combat = read("inCombat"),
                    moving = read("moving"),
                    usable = usable,
                    why = why,
                    free = freeSlots(),
                    reagents = reagents(row.id),
                    have = function(item) return read("itemCount", item) end,
                }
            end

            local act
            local function draw()
                if not panel then return end
                local rows = {}
                for _, r in ipairs(learned()) do
                    rows[#rows + 1] = { kind = "number", key = "count:" .. r.id,
                        label = type(r.name) == "string" and r.name or ("recipe " .. r.id),
                        value = counts[r.id] or 0, min = 0, max = Q.MAX, enabled = not running }
                end
                rows[#rows + 1] = { kind = "button", key = "start", label = running and "Stop" or "Start", enabled = true }
                if Q.SMELTS[book.profession] then
                    rows[#rows + 1] = { kind = "button", key = "all", label = "Smelt all", enabled = not running }
                end
                rows[#rows + 1] = { kind = "button", key = "goals", label = "From goals", enabled = not running }
                rows[#rows + 1] = { kind = "button", key = "clear", label = "Clear", enabled = not running }
                rows[#rows + 1] = { kind = "info", text = status or CraftBar.HINT }
                panel.draw(rows, act)
            end

            local function stop(why, detail)
                unwatch()
                running = false
                status = q and Q.StopLine(q, why, detail) or nil
                draw()
            end

            local function nextCraft()
                local row = Q.Current(q)
                if not row then
                    unwatch()
                    running = false
                    status = Q.DoneLine(q)
                    draw()
                    return
                end
                local why, detail = Q.Blocker(row, reads(row))
                if why then
                    if why == "missing" then detail = itemName(detail) end
                    stop(why, detail)
                    return
                end
                local ok, failed = craft(row.id)
                if not ok then
                    stop(failed == "combat" and "combat" or "noCall")
                    return
                end
                unwatch()
                cancelWatch = ctx.sched:after(CraftBar.NAME, CraftBar.WATCHDOG, function()
                    cancelWatch = nil
                    if running then stop("noStart") end
                end)
                status = Q.Line(q)
                draw()
            end

            local function begin()
                local picks = {}
                for _, r in ipairs(learned()) do
                    local n = counts[r.id]
                    if type(n) == "number" and n >= 1 then
                        picks[#picks + 1] = { id = r.id, name = r.name, count = n }
                    end
                end
                if #picks == 0 then
                    status = CraftBar.NOTHING
                    draw()
                    return
                end
                q = Q.New(picks)
                running = true
                nextCraft()
            end

            act = function(key, value)
                if key == "start" then
                    if running then stop("click") else begin() end
                elseif running then
                    return
                elseif key == "all" then
                    local picks = Q.MakeAll(learned(), reagents,
                        function(item) return read("itemCount", item) end)
                    counts = {}
                    for _, p in ipairs(picks) do counts[p.id] = p.count end
                    if #picks == 0 then
                        status = CraftBar.NOTHING_TO_SMELT
                        draw()
                        return
                    end
                    begin()
                elseif key == "goals" then
                    -- Section 231: ItemGoals.Crafts as it is. Each goal whose
                    -- recipe is learned in this window and still needs
                    -- crafts sets that count; the others are left as they
                    -- are. Fills counts only: Start is still the click.
                    local G = ns.ItemGoals
                    local ok, goals = false, nil
                    if type(G) == "table" and type(G.Crafts) == "function" then ok, goals = pcall(G.Crafts, k) end
                    local here, filled = {}, 0
                    for _, r in ipairs(learned()) do here[r.id] = true end
                    for _, g in ipairs(ok and type(goals) == "table" and goals or {}) do
                        local n = type(g) == "table" and g.times or nil
                        if g.known == true and here[g.recipeId] and type(n) == "number" and n >= 1 and n == math.floor(n) then
                            counts[g.recipeId] = math.min(n, Q.MAX)
                            filled = filled + 1
                        end
                    end
                    status = filled == 0 and CraftBar.NO_GOALS or nil
                    draw()
                elseif key == "clear" then
                    counts, status = {}, nil
                    draw()
                elseif type(key) == "string" and key:sub(1, 6) == "count:" then
                    local id = tonumber(key:sub(7))
                    if id and type(value) == "number" and value >= 0 and value <= Q.MAX
                        and value == math.floor(value) then
                        counts[id] = value
                        draw()
                    end
                end
            end

            local function mine(unit) return unit == "player" end
            ctx.bus:on(CraftBar.NAME, "TRADE_SKILL_SHOW", function()
                if ctx.settings:get(CraftBar.SETTING) == false then
                    hide()
                    return
                end
                readBook()
                draw()
                if panel then panel.show(true) end
            end)
            ctx.bus:on(CraftBar.NAME, "TRADE_SKILL_LIST_UPDATE", function()
                if not (panel and panel.shown()) then return end
                readBook()
                draw()
            end)
            ctx.bus:on(CraftBar.NAME, "TRADE_SKILL_CLOSE", function()
                if running then stop("window") end
                hide()
            end)
            ctx.bus:on(CraftBar.NAME, "UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
                if not running or not mine(unit) then return end
                local row = Q.Current(q)
                if not row or spellID ~= row.id then return end
                unwatch()
                Q.Made(q)
                nextCraft()
            end)
            ctx.bus:on(CraftBar.NAME, "UNIT_SPELLCAST_INTERRUPTED", function(unit, _, spellID)
                if not running or not mine(unit) then return end
                local row = Q.Current(q)
                if spellID ~= nil and row and spellID ~= row.id then return end
                stop("interrupted")
            end)
            ctx.bus:on(CraftBar.NAME, "PLAYER_REGEN_DISABLED", function()
                if running then stop("combat") end
            end)
            ctx.bus:on(CraftBar.NAME, "PLAYER_STARTED_MOVING", function()
                if running then stop("moving") end
            end)

            local id = k.id or ns.id
            panel = type(client.rowPanel) == "function" and client.rowPanel({ name = id.framePrefix .. "CraftBar",
                width = CraftBar.WIDTH, height = 80 }) or nil
            if panel then
                panel.show(false)
                panel.place(CraftBar.DEFAULT_POINT)
                panel.onClose(function()
                    if running then stop("closed") end
                end)
            end
        end,
        stop = function()
            unwatch()
            running = false
            hide()
        end,
    })
    return api
end

ns.craftBar = CraftBar.Declare(ns)
