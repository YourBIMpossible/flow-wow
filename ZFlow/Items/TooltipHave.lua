local _, ns = ...

-- The "how many you have" line of an item tooltip (S5), as text. Pure: the
-- counts come from a resources snapshot (Items/Resources.lua) handed in;
-- nothing here reads the game.
--
--   line = TooltipHave.Line(snapshot, key)
--
--   snapshot  what Resources.Take or Resources.Fake gives. Used: bags and
--             bank ({ [itemKey] = count }, or nil when not read) and
--             bankKnown (false: the bank has not been seen).
--   key       the item's key, as the snapshot's tables are keyed
--             (Items/Key.lua)
--   line      { text, tone = "none" }, or nil when no held count above zero
--             is known: an item you do not have gets no line.
--
-- The bank is only ever what was seen at the last bank visit, and the line
-- says so every time it gives a bank count. A part that was not read is
-- said to be not read (bags) or not seen yet (bank); it is never counted as
-- none. A count that is not a whole number of zero or more is not known.

local H = {}
ns.TooltipHave = H

H.BANK_AS_OF = "as of your last bank visit"

-- How many of `key` a counts table holds: a whole number, 0 when the table
-- was read and has none, or nil when it is not known.
local function held(counts, key)
    if type(counts) ~= "table" then return nil end
    local n = counts[key]
    if n == nil then return 0 end
    if type(n) ~= "number" or n ~= n or n < 0 or n == math.huge or n ~= math.floor(n) then return nil end
    return n
end

function H.Line(snapshot, key)
    if type(snapshot) ~= "table" or key == nil then return nil end
    local bags = held(snapshot.bags, key)
    local bank = nil
    if snapshot.bankKnown ~= false then bank = held(snapshot.bank, key) end

    local inBank = "in the bank (" .. H.BANK_AS_OF .. ")"
    local text
    if bags and bags > 0 and bank and bank > 0 then
        text = "You have " .. (bags + bank) .. ": " .. bags .. " in bags, " .. bank .. " " .. inBank
    elseif bags and bags > 0 and bank == 0 then
        text = "You have " .. bags .. " in bags, none " .. inBank
    elseif bags and bags > 0 then
        text = "You have " .. bags .. " in bags (bank not seen yet)"
    elseif bank and bank > 0 and bags == 0 then
        text = "You have " .. bank .. " " .. inBank .. ", none in bags"
    elseif bank and bank > 0 then
        text = "You have " .. bank .. " " .. inBank .. "; bags not read"
    else
        return nil
    end
    return { text = text, tone = "none" }
end
