local _, ns = ...
-- S41 quest items in the bags, end to end on the whole add-on loaded on a
-- fake client. A Gnoll Paw asked for by a quest that is then handed in is
-- named as left over; a quest item the open vendor sells is named to buy.
-- Unknown stays silent. Offline: fake client reads, not the game.
-- Not tested in game.
local tests = {}

local PAW, WOOD = 725, 13872
local GNOLL_Q, ERRAND_Q = 9101, 9102
local LEFT = "Gnoll Paw is left over from a finished quest: you can sell or destroy it."
local BUY = "Buy Bundle of Wood from a vendor for the quest Stormwind Errand."

local function row(id, title, text, done)
    return { id = id, title = title, complete = false, objectives = { { text = text, done = done == true } } }
end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo({ [PAW] = { name = "Gnoll Paw", classID = 12 }, [WOOD] = { name = "Bundle of Wood", classID = 7 } })
    c.setBagItems({ { item = PAW, count = 2 } })
    c.setQuestLog({ row(GNOLL_Q, "Gnoll Trouble", "Gnoll Paw: 8/8", true),
                    row(ERRAND_Q, "Stormwind Errand", "Bundle of Wood: 0/1") })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon, id)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == id then return p.text end
    end
    return nil
end

tests["quest bags e2e: a paw from a handed-in quest is left over; unknown hand-in says nothing"] = function(t)
    local c, addon = start()
    local Q = ns.QuestBags
    t.eq(prompt(addon, Q.LEFTOVER_PROMPT), nil, "its quest is still in the log")
    c.setQuestLog({ row(ERRAND_Q, "Stormwind Errand", "Bundle of Wood: 0/1") })
    c.fire("QUEST_LOG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon, Q.LEFTOVER_PROMPT), nil, "hand-in not known")
    c.setQuestDone(GNOLL_Q, true)
    c.fire("QUEST_TURNED_IN", GNOLL_Q)
    c.advance(1, 5)
    t.eq(prompt(addon, Q.LEFTOVER_PROMPT), LEFT)
    c.setBagItems({})
    c.fire("BAG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon, Q.LEFTOVER_PROMPT), nil, "gone from the bags")
end

tests["quest bags e2e: the open vendor sells a quest item: buy line, gone when the window closes"] = function(t)
    local c, addon = start()
    local Q = ns.QuestBags
    t.eq(prompt(addon, Q.BUY_PROMPT), nil, "no vendor open")
    c.setMerchant({ { index = 1, item = WOOD, price = 100, stack = 1 } })
    c.setMerchantOpen(true)
    c.advance(1, 5)
    t.eq(prompt(addon, Q.BUY_PROMPT), BUY)
    c.setMerchantOpen(false)
    c.advance(1, 5)
    t.eq(prompt(addon, Q.BUY_PROMPT), nil)
end

tests["quest bags e2e: wares that cannot be read say nothing"] = function(t)
    local c, addon = start()
    c.setMerchant(nil)
    c.setMerchantOpen(true)
    c.advance(1, 5)
    t.eq(prompt(addon, ns.QuestBags.BUY_PROMPT), nil)
end


-- Parity row C-11 (lead section 609; Twin's review, section 622): a quest
-- item the player saw at the auction house, with no vendor price known, is
-- named to buy there, through Q.Declare on the fake client: Questie's item
-- ID, the player's own logged price (Items/AuctionLog.lua's saved shape).
-- Nothing is bought or bid. Made-up realm.
local NOW, REALM = 1700000000, "Realm1-Horde"

local function startAuction()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { prices = { auctionHistory = { [REALM] = {
        [PAW] = { h = { NOW - 60, 140 } },
    } } } } })
    c.setSaved(ns.id.charDB, {})
    c.setClock(NOW)
    c.setRealm("Realm1")
    c.setFaction("Horde")
    c.setItemInfo({ [PAW] = { name = "Gnoll Paw", classID = 12 } })
    c.setBagItems({})
    c.setQuestieModule("QuestieDB", { GetQuest = function(id)
        if id == GNOLL_Q then return { ObjectiveData = { { Type = "item", Id = PAW } } } end
        return nil
    end })
    c.setQuestLog({ row(GNOLL_Q, "Gnoll Trouble", "Gnoll Paw: 3/8") })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

tests["quest bags e2e auction: a Questie item with a logged auction price and no vendor price: the line"] = function(t)
    local _, addon = startAuction()
    local Q, coin = ns.QuestBags, ns.Prices.Coin
    t.eq(prompt(addon, Q.AUCTION_PROMPT), Q.AUCTION:format(5, "Gnoll Paw", "Gnoll Trouble", coin(140), coin(700)))
end

tests["quest bags e2e auction: with the setting off, nothing shows"] = function(t)
    local c, addon = startAuction()
    local Q = ns.QuestBags
    addon.settings:set(Q.SETTING, false)
    c.fire("QUEST_LOG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon, Q.AUCTION_PROMPT), nil)
end

return tests
