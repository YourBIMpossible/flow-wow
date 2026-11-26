local _, ns = ...

-- Tests for UI/RouteList.lua (lead section 387, R4): the route list beside
-- the quest log. The rows and parts are pure; the window is read through
-- the fake client's kit window. Made-up quests and places. Not tested in
-- game.

local tests = {}

local function RL() return ns.RouteList end
local function TL() return ns.Nav.TrackerList end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }
local BOX = { shown = true, right = 400, top = 700, height = 450 }

local function view()
    return { kind = "quests", label = "Quest route", stops = {
        { quest = 11, objective = 1, label = "Boar Trouble", detail = "Boars slain: 2/8",
          place = { map = 1, x = 0.5, y = 0.6 } },
        { quest = 12, turnIn = true, label = "A Letter Home", detail = "Turn in: Marshal Dunn",
          place = { map = 1, x = 0.8, y = 0.6 } },
        { quest = 13, turnIn = true, label = "Lost Tools", detail = "Turn in: Marshal Dunn",
          place = { map = 1, x = 0.8, y = 0.6 } },
        { quest = 14, kind = "pickup", label = "Wolves at the Gate", detail = "Pick up from Guard Thom",
          place = { map = 2, x = 0.2, y = 0.2 } },
        { quest = 15, turnIn = true, label = "Old Debts", detail = "Turn in",
          place = { map = 2, x = 0.3, y = 0.3 } },
        { quest = 16, turnIn = true, label = "Stale Bread", detail = "Turn in", held = "not complete any more",
          place = { map = 1, x = 0.1, y = 0.1 } },
    }, left = {
        { quest = 17, label = "Far Away", detail = "Turn in", why = "not on this map" },
        { quest = 18, label = "Odd One", why = "needs a key" },
    } }
end

local function byKey(children, key)
    for _, part in ipairs(children) do
        if part.key == key then return part end
    end
    return nil
end

-- opts: view (a function giving the route's view, or nil for no route),
-- setting (false: the tick is off), noFrames.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    if opts.noFrames then c.setFrames(false) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local current = opts.view
    k:Module({ name = "tripRoute", provides = { View = function() return current end } })
    local api = RL().Declare(k)
    local card
    if opts.card then card = ns.StepCard.Declare(k) end
    if opts.cardToggle then k:Module({ name = "stepCard", provides = { Toggle = opts.cardToggle } }) end
    local map = ns.MapRoute.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.setting == false then k.settings:set(RL().SETTING, false) end
    return { c = c, k = k, api = api, map = map, card = card, set = function(v) current = v end }
end

local function window(h)
    return h.c.kitWindows()[RL().ID]
end

local function textOf(win, key)
    for _, p in ipairs(win and win.parts or {}) do
        if p.key == key then return p.text end
    end
    return nil
end

tests["rows: each kind of stop says what to do in plain words"] = function(t)
    local rows, _, nLeft = TL().Rows(view(), HERE)
    t.eq(#rows, 7, "four to walk (two turn-ins as one), one waiting, two left off")
    t.eq(nLeft, 2)
    t.eq(rows[1].text, "Boars slain: 2/8")
    t.eq(rows[1].sub, "For the quest Boar Trouble")
    t.eq(rows[1].now, true)
    t.eq(rows[1].dist, "100 yd")
    t.eq(rows[2].text, "Turn in 2 quests")
    t.eq(rows[2].sub, "A Letter Home, Lost Tools. Give them to Marshal Dunn")
    t.eq(rows[2].merged, 2)
    t.eq(rows[2].dist, "300 yd")
    t.eq(rows[3].text, "Wolves at the Gate")
    t.eq(rows[3].sub, "Pick up from Guard Thom")
    t.eq(rows[3].dist, ns.Nav.Trip.OTHER_MAP)
    t.eq(rows[4].text, "Turn in Old Debts")
    t.eq(rows[4].sub, nil, "no receiver known: none is made up")
    t.eq(rows[6].text, "Far Away")
    t.eq(rows[7].text, "Odd One")
end

tests["rows: numbered in route order, a waiting stop has no number"] = function(t)
    local rows = TL().Rows(view(), HERE)
    for i = 1, 4 do t.eq(rows[i].n, i) end
    t.eq(rows[5].n, nil)
    t.eq(rows[5].blocked, true)
end

tests["rows: one turn-in names its receiver"] = function(t)
    local rows = TL().Rows({ stops = {
        { quest = 12, turnIn = true, label = "A Letter Home", detail = "Turn in: Marshal Dunn",
          place = { map = 1, x = 0.8, y = 0.6 } } } }, HERE)
    t.eq(rows[1].text, "Turn in A Letter Home")
    t.eq(rows[1].sub, "Give it to Marshal Dunn")
end

tests["rows: turn-ins at different places stay apart"] = function(t)
    local rows = TL().Rows({ stops = {
        { quest = 12, turnIn = true, label = "A", detail = "Turn in", place = { map = 1, x = 0.8, y = 0.6 } },
        { quest = 13, turnIn = true, label = "B", detail = "Turn in", place = { map = 1, x = 0.7, y = 0.6 } },
    } }, HERE)
    t.eq(#rows, 2)
    t.eq(rows[1].text, "Turn in A")
    t.eq(rows[2].text, "Turn in B")
end

tests["rows: a trip's stop is its own words"] = function(t)
    local rows = TL().Rows({ kind = "run", stops = {
        { label = "Inn", detail = "Inna", place = { map = 1, x = 0.5, y = 0.6 } } } }, HERE)
    t.eq(rows[1].text, "Inn")
    t.eq(rows[1].sub, "Inna")
end

tests["rows: no route is no rows"] = function(t)
    t.eq(TL().Rows(nil, HERE), nil)
end

tests["blocked: a waiting stop and what was left off say why in plain words"] = function(t)
    local rows = TL().Rows(view(), HERE)
    t.eq(rows[5].text, "Turn in Stale Bread")
    t.eq(rows[5].sub, "this quest is not complete any more. Finish it again first.")
    t.eq(rows[6].text, "Far Away")
    t.eq(rows[6].sub, "Not on the route: it is in another zone. Plan a new route when you get there.")
    t.eq(rows[7].sub, "Not on the route: needs a key", "a reason not known here is shown as given")
    local kids = RL().Children(rows, 0, 2, { stops = 4, waiting = 1 })
    t.eq(byKey(kids, "waitingHead").text, "Waiting", "the held stops sit under their own heading")
    t.eq(byKey(kids, "held1").tone, RL().TONE_BLOCKED)
    t.eq(byKey(kids, "held1").sub, rows[5].sub)
    t.eq(byKey(kids, "leftHead").text, "Not on the route")
    t.eq(byKey(kids, "left1").sub, rows[6].sub)
    t.eq(byKey(kids, "left2").tone, RL().TONE_BLOCKED)
end

tests["blocked: every reason the route gives has plain words"] = function(t)
    local Q, T = ns.Nav.QuestSource, ns.Nav.TripRoute
    for _, why in ipairs({ Q.HELD_NOT_READ, Q.HELD_PREREQ, T.HELD_NOT_COMPLETE, T.NOT_HERE }) do
        t.ok(type(why) == "string" and TL().PLAIN[why] ~= nil, "plain words for: " .. tostring(why))
    end
end

tests["parts: the current stop is marked, numbers and distances shown"] = function(t)
    local rows, more, nLeft, counts = TL().Rows(view(), HERE)
    local kids = RL().Children(rows, more, nLeft, counts, "Today's route · Shortest first", nil,
        function() end, function() end)
    t.eq(kids[1].kind, "header")
    t.eq(byKey(kids, "plan").text, "Today's route · Shortest first", "the plan in one plain line")
    t.eq(byKey(kids, "summary").text, "4 stops, 1 waiting, 2 not on the route")
    local now = byKey(kids, "current")
    t.eq(now.text, "1. Boars slain: 2/8")
    t.eq(now.tone, RL().TONE_NOW)
    t.eq(now.right, "100 yd")
    t.eq(now.sub, "For the quest Boar Trouble. " .. RL().NOW)
    t.eq(byKey(kids, "stop2").text, "2. Turn in 2 quests")
    t.eq(byKey(kids, "stop2").tone, nil)
    t.eq(byKey(kids, "stop2").icon, ns.Kit.look.icon.questInLog)
    t.ok(type(byKey(kids, "stop2").onClick) == "function", "a row can be clicked")
    t.ok(type(byKey(kids, "left1").onClick) == "function", "what was left off can be clicked too (slice 7: it opens the card)")
    local foot = byKey(kids, "footer")
    t.ok(foot ~= nil and foot.buttons[1].text == RL().SKIP, "the Skip button under the current row")
    t.ok(ns.Kit.Window({ id = RL().ID, title = "x", children = kids }) ~= nil, "the kit takes the parts")
end

tests["parts: how many stops show is nav.routeShown's, in the builder"] = function(t)
    local stops = {}
    for i = 1, 15 do
        stops[i] = { label = "S" .. i, place = { map = 1, x = i / 100, y = 0.5 } }
    end
    local rows, more, _, counts = TL().Rows({ stops = stops }, HERE, TL().MaxShown("10"))
    t.eq(#rows, 10)
    t.eq(more, 5)
    local kids = RL().Children(rows, more, 0, counts)
    t.ok(byKey(kids, "stop10") ~= nil, "the last shown")
    t.eq(byKey(kids, "stop11"), nil)
    t.eq(byKey(kids, "more").text, "and 5 more stops")
    t.eq(RL().Rows, nil, "the list builds no rows of its own any more")
end

tests["empty: no route is one plain line and what to do"] = function(t)
    local kids = RL().Children(nil, nil, nil, nil, nil, "Type /zflow route to plan one from your quest log.")
    local e = byKey(kids, "empty")
    t.eq(e.kind, "empty")
    t.eq(e.text, "No route planned yet.")
    t.eq(e.how, "Type /zflow route to plan one from your quest log.")
    t.eq(byKey(kids, "current"), nil)
    t.eq(#kids, 2, "the header and the one line, no empty boxes")
    t.ok(ns.Kit.Window({ id = RL().ID, title = "x", children = kids }) ~= nil, "the kit takes the parts")
end

tests["empty: the window says it with the addon's own slash word"] = function(t)
    local h = start({})
    h.c.setQuestLogFrame(BOX)
    h.api.Refresh()
    t.eq(textOf(window(h), "empty"), RL().EMPTY)
    local how = RL().EMPTY_HOW:format(ns.id.slash, ns.Nav.TripRoute.WORD)
    t.eq(how, "Type /zflow route to plan one from your quest log.")
    t.eq(byKey(RL().Children(nil), "empty").how, how, "said even when no words are handed in")
end

tests["window: it opens with the quest log and closes with it"] = function(t)
    local h = start({ view = view() })
    h.api.Refresh()
    t.eq(h.api.Shown(), false, "no quest log frame: nothing shown")
    h.c.setQuestLogFrame({ shown = false })
    h.api.Refresh()
    t.eq(h.api.Shown(), false, "the quest log is closed")
    h.c.setQuestLogFrame(BOX)
    h.api.Refresh()
    t.eq(h.api.Shown(), true, "the quest log opened")
    t.eq(window(h).shown, true)
    t.eq(textOf(window(h), "current"), "1. Boars slain: 2/8")
    h.c.setQuestLogFrame({ shown = false })
    h.api.Refresh()
    t.eq(h.api.Shown(), false, "closed with the quest log")
    h.c.setQuestLogFrame(BOX)
    h.api.Refresh()
    t.eq(h.api.Shown(), true, "and open with it again")
end

tests["window: it stands at the quest log's right edge, as tall as it"] = function(t)
    local h = start({ view = view() })
    h.c.setQuestLogFrame(BOX)
    h.api.Refresh()
    local w = window(h)
    t.eq(w.point, { "TOPLEFT", "BOTTOMLEFT", 400, 700 })
    t.eq(w.width, RL().WIDTH)
    t.eq(w.height, 450)
    h.c.setQuestLogFrame({ shown = true, right = 500, top = 650, height = 450 })
    h.api.Refresh()
    t.eq(window(h).point, { "TOPLEFT", "BOTTOMLEFT", 500, 650 }, "it follows the quest log")
end

tests["window: it follows the route"] = function(t)
    local h = start({ view = view() })
    h.c.setQuestLogFrame(BOX)
    h.api.Refresh()
    h.set({ stops = { { label = "Inn", detail = "Inna", place = { map = 1, x = 0.5, y = 0.6 } } } })
    h.api.Refresh()
    t.eq(textOf(window(h), "current"), "1. Inn")
    h.set(nil)
    h.api.Refresh()
    t.eq(textOf(window(h), "empty"), RL().EMPTY)
end

tests["window: closed by the player it stays closed until the quest log opens again"] = function(t)
    local h = start({ view = view() })
    h.c.setQuestLogFrame(BOX)
    h.api.Refresh()
    h.c.kitClose(RL().ID)
    h.api.Refresh()
    t.eq(h.api.Shown(), false, "the player closed it")
    h.c.setQuestLogFrame({ shown = false })
    h.api.Refresh()
    h.c.setQuestLogFrame(BOX)
    h.api.Refresh()
    t.eq(h.api.Shown(), true, "the next time the quest log opens it is back")
end

tests["click: a row opens the map on its stop's map and nothing else"] = function(t)
    local h = start({ view = view() })
    h.c.setQuestLogFrame(BOX)
    h.api.Refresh()
    h.c.kitClick(RL().ID, "stop3")
    t.eq(h.c.mapsShown, { 2 })
    h.c.kitClick(RL().ID, "current")
    t.eq(h.c.mapsShown, { 2, 1 })
    t.eq(textOf(window(h), "current"), "1. Boars slain: 2/8", "the route is as it was")
end

tests["setting: on at first, and the tick hides the list, the pins and the card"] = function(t)
    local h = start({ view = view() })
    t.eq(h.k.settings:get(RL().SETTING), true, "on at first")
    h.c.setQuestLogFrame(BOX)
    h.c.setWorldMap(1)
    h.api.Refresh()
    h.map.Refresh()
    t.eq(h.api.Shown(), true)
    t.eq(h.c.routePinSets[1].shown, true)
    t.eq(h.c.mapCards[1].shown, true)
    h.k.settings:set(RL().SETTING, false)
    h.api.Refresh()
    h.map.Refresh()
    t.eq(h.api.Shown(), false, "the list is hidden")
    t.eq(h.c.routePinSets[1].shown, false, "the pins are hidden")
    t.eq(h.c.mapCards[1].shown, false, "the card is hidden")
    h.k.settings:set(RL().SETTING, true)
    h.api.Refresh()
    h.map.Refresh()
    t.eq(h.api.Shown(), true, "and back with the tick")
    t.eq(h.c.routePinSets[1].shown, true)
    t.eq(h.c.mapCards[1].shown, true)
end

tests["setting: off from the start nothing is drawn"] = function(t)
    local h = start({ view = view(), setting = false })
    h.c.setQuestLogFrame(BOX)
    h.c.setWorldMap(1)
    h.api.Refresh()
    h.map.Refresh()
    t.eq(window(h), nil)
    t.eq(#h.c.routePinSets, 0)
    t.eq(#h.c.mapCards, 0)
end

tests["no frames: nothing is drawn and nothing breaks"] = function(t)
    local h = start({ view = view(), noFrames = true })
    h.c.setQuestLogFrame(BOX)
    h.c.setWorldMap(1)
    h.api.Refresh()
    h.map.Refresh()
    t.eq(h.api.Shown(), false)
    t.eq(h.map.Shown(), false)
end

-- Parity row C-14 (lead section 603): what is worth knowing about a quest
-- before you walk to it, from Questie's quest data (Flow
-- Modules/Quests/QuestNeeds.lua Q.ApplyNeed). Fails before:
-- the needs are TL.Needs', read by TL.Rows through the needOf it is given.
tests["route list needs: an escort objective tags escort, with no note"] = function(t)
    local tags, note = TL().Needs({ triggerEnd = { "Escort Perith Stormhoof out of Palemane Rock" } })
    t.eq(tags, { "escort" })
    t.eq(note, nil, "Flow's hand-written escort note is not carried (section 620)")
    t.eq(TL().ESCORT_NOTE, nil)
end

tests["route list needs: a suggested group of 2 or more tags it"] = function(t)
    local tags, note = TL().Needs({ suggestedGroup = 3 })
    t.eq(tags, { "group of 3" })
    t.eq(note, nil)
    t.eq(TL().Needs({ suggestedGroup = 1 }), nil, "one is solo")
    t.eq(TL().Needs({ suggestedGroup = 0 }), nil)
end

tests["route list needs: nothing known says nothing"] = function(t)
    t.eq(TL().Needs(nil), nil)
    t.eq(TL().Needs({}), nil)
    t.eq(TL().Needs({ triggerEnd = { "Explore the cave" } }), nil)
end

tests["route list needs: a stop's tags follow its name; the note leads its line"] = function(t)
    local function needOf(quest)
        if quest == 11 then return { "escort", "group of 3" }, "Escort note." end
        if quest == 14 then return { "group of 2" }, nil end
        return nil
    end
    local rows = TL().Rows(view(), HERE, TL().ALL, needOf)
    t.eq(rows[1].text, "Boars slain: 2/8 (escort, group of 3)", "the tags follow the stop's own words")
    t.eq(rows[1].sub:sub(1, #"Escort note."), "Escort note.")
    local pickup
    for _, r in ipairs(rows) do
        if r.text:find("Wolves at the Gate", 1, true) then pickup = r end
    end
    t.eq(pickup and pickup.text, "Wolves at the Gate (group of 2)")
    local plain = TL().Rows(view(), HERE)
    t.eq(plain[1].text, "Boars slain: 2/8", "no needs given: as before")
end

-- Slice 5's point, made literal: the list and the tracker draw the
-- same TL.Rows rows — same stops in the same order, the same held
-- and left-off words under the same headings.
tests["slice 5: the list and the tracker read the same rows"] = function(t)
    local rows, more, nLeft, counts = TL().Rows(view(), HERE)
    local rl = RL().Children(rows, more, nLeft, counts, nil, nil, function() end, function() end)
    local rt = ns.RouteTracker.Children(rows, nil, more, nil, function() end)
    local function texts(kids, prefix)
        local out = {}
        for _, p in ipairs(kids) do
            if p.key == "current" or (p.key and p.key:sub(1, #prefix) == prefix) then
                out[#out + 1] = p.text
            end
        end
        return out
    end
    local rlStops = texts(rl, "stop")
    for i, txt in ipairs(rlStops) do
        t.eq(txt, RL().NUMBERED:format(rows[i].n, rows[i].text), "the list's stop " .. i)
    end
    local rtStops = {}
    for _, p in ipairs(rt) do
        if p.key == "current" or (p.key and p.key:sub(1, 4) == "next") then rtStops[#rtStops + 1] = p.text end
    end
    t.eq(#rtStops, #rlStops, "the same number of stops in both windows")
    for i, txt in ipairs(rtStops) do
        t.eq(txt, rows[i].label, "the tracker's stop " .. i .. " is the same stop")
    end
    t.eq(byKey(rl, "waitingHead").text, byKey(rt, "waitingHead").text)
    t.eq(byKey(rl, "held1").sub, byKey(rt, "held1").sub, "the held reason reads the same in both")
    t.eq(byKey(rl, "left1").sub, byKey(rt, "left1").sub, "the left-off reason reads the same in both")
    t.eq(ns.RouteList.Rows, nil, "the list's own builder is gone")
end

-- The step card's last tree, the way StepCardKit reads it.
local function cardTree(c)
    local last
    local real = c.kitWindow
    c.kitWindow = function(id, tree, extra)
        if id == "stepCard" then last = tree end
        local h = real(id, tree, extra)
        if id == "stepCard" and type(h) == "table" and type(h.update) == "function" then
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

local function cardButton(tree, key)
    local found
    ns.Kit.Each(tree, function(p) if p.key == key then found = p end end)
    return found
end

local function cardTexts(tree)
    local joined = {}
    ns.Kit.Each(tree, function(p)
        if p.text then joined[#joined + 1] = p.text end
        if p.title then joined[#joined + 1] = p.title end
    end)
    return table.concat(joined, "\n")
end

tests["slice 7: a row click opens the step card; held and left-behind rows say not on your route"] = function(t)
    local h = start({ view = view(), card = true })
    h.c.setQuestLogFrame(BOX)
    h.api.Refresh()
    local treeOf = cardTree(h.c)
    h.c.kitClick(RL().ID, "current")
    t.eq(h.card.Shown(), true, "the card opens for the clicked stop")
    t.ok(h.c.mapsShown == nil or #h.c.mapsShown == 0, "the map does not open: it is the card's own button now")
    t.ok(cardTexts(treeOf()):find("Boar Trouble", 1, true) ~= nil, "the card is for the clicked stop")
    local first = cardButton(treeOf(), "act.first")
    t.eq(first and first.enabled, false, "the next step cannot be made next")
    t.eq(first and first.tooltip, "This is already your next step.", "because it already is (index 1)")
    h.c.kitClick(RL().ID, "held1")
    t.eq(h.card.Shown(), true, "a held row opens the card too")
    first = cardButton(treeOf(), "act.first")
    t.eq(first and first.enabled, false, "a held stop cannot be made next")
    t.eq(first and first.tooltip, "This step is not on your route.", "the card's not-on-route reason (no index passed)")
    h.c.kitClick(RL().ID, "left1")
    t.eq(h.card.Shown(), true, "a left-behind row opens the card too")
    first = cardButton(treeOf(), "act.first")
    t.eq(first and first.tooltip, "This step is not on your route.", "the same reason for what was left off")
end

tests["slice 7: a card that cannot open, or raises, leaves the row's click on the map"] = function(t)
    for _, toggle in ipairs({ function() return false end, function() error("boom") end }) do
        local h = start({ view = view(), cardToggle = toggle })
        h.c.setQuestLogFrame(BOX)
        h.api.Refresh()
        h.c.kitClick(RL().ID, "current")
        t.ok(h.c.mapsShown ~= nil and #h.c.mapsShown > 0, "the map opens, as in slice 5")
    end
end

return tests
