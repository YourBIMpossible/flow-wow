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
--
-- E-44: with Skinning, anything left in the window means the corpse cannot be
-- skinned yet: the game lets you skin a corpse only once nothing is left on
-- it (Flow Modules/Items/LootFilter.lua:18-22, L.SkinWarning :63-68). Said
-- once per session, worded for a corpse "if" it was one (see above).
--   text = LootLeft.SkinWarning(items, professions)   pure: nil unless both
-- professions: client.professions() ({ [name] = true }, nil when not read).
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

LootLeft.SKIN_WARNING = "if that was a corpse you mean to skin, take everything first: "
    .. "the game lets you skin a corpse only once nothing is left on it, so it can't be skinned yet."

function LootLeft.SkinWarning(items, professions)
    if type(items) ~= "table" or #items == 0 then return nil end
    if type(professions) ~= "table" or professions.Skinning ~= true then return nil end
    return LootLeft.SKIN_WARNING
end

function LootLeft.Declare(k)
    local told, skinTold = false, false
    k:Module({
        name = LootLeft.NAME,
        needs = { "client" },
        start = function(ctx)
            local on = ctx.client.onLootLeft
            if type(on) ~= "function" then return end
            on(function(items)
                if not skinTold and type(ctx.client.professions) == "function" then
                    local okP, profs = pcall(ctx.client.professions)
                    local warn
                    if okP then warn = LootLeft.SkinWarning(items, profs) end
                    if warn then
                        skinTold = true
                        ctx.client.print(k.id.title .. ": " .. warn)
                    end
                end
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
