local _, ns = ...

-- Tests for ZFlow/Gear/MerchantMarks.lua (S20): which of a merchant's items
-- are upgrades, by the same verdict the item tooltip gives. Look only.
--
-- The fake client's gear answer is given what the game marks on each item
-- (gear.unmet) by hand, as in Tests/Gear/TooltipModule.lua.

local M = ns.GearMerchantMarks
local tests = {}

local STA = "ITEM_MOD_STAMINA_SHORT"
local HELM, BETTER, WORSE, PLATE, POTION, UNREAD = "item:1", "item:2", "item:3", "item:4", "item:5", "item:6"

local function packs()
    return { DRUID = {
        weights = {
            dps = { evidence = "first guess", values = { [STA] = 1 } },
            tank = { evidence = "first guess", values = { [STA] = 3 } },
        },
        proficiency = { evidence = "first guess", [4] = { [2] = true } },
    } }
end

-- Wearing HELM (4 stamina). On sale: see each test.
local function client(rows)
    local c = ns.make.fakeClient()
    c.setClass("DRUID")
    c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [STA] = 4 } })
    c.setItem(BETTER, { kind = "INVTYPE_HEAD", stats = { [STA] = 9 } })
    c.setItem(WORSE, { kind = "INVTYPE_HEAD", stats = { [STA] = 1 } })
    c.setItem(PLATE, { kind = "INVTYPE_HEAD", stats = { [STA] = 40 } })
    c.setItem(POTION, { stats = {} })
    c.setItem(UNREAD, { kind = "INVTYPE_HEAD", stats = { [STA] = 9 } })
    c.setWorn(1, HELM)
    c.unmet = { [HELM] = {}, [BETTER] = {}, [WORSE] = {}, [PLATE] = { "Plate" }, [POTION] = {} }
    local gear = c.gear
    c.gear = function(link)
        local g = gear(link)
        if c.unmet[link] ~= nil then g.unmet = c.unmet[link] end
        return g
    end
    c.setMerchant(rows or {})
    c.setMerchantOpen(true)
    return c
end

local function row(link, price) return { item = link, price = price or 100, stack = 1 } end

tests["merchant marks: an item that is an upgrade is marked, with a line for each role"] = function(t)
    local c = client({ row(BETTER) })
    local marks, info = M.Marks(c, packs())
    t.eq(#marks, 1)
    t.eq(marks[1].index, 1)
    t.eq(marks[1].link, BETTER)
    t.eq(marks[1].lines, { "Upgrade for your head piece (+5, dps)", "Upgrade for your head piece (+15, tank)" })
    t.eq(info.rows, 1)
    t.eq(info.gear, 1)
end

tests["merchant marks: only upgrades are marked, in the window's order"] = function(t)
    local c = client({ row(WORSE), row(POTION), row(BETTER), row(HELM), row(PLATE), row(BETTER) })
    local marks, info = M.Marks(c, packs())
    t.eq(#marks, 2)
    t.eq({ marks[1].index, marks[2].index }, { 3, 6 })
    t.eq(info.rows, 6)
    t.eq(info.gear, 5, "the potion is not gear")
    t.eq(info.cannotUse, 1, "the plate helm")
    t.eq(info.noVerdict, 0)
end

tests["merchant marks: gear the game marks as not usable is never marked"] = function(t)
    local c = client({ row(PLATE) })
    local marks, info = M.Marks(c, packs())
    t.eq(marks, {})
    t.eq(info.cannotUse, 1)
end

tests["merchant marks: an item with no verdict is counted, never marked"] = function(t)
    local c = client({ row(UNREAD), row(BETTER) })
    local marks, info = M.Marks(c, packs())
    t.eq(#marks, 1, "the marks on item:6 were not read: no verdict, although it would score higher")
    t.eq(marks[1].index, 2)
    t.eq(info.noVerdict, 1)
end

tests["merchant marks: an upgrade for one role only is marked with that role's line"] = function(t)
    local c = client({ row(BETTER) })
    local p = packs()
    p.DRUID.weights.tank.values = { ITEM_MOD_STRENGTH_SHORT = 1 }
    local marks = M.Marks(c, p)
    t.eq(#marks, 1)
    t.eq(marks[1].lines, { "Upgrade for your head piece (+5, dps)" })
end

tests["merchant marks: a row with no link is counted as not read"] = function(t)
    local c = client({ { price = 5, stack = 1 }, row(BETTER) })
    local marks, info = M.Marks(c, packs())
    t.eq(#marks, 1)
    t.eq(marks[1].index, 2)
    t.eq(info.unread, 1)
end

tests["merchant marks: no merchant window, or one that cannot be read, is no answer"] = function(t)
    local c = client({ row(BETTER) })
    c.setMerchantOpen(false)
    local marks, info = M.Marks(c, packs())
    t.eq(marks, nil)
    t.eq(info.why, M.REASON.merchant)
    marks, info = M.Marks({}, packs())
    t.eq(marks, nil, "a client with no merchant read")
    t.eq(info.why, M.REASON.merchant)
    t.eq(M.Marks(nil, packs()), nil)
end

tests["merchant marks: an empty merchant is an empty answer, not no answer"] = function(t)
    local marks, info = M.Marks(client({}), packs())
    t.eq(marks, {})
    t.eq(info.rows, 0)
end

tests["merchant marks: the text names how many, then each one"] = function(t)
    local c = client({ row(WORSE), row(BETTER), row(BETTER) })
    local marks, info = M.Marks(c, packs())
    local text = M.Text(marks, info)
    t.eq(text[1], "2 upgrades on sale here")
    t.eq(text[2], BETTER .. ": Upgrade for your head piece (+5, dps); Upgrade for your head piece (+15, tank)")
    t.eq(#text, 3)
    marks, info = M.Marks(client({ row(BETTER) }), packs())
    t.eq(M.Text(marks, info)[1], "1 upgrade on sale here")
end

tests["merchant marks: no upgrades says so only when gear was looked at"] = function(t)
    local marks, info = M.Marks(client({ row(WORSE), row(POTION) }), packs())
    t.eq(M.Text(marks, info), { "No upgrades on sale here" })
    marks, info = M.Marks(client({ row(POTION) }), packs())
    t.eq(M.Text(marks, info), {}, "no gear on sale: nothing to say")
    marks, info = M.Marks(client({ row(UNREAD) }), packs())
    t.eq(M.Text(marks, info), { "No upgrades on sale here; 1 item with no verdict" })
    t.eq(M.Text(nil, { why = M.REASON.merchant }), {}, "no answer: nothing is said")
end

tests["merchant marks: per-role badges - up, down, same; can't use and no verdict give none"] = function(t)
    local c = client({ row(BETTER), row(WORSE), row(HELM), row(PLATE), row(POTION), row(UNREAD) })
    local badges = M.Specs(c, packs(), "")
    t.eq(badges[1], { { role = "dps", state = "up" }, { role = "tank", state = "up" } })
    t.eq(badges[2], { { role = "dps", state = "down" }, { role = "tank", state = "down" } })
    t.eq(badges[3], { { role = "dps", state = "same" }, { role = "tank", state = "same" } })
    t.eq(badges[4], nil, "can't use: no badge")
    t.eq(badges[5], nil, "not gear: no badge")
    t.eq(badges[6], nil, "no verdict: no badge")
end

tests["merchant marks: per-role badges - the chosen role first"] = function(t)
    local badges = M.Specs(client({ row(BETTER) }), packs(), "tank")
    t.eq(badges[1], { { role = "tank", state = "up" }, { role = "dps", state = "up" } })
    badges = M.Specs(client({ row(BETTER) }), packs(), "heal")
    t.eq(badges[1][1].role, "dps", "a role the pack has no weights for: name order")
end

tests["merchant marks: per-role badges - no merchant read, nil"] = function(t)
    local c = client({ row(BETTER) })
    c.setMerchantOpen(false)
    t.eq(M.Specs(c, packs(), "dps"), nil)
end

tests["merchant marks: the price, and 'more than you have' only when money was read"] = function(t)
    local marks, info = M.Marks(client({ row(BETTER, 2540) }), packs())
    t.eq(marks[1].price, 2540)
    local tail = "Upgrade for your head piece (+5, dps); Upgrade for your head piece (+15, tank)"
    t.eq(M.Text(marks, info, { money = 1000 })[2], BETTER .. ": " .. tail .. "; 25s 40c, more than you have")
    t.eq(M.Text(marks, info, { money = 2540 })[2], BETTER .. ": " .. tail .. "; 25s 40c")
    t.eq(M.Text(marks, info, {})[2], BETTER .. ": " .. tail .. "; 25s 40c", "money not read")
    t.eq(M.Text(marks, info)[2], BETTER .. ": " .. tail, "no opts: as before")
end

tests["merchant marks: it only reads; nothing is bought"] = function(t)
    local c = client({ row(BETTER) })
    local calls = 0
    for _, name in ipairs({ "BuyMerchantItem", "PickupMerchantItem", "BuybackItem", "EquipItemByName" }) do
        c[name] = function() calls = calls + 1 end
    end
    M.Marks(c, packs())
    t.eq(calls, 0)
end

return tests
