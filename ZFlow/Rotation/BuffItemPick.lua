local _, ns = ...

-- BuffItemPick (parity row D-12; lead section 704): the buff item the self
-- button holds when no self buff spell is due: a sharpening stone,
-- weightstone or oil on your main hand, or an elixir, scroll or flask whose
-- buff is not on you. As Flow's Modules/Rotation/BuffButton.lua (:93-108,
-- the item step) and BuffItems.lua (:270-300 what a stone or oil goes on,
-- :440-470 the item step). Out of a fight, from the bags only; nothing is
-- bought. The click is the player's own.
--
-- An item is told by its own tooltip (lead sections 611 and 619): Flow
-- named stones and oils by typed names; here a "Use:" line says it.
--   weapon  the Use line names a weapon: "sharp" goes on an edged weapon,
--           "blunt" on a blunt one, any other (an oil) on any weapon but a
--           fishing pole
--   self    the Use line gives something "for N sec/min/hour", and is no
--           heal or restore (a potion is not a buff item); its buff is the
--           item's own use spell (client.itemSpellName)
-- The weapon kinds are the game's item subclass numbers for weapons
-- (warcraft.wiki.gg, ItemType: Weapon subclasses): edged 0 one-handed axe,
-- 1 two-handed axe, 6 polearm, 7 one-handed sword, 8 two-handed sword, 13
-- fist weapon, 15 dagger; blunt 4 one-handed mace, 5 two-handed mace, 10
-- staff; 20 fishing pole. As Flow's EDGED and BLUNT (BuffItems.lua:289-292).
--
-- Pure:
--   BI.Kind(lines) -> "weapon", "self" or nil; and for a weapon its fit:
--     "edged", "blunt" or "any"
--   BI.Fits(fit, sub) -> true when an item of that fit goes on a weapon of
--     that subclass
--   BI.Pick(items, ctx) -> { item = "item:ID", targetSlot = 16 | nil, name }
--     or nil. items = { { id, name, kind, fit, spell } } in bag order;
--     ctx = { inCombat, mainSub, mainEnchanted, buffs }. A weapon item first
--     (Flow: do it while you can), only when the game says plainly that the
--     main hand has no enchant; then a self item whose buff is read as not
--     on you. Anything not read: nothing.
-- BI.Read(client) -> items, ctx   reads only; nil when the bags are not read
-- CLIENT NEED (stubbed in Core/ClientFake.lua, "§ D-12"):
--   client.itemSpellName(item) -> the name of the item's use spell, or nil
--     (C_Item.GetItemSpell(item)'s first value, else GetItemSpell)
-- Not tested in game.

local BI = {}
ns.BuffItemPick = BI

BI.EDGED = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [13] = true, [15] = true }
BI.BLUNT = { [4] = true, [5] = true, [10] = true }
BI.POLE = 20
BI.MAIN = 16

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if ok then return v end
    return nil
end

function BI.Kind(lines)
    if type(lines) ~= "table" then return nil end
    for _, l in ipairs(lines) do
        if type(l) == "string" then
            local low = l:lower()
            if low:find("^use:") then
                if low:find("fishing pole", 1, true) then return nil end
                if low:find("weapon", 1, true) then
                    if low:find("sharp", 1, true) then return "weapon", "edged" end
                    if low:find("blunt", 1, true) then return "weapon", "blunt" end
                    return "weapon", "any"
                end
                local heals = low:find("restores", 1, true) or low:find("heals", 1, true)
                local lasts = low:find("for %d+ sec") or low:find("for %d+ min") or low:find("for %d+ hour")
                    or low:find("for %d+ hr")
                if lasts and not heals then return "self" end
                return nil
            end
        end
    end
    return nil
end

function BI.Fits(fit, sub)
    if type(sub) ~= "number" or sub == BI.POLE then return false end
    if fit == "edged" then return BI.EDGED[sub] == true end
    if fit == "blunt" then return BI.BLUNT[sub] == true end
    if fit == "any" then return BI.EDGED[sub] == true or BI.BLUNT[sub] == true end
    return false
end

function BI.Pick(items, ctx)
    if type(items) ~= "table" or type(ctx) ~= "table" or ctx.inCombat ~= false then return nil end
    if ctx.mainEnchanted == false then
        for _, it in ipairs(items) do
            if type(it) == "table" and it.kind == "weapon" and BI.Fits(it.fit, ctx.mainSub) then
                return { item = "item:" .. it.id, targetSlot = BI.MAIN, name = it.name }
            end
        end
    end
    if type(ctx.buffs) == "table" then
        for _, it in ipairs(items) do
            if type(it) == "table" and it.kind == "self" and type(it.spell) == "string" and it.spell ~= ""
                and ctx.buffs[it.spell] == nil then
                return { item = "item:" .. it.id, name = it.name }
            end
        end
    end
    return nil
end

function BI.Read(client)
    local stacks = ask(client, "bagItems")
    if type(stacks) ~= "table" then return nil end
    local items, seen = {}, {}
    for _, st in ipairs(stacks) do
        local id = type(st) == "table" and ns.Items.Id(st.item) or nil
        if id and not seen[id] and (st.count == nil or (type(st.count) == "number" and st.count > 0)) then
            seen[id] = true
            local kind, fit = BI.Kind(ask(client, "itemLines", id))
            if kind then
                local info = ask(client, "itemInfo", id)
                local name
                if type(info) == "table" and type(info.name) == "string" then name = info.name end
                local spell
                if kind == "self" then spell = ask(client, "itemSpellName", id) end
                items[#items + 1] = { id = id, name = name, kind = kind, fit = fit, spell = spell }
            end
        end
    end
    local ctx = { buffs = ask(client, "playerBuffs") }
    local combat = ask(client, "inCombat")
    if type(combat) == "boolean" then ctx.inCombat = combat end
    local we = ask(client, "weaponEnchant")
    local main
    if type(we) == "table" then main = we.main end
    if type(main) == "table" and type(main.has) == "boolean" then ctx.mainEnchanted = main.has end
    local worn = ask(client, "wornLinks")
    local link
    if type(worn) == "table" then link = worn[BI.MAIN] end
    if link ~= nil then
        local info = ask(client, "itemInfo", link)
        if type(info) == "table" and type(info.subclassID) == "number" then ctx.mainSub = info.subclassID end
    end
    return items, ctx
end

