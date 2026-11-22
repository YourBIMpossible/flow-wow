local _, ns = ...

-- LootNote (L6-E, G8): when you loot something the sell rules would sell,
-- one chat line says so ("Junk: 2 x Broken Fang (4c each at a vendor)").
-- The rule is the sell list's: Disposition.Decide, with your never-sell list.
--
-- LOOK ONLY. It reads the loot chat line and the item's facts and prints a
-- note. It never loots, skips, auto-loots, sells, deletes or clicks, and it
-- needs no protected action: the note comes after the item is in your bags.
--
--   text = LootNote.Note(item, count, itemInfo, context)   pure; nil: no note
--   text = LootNote.FromClient(client, store, chatText)    nil: no note
--   api  = LootNote.Declare(k)        api.notes() = how many were printed
--
-- Reads (through the injected client):
--   CHAT_MSG_LOOT             the event; its first argument is the chat text
--   client.ownLoot(text)      CLIENT NEED: the item (link) and count when the
--                             line is the player's own loot, else nil. Without
--                             it nothing is noted: whose loot a line is about
--                             is never guessed.
--   client.itemInfo(item)     CLIENT NEED (as the sell list): name, quality,
--                             sellPrice, classID
-- Saved data (read only): char settings.sell.never.
-- Setting: "loot.junkNote" (bool, on by default); the row is the lead's to
-- add. Until it is there the note is on.
-- Not tested in game: the event and both reads are first guesses.

local LootNote = {}
ns.LootNote = LootNote

LootNote.NAME = "lootNote"
LootNote.SETTING = "loot.junkNote"
LootNote.EVENT = "CHAT_MSG_LOOT"

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function isWhole(n)
    return isCount(n) and n == math.floor(n)
end

-- The part of a decision (or of its rest) that sells.
local function sellPart(decision)
    local d = decision
    while type(d) == "table" do
        if d.action == "sell" then return d end
        d = d.rest
    end
    return nil
end

function LootNote.Note(item, count, itemInfo, context)
    local key = ns.Items.Key(item)
    if key == nil or type(itemInfo) ~= "function" then return nil end
    local ok, f = pcall(itemInfo, item)
    if not ok or type(f) ~= "table" then return nil end
    local entry = { key = key }
    if isCount(count) and count > 0 then entry.count = count end
    if type(f.name) == "string" and f.name ~= "" then entry.name = f.name end
    if isWhole(f.quality) then entry.quality = f.quality end
    if isCount(f.sellPrice) then entry.sellPrice = f.sellPrice end
    if isWhole(f.classID) then entry.classID = f.classID end
    local part = sellPart(ns.Disposition.Decide(entry, type(context) == "table" and context or {}))
    if not part then return nil end
    return ns.ItemPresent.LootNoteText(entry, part)
end

local function neverOf(store)
    local never = {}
    if type(store) == "table" and type(store.get) == "function" then
        local ok, raw = pcall(store.get, store, "char", "settings.sell.never")
        if ok and type(raw) == "table" then
            for k, v in pairs(raw) do
                local key = v and ns.Items.Key(k) or nil
                if key ~= nil then never[key] = true end
            end
        end
    end
    return never
end

function LootNote.FromClient(client, store, chatText)
    if type(client) ~= "table" then return nil end
    local own = client.ownLoot
    if type(own) ~= "function" then return nil end
    local ok, item, count = pcall(own, chatText)
    if not ok or item == nil then return nil end
    local read = client.itemInfo
    return LootNote.Note(item, count, type(read) == "function" and read or nil,
        { choices = { never = neverOf(store) } })
end

function LootNote.Declare(k)
    local api = {}
    local printed = 0
    function api.notes() return printed end
    k:Module({
        name = LootNote.NAME,
        needs = { "client", "store", "bus", "settings" },
        provides = { Notes = api.notes },
        start = function(ctx)
            ctx.bus:on(LootNote.NAME, LootNote.EVENT, function(chatText)
                if ctx.settings:get(LootNote.SETTING) == false then return end
                local text = LootNote.FromClient(ctx.client, ctx.store, chatText)
                if not text then return end
                printed = printed + 1
                local id = k.id or ns.id
                ctx.client.print(id.title .. ": " .. text)
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.lootNote = LootNote.Declare(ns)
