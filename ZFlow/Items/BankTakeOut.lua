local _, ns = ...

-- BankTakeOut (parity row E-19, the data half): the bank's "Take out" list.
-- Of what the bank held at your last visit, what the sell rules would now
-- sell: the things to take out yourself and sell at the next vendor.
--
-- LOOK ONLY. Nothing here withdraws, deposits, moves, sells, picks up or
-- uses anything, and there is no window, list or button: this is the data
-- a surface asks for. Taking things out stays the player's own clicks.
--
-- Ported from Flow 0.35.377 Modules/Items/Banker.lua:
--   :313-333  B.TakeOutRows: of the bank's items with a count above 0, the
--             ones the sell rules sell, except what you chose to keep in
--             the bank (your rule "bank") and except weapons, armor and
--             quest things (B.NOT_OUT, :257: whether one is soulbound can't
--             be told while it lies in the bank); by name, then by id.
--   :456-488  B:Withdraw and :1048 the "Take out" button moved them. Not
--             ported: Z-Flow moves nothing.
-- "Marked to sell" is Z-Flow's own, not a second version of it: the bank's
-- items are Banker.Items' (Items/Banker.lua, from char "learned.bankCounts",
-- which Items/HaveTip.lua keeps), the sell verdicts are Banker.SellRows'
-- (Disposition.Decide with the bank list's context: your never-sell list,
-- your bank rules, your saved sets, and what your goals hold in the bank).
--
-- E-19 one-source join (lead ruling): this is Flow's whole B.TakeOutRows,
-- the one rule the Take out list, E-21's bank step (Items/BankPutAway.lua),
-- the banker view's bank rows (Items/BankerRows.lua BR.SellRows) and the
-- banker word (Items/Banker.lua) read. As Flow (:321-326), a bank thing a
-- route step wants (e.step) or a quest wants (e.quest) is taken out too,
-- and Z-Flow's own hold (e.hold, a reservation no route stop names; lead
-- section 776) between quest and sell: one row per thing, the first of
-- route, quest, hold, sell, then one sort of all rows by name. NOT_OUT
-- holds back the sell rows only (Flow: a route or quest takes even gear
-- out). Your rule "bank" drops a thing before every branch.
--
-- Left out, and why:
--   the auction half (Flow's action "ah")   Z-Flow's rules sell or keep;
--             none sends a banked thing to the auction house
--   the one-move memory (B.Unmoved, :198)   it undid Flow's own moves
--   the 10 s memo (B.TakeOut)               out of scope (lead ruling)
--
-- Pure parts (plain tables in):
--   rows, unread = BankTakeOut.Rows(items, sells, rules, where)
--     items   Banker.Items': { { key, name, count, quality, classID } },
--             each optionally with step, quest, hold (words: who wants it,
--             as Items/TakeOutWhy.lua Fill sets them); nil: the bank was
--             never seen
--     sells   Banker.SellRows': { { key, name, count, quality, reason,
--             mine } }
--     rules   your bank choices: { [key] = "bank" | "carry" }, or nil
--     where   BankTakeOut.Where's, or nil
--     rows    { { key, id, name, count, quality, reason, slots, take, mine,
--             next } }, by name (an item with no name read: by its key),
--             then by key. take: T.ROUTE | T.QUEST | T.HOLD | T.SELL;
--             reason: the step's words, the quest's title, the hold's
--             reason or the sell reason. next: what a click makes a sell
--             row (BankerRows.NextChoice), nil for the others. mine: your
--             own sell choice. name is nil when it was not read; count is
--             the bank's for a wanted thing, the sell rules' for a sell (nil
--             when they could not say how many); slots only when `where`
--             has it
--   list, why = BankTakeOut.Make(client, store, use, r): the list from the
--     reads (saved bank, sell rules, bank rules, quest log, the route's
--     View, the reservations r), as List() gives it; the banker word calls
--     it with its own reservations evaluation
--     unread  how many sold items nothing else wants were left out because
--             their kind was not
--             read (a weapon can't be told from a pelt then)
--     nil when items or sells is nil: not known is never an empty list.
--   where = BankTakeOut.Where(client)
--     { [key] = { { bag, slot, count }, ... } } from client.bankSlots(),
--     or nil. CLIENT NEED: client.bankSlots() -> rows { bag, slot, item,
--     count } while the bank is open (as client.bagSlots() for the bags).
--     No client has it yet, and the saved bank holds counts only, so today
--     no row has slots.
--
-- Module: BankTakeOut.Declare(k) -> api; api.list().
--   ns.use(BankTakeOut.NAME) -> { List = api.list }
--   List() -> { rows, unread, at }, or nil and one of the reasons below.
--     at: when the bank was last seen (client.clock() then), nil when not
--     kept.
-- Not tested in game.

local T = {}
ns.BankTakeOut = T

T.NAME = "bankTakeOut"
-- Item classes never listed to sell (Flow's B.NOT_OUT): weapon, armor, quest.
T.NOT_OUT = { [2] = true, [4] = true, [12] = true }
-- Why a row is taken out (row.take), in Flow's priority for one thing.
T.ROUTE = "route"
T.QUEST = "quest"
T.HOLD = "hold"
T.SELL = "sell"
-- Why there is no list.
T.NOT_STARTED = "The take out list has not started."
T.NOT_SEEN = "Your bank has not been seen yet. Open it once."
T.RESERVATIONS_UNKNOWN = "What your goals hold is not known, so nothing in your bank is offered for sale."
T.FAILED = "The take out list could not be made this time."

local function whole(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and v == math.floor(v)
end

-- What a row is ordered by: its name, or its key when no name was read.
local function label(row)
    if type(row.name) == "string" then return row.name end
    return tostring(row.key)
end

local function before(a, b)
    local la, lb = label(a), label(b)
    if la ~= lb then return la < lb end
    return tostring(a.key) < tostring(b.key)
end

function T.Where(client)
    if type(client) ~= "table" or type(client.bankSlots) ~= "function" then return nil end
    local ok, slots = pcall(client.bankSlots)
    if not ok or type(slots) ~= "table" then return nil end
    local out = {}
    for _, s in ipairs(slots) do
        local key
        if type(s) == "table" then key = ns.Items.Key(s.item) end
        if key ~= nil and type(s.bag) == "number" and type(s.slot) == "number" then
            local at = { bag = s.bag, slot = s.slot }
            if whole(s.count) then at.count = s.count end
            local list = out[key]
            if not list then
                list = {}
                out[key] = list
            end
            list[#list + 1] = at
        end
    end
    return out
end

local function words(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- What a sell row's click makes it (BankerRows.NextChoice, Flow's
-- B.NextSellChoice): nil when that file is not loaded.
local function nextOfSell()
    local BR = ns.BankerRows
    if type(BR) == "table" and type(BR.NextChoice) == "function" then return BR.NextChoice(nil) end
    return nil
end

-- One row per thing (Flow B.TakeOutRows): the first of route, quest, hold
-- that wants it, else a sell when the sell rules sell it and its kind may
-- leave (NOT_OUT: the sell rows only, as Flow). nil and the unread flag
-- when nothing takes it out.
local function rowOf(e, sold)
    local take, reason = nil, nil
    if words(e.step) then
        take, reason = T.ROUTE, e.step
    elseif words(e.quest) then
        take, reason = T.QUEST, e.quest
    elseif words(e.hold) then
        take, reason = T.HOLD, e.hold
    end
    if take then
        return { key = e.key, id = ns.Items.Id(e.key), name = words(e.name), count = e.count,
                 quality = e.quality, reason = reason, take = take }
    end
    if sold == nil then return nil end
    if e.classID == nil then return nil, true end
    if T.NOT_OUT[e.classID] then return nil end
    local name = words(e.name)
    if name == nil then name = words(sold.name) end
    local quality = e.quality
    if quality == nil then quality = sold.quality end
    local row = { key = e.key, id = ns.Items.Id(e.key), name = name, count = sold.count, quality = quality,
                  reason = sold.reason, take = T.SELL, next = nextOfSell() }
    if sold.mine == true then row.mine = true end
    return row
end

function T.Rows(items, sells, rules, where)
    if type(items) ~= "table" or type(sells) ~= "table" then return nil end
    local sold = {}
    for _, s in ipairs(sells) do
        if type(s) == "table" and s.key ~= nil then sold[s.key] = s end
    end
    local rows, unread, seen = {}, 0, {}
    for _, e in ipairs(items) do
        if type(e) == "table" and e.key ~= nil and not seen[e.key]
            and not (type(rules) == "table" and rules[e.key] == "bank") then
            seen[e.key] = true
            local row, notRead = rowOf(e, sold[e.key])
            if row then
                if type(where) == "table" and where[e.key] ~= nil then row.slots = where[e.key] end
                rows[#rows + 1] = row
            elseif notRead then
                unread = unread + 1
            end
        end
    end
    table.sort(rows, before)
    return rows, unread
end

-- The list from the reads the banker word and List() share: the saved bank
-- (Banker.Items), the sell rules with the bank list's context, your bank
-- rules, and who wants a bank thing (TakeOutWhy.Fill over the quest log,
-- the route's View and the reservations' grants). r: the one reservations
-- evaluation of the caller (BankList.Current). -> list, or nil and why.
function T.Make(client, store, use, r)
    local saved = store:get("char", ns.HaveTip.PATH)
    local items = ns.Banker.Items(saved, client.itemInfo)
    if items == nil then return nil, T.NOT_SEEN end
    local R = ns.Reservations
    -- As the banker word: with the reservations not known nothing in
    -- the bank is offered for sale.
    if type(r) ~= "table" or r.status == R.UNAVAILABLE then return nil, T.RESERVATIONS_UNKNOWN end
    local grants = R.Grants(r)
    local context = ns.BankList.Context(store, R.HeldIn(grants, "bank"))
    local view, route
    if type(use) == "function" then route = use("tripRoute") end
    if type(route) == "table" and type(route.View) == "function" then
        local ok, v = pcall(route.View)
        if ok then view = v end
    end
    local wanted = ns.TakeOutWhy.Fill(items, view, ns.Nav.QuestLogRows(client), grants)
    local rows, unread = T.Rows(wanted, ns.Banker.SellRows(items, context), context.bankRules, T.Where(client))
    if rows == nil then return nil, T.FAILED end
    local list = { rows = rows, unread = unread }
    if type(saved) == "table" and whole(saved.at) then list.at = saved.at end
    return list
end

function T.Declare(k)
    local api = {}
    local ctx

    local function make()
        return T.Make(ctx.client, ctx.store, ctx.use, ns.BankList.Current(ctx.use))
    end

    function api.list()
        if not ctx then return nil, T.NOT_STARTED end
        local ok, list, why = pcall(make)
        if not ok then return nil, T.FAILED end
        return list, why
    end

    k:Module({
        name = T.NAME,
        needs = { "client", "store" },
        provides = { List = api.list },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.bankTakeOut = T.Declare(ns)
