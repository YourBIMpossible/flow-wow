-- Reads: turns the client's reads (Core/Client.lua) into the tables other
-- areas ask for. Pure: it calls only the client it is handed, so it runs the
-- same over the fake client.
--
--   read = ns.make.resourceRead(client, keyOf)
--     The `read` table Items/Resources.lua's Resources.Take wants:
--       read.money()  -> copper or nil
--       read.bags()   -> { { free = n, total = n, family = n or nil }, ... } or nil
--       read.items()  -> { [itemKey] = count } for the bags, or nil
--       read.bank()   -> { [itemKey] = count } or nil (never seen), and the
--                        time it was last seen
--       read.now()    -> the time
--       read.clock()  -> the wall-clock time, or nil when not known
--     and one more for the caller:
--       read.seeBank() -> true when the bank was open and was read just now.
--     The bank can only be read while its window is open. read keeps the
--     last full reading and its time; read.bank() takes a new one when the
--     bank is open and otherwise answers with the one it kept. Call
--     read.seeBank() on a bank event to catch a visit no snapshot was taken
--     in. One read table per session: a new one has seen no bank.
--
--     keyOf(item) -> the item's key, or nil. item is what the client gave
--     for a stack: a link or an item ID. Left out, it is ns.Items.Key when
--     Items is loaded, else a whole item ID is its own key and nothing else
--     has one.
--
-- Unknown stays unknown: a client read that answers nil, or a stack whose
-- item has no key, makes that whole part nil. It is never a smaller count.
local _, ns = ...
ns.make = ns.make or {}

local function plainKey(item)
    if type(item) == "number" and item > 0 and item == math.floor(item) then return item end
    return nil
end

-- { { item =, count = }, ... } -> { [key] = count }, or nil.
local function sum(stacks, keyOf)
    if type(stacks) ~= "table" then return nil end
    local out = {}
    for i = 1, #stacks do
        local s = stacks[i]
        if type(s) ~= "table" or type(s.count) ~= "number" then return nil end
        local key = keyOf(s.item)
        if key == nil then return nil end
        out[key] = (out[key] or 0) + s.count
    end
    return out
end

function ns.make.resourceRead(client, keyOf)
    local function key(item)
        if type(keyOf) == "function" then return keyOf(item) end
        local Items = ns.Items
        if type(Items) == "table" and type(Items.Key) == "function" then return Items.Key(item) end
        return plainKey(item)
    end

    local function ask(name)
        local fn = type(client) == "table" and client[name]
        if type(fn) ~= "function" then return nil end
        return fn()
    end

    local bank, bankSeenAt
    local read = {}

    function read.money() return ask("money") end
    function read.bags() return ask("bags") end
    function read.items() return sum(ask("bagItems"), key) end
    function read.now() return ask("now") end
    function read.clock() return ask("clock") end

    function read.seeBank()
        if ask("bankOpen") ~= true then return false end
        local counts = sum(ask("bankItems"), key)
        if not counts then return false end
        -- uptime, not now: no time is kept when the client gives none.
        bank, bankSeenAt = counts, ask("uptime")
        return true
    end

    function read.bank()
        read.seeBank()
        return bank, bankSeenAt
    end

    ask("watchBank")
    return read
end
