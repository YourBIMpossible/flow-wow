local _, ns = ...

-- Parity row E-38, the data half (lead section 762): the auction house's
-- deals list, as Flow's Modules/Items/Trader.lua: its rows are what the
-- route needs first, then the deals (T.Rows :175-180), ten lines (T.ROWS
-- :49); a route row has its own line (T.Line :184-186, here in our words);
-- one trade spends a quarter of your gold at most (T.Budget :206, T.SHARE).
-- The deals are Items/Trader.lua's own (api.deals(), the larger gain
-- first); Z-Flow buys nothing, so Flow's buying (T.Pick, T.Button) is not
-- here. The tab on the auction house is the drawing lane's (a MUSE NEED).
-- Pure. Not tested in game.
--   DealList.Rows(needs, deals[, max]) -> rows, more   at most max (ROWS);
--     more: how many are not shown. needs: route rows { id, name,
--     kind = "route", qty, cost } (the caller's: Z-Flow has no route step
--     that buys at the auction house yet, a LEAD NEED).
--   DealList.Line(row, coin) -> text
--   DealList.Budget(gold[, share]) -> copper
local DL = {}
ns.DealList = DL

DL.ROWS = 10
DL.SHARE = 0.25
DL.ROUTE = "%d x %s, for your route"
DL.ABOUT = " (about %s)"

function DL.Rows(needs, deals, max)
    max = tonumber(max) or DL.ROWS
    local all = {}
    for _, list in ipairs({ needs, deals }) do
        if type(list) == "table" then
            for _, r in ipairs(list) do
                if type(r) == "table" then all[#all + 1] = r end
            end
        end
    end
    local rows = {}
    for i = 1, math.min(#all, max) do rows[i] = all[i] end
    return rows, math.max(0, #all - max)
end

function DL.Line(row, coin)
    if type(row) ~= "table" then return nil end
    if row.kind == "route" then
        local text = DL.ROUTE:format(tonumber(row.qty) or 0, tostring(row.name))
        if type(row.cost) == "number" and type(coin) == "function" then text = text .. DL.ABOUT:format(coin(row.cost)) end
        return text
    end
    return ns.Trader.Line(row, coin)
end

function DL.Budget(gold, share)
    if type(gold) ~= "number" or gold ~= gold then return 0 end
    return math.floor(gold * (tonumber(share) or DL.SHARE))
end
