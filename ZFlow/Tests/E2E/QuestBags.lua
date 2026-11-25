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

-- Parity row C-10 (lead section 664). Fails before: no Answers, no hand-in prompt.
tests["quest bags e2e: a quest ready to hand in says so for its item, and the answers are there to ask"] = function(t)
    local c, addon = start()
    local Q = ns.QuestBags
    t.eq(prompt(addon, Q.HANDIN_PROMPT), nil, "the quest is not complete yet")
    local answers = addon.use(Q.NAME).Answers()
    t.eq(answers, { { item = "Gnoll Paw", answer = "keep", quest = "Gnoll Trouble", questId = GNOLL_Q } })
    local ready = row(GNOLL_Q, "Gnoll Trouble", "Gnoll Paw: 8/8", true)
    ready.complete = true
    -- C-10 CHANGES-1: said only with the bags nearly full (Flow's rule).
    c.setBags({ { bag = 0, free = 2, total = 16, family = 0 } })
    c.setQuestLog({ ready })
    c.fire("QUEST_LOG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon, Q.HANDIN_PROMPT), "Gnoll Paw is for Gnoll Trouble, which is ready to hand in.")
    t.eq(addon.use(Q.NAME).Answers()[1].answer, "handIn")
    c.setBagItems({})
    c.fire("BAG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon, Q.HANDIN_PROMPT), nil, "gone from the bags")
    t.eq(addon.use(Q.NAME).Answers(), {})
end

tests["quest bags e2e: with the setting off no hand-in is said, and the answers can still be asked"] = function(t)
    local c, addon = start()
    local Q = ns.QuestBags
    addon.settings:set(Q.SETTING, false)
    local ready = row(GNOLL_Q, "Gnoll Trouble", "Gnoll Paw: 8/8", true)
    ready.complete = true
    c.setQuestLog({ ready })
    c.fire("QUEST_LOG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon, Q.HANDIN_PROMPT), nil)
    t.eq(addon.use(Q.NAME).Answers()[1].answer, "handIn")
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

-- C-10 CHANGES-1 (Twin, lead section 730; owner section 563, "Flow does
-- this perfectly"): as Flow's Modules/Quests/QuestBags.lua (:221, through
-- ns.BagsNearlyFull, Core.lua :103-106: 3 free slots or fewer), the
-- hand-in is said only when the bags are nearly full. With room, or bags
-- not read, nothing. The answers stay as built. Fails before: said always.
tests["quest bags e2e: a quest ready to hand in is said only with the bags nearly full"] = function(t)
    local c, addon = start()
    local Q = ns.QuestBags
    local ready = row(GNOLL_Q, "Gnoll Trouble", "Gnoll Paw: 8/8", true)
    ready.complete = true
    c.setBags({ { bag = 0, free = 4, total = 16, family = 0 }, { bag = 1, free = 6, total = 16, family = 0 } })
    c.setQuestLog({ ready })
    c.fire("QUEST_LOG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon, Q.HANDIN_PROMPT), nil, "room to spare: not said")
    t.eq(addon.use(Q.NAME).Answers()[1].answer, "handIn", "the answer is still there to ask")
    c.setBags({ { bag = 0, free = 1, total = 16, family = 0 }, { bag = 1, free = 2, total = 16, family = 0 } })
    c.fire("BAG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon, Q.HANDIN_PROMPT), "Gnoll Paw is for Gnoll Trouble, which is ready to hand in.", "3 free: said")
    c.setBags(nil)
    c.fire("BAG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon, Q.HANDIN_PROMPT), nil, "bags not read: not said")
end

-- C-10 CHANGES-2 (lead section 734; owner section 563): the free count is
-- Flow's Export.lua X.BagsFree (:94-102): every bag 0 to 4, of any kind,
-- a bag that cannot be read skipped; nil only when no bag reads.
tests["quest bags: nearly full is Flow's 3 free slots, counted as Flow counts them"] = function(t)
    local Q = ns.QuestBags
    t.eq(Q.NEARLY_FULL, 3)
    t.eq(Q.Free({ { bag = 0, free = 2, family = 0 }, { bag = 1, free = 1 }, { bag = 2, free = 9, family = 8 } }), 12,
        "a special bag's free slots count too")
    t.eq(Q.Free({ { bag = 0, free = 2 }, { bag = 1, free = "x" }, { bag = 2, free = 1 } }), 3, "a bag not read is skipped")
    t.eq(Q.Free({ { bag = 0, free = 2 }, { bag = 5, free = 20 }, { bag = -1, free = 28 } }), 2, "only bags 0 to 4")
    t.eq(Q.Free({ { free = 2 }, { free = 1 } }), 3, "rows with no bag number: in order, the first five")
    t.eq(Q.Free(nil), nil)
    t.eq(Q.Free({ { bag = 0, free = "x" } }), nil, "no bag reads: not known")
    local answers = { { item = "Gnoll Paw", answer = "handIn", quest = "Gnoll Trouble" } }
    t.eq(Q.HandInText(answers, 4), nil, "4 free: not said")
    t.ok(Q.HandInText(answers, 3) ~= nil, "3 free: said")
    t.eq(Q.HandInText(answers, nil), nil, "not read: not said")
end

return tests
