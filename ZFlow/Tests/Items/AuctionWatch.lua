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
    t.eq(say(c, "watch"), { T("watch: nothing watched. watch <item> [price, as 1g 2s 3c] adds one.") })
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

return tests
