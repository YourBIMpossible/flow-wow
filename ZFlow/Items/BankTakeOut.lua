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
-- Left out, and why:
--   the auction half (Flow's action "ah")   Z-Flow's rules sell or keep;
--             none sends a banked thing to the auction house
--   the quest and route rows (:321-324)     not "marked to sell"; what a
--             goal of yours holds in the bank is kept by the sell rules
--   the one-move memory (B.Unmoved, :198)   it undid Flow's own moves
--
-- Pure parts (plain tables in):
--   rows, unread = BankTakeOut.Rows(items, sells, rules, where)
--     items   Banker.Items': { { key, name, count, quality, classID } };
--             nil: the bank was never seen
--     sells   Banker.SellRows': { { key, name, count, quality, reason } }
--     rules   your bank choices: { [key] = "bank" | "carry" }, or nil
--     where   BankTakeOut.Where's, or nil
--     rows    { { key, id, name, count, quality, reason, slots } }, by name
--             (an item with no name read: by its key), then by key.
--             name is nil when it was not read; count is nil when the
--             rules could not say how many; slots only when `where` has it
--     unread  how many sold items were left out because their kind was not
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
-- Item classes never listed (Flow's B.NOT_OUT): weapon, armor, quest.
T.NOT_OUT = { [2] = true, [4] = true, [12] = true }
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

function T.Rows(items, sells, rules, where)
    if type(items) ~= "table" or type(sells) ~= "table" then return nil end
    local classOf = {}
    for _, e in ipairs(items) do
        if type(e) == "table" and e.key ~= nil then classOf[e.key] = e.classID end
    end
    local rows, unread = {}, 0
    for _, s in ipairs(sells) do
        if type(s) == "table" and s.key ~= nil and not (type(rules) == "table" and rules[s.key] == "bank") then
            local classID = classOf[s.key]
            if classID == nil then
                unread = unread + 1
            elseif not T.NOT_OUT[classID] then
                local row = { key = s.key, id = ns.Items.Id(s.key), name = s.name, count = s.count,
                              quality = s.quality, reason = s.reason }
                if type(where) == "table" and where[s.key] ~= nil then row.slots = where[s.key] end
                rows[#rows + 1] = row
            end
        end
    end
    table.sort(rows, before)
    return rows, unread
end

function T.Declare(k)
    local api = {}
    local ctx

    local function make()
        local client, store = ctx.client, ctx.store
        local saved = store:get("char", ns.HaveTip.PATH)
        local items = ns.Banker.Items(saved, client.itemInfo)
        if items == nil then return nil, T.NOT_SEEN end
        local R = ns.Reservations
        local r = ns.BankList.Current(ctx.use)
        -- As the banker word: with the reservations not known nothing in
        -- the bank is offered for sale.
        if r.status == R.UNAVAILABLE then return nil, T.RESERVATIONS_UNKNOWN end
        local context = ns.BankList.Context(store, R.HeldIn(R.Grants(r), "bank"))
        local rows, unread = T.Rows(items, ns.Banker.SellRows(items, context), context.bankRules, T.Where(client))
        if rows == nil then return nil, T.FAILED end
        local list = { rows = rows, unread = unread }
        if whole(saved.at) then list.at = saved.at end
        return list
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
