-- The client reads of the bags and vendor helper (F5): itemInfo,
-- durability, ownLoot and lootWindow, on the real boundary with a stand-in
-- for the globals of the client, and on the fake. No game client is
-- involved, and every call named here is a first guess not seen in game.
local _, ns = ...

local LINK = "|cffffffff|Hitem:2318::::::::20:::::|h[Light Leather]|h|r"
local GUID = "Creature-0-4444-0-55-299-00001A2B3C"

-- GetItemInfo as the client answers it: 13 values, the ones read here at
-- 1, 3, 11, 12 and 13.
local function itemAnswer(name, quality, price, class, subclass)
    return name, "link", quality, 10, 5, "Type", "Sub", 20, "", 134000, price, class, subclass
end

local function lootEnv(slots, guid)
    local env = {}
    function env.GetNumLootItems() return #slots end
    function env.GetLootSlotLink(i) return slots[i].link end
    function env.GetLootSlotInfo(i) return "icon", slots[i].name, slots[i].count, nil, 1 end
    function env.GetLootSourceInfo() return guid, 1 end
    return env
end

return {
    ["client item info: name, quality, sell price and class from GetItemInfo"] = function(t)
        local asked = {}
        local env = {}
        function env.GetItemInfo(item)
            asked[#asked + 1] = item
            return itemAnswer("Light Leather", 1, 15, 7, 6)
        end
        t.eq(ns.make.client(env).itemInfo(2318),
            { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7, subclassID = 6 })
        t.eq(asked, { 2318 })
    end,

    ["client item info: C_Item.GetItemInfo is asked when the client has it"] = function(t)
        local env = { GetItemInfo = function() error("the old call is not used") end }
        env.C_Item = { GetItemInfo = function() return itemAnswer("Broken Fang", 0, 4, 15, 0) end }
        t.eq(ns.make.client(env).itemInfo(LINK),
            { name = "Broken Fang", quality = 0, sellPrice = 4, classID = 15, subclassID = 0 })
    end,

    ["client item info: an item not loaded yet has its class only, never a made-up price"] = function(t)
        local env = {}
        function env.GetItemInfo() return nil end
        function env.GetItemInfoInstant() return 2318, "Type", "Sub", "", 134000, 7, 6 end
        local info = ns.make.client(env).itemInfo(2318)
        t.eq(info, { classID = 7, subclassID = 6 })
        t.eq(info and info.sellPrice, nil, "not known is not 0")
    end,

    ["client item info: nothing said, a failing call or no item is nil"] = function(t)
        t.eq(ns.make.client({}).itemInfo(2318), nil)
        t.eq(ns.make.client({ GetItemInfo = function() error("boom") end }).itemInfo(2318), nil)
        t.eq(ns.make.client({ GetItemInfo = function() return itemAnswer("A", 1, 1, 1, 1) end }).itemInfo(nil), nil)
    end,

    ["client item info: a value that is not a whole number is left out"] = function(t)
        local env = { GetItemInfo = function() return itemAnswer("Odd", "rare", -3, 2.5, nil) end }
        t.eq(ns.make.client(env).itemInfo(1), { name = "Odd" })
    end,

    ["client item info: hidden values are not read"] = function(t)
        local env = { GetItemInfo = function() return itemAnswer("Secret", 1, 15, 7, 6) end }
        env.issecretvalue = function() return true end
        t.eq(ns.make.client(env).itemInfo(1), nil)
    end,

    ["client durability: a row for each worn slot that wears"] = function(t)
        local env = {}
        function env.GetInventoryItemDurability(slot)
            if slot == 5 then return 40, 100 end
            if slot == 16 then return 0, 75 end
            return nil
        end
        t.eq(ns.make.client(env).durability(), { [5] = { cur = 40, max = 100 }, [16] = { cur = 0, max = 75 } })
    end,

    ["client durability: nothing wears is an empty reading, not nil"] = function(t)
        t.eq(ns.make.client({ GetInventoryItemDurability = function() return nil end }).durability(), {})
    end,

    ["client durability: no call, a failing call or a hidden value is nil"] = function(t)
        t.eq(ns.make.client({}).durability(), nil)
        t.eq(ns.make.client({ GetInventoryItemDurability = function() error("boom") end }).durability(), nil)
        local env = { GetInventoryItemDurability = function() return 40, 100 end }
        env.issecretvalue = function() return true end
        t.eq(ns.make.client(env).durability(), nil)
    end,

    ["client durability: a maximum of 0 or a broken pair is no row"] = function(t)
        local env = {}
        function env.GetInventoryItemDurability(slot)
            if slot == 1 then return 0, 0 end
            if slot == 3 then return 10 end
            if slot == 5 then return "x", 100 end
            return nil
        end
        t.eq(ns.make.client(env).durability(), {})
    end,

    ["client own loot: the line of the player gives the link and the count"] = function(t)
        local env = { LOOT_ITEM_SELF = "You receive loot: %s.", LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d." }
        local c = ns.make.client(env)
        t.eq({ c.ownLoot("You receive loot: " .. LINK .. ".") }, { LINK, 1 })
        t.eq({ c.ownLoot("You receive loot: " .. LINK .. "x4.") }, { LINK, 4 })
    end,

    ["client own loot: the numbered forms of another language are read too"] = function(t)
        local env = { LOOT_ITEM_SELF = "Ihr erhaltet Beute: %1$s.", LOOT_ITEM_SELF_MULTIPLE = "Beute: %2$d mal %1$s (neu)." }
        local c = ns.make.client(env)
        t.eq({ c.ownLoot("Ihr erhaltet Beute: " .. LINK .. ".") }, { LINK, 1 })
        t.eq({ c.ownLoot("Beute: 3 mal " .. LINK .. " (neu).") }, { LINK, 3 })
    end,

    ["client own loot: the line of anyone else, or a line with no item, is nil"] = function(t)
        local env = { LOOT_ITEM_SELF = "You receive loot: %s.", LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d." }
        local c = ns.make.client(env)
        t.eq((c.ownLoot("Thrall receives loot: " .. LINK .. ".")), nil)
        t.eq((c.ownLoot("You receive loot: some words.")), nil)
        t.eq((c.ownLoot("You receive item: " .. LINK .. ".")), nil, "made or bought is not loot")
        t.eq((c.ownLoot("")), nil)
        t.eq((c.ownLoot(nil)), nil)
        t.eq((c.ownLoot(12)), nil)
    end,

    ["client own loot: a client without the texts cannot tell, so nil"] = function(t)
        t.eq((ns.make.client({}).ownLoot("You receive loot: " .. LINK .. ".")), nil)
    end,

    ["client own loot: only the single form is enough"] = function(t)
        local c = ns.make.client({ LOOT_ITEM_SELF = "You receive loot: %s." })
        t.eq({ c.ownLoot("You receive loot: " .. LINK .. ".") }, { LINK, 1 })
    end,

    ["client loot window: items with counts, coins left out, the creature from its GUID"] = function(t)
        local env = lootEnv({
            { name = "12 Copper", count = 0 },
            { link = LINK, name = "Light Leather", count = 2 },
        }, GUID)
        local r = ns.make.client(env).lootWindow()
        t.ok(type(r) == "table", "a reading")
        if type(r) ~= "table" then return end
        t.eq(r.items, { { item = LINK, count = 2 } })
        t.eq(r.source, { kind = "creature", guid = GUID, id = 299 })
        t.eq(r.source and r.source.how, nil, "corpse, skinning or pickpocket is not known here")
    end,

    ["client loot window: the name only when the target is what is looted"] = function(t)
        local env = lootEnv({ { link = LINK, name = "Light Leather", count = 1 } }, GUID)
        env.UnitGUID = function() return GUID end
        env.UnitName = function() return "Young Wolf" end
        local r = ns.make.client(env).lootWindow()
        t.eq(r and r.source and r.source.name, "Young Wolf")
        env.UnitGUID = function() return "Creature-0-4444-0-55-300-00001A2B3D" end
        r = ns.make.client(env).lootWindow()
        t.eq(r and r.source and r.source.name, nil)
    end,

    -- Build 1.60.1 hides the server and spawn parts of a GUID (the public
    -- API page for UnitGUID says so): what they look like is not known.
    ["client loot window: the id is read whatever the server and spawn parts hold"] = function(t)
        local hiddenParts = "Creature-0-xQ9z-0-55-299-ZZ01xy"
        local r = ns.make.client(lootEnv({ { link = LINK, name = "x", count = 1 } }, hiddenParts)).lootWindow()
        t.eq(r and r.source, { kind = "creature", guid = hiddenParts, id = 299 })
    end,

    ["client loot window: a source that is not a creature has no kind"] = function(t)
        local chest = "GameObject-0-4444-0-55-2843-00001A2B3C"
        local r = ns.make.client(lootEnv({ { link = LINK, name = "x", count = 1 } }, chest)).lootWindow()
        t.eq(r and r.source, { guid = chest })
    end,

    ["client loot window: no source call is no source; a count not read is nil"] = function(t)
        local env = lootEnv({ { link = LINK, name = "x", count = 1 } }, GUID)
        env.GetLootSourceInfo = nil
        env.GetLootSlotInfo = nil
        local r = ns.make.client(env).lootWindow()
        t.eq(r and r.source, nil)
        t.eq(r and r.items, { { item = LINK } })
    end,

    ["client loot window: an empty window is no items, and no count call is nil"] = function(t)
        t.eq(ns.make.client(lootEnv({}, GUID)).lootWindow(), { items = {} })
        t.eq(ns.make.client({}).lootWindow(), nil)
        t.eq(ns.make.client({ GetNumLootItems = function() error("boom") end }).lootWindow(), nil)
    end,

    ["fake bag reads: nothing set is unknown"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.itemInfo(2318), nil)
        t.eq(c.durability(), nil)
        t.eq((c.ownLoot("You receive loot: " .. LINK .. ".")), nil)
        t.eq(c.lootWindow(), nil)
    end,

    ["fake bag reads: itemInfo answers a copy, by ID or by link"] = function(t)
        local c = ns.make.fakeClient()
        c.setItemInfo({ [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 } })
        local info = c.itemInfo(2318)
        t.eq(info, { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 })
        if type(info) ~= "table" then return end
        info.sellPrice = 9999
        local again = c.itemInfo(LINK)
        t.eq(again and again.sellPrice, 15, "a caller cannot change the facts")
        t.eq(c.itemInfo(97), nil)
        c.setItemInfo(nil)
        t.eq(c.itemInfo(2318), nil)
    end,

    ["fake bag reads: durability and the loot window answer copies"] = function(t)
        local c = ns.make.fakeClient()
        c.setDurability({ [5] = { cur = 40, max = 100 } })
        local d = c.durability()
        t.eq(d, { [5] = { cur = 40, max = 100 } })
        if type(d) ~= "table" then return end
        d[5].cur = 0
        t.eq(c.durability()[5].cur, 40)
        c.setLootWindow({ source = { kind = "creature", guid = GUID, id = 299 }, items = { { item = LINK, count = 2 } } })
        local w = c.lootWindow()
        t.ok(type(w) == "table" and type(w.source) == "table", "a reading with its source")
        if type(w) ~= "table" or type(w.source) ~= "table" then return end
        t.eq(w.items, { { item = LINK, count = 2 } })
        t.eq({ w.source.kind, w.source.guid, w.source.id }, { "creature", GUID, 299 })
        w.items[1].count = 50
        w.source.id = 1
        t.eq(c.lootWindow().items[1].count, 2)
        t.eq(c.lootWindow().source.id, 299)
    end,

    ["fake bag reads: ownLoot is what the test says it is"] = function(t)
        local c = ns.make.fakeClient()
        c.setOwnLoot(function(line)
            if line == "mine" then return LINK, 2 end
            return nil
        end)
        t.eq({ c.ownLoot("mine") }, { LINK, 2 })
        t.eq((c.ownLoot("theirs")), nil)
        c.setOwnLoot(nil)
        t.eq((c.ownLoot("mine")), nil)
    end,
}
