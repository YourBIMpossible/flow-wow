-- S3 slice 1: what is worth the auction house (Items/Posting.lua), from
-- legacy Flow's Posting.lua and Disposition.WorthAuction. Advice only:
-- nothing posts. Fake client only; not tested in game.
local _, ns = ...

local Po = ns.Posting
local tests = {}
-- Item names carry the game's quality colour (Items/Present.lua, Tint; the
-- colour itself is tested in Tests/Items/ItemColourTests.lua). These tests are
-- about the words, so they read them with the colour taken off.
local plain = ns.ItemPresent.Plain
local HOUR = 3600

local function near(t, a, b, msg)
    t.ok(type(a) == "number" and math.abs(a - b) < 0.01, (msg or "") .. ": " .. tostring(a) .. " ~ " .. tostring(b))
end

tests["posting: the ask is a silver under the cheapest seen, whole silver, never under one"] = function(t)
    t.eq(Po.Price(1000), 900)
    t.eq(Po.Price(1050), 900, "floored to whole silver")
    t.eq(Po.Price(250), 100)
    t.eq(Po.Price(150), 100, "undercut under a silver: the seen price floored instead")
    t.eq(Po.Price(100), 100, "exactly a silver")
    t.eq(Po.Price(99), nil, "under a silver: the game takes no copper prices")
    t.eq(Po.Price(nil), nil)
    t.eq(Po.Price("1000"), 900, "legacy took a number in a string")
    t.eq({ Po.UNDERCUT, Po.MIN, Po.CUT, Po.FEE }, { 100, 100, 0.05, 0.30 })
end

tests["posting: the verdict, post or vendor, with the gain left"] = function(t)
    local v, left = Po.Verdict(900, 100, 2, 0, 0)
    t.eq(v, "post")
    near(t, left, 1510, "two at 9s, a vendor's 1s, the 5% cut")
    v, left = Po.Verdict(100, 100, 1)
    t.eq(v, "vendor")
    near(t, left, -5, "the cut eats it")
    v, left = Po.Verdict(900, 100, 2, 1000, 600)
    t.eq(v, "vendor")
    near(t, left, -90, "deposits lost and the next one outweigh the gain")
end

tests["posting: worth the auction house at twice the vendor and a silver more, after cut and fee"] = function(t)
    t.eq(Po.WorthAuction(1000, 100), true)
    t.eq(Po.WorthAuction(250, 100), true)
    t.eq(Po.WorthAuction(240, 100), false, "under twice the vendor's price")
    t.eq(Po.WorthAuction(106, 0), true)
    t.eq(Po.WorthAuction(105, 0), false, "under a silver more than the vendor")
    t.eq(Po.WorthAuction(0, 10), false)
    t.eq(Po.WorthAuction(nil, 10), false)
    t.eq(Po.WorthAuction(1000, nil), true, "no vendor price: counted as none")
end

tests["posting: the candidate rule, shared with the trader"] = function(t)
    t.eq(Po.Candidate({ action = "sell", rule = "junk" }, {}), true)
    t.eq(Po.Candidate({ action = "keep", rule = nil }, {}), true, "nothing matched: a generic keep")
    t.eq(Po.Candidate({ action = "keep", rule = "notGear" }, {}), true)
    t.eq(Po.Candidate({ action = "keep", rule = nil, failed = true }, {}), false, "a failed check keeps it")
    for _, rule in ipairs({ "yourChoice", "neverSell", "unsellable", "professionTool", "held", "quest", "questNeeds",
        "classKeep", "inSet", "professionMaterial", "spareBag", "recipe", "needsTraining", "laterOrOtherRole",
        "unscoredClass" }) do
        t.eq(Po.Candidate({ action = "keep", rule = rule }, {}), false, rule)
    end
    t.eq(Po.Candidate({ action = "equip" }, {}), false)
    t.eq(Po.Candidate({ action = "sell" }, { bound = true }), false, "bound: never")
    t.eq(Po.Candidate(nil, {}), false)
    t.eq(Po.Candidate({ action = "sell" }, nil), true)
end

local BAG = {
    { key = 2589, name = "Linen Cloth", count = 20, quality = 1, sellPrice = 13, classID = 7 },
    { key = 4306, name = "Silk Cloth", count = 5, quality = 1, sellPrice = 150, classID = 7 },
    { key = 858, name = "Lesser Healing Potion", count = 5, quality = 1, sellPrice = 20, classID = 0 },
    { key = 2318, name = "Light Leather", count = 10, quality = 1, sellPrice = 15, classID = 7 },
    { key = 4865, name = "Ruined Pelt", count = 3, quality = 0, sellPrice = 5, classID = 15 },
    { key = 7005, name = "Skinning Knife", count = 1, quality = 1, sellPrice = 20, classID = 2 },
}
local DECISIONS = {
    [2589] = { action = "keep" },
    [4306] = { action = "sell", rule = "junk" },
    [858] = { action = "keep" },
    [2318] = { action = "keep", rule = "notGear" },
    [4865] = { action = "keep" },
    [7005] = { action = "keep", rule = "professionTool" },
}
local SEEN = {
    [2589] = { price = 300, at = 1000 },
    [4306] = { price = 400, at = 2000 },
    [858] = { price = 120, at = 1000 },
    [2318] = { price = 120, at = 1000 },
    [7005] = { price = 10000, at = 1000 },
}
local function decide(item) return DECISIONS[item.key] end
local function seen(key) return SEEN[key] end

tests["posting: the list, biggest ask first, only with a seen price"] = function(t)
    local rows = Po.List(BAG, decide, seen)
    t.eq(#rows, 3)
    t.eq(rows[1], { id = 2589, name = "Linen Cloth", quality = 1, count = 20, each = 200, seen = 300, seenAt = 1000, vendor = 13, gain = 3540 })
    t.eq(rows[2], { id = 4306, name = "Silk Cloth", quality = 1, count = 5, each = 300, seen = 400, seenAt = 2000, vendor = 150, gain = 675 })
    t.eq(rows[3].id, 2318, "not worth it by price, but an unused trade good: listed")
    t.eq(rows[3].gain, 800)
    -- The potion is not a trade good and not worth it; the pelt has no
    -- seen price; the knife is a tool.
    t.eq(Po.List(nil, decide, seen), {})
    t.eq(Po.List(BAG, function() error("boom") end, seen), {}, "a decision that raises lists nothing")
end

tests["posting: the lines say the ask, the seen price and its age, the vendor and the gain"] = function(t)
    local rows = Po.List(BAG, decide, seen)
    local lines = Po.Lines(rows, 1000 + HOUR, "T")
    t.eq(lines, {
        "T Auctions: 3 thing(s) worth the auction house (from prices in your own searches)",
        "20 x Linen Cloth: ask 2s each (seen 3s, 1 h ago; a vendor pays 13c; about +35.4s over vendoring, the deposit not counted)",
        "5 x Silk Cloth: ask 3s each (seen 4s, 43 min ago; a vendor pays 1.5s; about +6.75s over vendoring, the deposit not counted)",
        "10 x Light Leather: ask 1s each (seen 1.2s, 1 h ago; a vendor pays 15c; about +8s over vendoring, the deposit not counted)",
        "Posting is yours, in the auction window: T posts nothing.",
    })
    t.eq(Po.Lines({}, 1000, "T"), { "T Auctions: 0 thing(s) to post", "Posting is yours, in the auction window: T posts nothing." })
    local one = Po.Lines({ { id = 1, count = 1, each = 100, seen = 120, vendor = 90, gain = -5 } }, nil, "T", 1)
    t.eq(one[2], "1 x item 1: ask 1s each (seen 1.2s; a vendor pays 90c; about -5c over vendoring, the deposit not counted)")
    local cut = Po.Lines(rows, 1000, "T", 1)
    t.eq(cut[3], "and 2 more.")
end

tests["posting: no line says the addon posts, buys or cancels"] = function(t)
    local lines = Po.Lines(Po.List(BAG, decide, seen), 1000, "T")
    for _, l in ipairs(lines) do
        local low = l:lower()
        t.ok(not low:find("posting now", 1, true) and not low:find("will post", 1, true)
            and not low:find("buy", 1, true) and not low:find("cancel", 1, true), l)
    end
end

local INFO = {
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [858] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
}

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setRealm("Old Blanchy")
    c.setFaction("Horde")
    c.setClock(1000 + HOUR)
    c.setItemInfo(INFO)
    c.setBagItems({ { item = 2589, count = 20 }, { item = 858, count = 5 } })
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    -- Lead section 220 (SR-1, SR-2): with no reservations module the status
    -- is unavailable and nothing is advised for sale; this kernel has one.
    ns.Reservations.Declare(k)
    local api = Po.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

tests["posting word: lists from the prices of your own searches"] = function(t)
    local k, c, api = start()
    t.eq(k.store:set("account", ns.AuctionLog.PATH .. ".Old Blanchy-Horde",
        { [2589] = { h = { 500, 400, 1000, 300 } }, [858] = { h = { 1000, 120 } } }), true)
    local before = #c.printed
    c.slashes[ns.id.slash]("auctions")
    local title = ns.id.title
    t.eq(c.printed[before + 1], title .. " Auctions: 1 thing(s) worth the auction house (from prices in your own searches)")
    t.eq(c.printed[before + 2], "20 x Linen Cloth: ask 2s each (seen 3s, 1 h ago; a vendor pays 13c; "
        .. "about +35.4s over vendoring, the deposit not counted)", "the latest look is the one undercut")
    t.eq(c.printed[before + 3], "Posting is yours, in the auction window: " .. title .. " posts nothing.")
    t.eq(#c.printed, before + 3)
    t.eq(api.runs(), 1)
end

tests["posting word: no prices, no realm, nothing to post"] = function(t)
    local _, c = start()
    local before = #c.printed
    c.slashes[ns.id.slash]("auctions")
    t.eq(c.printed[before + 1], ns.id.title .. " Auctions: 0 thing(s) to post")
    t.eq(Po.WORD, "auctions")
end

for name, fn in pairs(tests) do
    tests[name] = function(t)
        return fn(setmetatable({ eq = function(got, want, msg) return t.eq(plain(got), plain(want), msg) end },
            { __index = t }))
    end
end

return tests
