local _, ns = ...

-- The craft bar (P-CRAFT, lead section 226: #34 Smelt All, G21 the craft
-- bar, craft controls): a small panel beside the profession window with a
-- count for each learned recipe, Start or Stop, Smelt all on the mining
-- window, From goals, and Clear. Lead section 234: a click on Start (or
-- Smelt all) asks one craft of the first recipe not yet made, with its
-- whole count as the game repeat count. A finish only counts; when a recipe
-- is made the next one waits for the next click. Nothing crafts without the
-- click, and never from a finish, a timer or the tick. A stop (the click,
-- combat, moving, a window closing, a blocker seen at a finish) asks the
-- game to stop the repeat, which is not a craft (Items/CraftQueue.lua says
-- what stops it). Needs game test: the events, the spell of a finished
-- craft being the recipe id, the repeat count, and the stop call.

local CraftBar = ns.CraftBar or {}
ns.CraftBar = CraftBar

CraftBar.NAME = "craftBar"
CraftBar.SETTING = "craft.queue"
CraftBar.WIDTH = 240
CraftBar.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 700, -120 }
-- The kit window's size and place. First guess: not yet seen in the game.
CraftBar.KIT_WIDTH, CraftBar.KIT_HEIGHT = 320, 360
CraftBar.KIT_POINT = { "TOPLEFT", "TOPLEFT", 700, -120 }
-- Seconds a craft may take to finish before the run stops as not started.
CraftBar.WATCHDOG = 10
CraftBar.HINT = "Tick a count, then click Start."
CraftBar.NOTHING = "Tick a count first."
CraftBar.NOTHING_TO_SMELT = "Nothing to smelt: no ore for a learned recipe."
-- Section 231: From goals found no goal still to craft in this window.
CraftBar.NO_GOALS = "No goal to craft in this window."
-- Section 234: a recipe is made and the next waits for the click.
CraftBar.NEXT = "Click Start for %s."
-- Sections 236, 237: each craft the click asked, kept on the character for
-- the capture (recipe, asked, made, at, stop, why), newest last. Shows
-- whether the client ran the repeat count: made against asked.
CraftBar.RUNS_PATH = "learned.craftRuns"
CraftBar.RUNS_KEEP = 10

-- The bar on the shared kit (lead sections 287 and 291): what it shows as
-- a kit window spec (UI/Kit.lua, K.Window). Pure: no client, no kernel.
CraftBar.TITLE = "Craft bar"
CraftBar.NO_RECIPES = "You know no recipe in this window."
CraftBar.NO_RECIPES_HOW = "Learn one at your profession trainer, then open this window again."

-- Lead sections 340 item 2 and 341: the bar and the skill-up helper stand
-- under the profession window, the list at its bottom left and the goal at
-- its bottom right, as the old add-on stood. Pure: the rectangle and the
-- screen are handed in.
-- The game's profession windows by their global names, classic then modern.
-- First guesses, not seen in game (both are in Diag.NAMES): only their
-- place is read (client.frameRect), nothing of theirs is changed.
CraftBar.DOCK_FRAMES = { "TradeSkillFrame", "ProfessionsFrame" }
-- The gap between the profession window, the two windows and the screen's
-- bottom edge; the least room under the profession window worth a dock; and
-- what a docked window's title, header, heading and first line take, so
-- the rest is the scroll's. First guesses.
CraftBar.DOCK_GAP = 8
CraftBar.DOCK_MIN = 90
CraftBar.DOCK_HEAD = 96
CraftBar.DOCK_SCROLL_MIN = 40
CraftBar.LIST = "Craft list"
CraftBar.LIST_FOLDED = "Craft list (click to open)"

local function isSide(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- CraftBar.Dock(rect, screenWidth, screenHeight)
--   rect  the profession window as client.frameRect gives it: { l, r, b, t }
--   -> { list = { point, height }, goal = { point, height } }; one of the
--      two is left out when it would stand past the screen's right edge.
--      nil when the rectangle or the screen is not read, or there is too
--      little room under the window.
-- A point is { "TOPLEFT", "BOTTOMLEFT", x, y }: the kit window's top left
-- corner, from the screen's bottom left. A height is the room under the
-- profession window, never more than the window's own.
function CraftBar.Dock(rect, screenWidth, screenHeight)
    if type(rect) ~= "table" or not isSide(rect.l) or not isSide(rect.r) or not isSide(rect.b)
        or not isSide(rect.t) then
        return nil
    end
    if not isSide(screenWidth) or not isSide(screenHeight) or screenWidth <= 0 or screenHeight <= 0 then
        return nil
    end
    local gap = CraftBar.DOCK_GAP
    local top = rect.b - gap
    local room = top - gap
    if room < CraftBar.DOCK_MIN then return nil end
    local H = ns.ProfHelper
    local goalWidth, goalHeight = CraftBar.KIT_WIDTH, CraftBar.KIT_HEIGHT
    if type(H) == "table" and isSide(H.KIT_WIDTH) and isSide(H.KIT_HEIGHT) then
        goalWidth, goalHeight = H.KIT_WIDTH, H.KIT_HEIGHT
    end
    local out, any = {}, false
    if rect.l >= 0 and rect.l + CraftBar.KIT_WIDTH <= screenWidth then
        out.list = { point = { "TOPLEFT", "BOTTOMLEFT", rect.l, top }, height = math.min(CraftBar.KIT_HEIGHT, room) }
        any = true
    end
    -- The goal's right edge is the profession window's, but never on the list.
    local x = math.max(rect.r - goalWidth, rect.l + CraftBar.KIT_WIDTH + gap)
    if x >= 0 and x + goalWidth <= screenWidth then
        out.goal = { point = { "TOPLEFT", "BOTTOMLEFT", x, top }, height = math.min(goalHeight, room) }
        any = true
    end
    if not any then return nil end
    return out
end

-- The place of one of the two ("list" or "goal") under the profession
-- window that is up now, or nil. Reads only.
function CraftBar.Slot(client, which)
    if type(client) ~= "table" or type(client.frameRect) ~= "function" or type(client.screen) ~= "function" then
        return nil
    end
    local okS, sw, sh = pcall(client.screen)
    if not okS then return nil end
    for _, name in ipairs(CraftBar.DOCK_FRAMES) do
        local okR, rect = pcall(client.frameRect, name)
        if okR and type(rect) == "table" then
            local d = CraftBar.Dock(rect, sw, sh)
            if d == nil then return nil end
            return d[which]
        end
    end
    return nil
end

-- Puts a docked view where its slot says; true when it was. A slot that
-- does not read leaves the view's own place and size.
function CraftBar.Place(view, slot)
    if type(slot) ~= "table" or type(slot.point) ~= "table" or not isSide(slot.height) or slot.height <= 0 then
        return false
    end
    view.point, view.height = slot.point, slot.height
    return true
end

-- The list the open body is added to: in a docked (short) window a scroll,
-- else the window's own children.
function CraftBar.Body(view, docked)
    if not docked then return view.children end
    local body = {}
    view.children[#view.children + 1] = { kind = "scroll", key = "body", children = body,
        height = math.max(CraftBar.DOCK_SCROLL_MIN, view.height - CraftBar.DOCK_HEAD) }
    return body
end

-- CraftBar.View(model[, act]) -> a kit window spec
--   model  { recipes, running, smelts, status, folded, dock }:
--          recipes  { { id, name, count, difficulty, icon, quality } } the
--                   learned recipes, count the number queued, quality the
--                   item quality of what it makes (0 to 5) or nil
--          folded   true: collapsed to the heading, the status and, while a
--                   craft runs, Stop; false: open under a heading that
--                   folds; nil: open, no heading
--          dock     a slot of CraftBar.Dock, or nil for the bar's own place
--          running  a craft the click asked is under way
--          smelts   the window smelts, so Smelt all is offered
--          status   why the bar stopped or what it waits for, or nil
--   act    the bar's own click: act("start"), act("all"), act("goals"),
--          act("clear"), act("count:<id>", n), act("fold", true | false). A
--          button that is off passes nothing on.
-- The count buttons stand in for a number control the kit does not have
-- yet (kit ask).
function CraftBar.View(model, act)
    local Q = ns.CraftQueue
    local view = { id = "CraftBar", title = CraftBar.TITLE, children = {},
        width = CraftBar.KIT_WIDTH, height = CraftBar.KIT_HEIGHT, point = CraftBar.KIT_POINT }
    local kids = view.children
    if type(model) ~= "table" then model = {} end
    local running = model.running == true
    local function click(key, value)
        if type(act) == "function" then act(key, value) end
    end

    local docked = CraftBar.Place(view, model.dock)
    kids[1] = { kind = "header", title = CraftBar.TITLE }
    local folded = model.folded == true
    if type(model.folded) == "boolean" then
        local heading = CraftBar.LIST
        if folded then heading = CraftBar.LIST_FOLDED end
        kids[#kids + 1] = { kind = "section", key = "fold", text = heading, folded = folded,
            onFold = function(now) click("fold", now == true) end }
    end
    local status = CraftBar.HINT
    if type(model.status) == "string" and model.status ~= "" then status = model.status end
    kids[#kids + 1] = { kind = "row", key = "status", label = status }
    if folded then
        -- A craft under way can always be stopped.
        if running then
            kids[#kids + 1] = { kind = "button", key = "start", text = "Stop", enabled = true,
                tooltip = "Stops the craft under way.", onClick = function() click("start") end }
        end
        return view
    end
    kids = CraftBar.Body(view, docked)

    local recipes = model.recipes
    if type(recipes) ~= "table" or #recipes == 0 then
        kids[#kids + 1] = { kind = "empty", key = "recipes", text = CraftBar.NO_RECIPES, how = CraftBar.NO_RECIPES_HOW }
        return view
    end

    local colours = ns.ProfHelper and ns.ProfHelper.COLOURS
    for _, r in ipairs(recipes) do
        local count = 0
        if type(r.count) == "number" and r.count > 0 then count = r.count end
        local name = "recipe " .. tostring(r.id)
        if type(r.name) == "string" and r.name ~= "" then name = r.name end
        local line = { kind = "itemLine", name = name, count = count }
        -- The kit takes a texture path or the game's file number; anything
        -- else is left out, so it cannot cost the window.
        local icon = r.icon
        if (type(icon) == "string" and icon ~= "") or (type(icon) == "number" and icon > 0 and icon < math.huge) then
            line.icon = icon
        end
        -- Kit ask: a line colour that is not an item quality (the skill colour).
        if type(colours) == "table" and type(r.difficulty) == "string" then line.color = colours[r.difficulty] end
        -- The kit colours the line by the quality of what the recipe makes.
        local quality = r.quality
        if type(quality) == "number" and quality >= 0 and quality <= 5 and quality == math.floor(quality) then
            line.quality = quality
        end
        kids[#kids + 1] = line
        local less, more = not running and count > 0, not running and count < Q.MAX
        kids[#kids + 1] = { kind = "button", key = "less:" .. r.id, text = "-", enabled = less,
            tooltip = "One fewer " .. name .. ".",
            onClick = function() if less then click("count:" .. r.id, count - 1) end end }
        kids[#kids + 1] = { kind = "button", key = "more:" .. r.id, text = "+", enabled = more,
            tooltip = "One more " .. name .. ".",
            onClick = function() if more then click("count:" .. r.id, count + 1) end end }
    end

    local startText = "Start"
    if running then startText = "Stop" end
    kids[#kids + 1] = { kind = "button", key = "start", text = startText, enabled = true,
        tooltip = "Start makes the first recipe with a count; the next one waits for your next click.",
        onClick = function() click("start") end }
    local function idle(key, text, tooltip)
        kids[#kids + 1] = { kind = "button", key = key, text = text, enabled = not running, tooltip = tooltip,
            onClick = function() if not running then click(key) end end }
    end
    if model.smelts == true then idle("all", "Smelt all", "Smelts every bar your ore makes.") end
    idle("goals", "From goals", "Fills the counts from your item goals. Start is still your click.")
    idle("clear", "Clear", "Sets every count back to none.")
    return view
end

function CraftBar.Declare(k)
    local Q = ns.CraftQueue
    local api = {}
    -- running: a craft the click asked is under way. asked: that craft was
    -- asked of the game, so a stop asks the game to stop its repeat.
    local running, asked, status = false, false, nil
    -- The kept record of the craft under way (CraftBar.RUNS_PATH), or nil.
    local run
    function api.running() return running end
    function api.status() return status end

    -- host: the bar's kit window with the plain panel behind it
    -- (UI/KitHost.lua).
    local host, cancelWatch
    -- What the bar shows, for CraftBar.View; nil while it shows nothing.
    local model
    local function hide()
        model = nil
        if host then host.show(false) end
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
            help = "Tick how many of each recipe to make and click Start: each click makes one recipe at its "
                .. "count, and the next recipe waits for your next click. It stops on combat, moving, full bags "
                .. "or a missing reagent. Nothing crafts without your click.",
            group = "professions", synonyms = { "craft", "crafting", "profession", "recipes", "batch", "smelt" },
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
            -- ACTING (section 234): one ask of the recipe n times
            -- (Core/Client.lua craftRecipe, n as the game repeat count).
            -- Reached only from act() on the player click on Start or
            -- Smelt all; never from a finish, a timer or the tick.
            local function craft(recipe, n)
                if type(client.craftRecipe) ~= "function" then return nil, "noCall" end
                local ok, done, why = pcall(client.craftRecipe, recipe, n)
                if not ok then return nil, "noCall" end
                return done, why
            end
            -- Not a craft: asks the game to stop the repeat a click started.
            local function stopRepeat()
                if not asked then return end
                asked = false
                if type(client.stopCraftRepeat) == "function" then pcall(client.stopCraftRepeat) end
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
            -- The item quality (0 to 5) of what a recipe makes, or nil when
            -- its product or that item is not read.
            local function quality(id)
                local sc = read("recipeSchematic", id)
                if type(sc) ~= "table" or sc.makes == nil then sc = saved(id) end
                if type(sc) ~= "table" or sc.makes == nil then return nil end
                local info = read("itemInfo", sc.makes)
                if type(info) ~= "table" then return nil end
                return info.quality
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

            -- Section 341: the bar opens collapsed. The player's fold is
            -- kept for the session, not saved.
            local folded = true
            -- Where the bar stands under the profession window; false: asked
            -- and none. Asked once, at the first draw: the kit places and
            -- sizes a window only when it is first made.
            local dock
            local act
            local function draw()
                if not host then return end
                if dock == nil then dock = CraftBar.Slot(client, "list") or false end
                local rows = {}
                local shown = { recipes = {}, running = running, smelts = Q.SMELTS[book.profession] == true,
                    status = status, folded = folded }
                if dock then shown.dock = dock end
                for _, r in ipairs(learned()) do
                    shown.recipes[#shown.recipes + 1] = { id = r.id, name = r.name, count = counts[r.id] or 0,
                        difficulty = r.difficulty, icon = r.icon, quality = quality(r.id) }
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
                model = shown
                host.draw(CraftBar.View(shown, act), rows, act)
            end

            -- Keeps the ask on the character, the oldest dropped past
            -- CraftBar.RUNS_KEEP. Records only; asks nothing.
            local function record(recipe, n)
                local runs = ctx.store:table("char", CraftBar.RUNS_PATH)
                if type(runs) ~= "table" then
                    run = nil
                    return
                end
                run = { recipe = recipe, asked = n, made = 0, at = client.now() }
                runs[#runs + 1] = run
                while #runs > CraftBar.RUNS_KEEP do table.remove(runs, 1) end
            end

            -- How the kept run ended. Clears it, so a later stop of the
            -- same run does not overwrite the reason.
            local function ended(why, detail)
                if run then
                    run.stop = why
                    run.why = detail
                end
                run = nil
            end

            local function stop(why, detail)
                ended(why)
                unwatch()
                stopRepeat()
                running = false
                status = q and Q.StopLine(q, why, detail) or nil
                q = nil
                draw()
            end

            -- The next finish must come within the watchdog, or the run
            -- stops as not started. A stop, never a craft.
            local function watch()
                unwatch()
                cancelWatch = ctx.sched:after(CraftBar.NAME, CraftBar.WATCHDOG, function()
                    cancelWatch = nil
                    if running then stop("noStart") end
                end)
            end

            -- What stops the row now, with the missing item named.
            local function blocked(row)
                local why, detail = Q.Blocker(row, reads(row))
                if why == "missing" then detail = itemName(detail) end
                return why, detail
            end

            -- On the click only: ask the current row, all it still needs.
            local function askRow()
                local row = Q.Current(q)
                local why, detail = blocked(row)
                if why then
                    stop(why, detail)
                    return
                end
                running = true
                record(row.id, row.count - row.made)
                local ok, failed = craft(row.id, row.count - row.made)
                if not ok then
                    ended("refused", failed)
                    stop(failed == "combat" and "combat" or "noCall")
                    return
                end
                asked = true
                watch()
                status = Q.Line(q)
                draw()
            end

            -- A finish of the row under way: count it. Asks nothing.
            local function finished()
                local row = Q.Current(q)
                Q.Made(q)
                if run then run.made = run.made + 1 end
                if Q.Current(q) == row then
                    local why, detail = blocked(row)
                    if why then
                        stop(why, detail)
                        return
                    end
                    watch()
                    status = Q.Line(q)
                    draw()
                    return
                end
                ended("done")
                unwatch()
                asked = false
                running = false
                local nextRow = Q.Current(q)
                if nextRow then
                    status = Q.DoneLine(q) .. " " .. CraftBar.NEXT:format(nextRow.name or ("recipe " .. nextRow.id))
                else
                    status = Q.DoneLine(q)
                    q = nil
                end
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
                askRow()
            end

            -- The player click. Start goes on with a run that waits for it,
            -- or begins one from the counts.
            act = function(key, value)
                -- Folding is no craft and drops no run: only the look changes.
                if key == "fold" then
                    folded = value == true
                    draw()
                    return
                end
                if key == "start" then
                    if running then stop("click")
                    elseif q and Q.Current(q) then askRow()
                    else begin() end
                    return
                elseif running then
                    return
                end
                -- Any other click drops a run that waits for Start.
                q = nil
                if key == "all" then
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

            -- The bar as a kit window spec now, or nil while it shows
            -- nothing. Its buttons pass the same clicks on as the panel's.
            function api.view()
                if model == nil then return nil end
                return CraftBar.View(model, act)
            end

            local function mine(unit) return unit == "player" end
            ctx.bus:on(CraftBar.NAME, "TRADE_SKILL_SHOW", function()
                if ctx.settings:get(CraftBar.SETTING) == false then
                    hide()
                    return
                end
                readBook()
                draw()
                host.show(true)
            end)
            ctx.bus:on(CraftBar.NAME, "TRADE_SKILL_LIST_UPDATE", function()
                if not host.shown() then return end
                readBook()
                draw()
            end)
            ctx.bus:on(CraftBar.NAME, "TRADE_SKILL_CLOSE", function()
                if running then stop("window") end
                q = nil
                hide()
            end)
            -- Counts a finish; never asks a craft (section 234).
            ctx.bus:on(CraftBar.NAME, "UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
                if not running or not mine(unit) then return end
                local row = Q.Current(q)
                if not row or spellID ~= row.id then return end
                finished()
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

            -- Closing the bar, the kit window or the plain panel, stops a run.
            local function closed()
                if running then stop("closed") end
            end
            local id = k.id or ns.id
            local panel
            if type(client.rowPanel) == "function" then
                panel = client.rowPanel({ name = id.framePrefix .. "CraftBar", width = CraftBar.WIDTH, height = 80 })
            end
            if panel then
                panel.show(false)
                panel.place(CraftBar.DEFAULT_POINT)
                panel.onClose(closed)
            end
            host = ns.KitHost.New(k, client, { name = id.framePrefix .. "CraftBarKit", panel = panel,
                onClose = closed })
        end,
        stop = function()
            unwatch()
            running, asked, run = false, false, nil
            hide()
        end,
    })
    return api
end

ns.craftBar = CraftBar.Declare(ns)
