local _, ns = ...

-- Parity row E-38, the data half (lead section 755): the rows of the
-- auction house's deals list. The deals are the trader's own (Items/
-- Trader.lua: T.Deals, the same rows its "Deal:" chat and tooltip lines
-- come from, api.deals() this session). As Flow's Modules/Items/Trader.lua
-- T:Fill (:510-546): a note above the list, up to T.ROWS (10) rows, the
-- most gain first, then how many more there are. Flow heads its list
-- with what the route has you buy (T.RouteNeeds); this client has no buy
-- step yet, so that part waits for one.
--
-- Pure: no client read, nothing bought. Each row says what it is (vendor:
-- under a vendor's price, certain; resell: half the usual price or less, a
-- guess); its words are Trader.Line's. Flow's Buy button is a buy action
-- and stays out (look only, as E-12). The tab on the auction window and its
-- drawing are the drawing lane's (a MUSE NEED).
--
--   TR.Rows(deals[, max]) -> rows, more   rows sorted by gain, then id
--   TR.Note(n, followed) -> the line above the list
--   TR.Foot(more) -> "N more deal(s) not shown." or ""
-- Not tested in game.
local TR = {}
ns.TraderRows = TR

TR.ROWS = 10
TR.MORE = "%d more deal(s) not shown."
TR.NOT_FOLLOWED = "Your auction searches can't be followed on this client, so there are no deals to list."
TR.NONE = "No deals in your searches this session: nothing priced under what a vendor pays, or at half its usual price."
TR.SOME = "%d deal(s) from your searches this session. Buying is yours, in the auction window."

local function number(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

function TR.Rows(deals, max)
    max = tonumber(max) or TR.ROWS
    local all = {}
    local list = {}
    if type(deals) == "table" then list = deals end
    for _, d in ipairs(list) do
        if type(d) == "table" and type(d.id) == "number" and number(d.gain) then all[#all + 1] = d end
    end
    table.sort(all, function(x, y)
        if x.gain ~= y.gain then return x.gain > y.gain end
        return x.id < y.id
    end)
    local rows = {}
    for i = 1, math.min(#all, max) do rows[i] = all[i] end
    return rows, #all - #rows
end

function TR.Note(n, followed)
    if type(n) == "number" and n > 0 then return TR.SOME:format(n) end
    if followed ~= true then return TR.NOT_FOLLOWED end
    return TR.NONE
end

function TR.Foot(more)
    if type(more) == "number" and more > 0 then return TR.MORE:format(more) end
    return ""
end
