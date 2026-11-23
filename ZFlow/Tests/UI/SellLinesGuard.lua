local _, ns = ...
-- Lead sections 224 and 225, MyBuddy SR-3 and LR-2: SellList.Lines gives no
-- sell advice unless it is handed a reservations evaluation it can trust.
-- A missing or odd evaluation is "unavailable"; bags unread with a goal
-- saved give no sell row. A fake client and made-up items. Look only:
-- nothing is sold or clicked. Not tested in game.
local tests = {}

local PELT = 4865
local INFO = { [PELT] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15 } }

local function client(bagsRead)
    local c = ns.make.fakeClient()
    c.setItemInfo(INFO)
    if bagsRead then c.setBagItems({ { item = PELT, count = 20 } }) end
    return c
end

local function sellRows(lines)
    local n = 0
    for _, l in ipairs(lines or {}) do
        if tostring(l):find("^%d+ x ") or l == ns.ItemPresent.SELL_HEADER then n = n + 1 end
    end
    return n
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

-- SR-3. Fails without the "r not a table" half of the guard in
-- UI/SellList.lua Lines.
tests["sell lines guard SR-3: no evaluation, or one that is not a table, gives no sell advice"] = function(t)
    local S, R = ns.SellList, ns.Reservations
    local c = client(true)
    local none = S.Lines(c, nil, nil, { status = R.NONE })
    t.ok(sellRows(none) > 0, "nothing reserved: the pelt is offered, so this test can fail")
    for _, r in ipairs({ false, "odd", 7 }) do
        local lines = S.Lines(c, nil, nil, r)
        t.eq(sellRows(lines), 0, "not an evaluation (" .. tostring(r) .. "): nothing offered")
        t.ok(has(lines, S.RESERVATIONS_UNKNOWN), "and it says why")
    end
    local missing = S.Lines(c, nil, nil, nil)
    t.eq(sellRows(missing), 0, "no evaluation at all: nothing offered")
    t.ok(has(missing, S.RESERVATIONS_UNKNOWN), "and it says why")
end

-- LR-2. Bags unread with a goal saved (the evaluation is unavailable): no
-- sell row, and the list says it can't be made. Fails without the bag-nil
-- check at the top of Items/Sell.lua Sell.List.
tests["sell lines guard LR-2: bags unread with a goal saved gives no sell line"] = function(t)
    local S, R = ns.SellList, ns.Reservations
    local lines = S.Lines(client(false), nil, nil, { status = R.UNAVAILABLE })
    t.eq(sellRows(lines), 0, "no sell row")
    t.ok(has(lines, "Can't list what to sell: " .. ns.ItemSell.BAGS_UNREAD), "says it can't list: "
        .. table.concat(lines or {}, " / "))
end

return tests
