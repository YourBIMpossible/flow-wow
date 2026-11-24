local _, ns = ...
-- The minimap button end to end (lead DISPATCH sections 340 and 303(g)):
-- made at login while its setting is on (the default), a click opens the
-- settings page only, a drag saves the angle and a reload puts it back,
-- the setting off hides it at once and on shows it again, and a client
-- that cannot make it costs one problem line and nothing else. Fake
-- client button, not the game frame. Not tested in game.
local tests = {}

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setMinimap({ size = 140, square = opts.square })
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function button(c) return type(c.minimapButtons) == "table" and c.minimapButtons[1] or nil end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

local function mine(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do
        if p.kind == "minimapButton" or p.owner == "minimapButton" then n = n + (p.count or 1) end
    end
    return n
end

tests["minimap button: made and shown at login by default, with the title and the hint"] = function(t)
    local c, addon = boot()
    local b = button(c)
    t.ok(b ~= nil, "made")
    t.eq(b and b.shown, true, "shown")
    t.eq(#c.minimapButtons, 1, "made once")
    t.eq(addon.settings:get("ui.minimapButton"), true, "on by default")
    t.eq(b and b.tipLines, { ns.id.title, "Click: settings. Right-click: route menu. Drag: move." })
    t.ok(b and type(b.x) == "number" and type(b.y) == "number", "placed")
    t.eq(mine(addon), 0, "no problem")
end

tests["minimap button: a click opens the settings page"] = function(t)
    local c = boot()
    local opened = c.optionsOpened()
    button(c).click()
    t.eq(c.optionsOpened(), opened + 1, "the settings page opened")
end

local function row(items, key)
    for _, item in ipairs(items or {}) do
        if item.key == key then return item end
    end
    return nil
end

tests["minimap button: a right click opens the route menu and not the settings"] = function(t)
    local c = boot()
    local opened = c.optionsOpened()
    local b = button(c)
    b.click("right")
    t.eq(c.optionsOpened(), opened, "the settings page stays shut")
    t.ok(type(b.menuItems) == "table", "the menu is open")
    t.eq(b.menuItems[1].title, true)
    t.eq(b.menuItems[1].text, ns.id.title .. " route")
    t.eq(row(b.menuItems, "plan").text, "Plan a route from my quest log")
    t.eq(row(b.menuItems, "none").disabled, true, "no route: says so, nothing to skip or clear")
    t.eq(row(b.menuItems, "skip"), nil)
    t.eq(row(b.menuItems, "clear"), nil)
    t.eq(row(b.menuItems, "window").checked, true, "the route window is on at first")
    t.ok(row(b.menuItems, "settings") ~= nil)
end

tests["minimap button: the menu's settings row opens the settings page"] = function(t)
    local c = boot()
    local opened = c.optionsOpened()
    local b = button(c)
    b.click("right")
    b.choose("settings")
    t.eq(b.menuItems, nil, "the menu closed")
    t.eq(c.optionsOpened(), opened + 1)
end

tests["minimap button: the menu's window row switches the route window's setting"] = function(t)
    local c, addon = boot()
    local b = button(c)
    b.click("right")
    b.choose("window")
    t.eq(addon.settings:get("nav.tracker"), false)
    b.click("right")
    t.eq(row(b.menuItems, "window").checked, false)
    b.choose("window")
    t.eq(addon.settings:get("nav.tracker"), true)
end

tests["minimap button: hiding the button closes its menu"] = function(t)
    local c, addon = boot()
    local b = button(c)
    b.click("right")
    addon.settings:set("ui.minimapButton", false)
    t.eq(b.menuItems, nil)
end

tests["minimap button: the route rows say what the route word says"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local said, has, stops = {}, false, 0
    k:Module({ name = "tripRoute", provides = {
        Lines = function() return has and { "Stops left: " .. stops } or nil end,
        Plan = function()
            said[#said + 1] = "new"
            if stops == 0 then return nil, "No stop known." end
            has = true
            return {}
        end,
        Skip = function()
            said[#said + 1] = "skip"
            stops = stops - 1
            if stops == 0 then has = false end
            return has and {} or nil
        end,
        Off = function()
            said[#said + 1] = "off"
            has = false
        end,
    } })
    ns.MinimapButton.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    local b = c.minimapButtons[1]
    t.ok(b ~= nil, "made")
    b.click("right")
    t.eq(row(b.menuItems, "window"), nil, "no route window here: no row for it")
    local T, said0 = ns.Nav.TripRoute, #c.printed
    b.choose("plan")
    t.eq(c.printed[said0 + 1], ns.id.title .. ": No stop known.", "why no route, in chat")
    stops = 2
    b.click("right")
    b.choose("plan")
    t.eq(said, { "new", "new" })
    t.eq(c.printed[said0 + 2], ns.id.title .. ": Stops left: 2")
    b.click("right")
    t.eq(row(b.menuItems, "plan").text, "Plan the route again")
    t.eq(row(b.menuItems, "none"), nil)
    b.choose("skip")
    t.eq(c.printed[said0 + 3], ns.id.title .. ": Stops left: 1")
    b.click("right")
    b.choose("clear")
    t.eq(c.printed[said0 + 4], ns.id.title .. ": " .. T.CLEARED)
    t.eq(said, { "new", "new", "skip", "off" })
    stops = 1
    b.click("right")
    b.choose("plan")
    b.click("right")
    b.choose("skip")
    t.eq(c.printed[said0 + 6], ns.id.title .. ": " .. T.DONE, "the last stop skipped: done")
    said = {}
    b.click("right")
    t.eq(row(b.menuItems, "skip"), nil, "cleared: nothing to skip")
    b.choose("none")
    b.click("right")
    b.choose("nonsense")
    t.eq(said, {}, "a row that is not offered does nothing")
end

tests["minimap button: a drag saves the angle and a reload puts it back"] = function(t)
    local c = boot()
    button(c).drag(90)
    local b = button(c)
    t.ok(near(b.x, 0) and near(b.y, 80), "placed at the top: " .. tostring(b.x) .. ", " .. tostring(b.y))
    local saved = c.saved(ns.id.accountDB)
    local place = type(saved.layout) == "table" and saved.layout.minimapButton or nil
    t.ok(type(place) == "table" and near(place.angle, 90), "the angle saved account-wide")
    local c2 = boot({ account = saved, char = c.saved(ns.id.charDB) })
    local b2 = button(c2)
    t.ok(b2 ~= nil and near(b2.x, 0) and near(b2.y, 80), "back at the top after a reload")
end

tests["minimap button: on a square minimap a corner drag goes to the corner"] = function(t)
    local c = boot({ square = true })
    button(c).drag(45)
    local b = button(c)
    t.ok(near(b.x, 80) and near(b.y, 80), "at the corner: " .. tostring(b.x) .. ", " .. tostring(b.y))
end

tests["minimap button: the setting off hides it at once, on shows it"] = function(t)
    local c, addon = boot()
    t.ok(addon.settings:set("ui.minimapButton", false), "the setting takes")
    t.eq(button(c).shown, false, "hidden")
    t.ok(addon.settings:set("ui.minimapButton", true), "back on")
    t.eq(button(c).shown, true, "shown")
    t.eq(#c.minimapButtons, 1, "still one button")
end

tests["minimap button: turned off as saved, none is made at login"] = function(t)
    local c = boot({ account = { settings = { ui = { minimapButton = false } } } })
    t.eq(button(c), nil, "not made")
end

tests["minimap button: a client that cannot make it costs one problem line and nothing else"] = function(t)
    local c, addon = boot({ before = function(x)
        x.minimapButton = function() return nil, "no frame" end
    end })
    t.eq(button(c), nil, "none")
    t.eq(mine(addon), 1, "one problem line")
    addon.settings:set("ui.minimapButton", false)
    addon.settings:set("ui.minimapButton", true)
    t.eq(mine(addon), 1, "still one")
end

return tests
