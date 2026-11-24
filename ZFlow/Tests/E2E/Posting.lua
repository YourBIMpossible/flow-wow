local _, ns = ...

-- Auction posting advice (S3, Items/Posting.lua), end to end, on the whole
-- add-on loaded on a fake client. The real entries: the auctions word
-- (<slash> auctions) lists what in the bags is worth the auction house,
-- from prices in the player's own searches (c.auctionResult, kept by
-- Items/AuctionLog.lua); the item tooltip gets the price to ask; the
-- game's own expired and sold lines (CHAT_MSG_SYSTEM) count unsold
-- auctions. Advice only: nothing posts, sells or equips. Made-up realm
-- and items. Not tested in game.
--
-- The numbers: one look at 50s for a grey fang the vendor pays 4c for.
-- Ask = 50s less one silver = 49s; gain for 2 = (4900 * 0.95 - 4) * 2 =
-- 9302c = 93s 2c.

local tests = {}

local FANG, SCRAP = 97, 2934
local INFO = {
    [FANG] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [SCRAP] = { name = "Ruined Leather Scraps", quality = 0, sellPrice = 1 },
}
local NOW = 1700000000

-- opts.realm: false for no realm read; opts.account: the account's saved table.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setClock(NOW)
    if opts.realm ~= false then c.setRealm("Realm1") end
    c.setFaction("Horde")
    c.setItemInfo(INFO)
    c.setBagItems({ { item = FANG, count = 2 }, { item = SCRAP, count = 1 } })
    c.setGlobalText("ERR_AUCTION_EXPIRED_S", "Your auction of %s has expired.")
    c.setGlobalText("ERR_AUCTION_SOLD_S", "A buyer has been found for your auction of %s.")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

-- The words the auctions word prints, as typed (names in their quality
-- colour, Items/Present.lua Tint).
local function rawWord(c)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    c.slashes[ns.id.slash]("auctions")
    local out = {}
    for i, l in ipairs(c.printed) do out[i] = l end
    return out
end

-- The same with the colour codes taken off, to compare the words.
local function word(c)
    local out = rawWord(c)
    for i, l in ipairs(out) do out[i] = ns.ItemPresent.Plain(l) end
    return out
end

local function tip(c, link)
    for _, l in ipairs(c.showItemTooltip(link)) do
        if type(l.text) == "string" and l.text:sub(1, 13) == "Auction: ask " then return l.text end
    end
    return nil
end

local FOOT = "Posting is yours, in the auction window: " .. ns.id.title .. " posts nothing."
local FANG_ROW = "2 x Broken Fang: ask 49s each (seen 50s, 0 min ago; a vendor pays 4c;"
    .. " about +93s 2c over vendoring, the deposit not counted)"

local function noneActs(t, c)
    t.eq(#c.soldSlots, 0, "nothing sold")
    t.eq(c.equipCalls, 0, "nothing equipped")
end

tests["posting e2e: a searched price puts the item on the auctions word"] = function(t)
    local c = boot()
    c.auctionResult(FANG, { unitPrice = 5000, quantity = 3 })
    t.eq(word(c), {
        ns.id.title .. " Auctions: 1 thing(s) worth the auction house (from prices in your own searches)",
        FANG_ROW,
        FOOT,
    })
    -- The name is in the colour of its quality (poor: Kit.Quality(0)), one
    -- name, tinted once.
    local raw = rawWord(c)[2]
    t.ok(raw:find(ns.ItemPresent.Tint("Broken Fang", 0), 1, true) ~= nil, "the name carries its quality colour: " .. raw)
    noneActs(t, c)
end

tests["posting e2e: the tooltip gives the price to ask"] = function(t)
    local c = boot()
    c.auctionResult(FANG, { unitPrice = 5000 })
    t.eq(tip(c, FANG), "Auction: ask 49s each (1s under 50s, seen 0 min ago)")
    t.eq(tip(c, SCRAP), nil, "no price seen: no advice")
    noneActs(t, c)
end

tests["posting e2e: an expired line counts, a sale clears it"] = function(t)
    local c = boot()
    c.auctionResult(FANG, { unitPrice = 5000 })
    c.systemMessage("Your auction of Broken Fang has expired.")
    c.systemMessage("Your auction of Broken Fang has expired.")
    t.eq(word(c)[2], FANG_ROW .. " (unsold at least 2x)")
    t.eq(tip(c, FANG), "Auction: ask 49s each (1s under 50s, seen 0 min ago) (unsold at least 2x)")
    c.systemMessage("A buyer has been found for your auction of Broken Fang.")
    t.eq(word(c)[2], FANG_ROW)
    -- A name that is in neither the bags nor the priced items is passed over.
    c.systemMessage("Your auction of Nobody's Hat has expired.")
    t.eq(word(c)[2], FANG_ROW)
    noneActs(t, c)
end

tests["posting e2e: unknown prices are not guessed"] = function(t)
    -- No search seen: nothing to post, and the tooltip says nothing.
    local c = boot()
    t.eq(word(c), { ns.id.title .. " Auctions: 0 thing(s) to post", FOOT })
    t.eq(tip(c, FANG), nil)
    -- A price row that has no price records nothing.
    c.auctionResult(FANG, { unitPrice = "x" })
    t.eq(word(c), { ns.id.title .. " Auctions: 0 thing(s) to post", FOOT })
    -- The realm not read: a search is kept nowhere, so nothing is offered.
    local c2 = boot({ realm = false })
    c2.auctionResult(FANG, { unitPrice = 5000 })
    t.eq(word(c2), { ns.id.title .. " Auctions: 0 thing(s) to post", FOOT })
    noneActs(t, c2)
end

tests["posting e2e: the tooltip setting off takes the line away, the word stays"] = function(t)
    local c = boot({ account = { settings = { auction = { postAdvice = false } } } })
    c.auctionResult(FANG, { unitPrice = 5000 })
    t.eq(tip(c, FANG), nil)
    t.eq(word(c)[2], FANG_ROW)
end

return tests
