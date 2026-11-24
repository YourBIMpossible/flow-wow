local _, ns = ...
-- Reconcile row G34: hover-to-bind (UI/HoverBind.lua), on the whole add-on
-- loaded on a fake client and entered the way the player enters: the slash
-- word, the mouse on an action button's cover, a key pressed, the window's
-- Save, Undo and Cancel buttons. Offline: the fake client's covers, window
-- and binding table, not the game's. Not tested in game. Made-up keys.
local tests = {}

local H = ns.HoverBind
local B1, B2, B3 = "ACTIONBUTTON1", "ACTIONBUTTON2", "MULTIACTIONBAR1BUTTON3"
local OTHER = "TOGGLEWORLDMAP"   -- made up: what a key did before

local function boot(t, opts)
    if type(ns.offline) ~= "table" or type(ns.offline.addon) ~= "function" then
        t.skip("no whole add-on offline")
        return nil
    end
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setLockdown(false)
    c.setBindings(opts.binds or { { "1", B1 }, { "2", B2 }, { "M", OTHER } })
    c.setBarButtons(opts.buttons or { "ActionButton1", "ActionButton2", "MultiBarBottomLeftButton3" })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, #addon.problems:list()
end

local function slash(c, rest) c.slashes[ns.id.slash](rest) end

local function window(c)
    local w = c.kitWindows()[H.ID]
    if w == nil or w.shown ~= true then return nil end
    return w
end

-- The text of the part with that key, or nil.
local function part(c, key)
    local w = window(c)
    for _, p in ipairs(w and w.parts or {}) do
        if p.key == key then return tostring(p.text) end
    end
    return nil
end

local function printed(c, text)
    for _, line in ipairs(c.printed) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

local function press(c, id, chord)
    c.bindHoverOver(id)
    return c.bindHoverKey(chord)
end

tests["hover bind: the slash word covers the buttons on the screen and opens the list"] = function(t)
    local c, addon, before = boot(t)
    if not c then return end
    slash(c, H.WORD)
    t.eq(c.bindHoverOpen(), true, "the covers are up")
    t.eq(c.bindHoverIds(), { B1, B2, B3 }, "only the buttons on the screen")
    t.ok(window(c) ~= nil, "the window is up")
    t.eq(part(c, "intro"), H.INTRO)
    t.eq(part(c, "none"), H.NONE)
    t.eq(c.bindHoverLabels(), { [B1] = "1", [B2] = "2" }, "each cover shows the key it has")
    t.eq(c.kitClick(H.ID, "cancel"), true)
    t.eq(c.bindHoverOpen(), false, "cancelled: the covers are gone")
    t.eq(window(c), nil, "and the window")
    t.eq(#c.bindingCalls(), 0, "nothing was written")
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

tests["hover bind: a key pressed over a button is listed, and written only at Save"] = function(t)
    local c, addon, before = boot(t)
    if not c then return end
    slash(c, H.WORD)
    t.eq(press(c, B3, "SHIFT-F"), true)
    t.eq(part(c, "change1"), "SHIFT-F -> Bottom Left Bar, slot 3")
    t.eq(c.bindingMap()["SHIFT-F"], nil, "listed, not bound")
    t.eq(#c.bindingCalls(), 0, "no write yet")
    t.eq(c.bindHoverLabels()[B3], "SHIFT-F", "the cover shows the key it will have")
    t.eq(c.kitClick(H.ID, "save"), true)
    t.eq(c.bindingMap()["SHIFT-F"], B3, "bound")
    t.eq(c.savedBindingMap()["SHIFT-F"], B3, "and kept by the game's own save")
    t.eq(c.bindingCalls(), { "setBinding", "saveBindings" })
    t.eq(c.bindHoverOpen(), false, "the mode closed")
    t.ok(printed(c, string.format(H.SAVED, 1)), "the player is told")
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

tests["hover bind: a key that already does something says so before it is taken"] = function(t)
    local c, addon = boot(t)
    if not c then return end
    slash(c, H.WORD)
    press(c, B1, "M")
    t.eq(part(c, "change1"), "M -> Action Bar 1, slot 1")
    t.eq(addon.use(H.NAME).Staged(), { { key = "M", id = B1, was = OTHER } }, "what it does now is kept")
    local staged = H.Lines(addon.use(H.NAME).Staged())
    t.eq(staged[1].text, "M -> Action Bar 1, slot 1")
    t.eq(staged[1].sub, string.format(H.NOW, OTHER), "what it does now")
    t.eq(staged[1].tone, "warn")
    local swap = H.Lines({ { key = "2", id = B1, was = B2 } })
    t.eq(swap[1].sub, string.format(H.NOW, "Action Bar 1, slot 2"), "another button, by its name")
    t.eq(H.Lines({ { key = "1", id = B1, was = B1 } })[1].sub, H.SAME)
    t.eq(H.Lines({ { key = "F", id = B1, was = "" } })[1].sub, nil, "a free key: no warning")
    c.kitClick(H.ID, "save")
    t.eq(c.bindingMap()["M"], B1, "the player saved it all the same")
end

tests["hover bind: the newest of a key wins, Undo and Ctrl+Z take a line back"] = function(t)
    local c, addon = boot(t)
    if not c then return end
    slash(c, H.WORD)
    press(c, B1, "F"); press(c, B2, "G"); press(c, B3, "F")
    local staged = addon.use(H.NAME).Staged()
    t.eq(#staged, 2, "F is listed once")
    t.eq(staged[1].key, "G"); t.eq(staged[2].id, B3, "on the last button asked")
    t.eq(c.kitClick(H.ID, "undo"), true)
    t.eq(#addon.use(H.NAME).Staged(), 1)
    c.bindHoverOver(nil)
    t.eq(c.bindHoverKey(H.UNDO_KEY), true, "Ctrl+Z, the mouse on no button")
    t.eq(#addon.use(H.NAME).Staged(), 0)
    t.eq(part(c, "none"), H.NONE)
    t.eq(c.bindHoverKey("X"), true)
    t.eq(#addon.use(H.NAME).Staged(), 0, "a key with the mouse on no button lists nothing")
    c.kitClick(H.ID, "cancel")
    t.eq(#c.bindingCalls(), 0, "nothing written")
end

tests["hover bind: a right click lists a button's keys to come off"] = function(t)
    local c = boot(t, { binds = { { "1", B1 }, { "Q", B1 }, { "2", B2 } } })
    if not c then return end
    slash(c, H.WORD)
    t.eq(c.bindHoverRight(B1), true)
    t.eq(part(c, "change1"), "1 -> " .. H.OFF)
    t.eq(part(c, "change2"), "Q -> " .. H.OFF)
    c.bindHoverRight(B3)
    t.ok(printed(c, H.NO_KEYS), "a button with no key says so")
    c.kitClick(H.ID, "save")
    t.eq(c.bindingMap(), { ["2"] = B2 }, "both keys are off, the other button's stays")
    t.eq(c.savedBindingMap(), { ["2"] = B2 })
end

tests["hover bind: Escape asks once when changes are listed, then leaves every key"] = function(t)
    local c, addon = boot(t)
    if not c then return end
    slash(c, H.WORD)
    press(c, B1, "M")
    t.eq(c.bindHoverKey("ESCAPE"), true)
    t.eq(c.bindHoverOpen(), true, "still open: one change would be lost")
    t.eq(part(c, "footer"), string.format(H.AGAIN, 1))
    c.bindHoverKey("ESCAPE")
    t.eq(c.bindHoverOpen(), false, "the second Escape closes it")
    t.eq(c.bindingMap()["M"], OTHER, "the key does what it did")
    t.eq(#c.bindingCalls(), 0)
    t.ok(printed(c, H.CANCELLED))
    -- With nothing listed one Escape is enough; the window's X is Cancel.
    slash(c, H.WORD)
    c.bindHoverKey("ESCAPE")
    t.eq(c.bindHoverOpen(), false)
    slash(c, H.WORD)
    press(c, B1, "M")
    t.eq(c.kitClose(H.ID), true)
    t.eq(c.bindHoverOpen(), false, "the X closes the mode")
    t.eq(#addon.use(H.NAME).Staged(), 0)
    t.eq(#c.bindingCalls(), 0)
end

tests["hover bind: refused in combat, and a fight closes it with nothing changed"] = function(t)
    local c, addon, before = boot(t)
    if not c then return end
    c.setLockdown(true)
    slash(c, H.WORD)
    t.eq(c.bindHoverOpen(), false, "not in combat")
    t.ok(printed(c, H.LOCKED))
    c.setLockdown(false)
    slash(c, H.WORD)
    press(c, B1, "M")
    c.setLockdown(true)
    t.eq(c.kitClick(H.ID, "save"), true)
    t.eq(c.bindingMap()["M"], OTHER, "Save in combat writes nothing")
    c.fire("PLAYER_REGEN_DISABLED")
    t.eq(c.bindHoverOpen(), false, "the fight closed it")
    t.eq(window(c), nil)
    t.ok(printed(c, H.FIGHT))
    t.eq(#c.bindingCalls(), 0)
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

tests["hover bind: one refused key puts the others back and saves nothing"] = function(t)
    local c, addon, before = boot(t)
    if not c then return end
    slash(c, H.WORD)
    c.bindHoverRight(B2)          -- "2" comes off
    press(c, B1, "M")             -- M: was the map
    press(c, B3, "F")             -- F: was free
    local n = 0
    local real = c.setBinding
    c.setBinding = function(...)
        n = n + 1
        if n == 2 then error("SetBinding failed (test)", 0) end
        return real(...)
    end
    c.kitClick(H.ID, "save")
    c.setBinding = real
    t.eq(c.bindingMap(), { ["1"] = B1, ["2"] = B2, ["M"] = OTHER }, "every key as it was")
    t.eq(c.savedBindingMap(), { ["1"] = B1, ["2"] = B2, ["M"] = OTHER }, "nothing saved")
    t.ok(printed(c, H.FAILED))
    t.eq(c.bindHoverOpen(), true, "still open, the list kept")
    t.eq(#addon.use(H.NAME).Staged(), 3)
    -- The second try goes through.
    c.kitClick(H.ID, "save")
    t.eq(c.bindingMap(), { ["1"] = B1, ["M"] = B1, ["F"] = B3 })
    t.eq(c.savedBindingMap(), { ["1"] = B1, ["M"] = B1, ["F"] = B3 })
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

tests["hover bind: keys not read, or no button on the screen, opens nothing"] = function(t)
    local c = boot(t)
    if not c then return end
    c.setBindingReads(false)
    slash(c, H.WORD)
    t.eq(c.bindHoverOpen(), false)
    t.ok(printed(c, H.UNREAD))
    local c2 = boot(t, { buttons = {} })
    slash(c2, H.WORD)
    t.eq(c2.bindHoverOpen(), false)
    t.eq(window(c2), nil)
    t.ok(printed(c2, H.NO_BUTTONS))
end

tests["hover bind: every bar slot has a name, and the fake has the real client's functions"] = function(t)
    local targets = H.Targets()
    t.eq(#targets, 8 * 12 + 10)
    local seen = {}
    for _, target in ipairs(targets) do
        t.ok(seen[target.id] == nil, "once: " .. target.id)
        seen[target.id] = true
        t.eq(H.Label(target.id), target.label)
    end
    t.eq(H.Label("ACTIONBUTTON2"), "Action Bar 1, slot 2")
    t.eq(H.Label(OTHER), nil)
    local c = ns.make.fakeClient()
    for _, name in ipairs({ "setBinding", "bindHover", "setBarButtons", "bindHoverOpen", "bindHoverIds",
        "bindHoverOver", "bindHoverKey", "bindHoverRight", "bindHoverLabels" }) do
        t.ok(type(c[name]) == "function", name)
    end
    c.setLockdown(true)
    t.eq({ c.setBinding("F", B1) }, { false, "lockdown" }, "the write is refused in combat")
    t.eq({ c.setBinding("", B1) }, { false, "no key" })
end

return tests
