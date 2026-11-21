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
