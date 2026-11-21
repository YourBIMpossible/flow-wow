-------------------------------------------------------------------------------
-- Flow - Quests/QuestBags.lua
-- Quest items in your bags: what clears each one (0.35.344).
--
-- "20 items in my bags are quest items, I can't carry anything. Do a deep
-- dive on what needs to happen with my quest items, and build it into Flow so
-- it guides me to do the right things to clear them."
--
-- The deep dive (a level 21 druid, 54 of 54 slots used, 19 of them quest
-- things):
--   * 11 slots were held by quests that were already finished. Three of those
--     hand-ins were on the route; two (4 slots, both in Ratchet) were not:
--     the planner looks at the 30 nearest steps, and with 130 quests to pick
--     up nearer by, a finished quest's hand-in further off never made the cut.
--   * 4 slots were for quests whose next step is on another continent: they
--     can't be cleared here, and a bank holds quest items as well as any.
--   * 3 slots were leftovers no quest in the log asks for: one to sell (its
--     quest is 39 levels away), two that wait for a quest not yet picked up.
--   * The rest belong to quests in progress here: finishing them clears them.
--
-- So every quest thing in your bags gets one of five answers:
--   turnin   its quest is finished: hand it in (the route now always carries
--            such a hand-in, pulled forward and marked "frees N bag slots"
--            while your bags are nearly full)
--   bank     its quest's next step is on another continent, or it waits for a
--            quest you don't have: Flow Banker puts it away, and lists it
--            under "To sell" (Take out) when a quest here needs it again
--   sell     a leftover a vendor buys
--   finish   its quest is in progress here: what's left to do
--   stuck    its quest has no step Flow can place: your quest log says how
--
-- /flow questbags lists them (also in the diagnostics); Flow Improvements
-- carries the first thing to do while your bags are nearly full.
-------------------------------------------------------------------------------

local _, ns = ...
local QG = {}
ns.questBags = QG

-- "Nearly full": ns.BagsNearlyFull (Core.lua), shared with the merchant and bank steps.
QG.ORDER = { "turnin", "sell", "bank", "finish", "stuck" }
QG.HEAD = {
    turnin = "Hand in (finished)",
    sell = "Sell (no quest of yours uses it)",
    bank = "Bank (nothing to do with it here)",
    finish = "Finish (in progress here)",
    stuck = "Flow can't place it (your quest log says how)",
}

-------------------------------------------------------------------------------
-- Pure parts
-------------------------------------------------------------------------------

-- The quest in your log an item is for: a finished one first (its hand-in
-- frees the slot). quests: { { id, title, complete, items = { [itemID] = true } } }
function QG.QuestOf(itemId, quests)
    local found
    for _, q in ipairs(quests or {}) do
        if q.items and q.items[itemId] then
            if not found or (q.complete and not found.complete) then found = q end
        end
    end
    return found
end

-- Is a quest's next step on another continent? steps: that quest's steps,
-- { { key, deps = { key }, conts = { [continent] = true } } }; cont: yours.
-- A step that waits for another of the quest's steps isn't the next one.
function QG.Away(steps, cont)
    local keys = {}
    for _, g in ipairs(steps or {}) do keys[g.key] = true end
    local any, here, other = false, false, nil
    for _, g in ipairs(steps or {}) do
        local waits = false
        for _, dep in ipairs(g.deps or {}) do if keys[dep] then waits = true end end
        if not waits then
            for c in pairs(g.conts or {}) do
                any = true
                if c == cont then here = true else other = other or c end
            end
        end
    end
    -- (and which continent it goes on on)
    return any and not here, (any and not here) and other or nil
end

-- Pure: a quest's steps without the ones that only fetch a thing you already
-- own (0.35.351). Put "Spells of Shadow" in the bank and the game calls its
-- quest unfinished again: a step "collect Spells of Shadow", here, comes
-- back, the quest looks like one to do here, and Flow asked for the book back
-- out. In your bags it was finished and handed in across the sea, so to the
-- bank it went again. A thing in your bank is a thing you have.
--   steps: { { key, item = itemID or nil, ... } }; held(itemID) -> bool
function QG.Unheld(steps, held)
    local out = {}
    for _, g in ipairs(steps or {}) do
        if not (g.item and held and held(g.item)) then out[#out + 1] = g end
    end
    return out
end

-- Pure: the things Flow has parked in the bank for a quest across the sea,
-- kept up to date (0.35.351). Once a thing is parked it stays "waiting",
-- wherever it lies and whatever the quest log says about it meanwhile, until
-- one of two things is true: you're on the continent its quest goes on on, or
-- the quest has left your log. Nothing else brings it back out.
--   parked: { [itemID] = { quest = id, title, cont } } (changed in place)
--   quests, states: as QG.Sets; awayCont: { [questID] = continent }; cont: yours (nil: not known)
function QG.Park(parked, quests, states, awayCont, cont)
    local inLog = {}
    for _, q in ipairs(quests or {}) do inLog[q.id] = q end
    for id, p in pairs(parked) do
        if not inLog[p.quest] or (cont ~= nil and p.cont == cont) then parked[id] = nil end
    end
    for _, q in ipairs(quests or {}) do
        local to = awayCont and awayCont[q.id]
        if states and states[q.id] == "away" and to ~= nil and to ~= cont then
            for id in pairs(q.items or {}) do parked[id] = { quest = q.id, title = q.title, cont = to } end
        end
    end
    return parked
end

-- Is a row of the inventory a quest thing? (The game's Quest kind, or
-- anything a quest in your log asks for: Earthroot for Gathering the Cure.)
function QG.IsQuestThing(row, quests)
    if type(row) ~= "table" or not row.id then return false end
    if type(row.kind) == "string" and row.kind:find("^Quest") then return true end
    return QG.QuestOf(row.id, quests) ~= nil
end

-- The plan. rows: D.Inventory's ({ id, name, count, stacks, kind, action,
-- reason }); quests: as above; where(questId) -> "away" | "stuck" | nil, and
-- who it's handed in to.
--   -> { slots = n, turnin = { entry }, sell = ..., bank = ..., finish = ..., stuck = ... }
--   entry = { title, slots, items = { "5 x Kodo Horn" }, ids = { itemID }, quest = id, who, why }
function QG.Plan(rows, quests, where)
    local plan = { slots = 0 }
    for _, k in ipairs(QG.ORDER) do plan[k] = {} end
    local groups, order = {}, {}
    for _, r in ipairs(rows or {}) do
        if QG.IsQuestThing(r, quests) then
            local slots = r.stacks or 1
            plan.slots = plan.slots + slots
            local label = string.format("%d x %s", r.count or 1, tostring(r.name))
            local q = QG.QuestOf(r.id, quests)
            if q then
                local g = groups[q.id]
                if not g then
                    g = { title = q.title, slots = 0, items = {}, ids = {}, quest = q.id, complete = q.complete }
                    groups[q.id] = g
                    order[#order + 1] = g
                end
                g.slots = g.slots + slots
                g.items[#g.items + 1] = label
                g.ids[#g.ids + 1] = r.id
            else
                local e = { title = tostring(r.name), slots = slots, items = { label }, ids = { r.id }, why = r.reason }
                table.insert(r.action == "sell" and plan.sell or plan.bank, e)
            end
        end
    end
    for _, g in ipairs(order) do
        local state, who = nil, nil
        if where then state, who = where(g.quest) end
        g.who = who
        if state == "away" then
            g.why = "its next step is on another continent"
            table.insert(plan.bank, g)
        elseif g.complete then table.insert(plan.turnin, g)
        elseif state == "stuck" then table.insert(plan.stuck, g)
        else table.insert(plan.finish, g) end
    end
    for _, k in ipairs(QG.ORDER) do
        table.sort(plan[k], function(a, b)
            if a.slots ~= b.slots then return a.slots > b.slots end
            return tostring(a.title) < tostring(b.title)
        end)
    end
    return plan
end

-- Pure: how many slots a list of entries holds.
function QG.Slots(list)
    local n = 0
    for _, e in ipairs(list or {}) do n = n + (e.slots or 0) end
    return n
end

-- Pure: the report's lines.
function QG.Lines(plan, free, total)
    local out = { string.format("Quest items hold %d of your %s bag slots (%s free).", plan.slots or 0, tostring(total or "?"), tostring(free or "?")) }
    for _, k in ipairs(QG.ORDER) do
        local list = plan[k] or {}
        if #list > 0 then
            out[#out + 1] = string.format("  %s: %d slot(s)", QG.HEAD[k], QG.Slots(list))
            for _, e in ipairs(list) do
                out[#out + 1] = string.format("    %d: %s%s (%s)%s", e.slots, tostring(e.title), e.who and (", to " .. e.who) or "",
                    table.concat(e.items, ", "), (e.why and not e.quest) and (": " .. e.why) or "")
            end
        end
    end
    return out
end

-- Pure: up to `max` titles of a list, "A (3), B (2) and 2 more".
function QG.Names(list, max)
    local parts = {}
    for i = 1, math.min(max or 3, #list) do parts[#parts + 1] = string.format("%s (%d)", tostring(list[i].title), list[i].slots or 0) end
    local more = #list - #parts
    return table.concat(parts, ", ") .. (more > 0 and string.format(" and %d more", more) or "")
end

-- Pure: what Flow Improvements says: nothing with room to spare.
function QG.Advice(plan, free)
    local out = {}
    if not ns.BagsNearlyFull(free) or (plan.slots or 0) == 0 then return out end
    local tight = free <= 1 and 90 or 80
    -- (Full bags lose loot: red. Nearly full: yellow.)
    local urgency = free <= 1 and "now" or "soon"
    if #plan.turnin > 0 then
        out[#out + 1] = { importance = tight, improves = { "Bag space" }, urgency = urgency,
            text = string.format("Bags nearly full: hand in %d finished quest(s) to free %d slot(s): %s",
                #plan.turnin, QG.Slots(plan.turnin), QG.Names(plan.turnin, 3)) }
    end
    if #plan.bank > 0 then
        out[#out + 1] = { importance = tight - 5, improves = { "Bag space" }, urgency = urgency,
            text = string.format("Bags nearly full: %d slot(s) of quest items have no use here. Flow Banker puts them away: %s",
                QG.Slots(plan.bank), QG.Names(plan.bank, 3)) }
    end
    if #plan.sell > 0 then
        out[#out + 1] = { importance = tight - 10, improves = { "Bag space" }, urgency = urgency,
            text = string.format("Bags nearly full: sell %d leftover quest item(s) no quest of yours uses: %s", #plan.sell, QG.Names(plan.sell, 3)) }
    end
    return out
end

-- Pure: a finished quest's hand-in that frees slots: says so, and with
-- nearly full bags it always makes the route's cut and is pulled forward.
function QG.MarkStep(goal, slots, free)
    if not goal or (slots or 0) <= 0 then return false end
    goal.frees = slots
    goal.details = goal.details or {}
    goal.details[#goal.details + 1] = string.format("Handing it in frees %d bag slot(s) of its quest items.", slots)
    if ns.BagsNearlyFull(free) then
        goal.keep = true   -- (Planner.lua: never cut as "too far")
        goal.weight = math.min(goal.weight or 1, 0.5)
        goal.text = (goal.text or "") .. string.format(" (frees %d bag slot%s)", slots, slots == 1 and "" or "s")
        goal.details[#goal.details + 1] = "Your bags are nearly full, so it comes early on your route."
    end
    return true
end

-------------------------------------------------------------------------------
-- Your log, your bags, your route
-------------------------------------------------------------------------------

-- Your log's quests and the items each asks for (a few seconds old at most).
local questsAt, questsNow = -100, {}
function QG.Quests()
    local now = GetTime()
    if now - questsAt < 3 then return questsNow end
    local Q, L, out = ns.quests, ns.leftovers, {}
    if Q and Q.LogIds and Q.QuestieGet and L and L.AddQuest then
        for id in pairs(Q:LogIds() or {}) do
            local raw = Q:QuestieGet("GetQuest", id)
            local complete = false
            if C_QuestLog and C_QuestLog.IsComplete then
                local ok, c = pcall(C_QuestLog.IsComplete, id)
                complete = ok and ns.rotation.Yes(c, false) or false
            end
            out[#out + 1] = { id = id, title = raw and raw.name or ("quest " .. id), complete = complete, items = L.AddQuest({}, raw) }
        end
        table.sort(out, function(a, b) return a.id < b.id end)
    end
    questsAt, questsNow = now, out
    return out
end

-- Bag slots each quest's items hold: { [questID] = slots }.
local slotsAt, slotsNow = -100, {}
function QG.SlotsByQuest()
    local now = GetTime()
    if now - slotsAt < 3 then return slotsNow end
    local out, quests, D = {}, QG.Quests(), ns.disposition
    if D and D.EachBagItem then
        D:EachBagItem(function(_, _, link)
            local id = tonumber(link:match("item:(%d+)"))
            local q = id and QG.QuestOf(id, quests)
            if q then out[q.id] = (out[q.id] or 0) + 1 end
        end)
    end
    slotsAt, slotsNow = now, out
    return out
end
ns:On("BAG_UPDATE_DELAYED", function() slotsAt = -100 end)

local function free() return ns.export and ns.export.BagsFree and ns.export.BagsFree() or nil end

-- A finished quest's hand-in, as the route's quest steps are made (Goals.lua).
function QG.MarkTurnIn(goal, questId)
    return QG.MarkStep(goal, QG.SlotsByQuest()[questId] or 0, free())
end

-- Where each quest stands on your route: its steps by quest ID.
local function stepsByQuest()
    local N, by = ns.nav, {}
    if not (N and N.Goals) then return by end
    for _, list in ipairs({ N:Goals() or {}, N.blockedGoals or {}, N.hiddenGoals or {} }) do
        for _, g in ipairs(list) do
            local qid = type(g.key) == "string" and tonumber(g.key:match("^(%d+):"))
            if qid then
                local conts = {}
                for _, pt in ipairs(g.points or {}) do
                    local cont = pt.cont
                    if cont == nil and pt.map and N.ToWorld then
                        local ok, c = pcall(N.ToWorld, N, pt.map, pt.x, pt.y)
                        cont = ok and c or nil
                    end
                    if cont ~= nil then conts[cont] = true end
                end
                by[qid] = by[qid] or {}
                table.insert(by[qid], { key = g.key, deps = g.deps, conts = conts, placed = next(conts) ~= nil, item = g.item,
                                        who = g.key:find(":done$") and g.npcs and g.npcs[1] or nil })
            end
        end
    end
    return by
end

-- Everything, as it stands now: the plan, free slots, slots in all, and the
-- items whose quest is on another continent ({ [itemID] = quest title }).
local nowAt, nowIs = -100, nil
function QG.Now(fresh)
    local t = GetTime()
    if not fresh and nowIs and t - nowAt < 3 then return nowIs end
    local D = ns.disposition
    local rows, total = {}, nil
    if D and D.Inventory then
        local ok, r, _, tot = pcall(D.Inventory, D)
        if ok then rows, total = r, tot end
    end
    local quests = QG.Quests()
    local by = stepsByQuest()
    -- (A step that fetches a thing lying in your bank isn't a step: QG.Unheld.)
    local bank = ns.db.bank and ns.db.bank.items or {}
    for qid, steps in pairs(by) do by[qid] = QG.Unheld(steps, function(id) return (bank[id] or 0) > 0 end) end
    local p = ns.nav and ns.nav.PlayerPos and ns.nav:PlayerPos()
    local cont = p and p.cont
    QG.lastCont = cont ~= nil and cont or QG.lastCont
    local awayCont = {}
    local function where(qid)
        local steps = by[qid]
        local who
        for _, s in ipairs(steps or {}) do who = who or s.who end
        if not steps or #steps == 0 then return "stuck", nil end
        -- (Where you are isn't known, in a loading screen or some buildings:
        -- then Flow moves nothing for this quest either way.)
        if cont == nil then return "stuck", who end
        local away, to = QG.Away(steps, cont)
        if away then awayCont[qid] = to return "away", who end
        local placed = false
        for _, s in ipairs(steps) do placed = placed or s.placed end
        return (not placed) and "stuck" or nil, who
    end
    local plan = QG.Plan(rows, quests, where)
    -- Where each quest of your log stands, whatever is in your bags (0.35.348:
    -- it was worked out from the bags, so a thing put in the bank for a quest
    -- across the sea stopped counting as "waiting" the moment it left them,
    -- was offered back out, and then banked again).
    local states = {}
    for _, q in ipairs(quests) do states[q.id] = where(q.id) or "here" end
    local waits, needs = QG.Sets(quests, states)
    -- What's parked for a quest across the sea stays parked (QG.Park).
    if ns.db.banker then
        ns.db.banker.parked = ns.db.banker.parked or {}
        for id, pk in pairs(QG.Park(ns.db.banker.parked, quests, states, awayCont, cont)) do
            waits[id], needs[id] = pk.title, nil
        end
    end
    nowAt, nowIs = t, { plan = plan, free = free(), total = total, waits = waits, needs = needs, quests = quests, states = states }
    return nowIs
end

-- Pure: from your log's quests and where each stands ("here" | "away" |
-- "stuck"):
--   waits = { [itemID] = title }  its quest goes on across the sea: to the bank
--   needs = { [itemID] = title }  a quest Flow can lead you through here uses
--                                 it: it stays with you, and comes out of the bank
-- A thing a quest here needs never waits. A quest Flow can't place ("stuck")
-- is neither: Flow doesn't know enough to move its things either way.
function QG.Sets(quests, states)
    local waits, needs = {}, {}
    for _, q in ipairs(quests or {}) do
        local s = states and states[q.id]
        for id in pairs(q.items or {}) do
            if s == "here" then needs[id] = needs[id] or q.title
            elseif s == "away" then waits[id] = waits[id] or q.title end
        end
    end
    for id in pairs(needs) do waits[id] = nil end
    return waits, needs
end

-- What quests Flow can lead you through here use: { [itemID] = quest title }.
function QG.Needs()
    local ok, now = pcall(QG.Now)
    return ok and now and now.needs or {}
end

-- Items whose quest's next step is on another continent: Flow Banker puts
-- them away. { [itemID] = quest title }
function QG.Waits()
    local ok, now = pcall(QG.Now)
    return ok and now and now.waits or {}
end

-- Something in your bank a quest of yours can use here: its title, or nil.
function QG.NeededHere(itemId)
    local ok, now = pcall(QG.Now)
    if not (ok and now) then return nil end
    local title = now.needs[itemId]
    if not title then return nil end
    -- (A finished quest you still carry its items for has what it needs.)
    local q = QG.QuestOf(itemId, now.quests)
    if q and q.complete and ns.api.Count and (ns.api.Count(itemId) or 0) > 0 then return nil end
    return title
end

ns:PerCharacter("banker.parked")

-- Pure: does the bank hold what's still to get? count: in the bank; need,
-- have: the objective's (nil: one is enough).
function QG.Banked(count, need, have)
    if (count or 0) <= 0 then return false end
    if not need then return true end
    return count + (have or 0) >= need
end
-- Is this item in your bank, as Flow last saw it (enough of it for an objective)?
function QG.InBank(itemId, need, have)
    local items = ns.db and ns.db.bank and ns.db.bank.items
    return QG.Banked(items and itemId and items[itemId] or 0, need, have)
end

ns:Register("advisor", "questBags", {
    check = function()
        local now = QG.Now()
        return QG.Advice(now.plan, now.free)
    end,
})

ns.commands.questbags = function()
    local ok, now = pcall(QG.Now, true)
    if not ok then ns:Print("quest items: " .. tostring(now)) return end
    for i, l in ipairs(QG.Lines(now.plan, now.free, now.total)) do if i == 1 then ns:Print(l) else print(l) end end
end
ns:Register("help", "questbags", { order = 59, title = "Quest items in your bags", lines = {
    "/flow questbags: every quest thing in your bags and what clears it: hand in (finished), sell, bank (nothing to do with it here), finish, or see your quest log.",
    "With nearly full bags, a finished quest's hand-in always stays on your route, comes early and says how many slots it frees. Flow Banker puts away what waits for another continent or another quest, and offers it back (To sell, Take out) when a quest here needs it.",
} })
