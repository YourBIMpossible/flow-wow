-- Inventory list (parity row E-27): the word "inventory" on the slash
-- command lists every item in the bags with what the sell rules say of it
-- (sell or keep) and why, anywhere: no merchant window is needed. The
-- earlier add-on had the same word; this is its list on the window kit.
--
-- The verdicts are the sell list's own: one SellList.Listing (UI/SellList.lua:
-- Items/Sell.lua and Items/SellView.lua on Disposition's rules, with the
-- never-sell list, the saved sets, the profession materials and what the
-- reservations hold in the bags), so this window and the merchant's sell
-- list never disagree. The rows are the listing's three parts in one order:
--   sell           the rows the sell list would offer
--   keep           what a rule keeps, and what no rule sells or no merchant
--                  buys (the sell list's "Not sold, and why")
--   not known yet  a price the game has not read, or reservations that
--                  could not be worked out: no verdict is given on a guess
--   not read yet   an item the game gave no facts for: never a verdict
-- Sell rows first, then keep, then the two that are not verdicts.
--
-- LOOK ONLY. Nothing here sells, buys, uses, moves or deletes anything,
-- and the window has no button and no footer slot for one.
--
--   InventoryList.Rows(listing)   -> rows, slots   nil rows: the bags were
--                                    not read. slots: stacks that are not a
--                                    readable item
--   InventoryList.TreeOf(listing, client, id) -> a Kit.Window spec
--   InventoryList.LinesOf(listing) -> the same as text lines (chat, on a
--                                    client that cannot draw the kit)
--   InventoryList.Declare(k, diag) -> api
--     api.show()    lists now and shows the window (or prints the lines).
--                   -> true, or false and why
--     api.last()    the lines of the last listing, nil before the first
--     api.window()  the kit window's handle, nil until it was drawn
--
-- While the window is shown it follows the bags, late item facts and the
-- reservations (at most one listing per frame). Closed, nothing is read.
-- Saved data (written): where the player left the window, at
-- InventoryList.LAYOUT (account), as UI/SellList.lua saves its own.
-- Not tested in game.
local _, ns = ...

local IL = ns.InventoryList or {}
ns.InventoryList = IL

IL.NAME = "inventoryList"
IL.WORD = "inventory"
IL.HELP = "every item in your bags, with whether it would be sold or kept and why (sells nothing)"
IL.KIT_ID = "InventoryList"
IL.KIT_WIDTH, IL.KIT_HEIGHT = 420, 480
IL.LIST_HEIGHT = 400
IL.DEFAULT_POINT = { "CENTER", "CENTER", 0, 0 }
IL.LAYOUT = "layout.inventoryList"     -- account: { point, width, height }
-- Player text.
IL.TITLE = "Inventory"
IL.HEAD = "%d to sell, %d to keep"
IL.HEAD_UNKNOWN = ", %d not known yet"
IL.HEAD_UNREAD = ", %d not read yet"
IL.BAGS_UNREAD_HEAD = "Bags not read yet"
IL.BAGS_UNREAD = "Your bags have not been read yet."
IL.EMPTY_HEAD = "No items"
IL.EMPTY = "No items were found in your bags."
IL.AGAIN = "Type %s %s to list them again."
IL.NOT_LOADED = "The inventory list has not started yet; try again after login."
-- Why show() showed nothing (for the caller; not player text).
IL.NOT_STARTED = "the inventory list has not started"
-- The four kinds of row, in the order shown: the word a row says first,
-- its section, and its tone on the kit (none: plain).
IL.KINDS = { "sell", "keep", "unknown", "unread" }
IL.WORDS = { sell = "sell", keep = "keep", unknown = "not known yet", unread = "not read yet" }
IL.SECTIONS = { sell = "To sell", keep = "To keep", unknown = "Not known yet", unread = "Not read yet" }
IL.TONES = { sell = "warn", keep = "good" }
-- The sell list's "Not sold" rows that are a keep: no merchant buys it, or
-- no rule sells it. Its other two (price not read, reservations not known)
-- are not verdicts.
IL.KEPT_WHY = { WHY_NO_PRICE = true, WHY_NO_RULE = true }

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

-- Every bag item of a listing (SellList.Listing's) as one list of rows,
-- { key, name, count, quality, kind, reason }, in IL.KINDS' order and,
-- within a kind, the order first met. An item a rule keeps part of has a
-- keep row and a sell row, each with its own count.
function IL.Rows(listing)
    listing = type(listing) == "table" and listing or {}
    local stacks = listing.stacks
    if type(stacks) ~= "table" then return nil, 0 end
    local rows, shown = {}, {}
    local function add(src, kind, reason)
        rows[#rows + 1] = { key = src.key, name = src.name, count = src.count, quality = src.quality,
            kind = kind, reason = reason }
        shown[src.key] = true
    end
    -- No sell row while the reservations are not known (the listing has
    -- no list then).
    local list = nil
    if not listing.unavailable and type(listing.list) == "table" then list = listing.list end
    if list and list.ok and type(list.rows) == "table" then
        for _, r in ipairs(list.rows) do add(r, "sell", r.reason) end
    end
    local kept = type(listing.kept) == "table" and type(listing.kept.rows) == "table" and listing.kept.rows or {}
    for _, r in ipairs(kept) do add(r, "keep", r.reason) end
    local others = type(listing.others) == "table" and listing.others or {}
    for _, o in ipairs(others) do
        if IL.KEPT_WHY[o.why] then add(o, "keep", o.reason) end
    end
    for _, o in ipairs(others) do
        if not IL.KEPT_WHY[o.why] then add(o, "unknown", o.reason) end
    end
    -- What is left was not read: one row per item, its stacks counted
    -- together; a stack that is no readable item at all is only counted.
    local unread, slots = {}, 0
    for i = 1, #stacks do
        local s = stacks[i]
        local key = nil
        if type(s) == "table" then key = ns.Items.Key(s.item) end
        if key == nil then
            slots = slots + 1
        elseif not shown[key] then
            local row = unread[key]
            if not row then
                row = { key = key, count = 0, kind = "unread" }
                unread[key] = row
                rows[#rows + 1] = row
            end
            if row.count ~= nil and isCount(s.count) then
                row.count = row.count + s.count
            else
                row.count = nil
            end
        end
    end
    return rows, slots
end

-- The header: how many rows of each kind. slots count as not read.
function IL.Head(rows, slots)
    local n = { sell = 0, keep = 0, unknown = 0, unread = tonumber(slots) or 0 }
    for _, r in ipairs(rows) do n[r.kind] = (n[r.kind] or 0) + 1 end
    local text = IL.HEAD:format(n.sell, n.keep)
    if n.unknown > 0 then text = text .. IL.HEAD_UNKNOWN:format(n.unknown) end
    if n.unread > 0 then text = text .. IL.HEAD_UNREAD:format(n.unread) end
    return text
end

-- What a row says after its item: the word, and why when a reason is known.
function IL.Note(row)
    local word = IL.WORDS[row.kind] or IL.WORDS.unread
    if type(row.reason) == "string" and row.reason ~= "" then return word .. ": " .. row.reason end
    return word
end

-- One row as a text line: "sell: 5 x Broken Fang (junk)".
function IL.RowText(row)
    local Present = ns.ItemPresent
    local name = row.name
    if type(name) ~= "string" or name == "" then name = Present.Name(row.key) end
    local text = (IL.WORDS[row.kind] or IL.WORDS.unread) .. ": "
    if isCount(row.count) then text = text .. row.count .. " x " end
    text = text .. tostring(Present.Tint(name, row.quality))
    if type(row.reason) == "string" and row.reason ~= "" then text = text .. " (" .. row.reason .. ")" end
    return text
end

local function again(id)
    return IL.AGAIN:format(tostring(id.slash), IL.WORD)
end

-- A listing as text lines, the header first. id: the identity the slash
-- name is read from (default ns.id).
function IL.LinesOf(listing, id)
    id = type(id) == "table" and id or ns.id
    listing = type(listing) == "table" and listing or {}
    local rows, slots = IL.Rows(listing)
    if not rows then return { IL.TITLE .. ": " .. IL.BAGS_UNREAD .. " " .. again(id) } end
    if #rows == 0 and slots == 0 then return { IL.TITLE .. ": " .. IL.EMPTY } end
    local lines = {}
    if listing.unavailable then
        lines[1] = IL.TITLE .. ": " .. ns.SellList.RESERVATIONS_UNKNOWN
    else
        lines[1] = IL.TITLE .. ": " .. IL.Head(rows, slots)
    end
    for _, r in ipairs(rows) do lines[#lines + 1] = IL.RowText(r) end
    if slots > 0 then lines[#lines + 1] = ns.ItemPresent.BankUnreadText(slots, true) end
    return lines
end

-- A listing as a Kit.Window spec: a header with the counts, then one item
-- line per row under its kind's section. client: for the icons and the
-- quality colours (SellList.Look). No footer and no button.
function IL.TreeOf(listing, client, id)
    id = type(id) == "table" and id or ns.id
    listing = type(listing) == "table" and listing or {}
    local SellList = ns.SellList
    local rows, slots = IL.Rows(listing)
    local title
    local body = {}
    if not rows then
        title = IL.BAGS_UNREAD_HEAD
        body[1] = { kind = "empty", text = IL.BAGS_UNREAD, how = again(id) }
    elseif #rows == 0 and slots == 0 then
        title = IL.EMPTY_HEAD
        body[1] = { kind = "empty", text = IL.EMPTY, how = again(id) }
    else
        title = IL.Head(rows, slots)
        -- What the goals hold is not known: said, as the sell list says it.
        if listing.unavailable then
            title = SellList.UNKNOWN_HEAD
            body[#body + 1] = { kind = "line", text = SellList.UNKNOWN_HOW, tone = "warn", wrap = true }
        end
        local look = SellList.Look(client, listing.stacks)
        local kind = nil
        for _, r in ipairs(rows) do
            if r.kind ~= kind then
                kind = r.kind
                body[#body + 1] = { kind = "section", text = IL.SECTIONS[kind] or IL.SECTIONS.unread }
            end
            local line = SellList.ItemLine(r, look)
            line.note = IL.Note(r)
            line.tone = IL.TONES[r.kind]
            body[#body + 1] = line
        end
        if slots > 0 then
            body[#body + 1] = { kind = "line", text = ns.ItemPresent.BankUnreadText(slots, true), tone = "warn" }
        end
    end
    return {
        id = IL.KIT_ID, title = tostring(id.title) .. ": " .. IL.TITLE,
        width = IL.KIT_WIDTH, height = IL.KIT_HEIGHT, point = IL.DEFAULT_POINT,
        children = {
            { kind = "header", title = title },
            { kind = "scroll", height = IL.LIST_HEIGHT, children = body },
        },
    }
end

-- Declares the module on kernel k and adds the word to diag.commands.
-- Usable at once: before login the word says the list has not started.
function IL.Declare(k, diag)
    local api = {}
    local ctx = nil
    local handle = nil
    local last = nil
    -- shown: the player has the window open (it follows the bags then).
    -- making: the window is being made, so a kit that will not draw is the
    -- chat lines' turn, not a problem.
    local shown, making = false, false
    function api.last() return last end
    function api.window() return handle end

    -- One listing, as the sell list makes it at a merchant: the
    -- reservations worked out now, and what they hold in the bags.
    local function listing()
        local SellList = ns.SellList
        local r = SellList.Current(ctx.use)
        return SellList.Listing(ctx.client, ctx.store, SellList.Held(r), r)
    end

    -- The kit window of a listing: true when it was drawn.
    local function draw(l, id)
        local client = ctx.client
        if type(client.kitWindow) ~= "function" then return false end
        local tree, why = ns.Kit.Window(IL.TreeOf(l, client, id))
        if not tree then
            k.problems:add(IL.NAME, "tree", tostring(why))
            return false
        end
        if not handle then
            local point, width, height = ns.Kit.Place(ctx.store:get("account", IL.LAYOUT), tree)
            making = true
            handle = client.kitWindow(IL.KIT_ID, tree, {
                name = id.framePrefix .. "InventoryList",
                point = point, width = width, height = height,
                onMoved = function(to, w, h)
                    if type(to) ~= "table" then return end
                    ctx.store:set("account", IL.LAYOUT,
                        { point = { to[1], to[2], to[3], to[4] }, width = w, height = h })
                end,
                onClose = function() shown = false end,
                failed = function(err)
                    if not making then k.problems:add(IL.NAME, "window", tostring(err)) end
                end,
            })
            making = false
            if not handle then return false end
        elseif handle.update(tree) == false then
            return false
        end
        handle.show(true)
        shown = true
        return true
    end

    -- Asked for (the word): lists now and shows the window; on a client
    -- that cannot draw it, the same lines go to chat.
    function api.show()
        if not ctx then return false, IL.NOT_STARTED end
        local id = k.id or ns.id
        local l = listing()
        last = IL.LinesOf(l, id)
        if draw(l, id) then return true end
        if type(ctx.client.print) == "function" then
            for i = 1, #last do ctx.client.print(tostring(id.title) .. ": " .. last[i]) end
        end
        return true
    end

    -- Lists again while the window is shown. Nothing when it is not: a
    -- closed window reads nothing and prints nothing.
    function api.refresh()
        if not ctx or not handle or not shown then return end
        local id = k.id or ns.id
        local l = listing()
        last = IL.LinesOf(l, id)
        draw(l, id)
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[IL.WORD] = function()
            if api.show() then return end
            local id = k.id or ns.id
            local client = k.client
            if type(client) == "table" and type(client.print) == "function" then
                client.print(tostring(id.title) .. ": " .. IL.NOT_LOADED)
            end
        end
        if type(diag.help) == "table" then diag.help[IL.WORD] = IL.HELP end
    end

    k:Module({
        name = IL.NAME,
        needs = { "client", "store", "bus", "sched" },
        provides = { Show = function() return api.show() end, Last = api.last },
        start = function(c)
            ctx = c
            -- The bags changed, item facts arrived late or the reservations
            -- changed: the shown window follows, at most once a frame (a
            -- cold open fires a burst of item reads).
            local pending = false
            local function follow()
                if pending or not shown then return end
                pending = true
                c.sched:nextFrame(IL.NAME, function()
                    pending = false
                    api.refresh()
                end)
            end
            c.bus:on(IL.NAME, ns.SellList.BAG_EVENT, follow)
            c.bus:on(IL.NAME, ns.SellList.INFO_EVENT, follow)
            c.bus:on(IL.NAME, ns.Reservations.CHANGED, follow)
        end,
        -- Stopped: the window goes, and nothing follows the bags.
        stop = function()
            if handle then handle.show(false) end
            shown = false
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.inventoryList = IL.Declare(ns, ns.diag)
