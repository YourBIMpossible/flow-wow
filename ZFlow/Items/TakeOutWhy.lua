local _, ns = ...

-- Lead section 774.2: who wants a thing in your bank, for the banker's
-- take-out rows (Items/BankerRows.lua: e.quest, e.step). As Flow's
-- Banker.lua B.TakeOut callbacks:
--   quest(id)  QuestBags.lua QG.NeededHere (:419-428): a quest in your log
--              still needing it (here: an objective "<item>: n/m" not done,
--              in a quest not ready to hand in)
--   route(id)  B.RouteFetch / B.FetchBy (:228-241): a step on your route
--              that uses it, by its words; "a step on your route" when not
--              known (here: the route step whose quest still needs it, from
--              TripRoute View; else what the reservations hold in the bank
--              for a step, Reservations.HeldIn(grants, "bank"))
-- Only existing reads (owner section 611): the quest log's rows
-- (Nav.QuestLogRows), TripRoute's View, the reservations' holds. Pure; look
-- only. The caller is the banker window's (a MUSE NEED for the drawing).
--   TakeOutWhy.QuestFor(name, rows) -> quest title | nil
--   TakeOutWhy.StepFor(name, key, view, rows, held) -> words | nil
--   TakeOutWhy.Fill(bank, view, rows, held) -> copies of bank's entries
--     with step and quest set where something wants them
-- Not tested in game.
local TW = {}
ns.TakeOutWhy = TW

TW.ON_ROUTE = "a step on your route"

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

function TW.StepFor(name, key, view, rows, held)
    local r = wanting(name, rows)
    if r and type(view) == "table" and type(view.stops) == "table" then
        for _, s in ipairs(view.stops) do
            if type(s) == "table" and s.quest == r.id and type(s.label) == "string" and s.label ~= "" then
                return s.label
            end
        end
    end
    if type(held) == "table" and type(held.Held) == "function" and key ~= nil then
        local ok, n = pcall(held.Held, held, key)
        if ok and type(n) == "number" and n > 0 then return TW.ON_ROUTE end
    end
    return nil
end

function TW.Fill(bank, view, rows, held)
    local out = {}
    if type(bank) ~= "table" then return out end
    for i, e in ipairs(bank) do
        local c = {}
        if type(e) == "table" then
            for k, v in pairs(e) do c[k] = v end
            c.step = TW.StepFor(e.name, e.key, view, rows, held)
            c.quest = TW.QuestFor(e.name, rows)
        end
        out[i] = c
    end
    return out
end
