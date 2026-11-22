local _, ns = ...

-- Resources: who gets how much of what the player has, for one moment in time.
--
-- Several things want the same copper, the same bag room and the same items:
-- class training, a profession tier, a recipe to buy, a quest's items, a craft.
-- This file answers "who holds how much" in one fixed order, so two parts of
-- Z-Flow can never both count the same gold or the same stack.
--
-- It only computes. Nothing here reads the game, buys, sells, mails, trades,
-- moves or deletes anything. What it needs from the game arrives as an
-- argument: a snapshot, a plain table.
--
--   snapshot = Resources.Fake(t)                    a snapshot for tests
--   ok, why  = Resources.CheckClaim(claim)          is this claim well formed?
--   grants   = Resources.Resolve(snapshot, claims)  pure
--   grants:For(owner), grants:Held(key), grants:Free(key)
--
-- A snapshot (unknown is never 0 here: a field that wasn't read is nil or the
-- word "unknown"):
--   { money = copper or nil,
--     bags = { [itemKey] = count } or nil,       nil: the bags weren't read
--     bank = { [itemKey] = count } or nil,
--     bankKnown = true / false,                  false: the bank hasn't been seen
--     bankSeenAt = time or nil,
--     slots = { [family] = { free = n, total = n } or "unknown",
--               unknown = { free = n, total = n } }   or nil (bags not read)
--     takenAt = time }
--   slots[0] is the bags that take anything. slots[32] is a bag for one kind
--   of thing (the game's family number). slots.unknown is room in bags whose
--   family the game didn't say: it is counted for no one.
--
-- A claim:
--   { owner = "train:Mining",     who asks (a step key, a module name); needed
--     activity = "professions",   the activity it belongs to
--     kind = "money",             "money", "slots" or "item"; needed
--     key = 2318,                 item: the item's key; slots: the bag family
--                                 (nil = 0, the bags that take anything)
--     amount = 5000,              a count. nil: not known ("price unknown")
--     required = false,           false: optional. Anything else is required
--     selected = true,            the player picked this step
--     priority = 1,               lower goes first; nil goes last
--     bank = true,                item: may also be taken from the bank
--     estimate = 4500 }           optional: carried to the grant for the text
--                                 ("about 45s"), never counted
--
-- A grant: { claim = claim, got = n, short = n, before = n }
--   got     what the claim holds. Money is all or nothing (a step is paid for
--           in full or it waits); slots and items are granted as far as they go.
--   short   what's missing. Not a failure: the claimant plans for it.
--   before  what the claims ahead of this one hold of the same thing.
--   from    item: { bags = n, bank = n }; slots: { [family] = n }.
--   unknown why Z-Flow can't say: "price" (a money claim with no amount),
--           "amount" (a slot or item claim with none), "money", "bags", "bank"
--           or "slots" (that part of the snapshot is unknown).
--           short is then nil: Z-Flow says neither "you have enough" nor "you
--           don't". got is nil when nothing at all was known, else what the
--           known part gives. A claim with no amount holds nothing and delays
--           no one behind it.
--   invalid true, with `problem`, for a claim CheckClaim refuses. It holds
--           nothing.
--
-- The order. Two passes over every kind:
--   pass 1  required claims
--   pass 2  optional claims (required == false); they only ever see what
--           pass 1 left
-- and inside a pass:
--   1. a claim the player picked (selected)
--   2. priority, lower first; none goes last
--   3. money: the cheaper first
--   4. the owner, then the activity, the amount, and last the place in the
--      list (so equal claims keep their order and nothing depends on `pairs`).

local Resources = {}
ns.Resources = Resources

Resources.UNKNOWN = "unknown"
Resources.MONEY = "money"
-- The priority a producer gives a claim that must be paid before anything else
-- of its pass (class training).
Resources.MILESTONE = 0

local KINDS = { money = true, slots = true, item = true }

-- A count: a number that is not negative, not NaN and not endless.
local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end
Resources.IsCount = isCount

-- The key grants:Held and grants:Free use for a bag family's slots.
function Resources.SlotKey(family)
    return "slots:" .. tostring(family == nil and 0 or family)
end

-------------------------------------------------------------------------------
-- Snapshots
-------------------------------------------------------------------------------

local function copyCounts(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(t) do
        if isCount(v) then out[k] = v end
    end
    return out
end

local function copySlots(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for family, v in pairs(t) do
        if type(v) == "table" then
            if isCount(v.free) then
                out[family] = { free = v.free, total = isCount(v.total) and v.total or v.free }
            else
                out[family] = Resources.UNKNOWN
            end
        elseif v == Resources.UNKNOWN then
            out[family] = Resources.UNKNOWN
        end
    end
    return out
end

-- Pure: free room by bag family, from what the game said about each bag.
--   bags = { { free = n, total = n, family = n or nil }, ... }
-- A bag that came without a family goes under `unknown`: its room exists, but
-- Z-Flow can't say what fits in it, so no claim is given it. A bag whose free
-- count isn't a count is left out. nil when the bags couldn't be read.
function Resources.Slots(bags)
    if type(bags) ~= "table" then return nil end
    local slots = {}
    for i = 1, #bags do
        local b = bags[i]
        if type(b) == "table" and isCount(b.free) then
            local family = b.family
            if type(family) ~= "number" then family = "unknown" end
            local e = slots[family]
            if not e then
                e = { free = 0, total = 0 }
                slots[family] = e
            end
            e.free = e.free + b.free
            e.total = e.total + (isCount(b.total) and b.total or b.free)
        end
    end
    return slots
end

-- Pure: free slots in every bag, whatever it holds; nil when any part of it
-- is unknown or the bags weren't read.
function Resources.SlotsAll(slots)
    if type(slots) ~= "table" then return nil end
    local n = 0
    for _, v in pairs(slots) do
        if type(v) ~= "table" or not isCount(v.free) then return nil end
        n = n + v.free
    end
    return n
end

-- A snapshot for tests: a copy of what `t` gives, and nothing made up. What
-- `t` leaves out stays unknown. The bank counts as seen when `t` has one
-- (unless t.bankKnown says otherwise). Changing `t` afterwards does not change
-- the snapshot.
function Resources.Fake(t)
    t = type(t) == "table" and t or {}
    local known = t.bankKnown
    if known == nil then known = type(t.bank) == "table" end
    return {
        money = isCount(t.money) and t.money or nil,
        bags = copyCounts(t.bags),
        bank = copyCounts(t.bank),
        bankKnown = known and true or false,
        bankSeenAt = type(t.bankSeenAt) == "number" and t.bankSeenAt or nil,
        slots = copySlots(t.slots),
        takenAt = type(t.takenAt) == "number" and t.takenAt or 0,
    }
end

-------------------------------------------------------------------------------
-- Claims
-------------------------------------------------------------------------------

-- Is this claim well formed? -> true, or false and what's wrong with it.
-- An amount of nil is fine: it means "not known".
function Resources.CheckClaim(claim)
    if type(claim) ~= "table" then return false, "a claim is a table" end
    if claim.owner == nil then return false, "no owner" end
    if type(claim.owner) ~= "string" and type(claim.owner) ~= "number" then return false, "the owner is not a name" end
    if not KINDS[claim.kind] then return false, "kind is not money, slots or item" end
    if claim.kind == "item" and claim.key == nil then return false, "an item claim needs a key" end
    if claim.kind == "item" and type(claim.key) ~= "string" and type(claim.key) ~= "number" then
        return false, "the item key is not a name or a number"
    end
    if claim.kind == "slots" and claim.key ~= nil and type(claim.key) ~= "number" then
        return false, "the bag family is not a number"
    end
    if claim.amount ~= nil and not isCount(claim.amount) then return false, "the amount is not a count" end
    if claim.priority ~= nil and not (type(claim.priority) == "number" and claim.priority == claim.priority) then
        return false, "the priority is not a number"
    end
    if claim.estimate ~= nil and not isCount(claim.estimate) then return false, "the estimate is not a count" end
    return true
end

-- Pure: what a list of steps asks for, for producers that plan in steps.
--   step = { key, activity, owner (the activity when it has no lane yet),
--            cost = copper, costUnknown = true, costEstimate = copper,
--            milestone = true, priority = n, held = "why it waits",
--            claims = { claims of its own } }
--   cost         -> a money claim; not for a step that waits (held), not for
--                   0 or less
--   costUnknown  -> a money claim with no amount; costEstimate rides along
--   claims       -> the step says it exactly; a money claim in there replaces
--                   the reading of cost. A copy is made: the step's own table
--                   is never written to.
-- The claim's owner is the step's key; its activity is the step's.
function Resources.ClaimsOf(steps)
    local claims = {}
    for _, s in ipairs(steps or {}) do
        if type(s) == "table" and not s.held then
            local activity, saysMoney = s.activity or s.owner, false
            local priority = s.priority
            if priority == nil and s.milestone then priority = Resources.MILESTONE end
            if type(s.claims) == "table" then
                for i = 1, #s.claims do
                    local c = s.claims[i]
                    if type(c) == "table" then
                        local copy = {}
                        for k, v in pairs(c) do copy[k] = v end
                        if copy.activity == nil then copy.activity = activity end
                        if copy.owner == nil then copy.owner = s.key end
                        if copy.kind == "money" then saysMoney = true end
                        claims[#claims + 1] = copy
                    end
                end
            end
            if not saysMoney then
                if type(s.cost) == "number" and s.cost > 0 then
                    claims[#claims + 1] = { owner = s.key, activity = activity, kind = "money", amount = s.cost,
                                            priority = priority }
                elseif s.costUnknown and s.cost == nil then
                    claims[#claims + 1] = { owner = s.key, activity = activity, kind = "money",
                                            estimate = s.costEstimate, priority = priority }
                end
            end
        end
    end
    return claims
end

-------------------------------------------------------------------------------
-- Resolving
-------------------------------------------------------------------------------

local grantsMeta = {}
grantsMeta.__index = grantsMeta

-- Every grant of one owner, in the order they were resolved.
function grantsMeta:For(owner)
    local out = {}
    for i = 1, #self do
        local c = self[i].claim
        if type(c) == "table" and c.owner == owner then out[#out + 1] = self[i] end
    end
    return out
end

-- How much of `key` is held by all claims together. key: Resources.MONEY, a
-- Resources.SlotKey(family), or an item key. 0 when nothing holds any.
function grantsMeta:Held(key)
    return self.held[key] or 0
end

-- How much of `key` is still free; nil when Z-Flow doesn't know (that part of
-- the snapshot wasn't read). For an item: bags, plus the bank when it has
-- been seen.
function grantsMeta:Free(key)
    return self.free(key)
end

local function before(a, b)
    if a.sel ~= b.sel then return a.sel > b.sel end
    if a.pri ~= b.pri then return a.pri < b.pri end
    local na, nb = a.n or math.huge, b.n or math.huge
    if a.money and na ~= nb then return na < nb end
    if a.owner ~= b.owner then return a.owner < b.owner end
    if a.act ~= b.act then return a.act < b.act end
    if na ~= nb then return na < nb end
    return a.i < b.i
end

-- Pure: claims in, grants out: a list, in the order the claims were resolved
-- (required pass, then optional; inside a pass money, then slots, then items),
-- with grants:For, grants:Held and grants:Free, plus
--   grants.unknown   how many grants are unknown
--   grants.invalid   how many claims were refused
-- Neither the snapshot nor a claim is changed. Every claim is answered once.
function Resources.Resolve(snapshot, claims)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local money = isCount(snapshot.money) and snapshot.money or nil
    local bags = type(snapshot.bags) == "table" and snapshot.bags or nil
    local bank = (snapshot.bankKnown and type(snapshot.bank) == "table") and snapshot.bank or nil
    local slots = type(snapshot.slots) == "table" and snapshot.slots or nil

    -- What has been handed out so far. Nothing in the snapshot is written to.
    local spent = 0                       -- copper
    local usedSlots = {}                  -- [family] = n
    local usedBags, usedBank = {}, {}     -- [itemKey] = n
    local held = {}                       -- [key] = n, for grants:Held

    local grants = setmetatable({ unknown = 0, invalid = 0, held = held }, grantsMeta)

    -- Free room in one bag family. nil: not known (bags not read, or that
    -- family marked unknown). 0 when the bags were read and none is of that
    -- family: no room there, and that is known.
    local function slotsFree(family)
        if not slots then return nil end
        local e = slots[family]
        if e == nil then return 0 end
        if type(e) ~= "table" or not isCount(e.free) then return nil end
        return e.free - (usedSlots[family] or 0)
    end
    local function bagsFree(key)
        if not bags then return nil end
        return (isCount(bags[key]) and bags[key] or 0) - (usedBags[key] or 0)
    end
    local function bankFree(key)
        if not bank then return nil end
        return (isCount(bank[key]) and bank[key] or 0) - (usedBank[key] or 0)
    end

    grants.free = function(key)
        if key == Resources.MONEY then return money and (money - spent) or nil end
        if type(key) == "string" then
            local family = key:match("^slots:(.+)$")
            if family then return slotsFree(tonumber(family) or family) end
        end
        local inBags = bagsFree(key)
        if inBags == nil then return nil end
        return inBags + (bankFree(key) or 0)
    end

    -- Sort the claims into the two passes.
    local passes = { { money = {}, slots = {}, item = {} }, { money = {}, slots = {}, item = {} } }
    local refused = {}
    for i = 1, #(claims or {}) do
        local c = claims[i]
        local ok, problem = Resources.CheckClaim(c)
        if ok then
            local pri = c.priority
            local pass = (c.required == false) and passes[2] or passes[1]
            local list = pass[c.kind]
            list[#list + 1] = {
                claim = c, i = i, n = c.amount, money = c.kind == "money",
                sel = c.selected and 1 or 0,
                pri = pri ~= nil and pri or math.huge,
                owner = tostring(c.owner), act = tostring(c.activity),
            }
        else
            refused[#refused + 1] = { claim = c, problem = problem }
        end
    end

    local function hold(key, n)
        if n and n > 0 then held[key] = (held[key] or 0) + n end
    end
    local function add(g)
        if g.unknown then grants.unknown = grants.unknown + 1 end
        grants[#grants + 1] = g
    end

    local function resolveMoney(e)
        local g = { claim = e.claim, before = spent }
        if e.n == nil then
            g.unknown, g.estimate = "price", e.claim.estimate
        elseif not money then
            g.unknown = "money"
        elseif spent + e.n <= money then
            g.got, g.short = e.n, 0
            spent = spent + e.n
            hold(Resources.MONEY, e.n)
        else
            g.got, g.short = 0, e.n
        end
        add(g)
    end

    local function resolveSlots(e)
        local family = e.claim.key == nil and 0 or e.claim.key
        local key = Resources.SlotKey(family)
        local g = { claim = e.claim, before = held[key] or 0 }
        if e.n == nil then
            g.unknown = "amount"
            add(g)
            return
        end
        -- Its own kind of bag first, then the bags that take anything.
        local pools = family == 0 and { 0 } or { family, 0 }
        local want, got, from, sawKnown, sawUnknown = e.n, 0, {}, false, false
        for _, f in ipairs(pools) do
            local free = slotsFree(f)
            if free == nil then
                -- Bags not read at all, or this family marked unknown.
                sawUnknown = true
            else
                sawKnown = true
                local take = math.min(want - got, free)
                if take > 0 then
                    usedSlots[f] = (usedSlots[f] or 0) + take
                    from[f] = take
                    got = got + take
                    hold(Resources.SlotKey(f), take)
                end
            end
        end
        -- Room in bags whose family wasn't given might fit it: Z-Flow can't tell.
        local unsorted = slots and slots.unknown
        if type(unsorted) == "table" and isCount(unsorted.free) and unsorted.free > 0 then sawUnknown = true end
        if got >= want then
            g.got, g.short, g.from = got, 0, from
        elseif sawUnknown then
            g.unknown = "slots"
            if sawKnown then g.got, g.from = got, from end
        else
            g.got, g.short, g.from = got, want - got, from
        end
        add(g)
    end

    local function resolveItem(e)
        local key = e.claim.key
        local g = { claim = e.claim, before = held[key] or 0 }
        if e.n == nil then
            g.unknown = "amount"
            add(g)
            return
        end
        local inBags = bagsFree(key)
        if inBags == nil then
            g.unknown = "bags"
            add(g)
            return
        end
        local fromBags = math.min(e.n, inBags)
        local fromBank, bankUnknown = 0, false
        if fromBags < e.n and e.claim.bank then
            local inBank = bankFree(key)
            if inBank == nil then bankUnknown = true
            else fromBank = math.min(e.n - fromBags, inBank) end
        end
        if fromBags > 0 then usedBags[key] = (usedBags[key] or 0) + fromBags end
        if fromBank > 0 then usedBank[key] = (usedBank[key] or 0) + fromBank end
        g.got = fromBags + fromBank
        g.from = { bags = fromBags, bank = fromBank }
        hold(key, g.got)
        if g.got < e.n and bankUnknown then
            g.unknown = "bank"
        else
            g.short = e.n - g.got
        end
        add(g)
    end

    for p = 1, 2 do
        local pass = passes[p]
        table.sort(pass.money, before)
        table.sort(pass.slots, before)
        table.sort(pass.item, before)
        for _, e in ipairs(pass.money) do resolveMoney(e) end
        for _, e in ipairs(pass.slots) do resolveSlots(e) end
        for _, e in ipairs(pass.item) do resolveItem(e) end
    end
    for _, r in ipairs(refused) do
        grants.invalid = grants.invalid + 1
        grants[#grants + 1] = { claim = r.claim, invalid = true, problem = r.problem, got = 0, short = 0, before = 0 }
    end
    return grants
end
