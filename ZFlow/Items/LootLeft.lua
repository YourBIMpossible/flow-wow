local _, ns = ...

-- LootLeft (E-45): after looting, one chat line saying how many junk (grey,
-- quality 0) items were left in the loot window. Told once per session, as
-- Flow does (Modules/Items/LootFilter.lua:73 L.told, :173-176 the line).
--
-- LOOK ONLY. It never loots, closes or skips anything.
--
--   n    = LootLeft.Junk(items)     pure: slots of quality 0
--   text = LootLeft.Line(n)         pure: nil when n is not above 0
--
-- items: what client.onLootLeft(fn) hands fn when the loot window closes
--   (CLIENT NEED): { { item = link, count = n, quality = q }, ... }.
--   A slot whose quality was not read is not counted.
-- "loot window", not "corpse": the client cannot tell a corpse from a
-- skinning or chest window (Core/Client.lua, lootWindow).
-- Not tested in game.

local LootLeft = {}
ns.LootLeft = LootLeft

LootLeft.NAME = "lootleft"

function LootLeft.Junk(items)
    if type(items) ~= "table" then return 0 end
    local n = 0
    for _, slot in ipairs(items) do
        if type(slot) == "table" and slot.quality == 0 then n = n + 1 end
    end
    return n
end

function LootLeft.Line(n)
    if type(n) ~= "number" or n ~= n or n < 1 then return nil end
    return string.format("left %d grey item%s in the loot window.", n, n == 1 and "" or "s")
end

function LootLeft.Declare(k)
    local told = false
    k:Module({
        name = LootLeft.NAME,
        needs = { "client" },
        start = function(ctx)
            local on = ctx.client.onLootLeft
            if type(on) ~= "function" then return end
            on(function(items)
                if told then return end
                local line = LootLeft.Line(LootLeft.Junk(items))
                if not line then return end
                told = true
                ctx.client.print(k.id.title .. ": " .. line)
            end)
        end,
    })
end

LootLeft.Declare(ns)
