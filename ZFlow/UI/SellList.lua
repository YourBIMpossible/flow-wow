-- Sell list (L6-A): while a merchant window is open, a panel lists what
-- Z-Flow would sell (Items/Sell.lua with Disposition's rules), each line
-- with its count, its vendor price as money text and where that price is
-- from (F-085), and below it what is kept and why.
--
-- LOOK ONLY. The panel has no buttons and nothing here sells, buys,
-- deletes, moves or clicks anything; selling is a separate decision (G2)
-- that this file does not make. It reads the bags, the item facts, the
-- player's never-sell list and the saved price book, and draws text.
--
--   SellList.Lines(client, store) -> lines     one listing; what the module shows
--   SellList.Declare(k)           -> api       declares the module on kernel k
--     api.last()   the lines of the last listing, nil before the first
--     api.shows()  how many listings were made since the start
--     api.show()   lists now and shows the panel, when asked for: only
--                  while a merchant window is open. -> true, or false and why
--   ns.use(SellList.NAME) -> { Last = api.last, Shows = api.shows, Show = api.show }
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
-- Saved data (read only): the character's never-sell list at
-- settings.sell.never (imported from Flow) and the price book at
-- learned.prices (account).
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
-- Not tested in game: MERCHANT_SHOW and the item read are first guesses.
local _, ns = ...

local SellList = ns.SellList or {}
ns.SellList = SellList

SellList.NAME = "sellList"
-- The bags changed (one event after a burst of changes): the list is made
-- again while a merchant window is open. A first guess: not seen in game.
SellList.BAG_EVENT = "BAG_UPDATE_DELAYED"
SellList.SETTING = "vendor.list"
SellList.WIDTH, SellList.HEIGHT = 340, 260
SellList.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 360, -120 }
SellList.NEVER_PATH = "settings.sell.never"
SellList.PRICES_PATH = "learned.prices"
-- Why Show() showed nothing (for the caller; not player text).
SellList.NOT_STARTED = "the sell list has not started"
SellList.NO_MERCHANT = "no merchant window is open"
SellList.NO_PANEL = "this client cannot draw the panel"
-- Player text when the reservations could not be worked out.
SellList.RESERVATIONS_UNKNOWN = "Reservations not known: nothing is offered for sale, as what your goals hold is not known."

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

-- One listing, as lines for the panel.
-- grants: what the bags hold (SellList.Held), or nil. r: the evaluation the
-- grants came from; missing or not a table counts as "unavailable" (lead
-- section 224, SR-3). "unavailable" lists nothing to sell
-- and says so (not when the bags themselves weren't read: the list already
-- says it can't be made).
function SellList.Lines(client, store, grants, r)
    local stacks = type(client) == "table" and type(client.bagItems) == "function" and client.bagItems() or nil
    local read = type(client) == "table" and type(client.itemInfo) == "function" and client.itemInfo or nil
    local bag = ns.SellView.Bag(stacks, read)
    local book = type(store) == "table" and type(store.get) == "function"
        and store:get("account", SellList.PRICES_PATH) or nil
    local context = { choices = SellList.Choices(store), book = type(book) == "table" and book or nil,
        grants = grants }
    local kept = ns.SellView.Kept(bag, context)
    -- An evaluation that is missing or not a table is unavailable too
    -- (MyBuddy SR-3): no sell advice without reservations that can be trusted.
    if bag ~= nil and (type(r) ~= "table" or r.status == ns.Reservations.UNAVAILABLE) then
        local lines = { SellList.RESERVATIONS_UNKNOWN }
        if #kept.rows > 0 then
            lines[#lines + 1] = ns.ItemPresent.KEPT_HEADER
            for _, k in ipairs(kept.rows) do lines[#lines + 1] = ns.ItemPresent.KeptText(k) end
        end
        return lines
    end
    return ns.ItemPresent.SellLines(ns.ItemSell.List(bag, context), kept)
end

-- Declares the module on kernel k. Usable at once: before the first listing
-- last() is nil and shows() is 0.
function SellList.Declare(k)
    local api = {}
    local last, shows = nil, 0
    local panel
    local open, relist = false, nil
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
        if not panel then return false, SellList.NO_PANEL end
        asked = true
        relist(true)
        return true
    end

    local function hide()
        if panel then panel.show(false) end
    end

    k:Module({
        name = SellList.NAME,
        needs = { "client", "store", "bus", "settings" },
        provides = { Last = api.last, Shows = api.shows, Show = function() return api.show() end },
        start = function(ctx)
            local client = ctx.client
            if type(client.watchMerchant) == "function" then client.watchMerchant() end
            started = true
            -- byAsk: true when the player asked for the list (Show()).
            relist = function(byAsk)
                -- Off only when the player turned it off; a missing row is on.
                -- The setting governs showing by itself, not an ask.
                if not byAsk and ctx.settings:get(SellList.SETTING) == false then
                    hide()
                    return
                end
                if not visit then visit = SellList.Current(ctx.use) end
                local lines = SellList.Lines(client, ctx.store, SellList.Held(visit), visit)
                shows = shows + 1
                last = lines
                if panel then
                    panel.setLines(lines)
                    panel.show(true)
                end
            end
            ctx.bus:on(SellList.NAME, "MERCHANT_SHOW", function()
                open = true
                asked = false       -- a new window: nothing was asked for yet
                visit = nil         -- and no evaluation yet
                relist()
            end)
            ctx.bus:on(SellList.NAME, "MERCHANT_CLOSED", function()
                open = false
                asked = false
                visit = nil
                hide()
            end)
            -- Something was sold, bought or moved by the player: the list
            -- follows the bags. Nothing when no merchant window is open.
            ctx.bus:on(SellList.NAME, SellList.BAG_EVENT, function()
                api.refresh()
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
            local id = k.id or ns.id
            panel = client.panel({ name = id.framePrefix .. "SellList",
                width = SellList.WIDTH, height = SellList.HEIGHT })
            if panel then
                panel.show(false)
                panel.place(SellList.DEFAULT_POINT)
            end
        end,
        -- Stopped: nothing is open as far as this module goes, so a later
        -- refresh() lists nothing.
        stop = function()
            open = false
            asked = false
            started = false
            visit = nil
            hide()
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.sellList = SellList.Declare(ns)
