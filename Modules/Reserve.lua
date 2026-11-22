-- The reservation ledger, first part: money and bag slots (P2 activity
-- contract, PR 7).
--
-- Several things want the same copper and the same bag room: class training,
-- a profession tier, a recipe to buy, a quest's items. This file answers, for
-- one moment in time, "who gets how much" in one fixed order, so two parts of
-- Flow can't both count the same gold.
--
-- It only computes. Nothing here buys, sells, mails, trades, moves or deletes
-- anything, and nothing reads it yet: no caller, so the player sees no change.
-- Items (bags, bank, quest item claims, one stock for every profession) come
-- later, on top of this; a claim for anything but money or slots is skipped.
--
--   raw      = R.ReadClient()          the only function that asks the game
--   snapshot = R.Snapshot(raw)         pure: { money, slots = { general, all } }
--   grants   = R.Resolve(snapshot, claims, defs)       pure
--
--   R.Begin(raw) / R.Finish(steps, defs): one refresh. Begin fixes the
--   snapshot (money and free slots are read once, there, never per claim);
--   Finish resolves what the finished steps ask for against it.
--
-- A claim:
--   { activity = "professions", step = "train:Mining", res = "money", n = 5000,
--     milestone = true,     -- money only: class training goes first
--     required = false,     -- an optional upgrade; anything else counts as required
--     priority = 1,         -- overrides the activity's (lower goes first)
--     unknown = true,       -- the amount isn't known (n is then ignored)
--     estimate = 4500 }     -- shown as "about", never counted
--   { activity = "professions", step = "buy:2320", res = "slots", n = 1 }
--
-- A grant: { claim = claim, got = n, short = n, before = n }
--   got     what the claim holds. Money is all or nothing (a step is paid for
--           in full or waits, as N.CommitCosts does it); slots are granted as
--           far as they go.
--   short   what's missing. Not a failure: the claimant plans for it.
--   before  what the claims ahead of this one hold.
--   unknown "price" (the claim's amount isn't known), "money" or "slots" (the
--           game couldn't be read). got and short are then nil: Flow doesn't
--           know, so it says neither "you can pay" nor "you can't" (F-085).
--           An unknown claim holds nothing and delays no one behind it.
--   invalid true for an amount that isn't a count (negative, not a number).
--           It holds nothing either.
--
-- The order, for money and for slots alike (P2 design 2.4):
--   1. the step the player picked in its activity (defs.selected)
--   2. money: milestones first; then required before optional
--   3. priority: the claim's own, else its activity's (defs.priority), lower first
--   4. money: the cheaper first
--   5. the step key, then the activity, the amount, and last the place in the
--      list (so equal claims keep their order and nothing depends on `pairs`).

local _, ns = ...

local R = {}
ns.reserve = R

-------------------------------------------------------------------------------
-- The game, read in one place.
-------------------------------------------------------------------------------

-- What the game says right now, untouched:
--   { money = copper or nil, bags = { { bag, free, family } ... } or nil }
-- money is nil when it can't be read, bags is nil when there's no bag API (not
-- 0 and not 99: unknown). family is the second value of the free-slot call
-- (0 = a bag for anything), nil when the game doesn't give one.
function R.ReadClient()
    local raw = {}
    if GetMoney then
        local ok, copper = pcall(GetMoney)
        if ok and type(copper) == "number" then raw.money = copper end
    end
    local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if get then
        raw.bags = {}
        for bag = 0, 4 do
            local ok, free, family = pcall(get, bag)
            if ok and type(free) == "number" then
                raw.bags[#raw.bags + 1] = { bag = bag, free = free, family = type(family) == "number" and family or nil }
            end
        end
    end
    return raw
end

-------------------------------------------------------------------------------
-- Pure from here on.
-------------------------------------------------------------------------------

-- A count: a number that is not negative, not NaN and not endless.
local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

-- Pure: free slots by kind of bag.
--   all      every bag, whatever it holds (what X.BagsFree and the Flow key's
--            freeSlots count)
--   general  bags that take anything: family 0, or no family given (what the
--            merchant step's freeBagSlots counts). A herb bag or a quiver
--            holds only its own things, so a claim can't count on it.
--   special  all - general
--   familiesKnown  false when a bag came without a family: `general` then
--            counts that bag too, and may be too high.
-- nil when the bags couldn't be read.
function R.FreeSlots(bags)
    if type(bags) ~= "table" then return nil end
    local slots = { general = 0, all = 0, special = 0, familiesKnown = true }
    for i = 1, #bags do
        local b = bags[i]
        local free = type(b) == "table" and isCount(b.free) and b.free or 0
        slots.all = slots.all + free
        if type(b) == "table" and b.family == nil then slots.familiesKnown = false end
        if type(b) == "table" and (b.family or 0) == 0 then slots.general = slots.general + free end
    end
    slots.special = slots.all - slots.general
    return slots
end

-- Pure: what R.ReadClient returned -> the snapshot the resolver works on.
-- money and slots are nil when unknown.
function R.Snapshot(raw)
    raw = type(raw) == "table" and raw or {}
    return {
        money = isCount(raw.money) and raw.money or nil,
        slots = R.FreeSlots(raw.bags),
    }
end

local RESOURCES = { "money", "slots" }

-- The claim's amount -> n, or nil and why ("price" unknown, or "invalid").
local function amount(claim)
    if claim.unknown or claim.n == nil then return nil, "price" end
    if not isCount(claim.n) then return nil, "invalid" end
    return claim.n
end

-- Pure: claims in, grants out (the list in the order they were resolved, money
-- then slots), plus:
--   grants.committed = { money = n, slots = n }   what was granted
--   grants.left      = { money = n, slots = n }   what's free (nil: unknown)
--   grants.unknown   = how many grants are unknown
--   grants.skipped   = claims for something this ledger doesn't hold yet
-- defs = { selected = { [activity] = step key }, priority = { [activity] = n } }
-- Neither the snapshot nor a claim is changed.
function R.Resolve(snapshot, claims, defs)
    snapshot = type(snapshot) == "table" and snapshot or {}
    defs = type(defs) == "table" and defs or {}
    local selected = type(defs.selected) == "table" and defs.selected or {}
    local priority = type(defs.priority) == "table" and defs.priority or {}
    local pool = {
        money = isCount(snapshot.money) and snapshot.money or nil,
        slots = type(snapshot.slots) == "table" and isCount(snapshot.slots.general) and snapshot.slots.general or nil,
    }
    local grants = { committed = {}, left = {}, unknown = 0, skipped = 0 }
    local byRes = { money = {}, slots = {} }
    for i = 1, #(claims or {}) do
        local c = claims[i]
        local list = type(c) == "table" and byRes[c.res]
        if list then
            local n, why = amount(c)
            local pri = c.priority
            if type(pri) ~= "number" then pri = priority[c.activity] end
            list[#list + 1] = {
                claim = c, i = i, n = n, why = why,
                sel = (c.step ~= nil and selected[c.activity] == c.step) and 1 or 0,
                mil = (c.res == "money" and c.milestone) and 1 or 0,
                req = (c.required == false) and 0 or 1,
                pri = type(pri) == "number" and pri == pri and pri or math.huge,
                step = tostring(c.step), act = tostring(c.activity),
            }
        else
            grants.skipped = grants.skipped + 1
        end
    end
    for _, res in ipairs(RESOURCES) do
        local list, money = byRes[res], res == "money"
        table.sort(list, function(a, b)
            if a.sel ~= b.sel then return a.sel > b.sel end
            if a.mil ~= b.mil then return a.mil > b.mil end
            if a.req ~= b.req then return a.req > b.req end
            if a.pri ~= b.pri then return a.pri < b.pri end
            local na, nb = a.n or math.huge, b.n or math.huge
            if money and na ~= nb then return na < nb end
            if a.step ~= b.step then return a.step < b.step end
            if a.act ~= b.act then return a.act < b.act end
            if na ~= nb then return na < nb end
            return a.i < b.i
        end)
        local have, total = pool[res], 0
        for _, e in ipairs(list) do
            local g = { claim = e.claim, before = total }
            if e.why == "invalid" then
                g.invalid, g.got, g.short = true, 0, 0
            elseif e.why then
                g.unknown, g.estimate = e.why, e.claim.estimate
            elseif not have then
                g.unknown = res
            elseif money then
                if total + e.n <= have then g.got, g.short = e.n, 0
                else g.got, g.short = 0, e.n end
            else
                g.got = math.min(e.n, have - total)
                g.short = e.n - g.got
            end
            total = total + (g.got or 0)
            if g.unknown then grants.unknown = grants.unknown + 1 end
            grants[#grants + 1] = g
        end
        grants.committed[res] = total
        grants.left[res] = have and (have - total) or nil
    end
    return grants
end

-- Pure: what a list of finished route steps asks for.
--   goal.cost (copper)   -> a money claim, as N.CommitCosts reads it: not for a
--                           step already held (blockedBy), not for 0 or less
--   goal.costUnknown     -> a money claim with no amount ("price unknown: check
--                           the trainer"); goal.costEstimate rides along
--   goal.claims          -> the step says it exactly; a money claim in there
--                           replaces the reading of goal.cost
-- The claim's activity is the step's lane (goal.activity), else its owner.
function R.ClaimsOf(list)
    local claims = {}
    for _, g in ipairs(list or {}) do
        if type(g) == "table" and not g.blockedBy then
            local activity, saysMoney = g.activity or g.owner, false
            if type(g.claims) == "table" then
                for i = 1, #g.claims do
                    local c = g.claims[i]
                    if type(c) == "table" then
                        local copy = {}
                        for k, v in pairs(c) do copy[k] = v end
                        if copy.activity == nil then copy.activity = activity end
                        if copy.step == nil then copy.step = g.key end
                        if copy.res == "money" then saysMoney = true end
                        claims[#claims + 1] = copy
                    end
                end
            end
            if not saysMoney then
                if type(g.cost) == "number" and g.cost > 0 then
                    claims[#claims + 1] = { activity = activity, step = g.key, res = "money", n = g.cost,
                                            milestone = g.milestone and true or nil }
                elseif g.costUnknown and g.cost == nil then
                    claims[#claims + 1] = { activity = activity, step = g.key, res = "money", unknown = true,
                                            estimate = g.costEstimate, milestone = g.milestone and true or nil }
                end
            end
        end
    end
    return claims
end

-------------------------------------------------------------------------------
-- One refresh: Begin, then Finish. Never saved: it's a function of the bags,
-- the money and the steps.
-------------------------------------------------------------------------------

-- Fixes the snapshot for this refresh. raw: what R.ReadClient gave (tests pass
-- their own); without it the game is read, once, here.
function R.Begin(raw)
    R.snapshot = R.Snapshot(raw or R.ReadClient())
    R.grants = nil
    return R.snapshot
end

-- Resolves the steps' claims against the snapshot Begin took. Without a Begin
-- nothing is known (it doesn't read the game by itself).
function R.Finish(list, defs)
    R.grants = R.Resolve(R.snapshot or R.Snapshot(nil), R.ClaimsOf(list), defs)
    return R.grants
end

-- What the last finished ledger granted of "money" or "slots"; nil before one.
function R.Committed(res)
    return R.grants and R.grants.committed[res] or nil
end
