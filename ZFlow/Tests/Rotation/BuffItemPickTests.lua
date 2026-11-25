local _, ns = ...
-- Rotation/BuffItemPick.lua (parity row D-12; lead section 704): the buff
-- item the self button holds, told by its own tooltip. Made-up items.
-- Offline only: not tested in game.
local tests = {}
local BI = ns.BuffItemPick

local STONE, WEIGHT, OIL, ELIXIR, POTION = 9201, 9202, 9203, 9204, 9205
local LINES = {
    [STONE] = { "Coarse Sharpening Stone", "Use: Increase sharp weapon damage by 4 for 30 min." },
    [WEIGHT] = { "Coarse Weightstone", "Use: Increase the damage of a blunt weapon by 4 for 30 min." },
    [OIL] = { "Minor Wizard Oil", "Use: When applied to a melee weapon it increases spell damage by up to 8 for 30 min." },
    [ELIXIR] = { "Elixir of Lion's Strength", "Use: Increases your Strength by 4 for 1 hour." },
    [POTION] = { "Minor Healing Potion", "Use: Restores 70 to 90 health." },
}

tests["buff items: each kind told by its own tooltip"] = function(t)
    t.eq({ BI.Kind(LINES[STONE]) }, { "weapon", "edged" })
    t.eq({ BI.Kind(LINES[WEIGHT]) }, { "weapon", "blunt" })
    t.eq({ BI.Kind(LINES[OIL]) }, { "weapon", "any" })
    t.eq(BI.Kind(LINES[ELIXIR]), "self")
    t.eq(BI.Kind(LINES[POTION]), nil, "a heal is no buff item")
    t.eq(BI.Kind({ "Shiny Bauble", "Use: When applied to your fishing pole, increases Fishing by 25 for 10 min." }),
        nil, "a lure is the fishing key's")
    t.eq(BI.Kind(nil), nil)
    -- Twin's review (lead section 715): a heal over time with a duration is
    -- still a heal, no buff item.
    t.eq(BI.Kind({ "Healing Draught", "Use: Restores 20 health per 5 sec for 30 min." }), nil,
        "a restore with a duration")
end

-- Twin's review: the self button's slot is a weapon hand or nothing.
tests["buff items: a target slot other than the two weapon hands is dropped"] = function(t)
    local FB = ns.FlowButton
    local function slotOf(e)
        for _, row in ipairs(FB.Rows(e)) do
            if row.attr == "1:target-slot" then return row.value end
        end
        return "no row"
    end
    t.eq(slotOf({ item = "item:1", targetSlot = 16 }), 16)
    t.eq(slotOf({ item = "item:1", targetSlot = 17 }), 17)
    t.eq(slotOf({ item = "item:1", targetSlot = 18 }), nil, "18 is dropped")
    t.eq(slotOf({ spell = "Power Word: Fortitude", targetSlot = 16 }), nil, "a spell has no slot")
end

tests["buff items: a stone or oil fits the weapon it is for"] = function(t)
    t.eq(BI.Fits("edged", 7), true, "a sword")
    t.eq(BI.Fits("edged", 4), false, "a mace")
    t.eq(BI.Fits("blunt", 4), true)
    t.eq(BI.Fits("any", 10), true, "a staff")
    t.eq(BI.Fits("any", 20), false, "never a fishing pole")
    t.eq(BI.Fits("edged", nil), false, "the weapon not read")
end

local function items()
    return {
        { id = ELIXIR, name = "Elixir of Lion's Strength", kind = "self", spell = "Lion's Strength" },
        { id = STONE, name = "Coarse Sharpening Stone", kind = "weapon", fit = "edged" },
    }
end

-- Fails before: there is no such pick.
tests["buff items: the weapon first, then a buff that is not on you, out of a fight only"] = function(t)
    local ctx = { inCombat = false, mainSub = 7, mainEnchanted = false, buffs = {} }
    t.eq(BI.Pick(items(), ctx), { item = "item:" .. STONE, targetSlot = 16, name = "Coarse Sharpening Stone" })
    ctx.mainEnchanted = true
    t.eq(BI.Pick(items(), ctx), { item = "item:" .. ELIXIR, name = "Elixir of Lion's Strength" })
    ctx.buffs = { ["Lion's Strength"] = 600 }
    t.eq(BI.Pick(items(), ctx), nil, "its buff is on")
    ctx.buffs, ctx.mainEnchanted = {}, nil
    t.eq(BI.Pick(items(), ctx).item, "item:" .. ELIXIR, "the enchant not read: no weapon item")
    ctx.buffs = nil
    t.eq(BI.Pick(items(), ctx), nil, "buffs not read: no self item")
    t.eq(BI.Pick(items(), { inCombat = true, mainSub = 7, mainEnchanted = false, buffs = {} }), nil, "in a fight")
    t.eq(BI.Pick(items(), { mainSub = 7, mainEnchanted = false, buffs = {} }), nil, "combat not read")
end

tests["buff items: read from the bags, the worn weapon and the buffs"] = function(t)
    local c = ns.make.fakeClient()
    c.setCombat(false)
    c.setBagItems({ { item = POTION, count = 1 }, { item = ELIXIR, count = 2 }, { item = STONE, count = 3 } })
    c.setItemInfo({ [STONE] = { name = "Coarse Sharpening Stone" }, [ELIXIR] = { name = "Elixir of Lion's Strength" },
        [POTION] = { name = "Minor Healing Potion" }, [2488] = { name = "Sword", classID = 2, subclassID = 7 } })
    for id, l in pairs(LINES) do c.setItemLines(id, l) end
    c.setItemSpellName(ELIXIR, "Lion's Strength")
    c.setPlayerBuffs({})
    c.setWeaponEnchant({ main = { has = false } })
    c.wornLinks = function() return { [16] = "item:2488" } end
    local list, ctx = BI.Read(c)
    t.eq(#list, 2, "the potion is no buff item")
    t.eq(list[1].spell, "Lion's Strength")
    t.eq(ctx.mainSub, 7)
    t.eq(ctx.mainEnchanted, false)
    t.eq(BI.Pick(list, ctx).item, "item:" .. STONE)
    c.setBagItems(nil)
    t.eq(BI.Read(c), nil, "bags not read")
end

return tests
