local _, ns = ...
-- N57 (lead section 249 item 2; Plexy's note 1 of section 250): the rotation
-- key and its second key set and cleared from the settings page, on the
-- whole add-on loaded on a fake client and entered the way the player
-- enters: the slash word, the Options page it opens, the Combat topic's key
-- rows and their buttons, one key pressed into the capture overlay. Per
-- lead section 236: a reload (a second add-on from the saved data and the
-- game's saved binding set), a binding read answering nil then late, and a
-- binding write raising once then fine. The add-on binds nothing on its
-- own: only the player's press on the page writes, out of combat.
-- Offline: the fake client's page, overlay and binding table, not the
-- game's. Not tested in game. Made-up keys and actions only.
local tests = {}

local ACTION = "CLICK " .. ns.id.framePrefix .. "RotationKey:LeftButton"
local OTHER = "TOGGLEWORLDMAP"   -- made up: what the key did before
local KEY1, KEY2 = "keys.rotation", "keys.rotation2"

-- opts: binds (the game's saved set, a list of { key, action }), before(c).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setLockdown(false)
    if type(c.setBindings) == "function" then c.setBindings(opts.binds or {}) end
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The same player after a reload: the saved data and the game's saved
-- binding set; what was only live (not saved, or an override) is gone.
local function reload(c)
    local binds = {}
    local saved = c.savedBindingMap()
    local keys = {}
    for key in pairs(saved) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do binds[#binds + 1] = { key, saved[key] } end
    return boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB), binds = binds })
end

local function ready(t, c)
    local ok = type(c.setBindings) == "function" and type(c.pressKey) == "function"
        and type(c.optionsNav) == "function"
    t.ok(ok, "the fake client's bindings, overlay and page controls are there")
    return ok
end

local function slash(c, rest) c.slashes[ns.id.slash](rest) end

local function open(c)
    slash(c, "settings")
    c.optionsNav("topic", "combat")
end

local function rowOf(c, key)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function buttonOf(r, text)
    if type(r) ~= "table" then return nil end
    for _, b in ipairs(r.actions or {}) do
        if b.label == text then return b end
    end
    return nil
end

-- The player clicks a row's button: true when it was there and enabled.
local function click(c, key, text)
    local b = buttonOf(rowOf(c, key), text)
    if not b or b.enabled ~= true then return false end
    c.optionsNav("action", b.key)
    return true
end

local function shown(c, key)
    local r = rowOf(c, key)
    return r and r.shown
end

local function status(c) return tostring(c.optionsStatus() or "") end

local function says(c, text) return status(c):find(text, 1, true) ~= nil end

local function SK(addon) return addon.SettingsKeys end

-- Rows -------------------------------------------------------------------

tests["settings keys: the Combat topic shows the rotation key and its second key, each with Set key and Clear"] = function(t)
    local c, addon = boot({ binds = { { "F", ACTION } } })
    if not ready(t, c) then return end
    t.ok(type(SK(addon)) == "table", "the add-on has the key rows")
    if type(SK(addon)) ~= "table" then return end
    open(c)
    local one, two = rowOf(c, KEY1), rowOf(c, KEY2)
    t.ok(one ~= nil and two ~= nil, "both rows drawn")
    if not (one and two) then return end
    t.eq({ one.kind, one.group, one.shown }, { "actions", "combat", "F" })
    t.eq({ two.kind, two.shown }, { "actions", SK(addon).NOT_SET })
    for _, word in ipairs({ "key", "keybind", "bind", "binding", "hotkey" }) do
        local found = false
        for _, s in ipairs(one.synonyms or {}) do if s == word then found = true end end
        t.ok(found, "synonym " .. word)
    end
    t.eq(buttonOf(one, SK(addon).SET).enabled, true)
    t.eq(buttonOf(one, SK(addon).CLEAR).enabled, true)
    t.eq(buttonOf(two, SK(addon).CLEAR).enabled, false, "nothing to clear")
    -- A search by a synonym finds them too.
    c.optionsNav("search", "hotkey")
    t.ok(rowOf(c, KEY1) ~= nil and rowOf(c, KEY2) ~= nil, "found by search")
    -- Not on another topic.
    c.optionsNav("topic", "bags")
    t.eq(rowOf(c, KEY1), nil)
end

tests["settings keys: the text page shows the current keys"] = function(t)
    local c, addon = boot({ binds = { { "F", ACTION }, { "G", ACTION } } })
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    addon.SettingsPage.Goto(addon, "combat")
    local text = table.concat(addon.SettingsPanel.Lines(addon), "\n")
    t.ok(text:find(SK(addon).SLOTS[1].label .. ": F", 1, true) ~= nil, text)
    t.ok(text:find(SK(addon).SLOTS[2].label .. ": G", 1, true) ~= nil, text)
end

-- Section 236 scenarios ----------------------------------------------------

tests["keys workflow: set the key and the second key, reload, read back, clear one, reload"] = function(t)
    local c, addon = boot()
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    local S = SK(addon)
    open(c)
    t.eq(c.bindingCalls(), {}, "nothing bound on load")
    t.eq(click(c, KEY1, S.SET), true)
    t.eq(c.keyCaptureOpen(), true, "the overlay waits for a key")
    t.ok(says(c, S.SLOTS[1].label), status(c))
    t.eq(c.bindingCalls(), {}, "nothing written before the key")
    t.eq(c.pressKey("CTRL-F"), true)
    t.eq(c.keyCaptureOpen(), false)
    t.eq(c.bindingMap()["CTRL-F"], ACTION)
    t.eq(c.savedBindingMap()["CTRL-F"], ACTION, "saved in the game's binding set")
    t.eq(shown(c, KEY1), "CTRL-F", "redrawn")
    t.ok(says(c, "CTRL-F"), status(c))
    click(c, KEY2, S.SET)
    c.pressKey("G")
    t.eq(c.bindingKeys(ACTION), { "CTRL-F", "G" })
    t.eq(shown(c, KEY2), "G")

    local c2 = reload(c)
    open(c2)
    t.eq({ shown(c2, KEY1), shown(c2, KEY2) }, { "CTRL-F", "G" }, "read back after the reload")
    t.eq(c2.bindingCalls(), {}, "the reload bound nothing")
    t.eq(click(c2, KEY1, S.CLEAR), true)
    t.eq(c2.savedBindingMap()["CTRL-F"], nil, "the clear is saved")
    t.eq(shown(c2, KEY1), "G", "the second key is now the first")
    local c3 = reload(c2)
    open(c3)
    t.eq({ shown(c3, KEY1), shown(c3, KEY2) }, { "G", S.NOT_SET })
end

tests["keys workflow: Escape cancels and writes nothing"] = function(t)
    local c, addon = boot({ binds = { { "F", ACTION } } })
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    open(c)
    click(c, KEY1, SK(addon).SET)
    t.eq(c.pressKey("ESCAPE"), true)
    t.eq(c.keyCaptureOpen(), false)
    t.eq(c.bindingCalls(), {})
    t.eq(c.bindingMap().F, ACTION, "the old key kept")
    t.ok(says(c, SK(addon).CANCELLED), status(c))
end

tests["keys workflow: refused in combat and with the lock not read; nothing opens or is written"] = function(t)
    local c, addon = boot({ binds = { { "F", ACTION } } })
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    local S = SK(addon)
    open(c)
    for _, lock in ipairs({ true, "unknown" }) do
        if lock == true then c.setLockdown(true) else c.setLockdown(nil) end
        local why = lock == true and S.LOCKED or S.LOCK_UNKNOWN
        local set = buttonOf(rowOf(c, KEY1), S.SET)
        c.optionsNav("action", set.key)
        t.eq(c.keyCaptureOpen(), false, tostring(lock) .. ": no overlay")
        t.ok(says(c, why), tostring(lock) .. ": " .. status(c))
        c.optionsNav("action", buttonOf(rowOf(c, KEY1), S.CLEAR).key)
        t.eq(c.bindingMap().F, ACTION, tostring(lock) .. ": not cleared")
        t.eq(buttonOf(rowOf(c, KEY1), S.SET).enabled, false, tostring(lock) .. ": the buttons are greyed")
    end
    -- The lock comes on while the overlay waits: the key is refused.
    c.setLockdown(false)
    c.optionsNav("topic", "combat")
    click(c, KEY2, S.SET)
    t.eq(c.keyCaptureOpen(), true)
    c.setLockdown(true)
    c.pressKey("G")
    t.eq(c.bindingMap().G, nil, "nothing set in combat")
    t.ok(says(c, S.LOCKED), status(c))
    t.eq(c.bindingCalls(), {})
end

tests["keys workflow: a key in use says what it does; Use it anyway is for this session only"] = function(t)
    local c, addon = boot({ binds = { { "M", OTHER } } })
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    local S = SK(addon)
    open(c)
    click(c, KEY1, S.SET)
    c.pressKey("M")
    t.eq(c.bindingCalls(), {}, "nothing written before the choice")
    local ask = rowOf(c, S.IN_USE_KEY)
    t.ok(ask ~= nil, "the question is on the page")
    if not ask then return end
    t.ok(tostring(ask.label):find("M", 1, true) and tostring(ask.label):find(OTHER, 1, true), tostring(ask.label))
    t.ok(buttonOf(ask, S.ANYWAY) and buttonOf(ask, S.UNBIND) and buttonOf(ask, S.OTHER), "three choices")
    t.eq(click(c, S.IN_USE_KEY, S.ANYWAY), true)
    t.eq(c.overrideKeys().M, ns.id.framePrefix .. "RotationKey")
    t.eq(c.bindingMap().M, OTHER, "the game's binding stays under it")
    t.eq(c.savedBindingMap().M, OTHER, "nothing saved")
    t.eq(shown(c, KEY1), "M" .. S.SESSION)
    t.eq(rowOf(c, S.IN_USE_KEY), nil, "the question is gone")
    local c2 = reload(c)
    open(c2)
    t.eq(shown(c2, KEY1), S.NOT_SET, "gone after the reload, as the page said")
    t.eq(c2.bindingMap().M, OTHER)
end

tests["keys workflow: a key in use, Use it and unbind takes it from the other action and saves"] = function(t)
    local c, addon = boot({ binds = { { "M", OTHER } } })
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    local S = SK(addon)
    open(c)
    click(c, KEY1, S.SET)
    c.pressKey("M")
    t.eq(click(c, S.IN_USE_KEY, S.UNBIND), true)
    t.eq(c.bindingMap().M, ACTION)
    t.eq(c.savedBindingMap().M, ACTION, "saved")
    t.eq(shown(c, KEY1), "M")
    local c2 = reload(c)
    open(c2)
    t.eq(shown(c2, KEY1), "M")
end

tests["keys workflow: a key in use, Pick another opens the overlay again"] = function(t)
    local c, addon = boot({ binds = { { "M", OTHER } } })
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    local S = SK(addon)
    open(c)
    click(c, KEY1, S.SET)
    c.pressKey("M")
    t.eq(click(c, S.IN_USE_KEY, S.OTHER), true)
    t.eq(c.keyCaptureOpen(), true)
    t.eq(rowOf(c, S.IN_USE_KEY), nil)
    c.pressKey("N")
    t.eq(c.bindingMap().N, ACTION)
    t.eq(c.bindingMap().M, OTHER, "the other action keeps its key")
    t.eq(shown(c, KEY1), "N")
end

tests["keys workflow: a key that is already one of Z-Flow's moves, never doubles and never asks"] = function(t)
    local c, addon = boot({ binds = { { "F", ACTION }, { "G", ACTION } } })
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    local S = SK(addon)
    open(c)
    click(c, KEY1, S.SET)
    c.pressKey("G")
    t.eq(rowOf(c, S.IN_USE_KEY), nil, "no question")
    t.eq(c.bindingKeys(ACTION), { "G" })
    t.eq(c.bindingMap().F, nil, "the old first key is cleared")
    t.eq(c.savedBindingMap().G, ACTION)
    t.eq({ shown(c, KEY1), shown(c, KEY2) }, { "G", S.NOT_SET })
end

tests["keys workflow (a): a binding read answering nil shows not known and refuses; late, it shows"] = function(t)
    local c, addon = boot({ binds = { { "F", ACTION } }, before = function(c0) c0.setBindingReads(false) end })
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    local S = SK(addon)
    open(c)
    t.eq(shown(c, KEY1), S.NOT_KNOWN, "never not set, never a guess")
    t.eq(buttonOf(rowOf(c, KEY1), S.SET).enabled, false)
    c.optionsNav("action", buttonOf(rowOf(c, KEY1), S.SET).key)
    t.eq(c.keyCaptureOpen(), false)
    t.ok(says(c, S.UNREAD), status(c))
    t.eq(c.bindingCalls(), {})
    c.setBindingReads(true)
    c.optionsNav("topic", "combat")
    t.eq(shown(c, KEY1), "F", "the late answer shows")
    t.eq(click(c, KEY1, S.SET), true)
end

tests["keys workflow (c): a binding write raising once says it could not be set; the next try works"] = function(t)
    local c, addon = boot({ binds = { { "F", ACTION } } })
    if not ready(t, c) or type(SK(addon)) ~= "table" then t.ok(false, "key rows") return end
    local S = SK(addon)
    open(c)
    c.setBindingWriteFault(1)
    click(c, KEY1, S.SET)
    local ok = pcall(c.pressKey, "H")
    t.eq(ok, true, "no error escapes")
    t.ok(says(c, S.FAILED), status(c))
    t.eq(c.bindingMap().H, nil)
    t.eq(c.bindingMap().F, ACTION, "the old key put back")
    t.eq(c.savedBindingMap().F, ACTION, "nothing new saved")
    t.eq(c.savedBindingMap().H, nil)
    click(c, KEY1, S.SET)
    c.pressKey("H")
    t.eq(c.bindingMap().H, ACTION)
    t.eq(c.savedBindingMap().H, ACTION)
end

tests["keys: nothing is bound on load, on an event or on a timer"] = function(t)
    local c = boot({ binds = { { "F", ACTION } } })
    if not ready(t, c) then return end
    c.fire("PLAYER_REGEN_DISABLED"); c.fire("PLAYER_REGEN_ENABLED")
    c.fire("UPDATE_BINDINGS")
    c.advance(60, 20)
    t.eq(c.bindingCalls(), {})
    t.eq(c.overrideKeys(), {})
end

return tests
