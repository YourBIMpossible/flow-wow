local _, ns = ...

-- G4 (CAPABILITY-RECONCILE row G4, lead section 395): every item tooltip
-- says what the sell rules would do with the item, the same rule as the
-- sell list and the loot note (Disposition.Decide, with your never-sell
-- list, your saved set pieces and what the reservations hold in your bags),
-- in Items/TooltipDisposition.lua's words: "Keep: ...", "Would sell: ...".
-- Look only: nothing is sold, kept, moved or marked.
--
--   lines = DispositionTip.Lines(link, itemInfo, context)  pure; nil: no line
--   api   = DispositionTip.Declare(k)                      api.hooked()
--
-- The reservations are worked out at most once every RESERVE_FOR seconds
-- while tooltips fill; while they cannot be worked out, no line is shown
-- (as the loot note: nothing is advised for sale on a guess).

local DT = {}
ns.DispositionTip = DT

DT.NAME = "dispositionTip"
DT.SETTING = "items.dispositionTip"
DT.RESERVE_FOR = 2   -- seconds; a first guess
DT.COLOUR = {
    good = { 0.1, 1, 0.1 },
    same = { 1, 1, 1 },
    none = { 0.6, 0.6, 0.6 },
}

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function isWhole(n)
    return isCount(n) and n == math.floor(n)
end

function DT.Lines(link, itemInfo, context)
    local key = ns.Items.Key(link)
    if key == nil or type(itemInfo) ~= "function" then return nil end
    local ok, f = pcall(itemInfo, link)
    if not ok or type(f) ~= "table" then return nil end
    local entry = { key = key }
    if type(f.name) == "string" and f.name ~= "" then entry.name = f.name end
    if isWhole(f.quality) then entry.quality = f.quality end
    if isCount(f.sellPrice) then entry.sellPrice = f.sellPrice end
    if isWhole(f.classID) then entry.classID = f.classID end
    return ns.TooltipDisposition.Lines(ns.Disposition.Decide(entry, type(context) == "table" and context or {}))
end

function DT.Declare(k)
    local api = {}
    local cancel, hooked = nil, false
    local grants, grantsAt = nil, nil
    function api.hooked() return hooked end

    -- What the reservations hold in the bags, or nil while not known.
    local function held(ctx)
        local now = type(ctx.client.uptime) == "function" and ctx.client.uptime() or nil
        if type(now) ~= "number" or now ~= now then now = nil end
        if grantsAt ~= nil and now ~= nil and now >= grantsAt and now - grantsAt < DT.RESERVE_FOR then
            return grants
        end
        local r = ns.SellList.Current(ctx.use)
        if type(r) ~= "table" or r.status == ns.Reservations.UNAVAILABLE then
            grants = nil
        else
            grants = ns.Reservations.HeldIn(ns.Reservations.Grants(r), "bags")
        end
        grantsAt = now
        return grants
    end

    k:Module({
        name = DT.NAME,
        needs = { "client", "store", "settings" },
        settings = { {
            key = DT.SETTING, scope = "account", type = "bool", default = true,
            label = "Keep or sell, on item tooltips",
            help = "A line on an item's tooltip saying whether the sell list would keep it or sell it, and why. "
                .. "This line sells nothing.",
            group = "bags", synonyms = { "sell", "keep", "junk", "tooltip" },
        } },
        provides = { Hooked = api.hooked },
        start = function(ctx)
            grants, grantsAt = nil, nil
            if type(ctx.client.onItemTooltip) ~= "function" then return end
            local got = ctx.client.onItemTooltip(function(link, add)
                if ctx.settings:get(DT.SETTING) ~= true or type(add) ~= "function" then return end
                if ns.Items.Key(link) == nil then return end
                local g = held(ctx)
                if g == nil then return end
                local read = ctx.client.itemInfo
                local lines = DT.Lines(link, type(read) == "function" and read or nil, {
                    grants = g,
                    choices = { never = ns.LootNote.Never(ctx.store) },
                    sets = ns.GearSets and ns.GearSets.Facts(ctx.store) or nil,
                })
                for _, l in ipairs(lines or {}) do
                    local col = DT.COLOUR[l.tone] or DT.COLOUR.none
                    add(l.text, col[1], col[2], col[3])
                end
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
ns.dispositionTip = DT.Declare(ns)
