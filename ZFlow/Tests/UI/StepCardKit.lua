-- The step card window (parity row A1-13), on the whole add-on loaded on a
-- fake client: the card for one step from Nav/StepCard.lua's SC.Card, its
-- three buttons and what they call, the toggle, the saved place
-- (nav.cardPoint) and the beside-the-arrow first place. The data half is
-- Zen-3's; this file tests only the window. Not tested in game.
--
-- Red before the code: UI/StepCard.lua does not exist, so ns.StepCard is
-- nil and every test here fails its first check.
local _, ns = ...
local tests = {}

local M = ns.StepCard
local ID = "stepCard"

-- opts: log (quest log rows for c.setQuestLog), first (a fake tripRoute
-- module whose First records its calls), noSelectQuest (the client has no
-- selectQuest call), charSaved (the char DB as saved).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.charSaved or {})
    c.setScreen(1920, 1080)
    c.setQuestLog(opts.log or {})
    if opts.noSelectQuest then c.selectQuest = nil end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local firstCalls = {}
    if opts.first or opts.view then
        local provides = { First = function(n) firstCalls[#firstCalls + 1] = n end }
        if opts.view then provides.View = function() return opts.view end end
        k:Module({
            name = "tripRoute",
            provides = provides,
            start = function() end,
        })
    end
    local api = M.Declare(k, ns.diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, api, firstCalls
end

-- The tree the kit was last handed for this window, kept whole (the
-- record's parts keep only kind, text and note).
local function keepTree(c)
    local last
    local real = c.kitWindow
    c.kitWindow = function(id, tree, extra)
        if id == ID then last = tree end
        local h = real(id, tree, extra)
        if id == ID and type(h) == "table" and type(h.update) == "function" then
            local update = h.update
            h.update = function(now)
                last = now
                return update(now)
            end
        end
        return h
    end
    return function() return last end
end

local function partByKey(tree, key)
    local found
    ns.Kit.Each(tree, function(part)
        if part.key == key then found = part end
    end)
    return found
end

local function buttonsOf(tree)
    local out = {}
    ns.Kit.Each(tree, function(part)
        if part.kind == "button" then out[#out + 1] = part end
    end)
    return out
end

local function allText(tree)
    local joined = {}
    ns.Kit.Each(tree, function(p) if p.text then joined[#joined + 1] = p.text end end)
    return table.concat(joined, " | ")
end

local function step(over)
    local s = {
        label = "Red Silk Bandanas", title = "Scout Riell's bandanas",
        objective = "Bring 10 Red Silk Bandanas to Scout Riell.",
        detail = "The bandanas drop from Defias in Moonbrook.",
        quest = 101, place = { map = 1436, x = 0.42, y = 0.71 }, kind = "trip",
    }
    for key, v in pairs(over or {}) do s[key] = v end
    return s
end

local function partOf(tree, key)
    local found
    ns.Kit.Each(tree, function(p) if p.key == key then found = p end end)
    return found
end

function tests.toggleOpensTheCard(t)
    local c, api = boot()
    local tree = keepTree(c)
    t.eq(api.Toggle(step(), { distance = "312 yd", index = 2 }), true, "the toggle opens")
    local rec = c.kitWindows()[ID]
    t.ok(rec ~= nil and rec.shown == true, "the window is shown")
    local drawn = tree()
    t.eq(drawn.title, "Red Silk Bandanas", "the window title is the step's label")
    local sub = partByKey(drawn, "sub")
    t.ok(sub ~= nil, "a sub line is drawn")
    t.eq(sub.text, "Bring 10 Red Silk Bandanas to Scout Riell.", "the sub is the objective")
    t.eq(sub.right, "312 yd", "the distance stands at the right of the sub")
    local all = allText(drawn)
    t.ok(all:find("The bandanas drop from Defias in Moonbrook.", 1, true) ~= nil,
        "the body lines show: " .. all)
    t.ok(all:find("Scout Riell's bandanas", 1, true) ~= nil,
        "the detail title line shows: " .. all)
end

function tests.threeButtonsInOrder(t)
    local c, api = boot()
    local tree = keepTree(c)
    api.Toggle(step(), { index = 2 })
    local bs = buttonsOf(tree())
    t.eq(#bs, 3, "three buttons")
    t.eq(bs[1].text, "Quest log", "the first button")
    t.eq(bs[2].text, "Map", "the second button")
    t.eq(bs[3].text, "Do this next", "the third button")
end

function tests.questLogOffWhenNotInLog(t)
    local c, api = boot()
    local tree = keepTree(c)
    api.Toggle(step(), { index = 2 })
    local b = partByKey(tree(), "act.questLog")
    t.ok(b ~= nil, "the quest log button is drawn")
    t.eq(b.enabled, false, "the button is off")
    t.eq(b.tooltip, "That quest is not in your log.", "the why is the tooltip")
    c.kitClick(ID, "act.questLog")
    t.eq(c.selectedQuest(), nil, "a click on the off button selects nothing")
end

function tests.questLogSelectsTheQuest(t)
    local c, api = boot({ log = { { id = 101, title = "Red Silk Bandanas" } } })
    local tree = keepTree(c)
    api.Toggle(step(), { index = 2 })
    local b = partByKey(tree(), "act.questLog")
    t.eq(b.enabled, true, "the button is on")
    t.eq(c.kitClick(ID, "act.questLog"), true, "the button is clickable")
    t.eq(c.selectedQuest(), 101, "the quest was selected in the log")
end

function tests.questLogOffWhenTheClientCannotSelect(t)
    local c, api = boot({ log = { { id = 101, title = "Red Silk Bandanas" } }, noSelectQuest = true })
    local tree = keepTree(c)
    api.Toggle(step(), { index = 2 })
    local b = partByKey(tree(), "act.questLog")
    t.eq(b.enabled, false, "the button is off")
    t.eq(b.tooltip, "The quest log can't be opened at a quest yet.", "the why is the tooltip")
end

function tests.mapButtonShowsTheMap(t)
    local c, api = boot()
    api.Toggle(step(), { index = 2 })
    t.eq(c.kitClick(ID, "act.map"), true, "the map button is clickable")
    local found = false
    for _, m in ipairs(c.mapsShown or {}) do if m == 1436 then found = true end end
    t.ok(found, "showMap was called with the step's map")
end

function tests.mapButtonOffWithoutAPlace(t)
    local c, api = boot()
    local tree = keepTree(c)
    local s = step()
    s.place = nil
    api.Toggle(s, { index = 2 })
    local b = partByKey(tree(), "act.map")
    t.eq(b.enabled, false, "the button is off")
    t.eq(b.tooltip, "This step has no place on a map.", "the why is the tooltip")
end

function tests.firstOffForTheNextStep(t)
    local c, api = boot()
    local tree = keepTree(c)
    api.Toggle(step(), { index = 1 })
    local b = partByKey(tree(), "act.first")
    t.eq(b.enabled, false, "the button is off")
    t.eq(b.tooltip, "This is already your next step.", "the why is the tooltip")
end

function tests.firstOffWithoutARoute(t)
    local c, api = boot()
    local tree = keepTree(c)
    api.Toggle(step(), { index = 2 })
    local b = partByKey(tree(), "act.first")
    t.eq(b.enabled, false, "the button is off")
    t.eq(b.tooltip, "Steps can't be moved to the front yet.", "the why is the tooltip")
end

function tests.firstCallsFirstAndCloses(t)
    local c, api, firstCalls = boot({ first = true })
    local tree = keepTree(c)
    api.Toggle(step(), { index = 2 })
    local b = partByKey(tree(), "act.first")
    t.eq(b.enabled, true, "the button is on")
    t.eq(c.kitClick(ID, "act.first"), true, "the button is clickable")
    t.eq(#firstCalls, 1, "First was called once")
    t.eq(firstCalls[1], 2, "First was called with the step's index")
    t.eq(api.Shown(), false, "the card closes after Do this next")
end

function tests.secondToggleClosesAndANewStepRedraws(t)
    local c, api = boot()
    local tree = keepTree(c)
    api.Toggle(step(), { index = 2 })
    t.eq(api.Shown(), true, "shown after the first toggle")
    api.Toggle(step(), { index = 2 })
    t.eq(api.Shown(), false, "closed after the second toggle for the same step")
    api.Toggle(step(), { index = 2 })
    api.Toggle(step({ label = "Moonbrook Patrol", quest = 102 }), { index = 3 })
    t.eq(api.Shown(), true, "shown for the new step")
    t.eq(tree().title, "Moonbrook Patrol", "the card redraws for the new step")
end

function tests.savedPlaceWins(t)
    local saved = { layout = { stepCard = { point = { "CENTER", "CENTER", 40, -30 } } } }
    local c, api = boot({ charSaved = saved })
    api.Toggle(step(), { index = 2 }, { left = 900, bottom = 500, width = 56, height = 56 })
    local rec = c.kitWindows()[ID]
    t.ok(rec ~= nil and rec.point ~= nil, "a point was recorded")
    t.eq(rec.point[3], 40, "the saved x wins over the arrow")
    t.eq(rec.point[4], -30, "the saved y wins over the arrow")
end

function tests.besideTheArrowFirstPlace(t)
    local c, api = boot()
    api.Toggle(step(), { index = 2 }, { left = 900, bottom = 500, width = 56, height = 56 })
    local rec = c.kitWindows()[ID]
    t.eq(rec.point[1], "TOPLEFT", "the card hangs from its top left")
    t.eq(rec.point[3], 964, "x: the arrow's right edge plus a gap")
    t.eq(rec.point[4], 556, "y: the tops aligned")
    local c2, api2 = boot()
    api2.Toggle(step(), { index = 2 }, { left = 1700, bottom = 500, width = 56, height = 56 })
    local rec2 = c2.kitWindows()[ID]
    t.eq(rec2.point[3], 1352, "x flipped: the arrow's left edge minus a gap and the card's width")
end

function tests.noDistanceInventedAndHandInSub(t)
    local c, api = boot()
    local tree = keepTree(c)
    api.Toggle(step(), { index = 2 })
    local sub = partByKey(tree(), "sub")
    t.ok(sub ~= nil, "a sub line is drawn")
    t.eq(sub.right, nil, "no distance stands at the right when none was given")
    local c2, api2 = boot()
    local tree2 = keepTree(c2)
    local s2 = step()
    s2.objective = nil
    s2.turnIn = true
    api2.Toggle(s2, { index = 2 })
    local sub2 = partByKey(tree2(), "sub")
    t.eq(sub2.text, "Hand the quest in", "a hand-in step's sub says so")
end

-- A1-10: the drawer is the card's lower section, for the current step.
local function routeView()
    local cur = step()
    local nxt = { label = "Defias Grease", quest = 102, turnIn = true,
        detail = "Turn in: Scout Riell", place = { map = 1436, x = 0.4, y = 0.7 }, kind = "trip" }
    local heldStop = { label = "Old Sea Chest", quest = 103, turnIn = true,
        detail = "Turn in", held = "needs the Brass Key",
        place = { map = 1436, x = 0.3, y = 0.6 }, kind = "trip" }
    local last = { label = "Moonbrook Well", quest = 104, kind = "pickup",
        detail = "Pick up from Scout Riell", place = { map = 1436, x = 0.2, y = 0.5 } }
    return { stops = { cur, nxt, heldStop, last } }, cur, nxt, heldStop, last
end

function tests.drawerListsTheNextStops(t)
    local view, cur = routeView()
    local c, api, firstCalls = boot({ first = true, view = view })
    local tree = keepTree(c)
    t.eq(api.Toggle(cur, { index = 1 }), true)
    local thenPart = partOf(tree(), "then")
    t.eq(thenPart and thenPart.text, "Then (3 steps)", "the drawer's heading counts the other stops")
    local d1 = partOf(tree(), "dstop1")
    t.eq(d1 and d1.text, "  2. Defias Grease", "the next stop, numbered by its place")
    t.ok(d1 and type(d1.onClick) == "function", "a listed stop can be clicked")
    local d2 = partOf(tree(), "dstop2")
    t.eq(d2 and d2.text, "  3. Old Sea Chest (needs the Brass Key)", "a held stop carries its reason")
    t.ok(d2 and type(d2.onClick) == "function", "a held stop's line clicks too (it opens with no index)")
    local d3 = partOf(tree(), "dstop3")
    t.eq(d3 and d3.text, "  4. Moonbrook Well")
    d1.onClick()
    t.eq(api.Shown(), true, "the card stays open")
    t.eq(partOf(tree(), "then"), nil, "the drawer is gone: that stop is not the current one")
    local head
    ns.Kit.Each(tree(), function(p) if p.kind == "header" then head = p end end)
    t.eq(head and head.title, "Defias Grease", "the card now shows the clicked stop")
    c.kitClick(ID, "act.first")
    t.eq(firstCalls, { 2 }, "making it next calls First with its place: 2, counted from the current stop")
    t.eq(api.Shown(), false, "and the card closes, as the button does")
    -- A held stop opens with no index: not on your route.
    t.eq(api.Toggle(cur, { index = 1 }), true)
    partOf(tree(), "dstop2").onClick()
    local firstBtn = partOf(tree(), "act.first")
    t.eq(firstBtn and firstBtn.enabled, false, "a held stop cannot be made next")
    t.eq(firstBtn and firstBtn.tooltip, "This step is not on your route.", "no index was passed for it")
end

function tests.drawerOnlyForTheCurrentStep(t)
    local view, _, nxt = routeView()
    local c, api = boot({ first = true, view = view })
    local tree = keepTree(c)
    t.eq(api.Toggle(nxt, { index = 2 }), true)
    t.eq(partOf(tree(), "then"), nil, "no drawer under another stop's card")
end

function tests.drawerListsAHeldStopBeforeTheCurrentOne(t)
    local heldFirst = { label = "Locked Gate", quest = 105, turnIn = true,
        detail = "Turn in", held = "needs the Brass Key",
        place = { map = 1436, x = 0.3, y = 0.6 }, kind = "trip" }
    local after = step({ label = "After Gate", quest = 106 })
    local view = { stops = { heldFirst, after } }
    local c, api = boot({ first = true, view = view })
    local tree = keepTree(c)
    -- The current step is the first not held (After Gate); the held one
    -- ahead of it is still listed, with its reason.
    t.eq(api.Toggle(after, { index = 1 }), true)
    local d1 = partOf(tree(), "dstop1")
    t.eq(d1 and d1.text, "  1. Locked Gate (needs the Brass Key)")
    t.ok(d1 and type(d1.onClick) == "function", "and it opens its card, with no index")
end

return tests
