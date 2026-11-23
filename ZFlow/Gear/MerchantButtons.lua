local _, ns = ...

-- S20 vendor upgrade marks on the merchant's own item buttons. Legacy Flow's
-- Modules/Gear/MerchantMarks.lua ("when I go to an item vendor it should
-- show me if the items are upgrades") badged each piece of gear on the
-- vendor's buttons and followed the window's pages; Z-Flow already says the
-- upgrades as advisor prompts (Gear/MerchantShow.lua, F4). This puts the
-- mark on the button too: a green arrow up on each item Gear/MerchantMarks.lua
-- finds is an upgrade. Research: WoW/from-plexy/RESEARCH-vendor-marks.md.
-- With it, as legacy Flow's Modules/Gear/SpecBadge.lua did, a small badge
-- per role the class pack has (the chosen spec.role first): up, down or
-- same against what you wear (GearMerchantMarks.Specs; can't use or no
-- verdict: none for that role), drawn by client.markMerchantSpecs on the
-- same pages, at the same times, as the arrows.
--
-- Marked again when the window opens or changes (MERCHANT_SHOW,
-- MERCHANT_UPDATE), draws a new page or the buyback tab (client
-- onMerchantRedraw), and when you put something on (PLAYER_EQUIPMENT_CHANGED);
-- once more RETRY seconds later when an item was not loaded yet (no
-- verdict), as legacy Flow did. Look only: nothing is bought or picked up,
-- and nothing of the window is called.
--
--   GearMerchantButtons.Indexes(marks) -> { [the merchant's item number] = true }
--   GearMerchantButtons.Declare(k, packs) -> api   (api.marked() -> the last count)
local B = {}
ns.GearMerchantButtons = B

B.NAME = "gearMerchantButtons"
B.SETTING = "gear.merchantButtons"
B.RETRY = 0.5
B.ROLE = "spec.role"           -- Rotation/Role.lua's setting

function B.Indexes(marks)
    local out = {}
    for _, m in ipairs(type(marks) == "table" and marks or {}) do
        if type(m) == "table" and type(m.index) == "number" then out[m.index] = true end
    end
    return out
end

function B.Declare(k, packs)
    local api = {}
    local ctx, marked, retried, retry, followed = nil, nil, false, nil, false
    function api.marked() return marked end

    -- The per-role badges; cleared with {}. A client without the call
    -- draws none.
    local function specs(badges)
        local client = ctx.client
        if type(client.markMerchantSpecs) == "function" then client.markMerchantSpecs(badges) end
    end

    local function badges()
        local okRole, role = pcall(ctx.settings.get, ctx.settings, B.ROLE)
        if not okRole then role = nil end
        local ok, out = pcall(ns.GearMerchantMarks.Specs, ctx.client, packs or ns.Packs, role)
        if not ok then
            k.problems:add(B.NAME, "badges", tostring(out))
            return {}
        end
        return out
    end

    local function update()
        local client = ctx.client
        if type(client.markMerchantButtons) ~= "function" then return end
        if ctx.settings:get(B.SETTING) ~= true then
            marked = client.markMerchantButtons({})
            specs({})
            return
        end
        specs(badges())
        local ok, marks, info = pcall(ns.GearMerchantMarks.Marks, client, packs or ns.Packs)
        if not ok then
            k.problems:add(B.NAME, "marks", tostring(marks))
            return
        end
        marked = client.markMerchantButtons(B.Indexes(marks))
        local waiting = type(info) == "table" and type(info.noVerdict) == "number" and info.noVerdict > 0
        if waiting and not retried then
            retried = true
            retry = ctx.sched:after(B.NAME, B.RETRY, update)
        end
    end

    local function fresh()
        retried = false
        if retry then retry() end
        retry = nil
        update()
    end

    local function follow()
        if followed or type(ctx.client.onMerchantRedraw) ~= "function" then return end
        followed = ctx.client.onMerchantRedraw(function()
            if ctx and ctx.client.merchantOpen() == true then fresh() end
        end) == true
    end

    k:Module({
        name = B.NAME,
        needs = { "client", "settings", "bus", "sched" },
        settings = { {
            key = B.SETTING, scope = "account", type = "bool", default = true,
            label = "Mark upgrades on a vendor's item buttons",
            help = "A green arrow on each item a vendor sells that is an upgrade for what you wear. It buys nothing.",
            group = "gear", synonyms = { "upgrade", "vendor", "merchant", "buy" },
        } },
        provides = { Marked = api.marked },
        start = function(c)
            ctx = c
            if type(c.client.watchMerchant) == "function" then c.client.watchMerchant() end
            follow()
            c.bus:on(B.NAME, "MERCHANT_SHOW", function()
                follow()
                fresh()
            end)
            c.bus:on(B.NAME, "MERCHANT_UPDATE", fresh)
            c.bus:on(B.NAME, "PLAYER_EQUIPMENT_CHANGED", function()
                if c.client.merchantOpen() == true then fresh() end
            end)
            c.bus:on(B.NAME, "MERCHANT_CLOSED", function()
                if retry then retry() end
                retry = nil
                if type(c.client.markMerchantButtons) == "function" then marked = c.client.markMerchantButtons({}) end
                specs({})
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gearMerchantButtons = B.Declare(ns)
