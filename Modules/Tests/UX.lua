-- Self-tests for lane W5 (arrows, settings, UX). Same style as Modules/Tests.lua:
--   ns:Register("test", "area: what it checks", function(t) ... end)
-- They stand in only for Flow's own functions (never a game global) and put
-- back any saved data they change.

local _, ns = ...

-- Runs fn with ns[tbl][name] replaced by stand-in, then puts it back.
local function withFlow(tbl, name, standIn, fn)
    local old = tbl[name]
    tbl[name] = standIn
    local ok, err = pcall(fn)
    tbl[name] = old
    if not ok then error(err, 0) end
end

-- Puts ns.db.setup's done / seen back after fn.
local function keepSetup(fn)
    local db = ns.db.setup
    local done, seen = db.done, db.seen
    local o, w = ns.setup._OfferFlags(false, false)
    local ok, err = pcall(fn)
    db.done, db.seen = done, seen
    ns.setup._OfferFlags(o, w)
    if not ok then error(err, 0) end
end

ns:Register("test", "setup: the first-run offer waits for the rest of Flow, then opens once a session", function(t)
    local O = ns.setup.OfferState
    t:eq(O(false, 0, false, true, false), "open", "never chosen: it opens")
    t:eq(O(false, 0, true, true, false), "wait", "in a fight: later, not never")
    t:eq(O(false, 0, false, false, false), "wait", "the rest of Flow isn't on screen yet: later this session, not next login")
    t:eq(O(false, 0, false, true, true), "no", "once a session")
    t:eq(O(true, 0, false, true, false), "no", "chosen, nothing new: nothing")
    t:eq(O(true, 2, false, true, false), "open", "chosen, a new suggestion: it opens")
end)

ns:Register("test", "setup: opening Flow Setup doesn't count as done; choosing does", function(t)
    if InCombatLockdown() then t:ok(true, "(in a fight: skipped)") return end
    local S = ns.setup
    keepSetup(function()
        ns.db.setup.done = nil
        local opened, printed, retries = 0, {}, 0
        local function later() retries = retries + 1 end
        withFlow(S, "Open", function() opened = opened + 1 end, function()
        withFlow(ns, "Print", function(_, m) printed[#printed + 1] = tostring(m) end, function()
            -- Not on screen yet: it waits and tries again, and isn't done.
            if ns.reveal then
                withFlow(ns.reveal, "Shown", function() return false end, function()
                    t:eq(S:TryOffer(later), "wait", "waits for the rest of Flow")
                end)
                t:eq(retries, 1, "tries again shortly")
                t:eq(opened, 0, "not opened yet")
            end
            withFlow(ns.reveal or {}, "Shown", function() return true end, function()
                t:eq(S:TryOffer(later), "open", "then opens")
                t:eq(S:TryOffer(later), "no", "only once a session")
            end)
        end)
        end)
        t:eq(opened, 1, "opened once")
        t:ok(not S:Done(), "opening it isn't choosing")
        t:ok(printed[1] and printed[1]:find("/flow setup", 1, true) ~= nil, "says how to reopen it")
        S:Finish()
        t:ok(S:Done(), "choosing marks it done")
    end)
end)

ns:Register("test", "click: Keep my settings finishes Flow Setup without changing a setting", function(t)
    local f = ns.settings._Build and ns.settings._Build()
    if not f then t:ok(true, "(no Options page on this client)") return end
    t:ok(f.useSuggestions ~= nil, "Use Flow's suggestions is on the page")
    t:ok(f.keepSettings ~= nil, "Keep my settings is on the page")
    if not f.keepSettings then return end
    keepSetup(function()
        ns.db.setup.done = nil
        local before = {}
        for _, r in ipairs(ns.setup:Rows()) do if r.item.isOn then before[r.key] = r.item.isOn() and true or false end end
        withFlow(ns, "Print", function() end, function()
            local ok, err = pcall(f.keepSettings:GetScript("OnClick"), f.keepSettings, "LeftButton")
            t:ok(ok, "the button runs" .. (ok and "" or (": " .. tostring(err))))
        end)
        t:ok(ns.setup:Done(), "Flow Setup is done")
        local same = true
        for _, r in ipairs(ns.setup:Rows()) do
            if r.item.isOn and before[r.key] ~= (r.item.isOn() and true or false) then same = false end
        end
        t:ok(same, "no setting changed")
    end)
end)

ns:Register("test", "setup: the camera style is a suggestion in Flow Setup, not switched at login", function(t)
    -- F-089: Flow used to set the game's Camera Following Style at the first login, unasked.
    local row = ns:Get("setupItem", "cameraStays")
    t:ok(row ~= nil, "a Flow Setup row")
    if not row then return end
    t:ok(row.suggested == true, "Flow suggests it (so a new player is offered it)")
    t:ok(row.isNew == true, "shown once to players who finished setup before it existed")
    t:ok(type(row.set) == "function", "changed only from the row")
end)

ns:Register("test", "click: the world-map route box turns the route back on after /flow map off", function(t)
    local M, n = ns.mapOverlay, ns.db.nav
    local route, lines = n.mapRoute, n.mapLines
    local ok, err = pcall(function()
        n.mapRoute, n.mapLines = false, nil      -- /flow map off
        t:ok(not M:RouteShown(), "hidden after /flow map off")
        local f = ns.settings._Build and ns.settings._Build()
        local box
        for _, c in ipairs(f and ns.settings:Checks() or {}) do
            local text = c.label and c.label:GetText()
            if text and text:find("Show the route on the world map", 1, true) then box = c end
        end
        if box and not InCombatLockdown() then
            if box.get then t:ok(not box.get(), "the box shows it hidden") end
            box:SetChecked(true)
            local okc, errc = pcall(box:GetScript("OnClick"), box, "LeftButton")
            t:ok(okc, "the box runs" .. (okc and "" or (": " .. tostring(errc))))
        else
            M:SetRouteShown(true)
        end
        t:ok(M:RouteShown(), "ticking it shows the route again")
        M:SetRouteShown(false)
        t:ok(not M:RouteShown(), "unticking hides it")
        t:eq(n.mapRoute, true, "and /flow map stays on (only the route is off)")
    end)
    n.mapRoute, n.mapLines = route, lines
    if not ok then error(err, 0) end
end)

ns:Register("test", "commands: /flow chat stamps still reaches the timestamps command", function(t)
    -- F-100: AskClaude.lua's /flow chat replaced Chat.lua's, so "stamps" did nothing.
    local AC = ns.askClaude
    t:ok(AC and AC._chatStamps ~= nil, "Chat.lua's command is kept")
    if not (AC and AC._chatStamps) then return end
    local got
    withFlow(AC, "_chatStamps", function(arg) got = arg end, function()
        ns.commands.chat("stamps short")
    end)
    t:eq(got, "stamps short", "passed on to it")
end)

ns:Register("test", "click: Flow Setup's Revert puts the boxes back to the settings as they are now", function(t)
    -- F-090: the button said "Reset", which reads as "back to defaults".
    if InCombatLockdown() then t:ok(true, "(in a fight: skipped)") return end
    local f = ns.setup._Table and ns.setup._Table()
    if not f then t:ok(true, "(no Flow Setup table)") return end
    t:ok(f.head and f.head.flowTitleBar == true, "a Flow title bar")
    t:eq(f.head and f.head.text:GetText(), "Flow Setup", "named Flow Setup")
    t:ok(f.picks.Reset == nil, "no Reset button")
    local b = f.picks.Revert
    t:ok(b ~= nil, "a Revert button")
    if not b then return end
    local rows = {}
    for _, r in ipairs(f.rows) do if r.check and r.item.isOn then rows[#rows + 1] = r end end
    for _, r in ipairs(rows) do r.check:SetChecked(not r.item.isOn()) end
    local ok, err = pcall(b:GetScript("OnClick"), b, "LeftButton")
    t:ok(ok, "the button runs" .. (ok and "" or (": " .. tostring(err))))
    local same = true
    for _, r in ipairs(rows) do
        if (r.check:GetChecked() and true or false) ~= (r.item.isOn() and true or false) then same = false end
    end
    t:ok(same, "every box matches the setting as it is now")
end)

ns:Register("test", "help: /flow help <word> shows only the help about that word", function(t)
    -- F-098: /flow help was one long dump.
    local all = ns.HelpFor("")
    t:ok(#all > 3, "no word: every topic")
    local nav = ns:Get("help", "nav")
    local got = ns.HelpFor("nav")
    local whole
    for _, e in ipairs(got) do if nav and e.title == nav.title then whole = e end end
    t:ok(whole ~= nil and #whole.lines == #nav.lines, "a topic's own name: the whole topic")
    local lines, others = 0, true
    for _, e in ipairs(ns.HelpFor("splash")) do
        for _, l in ipairs(e.lines) do
            lines = lines + 1
            if not l:lower():find("splash", 1, true) then others = false end
        end
    end
    t:ok(lines >= 1 and others, "any other word: only the lines that have it")
    t:eq(#ns.HelpFor("  SPLASH "), #ns.HelpFor("splash"), "case and spaces don't matter")
    t:eq(#ns.HelpFor("no-such-word-xq"), 0, "nothing for a word no help has")
end)

ns:Register("test", "click: the short, still intro box turns the spinning off and back on", function(t)
    -- F-097: the login intro was 4.6 s of motion with no way to tone it down.
    local I, db = ns.intro, ns.db.splash
    local was = db.short
    local ok, err = pcall(function()
        db.short = nil
        local spin, tail, moves = I.Times()
        t:ok(moves and spin + tail > 4, "by default: the full spinning intro")
        local f = ns.settings._Build and ns.settings._Build()
        local box
        for _, c in ipairs(f and ns.settings:Checks() or {}) do
            local text = c.label and c.label:GetText()
            if text and text:find("Short, still intro", 1, true) then box = c end
        end
        if box and not InCombatLockdown() then
            t:ok(not box.get(), "the box starts unticked")
            box:SetChecked(true)
            local okc, errc = pcall(box:GetScript("OnClick"), box, "LeftButton")
            t:ok(okc, "the box runs" .. (okc and "" or (": " .. tostring(errc))))
        else
            ns.commands.splash("short on")
        end
        spin, tail, moves = I.Times()
        t:ok(not moves, "ticked: nothing spins")
        t:ok(spin + tail < 2, "and it is short")
        withFlow(ns, "Print", function() end, function() ns.commands.splash("short off") end)
        t:ok(select(3, I.Times()), "/flow splash short off: back to the full intro")
    end)
    db.short = was
    if not ok then error(err, 0) end
end)

ns:Register("test", "words: the self button is called the self button, not the buff button", function(t)
    -- F-093: "Self button", "buff button"/"buff key" and "blue button" named one control.
    local said = {}
    local function scan(where, text)
        if type(text) ~= "string" then return end
        local l = text:lower()
        if l:find("buff key", 1, true) or l:find("buff button", 1, true) or l:find("/flow buff", 1, true) then
            said[#said + 1] = where .. ": " .. text
        end
    end
    local items = ns.menu and ns.menu.ButtonItems and ns.menu.ButtonItems() or {}
    for _, it in ipairs(items) do scan("menu", it.text); scan("menu tip", it.tip) end
    t:ok(items[1] and items[1].tip:find("self button", 1, true) ~= nil, "the menu's tip names it")
    local K = ns.careKeys
    if K and K.Lines then
        local ok, lines = pcall(K.Lines)
        if ok then for _, l in ipairs(lines) do scan("/flow carekeys", l) end end
    end
    t:eq(said[1], nil, "no other name for it")
end)

ns:Register("test", "settings: the tooltip spot is saved inverted and only through its accessor", function(t)
    -- F-092: settings.tipsBeside is "off" saved as true; Settings wrote it by hand.
    local s = ns.db.settings
    local was = s.tipsBeside
    local ok, err = pcall(function()
        s.tipsBeside = nil
        t:ok(ns.TipsAtGameSpot(), "unset: where WoW shows them (the default)")
        ns.SetTipsAtGameSpot(false)
        t:ok(not ns.TipsAtGameSpot(), "off: beside what you hover")
        t:eq(s.tipsBeside, true, "saved inverted")
        ns.SetTipsAtGameSpot(true)
        t:ok(ns.TipsAtGameSpot(), "back on")
        t:eq(s.tipsBeside, false, "the player's choice is kept, not cleared")
    end)
    s.tipsBeside = was
    if not ok then error(err, 0) end
end)

-------------------------------------------------------------------------------
-- P5 arrows: the pure layout functions (Modules/Nav/Arrows.lua). Plain tables
-- in and out: no frame and no saved data is touched, so these run offline.
-- (S1) to (S12) are the acceptance rows of the P5 design, section 7.1; what
-- each row needs from the frames is not covered here and needs the client.
-------------------------------------------------------------------------------
local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- A saved table as it comes back from a /reload: a new table, nothing shared.
local function reloaded(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[reloaded(k)] = reloaded(x) end
    return out
end

local function arrowCtx(gate)
    return { gate = gate or "open", screenW = 1920, screenH = 1080, size = 56, keys = { "professions" } }
end

-- The two lanes; nil leaves a lane out, true / false is "has a step".
local function arrowLanes(quest, prof)
    local out = {}
    if quest ~= nil then out[#out + 1] = { key = "quest", order = 1, hasStep = quest } end
    if prof ~= nil then out[#out + 1] = { key = "professions", order = 2, hasStep = prof } end
    return out
end

local OWN = { "CENTER", "CENTER", 200, -50 }   -- a place the profession arrow was dragged to

-- Separate, with the profession arrow at OWN.
local function separated()
    return ns.nav.ArrowApply({}, { type = "move", key = "professions", point = OWN }, arrowCtx())
end

ns:Register("test", "arrows (S1): stacked by default", function(t)
    local N = ns.nav
    for _, saved in ipairs({ {}, { arrows = {} }, { arrows = { mode = "stacked" } } }) do
        local L = N.ArrowLayout(saved, arrowLanes(true, true), arrowCtx())
        local Q, P = L.quest, L.professions
        t:ok(Q.shown and P.shown, "both arrows show")
        t:eq(Q.anchor, "screen", "the quest arrow has the place")
        t:ok(same(Q.point, { "TOP", "TOP", 0, -120 }), "nothing saved: the default place")
        t:eq(Q.look, "pointer", "the quest arrow is the full arrow")
        t:eq(Q.colourRule, "quest", "in its own colours")
        t:eq(Q.emphasis, "primary", "the main one")
        t:ok(not Q.behind, "in front")
        t:eq(P.anchor, "leader", "the profession arrow is anchored on the quest arrow")
        t:eq(P.point, nil, "with no place of its own on screen")
        t:eq(P.look, "needle", "as the long faint needle")
        t:ok(P.behind, "drawn behind it")
        t:eq(P.alpha, N.PROF_HOLDER_ALPHA, "see-through: the alpha today's arrow is built with")
        t:ok(P.alpha < 1, "less than solid")
        t:eq(P.colourRule, "profession", "in its one faint colour")
        t:ok(P.text, "its text shows")
        t:ok(Q.small and Q.scale == N.ON_NEEDLE_SCALE and Q.alpha == N.ON_NEEDLE_ALPHA, "the quest arrow shrinks over the needle, as today")
    end
    t:ok(N.ArrowLayout(nil, arrowLanes(true, true), nil).professions.anchor == "leader", "no saved table at all: stacked")
end)

ns:Register("test", "arrows (S2): separating gives each a place", function(t)
    local N = ns.nav
    local before = {}
    local s = N.ArrowApply(before, { type = "mode", mode = "separate" }, arrowCtx())
    t:eq(next(before), nil, "the saved table handed in is not changed")
    t:eq(s.arrows.mode, "separate", "the mode is saved")
    t:ok(s.arrows.points.professions ~= nil, "with no place yet, it gets one at once")
    local L = N.ArrowLayout(s, arrowLanes(true, true), arrowCtx())
    local Q, P = L.quest, L.professions
    t:eq(P.anchor, "screen", "the profession arrow stands on its own")
    t:eq(P.look, "pointer", "as a full arrow")
    t:ok(not P.behind, "not behind anything")
    t:eq(P.colourRule, "quest", "with the quest arrow's colour meanings")
    t:eq(P.alpha, N.PROF_HOLDER_ALPHA, "still the fainter one")
    t:eq(P.emphasis, "secondary", "and the second one")
    t:ok(same(P.point, s.arrows.points.professions), "at its saved place")
    t:ok(not Q.small and Q.scale == 1 and Q.alpha == 1, "the quest arrow is back to full size and solid")
    t:ok(same(Q.point, { "TOP", "TOP", 0, -120 }), "and where it was")
    -- Its first place: beside the quest arrow, not on it and not under it.
    t:eq(P.point[4], 1080 - 120 - 56, "level with the quest arrow")
    t:ok(math.abs(P.point[3] - (960 - 28)) >= 56, "clear of it sideways")
    -- By Ctrl-drag: a move of the profession arrow separates.
    local d = separated()
    t:eq(d.arrows.mode, "separate", "dragging it out separates")
    t:ok(same(N.ArrowLayout(d, arrowLanes(true, true), arrowCtx()).professions.point, OWN), "where it was dropped")
end)

ns:Register("test", "arrows (S3): stack again by tick and by drop", function(t)
    local N = ns.nav
    local ctx = arrowCtx()
    -- The quest arrow's centre at the default place on 1920 x 1080.
    local leader = { 960, 1080 - 120 - 28 }
    local s = N.ArrowApply(separated(), { type = "mode", mode = "stacked" }, ctx)
    local P = N.ArrowLayout(s, arrowLanes(true, true), ctx).professions
    t:ok(P.anchor == "leader" and P.look == "needle" and P.behind, "unticked: the needle behind the quest arrow again")
    s = N.ArrowApply(separated(), { type = "drop", key = "professions", point = { "CENTER", "CENTER", 9, 9 }, leader = leader, at = { 970, 940 } }, ctx)
    t:eq(s.arrows.mode, "stacked", "dropped on the quest arrow: stacked")
    t:ok(same(s.arrows.points.professions, OWN), "and its own place is kept, not the drop's")
    s = N.ArrowApply(separated(), { type = "drop", key = "professions", point = { "BOTTOMLEFT", "BOTTOMLEFT", 940, 910 }, leader = leader }, ctx)
    t:eq(s.arrows.mode, "stacked", "the same, its centre worked out from the dropped point")
    local far = { "BOTTOMLEFT", "BOTTOMLEFT", 300, 300 }
    s = N.ArrowApply(separated(), { type = "drop", key = "professions", point = far, leader = leader }, ctx)
    t:eq(s.arrows.mode, "separate", "dropped away from it: still separate")
    t:ok(same(s.arrows.points.professions, far), "at the new place")
    t:eq(N.STACK_SNAP, 40, "the snap distance")
    t:ok(N.StackSnap(0, 39, 40) and N.StackSnap(28, 28, 40) and N.StackSnap(0, 0), "inside 40: stacks")
    t:ok(not N.StackSnap(40, 0, 40), "at 40: does not")
    t:ok(not N.StackSnap(0, 41, 40) and not N.StackSnap(30, 30, 40), "outside 40: does not")
end)

ns:Register("test", "arrows (S4, S5): place and state survive a reload", function(t)
    local N = ns.nav
    local ctx, lanes = arrowCtx(), arrowLanes(true, true)
    -- Separate, move, /reload.
    local s = separated()
    local L = N.ArrowLayout(s, lanes, ctx)
    t:ok(same(N.ArrowLayout(s, lanes, ctx), L), "asked twice: the same layout")
    local back = N.ArrowLayout(reloaded(s), lanes, ctx)
    t:ok(same(back, L), "after a reload: the same layout")
    t:ok(back.professions.anchor == "screen" and same(back.professions.point, OWN), "still separate, at the same place")
    -- Stack, /reload.
    local st = N.ArrowApply(s, { type = "mode", mode = "stacked" }, ctx)
    t:eq(N.ArrowLayout(reloaded(st), lanes, ctx).professions.anchor, "leader", "stacked stays stacked")
    -- Separate with no drag, /reload.
    local nd = N.ArrowApply({}, { type = "mode", mode = "separate" }, ctx)
    t:ok(nd.arrows.points.professions ~= nil, "separated with no drag: its place is in the saved table at once")
    t:ok(same(N.ArrowLayout(reloaded(nd), lanes, ctx), N.ArrowLayout(nd, lanes, ctx)), "and is the same after a reload")
    -- (S5) Stack, then separate again: back at its last own place.
    t:ok(same(st.arrows.points.professions, OWN), "stacking keeps its own place")
    local again = N.ArrowApply(reloaded(st), { type = "mode", mode = "separate" }, ctx)
    t:ok(same(N.ArrowLayout(again, lanes, ctx).professions.point, OWN), "separated again: where it was")
end)

ns:Register("test", "arrows (S6): the stack moves as one", function(t)
    local N = ns.nav
    local ctx, lanes = arrowCtx(), arrowLanes(true, true)
    local to = { "CENTER", "CENTER", -300, 100 }
    local s = N.ArrowApply({}, { type = "move", key = "quest", point = to }, ctx)
    local L = N.ArrowLayout(s, lanes, ctx)
    t:ok(same(L.quest.point, to), "stacked: the quest arrow is at the new place")
    t:ok(L.professions.anchor == "leader" and L.professions.point == nil, "and the profession arrow goes with it, still on it")
    t:ok(s.arrows.mode ~= "separate", "moving the stack does not separate")
    local sep = separated()
    local moved = N.ArrowApply(sep, { type = "move", key = "quest", point = to }, ctx)
    local A, B = N.ArrowLayout(sep, lanes, ctx), N.ArrowLayout(moved, lanes, ctx)
    t:ok(same(B.quest.point, to), "separate: the quest arrow moves")
    t:ok(same(A.professions, B.professions), "and the profession arrow does not")
    t:eq(moved.arrows.mode, "separate", "still separate")
end)

ns:Register("test", "arrows (S7): a control changes one arrow", function(t)
    local N = ns.nav
    local ctx, lanes = arrowCtx(), arrowLanes(true, true)
    local sep = separated()
    local base = N.ArrowLayout(sep, lanes, ctx)
    local function after(action) return N.ArrowLayout(N.ArrowApply(sep, action, ctx), lanes, ctx) end
    local L = after({ type = "hide", key = "professions", on = true })
    t:ok(not L.professions.shown, "hide the profession arrow: it hides")
    t:ok(same(L.quest, base.quest), "the quest arrow is as it was")
    L = after({ type = "text", key = "professions", on = false })
    t:ok(not L.professions.text and L.professions.shown, "its text off: only its text")
    t:ok(same(L.quest, base.quest), "the quest arrow is as it was")
    L = after({ type = "hide", key = "quest", on = true })
    t:ok(not L.quest.shown, "hide the quest arrow: it hides")
    t:ok(same(L.professions, base.professions), "the profession arrow is as it was")
    L = after({ type = "text", key = "quest", on = false })
    t:ok(not L.quest.text and same(L.professions, base.professions), "the quest arrow's text off: only its text")
    -- Stacked: the profession arrow's text switch leaves the quest arrow alone.
    local st = N.ArrowLayout({}, lanes, ctx)
    local st2 = N.ArrowLayout(N.ArrowApply({}, { type = "text", key = "professions", on = false }, ctx), lanes, ctx)
    t:ok(same(st.quest, st2.quest) and not st2.professions.text, "stacked: the same")
    -- The older switch (nav.profArrowText) is read when the new one is unset, and never written.
    t:ok(not N.ArrowLayout({ profArrowText = false }, lanes, ctx).professions.text, "the older text switch, off, is honoured")
    local on = N.ArrowApply({ profArrowText = false }, { type = "text", key = "professions", on = true }, ctx)
    t:ok(N.ArrowLayout(on, lanes, ctx).professions.text, "the new switch wins once set")
    t:eq(on.profArrowText, false, "and the older one is left as it was")
end)

ns:Register("test", "arrows (S8): separating changes no step", function(t)
    local N = ns.nav
    local saved = { point = { "CENTER", "CENTER", 10, 20 }, profArrowText = false, selectedKey = "quest:1", profArrow = true }
    local kept = reloaded(saved)
    local s = N.ArrowApply(saved, { type = "mode", mode = "separate" }, arrowCtx())
    t:ok(same(saved, kept), "the saved table handed in is not changed")
    for k, v in pairs(s) do
        if k ~= "arrows" then t:ok(same(v, kept[k]), "unchanged: " .. tostring(k)) end
    end
    for k in pairs(kept) do t:ok(s[k] ~= nil, "still there: " .. tostring(k)) end
    -- The layout looks at "has a step", never at which step.
    local a = N.ArrowLayout(s, arrowLanes(true, true), arrowCtx())
    local lanes = arrowLanes(true, true)
    lanes[1].goal, lanes[2].goal, lanes[2].selected = { key = "quest:2" }, { key = "prof:9" }, "prof:9"
    local kl = reloaded(lanes)
    t:ok(same(N.ArrowLayout(s, lanes, arrowCtx()), a), "a different step: the same layout")
    t:ok(same(lanes, kl), "and the lanes handed in are not changed")
end)

ns:Register("test", "arrows (S9): hide, switch, unhide", function(t)
    local N = ns.nav
    local ctx, lanes = arrowCtx(), arrowLanes(true, true)
    local s = separated()
    s = N.ArrowApply(s, { type = "mode", mode = "stacked" }, ctx)
    s = N.ArrowApply(s, { type = "hide", key = "professions", on = true }, ctx)
    t:ok(not N.ArrowLayout(s, lanes, ctx).professions.shown, "hidden")
    s = N.ArrowApply(s, { type = "mode", mode = "separate" }, ctx)
    t:ok(not N.ArrowLayout(s, lanes, ctx).professions.shown, "switching the mode does not show it")
    s = N.ArrowApply(s, { type = "hide", key = "professions", on = false }, ctx)
    local P = N.ArrowLayout(s, lanes, ctx).professions
    t:ok(P.shown and P.anchor == "screen" and same(P.point, OWN), "shown again: separate, at its saved place")
    s = N.ArrowApply(s, { type = "hide", key = "professions", on = true }, ctx)
    s = N.ArrowApply(s, { type = "mode", mode = "stacked" }, ctx)
    s = N.ArrowApply(s, { type = "hide", key = "professions", on = false }, ctx)
    P = N.ArrowLayout(s, lanes, ctx).professions
    t:ok(P.shown and P.anchor == "leader" and P.look == "needle", "and the other way: back as the needle")
end)

ns:Register("test", "arrows (S9, S10): a lane off and on, or missing, keeps its keys", function(t)
    local N = ns.nav
    local ctx = arrowCtx()
    local s = separated()
    local kept = reloaded(s)
    local with = N.ArrowLayout(s, arrowLanes(true, true), ctx)
    -- The profession lane off (nav.profArrow), or a character with none.
    local L = N.ArrowLayout(s, arrowLanes(true, nil), ctx)
    t:eq(L.professions, nil, "no profession lane: no profession arrow")
    t:ok(L.quest.shown and not L.quest.small, "one arrow, full size")
    t:ok(same(s, kept), "the other arrow's saved keys are left alone")
    t:ok(same(N.ArrowLayout(s, arrowLanes(true, true), ctx), with), "the lane back on: same mode, same place")
    -- (S10) Account-wide: the same saved table gives the same layout to anyone.
    t:ok(same(N.ArrowLayout(reloaded(s), arrowLanes(true, true), arrowCtx()), with), "a second character: the same layout")
    -- Stacked, one lane.
    L = N.ArrowLayout({}, arrowLanes(true, nil), ctx)
    t:ok(L.quest.shown and not L.quest.small and L.professions == nil, "stacked with no profession lane: the quest arrow alone, full size")
end)

ns:Register("test", "arrows (S11): what shows when the leader does not", function(t)
    local N = ns.nav
    -- The arrow update's early returns, in their order.
    t:eq(N.ArrowGate(false, true, false, true, false), "off", "arrow switched off")
    t:eq(N.ArrowGate(true, false, false, true, false), "off", "not revealed to a new player yet")
    t:eq(N.ArrowGate(true, true, true, true, false), "intro", "the login intro is playing")
    t:eq(N.ArrowGate(true, true, false, false, false), "off", "no player position")
    t:eq(N.ArrowGate(true, true, false, true, true), "corpse", "dead")
    t:eq(N.ArrowGate(true, true, false, true, false), "open", "none of those")
    t:eq(N.ArrowGate(false, true, true, true, true), "off", "off comes before the intro")
    t:eq(N.ArrowGate(true, true, true, false, true), "intro", "the intro before the position and the corpse")
    local both = arrowLanes(true, true)
    local modes = { stacked = {}, separate = separated() }
    for name, saved in pairs(modes) do
        local kept = reloaded(saved)
        local function lay(gate, lanes, s) return N.ArrowLayout(s or saved, lanes or both, arrowCtx(gate)) end
        local open = lay("open")
        local L = lay("off")
        t:ok(not L.quest.shown and not L.professions.shown, name .. ", off: no arrow at all")
        L = lay("intro")
        t:ok(L.quest.shown and not L.professions.shown, name .. ", intro: the quest arrow only")
        L = lay("corpse")
        t:ok(L.quest.shown and not L.professions.shown, name .. ", dead: the quest arrow only (on the corpse)")
        t:ok(same(L.professions.point, open.professions.point) and L.professions.anchor == open.professions.anchor,
            name .. ", dead: the other arrow's place is kept for when you are alive again")
        t:ok(open.quest.shown and open.professions.shown, name .. ", open: both")
        -- The quest lane has no step and no overlay; and the same with the leader hidden by the player.
        local hiddenQuest = N.ArrowApply(saved, { type = "hide", key = "quest", on = true }, arrowCtx())
        for what, l in pairs({ ["no quest step"] = lay("open", arrowLanes(false, true)), ["quest arrow hidden"] = lay("open", both, hiddenQuest) }) do
            local P = l.professions
            t:ok(not l.quest.shown, name .. ", " .. what .. ": the quest arrow hides")
            t:ok(P.shown and P.look == "pointer" and P.anchor == "screen", name .. ", " .. what .. ": the profession arrow stays, a full arrow")
            if name == "stacked" then
                t:ok(same(P.point, { "TOP", "TOP", 0, -120 }), name .. ", " .. what .. ": at the stack's place")
            else
                t:ok(same(P.point, OWN), name .. ", " .. what .. ": at its own place")
            end
        end
        t:eq(hiddenQuest.arrows.mode, saved.arrows and saved.arrows.mode, name .. ": hiding the leader does not change the mode")
        -- An overlay (a waypoint, a party member) with no quest step still shows the leader.
        local over = arrowLanes(false, true)
        over[1].overlay = true
        t:ok(lay("open", over).quest.shown, name .. ", an overlay and no quest step: the quest arrow shows")
        -- The other arrow hidden by the player.
        L = lay("open", both, N.ArrowApply(saved, { type = "hide", key = "professions", on = true }, arrowCtx()))
        t:ok(L.quest.shown and not L.quest.small and not L.professions.shown, name .. ", profession arrow hidden: the quest arrow alone, full size")
        -- No profession step.
        L = lay("open", arrowLanes(true, false))
        t:ok(L.quest.shown and not L.quest.small and not L.professions.shown, name .. ", no profession step: the quest arrow alone, full size")
        t:ok(same(saved, kept), name .. ": none of this wrote to the saved table")
    end
    -- Stacked, standing on the main step's point: the needle is off (N.ProfArrowMode), the quest arrow full size.
    local onPoint = arrowLanes(true, true)
    onPoint[2].mode = N.ProfArrowMode(true, false, true)
    t:ok(not N.ArrowLayout({}, onPoint, arrowCtx()).quest.small, "needle off on the main step's point: the quest arrow is not shrunk")
    t:eq(N.ProfArrowMode(false, false, true), "arrow", "N.ProfArrowMode is as it was")
end)

ns:Register("test", "arrows (S12): clamped to the screen", function(t)
    local N = ns.nav
    local p = N.ClampPoint({ "CENTER", "CENTER", 5000, 0 }, 56, 1920, 1080)
    t:ok(same(p, { "CENTER", "CENTER", 932, 0 }), "off the right edge: back to it")
    p = N.ClampPoint({ "TOPLEFT", "TOPLEFT", -300, 400 }, 56, 1920, 1080)
    t:ok(same(p, { "TOPLEFT", "TOPLEFT", 0, 0 }), "off the top left corner: back to it")
    p = N.ClampPoint({ "BOTTOM", "BOTTOM", 0, -900 }, 56, 1920, 1080)
    t:ok(same(p, { "BOTTOM", "BOTTOM", 0, 0 }), "under the screen: back to the bottom")
    local inside = { "TOP", "TOP", 0, -120 }
    p = N.ClampPoint(inside, 56, 1920, 1080)
    t:ok(same(p, inside) and p ~= inside, "on screen: the same place, a new table")
    t:ok(same(N.ClampPoint(p, 56, 1920, 1080), p), "clamping twice changes nothing more")
    t:eq(N.ClampPoint(nil, 56, 1920, 1080), nil, "no point: none")
    -- A smaller screen than the one it was saved on, through the layout: both arrows.
    local s = N.ArrowApply(separated(), { type = "move", key = "quest", point = { "BOTTOMLEFT", "BOTTOMLEFT", 2400, 1300 } }, arrowCtx())
    s = N.ArrowApply(s, { type = "move", key = "professions", point = { "BOTTOMLEFT", "BOTTOMLEFT", -90, 2000 } }, arrowCtx())
    local kept = reloaded(s)
    local L = N.ArrowLayout(s, arrowLanes(true, true), arrowCtx())
    t:ok(same(L.quest.point, { "BOTTOMLEFT", "BOTTOMLEFT", 1920 - 56, 1080 - 56 }), "the quest arrow comes back on screen")
    t:ok(same(L.professions.point, { "BOTTOMLEFT", "BOTTOMLEFT", 0, 1080 - 56 }), "the separated arrow comes back on screen")
    t:ok(same(s, kept), "the saved places themselves are not rewritten")
    local st = N.ArrowLayout({ point = { "BOTTOMLEFT", "BOTTOMLEFT", 2400, 1300 } }, arrowLanes(true, true), arrowCtx())
    t:ok(same(st.quest.point, { "BOTTOMLEFT", "BOTTOMLEFT", 1920 - 56, 1080 - 56 }) and st.professions.anchor == "leader", "stacked: the stack comes back on screen")
end)

ns:Register("test", "arrows (S12): reset", function(t)
    local N = ns.nav
    local ctx, lanes = arrowCtx(), arrowLanes(true, true)
    local s = separated()
    s = N.ArrowApply(s, { type = "move", key = "quest", point = { "CENTER", "CENTER", -300, 100 } }, ctx)
    s = N.ArrowApply(s, { type = "hide", key = "professions", on = true }, ctx)
    s = N.ArrowApply(s, { type = "hide", key = "quest", on = true }, ctx)
    s = N.ArrowApply(s, { type = "text", key = "professions", on = false }, ctx)
    local r = N.ArrowApply(s, { type = "reset" }, ctx)
    t:eq(r.point, nil, "the stack's place is cleared")
    t:ok(r.arrows.mode == nil and r.arrows.points == nil and r.arrows.hidden == nil, "mode, places and hidden arrows are cleared")
    t:eq(r.arrows.text.professions, false, "the text switches are kept")
    local L = N.ArrowLayout(r, lanes, ctx)
    local fresh = N.ArrowLayout({ arrows = { text = { professions = false } } }, lanes, ctx)
    t:ok(same(L, fresh), "the layout is the default one: stacked, default place, all shown")
    t:ok(L.quest.shown and L.professions.shown and L.professions.anchor == "leader", "stacked and shown")
    t:ok(same(N.ArrowApply({}, { type = "reset" }, ctx), {}), "resetting nothing gives nothing")
end)

ns:Register("test", "arrows (7.3): the first place beside the leader, and the stack's order", function(t)
    local N = ns.nav
    -- At the right edge the new arrow lands on the left; never on top.
    local p = N.ArrowBeside({ "BOTTOMLEFT", "BOTTOMLEFT", 1860, 500 }, 56, 1920, 1080)
    t:ok(p[3] <= 1860 - 56 and p[4] == 500, "leader at the right edge: to its left")
    p = N.ArrowBeside({ "BOTTOMLEFT", "BOTTOMLEFT", 4, 500 }, 56, 1920, 1080)
    t:ok(p[3] >= 4 + 56 and p[4] == 500, "leader at the left edge: to its right")
    p = N.ArrowBeside({ "CENTER", "CENTER", 0, 0 }, 56)
    t:ok(same(p, { "CENTER", "CENTER", 56 + N.ARROW_BESIDE_GAP, 0 }), "no screen size known: to its right, by its own anchor")
    -- More than one arrow stacked: the first by order is the needle, the rest a line of text.
    local lanes = {
        { key = "cooking", order = 5, hasStep = true },
        { key = "quest", order = 1, hasStep = true },
        { key = "professions", order = 2, hasStep = true },
    }
    local L = N.ArrowLayout({}, lanes, arrowCtx())
    t:eq(L.professions.look, "needle", "the first by order is the needle")
    t:eq(L.cooking.look, "text", "the next a line of text")
    t:ok(L.cooking.anchor == "leader" and L.cooking.shown, "still on the stack")
    -- Separate is never hidden by the main step's point: N.ProfArrowMode is for the stack only.
    lanes[3].mode = "off"
    local sep = N.ArrowApply({}, { type = "mode", mode = "separate" }, { screenW = 1920, screenH = 1080, keys = { "professions", "cooking" } })
    L = N.ArrowLayout(sep, lanes, arrowCtx())
    t:ok(L.professions.shown and L.professions.look == "pointer" and L.cooking.look == "pointer", "separate: each a full arrow")
end)
