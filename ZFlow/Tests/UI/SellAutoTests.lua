local _, ns = ...
-- G2 (lead section 402 item 9): the sell list reads the vendor automations
-- the import carries (settings.sell.autoJunk, autoAll, autoRepair,
-- autoCleanup in the account data) and only says what they would do. Each
-- line says Z-Flow does nothing by itself; the junk and all lines count
-- what is on the list. The repair cost is Items/RepairCost.lua's own line.
-- Carried forward from zflow-roll-mbb-merchant-acting 3749c836 (reconcile
-- sweep); the profession material guard is ProfPlan's on this line, not here.
-- Made-up items.
--
-- Fails before: SellList.AutoLines is nil and a listing has no auto lines.
local tests = {}
local L = ns.SellList

local BONE = 3300
local INFO = {
    [BONE] = { name = "Cracked Bone", quality = 0, sellPrice = 5 },
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
        "Repair automatically is on, but Z repairs nothing by itself: use the merchant's Repair button.",
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
        .. "use the merchant's Repair button."
    t.eq(listing.auto, { want }, "on the listing")
    t.eq(L.LinesOf(listing)[1], want, "the first text line")
    local tree = L.TreeOf(listing)
    local body = tree.children[2].children
    t.eq(body[1] and body[1].text, want, "the first line in the window")
    t.eq(body[1] and body[1].tone, "warn")
    t.eq(L.Listing(client(), store(), nil, NONE).auto, {}, "all off: none")
end

return tests
