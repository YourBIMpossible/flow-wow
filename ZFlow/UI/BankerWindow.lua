local _, ns = ...

-- Banker window (E-17, E-22, E-23, E-25; E-24 is its fourth view): one kit
-- window, "Banker", with four views on tabs, the Dungeon Quests window's
-- shape:
--
--   To bank       the bank list (UI/BankList.lua) exactly as it renders,
--                 made at the bank; away from the bank one line says so.
--   In your bank  what the bank held at the last visit (Items/Banker.lua's
--                 Banker.Items over the remembered bank contents), as item
--                 lines under the last-visit line. Away from the bank this
--                 is the view the window opens on.
--   To sell       the take-out rows (Items/BankTakeOut.lua, grouped as
--                 Items/Banker.lua's SellLines groups them) as rows with
--                 their reasons underneath. Clicking a row keeps the item: it
--                 goes on the never-sell list and moves to the Kept
--                 section at the bottom; clicking a kept row puts it back.
--   Auction prices  Items/PriceList.lua's rows for this realm, cheapest
--                 buyout last seen, with the header's search box.
--
-- LOOK ONLY (§156 §8), like both modules behind it: nothing here deposits,
-- withdraws, moves or sells anything. Flow's Deposit button is not in this
-- window; if it is wanted it is its own row.
--
--   BankerWindow.Children(tab, data, acts) -> the window's children (pure)
--   BankerWindow.Declare(k, diag) -> api   (api.show(tab), api.shows())
--   ns.use(BankerWindow.NAME) -> { Show }
--     Show(tab): opens the window. With no tab: on To bank at the bank,
--     on In your bank away from it (the two buttons of E-25 pass their
--     tab). -> true, or false and why.
--
-- The chat word <slash> banker keeps printing its lists (Items/Banker.lua)
-- and also opens this window: the word is wrapped once, at the start.
--
-- The buttons that open it are rows of UI/WindowButtons.lua: "banker" on
-- BankFrame (Show on To bank) and "bags" above ContainerFrame1, the
-- backpack window (Show on In your bank), each with its own setting.
--
-- DATA NEED (Lane Items): the To sell click writes the never-sell list
-- (settings.sell.never), which Items/Keep.lua owns. The window calls
-- ItemKeep.Set(k, key, on) -> changed, when that call exists; until Lane
-- Items adds it, clicks do nothing and rows stay where they are, so the
-- list keeps its one writer.
--
-- Reads: client.bankOpen(), client.itemInfo / client.itemTexture (through
-- the data modules and SellList.Look), client.clock(), client.kitWindow.
-- Saved data (read only): char learned.bankCounts (Items/HaveTip.lua),
-- char settings.sell.never (through SellList.Choices), the auction realm
-- table (through AuctionLog.Kept). Saved data (written): where the player
-- left the window, at BankerWindow.LAYOUT (account).
-- Not tested in game.
local W = {}
ns.BankerWindow = W

W.NAME = "bankerWindow"
W.ID = "Banker"
W.TITLE = "Banker"
W.TABS = { "To bank", "In your bank", "To sell", "Auction prices" }
W.TAB_BANK, W.TAB_IN, W.TAB_SELL, W.TAB_PRICES = 1, 2, 3, 4

W.KIT_WIDTH, W.KIT_HEIGHT = 420, 480
W.LIST_HEIGHT = 360
W.LAYOUT = "layout.banker"          -- account: { point, width, height }
W.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 380, -120 }
W.NOT_STARTED = "the banker window has not started"
W.NO_PANEL = "this client cannot draw the window"
W.AWAY_LINE = "This list is made at the bank."
W.IN_HEAD = "In your bank"
W.LAST_VISIT = "Last visit: %s"
W.KEPT_SECTION = "Kept"
W.KEPT_NOTE = "Kept"
W.PRICES_FOOTER = "Prices are from your own auction searches."
W.SEEN = "seen %s ago"
W.PRICE_SEARCH = "Search prices"

local function whole(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and v == math.floor(v)
end

-- The bank list's own tree, taken apart for the To bank tab: its scroll's
-- rows, its header's title, its footer's words. nil when the tree is not
-- the shape BankList.Tree makes.
local function bankParts(tree)
    if type(tree) ~= "table" or type(tree.children) ~= "table" then return nil end
    local rows, title, says
    for _, part in ipairs(tree.children) do
        if type(part) == "table" then
            if part.kind == "scroll" and type(part.children) == "table" then rows = part.children end
            if part.kind == "header" and type(part.title) == "string" then title = part.title end
            if part.kind == "footer" and type(part.text) == "string" then says = part.text end
        end
    end
    if rows == nil then return nil end
    return { rows = rows, title = title, says = says }
end

-- One item line for a row of the bank's contents (display only).
local function itemPart(row, look, key)
    local line = ns.SellList.ItemLine(row, look)
    line.key = key
    return line
end

-- One To sell row: a line (the kit's item line cannot be clicked), with
-- the item's icon from the look, its count beside its name, its reason
-- underneath, and its click.
local function sellPart(row, look, note, key, onClick)
    local seen = nil
    if type(look) == "table" then seen = look[row.key] end
    local name = row.name
    if type(name) ~= "string" or name == "" then name = ns.ItemPresent.Name(row.key) end
    local text = name
    if whole(row.count) and row.count > 1 then text = name .. " x" .. row.count end
    local line = { kind = "line", key = key, text = text, sub = note, onClick = onClick }
    if type(seen) == "table" and seen.icon ~= nil then line.icon = seen.icon end
    return line
end

-- The window's children for one tab. data (made by the module, which holds
-- the client and the store):
--   atBank                    the bank window is open
--   bankTree                  BankList.Tree's spec (at the bank only)
--   inItems, inHead           Banker.Items' rows (or nil) and the
--                             last-visit line; inLook their SellList look
--   sellGroups                { { header, rows }, ... } in Banker.TAKES'
--                             order, sellLine (a line to show instead),
--                             sellKept (the bank's kept items, built
--                             by the module from the never list), sellLook
--   priceRows, priceHead      PriceList's filtered rows and header line;
--                             priceNow the clock, for "seen ... ago"
--   search                    the prices search text
-- acts: { tab(i), keep(row), unkeep(row), search(text) }.
function W.Children(tab, d, acts)
    if type(d) ~= "table" then d = {} end
    if type(acts) ~= "table" then acts = {} end
    local header = { kind = "header", key = "header", title = W.TITLE }
    if tab == W.TAB_PRICES then
        header.search = { text = d.search or "", placeholder = W.PRICE_SEARCH,
            onText = function(text) if acts.search then acts.search(text) end end }
    end
    local kids = { header,
        { kind = "tabs", key = "tabs", items = W.TABS, selected = tab,
          onSelect = function(i) if acts.tab then acts.tab(i) end end } }
    local body, says = {}, W.TABS[tab] or W.TITLE
    if tab == W.TAB_BANK then
        local parts = nil
        if d.atBank then parts = bankParts(d.bankTree) end
        if parts then
            for _, row in ipairs(parts.rows) do body[#body + 1] = row end
            if parts.says then says = parts.says end
        else
            body[#body + 1] = { kind = "line", key = "away", text = W.AWAY_LINE }
        end
    elseif tab == W.TAB_SELL then
        if type(d.sellLine) == "string" then
            body[#body + 1] = { kind = "line", key = "sellLine", text = d.sellLine }
        else
            local n = 0
            for _, group in ipairs(d.sellGroups or {}) do
                body[#body + 1] = { kind = "section", text = group.header }
                for _, row in ipairs(group.rows) do
                    n = n + 1
                    local r = row
                    -- The keep click goes only on a row taken to sell
                    -- (a row with no take reads as sell, as in Banker):
                    -- keeping a route, quest or held row means nothing.
                    local click = nil
                    if r.take == "sell" or r.take == nil then
                        click = function() if acts.keep then acts.keep(r) end end
                    end
                    body[#body + 1] = sellPart(r, d.sellLook, r.reason, "sell" .. n, click)
                end
            end
            if n == 0 then
                body[#body + 1] = { kind = "line", key = "sellLine", text = ns.Banker.NOTHING_TO_SELL }
            end
            local kept = d.sellKept or {}
            if #kept > 0 then
                body[#body + 1] = { kind = "section", text = W.KEPT_SECTION }
                for i, row in ipairs(kept) do
                    local r = row
                    body[#body + 1] = sellPart(r, d.sellLook, W.KEPT_NOTE, "kept" .. i,
                        function() if acts.unkeep then acts.unkeep(r) end end)
                end
            end
        end
    elseif tab == W.TAB_PRICES then
        body[#body + 1] = { kind = "line", key = "priceHead", text = d.priceHead or ns.PriceList.NONE }
        for i, row in ipairs(d.priceRows or {}) do
            local line = { kind = "line", key = "price" .. i, text = row.name,
                right = ns.Prices.Coin(row.price) }
            if line.right == nil then line.right = "?" end
            if whole(d.priceNow) and whole(row.at) and d.priceNow >= row.at then
                line.sub = W.SEEN:format(ns.PriceChart.Span(d.priceNow - row.at))
            end
            body[#body + 1] = line
        end
        says = W.PRICES_FOOTER
    else
        -- In your bank (also the fall-back tab).
        if type(d.inItems) ~= "table" then
            body[#body + 1] = { kind = "line", key = "inLine", text = ns.Banker.NOT_SEEN }
        else
            if type(d.inHead) == "string" then
                body[#body + 1] = { kind = "line", key = "inHead", text = d.inHead }
                says = d.inHead
            end
            local items = d.inItems
            if #items == 0 then
                body[#body + 1] = { kind = "line", key = "inLine", text = "Nothing." }
            end
            for i = 1, math.min(#items, ns.Banker.MAX) do
                body[#body + 1] = itemPart(items[i], d.inLook, "in" .. i)
            end
            if #items > ns.Banker.MAX then
                body[#body + 1] = { kind = "line", key = "inMore",
                    text = "and " .. (#items - ns.Banker.MAX) .. " more." }
            end
        end
    end
    kids[#kids + 1] = { kind = "scroll", height = W.LIST_HEIGHT, children = body }
    kids[#kids + 1] = { kind = "footer", text = says }
    return kids
end

function W.Declare(k, diag)
    local api = {}
    local shows = 0
    local handle
    local started = false
    -- The view: the tab shown (nil until the first Show picks by place),
    -- the prices search, and this session's keeps the data has not caught
    -- up with yet (a click moves its row at once; the saved list is the
    -- data's own call's business).
    local view = { tab = nil, search = "" }
    local keptNow, unkeptNow = {}, {}
    local render, bankOpenNow

    function api.shows() return shows end
    function api.show(tab)
        if not started then return false, W.NOT_STARTED end
        if not handle then return false, W.NO_PANEL end
        local at = nil
        if type(tab) == "number" and W.TABS[tab] then at = tab end
        if at == nil and view.tab == nil then
            if bankOpenNow() then at = W.TAB_BANK else at = W.TAB_IN end
        end
        if at ~= nil then view.tab = at end
        render()
        handle.show(true)
        shows = shows + 1
        return true
    end

    local ctx
    local function client()
        if ctx then return ctx.client end
        return nil
    end

    bankOpenNow = function()
        local c = client()
        if type(c) == "table" and type(c.bankOpen) == "function" then
            return c.bankOpen() == true
        end
        return false
    end

    -- The never-sell list as the sell list reads it, with this session's
    -- clicks laid over it.
    local function keptSet()
        local set = {}
        local choices = ns.SellList.Choices(ctx.store)
        if type(choices) == "table" and type(choices.never) == "table" then
            for key in pairs(choices.never) do set[key] = true end
        end
        for key in pairs(unkeptNow) do set[key] = nil end
        for key in pairs(keptNow) do set[key] = true end
        return set
    end

    -- DATA NEED: ItemKeep.Set(k, key, on) -> changed. Without it the click
    -- does nothing (see the header).
    local function setKeep(key, on)
        local K = ns.ItemKeep
        if type(K) ~= "table" or type(K.Set) ~= "function" then return false end
        local ok, changed = pcall(K.Set, k, key, on)
        if not ok then
            k.problems:add(W.NAME, "keep", tostring(changed))
            return false
        end
        return changed == true
    end

    local acts = {
        tab = function(i)
            view.tab = i
            render()
        end,
        search = function(text)
            if type(text) == "string" then view.search = text else view.search = "" end
            render()
        end,
        keep = function(row)
            if type(row) ~= "table" or row.key == nil then return end
            if setKeep(row.key, true) then
                keptNow[row.key] = true
                unkeptNow[row.key] = nil
                render()
            end
        end,
        unkeep = function(row)
            if type(row) ~= "table" or row.key == nil then return end
            if setKeep(row.key, false) then
                keptNow[row.key] = nil
                unkeptNow[row.key] = true
                render()
            end
        end,
    }

    -- The bank's remembered contents and their look (icon and quality, the
    -- sell list's reads over the bank's own stacks).
    local function bankItems()
        local c = client()
        local saved = ctx.store:get("char", ns.HaveTip.PATH)
        local itemInfo = nil
        if type(c) == "table" then itemInfo = c.itemInfo end
        local items = ns.Banker.Items(saved, itemInfo)
        local look = {}
        if type(items) == "table" then
            local stacks = {}
            for i, e in ipairs(items) do stacks[i] = { item = ns.Items.Id(e.key) } end
            look = ns.SellList.Look(c, stacks)
            for _, e in ipairs(items) do
                local seen = look[e.key]
                if type(seen) == "table" and seen.quality == nil and whole(e.quality) then
                    seen.quality = e.quality
                end
            end
        end
        return saved, items, look
    end

    local function data()
        local c = client()
        local d = { atBank = bankOpenNow(), search = view.search }
        local r = ns.BankList.Current(ctx.use)
        if d.atBank then
            d.bankTree = ns.BankList.Tree(c, ctx.store, ns.BankList.Held(r), r)
        end
        local saved, items, look = bankItems()
        d.inItems, d.inLook = items, look
        -- Kept: the bank's own items whose key is on the never list
        -- (with this session's clicks laid over it). Not a filter of
        -- the take-out rows: once the keep is written, Make drops the
        -- item, so a filter would never find it (CHANGES-1 b).
        if type(items) == "table" then
            local kept = keptSet()
            local keptRows = {}
            for _, e in ipairs(items) do
                if kept[e.key] then keptRows[#keptRows + 1] = { key = e.key, name = e.name, count = e.count } end
            end
            d.sellKept, d.sellLook = keptRows, look
        end
        if type(items) == "table" and type(saved) == "table" and whole(saved.at) then
            local now = nil
            if type(c) == "table" and type(c.clock) == "function" then now = c.clock() end
            if whole(now) and now >= saved.at then
                d.inHead = W.LAST_VISIT:format(ns.PriceChart.Span(now - saved.at) .. " ago")
            else
                d.inHead = W.LAST_VISIT:format("your last visit")
            end
        end
        -- To sell: the banker word's own path (one reservations
        -- evaluation; BankTakeOut's rows, Banker's groups).
        if r.status == ns.Reservations.UNAVAILABLE then
            d.sellLine = ns.Banker.SELL_UNKNOWN
        else
            local T = ns.BankTakeOut
            local list, why = T.Make(c, ctx.store, ctx.use, r)
            if list == nil and why == T.NOT_SEEN then
                d.sellLine = ns.Banker.SELL_NOT_SEEN
            elseif list == nil then
                d.sellLine = "To sell: " .. ns.Banker.FAILED
            elseif type(list.rows) == "table" then
                local groups = {}
                local byTake = {}
                for _, row in ipairs(list.rows) do
                    local take = row.take
                    if take == nil then take = "sell" end
                    byTake[take] = byTake[take] or {}
                    local g = byTake[take]
                    g[#g + 1] = row
                end
                for _, kind in ipairs(ns.Banker.TAKES) do
                    local g = byTake[kind.take]
                    if g then groups[#groups + 1] = { header = kind.header, rows = g } end
                end
                d.sellGroups = groups
            end
        end
        -- Auction prices: this realm's table, through AuctionLog's read.
        local realm = nil
        local keptLog = ns.AuctionLog.Kept(ctx.store)
        if type(keptLog) == "table" and type(keptLog.realm) == "function" then
            realm = keptLog.realm(ns.AuctionLog.Key(c))
        end
        local nameOf = function(id)
            if type(c) == "table" and type(c.itemInfo) == "function" then
                local info = c.itemInfo(id)
                if type(info) == "table" then return info.name end
            end
            return nil
        end
        local rows = ns.PriceList.Rows(realm, nameOf)
        d.priceRows = ns.PriceList.Filter(rows, view.search)
        d.priceHead = ns.PriceList.Header(#d.priceRows, #rows, view.search)
        if type(c) == "table" and type(c.clock) == "function" then d.priceNow = c.clock() end
        return d
    end

    render = function()
        if not handle then return end
        local tab = view.tab
        if tab == nil then tab = W.TAB_IN end
        local tree = ns.Kit.Window({ id = W.ID, title = tostring((k.id or ns.id).title) .. ": " .. W.TITLE,
            width = W.KIT_WIDTH, height = W.KIT_HEIGHT, point = W.DEFAULT_POINT,
            children = W.Children(tab, data(), acts) })
        if tree then handle.update(tree) end
    end

    -- The banker word also opens the window (E-25). Wrapped once, at the
    -- start: Items/Banker.lua loads after this file, so the word is only
    -- there by then.
    local wrapped = false
    local function wrapWord()
        if wrapped then return end
        wrapped = true
        if type(diag) ~= "table" or type(diag.commands) ~= "table" then return end
        local word = diag.commands[ns.Banker.WORD]
        if type(word) ~= "function" then return end
        diag.commands[ns.Banker.WORD] = function(...)
            local out = word(...)
            api.show()
            return out
        end
    end

    k:Module({
        name = W.NAME,
        needs = { "client", "store", "bus" },
        provides = { Show = function(tab) return api.show(tab) end },
        start = function(c)
            ctx = c
            started = true
            wrapWord()
            local id = k.id or ns.id
            local making = true
            local tree = ns.Kit.Window({ id = W.ID, title = tostring(id.title) .. ": " .. W.TITLE,
                width = W.KIT_WIDTH, height = W.KIT_HEIGHT, point = W.DEFAULT_POINT,
                children = W.Children(W.TAB_IN, {}, acts) })
            if tree and type(ctx.client.kitWindow) == "function" then
                local point, width, height = ns.Kit.Place(ctx.store:get("account", W.LAYOUT), tree)
                handle = ctx.client.kitWindow(W.ID, tree, {
                    name = id.framePrefix .. "Banker",
                    point = point, width = width, height = height,
                    onMoved = function(to, w, h)
                        if type(to) ~= "table" then return end
                        ctx.store:set("account", W.LAYOUT,
                            { point = { to[1], to[2], to[3], to[4] }, width = w, height = h })
                    end,
                    failed = function(err)
                        if not making then k.problems:add(W.NAME, "window", tostring(err)) end
                    end,
                })
            end
            making = false
            if handle then handle.show(false) end
            -- The bank opening or closing, or the reservations changing,
            -- remakes an open window (its To bank and To sell views read
            -- both). A closed window is left alone.
            local function refresh()
                if handle and handle.shown() then render() end
            end
            ctx.bus:on(W.NAME, "BANKFRAME_OPENED", refresh)
            ctx.bus:on(W.NAME, "BANKFRAME_CLOSED", refresh)
            ctx.bus:on(W.NAME, ns.Reservations.CHANGED, refresh)
        end,
        stop = function()
            if handle then handle.show(false) end
            started = false
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.bankerWindow = W.Declare(ns, ns.diag)
