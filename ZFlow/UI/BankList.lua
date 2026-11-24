-- Bank list (L6-D): while the bank window is open, a window lists what to
-- put in the bank (Items/Bank.lua): what Z-Flow keeps for you that nothing
-- on your route uses now. Items a step holds are listed apart, as staying.
--
-- The window is one of the shared window kit's (UI/Kit.lua, lead sections
-- 287, 291 item 3 and 303): an item line for each row, with its icon, its
-- name in the item's quality colour, its count and why. A client that
-- cannot draw the kit gets the same listing as text on a plain panel.
--
-- LOOK ONLY. No buttons; nothing here deposits, withdraws, moves or clicks.
--
--   BankList.Lines(client, store, grants, r) -> lines   one listing as text
--   BankList.Tree(client, store, grants, r, id) -> a Kit.Window spec of the
--     same listing. id: the identity for the title (default ns.id)
--   BankList.Current(use) -> r, one Reservations evaluation (Items/Reservations.lua)
--   BankList.Declare(k) -> api   (api.last(), api.shows())
--   ns.use(BankList.NAME) -> { Last, Shows }
--
-- Setting: "bank.list" (bool, on by default); the row is the lead's to add.
-- Until it is there the list is on.
-- Reads: client.watchBank / BANKFRAME_OPENED / BANKFRAME_CLOSED,
-- Reservations.CHANGED (internal, sent by a source),
-- client.bagItems(), client.itemInfo(item) (CLIENT NEED, as the sell list).
-- client.itemTexture(item) (the icon: a texture name or file number),
-- client.kitWindow(id, tree, extra) (client.panel when the kit cannot draw).
-- Saved data (read only): char settings.sell.never, account
-- settings.banker.rules ({ [item] = "bank" | "carry" }, imported from Flow).
-- Saved data (written): where the player left the window and its size, at
-- BankList.LAYOUT (account).
-- grants: what the bags hold for the player's goals, from one Reservations
-- evaluation (Reservations.HeldIn(grants, "bags")). The prompt and the panel
-- of one bank visit share that evaluation; a Reservations.CHANGED while the
-- bank is open makes a new one and lists again, once (section 219). When it
-- is unavailable nothing is shown as held, and the list says the
-- reservations are not known.
-- Not tested in game.
local _, ns = ...

local BankList = ns.BankList or {}
ns.BankList = BankList

BankList.NAME = "bankList"
BankList.BAG_EVENT = "BAG_UPDATE_DELAYED"
BankList.SETTING = "bank.list"
BankList.WIDTH, BankList.HEIGHT = 340, 260              -- the text panel
BankList.KIT_ID = "BankList"
BankList.KIT_WIDTH, BankList.KIT_HEIGHT = 420, 480
BankList.LIST_HEIGHT = 360
BankList.LAYOUT = "layout.bankList"     -- account: { point, width, height }
-- The kit window's own words.
BankList.TITLE = "Bank list"
BankList.BANK_SECTION = "To bank"
BankList.HELD_SECTION = "Staying with you"
BankList.HELD_NOTE = "held for your steps"
BankList.NOTHING = "Nothing to bank."
BankList.NOTHING_HOW = "Nothing in your bags is kept for later."
BankList.UNREAD_HEAD = "Can't list what to bank"
BankList.NEVER_SEEN = "No bank data yet."
BankList.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 360, -120 }
-- The advisor prompt (UI/Advisor.lua: Add(id, text, priority), Remove(id)):
-- "Put in your bank for later: Linen Cloth x12, Copper Ore x5" (ItemPresent.BankPrompt) while
-- the bank window is open and there is something to bank; removed when the
-- bank closes (lead sections 340/341: raised only at the bank).
-- A low priority, a first guess: it is a chore, not a warning.
BankList.ADVISOR = "advisor"
BankList.PROMPT_ID = "l6d.bank"
BankList.PROMPT_PRIORITY = 10
BankList.RESERVATIONS_UNKNOWN = "Reservations not known: what your goals hold is not counted here."

local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

-- A saved table keyed by item, re-keyed by Items.Key; values kept.
local function byKey(raw, want)
    local out = {}
    if type(raw) == "table" then
        for k, v in pairs(raw) do
            local key = ns.Items.Key(k)
            if key ~= nil and (want == nil or want(v)) then out[key] = v end
        end
    end
    return out
end

-- The decision context from the player's saved choices: the never-sell list
-- and the bank rules. Items/Banker.lua decides the bank's items with it too.
function BankList.Context(store, grants)
    local never = byKey(saved(store, "char", "settings.sell.never"), function(v) return v and true or false end)
    for key in pairs(never) do never[key] = true end
    return {
        grants = grants,
        choices = { never = never },
        bankRules = byKey(saved(store, "account", "settings.banker.rules"),
            function(v) return v == "bank" or v == "carry" end),
        -- P-SETS: saved gear set pieces are kept (Disposition's inSet).
        sets = ns.GearSets and ns.GearSets.Facts(store) or nil,
    }
end

-- What to bank, worked out from the bags now: Bank.Pick's result.
function BankList.Pick(client, store, grants)
    local stacks = type(client) == "table" and type(client.bagItems) == "function" and client.bagItems() or nil
    local read = type(client) == "table" and type(client.itemInfo) == "function" and client.itemInfo or nil
    return ns.Bank.Pick(ns.Bank.Entries(stacks, read), BankList.Context(store, grants))
end

-- r: the evaluation the grants came from, when there is one; unavailable
-- adds the line that says so (not when the bags themselves weren't read:
-- the list already says it can't be made).
function BankList.LinesOf(pick, r)
    local lines = ns.ItemPresent.BankLines(pick)
    if pick.ok and type(r) == "table" and r.status == ns.Reservations.UNAVAILABLE then
        lines[#lines + 1] = BankList.RESERVATIONS_UNKNOWN
    end
    return lines
end

function BankList.Lines(client, store, grants, r)
    return BankList.LinesOf(BankList.Pick(client, store, grants), r)
end

local function plural(n, one, many)
    if n == 1 then return n .. " " .. one end
    return n .. " " .. many
end

-- A pick (BankList.Pick's) as a Kit.Window spec. client: for the icons and
-- the quality colours (SellList.Look, the same read as the sell list's).
-- r: the evaluation the grants came from; unavailable adds the line that
-- says so, as in Lines. id: the identity the title names the add-on from.
function BankList.TreeOf(pick, client, r, id)
    id = type(id) == "table" and id or ns.id
    pick = type(pick) == "table" and pick or {}
    local Present = ns.ItemPresent
    local stacks
    if type(client) == "table" and type(client.bagItems) == "function" then stacks = client.bagItems() end
    local look = ns.SellList.Look(client, stacks)
    local rows = pick.ok and type(pick.rows) == "table" and pick.rows or {}
    local held = pick.ok and type(pick.held) == "table" and pick.held or {}
    local unread = type(pick.unread) == "number" and pick.unread > 0 and pick.unread or 0
    local title, says = BankList.TITLE, BankList.TITLE
    local body = {}
    if not pick.ok then
        body[#body + 1] = { kind = "empty", text = BankList.UNREAD_HEAD .. ".", how = Present.BAGS_UNREAD }
    elseif #rows == 0 and unread > 0 then
        -- Items whose kind was not read are not "nothing to bank".
        body[#body + 1] = { kind = "empty", text = Present.BANK_UNREAD_HEAD .. ".",
            how = Present.BankUnreadText(unread, true) }
    elseif #rows == 0 then
        title = Present.NOTHING_TO_BANK
        says = Present.NOTHING_TO_BANK
        body[#body + 1] = { kind = "empty", text = BankList.NOTHING, how = BankList.NOTHING_HOW }
    else
        title = plural(#rows, "kind", "kinds") .. " of item to bank"
        says = title
        body[#body + 1] = { kind = "section", text = BankList.BANK_SECTION }
        for _, row in ipairs(rows) do
            local line = ns.SellList.ItemLine(row, look)
            line.note = tostring(row.reason or "kept for later")
            body[#body + 1] = line
        end
        if unread > 0 then
            body[#body + 1] = { kind = "line", text = Present.BankUnreadText(unread, false), tone = "warn" }
        end
    end
    if #held > 0 then
        says = says .. ", " .. #held .. " staying with you"
        body[#body + 1] = { kind = "section", text = BankList.HELD_SECTION }
        for _, row in ipairs(held) do
            local line = ns.SellList.ItemLine(row, look)
            line.note = BankList.HELD_NOTE
            line.tone = "good"
            body[#body + 1] = line
        end
    end
    if pick.ok and type(r) == "table" and r.status == ns.Reservations.UNAVAILABLE then
        body[#body + 1] = { kind = "line", text = BankList.RESERVATIONS_UNKNOWN, tone = "warn" }
    end
    return {
        id = BankList.KIT_ID, title = tostring(id.title) .. ": " .. BankList.TITLE,
        width = BankList.KIT_WIDTH, height = BankList.KIT_HEIGHT, point = BankList.DEFAULT_POINT,
        children = {
            { kind = "header", title = title },
            { kind = "scroll", height = BankList.LIST_HEIGHT, children = body },
            { kind = "footer", text = says },
        },
    }
end

function BankList.Tree(client, store, grants, r, id)
    return BankList.TreeOf(BankList.Pick(client, store, grants), client, r, id)
end

-- The window before the bank was ever opened: it says what is missing.
function BankList.ClosedTree(id)
    id = type(id) == "table" and id or ns.id
    return {
        id = BankList.KIT_ID, title = tostring(id.title) .. ": " .. BankList.TITLE,
        width = BankList.KIT_WIDTH, height = BankList.KIT_HEIGHT, point = BankList.DEFAULT_POINT,
        children = {
            { kind = "header", title = BankList.TITLE },
            { kind = "scroll", height = BankList.LIST_HEIGHT, children = {
                { kind = "empty", text = BankList.NEVER_SEEN,
                  how = "Open your bank once and " .. tostring(id.title) .. " will remember it." },
            } },
            { kind = "footer", text = BankList.TITLE },
        },
    }
end

-- One evaluation of the reservations, through ctx.use. The module not being
-- there, or raising, is "unavailable", never "none".
function BankList.Current(use)
    local ok, mod = pcall(use, ns.Reservations.NAME)
    if ok and type(mod) == "table" and type(mod.Current) == "function" then
        local fine, r = pcall(mod.Current)
        if fine and type(r) == "table" then return r end
    end
    return { status = ns.Reservations.UNAVAILABLE }
end

-- What the bags hold, from an evaluation: the grants Pick takes.
function BankList.Held(r)
    return ns.Reservations.HeldIn(ns.Reservations.Grants(r), "bags")
end

function BankList.Declare(k)
    local api = {}
    local last, shows = nil, 0
    -- win: the kit window. panel: the text panel, made only when the kit
    -- cannot draw.
    local win, panel
    -- The player closed the window (its close button, Escape): it stays
    -- closed for that bank visit; the next BANKFRAME_OPENED clears it.
    local closed = false
    function api.last() return last end
    function api.shows() return shows end
    function api.window() return win end

    local function hide()
        if win then win.show(false) end
        if panel then panel.show(false) end
    end

    k:Module({
        name = BankList.NAME,
        needs = { "client", "store", "bus", "settings" },
        provides = { Last = api.last, Shows = api.shows },
        start = function(ctx)
            local client = ctx.client
            local id = k.id or ns.id
            if type(client.watchBank) == "function" then client.watchBank() end
            -- The text panel: the same listing on a client that cannot
            -- draw the kit. Made once, when first needed.
            local function textPanel()
                if panel then return panel end
                panel = client.panel({ name = id.framePrefix .. "BankList",
                    width = BankList.WIDTH, height = BankList.HEIGHT })
                if panel then
                    panel.show(false)
                    panel.place(BankList.DEFAULT_POINT)
                end
                return panel
            end
            -- The kit window of a pick: true when it was drawn.
            local function draw(pick, r)
                if not win then return false end
                local tree = ns.Kit.Window(BankList.TreeOf(pick, client, r, id))
                if not tree or win.update(tree) == false then return false end
                win.show(true)
                return true
            end
            -- The advisor prompt. The advisor is looked up each time and never
            -- needed: without it, or when it raises, the list works as before.
            -- Given only on a change of the text, so nothing is re-added on
            -- every check and nothing is removed that was never added.
            local prompted = nil
            local open
            local function prompt(r)
                local text = nil
                if open and ctx.settings:get(BankList.SETTING) ~= false then
                    r = r or BankList.Current(ctx.use)
                    local ok, pick = pcall(BankList.Pick, client, ctx.store, BankList.Held(r))
                    text = ok and ns.ItemPresent.BankPrompt(pick) or nil
                end
                if text == prompted then return end
                prompted = text
                local ok, advisor = pcall(ctx.use, BankList.ADVISOR)
                if not ok or type(advisor) ~= "table" then return end
                if text then
                    if type(advisor.Add) == "function" then
                        pcall(advisor.Add, BankList.PROMPT_ID, text, BankList.PROMPT_PRIORITY)
                    end
                elseif type(advisor.Remove) == "function" then
                    pcall(advisor.Remove, BankList.PROMPT_ID)
                end
            end
            -- The bank window is open: read at the start, so a start while
            -- the bank stays open (an interface load at the bank, lead
            -- section 223 BR-1) is not taken as closed; then set on
            -- BANKFRAME_OPENED, cleared on BANKFRAME_CLOSED. Not known is
            -- not open. Needs game test: the first read before any bank
            -- event is BankFrame:IsShown() (Core/Client.lua).
            open = type(client.bankOpen) == "function" and client.bankOpen() == true
            -- One evaluation for the prompt and the panel: made when the bank
            -- opens, and again when the reservations change while it is open.
            local function list()
                local r = BankList.Current(ctx.use)
                prompt(r)
                if ctx.settings:get(BankList.SETTING) == false then
                    hide()
                    return
                end
                local pick = BankList.Pick(client, ctx.store, BankList.Held(r))
                local lines = BankList.LinesOf(pick, r)
                shows = shows + 1
                last = lines
                if draw(pick, r) then
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
            ctx.bus:on(BankList.NAME, "PLAYER_ENTERING_WORLD", function() prompt() end)
            ctx.bus:on(BankList.NAME, "BANKFRAME_OPENED", function()
                open = true
                closed = false
                list()
            end)
            ctx.bus:on(BankList.NAME, "BANKFRAME_CLOSED", function()
                open = false
                closed = false
                hide()
                prompt()      -- away from the bank: the prompt goes
            end)
            -- A source's claims changed (lead section 219): with the bank
            -- open, the list and the prompt are made again, once. With the
            -- bank closed nothing is drawn.
            ctx.bus:on(BankList.NAME, ns.Reservations.CHANGED, function()
                if not open then return end
                if closed then
                    prompt()
                    return
                end
                list()
            end)
            -- The bags changed: at the bank the prompt follows them, and goes
            -- when there is nothing left to bank; away from it there is none.
            -- A first guess: not seen in game.
            ctx.bus:on(BankList.NAME, BankList.BAG_EVENT, function()
                prompt()
            end)
            -- The kit window, where the player left it; hidden until the
            -- bank opens. A function of the window's that raises is a
            -- problem; the kit not drawing at all is not one: the text
            -- panel stands in.
            local making = true
            local tree = ns.Kit.Window(BankList.ClosedTree(id))
            if tree and type(client.kitWindow) == "function" then
                local point, width, height = ns.Kit.Place(ctx.store:get("account", BankList.LAYOUT), tree)
                win = client.kitWindow(BankList.KIT_ID, tree, {
                    name = id.framePrefix .. "BankList",
                    point = point, width = width, height = height,
                    onMoved = function(to, w, h)
                        if type(to) ~= "table" then return end
                        ctx.store:set("account", BankList.LAYOUT,
                            { point = { to[1], to[2], to[3], to[4] }, width = w, height = h })
                    end,
                    onClose = function()
                        closed = true
                    end,
                    failed = function(err)
                        if not making then k.problems:add(BankList.NAME, "window", tostring(err)) end
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
        stop = function()
            hide()
            closed = false
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.bankList = BankList.Declare(ns)
