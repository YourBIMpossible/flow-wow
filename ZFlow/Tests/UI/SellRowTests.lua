local _, ns = ...
-- G1 (CAPABILITY-RECONCILE 2026-11-24): the sell list at the merchant had
-- one button, "Sell these", for every listed row. Each row to sell now has
-- its own "Sell" button under it, which sells every stack of that one item
-- and nothing else, through the same runner (Items/SellThese.lua): on the
-- player's own click only, merchant open, out of combat, one stack a
-- frame. A row a goal holds part of can't be sold whole, so its button is
-- off and says why. ACTING: a click sells. Made-up items. Not run: no Lua
-- on this machine.
--
-- Fails before: SellThese.PlanRow is nil and the window has no row buttons.
local tests = {}
local S = ns.SellThese
local L = ns.SellList

local FANG, SCRAP = 97, 2934
local SLOTS = {
    { bag = 0, slot = 1, item = FANG, count = 3 },
    { bag = 0, slot = 4, item = FANG, count = 2 },
    { bag = 1, slot = 1, item = SCRAP, count = 1 },
}
local function listing(rows)
    return { list = { ok = true, rows = rows or {
        { key = FANG, name = "Broken Fang", count = 5 },
        { key = SCRAP, name = "Ruined Leather Scraps", count = 1 },
    } } }
end

tests["sell row: the plan for one row is that item's stacks only, by bag and slot"] = function(t)
    t.eq(type(S.PlanRow), "function", "the row plan is there")
    if type(S.PlanRow) ~= "function" then return end
    t.eq(S.PlanRow(listing(), SLOTS, FANG), {
        { bag = 0, slot = 1, key = FANG, count = 3 },
        { bag = 0, slot = 4, key = FANG, count = 2 },
    })
    t.eq(S.PlanRow(listing(), SLOTS, SCRAP), { { bag = 1, slot = 1, key = SCRAP, count = 1 } })
end

tests["sell row: a row not listed, part held, or bags not read is not planned, with why"] = function(t)
    if type(S.PlanRow) ~= "function" then t.ok(false, "PlanRow") return end
    local steps, why = S.PlanRow(listing(), SLOTS, 12345)
    t.eq(steps, nil); t.eq(why, S.NOTHING, "not on the list")
    steps, why = S.PlanRow(listing({ { key = FANG, name = "Broken Fang", count = 3 } }), SLOTS, FANG)
    t.eq(steps, nil); t.eq(why, S.NOT_WHOLE, "a goal holds two of the five")
    steps, why = S.PlanRow(listing(), nil, FANG)
    t.eq(steps, nil); t.eq(why, S.NOT_READ)
    steps, why = S.PlanRow({ unavailable = true }, SLOTS, FANG)
    t.eq(steps, nil); t.eq(why, S.NOT_KNOWN)
end

tests["sell row: the whole-list plan is as it was"] = function(t)
    t.eq(S.Plan(listing(), SLOTS), {
        { bag = 0, slot = 1, key = FANG, count = 3 },
        { bag = 0, slot = 4, key = FANG, count = 2 },
        { bag = 1, slot = 1, key = SCRAP, count = 1 },
    })
end

tests["sell row: the window puts the action's button for each row under its line"] = function(t)
    local asked = {}
    local action = { rowButton = function(row)
        asked[#asked + 1] = row.key
        return { kind = "button", key = "sellRow." .. row.key, text = S.ROW_TEXT, onClick = function() end }
    end }
    local tree = L.TreeOf(listing(), nil, nil, action)
    local body = tree.children[2].children
    local at = {}
    for i, p in ipairs(body) do
        if p.kind == "itemLine" then at[p.name] = i end
        if p.kind == "row" and p.control then at[p.control.key] = i end
    end
    t.eq(asked, { FANG, SCRAP }, "asked once per row to sell, in order")
    t.eq(at["sellRow." .. FANG], at["Broken Fang"] + 1, "the fang's button right under its line")
    t.eq(at["sellRow." .. SCRAP], at["Ruined Leather Scraps"] + 1)
    t.ok(ns.Kit.Window(tree) ~= nil, "the kit takes it")
end

tests["sell row: no action, or one that gives no button, adds no row"] = function(t)
    for _, action in ipairs({ nil, {}, { rowButton = function() return nil end } }) do
        local body = L.TreeOf(listing(), nil, nil, action).children[2].children
        for _, p in ipairs(body) do t.ok(p.kind ~= "row", "no row part") end
    end
end

tests["sell row: the button's words"] = function(t)
    t.eq(S.ROW_TEXT, "Sell")
    t.eq(S.ROW_LABEL, "Only %s")
    t.eq(S.RowTip(nil), "Sells only this item, every stack of it in your bags. "
        .. "You can buy it back on the merchant's Buyback tab.")
    t.eq(S.RowTip(S.NOT_WHOLE), "A goal holds part of this item, and a stack can't be split here. Sell it by hand.")
    t.eq(S.RowTip(S.NOT_READ), S.Tip(S.NOT_READ), "other whys as the main button's")
end

return tests
