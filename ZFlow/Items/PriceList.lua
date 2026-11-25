local _, ns = ...

-- Parity row E-24, the data half (lead section 752): the "Auction prices"
-- view's list and its search, as Flow's Modules/Items/Banker.lua: B.PriceRows
-- (:662-674, one row an item, by name), B.Filter (:692-700, "any part, any
-- case; no text: all") and the "prices" header lines (:718-737). Pure: no
-- client read, nothing saved. The window and its search box are the drawing
-- lane's (a MUSE NEED).
--
-- From Items/AuctionLog.lua's realm table, [itemID] = { h = { at, price,
-- at, price, ... } } (the cheapest buyout for one at each look, oldest
-- first): a row's price is the last look's.
--   PriceList.Rows(realm, nameOf) -> { { id, name, price, at } }, by name
--     (then id); nameOf(id) -> name or nil ("item <id>" then, as Flow)
--   PriceList.Filter(rows, text) -> the rows whose name holds text
--   PriceList.Header(shown, all, text) -> the line above the list
-- Not tested in game.
local PL = {}
ns.PriceList = PL

PL.NONE = "No auction prices yet: they are read when you search at the auction house."
PL.ALL = "The cheapest buyout seen, for %d item(s). Search below."
PL.SOME = "%d of %d item(s) with \"%s\" in the name (the cheapest buyout seen):"

local function number(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

function PL.Rows(realm, nameOf)
    local out = {}
    if type(realm) ~= "table" then return out end
    for id, e in pairs(realm) do
        local h = nil
        if type(e) == "table" then h = e.h end
        if type(id) == "number" and type(h) == "table" and #h >= 2 and number(h[#h]) and number(h[#h - 1]) then
            local name = nil
            if type(nameOf) == "function" then
                local ok, v = pcall(nameOf, id)
                if ok and type(v) == "string" and v ~= "" then name = v end
            end
            out[#out + 1] = { id = id, name = name or ("item " .. id), price = h[#h], at = h[#h - 1] }
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

local function trimmed(text)
    if type(text) ~= "string" then return "" end
    return (text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

function PL.Filter(rows, text)
    local want = trimmed(text)
    if type(rows) ~= "table" then return {} end
    if want == "" then return rows end
    local out = {}
    for _, r in ipairs(rows) do
        if type(r) == "table" and type(r.name) == "string" and r.name:lower():find(want, 1, true) then
            out[#out + 1] = r
        end
    end
    return out
end

function PL.Header(shown, all, text)
    if type(all) ~= "number" or all == 0 then return PL.NONE end
    if type(shown) == "number" and shown < all then return PL.SOME:format(shown, all, trimmed(text)) end
    return PL.ALL:format(all)
end
