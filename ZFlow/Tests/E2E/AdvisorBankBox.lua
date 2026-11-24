local _, ns = ...
-- Lead DISPATCH sections 340/341, the owner's in-game feedback on the
-- advisor's bank box, end to end on the whole add-on loaded on a fake
-- client: the advisor panel has a title; the bank prompt names the items;
-- the bank prompt is there only while the bank window is open. Advice only:
-- nothing here moves an item.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
local tests = {}
-- Item names carry the game's quality colour (Items/Present.lua, Tint; the
-- colour itself is tested in Tests/Items/ItemColourTests.lua). These tests are
-- about the words, so they read them with the colour taken off.
local plain = ns.ItemPresent.Plain

local LINEN, WOOL, COPPER, LEATHER, POTION = 2589, 2592, 2770, 2318, 858
local INFO = {
    [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [WOOL] = { name = "Wool Cloth", quality = 1, sellPrice = 33, classID = 7 },
    [COPPER] = { name = "Copper Ore", quality = 1, sellPrice = 5, classID = 7 },
    [LEATHER] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
    [POTION] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
}

-- opts: bag (stacks), kitFails (kit windows the client refuses)
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo(INFO)
    c.setBagItems(opts.bag or { { item = LINEN, count = 12 }, { item = COPPER, count = 5 },
                                { item = POTION, count = 3 } })
    if opts.kitFails then c.setKitFails(opts.kitFails) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function promptOf(addon)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == addon.BankList.PROMPT_ID then return p.text end
    end
    return nil
end

local TITLE = ns.id.title .. ": Advice"

tests["advisor bank box: the advisor window has a title, the add-on's own"] = function(t)
    local c, addon = start()
    addon.advisor.Add("boxTest", "Repair your gear.", 1)
    local w = c.kitWindows().Advisor
    t.ok(type(w) == "table" and w.shown == true, "the kit window is shown")
    -- Lead section 408: in the title bar only, not again as a part.
    t.eq(w and w.title, TITLE)
    for _, part in ipairs(w and w.parts or {}) do
        t.ok(part.kind ~= "header" and part.text ~= TITLE, "the title is not shown twice")
    end
end

tests["advisor bank box: the plain panel shows the same title above its prompts"] = function(t)
    local c, addon = start({ kitFails = 1000 })
    addon.advisor.Add("boxTest", "Repair your gear.", 1)
    local p
    for _, panel in ipairs(c.panels) do
        if type(panel.spec) == "table" and panel.spec.name == ns.id.framePrefix .. "Advisor" then p = panel end
    end
    t.ok(p ~= nil and p.shown == true, "the plain panel is shown")
    t.eq(p and p.lines, { TITLE, "Repair your gear." })
end

tests["advisor bank box: the bank prompt names the items and their counts"] = function(t)
    local c, addon = start()
    c.setBankOpen(true)
    t.eq(promptOf(addon), "Put in your bank for later: Linen Cloth x12, Copper Ore x5")
    c.setBankOpen(false)
end

tests["advisor bank box: the bank prompt names three, then counts the rest"] = function(t)
    local c, addon = start({ bag = { { item = LINEN, count = 20 }, { item = WOOL, count = 10 },
        { item = COPPER, count = 5 }, { item = LEATHER, count = 4 } } })
    c.setBankOpen(true)
    t.eq(promptOf(addon), "Put in your bank for later: Linen Cloth x20, Wool Cloth x10, Copper Ore x5, and 1 more")
end

tests["advisor bank box: a name not read yet is said so, never an item number"] = function(t)
    local text = ns.ItemPresent.BankPrompt({ ok = true, rows = { { key = "818", count = 3 } }, unread = 0 })
    t.eq(text, "Put in your bank for later: item not read yet x3")
    t.ok(not tostring(text):find("818", 1, true), "no item number")
end

tests["advisor bank box: the bank prompt is there only while the bank is open"] = function(t)
    local c, addon = start()
    t.eq(promptOf(addon), nil, "away from the bank: no bank prompt")
    c.fire(addon.BankList.BAG_EVENT)
    t.eq(promptOf(addon), nil, "a bag change away from the bank raises none")
    c.setBankOpen(true)
    t.ok(promptOf(addon) ~= nil, "at the bank: the prompt")
    c.setBankOpen(false)
    t.eq(promptOf(addon), nil, "the bank closed: the prompt is gone")
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(promptOf(addon), nil, "and entering the world does not bring it back")
end

-- Owner, 2026-11-23: the box at the bank read as "one kind of item to put
-- in the bank" and the owner could not tell what it was. Fails before: the
-- line began with the one word "Bank:".
tests["advisor bank box: the line at the bank says what to do with the items, in the titled advice window"] = function(t)
    local c, addon = start()
    local before = addon.problems:count()
    c.setBankOpen(true)
    local text = promptOf(addon)
    t.eq(text, "Put in your bank for later: Linen Cloth x12, Copper Ore x5")
    local w = c.kitWindows().Advisor
    t.ok(type(w) == "table" and w.shown == true, "the advice window is shown at the bank")
    local said = false
    -- Lead section 408: the title is in the title bar, not a part.
    t.eq(w and w.title, TITLE, "under the add-on's own title")
    for _, p in ipairs((w and w.parts) or {}) do
        if p.text == text then said = true end
    end
    t.ok(said, "the line is on the window, whole")
    t.ok(not tostring(text):find("kind of item", 1, true), "never a bare count of kinds")
    t.eq(addon.problems:count(), before)
end

for name, fn in pairs(tests) do
    tests[name] = function(t)
        return fn(setmetatable({ eq = function(got, want, msg) return t.eq(plain(got), plain(want), msg) end },
            { __index = t }))
    end
end

return tests
