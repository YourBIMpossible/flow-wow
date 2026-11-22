-- Bank list (L6-D): while the bank window is open, a panel lists what to
-- put in the bank (Items/Bank.lua): what Z-Flow keeps for you that nothing
-- on your route uses now. Items a step holds are listed apart, as staying.
--
-- LOOK ONLY. No buttons; nothing here deposits, withdraws, moves or clicks.
--
--   BankList.Lines(client, store, grants) -> lines
--   BankList.Declare(k) -> api   (api.last(), api.shows())
--   ns.use(BankList.NAME) -> { Last, Shows }
--
-- Setting: "bank.list" (bool, on by default); the row is the lead's to add.
-- Until it is there the list is on.
-- Reads: client.watchBank / BANKFRAME_OPENED / BANKFRAME_CLOSED,
-- client.bagItems(), client.itemInfo(item) (CLIENT NEED, as the sell list).
-- Saved data (read only): char settings.sell.never, account
-- settings.banker.rules ({ [item] = "bank" | "carry" }, imported from Flow).
-- grants: what Resources.Resolve returned, when a caller has it; no module
-- resolves claims yet, so the addon's own list passes none and nothing is
-- shown as held.
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

function BankList.Lines(client, store, grants)
    return ns.ItemPresent.BankLines(BankList.Pick(client, store, grants))
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
            local function prompt()
                local text = nil
                if ctx.settings:get(BankList.SETTING) ~= false then
                    local ok, pick = pcall(BankList.Pick, client, ctx.store, nil)
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
            ctx.bus:on(BankList.NAME, "PLAYER_ENTERING_WORLD", prompt)
            ctx.bus:on(BankList.NAME, "BANKFRAME_OPENED", function()
                prompt()
                if ctx.settings:get(BankList.SETTING) == false then
                    hide()
                    return
                end
                local lines = BankList.Lines(client, ctx.store, nil)
                shows = shows + 1
                last = lines
                if panel then
                    panel.setLines(lines)
                    panel.show(true)
                end
            end)
            ctx.bus:on(BankList.NAME, "BANKFRAME_CLOSED", function()
                hide()
                prompt()      -- the bags may have changed at the bank
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
