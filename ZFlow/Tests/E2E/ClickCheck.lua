local _, ns = ...
-- S23 (P-KEYS slice B): the click-casting check on the whole add-on loaded
-- on a fake client. When a click-cast add-on or another binding would take
-- the rotation key, one line on the Combat topic of the settings window
-- (and in the text page's key lines) says which. A read only: nothing is
-- bound, nothing is cleared, no add-on is touched. Per lead section 236: an
-- add-on loaded late, a reload, and a read that fails then recovers.
-- First guess: the add-on names (UI/ClickCheck.lua) and the override read
-- (c.bindingOverride) are not seen in game. Made-up keys and actions.
local tests = {}

local ACTION = "CLICK " .. ns.id.framePrefix .. "RotationKey:LeftButton"
local OTHER = "CLICK SomeClickCastButton:LeftButton"   -- made up
local NOTE = "keys.clickCheck"

-- opts: binds (a list of { key, action }), before(c), account, char.
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

local function ready(t, c)
    local ok = type(c.setForeignOverride) == "function" and type(c.setBindingOverrideFails) == "function"
        and type(c.setLoaded) == "function"
    t.ok(ok, "the fake client's c.setForeignOverride, c.setBindingOverrideFails and c.setLoaded")
    return ok
end

local function open(c)
    c.slashes[ns.id.slash]("settings")
    c.optionsNav("topic", "combat")
end

local function note(c)
    open(c)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == NOTE then return r end
    end
    return nil
end

local function has(s, text) return type(s) == "string" and s:find(text, 1, true) ~= nil end

local function inLines(addon, text)
    local page = addon.keysPage
    if type(page) ~= "table" or type(page.lines) ~= "function" then return false end
    for _, line in ipairs(page.lines()) do
        if has(line, text) then return true end
    end
    return false
end

tests["click check: a click-cast add-on and a binding over your key: one line names the key, what it does, and the add-on"] = function(t)
    local c, addon = boot({ binds = { { "F", ACTION } }, before = function(c0)
        if type(c0.setLoaded) == "function" then c0.setLoaded("Clique", true) end
        if type(c0.setForeignOverride) == "function" then c0.setForeignOverride("F", OTHER) end
    end })
    if not ready(t, c) then return end
    local r = note(c)
    t.ok(r ~= nil, "a click check line on the Combat topic")
    if not r then return end
    t.eq(r.kind, "note")
    t.ok(has(r.text, "F"), tostring(r.text))
    t.ok(has(r.text, OTHER), "what the key does: " .. tostring(r.text))
    t.ok(has(r.text, "Clique"), "the add-on named: " .. tostring(r.text))
    t.ok(inLines(addon, OTHER), "and in the text page's key lines")
    t.eq(c.bindingCalls(), {}, "nothing bound or cleared")
end

tests["click check: nothing loaded and the key is yours: no line"] = function(t)
    local c, addon = boot({ binds = { { "F", ACTION } } })
    if not ready(t, c) then return end
    t.eq(note(c), nil)
    t.ok(not inLines(addon, "click-cast"), "no line in the text page either")
end

tests["click check: a click-cast add-on loaded with your key free: a softer line names it"] = function(t)
    local c = boot({ binds = { { "F", ACTION } }, before = function(c0)
        if type(c0.setLoaded) == "function" then c0.setLoaded("Clique", true) end
    end })
    if not ready(t, c) then return end
    local r = note(c)
    t.ok(r ~= nil and has(r.text, "Clique"), "the add-on named: " .. tostring(r and r.text))
    t.ok(r == nil or not has(r.text, OTHER), "no key named as taken")
end

tests["click check: an add-on loaded late is named when the page is opened again"] = function(t)
    local c = boot({ binds = { { "F", ACTION } } })
    if not ready(t, c) then return end
    t.eq(note(c), nil, "nothing yet")
    c.setLoaded("Clique", true)
    c.fire("ADDON_LOADED", "Clique"); c.advance(1, 5)
    local r = note(c)
    t.ok(r ~= nil and has(r.text, "Clique"), "named once loaded: " .. tostring(r and r.text))
end

tests["click check: the override read fails: no line and no error; it recovers"] = function(t)
    local c = boot({ binds = { { "F", ACTION } } })
    if not ready(t, c) then return end
    c.setForeignOverride("F", OTHER)
    c.setBindingOverrideFails(true)
    local ok, r = pcall(note, c)
    t.ok(ok, "opening the page raises nothing")
    t.eq(r, nil, "not known is not a conflict")
    c.setBindingOverrideFails(false)
    r = note(c)
    t.ok(r ~= nil and has(r.text, OTHER), "the read recovers: " .. tostring(r and r.text))
    t.eq(c.bindingCalls(), {}, "nothing bound or cleared")
end

tests["click check: after a reload the line is read again from the game"] = function(t)
    local c = boot({ binds = { { "F", ACTION } } })
    if not ready(t, c) then return end
    t.eq(note(c), nil)
    local c2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB), binds = { { "F", ACTION } },
        before = function(c0)
            c0.setLoaded("Clique", true)
            c0.setForeignOverride("F", OTHER)
        end })
    local r = note(c2)
    t.ok(r ~= nil and has(r.text, OTHER) and has(r.text, "Clique"), "after the reload: " .. tostring(r and r.text))
end

return tests
