-- Sell list (L6-A): while a merchant window is open, a window lists what
-- Z-Flow would sell (Items/Sell.lua with Disposition's rules), and below it
-- what is kept and why.
--
-- The window is one of the shared window kit's (UI/Kit.lua, lead sections
-- 287, 291 item 3 and 303): an item line for each row, with its icon, its
-- name in the item's quality colour, its count and its price as coins. A
-- price shows as coins only when it was observed; an estimate or a price
-- nobody has seen is a note in Items/Present.lua's own words (F-085). The
-- footer holds the observed total and an empty slot, SellList.SLOT, where
-- the lane that owns selling puts its button. A client that cannot draw
-- the kit gets the same listing as text on a plain panel.
--
-- The "Sell these" button (lead section 337 item 1) is the footer's kit
-- button: Items/SellThese.lua sells the rows the window shows, on the
-- player's click only; this file draws the button, says on it why it
-- can't be pressed, and shows the note after a run. Nothing is sold when
-- a merchant opens, and the text panel has no button.
--
-- LOOK ONLY. This file makes no button and nothing here sells, buys,
-- deletes, moves or clicks anything; selling is a separate decision (G2)
-- that this file does not make. It reads the bags, the item facts, the
-- player's never-sell list and the saved price book, and draws them.
--
--   SellList.Lines(client, store, grants, r) -> lines   one listing as text;
--                                     r missing: unavailable (SR-3)
--   SellList.TreeOf(listing, client, id, action): action (optional) =
--                                     { button = a kit button for the
--                                     footer, note = { text, tone } shown
--                                     first in the list }
--   SellList.Tree(client, store, grants, r, id) -> a Kit.Window spec of the
--                                     same listing. id: the identity for
--                                     the title (default ns.id)
--   SellList.Listing(client, store, grants, r) -> one listing, worked out
--                                     once; LinesOf(listing) and
--                                     TreeOf(listing, client, id) word it
--   SellList.Declare(k)           -> api       declares the module on kernel k
--     api.last()   the lines of the last listing, nil before the first
--     api.shows()  how many listings were made since the start
--     api.show()   lists now and shows the window, when asked for: only
--                  while a merchant window is open. -> true, or false and why
--     api.window() the kit window's handle (h.slot(SellList.SLOT) is the
--                  footer's slot), nil when the kit did not draw
--   ns.use(SellList.NAME) -> { Last = api.last, Shows = api.shows,
--                              Show = api.show, Window = api.window }
--   Show() is for the merchant window's Z-Flow button (UI/WindowButtons.lua):
--   the player asked, so it shows even with "vendor.list" off; that setting
--   only governs showing by itself when a merchant opens.
--
-- Setting: "vendor.list" (bool, on by default). The row is the lead's to add
-- to the settings model; until it is there, the list is on. Off: nothing is
-- read and the panel stays hidden.
--
-- Reads (through the injected client):
--   client.watchMerchant / MERCHANT_SHOW / MERCHANT_CLOSED   the window
--   client.bagItems()                                        the bag stacks
--   client.itemInfo(item)    CLIENT NEED: name, quality, sell price, class
--   client.itemTexture(item)   the item's icon: a texture name or file number
--   client.kitWindow(id, tree, extra)   the window (client.panel when the
--                                       kit cannot draw)
-- Saved data (read only): the character's never-sell list at
-- settings.sell.never (imported from Flow) and the price book at
-- learned.prices (account).
-- Saved data (written): where the player left the window and its size, at
-- SellList.LAYOUT (account), as UI/BossLoot.lua saves its panel's place.
-- Reservations (lead section 209): one evaluation per merchant visit
-- (ns.use(Reservations.NAME).Current, made at the first listing of the visit
-- and kept until the window closes; dropped and listed once again when
-- Reservations.CHANGED says the claims changed, lead section 218). What it
-- holds in the bags
-- (Reservations.HeldIn(grants, "bags")) goes to Disposition as the grants,
-- so a held part is kept, not offered. "none" (no producer, or nothing
-- claimed) changes nothing. "unavailable" (a producer failed, or the module
-- is not there) offers nothing for sale and says the reservations are not
-- known, as the bank list does (UI/BankList.lua).
-- Lead section 340: every bag item neither offered nor kept by a rule has a
-- row under "Not sold, and why" (no vendor price, price not read yet,
-- reservations not known, no rule sells it); the list is made again on
-- GET_ITEM_INFO_RECEIVED; the first grey item and what was done with it go
-- to the saved diagnostics (diag.sellGrey, read by tools/zflow-read-diag.ps1).
-- Not tested in game: MERCHANT_SHOW and the item read are first guesses.
local _, ns = ...

local SellList = ns.SellList or {}
ns.SellList = SellList

SellList.NAME = "sellList"
-- The bags changed (one event after a burst of changes): the list is made
-- again while a merchant window is open. A first guess: not seen in game.
SellList.BAG_EVENT = "BAG_UPDATE_DELAYED"
SellList.SETTING = "vendor.list"
SellList.WIDTH, SellList.HEIGHT = 340, 260              -- the text panel
SellList.KIT_ID = "SellList"
SellList.KIT_WIDTH, SellList.KIT_HEIGHT = 420, 480
SellList.LIST_HEIGHT = 360
SellList.LAYOUT = "layout.sellList"     -- account: { point, width, height }
-- The footer's slot: left empty here. The lane that owns the player's sell
-- click puts its button in it (handle.slot(SellList.SLOT)).
SellList.SLOT = "sellAction"
SellList.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 360, -120 }
SellList.NEVER_PATH = "settings.sell.never"
SellList.PRICES_PATH = "learned.prices"
-- Why Show() showed nothing (for the caller; not player text).
SellList.NOT_STARTED = "the sell list has not started"
SellList.NO_MERCHANT = "no merchant window is open"
SellList.NO_PANEL = "this client cannot draw the panel"
-- Player text when the reservations could not be worked out.
SellList.RESERVATIONS_UNKNOWN = "Reservations not known: nothing is offered for sale, as what your goals hold is not known."
-- The kit window's own words. The same meaning as the line above, as what
-- is missing and what follows from it.
SellList.TITLE = "Sell list"
SellList.SELL_SECTION = "To sell"
SellList.KEPT_SECTION = "Kept, and why"
SellList.TOTAL = "Total"
SellList.NO_TOTAL = "No total"
-- The footer when some rows are not in the total, and when none is.
SellList.TOTAL_SEEN = "Total of the prices seen"
SellList.PRICES_UNKNOWN = "Prices not known"
-- Items in the bags whose facts were not read yet: not "nothing to sell".
SellList.ITEMS_UNREAD_HEAD = "Items not read yet"
SellList.ITEMS_UNREAD_HOW = "Reopen the merchant window to list them."
SellList.NOTHING = "Nothing to sell."
-- The bags read as holding no item at all (owner, 2026-11-23): said apart
-- from bags that hold only things not to sell.
SellList.BAGS_EMPTY = "No items were found in your bags. If they are not empty, reopen the merchant window."
SellList.UNKNOWN_HEAD = "Reservations not known"
SellList.UNKNOWN_HOW = "Nothing is offered for sale until what your goals hold is known."
SellList.UNREAD_HEAD = "Can't list what to sell"
SellList.CLOSED_HEAD = "No merchant window is open."
SellList.CLOSED_HOW = "Talk to a merchant to see what would be sold."
SellList.COUNT_UNKNOWN = "how many not known"
-- Lead section 340: every bag item the list does not offer for sale, and
-- that no rule keeps, still has a row with why (a grey item never
-- vanishes). Player text.
SellList.OTHER_SECTION = "Not sold, and why"
SellList.WHY_NO_PRICE = "can't be sold to a merchant"
SellList.WHY_NOT_READ = "price not read yet"
SellList.WHY_RESERVATIONS = "reservations not known"
SellList.WHY_NO_RULE = "no rule says to sell it"
-- No row to sell while some prices are not read yet: not "nothing to sell".
SellList.PRICES_UNREAD_HEAD = "Prices not read yet"
SellList.PRICES_UNREAD_HOW = "The list is drawn again when the game reads them."
-- Item facts arrived late (the game read an item it had not loaded): the
-- list is made again while a merchant window is open. The repo's other
-- modules listen to it too (Gear/RewardMark.lua, Rotation/Driver.lua).
SellList.INFO_EVENT = "GET_ITEM_INFO_RECEIVED"
-- The saved diagnostics' line for the first grey item in the bags
-- (diag.sellGrey, account): { item, rule, why, counts }, all text.
SellList.DIAG_KEY = "sellGrey"

-- The player's never-sell list as Disposition takes it: { never = { [key] = true } }.
-- Takes a set ({ [item] = true }) or a list ({ item, ... }); anything that is
-- not an item is left out.
function SellList.Choices(store)
    local never = {}
    local raw = type(store) == "table" and type(store.get) == "function"
        and store:get("char", SellList.NEVER_PATH) or nil
    if type(raw) == "table" then
        for k, v in pairs(raw) do
            local key
            if type(k) == "number" and k == math.floor(k) and k >= 1 and k <= #raw and v ~= true then
                key = ns.Items.Key(v)          -- a list entry
            elseif v then
                key = ns.Items.Key(k)          -- a set entry
            end
            if key ~= nil then never[key] = true end
        end
    end
    return { never = never }
end

-- One evaluation of the reservations, through use (ctx.use). The module not
-- being there, or raising, is "unavailable", never "none".
function SellList.Current(use)
    local ok, mod = pcall(use, ns.Reservations.NAME)
    if ok and type(mod) == "table" and type(mod.Current) == "function" then
        local fine, r = pcall(mod.Current)
        if fine and type(r) == "table" then return r end
    end
    return { status = ns.Reservations.UNAVAILABLE }
end

-- What the bags hold, from an evaluation: the grants Disposition takes.
function SellList.Held(r)
    return ns.Reservations.HeldIn(ns.Reservations.Grants(r), "bags")
end

-- One listing, worked out once: what the text and the window both show.
-- grants: what the bags hold (SellList.Held), or nil. r: the evaluation the
-- grants came from; missing or not a table counts as "unavailable" (lead
-- section 224, SR-3). "unavailable" lists nothing to sell
-- and says so (not when the bags themselves weren't read: the list already
-- says it can't be made).
--   -> { stacks, kept = SellView.Kept's, unavailable = true, or
--        list = ItemSell.List's }
function SellList.Listing(client, store, grants, r)
    local stacks = type(client) == "table" and type(client.bagItems) == "function" and client.bagItems() or nil
    local read = type(client) == "table" and type(client.itemInfo) == "function" and client.itemInfo or nil
    local bag = ns.SellView.Bag(stacks, read)
    local book = type(store) == "table" and type(store.get) == "function"
        and store:get("account", SellList.PRICES_PATH) or nil
    local context = { choices = SellList.Choices(store), book = type(book) == "table" and book or nil,
        grants = grants }
    -- P-SETS: saved gear set pieces are kept (Disposition's inSet).
    context.sets = ns.GearSets and ns.GearSets.Facts(store) or nil
    -- P-INV G6: skill boosters are kept while the skill can rise.
    if type(ns.SkillBoosters) == "table" then context.boosters = ns.SkillBoosters.Facts(client, bag) end
    local out = { stacks = stacks, kept = ns.SellView.Kept(bag, context), notRead = 0 }
    -- Items whose facts were not read yet (no name, quality or price),
    -- counted once per item: two stacks of one item are one item.
    local unreadSeen = {}
    for _, e in ipairs(type(bag) == "table" and bag or {}) do
        if e.key ~= nil and e.name == nil and e.quality == nil and e.sellPrice == nil and not unreadSeen[e.key] then
            unreadSeen[e.key] = true
            out.notRead = out.notRead + 1
        end
    end
    -- An evaluation that is missing or not a table is unavailable too
    -- (MyBuddy SR-3): no sell advice without reservations that can be trusted.
    if bag ~= nil and (type(r) ~= "table" or r.status == ns.Reservations.UNAVAILABLE) then
        out.unavailable = true
    else
        out.list = ns.ItemSell.List(bag, context)
    end
    out.others = SellList.Others(bag, out, context.book)
    out.grey = SellList.Grey(bag, out)
    return out
end

-- The bag items a listing neither offers for sale nor keeps by a rule,
-- each with why (lead section 340). Items not read at all (no name,
-- quality or price) are left to listing.notRead. -> { { key, name, count,
-- reason, why = the WHY_ text's own key } }
function SellList.Others(bag, listing, book)
    local rows = {}
    if type(bag) ~= "table" then return rows end
    local shown = {}
    local list = type(listing.list) == "table" and listing.list or nil
    for _, r in ipairs(list and type(list.rows) == "table" and list.rows or {}) do shown[r.key] = true end
    for _, k in ipairs(type(listing.kept) == "table" and listing.kept.rows or {}) do shown[k.key] = true end
    local items = ns.ItemSell.Gather(bag)
    for _, item in ipairs(items) do
        local unread = item.name == nil and item.quality == nil and item.sellPrice == nil
        if not shown[item.key] and not unread then
            local why
            if listing.unavailable then
                why = "WHY_RESERVATIONS"
            elseif ns.ItemSell.PriceOf(item, book) == nil then
                why = "WHY_NO_PRICE"
            elseif item.sellPrice == nil then
                why = "WHY_NOT_READ"
            else
                why = "WHY_NO_RULE"
            end
            rows[#rows + 1] = {
                key = item.key,
                name = type(item.name) == "string" and item.name ~= "" and item.name or nil,
                count = item.count, reason = SellList[why], why = why,
            }
        end
    end
    return rows
end

-- What a "Not sold" row's why is in the diagnostics' words.
local GREY_RULE = {
    WHY_RESERVATIONS = "reservations unknown", WHY_NO_PRICE = "unsellable",
    WHY_NOT_READ = "not read", WHY_NO_RULE = "not sold",
}

-- The first grey item in the bags and what the listing did with it, for
-- the saved diagnostics: { item, rule, why, counts }, all text (why and
-- item nil when not known). rule: "sold", "kept", "unsellable",
-- "not read", "reservations unknown", "not sold", "no grey item" or
-- "bags not read". A grey item not read at all is not known to be grey.
function SellList.Grey(bag, listing)
    local list = type(listing.list) == "table" and listing.list or nil
    local sell = list and type(list.rows) == "table" and list.rows or {}
    local kept = type(listing.kept) == "table" and listing.kept.rows or {}
    local others = type(listing.others) == "table" and listing.others or {}
    local out = { counts = string.format("to sell %d, kept %d, not sold %d, not read %d",
        #sell, #kept, #others, tonumber(listing.notRead) or 0) }
    if type(bag) ~= "table" then out.rule = "bags not read" return out end
    local first
    for _, e in ipairs(bag) do
        if type(e) == "table" and e.key ~= nil and e.quality == 0 then first = e break end
    end
    if not first then out.rule = "no grey item" return out end
    out.item = type(first.name) == "string" and first.name or tostring(first.key)
    local function find(rows)
        for _, r in ipairs(rows) do if r.key == first.key then return r end end
        return nil
    end
    local r = find(sell)
    if r then
        out.rule, out.why = "sold", r.reason
        return out
    end
    r = find(kept)
    if r then
        out.rule = r.rule == "unsellable" and "unsellable" or "kept"
        out.why = r.reason
        return out
    end
    r = find(others)
    if r then
        out.rule, out.why = GREY_RULE[r.why] or "not sold", r.reason
        return out
    end
    out.rule = "not sold"
    return out
end

-- A listing as lines for the text panel.
function SellList.LinesOf(listing)
    local kept = listing.kept
    if listing.unavailable then
        local lines = { SellList.RESERVATIONS_UNKNOWN }
        if #kept.rows > 0 then
            lines[#lines + 1] = ns.ItemPresent.KEPT_HEADER
            for _, k in ipairs(kept.rows) do lines[#lines + 1] = ns.ItemPresent.KeptText(k) end
        end
        return SellList.OtherLines(lines, listing)
    end
    return SellList.OtherLines(ns.ItemPresent.SellLines(listing.list, kept), listing)
end

-- The "Not sold" rows added to text lines: "<name>: <why>".
function SellList.OtherLines(lines, listing)
    local others = type(listing.others) == "table" and listing.others or {}
    if #others == 0 then return lines end
    lines[#lines + 1] = SellList.OTHER_SECTION .. ":"
    for _, o in ipairs(others) do
        local name = o.name
        if type(name) ~= "string" or name == "" then name = ns.ItemPresent.Name(o.key) end
        lines[#lines + 1] = tostring(name) .. ": " .. tostring(o.reason)
    end
    return lines
end

function SellList.Lines(client, store, grants, r)
    return SellList.LinesOf(SellList.Listing(client, store, grants, r))
end

local function isWhole(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge and n == math.floor(n)
end

-- What an item line shows of each item in the bags, by item key: the item
-- itself (for the tooltip), its quality and its icon. Each only when the
-- client gives it in the shape the kit takes; a read that raises gives
-- nothing. The icon is the item fact's own `icon` when it has one, else
-- client.itemTexture's when that is a texture name or file number (a first guess: not seen
-- in game which of the two this client answers).
-- An icon the kit draws: a texture path, or a file number above 0 (what
-- client.itemTexture gives first in game).
local function isIcon(v)
    if type(v) == "string" then return v ~= "" end
    return type(v) == "number" and v > 0
end

function SellList.Look(client, stacks)
    local look = {}
    if type(client) ~= "table" or type(stacks) ~= "table" then return look end
    for i = 1, #stacks do
        local s = stacks[i]
        local key
        if type(s) == "table" then key = ns.Items.Key(s.item) end
        if key ~= nil and look[key] == nil then
            local entry = { item = s.item }
            if type(client.itemInfo) == "function" then
                local ok, info = pcall(client.itemInfo, s.item)
                if ok and type(info) == "table" then
                    if isWhole(info.quality) and info.quality <= 5 then entry.quality = info.quality end
                    if isIcon(info.icon) then entry.icon = info.icon end
                end
            end
            if entry.icon == nil and type(client.itemTexture) == "function" then
                local ok, tex = pcall(client.itemTexture, s.item)
                if ok and isIcon(tex) then entry.icon = tex end
            end
            look[key] = entry
        end
    end
    return look
end

-- One item line: the row's name and count, and what the bags say of it.
function SellList.ItemLine(row, look)
    local seen = look[row.key] or {}
    local name = row.name
    if type(name) ~= "string" or name == "" then name = ns.ItemPresent.Name(row.key) end
    local line = { kind = "itemLine", name = name, quality = seen.quality, icon = seen.icon }
    if isWhole(row.count) then line.count = row.count end
    local item = seen.item
    if type(item) ~= "number" and type(item) ~= "string" then item = row.key end
    if type(item) == "number" or type(item) == "string" then line.item = item end
    return line
end

local function plural(n, one, many)
    if n == 1 then return n .. " " .. one end
    return n .. " " .. many
end

-- A listing as a Kit.Window spec. client: for the icons and the quality
-- colours (SellList.Look); without it the lines have none. id: the identity
-- the title and the empty state name the add-on from (default ns.id).
function SellList.TreeOf(listing, client, id, action)
    id = type(id) == "table" and id or ns.id
    listing = type(listing) == "table" and listing or {}
    local Present, Prices = ns.ItemPresent, ns.Prices
    local look = SellList.Look(client, listing.stacks)
    local list
    if type(listing.list) == "table" then list = listing.list end
    local rows = list and list.ok and type(list.rows) == "table" and list.rows or {}
    local title, total = SellList.TITLE, nil
    -- footText: what the footer total covers when not every row is in it.
    local footText = nil
    local notRead = (tonumber(listing.notRead) or 0) + (list and tonumber(list.unread) or 0)
    local others = type(listing.others) == "table" and listing.others or {}
    -- Rows whose price is not read yet: the list is drawn again then.
    local waiting = 0
    for _, o in ipairs(others) do
        if o.why == "WHY_NOT_READ" then waiting = waiting + 1 end
    end
    local body = {}
    if listing.unavailable then
        title = SellList.UNKNOWN_HEAD
        body[#body + 1] = { kind = "empty", text = SellList.UNKNOWN_HEAD .. ".", how = SellList.UNKNOWN_HOW }
    elseif not list or not list.ok then
        local why = list and type(list.problem) == "string" and list.problem ~= "" and list.problem
            or ns.ItemSell.BAGS_UNREAD
        body[#body + 1] = { kind = "empty", text = SellList.UNREAD_HEAD .. ".", how = why }
    elseif #rows == 0 and notRead > 0 then
        body[#body + 1] = { kind = "empty", text = SellList.ITEMS_UNREAD_HEAD .. ".",
            how = Present.BankUnreadText(notRead, true) .. " " .. SellList.ITEMS_UNREAD_HOW }
    elseif #rows == 0 and waiting > 0 then
        body[#body + 1] = { kind = "empty", text = SellList.PRICES_UNREAD_HEAD .. ".",
            how = SellList.PRICES_UNREAD_HOW }
    elseif #rows == 0 then
        title = Present.NOTHING_TO_SELL
        total = 0
        local how = "Bags hold nothing " .. tostring(id.title) .. " would sell."
        if type(listing.stacks) == "table" and #listing.stacks == 0 then how = SellList.BAGS_EMPTY end
        body[#body + 1] = { kind = "empty", text = SellList.NOTHING, how = how }
    else
        title = plural(#rows, "item", "items") .. " to sell"
        total = 0
        local seen = 0
        body[#body + 1] = { kind = "section", text = SellList.SELL_SECTION }
        for _, r in ipairs(rows) do
            local line = SellList.ItemLine(r, look)
            -- Coins only for a total somebody saw the price of. Anything
            -- else is said in words, and is not in the footer's total.
            if r.basis == Prices.OBSERVED and isWhole(r.total) then
                line.money = r.total
                total = total + r.total
                seen = seen + 1
            else
                line.note = Present.SellPriceText(r)
                if not isWhole(r.count) then line.note = line.note .. "; " .. SellList.COUNT_UNKNOWN end
            end
            body[#body + 1] = line
        end
        -- No price seen: no money, as unknown is not 0. Some seen: the
        -- total says it covers only those.
        if seen == 0 then
            total = nil
            footText = SellList.PRICES_UNKNOWN
        elseif seen < #rows then
            footText = SellList.TOTAL_SEEN
        end
        -- The estimate and the prices nobody saw, apart from the total.
        local t = type(list.total) == "table" and list.total or {}
        if (tonumber(t.estimated) or 0) > 0 or (tonumber(t.unknown) or 0) > 0 then
            local says = Present.SellTotal(list)
            if says then body[#body + 1] = { kind = "line", text = says } end
        end
    end
    for _, note in ipairs(Present.SellNotes(list)) do
        body[#body + 1] = { kind = "line", text = note, tone = "warn" }
    end
    local kept = type(listing.kept) == "table" and type(listing.kept.rows) == "table" and listing.kept.rows or {}
    if #kept > 0 then
        body[#body + 1] = { kind = "section", text = SellList.KEPT_SECTION }
        for _, k in ipairs(kept) do
            local line = SellList.ItemLine(k, look)
            line.note = tostring(k.reason or "kept")
            line.tone = "good"
            body[#body + 1] = line
        end
    end
    if #others > 0 then
        body[#body + 1] = { kind = "section", text = SellList.OTHER_SECTION }
        for _, o in ipairs(others) do
            local line = SellList.ItemLine(o, look)
            line.note = tostring(o.reason)
            line.tone = "warn"
            body[#body + 1] = line
        end
    end
    local footer = { kind = "footer", text = SellList.TOTAL, money = total, slot = SellList.SLOT }
    if type(action) == "table" then
        if type(action.button) == "table" then footer.buttons = { action.button } end
        if type(action.note) == "table" then
            table.insert(body, 1, { kind = "line", text = action.note.text, tone = action.note.tone })
        end
    end
    if footText then
        footer.text = footText
    elseif total == nil then
        footer.text = SellList.NO_TOTAL
    end
    return {
        id = SellList.KIT_ID, title = tostring(id.title) .. ": " .. SellList.TITLE,
        width = SellList.KIT_WIDTH, height = SellList.KIT_HEIGHT, point = SellList.DEFAULT_POINT,
        children = {
            { kind = "header", title = title },
            { kind = "scroll", height = SellList.LIST_HEIGHT, children = body },
            footer,
        },
    }
end

function SellList.Tree(client, store, grants, r, id)
    return SellList.TreeOf(SellList.Listing(client, store, grants, r), client, id)
end

-- The window before any merchant was seen: it says what is missing.
function SellList.ClosedTree(id)
    id = type(id) == "table" and id or ns.id
    return {
        id = SellList.KIT_ID, title = tostring(id.title) .. ": " .. SellList.TITLE,
        width = SellList.KIT_WIDTH, height = SellList.KIT_HEIGHT, point = SellList.DEFAULT_POINT,
        children = {
            { kind = "header", title = SellList.TITLE },
            { kind = "scroll", height = SellList.LIST_HEIGHT, children = {
                { kind = "empty", text = SellList.CLOSED_HEAD, how = SellList.CLOSED_HOW },
            } },
            { kind = "footer", text = SellList.NO_TOTAL, slot = SellList.SLOT },
        },
    }
end

-- Declares the module on kernel k. Usable at once: before the first listing
-- last() is nil and shows() is 0.
function SellList.Declare(k)
    local api = {}
    local last, shows = nil, 0
    -- win: the kit window. panel: the text panel, made only when the kit
    -- cannot draw.
    local win, panel
    local open, relist = false, nil
    -- The "Sell these" run (Items/SellThese.lua), made at the start.
    local sellRunner = nil
    -- The player closed the window (its close button, Escape): it stays
    -- away for the rest of this merchant visit unless asked for.
    local closed = false
    function api.window() return win end
    -- The reservations evaluation of this merchant visit: made at its first
    -- listing, kept until the window closes or the reservations change
    -- (Reservations.CHANGED).
    local visit = nil
    function api.last() return last end
    function api.shows() return shows end
    -- Lists again while a merchant window is open (the never-sell list
    -- changed: Items/Keep.lua). Does nothing when none is open.
    -- A list the player asked for (Show()) stays asked for until the merchant
    -- window closes, so a refresh keeps it shown with "vendor.list" off too.
    local asked = false
    function api.refresh()
        if open and relist then relist(asked) end
    end
    -- Asked for (the merchant window's button): lists now and shows the
    -- panel, whatever "vendor.list" says. Only while a merchant window is
    -- open, so that its closing hides the panel again.
    local started = false
    function api.show()
        if not started or not relist then return false, SellList.NOT_STARTED end
        if not open then return false, SellList.NO_MERCHANT end
        if not win and not panel then return false, SellList.NO_PANEL end
        asked = true
        closed = false
        relist(true)
        return true
    end

    local function hide()
        if win then win.show(false) end
        if panel then panel.show(false) end
    end

    k:Module({
        name = SellList.NAME,
        needs = { "client", "store", "bus", "settings", "sched" },
        provides = { Last = api.last, Shows = api.shows, Show = function() return api.show() end,
            Window = function() return api.window() end },
        start = function(ctx)
            local client = ctx.client
            local id = k.id or ns.id
            if type(client.watchMerchant) == "function" then client.watchMerchant() end
            started = true
            -- The text panel: the same listing on a client that cannot
            -- draw the kit. Made once, when first needed.
            local function textPanel()
                if panel then return panel end
                panel = client.panel({ name = id.framePrefix .. "SellList",
                    width = SellList.WIDTH, height = SellList.HEIGHT })
                if panel then
                    panel.show(false)
                    panel.place(SellList.DEFAULT_POINT)
                end
                return panel
            end
            -- The "Sell these" button and its note (Items/SellThese.lua).
            -- shownListing: the listing the window shows, which a click
            -- sells. note: what the last run or click did, this visit.
            local SellThese = ns.SellThese
            local shownListing, note = nil, nil
            local function bagSlots()
                if type(client.bagSlots) ~= "function" then return nil end
                return client.bagSlots()
            end
            local runner = SellThese.Runner(client, ctx.sched, function(result)
                local tone = "warn"
                if result.sold > 0 and result.stopped == nil and result.skipped == 0 then tone = "good" end
                note = { text = SellThese.Note(result), tone = tone }
                api.refresh()
            end)
            sellRunner = runner
            local function sellClicked()
                if not open or runner.running() then return end
                local steps, why = SellThese.Plan(shownListing, bagSlots())
                if steps then
                    runner.start(steps)
                else
                    note = { text = SellThese.Tip(why), tone = "warn" }
                end
                api.refresh()
            end
            local function action(listing)
                local button = { kind = "button", key = SellThese.KEY, text = SellThese.TEXT,
                    tooltip = SellThese.TIP, onClick = sellClicked }
                if runner.running() then
                    button.text, button.enabled = SellThese.SELLING, false
                    button.tooltip = SellThese.Tip(SellThese.SELLING)
                else
                    local steps, why = SellThese.Plan(listing, bagSlots())
                    if not steps then
                        button.text, button.enabled, button.tooltip = why, false, SellThese.Tip(why)
                    end
                end
                return { button = button, note = note }
            end
            -- The kit window of a listing: true when it was drawn.
            local function draw(listing)
                if not win then return false end
                shownListing = listing
                local tree = ns.Kit.Window(SellList.TreeOf(listing, client, id, action(listing)))
                if not tree or win.update(tree) == false then return false end
                win.show(true)
                return true
            end
            -- Lead section 340: the first grey item and what the listing
            -- did with it, in the saved diagnostics (diag.sellGrey), as
            -- UI/KitProbe.lua keeps diag.kitDrawn. Text fields only.
            local function saveGrey(listing)
                local g = type(listing) == "table" and listing.grey or nil
                if type(g) ~= "table" or type(client.saved) ~= "function" then return end
                local ok, db = pcall(client.saved, id.accountDB)
                if not ok or type(db) ~= "table" then return end
                if type(db.diag) ~= "table" then db.diag = {} end
                local row = {}
                for _, f in ipairs({ "item", "rule", "why", "counts" }) do
                    if type(g[f]) == "string" then row[f] = g[f] end
                end
                db.diag[SellList.DIAG_KEY] = row
            end
            -- byAsk: true when the player asked for the list (Show()).
            relist = function(byAsk)
                -- Off only when the player turned it off; a missing row is on.
                -- The setting governs showing by itself, not an ask.
                if not byAsk and ctx.settings:get(SellList.SETTING) == false then
                    hide()
                    return
                end
                -- Closed by the player: a bag change does not bring it back.
                if closed and not byAsk then return end
                if not visit then visit = SellList.Current(ctx.use) end
                local listing = SellList.Listing(client, ctx.store, SellList.Held(visit), visit)
                local lines = SellList.LinesOf(listing)
                saveGrey(listing)
                shows = shows + 1
                last = lines
                if draw(listing) then
                    if panel then panel.show(false) end
                    return
                end
                -- No kit window, or it would not take the listing: as text.
                if win then win.show(false) end
                local p = textPanel()
                if p then
                    p.setLines(lines)
                    p.show(true)
                end
            end
            ctx.bus:on(SellList.NAME, "MERCHANT_SHOW", function()
                open = true
                asked = false       -- a new window: nothing was asked for yet
                closed = false
                visit = nil         -- and no evaluation yet
                note = nil          -- nor a sell note
                relist()
            end)
            ctx.bus:on(SellList.NAME, "MERCHANT_CLOSED", function()
                open = false
                asked = false
                closed = false
                visit = nil
                runner.stop("closed")   -- a run stops with the window
                hide()
            end)
            -- Something was sold, bought or moved by the player: the list
            -- follows the bags. Nothing when no merchant window is open.
            ctx.bus:on(SellList.NAME, SellList.BAG_EVENT, function()
                api.refresh()
            end)
            -- Item facts arrived late (lead section 340): a row whose price
            -- was not read yet becomes what it is. Nothing when no merchant
            -- window is open.
            -- A cold visit fires a burst of these: at most one relist per
            -- frame (the scheduler's next frame).
            local infoPending = false
            ctx.bus:on(SellList.NAME, SellList.INFO_EVENT, function()
                if infoPending or not open then return end
                infoPending = true
                ctx.sched:nextFrame(SellList.NAME, function()
                    infoPending = false
                    api.refresh()
                end)
            end)
            -- The reservations changed (a goal added or removed): this
            -- visit's evaluation is old, so drop it and list once again.
            -- Nothing when no merchant window is open.
            ctx.bus:on(SellList.NAME, ns.Reservations.CHANGED, function()
                if not open then return end
                visit = nil
                api.refresh()
            end)
            -- The frame last, after everything that can switch the module off.
            -- The kit window, where the player left it; hidden until a
            -- merchant opens. A function of the window's that raises is a
            -- problem; the kit not drawing at all is not one: the text
            -- panel stands in.
            local making = true
            local tree = ns.Kit.Window(SellList.ClosedTree(id))
            if tree and type(client.kitWindow) == "function" then
                local point, width, height = ns.Kit.Place(ctx.store:get("account", SellList.LAYOUT), tree)
                win = client.kitWindow(SellList.KIT_ID, tree, {
                    name = id.framePrefix .. "SellList",
                    point = point, width = width, height = height,
                    onMoved = function(to, w, h)
                        if type(to) ~= "table" then return end
                        ctx.store:set("account", SellList.LAYOUT,
                            { point = { to[1], to[2], to[3], to[4] }, width = w, height = h })
                    end,
                    onClose = function()
                        closed = true
                        asked = false
                    end,
                    failed = function(err)
                        if not making then k.problems:add(SellList.NAME, "window", tostring(err)) end
                    end,
                })
            end
            making = false
            if win then
                win.show(false)
            else
                textPanel()
            end
        end,
        -- Stopped: nothing is open as far as this module goes, so a later
        -- refresh() lists nothing.
        stop = function()
            open = false
            asked = false
            closed = false
            started = false
            visit = nil
            if sellRunner then sellRunner.stop("closed") end
            hide()
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.sellList = SellList.Declare(ns)
