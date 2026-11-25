local _, ns = ...

-- Quest items in the bags (S41, lead dispatch section 395 item 1), shown as
-- advisor prompts:
--   leftover  a quest item (the game's item class 12) in the bags whose
--             every quest that asked for it has left the log and is known
--             handed in: "Gnoll Paw is left over from a finished quest: you
--             can sell or destroy it."
--   buy       while a vendor window is open, an item it sells that an open
--             objective of a quest in the log still needs: "Buy Bundle of
--             Wood from a vendor for the quest Stormwind Errand."
--   hand in   (parity row C-10) a quest item in the bags whose quest is in
--             the log and complete: "Gnoll Paw is for Gnoll Trouble, which
--             is ready to hand in."
--   auction   (parity row C-11, lead section 603) an item an open objective
--             still needs, with an auction price this player saw
--             (Items/AuctionLog.lua) and no vendor price known (the price
--             book's "vendor" kind): "Buy 5 Earthroot at the auction house
--             for the quest Gathering the Cure: about 12s each when you
--             last looked (1g)." The item's ID is Questie's (the quest's
--             ObjectiveData[i], Type "item", as UI/PlateQuests.lua reads
--             it); without Questie nothing is said. As Flow
--             Modules/Quests/QuestBuy.lua QB.Steps / QB.Line: a price seen
--             at the auction house is the test that it can be bought there.
--             Flow also made it an optional route step near an auctioneer;
--             here it is words only.
-- And, for another module to show (C-10, data only; a window is the
-- drawing lane's): Answers(), for each quest item in the bags, why it is
-- held and what to do with it. As Flow's Modules/Quests/QuestBags.lua
-- (QG.QuestOf :55-63 and its answers): "handIn" (Flow's turnin: its quest
-- is complete), "keep" (Flow's finish: its quest is in progress), "drop"
-- (Flow's sell: every quest that asked for it was handed in), and
-- "unknown" where the quest, or whether it was handed in, is not known
-- (nothing is advised). Not here: Flow's "bank" and "stuck", which need the
-- route's steps of a quest, and Flow's sell price.
-- Which quest asked for which item is learned from the player's own quest
-- log (objective text "Name: 3/8"), never from a table. An item never seen
-- asked for, a hand-in not known, an item kind not read, a log, bag or
-- vendor list that cannot be read: nothing is said.
-- ADVICE ONLY. Nothing here sells, destroys, buys, moves or uses anything.
--
-- Pure parts:
--   Q.ObjectiveItem(text)               the item name of "Name: n/m", or nil
--   Q.Learn(owners, rows)               adds { [name] = { [questId] = title } }
--   Q.Leftovers(owners, rows, bag, done) the leftover names, bag order, once
--   Q.LeftoverText(names)               the line, or nil
--   Q.WareName(ware, info)              a ware's item name, or nil
--   Q.ToBuy(rows, wares)                { { item, quest }, ... }
--   Q.BuyText(list)                     the line, or nil
--   Q.Answers(owners, rows, bag, done)  { { item, answer, quest, questId } },
--                                       bag order, each item once; {} when
--                                       the log, the bags or the hand-in
--                                       read is not there
--   Q.AnswerLine(row)                   one answer as a line, or nil
--   Q.HandInText(answers)               the hand-in prompt, or nil
-- Module: ns.use("questBags").Answers() -> the answers now (not held back
-- by the setting, which is for the prompts).
--   Q.AuctionBuys(rows, itemOf, ahPrice, vendorSells)
--                                       { { item, quest, left, price }, ... }
--   Q.AuctionText(list, coin)           the line, or nil
--
-- Reads (existing, Core/Client.lua): questLog (through ns.Nav.QuestLogRows),
-- questDone, bagItems, itemInfo, merchantItems, watchMerchant.
-- Saved data: char "learned.questItemOwners".
-- Setting (char, on by default): items.questBags "Quest items in your bags".
-- Not seen in game: that objective text is "Name: n/m" on this client.

local Q = {}
ns.QuestBags = Q

Q.NAME = "questBags"
Q.PATH = "learned.questItemOwners"
Q.SETTING = "items.questBags"
Q.LEFTOVER_PROMPT = "items.questLeftover"
Q.BUY_PROMPT = "items.questBuy"
Q.HANDIN_PROMPT = "items.questHandIn"
Q.HAND_IN, Q.KEEP, Q.DROP, Q.UNKNOWN = "handIn", "keep", "drop", "unknown"
Q.LINES = {
    handIn = "%s: for %s, which is ready to hand in. Hand it in.",
    keep = "%s: for %s, still in progress. Keep it.",
    drop = "%s: left over from %s, which you handed in. You can sell or destroy it.",
}
Q.LINE_NO_QUEST = "%s: a quest item, but which quest it is for is not known."
Q.LINE_NOT_KNOWN = "%s: for %s, which is not in your log; whether you handed it in is not known."
Q.HANDIN_ONE = "%s is for %s, which is ready to hand in."
Q.HANDIN_MANY = "Quest items ready to hand in: %s."
Q.PRIORITY = 2
Q.QUEST_CLASS = 12
Q.MAX_NAMES = 3

Q.LEFT_ONE = "%s is left over from a finished quest: you can sell or destroy it."
Q.LEFT_MANY = "%s are left over from finished quests: you can sell or destroy them."
Q.BUY = "Buy %s from a vendor for the quest %s."
Q.AUCTION_PROMPT = "items.questAuction"
Q.AUCTION = "Buy %d %s at the auction house for the quest %s: about %s each when you last looked (%s)."
Q.AUCTION_ONE_MORE = " 1 more item too."
Q.AUCTION_MORE = " %d more items too."

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function Q.ObjectiveItem(text)
    if type(text) ~= "string" then return nil end
    local name = text:match("^%s*(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
    if name == nil or name == "" then return nil end
    return name
end

function Q.Learn(owners, rows)
    if type(owners) ~= "table" or type(rows) ~= "table" then return end
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.id ~= nil and type(r.objectives) == "table" then
            for _, o in ipairs(r.objectives) do
                local name = type(o) == "table" and Q.ObjectiveItem(o.text) or nil
                if name then
                    if type(owners[name]) ~= "table" then owners[name] = {} end
                    owners[name][r.id] = r.title
                end
            end
        end
    end
end

function Q.Leftovers(owners, rows, bag, done)
    local out = {}
    if type(owners) ~= "table" or type(rows) ~= "table" or type(bag) ~= "table" or type(done) ~= "function" then
        return out
    end
    local inLog = {}
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.id ~= nil then inLog[r.id] = true end
    end
    local seen = {}
    for _, e in ipairs(bag) do
        local name = type(e) == "table" and e.name or nil
        local quests = type(name) == "string" and owners[name] or nil
        if not seen[name or false] and e.classID == Q.QUEST_CLASS and type(quests) == "table" and next(quests) ~= nil then
            local left = true
            for id in pairs(quests) do
                if inLog[id] or done(id) ~= true then left = false end
            end
            if left then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    return out
end

-- C-10: for each quest item in the bags, the quest it is for and what to
-- do with it. A complete quest in the log comes first (its hand-in frees
-- the slot), then one in progress; with none in the log, "drop" only when
-- every quest that asked for it is known handed in.
function Q.Answers(owners, rows, bag, done)
    local out = {}
    if type(owners) ~= "table" or type(rows) ~= "table" or type(bag) ~= "table"
        or type(done) ~= "function" then
        return out
    end
    local inLog = {}
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.id ~= nil then inLog[r.id] = r end
    end
    local seen = {}
    for _, e in ipairs(bag) do
        local name = type(e) == "table" and e.name or nil
        if type(name) == "string" and name ~= "" and e.classID == Q.QUEST_CLASS and not seen[name] then
            seen[name] = true
            local quests = type(owners[name]) == "table" and owners[name] or {}
            -- The quests in a fixed order, so the answer does not change by itself.
            local ids = {}
            for id in pairs(quests) do ids[#ids + 1] = id end
            table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
            local ready, open, left, allDone = nil, nil, nil, #ids > 0
            for _, id in ipairs(ids) do
                local r = inLog[id]
                if r then
                    allDone = false
                    if r.complete == true and r.failed ~= true then
                        ready = ready or id
                    else
                        open = open or id
                    end
                else
                    left = left or id
                    if done(id) ~= true then allDone = false end
                end
            end
            local row = { item = name }
            local id = ready or open
            if ready then
                row.answer = Q.HAND_IN
            elseif open then
                row.answer = Q.KEEP
            elseif allDone then
                row.answer, id = Q.DROP, left
            else
                row.answer, id = Q.UNKNOWN, left
            end
            if id ~= nil then
                row.questId = id
                local title = inLog[id] and inLog[id].title or quests[id]
                if type(title) == "string" and title ~= "" then row.quest = title end
            end
            out[#out + 1] = row
        end
    end
    return out
end

function Q.AnswerLine(row)
    if type(row) ~= "table" or type(row.item) ~= "string" then return nil end
    local quest = type(row.quest) == "string" and row.quest or nil
    local line = Q.LINES[row.answer]
    if line and quest then return line:format(row.item, quest) end
    if quest then return Q.LINE_NOT_KNOWN:format(row.item, quest) end
    return Q.LINE_NO_QUEST:format(row.item)
end

function Q.HandInText(answers)
    if type(answers) ~= "table" then return nil end
    local ready = {}
    for _, row in ipairs(answers) do
        if type(row) == "table" and row.answer == Q.HAND_IN and type(row.item) == "string"
            and type(row.quest) == "string" then
            ready[#ready + 1] = row
        end
    end
    if #ready == 0 then return nil end
    if #ready == 1 then return Q.HANDIN_ONE:format(ready[1].item, ready[1].quest) end
    local parts = {}
    for i = 1, math.min(#ready, Q.MAX_NAMES) do parts[i] = ready[i].item .. " (" .. ready[i].quest .. ")" end
    local line = table.concat(parts, ", ")
    if #ready > #parts then line = string.format("%s and %d more", line, #ready - #parts) end
    return Q.HANDIN_MANY:format(line)
end

local function names(list)
    local shown = {}
    for i = 1, math.min(#list, Q.MAX_NAMES) do shown[i] = tostring(list[i]) end
    local line = table.concat(shown, ", ")
    if #list > #shown then line = string.format("%s and %d more", line, #list - #shown) end
    return line
end

function Q.LeftoverText(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    if #list == 1 then return Q.LEFT_ONE:format(tostring(list[1])) end
    return Q.LEFT_MANY:format(names(list))
end

function Q.WareName(ware, info)
    local item = type(ware) == "table" and ware.item or nil
    if item == nil then return nil end
    local facts = type(info) == "function" and info(item) or nil
    if type(facts) == "table" and type(facts.name) == "string" and facts.name ~= "" then return facts.name end
    if type(item) == "string" then
        local name = item:match("|h%[(.-)%]|h")
        if name and name ~= "" then return name end
    end
    return nil
end

function Q.ToBuy(rows, wares)
    local out = {}
    if type(rows) ~= "table" or type(wares) ~= "table" then return out end
    local sold = {}
    for _, w in ipairs(wares) do
        local name = type(w) == "table" and w.name or nil
        if type(name) == "string" and name ~= "" then sold[name] = true end
    end
    local seen = {}
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.complete ~= true and r.failed ~= true and type(r.title) == "string"
            and type(r.objectives) == "table" then
            for _, o in ipairs(r.objectives) do
                local name = type(o) == "table" and o.done ~= true and Q.ObjectiveItem(o.text) or nil
                if name and sold[name] and not seen[name] then
                    seen[name] = true
                    out[#out + 1] = { item = name, quest = r.title }
                end
            end
        end
    end
    return out
end

function Q.BuyText(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local lines = {}
    for i = 1, #list do lines[i] = Q.BUY:format(tostring(list[i].item), tostring(list[i].quest)) end
    return table.concat(lines, " ")
end

-- "Name: n/m" -> m - n, or nil.
local function leftOf(text)
    if type(text) ~= "string" then return nil end
    local have, need = text:match(":%s*(%d+)%s*/%s*(%d+)%s*$")
    have, need = tonumber(have), tonumber(need)
    if not have or not need or need <= have then return nil end
    return need - have
end

function Q.AuctionBuys(rows, itemOf, ahPrice, vendorSells)
    local out, seen = {}, {}
    if type(rows) ~= "table" or type(itemOf) ~= "function" or type(ahPrice) ~= "function" then return out end
    for _, r in ipairs(rows) do
        if type(r) == "table" and r.complete ~= true and r.failed ~= true and type(r.title) == "string"
            and type(r.objectives) == "table" then
            for i, o in ipairs(r.objectives) do
                local name, left
                if type(o) == "table" and o.done ~= true then name = Q.ObjectiveItem(o.text) end
                if name then left = leftOf(o.text) end
                local okId, id = false, nil
                if left then okId, id = pcall(itemOf, r.id, i) end
                if okId and type(id) == "number" and not seen[id] then
                    local okV, sold = true, false
                    if type(vendorSells) == "function" then okV, sold = pcall(vendorSells, id) end
                    local okP, price = pcall(ahPrice, id)
                    if okV and sold ~= true and okP and type(price) == "number" and price == price
                        and price > 0 and price < math.huge then
                        seen[id] = true
                        out[#out + 1] = { item = name, quest = r.title, left = left, price = price }
                    end
                end
            end
        end
    end
    return out
end

function Q.AuctionText(list, coin)
    if type(list) ~= "table" or #list == 0 or type(coin) ~= "function" then return nil end
    local f = list[1]
    local line = Q.AUCTION:format(f.left, tostring(f.item), tostring(f.quest), coin(math.floor(f.price)),
        coin(math.ceil(f.left * f.price)))
    if #list == 2 then line = line .. Q.AUCTION_ONE_MORE
    elseif #list > 2 then line = line .. Q.AUCTION_MORE:format(#list - 1) end
    return line
end

local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_REMOVED", "BAG_UPDATE",
                 "MERCHANT_SHOW", "MERCHANT_CLOSED" }

function Q.Declare(k)
    local api = {}
    local refresh, answersNow

    -- C-10: the answers as of now, {} before the module starts.
    function api.Answers()
        if answersNow then return answersNow() end
        return {}
    end

    k:Module({
        name = Q.NAME,
        needs = { "client", "store", "bus", "settings", "advisor" },
        provides = { Answers = api.Answers },
        settings = { {
            key = Q.SETTING, scope = "char", type = "bool", default = true,
            label = "Quest items in your bags",
            help = "Names quest items left over from quests you have handed in, quest items whose quest is "
                .. "ready to hand in, and items a vendor you have open sells that a quest in your log needs, "
                .. "or that you saw at the auction house. "
                .. "It only advises: nothing is sold, destroyed, bought, posted or handed in.",
            group = "bags",
            synonyms = { "quest", "leftover", "vendor", "buy", "bags", "sell" },
        } },
        ticks = { { every = 5, when = "outOfCombat", run = function() if refresh then refresh() end end } },
        start = function(ctx)
            local advisor = ctx.use("advisor")
            if type(advisor) ~= "table" then return end
            local client = ctx.client
            local shown = {}

            local function show(id, text)
                if text == shown[id] then return end
                if text then advisor.Add(id, text, Q.PRIORITY) else advisor.Remove(id) end
                shown[id] = text
            end

            local function info(item) return ask(client, "itemInfo", item) end

            local function bag()
                local stacks = ask(client, "bagItems")
                if type(stacks) ~= "table" then return nil end
                local out = {}
                for i, s in ipairs(stacks) do
                    local f = type(s) == "table" and info(s.item) or nil
                    out[i] = type(f) == "table" and { name = f.name, classID = f.classID } or {}
                end
                return out
            end

            local function wares()
                local list = ask(client, "merchantItems")
                if type(list) ~= "table" then return nil end
                local out = {}
                for i, w in ipairs(list) do out[i] = { name = Q.WareName(w, info) } end
                return out
            end

            local function doneOf(id) return ask(client, "questDone", id) end

            answersNow = function()
                local rows = ns.Nav.QuestLogRows(client)
                local owners = ctx.store:table("char", Q.PATH)
                if type(rows) == "table" and type(owners) == "table" then Q.Learn(owners, rows) end
                return Q.Answers(owners, rows, bag(), doneOf)
            end

            -- C-11 reads: Questie's item ID for objective i, the last auction
            -- price seen here, whether a vendor price is known.
            local function itemOf(quest, i)
                local db = ask(client, "questieModule", "QuestieDB")
                if type(db) ~= "table" or type(db.GetQuest) ~= "function" then return nil end
                local okQ, q = pcall(db.GetQuest, quest)
                local od = okQ and type(q) == "table" and type(q.ObjectiveData) == "table" and q.ObjectiveData[i]
                if type(od) ~= "table" or od.Type ~= "item" then return nil end
                local id = od.Id
                if type(id) == "table" then id = id[1] end
                return type(id) == "number" and id or nil
            end
            local function ahPrice(id)
                local AL = ns.AuctionLog
                local e = AL and AL.Read(ctx.store, client, id)
                local h
                if type(e) == "table" then h = e.h end
                return type(h) == "table" and #h >= 2 and h[#h] or nil
            end
            local function vendorSells(id)
                local book = ctx.store:get("account", "learned.prices")
                local key = ns.Items and ns.Items.Key(id)
                if type(book) ~= "table" or key == nil then return false end
                local p = ns.Prices.Get(book, key, "vendor")
                return type(p) == "table" and type(p.value) == "number"
            end

            refresh = function()
                local rows = ns.Nav.QuestLogRows(client)
                local owners = ctx.store:table("char", Q.PATH)
                if type(rows) == "table" and type(owners) == "table" then Q.Learn(owners, rows) end
                local left, buy, handIn, auction
                if ctx.settings:get(Q.SETTING) ~= false and type(rows) == "table" then
                    handIn = Q.HandInText(Q.Answers(owners, rows, bag(), doneOf))
                    left = Q.LeftoverText(Q.Leftovers(owners, rows, bag(),
                        function(id) return ask(client, "questDone", id) end))
                    if ask(client, "merchantOpen") == true then buy = Q.BuyText(Q.ToBuy(rows, wares())) end
                    auction = Q.AuctionText(Q.AuctionBuys(rows, itemOf, ahPrice, vendorSells), ns.Prices.Coin)
                end
                show(Q.LEFTOVER_PROMPT, left)
                show(Q.HANDIN_PROMPT, handIn)
                show(Q.BUY_PROMPT, buy)
                show(Q.AUCTION_PROMPT, auction)
            end

            ask(client, "watchMerchant")
            for _, ev in ipairs(EVENTS) do
                ctx.bus:on(Q.NAME, ev, refresh)
            end
            refresh()
        end,
        stop = function()
            refresh, answersNow = nil, nil
        end,
    })
    return api
end

ns.questBags = Q.Declare(ns)
