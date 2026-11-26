local _, ns = ...

-- Deals panel (E-38): what the Deals tab on the auction house window
-- lists — this session's deals from Items/Trader.lua (api.deals(), the
-- larger gain first), one row a deal: the item's name and how many, what
-- it costs and the gain, with the data's own advice (Trader.TipLines)
-- as smaller lines under it. Before any deal, one line says what will
-- be listed; its "half" is Trader.DEAL's, read from the constant.
--
-- LOOK ONLY: the panel lists. Clicking a row does nothing; the player
-- acts on a deal in Blizzard's own search, as with the tooltip line.
-- Nothing here buys, bids or posts.
--
--   DealsPanel.Parts(deals, coin) -> kit parts (pure)
--   DealsPanel.EmptyText() -> the no-deals line
--   DealsPanel.Declare(k) -> api   (api.parts(), api.on())
--   ns.use(DealsPanel.NAME) -> { Parts, On }
--     Parts: the panel's parts now, or nil while the trader's switch
--     (trader.off) says nothing — the tab is not shown then.
--     On: whether the tab is shown at all; it follows the trader.
--
-- CLIENT NEED (the lead's): a tab on Blizzard's auction house frame
-- with a panel this module fills — shown while On() holds, its parts
-- taken from Parts() when the tab opens and whenever the deals change.
-- (The client already draws on that frame for the deal tooltip line.)
-- Until the tab lands, these parts are the panel, ready to be handed
-- over; nothing else draws them.
--
-- Reads: the trader module through ctx.use, the trader.off setting.
-- Not tested in game.
local DP = {}
ns.DealsPanel = DP

DP.NAME = "dealsPanel"
DP.ID = "dealsPanel"
DP.HEADER = "Deals"

-- Items/Trader.lua loads after this file, so the trader's table is read
-- when a function runs, never at load.
local function trader() return ns.Trader end

local function whole(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and v == math.floor(v)
end

-- The no-deals line. The share is Trader.DEAL's own: at 0.5 it reads
-- "half", as the design agreed; any other value reads as a percent, so
-- the line follows the constant, not a copy of the number.
function DP.EmptyText()
    local share
    if trader().DEAL == 0.5 then
        share = "half its usual price"
    else
        share = string.format("%d%% of its usual price", math.floor(trader().DEAL * 100 + 0.5))
    end
    return "No deals yet. Search the auction house, and anything priced at "
        .. share .. " or less will be listed here."
end

-- One session's deals as kit parts, in the order given (the trader's
-- api deals are already the larger gain first). coin: copper -> text,
-- the same function the trader's advice takes.
function DP.Parts(deals, coin)
    if type(coin) ~= "function" then coin = ns.Prices.Coin end
    if type(deals) ~= "table" or #deals == 0 then
        return { { kind = "line", key = "empty", text = DP.EmptyText() } }
    end
    local kids = {}
    for i, row in ipairs(deals) do
        local name = row.name
        if type(name) ~= "string" or name == "" then name = "item " .. tostring(row.id) end
        local text = name
        if whole(row.qty) and row.qty > 1 then text = name .. " x" .. row.qty end
        local line = { kind = "line", key = "deal" .. i, text = text }
        local sub = {}
        if type(row.cost) == "number" then sub[#sub + 1] = "Costs " .. coin(row.cost) end
        if type(row.gain) == "number" then sub[#sub + 1] = "gain " .. coin(row.gain) end
        if #sub > 0 then line.sub = table.concat(sub, " · ") end
        -- A vendor deal's gain is certain (Trader.COLOUR paints it
        -- green); a resell deal's is a guess, and keeps no tone.
        if row.kind == "vendor" then line.tone = "good" end
        kids[#kids + 1] = line
        local tips = trader().TipLines(row, coin)
        if type(tips) == "table" then
            for j, tip in ipairs(tips) do
                kids[#kids + 1] = { kind = "line", key = "deal" .. i .. "tip" .. j, text = tip }
            end
        end
    end
    return kids
end

function DP.Declare(k)
    local api = {}
    local ctx

    -- The trader's own switch, read as the trader reads it: the tab is
    -- shown unless "trader.off" is set.
    function api.on()
        if not ctx then return false end
        return ctx.settings:get(trader().SETTING) ~= true
    end

    function api.parts()
        if not api.on() then return nil end
        local deals = nil
        local ok, mod = pcall(ctx.use, trader().NAME)
        if ok and type(mod) == "table" and type(mod.Deals) == "function" then
            local fine, list = pcall(mod.Deals)
            if fine then deals = list end
        end
        return DP.Parts(deals, ns.Prices.Coin)
    end

    k:Module({
        name = DP.NAME,
        needs = { "settings" },
        provides = { Parts = function() return api.parts() end, On = function() return api.on() end },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.dealsPanel = DP.Declare(ns)
