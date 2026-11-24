local _, ns = ...

-- Repair cost (reconcile row G2, the part that only shows; lead section 397
-- lane B item 9): at a merchant that repairs, one chat line says what
-- repairing everything costs and what the player has, and which button
-- repairs.
--
-- LOOK ONLY. Nothing here repairs, sells, buys or clicks: it reads the
-- cost and the player's money and says them. Repairing stays the player's
-- own click on the merchant's Repair All button. The stored
-- "sell.autoRepair" is not read: there is no automatic repair.
--
--   RepairCost.Line(cost, money) -> the line, or nil when there is nothing
--     to say (cost not known, or nothing to repair).
--     cost, money: copper; money nil when it was not read.
--   RepairCost.Declare(k) -> api   (api.last(), api.said())
--   ns.use(RepairCost.NAME) -> { Last, Said }
--
-- Module: on MERCHANT_SHOW (through the bus), once per opened window.
-- Reads: client.merchantRepairs(), client.repairCost(), client.money().
-- Setting: "repair.costLine" (bool, on by default; its row is in
-- Settings/Rows.lua, with the bag and bank rows).
-- Not tested in game: whether the cost is already given when MERCHANT_SHOW
-- fires is a first guess.
local RepairCost = ns.RepairCost or {}
ns.RepairCost = RepairCost

RepairCost.NAME = "repairCost"
RepairCost.SETTING = "repair.costLine"
RepairCost.EVENT = "MERCHANT_SHOW"
RepairCost.BUTTON = "Press the merchant's Repair All button."
RepairCost.SHORT = "That is not enough for all of it: repair the worst pieces one at a time with the merchant's Repair button."

local function count(v)
    return type(v) == "number" and v == v and v >= 0 and v < math.huge and v == math.floor(v)
end

-- A money figure the player reads, through Prices (the one place that
-- writes coin text). nil when Prices is not there.
local function coin(copper)
    local P = ns.Prices
    if type(P) ~= "table" or type(P.Text) ~= "function" then return nil end
    local ok, text = pcall(P.Text, { value = copper, basis = P.OBSERVED })
    if ok and type(text) == "string" and text ~= "" then return text end
    return nil
end

function RepairCost.Line(cost, money)
    if not count(cost) or cost == 0 then return nil end
    local costs = coin(cost)
    if costs == nil then return nil end
    local have = count(money) and coin(money) or nil
    if have == nil then
        return "Repairing everything here costs " .. costs .. ". " .. RepairCost.BUTTON
    end
    if money >= cost then
        return "Repairing everything here costs " .. costs .. "; you have " .. have .. ". " .. RepairCost.BUTTON
    end
    return "Repairing everything here costs " .. costs .. "; you have " .. have .. ". " .. RepairCost.SHORT
end

function RepairCost.Declare(k)
    local api = {}
    local last, said = nil, 0
    function api.last() return last end
    function api.said() return said end
    k:Module({
        name = RepairCost.NAME,
        needs = { "client", "bus", "settings" },
        provides = { Last = api.last, Said = api.said },
        start = function(ctx)
            local client = ctx.client
            if type(client.watchMerchant) == "function" then client.watchMerchant() end
            local function ask(name)
                local fn = client[name]
                if type(fn) ~= "function" then return nil end
                local ok, v = pcall(fn)
                if ok then return v end
                return nil
            end
            ctx.bus:on(RepairCost.NAME, RepairCost.EVENT, function()
                last = nil
                if ctx.settings:get(RepairCost.SETTING) == false then return end
                if ask("merchantRepairs") ~= true then return end
                local text = RepairCost.Line(ask("repairCost"), ask("money"))
                if text == nil then return end
                last = text
                said = said + 1
                local id = k.id or ns.id
                client.print(id.title .. ": " .. text)
            end)
        end,
        stop = function() last = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.repairCost = RepairCost.Declare(ns)
