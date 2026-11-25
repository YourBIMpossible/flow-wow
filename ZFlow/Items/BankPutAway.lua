local _, ns = ...

-- BankPutAway (parity row E-21, the data half): the route step "put N
-- stacks away at the bank", returned for the route to take. Nothing here
-- wires it into the route or the arrow (Nav/TripRoute.lua is untouched).
--
-- LOOK ONLY. Nothing here deposits, withdraws, moves, sells, picks up or
-- uses anything: it reads the bags, the bank list's rules, the take out
-- list and the saved places, and gives a step. Banking stays the player's.
--
-- Ported from Flow 0.35.377 Modules/Items/Banker.lua:
--   :37        B.MIN_STACKS = 4
--   :94-98     B.Stacks: the rows' stacks summed (a row with none counted
--              as 1 there; here it is not known and not counted)
--   :1190-1193 B.WorthAStop: stacks >= MIN_STACKS, or any when the bags
--              are nearly full (Core.lua:103-106, 3 free slots or fewer)
--   :1196-1200 B.StepText: three forms (put away / take out / both)
--   :1203-1231 the "banker" navGoal: at most every 5 s, never while the
--              bank is open, the take out count added to the stacks for
--              "worth it", optional, weight 1
--   :1206      ns.db.banker.off: Flow's off switch, imported to account
--              "settings.banker.off" (Import/FromFlow.lua); read here
-- The list is Z-Flow's own (BankList.Pick: Items/Bank.lua's rules with the
-- reservations), the take out count BankTakeOut's (E-19), the free slots
-- QuestBags.Free's, the banker Nav.Nearest's (one this character used).
--
-- Pure parts:
--   n, unknown = P.Stacks(rows)            rows' stacks; unknown: rows with none
--   items = P.Count(rows, bagStacks)       rows with stacks (slots) added
--   yes = P.Worth(stacks, out, nearlyFull, min)
--   text = P.Text(stacks, out)
--   step, why = P.Of(input)
--     input { stacks, items, out, nearlyFull, near, partial, unread }
--
-- Module: P.Declare(k) -> api; api.step().
--   ns.use(P.NAME) -> { Step = api.step }
--   Step() -> step, or nil and why.
--   step = { kind = "bank", label, text, words, stacks, out, items, place,
--            radius, yards, name, why, optional = true, weight, partial,
--            unread }
-- Not tested in game.

local P = {}
ns.BankPutAway = P

P.NAME = "bankPutAway"
P.KIND = "bank"
P.SERVICE = "banker"
P.TAKE_OUT = "bankTakeOut"
P.MIN_STACKS = 4
P.NEARLY_FULL = 3       -- as QuestBags.NEARLY_FULL and Flow's BAGS_NEARLY_FULL
P.WEIGHT = 1
P.KEEP = 5
P.RADIUS = 10
P.OFF_PATH = "settings.banker.off"
P.LABEL = "Bank"
-- Words under the step.
P.WHAT = "Things kept for later that nothing on your route uses now. At the bank, the Bank list shows them."
P.TAKE_WHAT = "And things in your bank the sell rules would sell now: take them out and sell them at a vendor."
-- Why there is no step, or no place.
P.NOT_STARTED = "The bank step has not started."
P.OFF = "The bank step is off (your Flow banker setting)."
P.AT_BANK = "The bank window is open."
P.BAGS_UNREAD = "Your bags could not be read."
P.RESERVATIONS_UNKNOWN = "What your goals hold is not known, so no bank step is offered."
P.NOT_WORTH = "Not enough to put away for a bank step."
P.FAILED = "The bank step could not be worked out this time."
P.NO_BANK = "No banker you have used is known yet. Visit one once."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function whole(v)
    return finite(v) and v >= 0 and v == math.floor(v)
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function plural(n, one, many)
    if n == 1 then return one end
    return many
end

function P.Stacks(rows)
    local n, unknown = 0, 0
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if type(r) == "table" and whole(r.stacks) then
            n = n + r.stacks
        else
            unknown = unknown + 1
        end
    end
    return n, unknown
end

-- The bag slots holding each row's item. A row whose count is all the bags
-- have of it goes slot by slot: its stacks are the slots. A part of it (a
-- step holds the rest) or bags not read: not known.
function P.Count(rows, bagStacks)
    local slots, total = {}, {}
    local read = type(bagStacks) == "table"
    if read then
        for _, s in ipairs(bagStacks) do
            local key
            if type(s) == "table" then key = ns.Items.Key(s.item) end
            if key ~= nil then
                slots[key] = (slots[key] or 0) + 1
                if total[key] ~= false and whole(s.count) then
                    total[key] = (total[key] or 0) + s.count
                else
                    total[key] = false
                end
            end
        end
    end
    local items = {}
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if type(r) == "table" then
            local item = { key = r.key, id = r.key, name = r.name, count = r.count, quality = r.quality,
                           reason = r.reason }
            if read and slots[r.key] then
                if r.count == nil or (whole(r.count) and r.count == total[r.key]) then
                    item.stacks = slots[r.key]
                end
            end
            items[#items + 1] = item
        end
    end
    table.sort(items, function(a, b)
        local sa, sb = a.stacks or -1, b.stacks or -1
        if sa ~= sb then return sa > sb end
        return tostring(a.name or a.key) < tostring(b.name or b.key)
    end)
    return items
end

-- Flow's WorthAStop on stacks + out: from MIN_STACKS, or any when the bags
-- are nearly full. out nil (not known) adds nothing.
function P.Worth(stacks, out, nearlyFull, min)
    local n = (whole(stacks) and stacks or 0) + (whole(out) and out or 0)
    if n >= (whole(min) and min or P.MIN_STACKS) then return true end
    return n > 0 and nearlyFull == true
end

function P.Text(stacks, out)
    local s = whole(stacks) and stacks or 0
    local o = whole(out) and out or 0
    if o <= 0 then
        return string.format("Bank: put %d %s away", s, plural(s, "stack", "stacks"))
    end
    if s <= 0 then
        return string.format("Bank: take %d %s out to sell", o, plural(o, "thing", "things"))
    end
    return string.format("Bank: put %d %s away, take %d %s out to sell",
        s, plural(s, "stack", "stacks"), o, plural(o, "thing", "things"))
end

local function labelMax()
    local N = ns.Nav
    return N and N.Waypoint and N.Waypoint.LABEL_MAX or 40
end

function P.Of(input)
    if type(input) ~= "table" then return nil, P.NOT_WORTH end
    local stacks = whole(input.stacks) and input.stacks or 0
    local out = whole(input.out) and input.out or nil
    if not P.Worth(stacks, out, input.nearlyFull) then return nil, P.NOT_WORTH end
    local text = P.Text(stacks, out)
    local label = P.LABEL
    if #text <= labelMax() then label = text end
    local words = { text, P.WHAT }
    if out and out > 0 then words[#words + 1] = P.TAKE_WHAT end
    local step = {
        kind = P.KIND, label = label, text = text, words = words,
        stacks = stacks, out = out,
        items = type(input.items) == "table" and input.items or {},
        radius = P.RADIUS, optional = true, weight = P.WEIGHT,
        partial = whole(input.partial) and input.partial > 0 and input.partial or nil,
        unread = whole(input.unread) and input.unread > 0 and input.unread or nil,
    }
    local near = input.near
    if type(near) == "table" and near.kind == P.SERVICE and near.map ~= nil and share(near.x) and share(near.y) then
        step.place = { cont = near.cont, map = near.map, x = near.x, y = near.y }
        if finite(near.yards) and near.yards >= 0 then step.yards = near.yards end
        if type(near.name) == "string" and near.name ~= "" then step.name = near.name end
    else
        step.why = P.NO_BANK
        words[#words + 1] = P.NO_BANK
    end
    return step
end

function P.Declare(k)
    local api = {}
    local ctx
    local kept, keptWhy, keptAt

    local function now()
        local client = ctx.client
        if type(client.uptime) ~= "function" then return nil end
        local ok, t = pcall(client.uptime)
        if ok and finite(t) then return t end
        return nil
    end

    -- The take out count: nil when not known (no list, no bank seen, raised).
    local function outCount()
        local ok, mod = pcall(ctx.use, P.TAKE_OUT)
        if not ok or type(mod) ~= "table" or type(mod.List) ~= "function" then return nil end
        local fine, list = pcall(mod.List)
        if not fine or type(list) ~= "table" or type(list.rows) ~= "table" then return nil end
        return #list.rows
    end

    local function make()
        local client, store = ctx.client, ctx.store
        local L, R = ns.BankList, ns.Reservations
        local r = L.Current(ctx.use)
        if r.status == R.UNAVAILABLE then return nil, P.RESERVATIONS_UNKNOWN end
        local pick = L.Pick(client, store, L.Held(r))
        if not pick.ok then return nil, P.BAGS_UNREAD end
        local items = P.Count(pick.rows, client.bagItems())
        local stacks, partial = P.Stacks(items)
        local free = ns.QuestBags.Free(client.bags())
        return P.Of({
            stacks = stacks, items = items, partial = partial, unread = pick.unread,
            out = outCount(),
            nearlyFull = free ~= nil and free <= P.NEARLY_FULL,
            near = ns.Nav.Nearest(P.SERVICE, client, store),
        })
    end

    function api.step()
        if not ctx then return nil, P.NOT_STARTED end
        local okOff, off = pcall(ctx.store.get, ctx.store, "account", P.OFF_PATH)
        if okOff and off == true then return nil, P.OFF end
        local client = ctx.client
        if type(client.bankOpen) == "function" then
            local okB, open = pcall(client.bankOpen)
            if okB and open == true then return nil, P.AT_BANK end
        end
        local t = now()
        if t and keptAt and t >= keptAt and t - keptAt < P.KEEP then return kept, keptWhy end
        local ok, step, why = pcall(make)
        if not ok then
            kept, keptWhy, keptAt = nil, nil, nil
            return nil, P.FAILED
        end
        kept, keptWhy, keptAt = step, why, t
        return step, why
    end

    k:Module({
        name = P.NAME,
        needs = { "client", "store" },
        provides = { Step = api.step },
        start = function(c) ctx = c end,
        stop = function()
            ctx = nil
            kept, keptWhy, keptAt = nil, nil, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.bankPutAway = P.Declare(ns)
