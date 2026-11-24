-- The buyback list (G3): what is on the open merchant's Buyback tab, said
-- in chat by a slash word, so an item sold by mistake is easy to find again.
--
-- LOOK ONLY. It reads the tab (client.returnableItems) and prints. Nothing is
-- bought back, sold or moved: the player clicks the item on the game's own
-- Buyback tab.
--
--   Buyback.Lines(items) -> lines   (pure) the words for a reading:
--     nil      the merchant window is not open, or the tab was not read
--     {}       nothing on the tab
--     rows     a header, one line for each item, then where to click
--   Buyback.Start(k, diag) -> { run }   adds the word to diag.commands
--   `<slash> buyback` says it.
-- Not tested in game.
local _, ns = ...

local Buyback = {}
ns.Buyback = Buyback

Buyback.WORD = "buyback"
Buyback.HELP = "at a merchant: list what you can buy back. It buys nothing."
Buyback.NOT_OPEN = "open a merchant's window first. What you sold there is on its Buyback tab."
Buyback.EMPTY = "nothing is on this merchant's Buyback tab."
Buyback.HEADER_ONE = "1 item is on this merchant's Buyback tab:"
Buyback.HEADER = "%d items are on this merchant's Buyback tab:"
Buyback.HOW = "To get one back, open the Buyback tab at the bottom of the merchant window and click it. Nothing is bought for you."
Buyback.NO_NAME = "An item"
Buyback.NO_PRICE = "its price was not read"
Buyback.PRICE = "%s to buy back"

local function isText(v) return type(v) == "string" and v ~= "" end

local function nameOf(row)
    if isText(row.name) then return row.name end
    if isText(row.item) then
        local name = row.item:match("%[(.-)%]")
        if isText(name) then return name end
    end
    return Buyback.NO_NAME
end

function Buyback.Lines(items)
    if type(items) ~= "table" then return { Buyback.NOT_OPEN } end
    local rows = {}
    for _, row in ipairs(items) do
        if type(row) == "table" then rows[#rows + 1] = row end
    end
    if #rows == 0 then return { Buyback.EMPTY } end
    local lines = { #rows == 1 and Buyback.HEADER_ONE or Buyback.HEADER:format(#rows) }
    for i, row in ipairs(rows) do
        local what = nameOf(row)
        if type(row.count) == "number" and row.count > 1 then what = what .. " x" .. row.count end
        local coin = ns.Prices.Coin(row.price)
        local price = coin and Buyback.PRICE:format(coin) or Buyback.NO_PRICE
        lines[#lines + 1] = string.format("%d. %s: %s", i, what, price)
    end
    lines[#lines + 1] = Buyback.HOW
    return lines
end

function Buyback.Start(k, diag)
    local function run()
        local c = k.client
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        local items
        if type(c.returnableItems) == "function" then
            local ok, got = pcall(c.returnableItems)
            if ok then items = got end
        end
        local lines = Buyback.Lines(items)
        for i = 1, #lines do
            c.print(i == 1 and (k.id.title .. ": " .. lines[i]) or lines[i])
        end
    end
    if diag and type(diag.commands) == "table" then
        diag.commands[Buyback.WORD] = run
        if type(diag.help) == "table" then diag.help[Buyback.WORD] = Buyback.HELP end
    end
    return { run = run }
end

-- The addon's own: the word is added when this file loads.
ns.buyback = Buyback.Start(ns, ns.diag)
