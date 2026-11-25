local _, ns = ...

-- Tests for ZFlow/Items/AuctionWatch.lua (G9, section 393): a watch list of
-- items, each with an optional price mark. The `watch` word adds, drops and
-- lists them with the last auction price seen in the player's own searches
-- (Items/AuctionLog.lua); when the auction window closes, one chat line per
-- watched item seen at or under its mark. Read and show only: nothing
-- searches, bids or buys. Fake client and a real kernel; made-up prices.
--
-- Red before the code: ns.AuctionWatch does not exist.

local tests = {}
local function W() return ns.AuctionWatch end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setRealm("Old Blanchy")
    c.setFaction("Horde")
    c.setClock(1000)
    c.setItemInfo({ [2589] = { name = "Linen Cloth" }, [2592] = { name = "Wool Cloth" } })
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    ns.AuctionLog.Declare(k, d)
    if type(W()) == "table" then W().Declare(k, d) end
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

local function say(c, text)
    local before = #c.printed
    c.slashes[ns.id.slash](text)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function T(s) return ns.id.title .. ": " .. s end

tests["auction watch: the module and its words exist"] = function(t)
    t.eq(type(W()), "table", "ns.AuctionWatch")
    if type(W()) ~= "table" then return end
    t.eq(W().WORD, "watch")
    t.eq(type(W().Mark), "function", "AuctionWatch.Mark")
    t.eq(type(W().Lines), "function", "AuctionWatch.Lines")
end

tests["auction watch: a price mark is read from coins; anything else is no mark"] = function(t)
    if type(W()) ~= "table" then return t.ok(false, "ns.AuctionWatch") end
    t.eq(W().Mark("1g 2s 3c"), 10203)
    t.eq(W().Mark("15s"), 1500)
    t.eq(W().Mark("40c"), 40)
    t.eq(W().Mark(""), nil)
    t.eq(W().Mark("cheap"), nil)
    t.eq(W().Mark(nil), nil)
end

tests["auction watch: the word adds, lists with the last price, and drops"] = function(t)
    if type(W()) ~= "table" then return t.ok(false, "ns.AuctionWatch") end
    local _, c = start()
    t.eq(say(c, "watch"), { T("watch: nothing watched. watch <item> [price] adds one; an amount ends in g, s or c.") })
    t.eq(say(c, "watch item:2589 15c"), { T("watch: Linen Cloth, at or under 15c.") })
    t.eq(say(c, "watch item:2592"), { T("watch: Wool Cloth.") })
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(say(c, "watch"), {
        T("watch: Linen Cloth: 12c each, under your 15c."),
        T("watch: Wool Cloth: not seen in your searches yet."),
    })
    t.eq(say(c, "watch item:2592 off"), { T("watch: Wool Cloth dropped.") })
    t.eq(#say(c, "watch"), 1)
end

tests["auction watch: closing the auction window names what is at or under its mark"] = function(t)
    if type(W()) ~= "table" then return t.ok(false, "ns.AuctionWatch") end
    local k, c = start()
    say(c, "watch item:2589 15c")
    say(c, "watch item:2592 10c")
    c.auctionResult(2589, { unitPrice = 12 })
    c.auctionResult(2592, { unitPrice = 30 })
    local before = #c.printed
    c.fire("AUCTION_HOUSE_CLOSED")
    t.eq(c.printed[before + 1], T("watch: Linen Cloth was 12c each, under your 15c."))
    t.eq(#c.printed, before + 1, "Wool Cloth is over its mark: no line")
    t.eq(k.settings:set(W().SETTING, false), true)
    before = #c.printed
    c.fire("AUCTION_HOUSE_CLOSED")
    t.eq(#c.printed, before, "switched off: no line")
end

-- E-31 (lead 681, 682): the short form the add-on prints ("1.36g", "5.52s",
-- "52c", "13.6g") reads back, as the legacy AH.ParseMoney does
-- (Flow d78839f7 Modules/Items/Auction.lua:40-52): a plain number is gold, joined
-- amounts ("1g50s") add up, anything else is no mark.
tests["auction watch: the short money form reads back as a mark"] = function(t)
    if type(W()) ~= "table" then return t.ok(false, "ns.AuctionWatch") end
    t.eq(W().Mark("1.36g"), 13600)
    t.eq(W().Mark("13.6g"), 136000)
    t.eq(W().Mark("5.52s"), 552)
    t.eq(W().Mark("52c"), 52)
    t.eq(W().Mark("1.5"), 15000, "a plain number is gold")
    t.eq(W().Mark("1g50s"), 15000)
    t.eq(W().Mark("1G 50S"), 15000)
    t.eq(W().Mark("75s"), 7500)
    t.eq(W().Mark("1.2.3g"), nil)
    t.eq(W().Mark("1gx"), nil)
    t.eq(W().Mark("g"), nil)
    t.eq(W().Mark("-1g"), nil)
end

tests["auction watch: what the add-on prints reads back as the same mark"] = function(t)
    if type(W()) ~= "table" then return t.ok(false, "ns.AuctionWatch") end
    for _, copper in ipairs({ 52, 552, 13600, 136000 }) do
        local text = ns.Prices.Coin(copper)
        t.eq(W().Mark(text), copper, tostring(text))
    end
end

-- E-31: a watched item seen at or under its mark: one chat line and the
-- alert sound, once an item a visit to the auction house.
tests["auction watch: a result at or under the mark says it and plays the sound once"] = function(t)
    if type(W()) ~= "table" then return t.ok(false, "ns.AuctionWatch") end
    local _, c = start()
    say(c, "watch item:2589 15c")
    say(c, "watch item:2592 10c")
    local before = #c.printed
    c.auctionResult(2592, { unitPrice = 30 })
    t.eq(#c.printed, before, "over its mark: no line")
    t.eq(#c.alertsPlayed(), 0, "over its mark: no sound")
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(c.printed[before + 1], T("watch: Linen Cloth is on the auction house for 12c each, at or under your 15c."))
    t.eq(#c.alertsPlayed(), 1)
    c.auctionResult(2589, { unitPrice = 11 })
    t.eq(#c.printed, before + 1, "once an item a visit")
    t.eq(#c.alertsPlayed(), 1)
    c.fire("AUCTION_HOUSE_CLOSED")
    before = #c.printed
    c.auctionResult(2589, { unitPrice = 15 })
    t.eq(c.printed[before + 1], T("watch: Linen Cloth is on the auction house for 15c each, at or under your 15c."))
    t.eq(#c.alertsPlayed(), 2, "a new visit alerts again")
end

tests["auction watch: no mark, or no sound in the game, still never acts"] = function(t)
    if type(W()) ~= "table" then return t.ok(false, "ns.AuctionWatch") end
    local _, c = start()
    say(c, "watch item:2592")
    local before = #c.printed
    c.auctionResult(2592, { unitPrice = 1 })
    t.eq(#c.printed, before, "no mark: no alert")
    say(c, "watch item:2589 15c")
    c.setAlertSound({ fail = "noCall" })
    before = #c.printed
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(c.printed[before + 1], T("watch: Linen Cloth is on the auction house for 12c each, at or under your 15c."))
    t.eq(#c.alertsPlayed(), 0)
end

tests["auction watch: the ah word watches and unwatches"] = function(t)
    if type(W()) ~= "table" then return t.ok(false, "ns.AuctionWatch") end
    local _, c = start()
    t.eq(say(c, "ah watch item:2589 1.5s"), { T("watch: Linen Cloth, at or under 1.5s.") })
    t.eq(say(c, "ah unwatch item:2589"), { T("watch: Linen Cloth dropped.") })
    t.eq(say(c, "ah"), {
        T("watch: auction watch list, last price seen:"),
        T("watch: nothing watched."),
        T("watch: ah watch <item> [price] | ah unwatch <item> | ah (the list). It buys nothing."),
    })
    t.eq(say(c, "ah scan"), { T("watch: ah watch <item> [price] | ah unwatch <item> | ah (the list). It buys nothing.") })
end

-- E-33: bare ah, as the legacy /flow ah (Flow d78839f7 Modules/Items/Auction.lua:224-235):
-- a heading, each watched item with its last price, then the words.
tests["auction watch: AhLines frames the list as the legacy ah did"] = function(t)
    if type(W()) ~= "table" or type(W().AhLines) ~= "function" then return t.ok(false, "AuctionWatch.AhLines") end
    t.eq(W().AhLines({ "Linen Cloth: 1.4s each." }),
        { W().AH_HEAD, "Linen Cloth: 1.4s each.", W().AH_USAGE })
    t.eq(W().AhLines({}), { W().AH_HEAD, W().AH_EMPTY, W().AH_USAGE })
    t.eq(W().AhLines(nil), { W().AH_HEAD, W().AH_EMPTY, W().AH_USAGE })
end

tests["auction watch: bare ah lists each watched item's last price"] = function(t)
    if type(W()) ~= "table" then return t.ok(false, "ns.AuctionWatch") end
    local _, c = start()
    say(c, "watch item:2589 1.5s")
    say(c, "watch item:2592")
    c.auctionResult(2589, { unitPrice = 140 })
    local lines = say(c, "ah")
    t.eq(lines[1], T("watch: auction watch list, last price seen:"))
    t.eq(lines[#lines], T("watch: ah watch <item> [price] | ah unwatch <item> | ah (the list). It buys nothing."))
    t.eq(#lines, 4)
end

return tests
