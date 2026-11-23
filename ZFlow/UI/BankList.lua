-- Bank list (L6-D): while the bank window is open, a panel lists what to
-- put in the bank (Items/Bank.lua): what Z-Flow keeps for you that nothing
-- on your route uses now. Items a step holds are listed apart, as staying.
--
-- LOOK ONLY. No buttons; nothing here deposits, withdraws, moves or clicks.
--
--   BankList.Lines(client, store, grants, r) -> lines
--   BankList.Current(use) -> r, one Reservations evaluation (Items/Reservations.lua)
--   BankList.Declare(k) -> api   (api.last(), api.shows())
--   ns.use(BankList.NAME) -> { Last, Shows }
--
-- Setting: "bank.list" (bool, on by default); the row is the lead's to add.
-- Until it is there the list is on.
-- Reads: client.watchBank / BANKFRAME_OPENED / BANKFRAME_CLOSED,
-- Reservations.CHANGED (internal, sent by a source),
-- client.bagItems(), client.itemInfo(item) (CLIENT NEED, as the sell list).
-- Saved data (read only): char settings.sell.never, account
-- settings.banker.rules ({ [item] = "bank" | "carry" }, imported from Flow).
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
BankList.WIDTH, BankList.HEIGHT = 340, 260
BankList.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 360, -120 }
-- The advisor prompt (UI/Advisor.lua: Add(id, text, priority), Remove(id)):
-- "N kinds of item to put in the bank." while there is something to bank.
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
function BankList.Lines(client, store, grants, r)
    local pick = BankList.Pick(client, store, grants)
    local lines = ns.ItemPresent.BankLines(pick)
    if pick.ok and type(r) == "table" and r.status == ns.Reservations.UNAVAILABLE then
        lines[#lines + 1] = BankList.RESERVATIONS_UNKNOWN
    end
    return lines
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
    local panel
    function api.last() return last end
    function api.shows() return shows end

    local function hide()
        if panel then panel.show(false) end
    end

    k:Module({
        name = BankList.NAME,
        needs = { "client", "store", "bus", "settings" },
        provides = { Last = api.last, Shows = api.shows },
        start = function(ctx)
            local client = ctx.client
            if type(client.watchBank) == "function" then client.watchBank() end
            -- The advisor prompt. The advisor is looked up each time and never
            -- needed: without it, or when it raises, the list works as before.
            -- Given only on a change of the text, so nothing is re-added on
            -- every check and nothing is removed that was never added.
            local prompted = nil
            local function prompt(r)
                local text = nil
                if ctx.settings:get(BankList.SETTING) ~= false then
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
            local open = type(client.bankOpen) == "function" and client.bankOpen() == true
            -- One evaluation for the prompt and the panel: made when the bank
            -- opens, and again when the reservations change while it is open.
            local function list()
                local r = BankList.Current(ctx.use)
                prompt(r)
                if ctx.settings:get(BankList.SETTING) == false then
                    hide()
                    return
                end
                local lines = BankList.Lines(client, ctx.store, BankList.Held(r), r)
                shows = shows + 1
                last = lines
                if panel then
                    panel.setLines(lines)
                    panel.show(true)
                end
            end
            ctx.bus:on(BankList.NAME, "PLAYER_ENTERING_WORLD", function() prompt() end)
            ctx.bus:on(BankList.NAME, "BANKFRAME_OPENED", function()
                open = true
                list()
            end)
            ctx.bus:on(BankList.NAME, "BANKFRAME_CLOSED", function()
                open = false
                hide()
                prompt()      -- the bags may have changed at the bank
            end)
            -- A source's claims changed (lead section 219): with the bank
            -- open, the list and the prompt are made again, once. With the
            -- bank closed nothing is drawn.
            ctx.bus:on(BankList.NAME, ns.Reservations.CHANGED, function()
                if not open then return end
                list()
            end)
            -- The bags changed away from the bank too: the prompt follows
            -- them, and goes when there is nothing left to bank. A first
            -- guess: not seen in game.
            ctx.bus:on(BankList.NAME, BankList.BAG_EVENT, function()
                prompt()
            end)
            local id = k.id or ns.id
            panel = client.panel({ name = id.framePrefix .. "BankList",
                width = BankList.WIDTH, height = BankList.HEIGHT })
            if panel then
                panel.show(false)
                panel.place(BankList.DEFAULT_POINT)
            end
        end,
        stop = hide,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.bankList = BankList.Declare(ns)
