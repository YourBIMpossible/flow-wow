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
Q.PRIORITY = 2
Q.QUEST_CLASS = 12
Q.MAX_NAMES = 3

Q.LEFT_ONE = "%s is left over from a finished quest: you can sell or destroy it."
Q.LEFT_MANY = "%s are left over from finished quests: you can sell or destroy them."
Q.BUY = "Buy %s from a vendor for the quest %s."

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

local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_REMOVED", "BAG_UPDATE",
                 "MERCHANT_SHOW", "MERCHANT_CLOSED" }

function Q.Declare(k)
    local api = {}
    local refresh

    k:Module({
        name = Q.NAME,
        needs = { "client", "store", "bus", "settings", "advisor" },
        settings = { {
            key = Q.SETTING, scope = "char", type = "bool", default = true,
            label = "Quest items in your bags",
            help = "Names quest items left over from quests you have handed in, and items a vendor you have "
                .. "open sells that a quest in your log needs. It only advises: nothing is sold, destroyed or bought.",
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

            refresh = function()
                local rows = ns.Nav.QuestLogRows(client)
                local owners = ctx.store:table("char", Q.PATH)
                if type(rows) == "table" and type(owners) == "table" then Q.Learn(owners, rows) end
                local left, buy
                if ctx.settings:get(Q.SETTING) ~= false and type(rows) == "table" then
                    left = Q.LeftoverText(Q.Leftovers(owners, rows, bag(),
                        function(id) return ask(client, "questDone", id) end))
                    if ask(client, "merchantOpen") == true then buy = Q.BuyText(Q.ToBuy(rows, wares())) end
                end
                show(Q.LEFTOVER_PROMPT, left)
                show(Q.BUY_PROMPT, buy)
            end

            ask(client, "watchMerchant")
            for _, ev in ipairs(EVENTS) do
                ctx.bus:on(Q.NAME, ev, refresh)
            end
            refresh()
        end,
        stop = function()
            refresh = nil
        end,
    })
    return api
end

ns.questBags = Q.Declare(ns)
