local _, ns = ...
-- P-EVIDENCE+ (lead DISPATCH sections 252, 262 and 355): look-only capture
-- fields collected in normal play, with no player step, saved bounded in
-- the account's diag table for the lead to read after the owner plays.
-- It reads; it never sends, casts, clicks or switches a tracking.
--
-- Saved, account:
--   diag.trackingList = { { at, why, state, count, failed, entries }, ... }
--     the minimap tracking list as client.trackingRaw returns it (per
--     entry: form, kind = the type or category word incl. town kinds,
--     name = the tracking's game name, hasActive, active, hidden,
--     spellId). Read when the add-on starts at login (why "login"),
--     E.LATER seconds after (why "later") and on each
--     MINIMAP_UPDATE_TRACKING (why "event"). Section 252: GK-2/3/4 can be
--     replayed against it.
--   diag.recipeBookAnswers = { { at, after, why, state, rows, headers,
--     expanded, collapsed, unknown, allExpanded, subClass, invSlot }, ... }
--     RB4-2 (section 262): whether the classic recipe list's headers were
--     all expanded (allExpanded true; false when one is collapsed; nil
--     when one says neither) and the two filter reads' answers, as
--     client.tradeSkillAnswers returns them. Read on TRADE_SKILL_SHOW (why
--     "show") and TRADE_SKILL_LIST_UPDATE (why "update"); after = seconds
--     since the window opened.
-- Every record (section 6451): at = seconds since the add-on started at
-- login, one decimal; state = "answered", "empty" (the read is there and
-- gave nothing yet) or "absent" (no such read), so an early empty answer
-- is not taken for a limit. The newest E.KEPT records of each are kept.
-- Game words and numbers only: no player, realm, guild or item-owner name.
-- diag.bossLoot.gaps is UI/BossLoot.lua's (it knows the kill time).
--
-- Not tested in game. First guesses: the events MINIMAP_UPDATE_TRACKING,
-- TRADE_SKILL_SHOW and TRADE_SKILL_LIST_UPDATE, and the reads in
-- Core/Client.lua (trackingRaw, tradeSkillAnswers).

local E = {}
ns.AutoEvidence = E

E.NAME = "autoEvidence"
E.TRACKING = "diag.trackingList"
E.RECIPES = "diag.recipeBookAnswers"
E.KEPT = 20
E.LATER = 5          -- seconds after login for the second tracking read
E.EVENTS = { "MINIMAP_UPDATE_TRACKING", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }

local function tenth(n) return math.floor(n * 10 + 0.5) / 10 end

-- One tracking read made a record (pure).
function E.TrackingRecord(r, at, why)
    local rec = { at = at, why = why }
    if type(r) ~= "table" then
        rec.state = "absent"
        return rec
    end
    rec.count = type(r.count) == "number" and r.count or nil
    rec.failed = type(r.failed) == "number" and r.failed > 0 and r.failed or nil
    rec.entries = {}
    for i, e in ipairs(type(r.entries) == "table" and r.entries or {}) do
        if type(e) == "table" then
            rec.entries[i] = {
                form = type(e.form) == "string" and e.form or nil,
                kind = type(e.kind) == "string" and e.kind or nil,
                name = type(e.name) == "string" and e.name or nil,
                hasActive = e.hasActive == true,
                hidden = e.hidden == true or nil,
                spellId = type(e.spellId) == "number" and e.spellId or nil,
            }
            -- Set apart: `x and v or nil` would turn false into nil.
            if type(e.active) == "boolean" then rec.entries[i].active = e.active end
        end
    end
    rec.state = (#rec.entries > 0) and "answered" or "empty"
    return rec
end

-- One profession window read made a record (pure).
function E.RecipeRecord(r, at, after, why)
    local rec = { at = at, after = after, why = why }
    if type(r) ~= "table" then
        rec.state = "absent"
        return rec
    end
    local function count(v) return type(v) == "number" and v or nil end
    rec.rows, rec.headers, rec.expanded = count(r.rows), count(r.headers), count(r.expanded)
    rec.collapsed, rec.unknown = count(r.collapsed), count(r.unknown)
    rec.subClass = type(r.subClass) == "string" and r.subClass or nil
    rec.invSlot = type(r.invSlot) == "string" and r.invSlot or nil
    if (rec.collapsed or 0) > 0 then
        rec.allExpanded = false
    elseif rec.unknown == 0 and rec.collapsed == 0 then
        rec.allExpanded = true
    end
    if r.open == true and (rec.rows or 0) > 0 then rec.state = "answered" else rec.state = "empty" end
    return rec
end

function E.Declare(k)
    local api = {}
    local ctx, startedAt, shownAt, laterDone
    local cancels = {}

    local function now()
        local ok, t = pcall(ctx.client.uptime)
        if ok and type(t) == "number" and t == t then return t end
        return nil
    end

    local function since(from)
        local t = now()
        if t == nil or from == nil then return nil end
        return tenth(t - from)
    end

    local function keep(path, rec)
        local saved = ctx.store:get("account", path)
        local list = type(saved) == "table" and saved or {}
        list[#list + 1] = rec
        while #list > E.KEPT do table.remove(list, 1) end
        local ok, why = ctx.store:set("account", path, list)
        if not ok then k.problems:add(E.NAME, "save", tostring(why)) end
    end

    local function read(name)
        local fn = ctx.client[name]
        if type(fn) ~= "function" then return nil end
        local ok, r = pcall(fn)
        if not ok then return nil end
        return r
    end

    local function tracking(why)
        keep(E.TRACKING, E.TrackingRecord(read("trackingRaw"), since(startedAt), why))
    end

    local function recipes(why)
        keep(E.RECIPES, E.RecipeRecord(read("tradeSkillAnswers"), since(startedAt), since(shownAt), why))
    end

    k:Module({
        name = E.NAME,
        needs = { "client", "store" },
        provides = {},
        start = function(c)
            ctx = c
            local client = c.client
            startedAt, shownAt, laterDone = now(), nil, false
            local function on(event, fn)
                cancels[#cancels + 1] = client.listen(event, function(...)
                    local ok, err = pcall(fn, ...)
                    if not ok then k.problems:add(E.NAME, event, tostring(err)) end
                end)
            end
            on("MINIMAP_UPDATE_TRACKING", function() tracking("event") end)
            on("TRADE_SKILL_SHOW", function()
                shownAt = now()
                recipes("show")
            end)
            on("TRADE_SKILL_LIST_UPDATE", function() recipes("update") end)
            if type(client.onFrame) == "function" then
                cancels[#cancels + 1] = client.onFrame(function()
                    if laterDone then return end
                    local s = since(startedAt)
                    if s == nil or s < E.LATER then return end
                    laterDone = true
                    local ok, err = pcall(tracking, "later")
                    if not ok then k.problems:add(E.NAME, "later", tostring(err)) end
                end)
            end
            local ok, err = pcall(tracking, "login")
            if not ok then k.problems:add(E.NAME, "login", tostring(err)) end
        end,
        stop = function()
            for _, cancel in ipairs(cancels) do pcall(cancel) end
            cancels = {}
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.autoEvidence = E.Declare(ns)
