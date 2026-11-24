local _, ns = ...
-- The welcome and window-button setting rows (UI/Rows.lua) on the whole
-- add-on loaded on a fake client. UI/Rows.lua has no entry of its own: it
-- only declares rows, read by UI/WindowButtons.lua and UI/Intro.lua. So it
-- is tested through the settings page that shows the rows (the "settings"
-- slash word, a search, a control changed) and the world map button the
-- row switches. What the player sees: the row on the page under its own
-- label, the button gone after switching it off, still gone after a
-- reload. Unknown data: a saved value of the wrong type, and a control
-- given a value that is no on/off. Not tested in game.
local tests = {}

local R = ns.UIRows
local KEY = "buttons.worldMap"

local function start(account)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, {})
    c.setWindow("WorldMapFrame", {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function mapButton(c)
    for _, h in ipairs(c.windowButtons) do
        if h.frame == "WorldMapFrame" then return h end
    end
    return nil
end

local function pageRow(c, key)
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end

tests["window button rows: on the settings page, switched off there, the map button goes and stays gone"] = function(t)
    local c, addon = start()
    t.ok(mapButton(c) ~= nil, "a default profile has the world map button")
    c.slashes[ns.id.slash]("settings")
    c.optionsNav("search", "map")
    local row = pageRow(c, KEY)
    t.ok(row ~= nil, "the search finds the world map button row")
    for _, key in ipairs({ "ui.intro", "buttons.worldMap", "buttons.merchant", "buttons.profession", "buttons.bank" }) do
        local r = addon.settings:row(key)
        t.ok(r ~= nil, key .. " is a row")
        if r then t.eq(r.group, R.GROUP, key .. " is under the windows section") end
    end
    t.eq((c.optionsAct(KEY, false)), true, "the control takes off")
    t.eq(addon.settings:get(KEY), false, "switched off")

    local c2, addon2 = start(c.saved(ns.id.accountDB))
    t.eq(addon2.settings:get(KEY), false, "read back after a reload")
    t.eq(mapButton(c2), nil, "no world map button")
end

tests["window button rows: unknown data: a saved value of the wrong type and a control given no on/off"] = function(t)
    local c, addon = start({ settings = { buttons = { worldMap = "maybe" } } })
    local v = addon.settings:get(KEY)
    t.eq(type(v), "boolean", "the row answers on or off, never the stored text: " .. tostring(v))
    t.eq(mapButton(c) ~= nil, v == true, "the button follows what the row answers")

    c.slashes[ns.id.slash]("settings")
    c.optionsNav("search", "map")
    local ok = c.optionsAct(KEY, "sometimes")
    t.ok(ok ~= true, "a value that is no on/off is refused")
    t.eq(addon.settings:get(KEY), v, "the setting is unchanged")
end

return tests
