local _, ns = ...
-- Lead section 255: a "Set key" row for the mouseover button (Rotation/
-- Mouseover.lua, N63), through the same SettingsKeys slots and refusals as
-- the rotation key (Tests/E2E/SettingsKeys.lua). Whole add-on on a fake
-- client, a priest, entered the way the player enters: the slash word, the
-- Options page, the Combat topic's key rows, one key pressed into the
-- capture overlay. Section 236: a reload, a binding write raising once
-- then fine; and the mouseover button not made: the row says why and binds
-- nothing. Offline only; not tested in game. Made-up keys, ids and actions.
local tests = {}

local M = ns.Mouseover
local MOUSE = "CLICK " .. ns.id.framePrefix .. "Mouseover:LeftButton"
local ROTATION = "CLICK " .. ns.id.framePrefix .. "RotationKey:LeftButton"
local OTHER = "TOGGLEWORLDMAP"   -- made up
local KEY = "keys.mouseover"
local IDS = { ["Flash Heal"] = 2061, ["Dispel Magic"] = 527, ["Cure Disease"] = 528 }

-- opts: binds, account, char, on (switch the mouseover setting on).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("PRIEST"); c.setFaction("Alliance"); c.setLevel(20)
    c.setDead(false); c.setCombat(false); c.setLockdown(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
    end
    if type(c.setBindings) == "function" then c.setBindings(opts.binds or {}) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.on then
        addon.settings:set(M.SETTING, true)
        c.advance(3, 5)
    end
    return c, addon
end

local function reload(c)
    local binds, saved, keys = {}, c.savedBindingMap(), {}
    for key in pairs(saved) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do binds[#binds + 1] = { key, saved[key] } end
    return boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB), binds = binds })
end

local function open(c)
    c.slashes[ns.id.slash]("settings")
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

local function ready(t, c, addon)
    local ok = type(c.setBindings) == "function" and type(addon.SettingsKeys) == "table"
        and rowOf(c, KEY) ~= nil
    t.ok(ok, "the mouseover key row is on the Combat topic")
    return ok
end

tests["mouseover key: one row on the Combat topic, with its synonyms, found by search"] = function(t)
    local c, addon = boot({ on = true })
    open(c)
    if not ready(t, c, addon) then return end
    local r = rowOf(c, KEY)
    -- Changed for the window (lead section 285 item 3): it asserted kind "actions".
    t.eq({ r.kind, r.group, r.shown }, { "bind", "combat", addon.SettingsKeys.NOT_SET })
    for _, word in ipairs({ "mouseover", "heal", "cure", "friendly", "key", "bind" }) do
        local found = false
        for _, s in ipairs(r.synonyms or {}) do if s == word then found = true end end
        t.ok(found, "synonym " .. word)
    end
    c.optionsNav("search", "friendly")
    t.ok(rowOf(c, KEY) ~= nil, "found by search")
end

tests["mouseover key: set, reload, read back, clear, reload"] = function(t)
    local c, addon = boot({ on = true })
    open(c)
    if not ready(t, c, addon) then return end
    local S = addon.SettingsKeys
    t.eq(click(c, KEY, S.SET), true)
    t.eq(c.keyCaptureOpen(), true)
    c.pressKey("F")
    t.eq(c.bindingMap().F, MOUSE)
    t.eq(c.savedBindingMap().F, MOUSE)
    t.eq(shown(c, KEY), "F")
    t.eq(shown(c, "keys.rotation"), S.NOT_SET, "the rotation key is untouched")
    local c2 = reload(c)
    open(c2)
    t.eq(shown(c2, KEY), "F", "read back")
    t.eq(c2.bindingCalls(), {}, "the reload bound nothing")
    t.eq(click(c2, KEY, S.CLEAR), true)
    t.eq(c2.savedBindingMap().F, nil)
    local c3 = reload(c2)
    open(c3)
    t.eq(shown(c3, KEY), S.NOT_SET)
end

tests["mouseover key: refused in combat and with the lock not read"] = function(t)
    local c, addon = boot({ on = true })
    open(c)
    if not ready(t, c, addon) then return end
    local S = addon.SettingsKeys
    for _, lock in ipairs({ true, "unknown" }) do
        if lock == true then c.setLockdown(true) else c.setLockdown(nil) end
        c.optionsNav("action", buttonOf(rowOf(c, KEY), S.SET).key)
        t.eq(c.keyCaptureOpen(), false)
        t.ok(says(c, lock == true and S.LOCKED or S.LOCK_UNKNOWN), status(c))
    end
    t.eq(c.bindingCalls(), {})
end

tests["mouseover key: a key in use asks; Use it and unbind takes it and saves"] = function(t)
    local c, addon = boot({ on = true, binds = { { "M", OTHER } } })
    open(c)
    if not ready(t, c, addon) then return end
    local S = addon.SettingsKeys
    click(c, KEY, S.SET)
    c.pressKey("M")
    t.eq(c.bindingCalls(), {}, "nothing before the choice")
    local ask = rowOf(c, S.IN_USE_KEY)
    t.ok(ask and buttonOf(ask, S.ANYWAY) and buttonOf(ask, S.UNBIND) and buttonOf(ask, S.OTHER), "three choices")
    t.eq(click(c, S.IN_USE_KEY, S.UNBIND), true)
    t.eq(c.savedBindingMap().M, MOUSE)
end

tests["mouseover key: a key on the rotation key is Z-Flow's own: it moves without a question"] = function(t)
    local c, addon = boot({ on = true, binds = { { "G", ROTATION } } })
    open(c)
    if not ready(t, c, addon) then return end
    local S = addon.SettingsKeys
    click(c, KEY, S.SET)
    c.pressKey("G")
    t.eq(rowOf(c, S.IN_USE_KEY), nil, "no question")
    t.eq(c.savedBindingMap().G, MOUSE)
    t.eq(shown(c, "keys.rotation"), S.NOT_SET, "taken off the rotation key")
    t.ok(says(c, S.SLOTS[1].label), "the page says where it moved from: " .. status(c))
end

tests["mouseover key: the button not made, the row says why and binds nothing"] = function(t)
    local c, addon = boot()   -- the mouseover setting off: no button
    open(c)
    if not ready(t, c, addon) then return end
    local S = addon.SettingsKeys
    local r = rowOf(c, KEY)
    t.eq(buttonOf(r, S.SET).enabled, false)
    t.ok(type(r.why) == "string" and r.why:find(M.LABEL, 1, true) ~= nil, tostring(r.why))
    c.optionsNav("action", buttonOf(r, S.SET).key)
    t.eq(c.keyCaptureOpen(), false)
    t.ok(says(c, M.LABEL), status(c))
    t.eq(c.bindingCalls(), {})
    -- The rotation key is not held back by it.
    t.eq(buttonOf(rowOf(c, "keys.rotation"), S.SET).enabled, true)
end

tests["mouseover key (c): a write raising once says it could not be set; the next try works"] = function(t)
    local c, addon = boot({ on = true })
    open(c)
    if not ready(t, c, addon) then return end
    local S = addon.SettingsKeys
    c.setBindingWriteFault(1)
    click(c, KEY, S.SET)
    t.eq(pcall(c.pressKey, "H"), true, "no error escapes")
    t.ok(says(c, S.FAILED), status(c))
    t.eq(c.savedBindingMap().H, nil)
    click(c, KEY, S.SET)
    c.pressKey("H")
    t.eq(c.savedBindingMap().H, MOUSE)
end

return tests
