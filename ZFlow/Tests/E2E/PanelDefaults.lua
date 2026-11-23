local _, ns = ...
-- What a new player sees with nothing saved (lead section 294, item 4), on
-- the whole add-on loaded on a fake client, from a default profile, through
-- the login events and the settings the player has.
--   info bar     shown by default (N59 is the owner's info display)
--   alerts       stay off by default, as legacy Flow: it said nothing in
--                chat when a prompt turned up (see UI/Alerts.lua)
--   advisor,     on by default and hidden with nothing to list; each one's
--   boss loot    settings row says when the panel appears
-- A value the player saved is kept: only the default for a key never saved
-- changes. Offline: the fake client bar and panels, not the game frames.
-- Not tested in game. Made-up values only.
-- Fails before the code: the info bar is off by default (no bar shown at
-- login), and neither row's help says when its panel appears.
local tests = {}

local function boot(account)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setMoney(12345)
    c.setBags({ { bag = 0, free = 4, total = 16 }, { bag = 1, free = 8, total = 20 } })
    c.setDurability({ [1] = { cur = 50, max = 100 } })
    c.setXp({ cur = 450, max = 1000, rested = 200 })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function bar(c) return type(c.infoBars) == "table" and c.infoBars[1] or nil end

local function shown(c)
    local b = bar(c)
    return b ~= nil and b.shown == true
end

-- ------------------------------------------------------------------ info bar
tests["panel defaults: nothing saved, the info bar is on the screen at login with its four metrics"] = function(t)
    local c, addon = boot()
    t.eq(addon.settings:get("infoBar.shown"), true, "on by default")
    t.eq(shown(c), true, "the bar is shown with no setting touched")
    t.eq(bar(c) and bar(c).text, "1g 23s 45c  |  Bags 12  |  Dur 50%  |  XP 45%")
    local row = addon.settings:row("infoBar.shown")
    t.eq(type(row) == "table" and row.default, true, "the row's default")
end

tests["panel defaults: an info bar the player turned off stays off, and the saved value is kept"] = function(t)
    local c, addon = boot({ settings = { infoBar = { shown = false } } })
    t.eq(addon.settings:get("infoBar.shown"), false)
    t.eq(shown(c), false, "not shown")
    local saved = c.saved(ns.id.accountDB)
    t.eq(saved.settings.infoBar.shown, false, "the saved value is not overwritten")
end

tests["panel defaults: an info bar the player turned on stays on after a reload"] = function(t)
    local c = boot({ settings = { infoBar = { shown = true } } })
    t.eq(shown(c), true)
    t.eq(c.saved(ns.id.accountDB).settings.infoBar.shown, true)
end

tests["panel defaults: the player turns the default bar off and it is off after a reload"] = function(t)
    local c, addon = boot()
    t.ok(addon.settings:set("infoBar.shown", false), "the setting takes")
    t.eq(shown(c), false)
    local c2, addon2 = boot(c.saved(ns.id.accountDB))
    t.eq(addon2.settings:get("infoBar.shown"), false, "kept, not put back to the default")
    t.eq(shown(c2), false)
end

-- -------------------------------------------------------------------- alerts
tests["panel defaults: alerts stay off with nothing saved, and the sound with them"] = function(t)
    local A = ns.Alerts
    t.ok(type(A) == "table", "ns.Alerts")
    if type(A) ~= "table" then return end
    local _, addon = boot()
    t.eq(addon.settings:get(A.SETTING), false, "as legacy Flow: no chat line for a new prompt")
    t.eq(addon.settings:get(A.SOUND), false)
end

-- ------------------------------------------------- advisor and boss loot rows
local function panelOf(c, name)
    for _, p in ipairs(c.panels or {}) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. name then return p end
    end
    return nil
end

-- The one line that says when the panel appears, and that it is on the row
-- the settings window shows.
local function says(t, addon, key, const, label)
    t.ok(type(const) == "string" and const ~= "", label .. ": the line is declared")
    if type(const) ~= "string" or const == "" then return end
    t.ok(not const:find("\n", 1, true), label .. ": one line")
    local row = addon.settings:row(key)
    t.ok(type(row) == "table", label .. ": the row " .. key)
    if type(row) ~= "table" then return end
    t.eq(row.default, true, label .. ": on by default")
    t.ok(type(row.help) == "string" and row.help:find(const, 1, true) ~= nil,
        label .. ": the row's help says when it appears: " .. tostring(row.help))
end

tests["panel defaults: the advisor row says when the panel appears; nothing to say, nothing shown"] = function(t)
    local c, addon = boot()
    local A = ns.Advisor or {}
    says(t, addon, "advisor.panel", A.APPEARS, "advisor")
    t.eq(addon.settings:get("advisor.panel"), true)
    local p = panelOf(c, "Advisor")
    t.ok(p ~= nil, "the panel is made")
    t.eq(p and p.shown, false, "hidden with no prompt")
end

tests["panel defaults: the boss loot row says when the panel appears; no boss, nothing shown"] = function(t)
    local c, addon = boot()
    local B = ns.BossLoot or {}
    says(t, addon, B.SETTING or "loot.bossPanel", B.APPEARS, "boss loot")
    local p = panelOf(c, "BossLoot")
    t.ok(p ~= nil, "the panel is made")
    t.eq(p and p.shown, false, "hidden with no boss")
end

return tests
