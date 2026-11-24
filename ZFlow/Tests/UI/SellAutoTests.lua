local _, ns = ...
-- G2 (lead section 402 item 9): the sell list reads the vendor automations
-- the import carries (settings.sell.autoJunk, autoAll, autoRepair,
-- autoCleanup in the account data) and only says what they would do. Each
-- line says Z-Flow does nothing by itself; the junk and all lines count
-- what is on the list. No repair cost is read yet, so the repair line says
-- that. A profession material (a trade good) is never offered to the
-- vendor, also when it is grey: it moves to the kept part with its reason.
-- Made-up items. Not run: no Lua on this machine.
--
-- Fails before: SellList.AutoLines is nil, a listing has no auto lines,
-- and a grey trade good is offered for sale.
local tests = {}
local L = ns.SellList

local BONE, SCRAP, CLOTH = 3300, 3304, 2589
local INFO = {
    [BONE] = { name = "Cracked Bone", quality = 0, sellPrice = 5 },
    [SCRAP] = { name = "Frayed Scrap", quality = 0, sellPrice = 3, classID = 7 },
    [CLOTH] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
}
local NONE = { status = ns.Reservations.NONE }

-- A store with only get: account paths from `sell` (key -> value).
local function store(sell)
    local data = {}
    for k, v in pairs(sell or {}) do data["account:settings.sell." .. k] = v end
    return { get = function(_, scope, path) return data[tostring(scope) .. ":" .. tostring(path)] end }
end

local function client(bag)
    local c = ns.make.fakeClient()
    c.setBagItems(bag or { { item = BONE, count = 2 } })
    c.setItemInfo(INFO)
    return c
end

local function has(lines, text)
    for _, l in ipairs(type(lines) == "table" and lines or {}) do
        if l == text then return true end
    end
    return false
end

local function title() return tostring(ns.id.title) end

tests["sell auto: all four off, or no store, says nothing"] = function(t)
    t.eq(type(L.AutoLines), "function", "the reader is there")
    if type(L.AutoLines) ~= "function" then return end
    local listing = L.Listing(client(), store(), nil, NONE)
    t.eq(L.AutoLines(store(), listing, "Z"), {}, "nothing turned on, nothing said")
    t.eq(L.AutoLines(nil, listing, "Z"), {}, "no store, nothing said")
    t.eq(L.AutoLines(store({ autoJunk = "yes" }), listing, "Z"), {}, "only a true value is on")
end

tests["sell auto: junk on counts the grey items and says nothing is sold by itself"] = function(t)
    if type(L.AutoLines) ~= "function" then t.ok(false, "AutoLines") return end
    local s = store({ autoJunk = true })
    local listing = L.Listing(client({ { item = BONE, count = 2 } }), s, nil, NONE)
    t.eq(L.AutoLines(s, listing, "Z"),
        { "Sell junk automatically is on, but Z sells nothing by itself. Grey items it would sell: 1 item." })
end

tests["sell auto: all on counts every row; repair and cleanup say what is not done"] = function(t)
    if type(L.AutoLines) ~= "function" then t.ok(false, "AutoLines") return end
    local s = store({ autoAll = true, autoRepair = true, autoCleanup = true })
    local listing = L.Listing(client({ { item = BONE, count = 2 } }), s, nil, NONE)
    t.eq(L.AutoLines(s, listing, "Z"), {
        "Sell all automatically is on, but Z sells nothing by itself. Items on this list: 1 item.",
        "Repair automatically is on, but Z repairs nothing by itself: use the merchant's Repair button. "
            .. "The repair cost is not read yet.",
        "Clean up bags automatically is on, but Z deletes and moves nothing by itself.",
    }, "in the order of the settings")
end

tests["sell auto: with the list not made, the counts say so"] = function(t)
    if type(L.AutoLines) ~= "function" then t.ok(false, "AutoLines") return end
    local s = store({ autoJunk = true })
    local unavailable = L.Listing(client(), s, nil, { status = ns.Reservations.UNAVAILABLE })
    t.eq(L.AutoLines(s, unavailable, "Z"),
        { "Sell junk automatically is on, but Z sells nothing by itself. Grey items it would sell: not counted yet." })
end

tests["sell auto: the listing carries the lines, the text panel and the kit window show them first"] = function(t)
    local s = store({ autoRepair = true })
    local listing = L.Listing(client(), s, nil, NONE)
    local want = "Repair automatically is on, but " .. title() .. " repairs nothing by itself: "
        .. "use the merchant's Repair button. The repair cost is not read yet."
    t.eq(listing.auto, { want }, "on the listing")
    t.eq(L.LinesOf(listing)[1], want, "the first text line")
    local tree = L.TreeOf(listing)
    local body = tree.children[2].children
    t.eq(body[1] and body[1].text, want, "the first line in the window")
    t.eq(body[1] and body[1].tone, "warn")
    t.eq(L.Listing(client(), store(), nil, NONE).auto, {}, "all off: none")
end

tests["sell auto: a grey trade good is never offered to the vendor, it is kept with why"] = function(t)
    local listing = L.Listing(client({ { item = BONE, count = 2 }, { item = SCRAP, count = 4 } }), store(), nil, NONE)
    local offered = {}
    for _, r in ipairs(listing.list.rows) do offered[r.key] = true end
    t.ok(offered[BONE], "the grey bone is still offered")
    t.ok(not offered[SCRAP], "the grey trade good is not")
    local kept
    for _, k in ipairs(listing.kept.rows) do if k.key == SCRAP then kept = k end end
    t.ok(kept ~= nil, "it is in the kept part")
    t.eq(kept and kept.reason, L.MATERIAL_KEPT)
    t.eq(kept and kept.count, 4)
    t.eq(listing.list.total.known + listing.list.total.estimated, 10, "the total is the bone's alone")
    t.ok(not has(L.LinesOf(listing), "4 x Frayed Scrap: 3c each, 12c (the item's own sell price)"),
        "no text line offers it")
end

tests["sell auto: a white trade good stays as it was, and the sell button plan skips the material"] = function(t)
    local before = L.Listing(client({ { item = CLOTH, count = 20 } }), store(), nil, NONE)
    t.eq(#before.list.rows, 0, "white cloth was never offered")
    for _, k in ipairs(before.kept.rows) do
        t.ok(k.key ~= CLOTH, "and is not moved into the kept part")
    end
    local c = client({ { bag = 0, slot = 1, item = SCRAP, count = 4 } })
    local listing = L.Listing(c, store(), nil, NONE)
    local steps = ns.SellThese.Plan(listing, c.bagSlots and c.bagSlots() or nil)
    t.eq(steps, nil, "nothing to sell: the material is not a step")
end

return tests
