local _, ns = ...

-- The merchant upgrade marks on screen (F4): when a merchant window opens,
-- the upgrades on sale (Gear/MerchantMarks.lua) are shown as advisor prompts
-- (UI/Advisor.lua); when it closes, they go. Look only: nothing is bought,
-- picked up or equipped, and the merchant window itself is not touched.
--
--   api = GearMerchantShow.Declare(k[, packs])
--     api.shown()    the prompt ids shown now, in order
--     api.errors()   how many merchant visits could not be worked out
--   ns.use(GearMerchantShow.NAME) -> { Shown = api.shown, Errors = api.errors }
--
-- One prompt per line of GearMerchantMarks.Text: "2 upgrades on sale here",
-- then one per item ("<item link>: Upgrade for your head piece (+5, dps);
-- 25s 40c", with ", more than you have" when it costs more than the
-- player's money: client.money(), pcall'd; no read, or one that raises,
-- says no such thing),
-- or "No upgrades on sale here" when gear was looked at and none is. No gear
-- on sale, or a merchant that cannot be read: no prompt.
--
-- Setting: gear.merchantMarks (bool, account, on by default), "Point out
-- upgrades at merchants". Off: nothing is worked out at the next merchant;
-- prompts already up go when that merchant closes.
--
-- Events: MERCHANT_SHOW and MERCHANT_CLOSED, through the bus, after
-- client.watchMerchant() so the client knows the window is open first.

local M = {}
ns.GearMerchantShow = M

M.NAME = "gearMerchantShow"
M.SETTING = "gear.merchantMarks"
M.ID = "gear.merchant."      -- prompt ids: this and the line number
M.PRIORITY = 1

-- The player's copper, or nil: no read, a read that raises, not a number.
local function moneyOf(client)
    if type(client) ~= "table" or type(client.money) ~= "function" then return nil end
    local ok, copper = pcall(client.money)
    if ok and type(copper) == "number" then return copper end
    return nil
end

function M.Declare(k, packs)
    local api = {}
    local shown, errors, seen = {}, 0, {}
    function api.shown()
        local out = {}
        for i = 1, #shown do out[i] = shown[i] end
        return out
    end
    function api.errors() return errors end

    local function clear(advisor)
        for i = 1, #shown do
            if advisor then advisor.Remove(shown[i]) end
        end
        shown = {}
    end

    k:Module({
        name = M.NAME,
        needs = { "client", "store", "bus", "advisor" },
        settings = { {
            key = M.SETTING, scope = "account", type = "bool", default = true,
            label = "Point out upgrades at merchants",
            help = "When you open a merchant, list the items on sale that are upgrades for you. It buys nothing.",
            group = "gear", synonyms = { "upgrade", "vendor", "merchant", "buy" },
        } },
        provides = { Shown = api.shown, Errors = api.errors },
        start = function(ctx)
            local advisor = ctx.use("advisor")
            if type(ctx.client.watchMerchant) == "function" then ctx.client.watchMerchant() end
            ctx.bus:on(M.NAME, "MERCHANT_SHOW", function()
                clear(advisor)
                if ctx.settings:get(M.SETTING) ~= true or type(advisor) ~= "table" then return end
                local ok, marks, info = pcall(ns.GearMerchantMarks.Marks, ctx.client, packs or ns.Packs)
                if not ok then
                    errors = errors + 1
                    local text = tostring(marks)
                    if not seen[text] then
                        seen[text] = true
                        k.problems:add("gear", "merchant marks", text)
                    end
                    return
                end
                local lines = ns.GearMerchantMarks.Text(marks, info, { money = moneyOf(ctx.client) })
                for i = 1, #lines do
                    local id = M.ID .. i
                    if advisor.Add(id, lines[i], M.PRIORITY) then shown[#shown + 1] = id end
                end
            end)
            ctx.bus:on(M.NAME, "MERCHANT_CLOSED", function() clear(advisor) end)
        end,
        stop = function()
            clear(k.use and k.use("advisor") or nil)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gearMerchantShow = M.Declare(ns)
