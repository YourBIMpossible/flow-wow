local _, ns = ...

-- Profession sources (lead section 382, P-COACH C3): where a material the
-- plan (Items/ProfPlan.lua) lacks can come from, in this order:
--   1. gather: a node seen on the map the player is on (GatherMate2's,
--      through Nav/AddonSources.lua), the nearest;
--   2. buy_vendor: a vendor price seen (learned.prices kind "vendor").
--      Queue item A5: when a vendor was seen selling it (Items/
--      VendorWares.lua, through input.vendorOf) the line names that vendor
--      and the step carries npc and target; else it is text only;
--   3. buy_auction: the auction house, text only.
-- The bank is the plan's own step (take_bank). Z-Flow never buys, posts or
-- gathers for the player: each is a line of text, with a place only where
-- one was seen.
--
--   ok   = ProfSources.Gives(nodeName, itemName)
--   step = ProfSources.For(input, item, count)   nil when count < 1
-- input = { here = { map, x, y }, nodes = { { kind, node, map, x, y } },
--           name(item), vendorPrice(item) -> copper or nil,
--           vendorOf(item) -> { npc, map, x, y } or nil }
--
-- Gives is a first guess, not seen in game: a node gives the item of its
-- own name (herbs), and "<X> Vein" or "<X> Deposit" gives "<X> Ore". A
-- node that gives something else is not matched, so the line falls back
-- to a vendor or the auction house rather than a wrong place.

ns.ProfSources = {}
local S = ns.ProfSources

-- Section 383: a material whose name is not read yet; never its number.
S.UNNAMED = "of the materials"
S.ORE_SUFFIXES = { " Vein", " Deposit" }

local function whole(n)
    return type(n) == "number" and n == n and n >= 1 and n < math.huge and n == math.floor(n)
end

local function call(f, ...)
    if type(f) ~= "function" then return nil end
    return f(...)
end

function S.Gives(node, item)
    if type(node) ~= "string" or type(item) ~= "string" then return false end
    if node == item then return true end
    for _, suffix in ipairs(S.ORE_SUFFIXES) do
        if #node > #suffix and node:sub(-#suffix) == suffix and node:sub(1, -#suffix - 1) .. " Ore" == item then
            return true
        end
    end
    return false
end

local function nearestNode(input, itemName)
    local here = input.here
    if type(here) ~= "table" or here.map == nil or type(input.nodes) ~= "table" then return nil end
    local best, bestD
    for _, n in ipairs(input.nodes) do
        if type(n) == "table" and n.map == here.map and type(n.x) == "number" and type(n.y) == "number"
            and S.Gives(n.node, itemName) then
            local d = (n.x - (here.x or 0)) ^ 2 + (n.y - (here.y or 0)) ^ 2
            if not best or d < bestD then best, bestD = n, d end
        end
    end
    return best
end

local function coin(copper)
    local text = call(ns.Prices and ns.Prices.Coin, copper)
    if type(text) == "string" then return text end
    return string.format("%dc", copper)
end

function S.For(input, item, count)
    if not whole(count) then return nil end
    if type(input) ~= "table" then input = {} end
    local name = call(input.name, item)
    if type(name) ~= "string" or name == "" then name = S.UNNAMED end
    local node = nearestNode(input, name)
    if node then
        return { kind = "gather", item = item, count = count,
            target = { map = node.map, x = node.x, y = node.y },
            text = string.format("Gather %d %s (%s)", count, name, node.node) }
    end
    local price = call(input.vendorPrice, item)
    if type(price) == "number" and price >= 0 then
        local who = call(input.vendorOf, item)
        if type(who) == "table" and type(who.npc) == "string" and who.npc ~= "" then
            local step = { kind = "buy_vendor", item = item, count = count, npc = who.npc,
                text = string.format("Buy %d %s from %s (%s each)", count, name, who.npc, coin(price)) }
            if type(who.map) == "number" and type(who.x) == "number" and type(who.y) == "number" then
                step.target = { map = who.map, x = who.x, y = who.y }
            end
            return step
        end
        return { kind = "buy_vendor", item = item, count = count,
            text = string.format("Buy %d %s from a vendor (%s each)", count, name, coin(price)) }
    end
    return { kind = "buy_auction", item = item, count = count,
        text = string.format("Buy %d %s at the auction house", count, name) }
end
