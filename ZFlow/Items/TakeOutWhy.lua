local _, ns = ...

-- Lead section 774.2: who wants a thing in your bank, for the banker's
-- take-out rows (Items/BankerRows.lua: e.quest, e.step). As Flow's
-- Banker.lua B.TakeOut callbacks:
--   quest(id)  QuestBags.lua QG.NeededHere (:419-428): a quest in your log
--              still needing it (here: an objective "<item>: n/m" not done,
--              in a quest not ready to hand in)
--   route(id)  B.RouteFetch / B.FetchBy (:228-241): a step on your route
--              that uses it, by its words (here: the route step whose quest
--              still needs it, from TripRoute View; only a stop that names
--              it counts, lead section 776)
--   hold       a thing the reservations hold in the bank that no route stop
--              names: the reservation's own reason, from its claim's
--              activity (Items/Resources.lua; Items/Goals.lua "goal")
-- Only existing reads (owner section 611): the quest log's rows
-- (Nav.QuestLogRows), TripRoute's View, the reservations' holds. Pure; look
-- only. The caller is the banker window's (a MUSE NEED for the drawing).
--   TakeOutWhy.QuestFor(name, rows) -> quest title | nil
--   TakeOutWhy.StepFor(name, key, view, rows) -> words | nil
--   TakeOutWhy.HoldFor(key, grants) -> reason, n | nil   grants: the
--     reservations' (Reservations.Grants(r)); held in the bank only; n: how
--     many that claim keeps in the bank (E-19 join CHANGES-2)
--   TakeOutWhy.Fill(bank, view, rows[, grants]) -> copies of bank's entries
--     with step, quest and hold set where something wants them, and
--     holdCount with hold
-- Not tested in game.
local TW = {}
ns.TakeOutWhy = TW

-- A reservation's own reason, by its claim's activity.
TW.REASONS = { goal = "for one of your item goals" }
TW.HELD_FOR = "held for %s"
-- A claim that names no activity: a plain word, never its internal owner key.
TW.SOMETHING = "something you planned"

local function itemOf(text)
    local Q = ns.QuestBags
    if type(Q) == "table" and type(Q.ObjectiveItem) == "function" then return Q.ObjectiveItem(text) end
    return nil
end

-- The quest of rows that still needs the item name, or nil.
local function wanting(name, rows)
    if type(name) ~= "string" or name == "" or type(rows) ~= "table" then return nil end
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.complete ~= true and r.failed ~= true and type(r.objectives) == "table" then
            for _, o in ipairs(r.objectives) do
                if type(o) == "table" and o.done ~= true and itemOf(o.text) == name then return r end
            end
        end
    end
    return nil
end

function TW.QuestFor(name, rows)
    local r = wanting(name, rows)
    if r and type(r.title) == "string" and r.title ~= "" then return r.title end
    return nil
end

function TW.StepFor(name, _, view, rows)
    local r = wanting(name, rows)
    if r and type(view) == "table" and type(view.stops) == "table" then
        for _, s in ipairs(view.stops) do
            if type(s) == "table" and s.quest == r.id and type(s.label) == "string" and s.label ~= "" then
                return s.label
            end
        end
    end
    return nil
end

-- The reason of the first claim that holds some of key in the bank, worded
-- by its activity, and how many every claim on key holds there, summed as
-- Reservations.HeldIn sums them (from.bank, plus an unseen bank's share;
-- E-19 join CHANGES-3).
local function reasonOf(c)
    local act = c.activity
    if type(act) == "string" and TW.REASONS[act] then return TW.REASONS[act] end
    if type(act) == "string" and act ~= "" then return TW.HELD_FOR:format(act) end
    return TW.HELD_FOR:format(TW.SOMETHING)
end

function TW.HoldFor(key, grants)
    if key == nil or type(grants) ~= "table" then return nil end
    local reason, total = nil, 0
    for _, g in ipairs(grants) do
        local c = nil
        if type(g) == "table" then c = g.claim end
        if type(c) == "table" and not g.invalid and c.kind == "item" and c.key == key then
            local n = 0
            if type(g.from) == "table" and type(g.from.bank) == "number" then n = g.from.bank end
            if g.unknown == "bank" and type(c.amount) == "number" then
                n = n + math.max(0, c.amount - (tonumber(g.got) or 0))
            end
            if n > 0 then
                if reason == nil then reason = reasonOf(c) end
                total = total + n
            end
        end
    end
    if reason == nil then return nil end
    return reason, total
end

function TW.Fill(bank, view, rows, grants)
    local out = {}
    if type(bank) ~= "table" then return out end
    for i, e in ipairs(bank) do
        local c = {}
        if type(e) == "table" then
            for k, v in pairs(e) do c[k] = v end
            c.step = TW.StepFor(e.name, e.key, view, rows)
            c.quest = TW.QuestFor(e.name, rows)
            c.hold, c.holdCount = TW.HoldFor(e.key, grants)
        end
        out[i] = c
    end
    return out
end
