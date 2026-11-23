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
--   text = LootNote.FromClient(client, store, chatText, r)  nil: no note
--                                     r: the reservations evaluation now
--                                     (UI/SellList.lua SellList.Current).
--                                     What a goal holds is kept, not noted
--                                     to sell; r unavailable, or not given,
--                                     gives no note (lead section 220, SR-1:
--                                     no sell advice on any path while the
--                                     reservations can't be worked out).
--   item, count = LootNote.Own(client, chatText)   the player's own loot
--                                     line read, or nil (another player's,
--                                     not loot, or the read raised)
--   text = LootNote.FromItem(client, store, item, count, r)   FromClient
--                                     past the read. Section 225 (LR-1): the
--                                     module reads the line and applies the
--                                     REPEAT_S throttle first, and works out
--                                     the reservations only for a line that
--                                     can still be noted.
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
-- Docs (warcraft.wiki.gg, Event CHAT_MSG_LOOT): the name matches; the line is
-- its first value. The reads: see Core/Client.lua.

local LootNote = {}
ns.LootNote = LootNote

LootNote.NAME = "lootNote"
LootNote.SETTING = "loot.junkNote"
LootNote.EVENT = "CHAT_MSG_LOOT"
LootNote.REPEAT_S = 60     -- the same item is noted again only after this long; a first guess

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
            -- A set ({ [item] = true }) or a list ({ item, ... }), as
            -- the sell list reads it.
            for k, v in pairs(raw) do
                local key
                if type(k) == "number" and k == math.floor(k) and k >= 1 and k <= #raw and v ~= true then
                    key = ns.Items.Key(v)
                elseif v then
                    key = ns.Items.Key(k)
                end
                if key ~= nil then never[key] = true end
            end
        end
    end
    return never
end

function LootNote.Own(client, chatText)
    if type(client) ~= "table" then return nil end
    local own = client.ownLoot
    if type(own) ~= "function" then return nil end
    local ok, item, count = pcall(own, chatText)
    if not ok or item == nil then return nil end
    return item, count
end

function LootNote.FromClient(client, store, chatText, r)
    local item, count = LootNote.Own(client, chatText)
    if item == nil then return nil end
    return LootNote.FromItem(client, store, item, count, r)
end

function LootNote.FromItem(client, store, item, count, r)
    if type(client) ~= "table" then return nil end
    local R = ns.Reservations
    if type(r) ~= "table" or r.status == R.UNAVAILABLE then return nil end
    local read = client.itemInfo
    local text = LootNote.Note(item, count, type(read) == "function" and read or nil,
        { choices = { never = neverOf(store) }, grants = R.HeldIn(R.Grants(r), "bags") })
    if not text then return nil end
    return text, ns.Items.Key(item)
end

function LootNote.Declare(k)
    local api = {}
    local printed, quiet = 0, 0
    -- When each item was last noted: [key] = the client's uptime, or true
    -- when the client gave no time. In memory only.
    local notedAt = {}
    function api.notes() return printed end
    function api.quieted() return quiet end
    k:Module({
        name = LootNote.NAME,
        needs = { "client", "store", "bus", "settings" },
        provides = { Notes = api.notes },
        start = function(ctx)
            ctx.bus:on(LootNote.NAME, LootNote.EVENT, function(chatText)
                if ctx.settings:get(LootNote.SETTING) == false then return end
                -- Section 225 (LR-1): every loot line in chat comes here,
                -- other players' too. The line is read first, then the
                -- throttle; only then are the reservations worked out (the
                -- bag read, the goal claims), so a line that can't be noted
                -- costs no evaluation.
                local item, count = LootNote.Own(ctx.client, chatText)
                if item == nil then return end
                local key = ns.Items.Key(item)
                -- No flood while grinding: one note per item per REPEAT_S
                -- seconds; with no time from the client, once a session.
                local now = type(ctx.client.uptime) == "function" and ctx.client.uptime() or nil
                if type(now) ~= "number" or now ~= now then now = nil end
                local last = key ~= nil and notedAt[key] or nil
                if last ~= nil and (now == nil or last == true or now - last < LootNote.REPEAT_S) then
                    quiet = quiet + 1
                    return
                end
                -- The reservations now: one evaluation for this loot.
                local r = ns.SellList.Current(ctx.use)
                local text = LootNote.FromItem(ctx.client, ctx.store, item, count, r)
                if not text then return end
                if key ~= nil then notedAt[key] = now or true end
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
