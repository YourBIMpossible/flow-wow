local _, ns = ...

-- S5 have-count on item tooltips: the module that shows Items/TooltipHave.lua's
-- line. Legacy Flow's Modules/Items/HaveCount.lua (0.35.267; the owner asked
-- "When I hover over an item it should tell me if I have any in my bank /
-- bags / total") put one line on every item tooltip; this is that, through
-- Z-Flow's reads. Research: WoW/from-plexy/RESEARCH-have-count.md.
--
--   bags  the bags as they are now (client.bagItems, summed by Items.Key),
--         read again at most once every BAGS_FOR seconds while tooltips fill
--   bank  what the bank held at the last visit, kept for this character at
--         char "learned.bankCounts" = { at = client.clock() or nil,
--         counts = { [itemKey] = count } }: read when the bank opens and
--         again on BAG_UPDATE_DELAYED while it is open (the game only tells
--         add-ons the bank's contents while it is open)
-- Nothing when you have none (TooltipHave.Line). Look only: nothing is
-- moved, deposited or withdrawn.
--
--   HaveTip.Counts(stacks, keyOf) -> { [key] = count }, or nil when the
--     stacks were not read or a stack has no key (never a smaller count)
--   HaveTip.Snapshot(bags, saved) -> what TooltipHave.Line takes
--   HaveTip.Declare(k) -> api   (api.hooked(), api.bankReads())
local H = {}
ns.HaveTip = H

H.NAME = "haveTip"
H.SETTING = "items.haveCount"
H.PATH = "learned.bankCounts"
H.BAGS_FOR = 1
H.COLOUR = { 0.6, 0.85, 1 } -- legacy Flow's light blue

local function whole(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and v == math.floor(v)
end

function H.Counts(stacks, keyOf)
    if type(stacks) ~= "table" or type(keyOf) ~= "function" then return nil end
    local out = {}
    for _, s in ipairs(stacks) do
        if type(s) ~= "table" then return nil end
        local key = keyOf(s.item)
        local n = s.count
        if key == nil or not whole(n) then return nil end
        out[key] = (out[key] or 0) + n
    end
    return out
end

function H.Snapshot(bags, saved)
    local counts = type(saved) == "table" and type(saved.counts) == "table" and saved.counts or nil
    return { bags = bags, bank = counts, bankKnown = counts ~= nil }
end

function H.Declare(k)
    local api = {}
    local ctx, cancel, hooked, bankReads = nil, nil, false, 0
    local bagCache, bagAt = nil, nil
    function api.hooked() return hooked end
    function api.bankReads() return bankReads end

    local function keyOf(item) return ns.Items.Key(item) end

    local function bags()
        local client = ctx.client
        local now = type(client.uptime) == "function" and client.uptime() or nil
        if bagAt ~= nil and type(now) == "number" and now - bagAt < H.BAGS_FOR and now >= bagAt then return bagCache end
        bagCache = H.Counts(client.bagItems(), keyOf)
        bagAt = type(now) == "number" and now or nil
        return bagCache
    end

    local function readBank()
        local client = ctx.client
        if client.bankOpen() ~= true then return end
        local counts = H.Counts(client.bankItems(), keyOf)
        if counts == nil then return end
        local when = type(client.clock) == "function" and client.clock() or nil
        if ctx.store:set("char", H.PATH, { at = whole(when) and when or nil, counts = counts }) then
            bankReads = bankReads + 1
        end
        bagAt = nil -- a deposit changes the bags too
    end

    k:Module({
        name = H.NAME,
        needs = { "client", "store", "settings", "bus" },
        settings = { {
            key = H.SETTING, scope = "account", type = "bool", default = true,
            label = "How many you have, on item tooltips",
            help = "A line on an item's tooltip saying how many you have, in your bags and in your bank. "
                .. "The bank's count is from the last time you had it open.",
            group = "Vendor",
        } },
        provides = { Hooked = api.hooked, BankReads = api.bankReads },
        start = function(c)
            ctx = c
            bagCache, bagAt = nil, nil
            if type(c.client.watchBank) == "function" then c.client.watchBank() end
            c.bus:on(H.NAME, "BANKFRAME_OPENED", readBank)
            c.bus:on(H.NAME, "BAG_UPDATE_DELAYED", function()
                bagAt = nil
                readBank()
            end)
            if type(c.client.onItemTooltip) ~= "function" then return end
            local got = c.client.onItemTooltip(function(link, add)
                if c.settings:get(H.SETTING) ~= true or type(add) ~= "function" then return end
                local key = keyOf(link)
                if key == nil then return end
                local line = ns.TooltipHave.Line(H.Snapshot(bags(), c.store:get("char", H.PATH)), key)
                if line then add(line.text, H.COLOUR[1], H.COLOUR[2], H.COLOUR[3]) end
            end)
            if type(got) == "function" then cancel, hooked = got, true end
        end,
        stop = function()
            if cancel then cancel() end
            cancel, hooked = nil, false
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.haveTip = H.Declare(ns)
