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
--   ns.use(SellList.NAME) -> { Last = api.last, Shows = api.shows }
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
-- Not tested in game: MERCHANT_SHOW and the item read are first guesses.
local _, ns = ...

local SellList = ns.SellList or {}
ns.SellList = SellList

SellList.NAME = "sellList"
SellList.SETTING = "vendor.list"
SellList.WIDTH, SellList.HEIGHT = 340, 260
SellList.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 360, -120 }
SellList.NEVER_PATH = "settings.sell.never"
SellList.PRICES_PATH = "learned.prices"

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

-- One listing, as lines for the panel.
function SellList.Lines(client, store)
    local stacks = type(client) == "table" and type(client.bagItems) == "function" and client.bagItems() or nil
    local read = type(client) == "table" and type(client.itemInfo) == "function" and client.itemInfo or nil
    local bag = ns.SellView.Bag(stacks, read)
    local book = type(store) == "table" and type(store.get) == "function"
        and store:get("account", SellList.PRICES_PATH) or nil
    local context = { choices = SellList.Choices(store), book = type(book) == "table" and book or nil }
    return ns.ItemPresent.SellLines(ns.ItemSell.List(bag, context), ns.SellView.Kept(bag, context))
end

-- Declares the module on kernel k. Usable at once: before the first listing
-- last() is nil and shows() is 0.
function SellList.Declare(k)
    local api = {}
    local last, shows = nil, 0
    local panel
    local open, relist = false, nil
    function api.last() return last end
    function api.shows() return shows end
    -- Lists again while a merchant window is open (the never-sell list
    -- changed: Items/Keep.lua). Does nothing when none is open.
    function api.refresh()
        if open and relist then relist() end
    end

    local function hide()
        if panel then panel.show(false) end
    end

    k:Module({
        name = SellList.NAME,
        needs = { "client", "store", "bus", "settings" },
        provides = { Last = api.last, Shows = api.shows },
        start = function(ctx)
            local client = ctx.client
            if type(client.watchMerchant) == "function" then client.watchMerchant() end
            relist = function()
                -- Off only when the player turned it off; a missing row is on.
                if ctx.settings:get(SellList.SETTING) == false then
                    hide()
                    return
                end
                local lines = SellList.Lines(client, ctx.store)
                shows = shows + 1
                last = lines
                if panel then
                    panel.setLines(lines)
                    panel.show(true)
                end
            end
            ctx.bus:on(SellList.NAME, "MERCHANT_SHOW", function()
                open = true
                relist()
            end)
            ctx.bus:on(SellList.NAME, "MERCHANT_CLOSED", function()
                open = false
                hide()
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
        stop = hide,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.sellList = SellList.Declare(ns)
