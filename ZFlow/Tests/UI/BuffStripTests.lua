local _, ns = ...

-- Old-Flow parity R6: the strip of your own class buffs with the time left,
-- under the player frame (UI/BuffStrip.lua). Offline, over the fake client;
-- none of this was looked at in game.

local B = ns.BuffStrip
local tests = {}

tests["buff strip: the time left in the words a player reads"] = function(t)
    t.eq(B.Time(1500), "25 min")
    t.eq(B.Time(90), "2 min")
    t.eq(B.Time(40.4), "40 s")
    t.eq(B.Time(7200), "2 h")
    t.eq(B.Time(math.huge), nil, "no end: no time")
    t.eq(B.Time(true), nil, "not known: no time")
    t.eq(B.Time(-1), nil)
end

tests["buff strip: only the class buffs that are on, in the pack's order"] = function(t)
    local rows = B.Rows({ "Test Armor", "Test Intellect", "Test Ward" },
        { ["Test Intellect"] = 1500, ["Test Armor"] = 30, ["Someone Else's"] = 60 })
    t.eq(#rows, 2, "two of the three, and not a stranger's")
    t.eq(rows[1], { name = "Test Armor", left = 30, soon = true }, "close to running out")
    t.eq(rows[2], { name = "Test Intellect", left = 1500, soon = false })
    local odd = B.Rows({ "Test Armor", "Test Ward" }, { ["Test Armor"] = math.huge, ["Test Ward"] = true })
    t.eq(odd[1].left, nil, "no end: no time")
    t.eq(odd[1].soon, false, "and never 'soon'")
    t.eq(odd[2].left, nil, "time not known")
    t.eq(#B.Rows({ "Test Armor" }, nil), 0, "the buffs not read: nothing, never 'missing'")
    t.eq(#B.Rows(nil, {}), 0)
end

tests["buff strip: one that ran out is named after those that are on"] = function(t)
    local rows = B.Rows({ "Test Armor", "Test Intellect" }, { ["Test Intellect"] = 600 }, { ["Test Armor"] = true })
    t.eq(rows[1].name, "Test Intellect")
    t.eq(rows[2], { name = "Test Armor", gone = true })
    local back = B.Rows({ "Test Armor" }, { ["Test Armor"] = 600 }, { ["Test Armor"] = true })
    t.eq(#back, 1, "on again: named once")
    t.eq(back[1].gone, nil)
end

tests["buff strip: each line says how long, and what to do when it matters"] = function(t)
    local kids = B.Children({
        { name = "Test Intellect", left = 1500, soon = false },
        { name = "Test Armor", left = 30, soon = true },
        { name = "Test Ward", soon = false },
        { name = "Test Shield", gone = true },
    })
    t.eq(kids[1].kind, "header")
    t.eq(kids[2].text, "Test Intellect"); t.eq(kids[2].right, "25 min"); t.eq(kids[2].sub, nil)
    t.eq(kids[3].right, "30 s"); t.eq(kids[3].tone, "warn"); t.eq(kids[3].sub, B.SOON_TEXT)
    t.eq(kids[4].right, B.ON, "no time: on")
    t.eq(kids[5].right, B.GONE); t.eq(kids[5].tone, "bad"); t.eq(kids[5].sub, B.GONE_TEXT)
    for i = 2, 5 do t.eq(kids[i].onClick, nil, "a line is not a button") end
    t.ok(ns.Kit.Window({ id = B.ID, title = "t", children = kids }) ~= nil, "the kit takes it")
end

tests["buff strip: it stands under the player frame when there is room"] = function(t)
    local rect = { l = 20, r = 250, b = 640, t = 740 }
    t.eq(B.Dock(rect, 1024, 768, 94), { "TOPLEFT", "BOTTOMLEFT", 20, 640 - B.GAP })
    t.eq(B.Dock({ l = 20, r = 250, b = 50, t = 150 }, 1024, 768, 94), nil, "no room under it")
    t.eq(B.Dock(nil, 1024, 768, 94), nil, "the frame not read")
    t.eq(B.Dock(rect, nil, nil, 94), nil, "the screen not read")
end

-- ------------------------------------------------------------ whole add-on
local function start(t, class)
    if type(ns.offline) ~= "table" or type(ns.offline.addon) ~= "function" then
        t.skip("no whole add-on offline")
        return nil
    end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setFrameRect(B.FRAME, { l = 20, r = 250, b = 640, t = 740 })
    c.setClass(class or "MAGE")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    return c, addon
end

local function said(c)
    local w = c.kitWindows()[B.ID]
    if w == nil or w.shown ~= true then return nil end
    local out = {}
    for _, part in ipairs(w.parts) do out[#out + 1] = tostring(part.text) end
    return table.concat(out, "\n"), w
end

tests["buff strip module: a mage sees the buffs on them, then which ran out"] = function(t)
    local c, addon = start(t)
    if not c then return end
    local before = #addon.problems:list()
    c.advance(B.EVERY + 0.1, 2)
    t.eq(said(c), nil, "no class buff on: no strip")
    c.setPlayerBuffs({ ["Arcane Intellect"] = 1500, ["Frost Armor"] = 40, ["Test Stranger"] = 10 })
    c.advance(B.EVERY + 0.1, 2)
    local text, w = said(c)
    t.ok(text ~= nil, "the strip is up")
    if not text then return end
    t.ok(text:find("Frost Armor", 1, true) ~= nil, text)
    t.ok(text:find("Arcane Intellect", 1, true) ~= nil, text)
    t.eq(text:find("Test Stranger", 1, true), nil, "not a buff of the class")
    t.eq(w.point, { "TOPLEFT", "BOTTOMLEFT", 20, 640 - B.GAP }, "under the player frame")
    local rows = addon.use(B.NAME).Rows()
    t.eq(rows[1].name, "Frost Armor"); t.eq(rows[1].soon, true, "close to running out")
    t.eq(rows[2].soon, false)
    -- It runs out.
    c.setPlayerBuffs({ ["Arcane Intellect"] = 1400 })
    c.advance(B.EVERY + 0.1, 2)
    rows = addon.use(B.NAME).Rows()
    t.eq(rows[2], { name = "Frost Armor", gone = true }, "named as run out")
    -- Cast again: on, and no longer run out.
    c.setPlayerBuffs({ ["Arcane Intellect"] = 1390, ["Frost Armor"] = 1800 })
    c.advance(B.EVERY + 0.1, 2)
    rows = addon.use(B.NAME).Rows()
    t.eq(#rows, 2); t.eq(rows[1].gone, nil)
    -- Replaced with plenty left: not nagged about.
    c.setPlayerBuffs({ ["Arcane Intellect"] = 1380, ["Mage Armor"] = 1800 })
    c.advance(B.EVERY + 0.1, 2)
    rows = addon.use(B.NAME).Rows()
    t.eq(#rows, 2, "the new armour and the intellect")
    t.eq(rows[1].name, "Mage Armor")
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

tests["buff strip module: off, or the buffs not read, shows nothing"] = function(t)
    local c, addon = start(t)
    if not c then return end
    c.setPlayerBuffs({ ["Arcane Intellect"] = 1500 })
    c.advance(B.EVERY + 0.1, 2)
    t.ok(said(c) ~= nil, "up")
    addon.settings:set(B.SETTING, false)
    c.advance(B.EVERY + 0.1, 2)
    t.eq(said(c), nil, "turned off: gone")
    addon.settings:set(B.SETTING, true)
    c.advance(B.EVERY + 0.1, 2)
    t.ok(said(c) ~= nil, "on again: back")
    c.setPlayerBuffs(nil)
    c.advance(B.EVERY + 0.1, 2)
    t.eq(said(c), nil, "not read: nothing claimed")
end

tests["buff strip module: a dragged place is kept"] = function(t)
    local c, addon = start(t)
    if not c then return end
    c.setPlayerBuffs({ ["Arcane Intellect"] = 1500 })
    c.advance(B.EVERY + 0.1, 2)
    t.eq(c.kitDrag(B.ID, { "TOPLEFT", "BOTTOMLEFT", 300, 500 }), true, "dragged")
    t.eq(addon.store:get("account", B.PATH).point, { "TOPLEFT", "BOTTOMLEFT", 300, 500 }, "saved")
end

-- Owner's report (lead section 561 item 6): the strip can be closed, and
-- closing it is switching it off. Red on aa3dd5a8: closing wrote nothing,
-- so the setting stayed on and the strip came back at the next look.
tests["buff strip module: closing it switches the setting off, says how to get it back, and it stays closed"] = function(t)
    local c, addon = start(t)
    if not c then return end
    c.setPlayerBuffs({ ["Arcane Intellect"] = 1500 })
    c.advance(B.EVERY + 0.1, 2)
    t.ok(said(c) ~= nil, "up")
    t.eq(addon.settings:get(B.SETTING), true, "on by default")
    local from = #c.printed
    t.eq(c.kitClose(B.ID), true, "the player closes it")
    t.eq(addon.settings:get(B.SETTING), false, "closing it switched the setting off")
    c.advance(B.EVERY * 3, 6)
    t.eq(said(c), nil, "it stays closed")
    local lines = {}
    for i = from + 1, #c.printed do lines[#lines + 1] = tostring(c.printed[i]) end
    t.eq(#lines, 1, "one chat line")
    t.ok(lines[1] ~= nil and lines[1]:find(B.LABEL, 1, true) ~= nil
        and lines[1]:find(ns.id.slash .. " settings", 1, true) ~= nil, "it names the setting and the way there: "
        .. tostring(lines[1]))
    -- Lead section 578 point A: the click path too. Red on 6f77dd79.
    t.ok(lines[1] ~= nil and lines[1]:find("left-click the Flow button", 1, true) ~= nil,
        "and the click path: " .. tostring(lines[1]))
    -- Kept over a reload: the saved setting is what was written.
    local c2 = ns.make.fakeClient()
    c2.setSaved(ns.id.accountDB, c.saved(ns.id.accountDB)); c2.setSaved(ns.id.charDB, {})
    c2.setScreen(1024, 768); c2.setClass("MAGE")
    local addon2 = ns.offline.addon(c2)
    c2.fire("ADDON_LOADED", ns.id.addon); c2.fire("PLAYER_LOGIN"); c2.fire("PLAYER_ENTERING_WORLD")
    c2.setPlayerBuffs({ ["Arcane Intellect"] = 1500 })
    c2.advance(B.EVERY * 3, 6)
    t.eq(addon2.settings:get(B.SETTING), false, "still off after a reload")
    t.eq(said(c2), nil, "and not shown")
    addon2.settings:set(B.SETTING, true)
    c2.advance(B.EVERY + 0.1, 2)
    t.ok(said(c2) ~= nil, "switched on in the settings: back")
end

return tests
