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
