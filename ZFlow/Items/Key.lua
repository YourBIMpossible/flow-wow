local _, ns = ...

-- Items.Key: one name for an item, whatever it was handed in as.
--
-- Bags, the bank, claims, grants, prices and keep rules all have to agree on
-- what "the same item" is. Items.Key turns an item ID, an item string or a
-- chat link into that one key:
--   2318                                  -> 2318
--   "2318"                                -> 2318
--   "item:2318"                           -> 2318
--   "|cffffffff|Hitem:2318:0:0:0:0:0:0:0|h[Light Leather]|h|r" -> 2318
--   "item:15234:0:0:0:0:0:588:0"          -> "15234:588"
-- A plain item's key is its number. An item with a random suffix ("of the
-- Bear") is a different item for selling and wearing, so its key carries the
-- suffix. Enchants, gems and the unique number are left out: they don't make
-- it another item to count.
-- nil for anything that isn't an item: Z-Flow doesn't guess.
--
-- Pure: nothing here reads the game. The place of the suffix in an item
-- string (the seventh field, counting the ID as the first) is taken from the item strings in
-- Flow's own source and is not confirmed in the game client.

local Items = ns.Items or {}
ns.Items = Items

local SUFFIX_FIELD = 7     -- item:ID:enchant:gem1:gem2:gem3:gem4:suffix:unique

local function wholeId(n)
    return type(n) == "number" and n == n and n > 0 and n < math.huge and n == math.floor(n)
end

-- -> key, or nil when `what` isn't an item ID, an item string or a link.
function Items.Key(what)
    if type(what) == "number" then
        return wholeId(what) and what or nil
    end
    if type(what) ~= "string" then return nil end
    if what:match("^%d+$") then
        local n = tonumber(what)
        return wholeId(n) and n or nil
    end
    if what:match("^%d+:%-?%d+$") then
        -- Already a key with a suffix.
        local id, suffix = what:match("^(%d+):(%-?%d+)$")
        id, suffix = tonumber(id), tonumber(suffix)
        if not wholeId(id) then return nil end
        if suffix == 0 then return id end
        return id .. ":" .. suffix
    end
    local body = what:match("item:([%-%d:]+)")
    if not body then return nil end
    local fields = {}
    for part in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = part end
    local id = tonumber(fields[1])
    if not wholeId(id) then return nil end
    local suffix = tonumber(fields[SUFFIX_FIELD])
    if suffix and suffix ~= 0 then return id .. ":" .. suffix end
    return id
end

-- The item's ID number from a key (or from anything Items.Key takes); nil
-- when it isn't an item.
function Items.Id(what)
    local key = Items.Key(what)
    if type(key) == "number" then return key end
    if type(key) == "string" then return tonumber(key:match("^(%d+):")) end
    return nil
end

-- Do two things name the same item? false when either isn't an item.
function Items.Same(a, b)
    local ka, kb = Items.Key(a), Items.Key(b)
    return ka ~= nil and ka == kb
end
