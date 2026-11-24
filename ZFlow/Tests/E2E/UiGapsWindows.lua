local _, ns = ...
-- UI files that had no end-to-end test (CAPABILITY-RECONCILE 2026-11-24):
-- UI/Rows.lua, UI/MinimapPlace.lua, UI/DevPanel.lua, UI/Kit/Parts.lua and
-- UI/Kit/Theme.lua, on the whole add-on loaded on a fake client. Each test
-- starts where the player does: a click on the minimap button, a drag of
-- it, the panel word. Offline: the reads are the fake client's, not the
-- game's. Not tested in game.
local tests = {}

-- opts: account, char, size, square
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setMinimap({ size = opts.size or 140, square = opts.square })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function button(c) return type(c.minimapButtons) == "table" and c.minimapButtons[1] or nil end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

local function said(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, "\n")
end

local function part(w, text)
    for _, p in ipairs(type(w) == "table" and w.parts or {}) do
        if p.text == text then return p end
    end
    return nil
end

-- UI/Rows.lua -----------------------------------------------------------

local ROWS = {
    ["buttons.worldMap"] = "Button on the world map",
    ["buttons.merchant"] = "Button on the merchant window",
    ["buttons.profession"] = "Button on the profession window",
    ["buttons.bank"] = "Button on the bank window",
}

tests["ui gaps windows: the settings window has a row for each window button, on by default"] = function(t)
    local c, addon = boot()
    button(c).click("LeftButton")
    local w = c.kitWindows().settings
    t.ok(type(w) == "table" and w.shown == true, "a click on the minimap button opens the settings")
    for key, label in pairs(ROWS) do
        t.ok(part(w, label) ~= nil, "a row reads: " .. label)
        t.eq(addon.settings:get(key), true, key .. " is on at a new profile")
    end
end

tests["ui gaps windows: unticking a window button's row turns its setting off and saves it"] = function(t)
    local c, addon = boot()
    button(c).click("LeftButton")
    t.ok(c.kitClick("settings", "buttons.bank"), "the bank row's box takes a click")
    t.eq(addon.settings:get("buttons.bank"), false)
    t.eq(addon.settings:get("buttons.merchant"), true, "the others are left alone")
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(addon2.settings:get("buttons.bank"), false, "still off after a reload")
    t.ok(button(c2) ~= nil, "and the add-on loads as before")
end

-- UI/MinimapPlace.lua ---------------------------------------------------

tests["ui gaps windows: the minimap button starts bottom left on the rim, ten past the edge"] = function(t)
    local c = boot()
    local b = button(c)
    local x, y = ns.MinimapPlace.Offset(ns.MinimapPlace.DEFAULT, ns.MinimapPlace.Radius(140))
    t.ok(b and near(b.x, x) and near(b.y, y), "at the default angle")
    t.ok(b and b.x < 0 and b.y < 0, "left of and below the middle")
    t.ok(b and near(math.sqrt(b.x * b.x + b.y * b.y), 80), "70 to the rim and 10 past it")
end

tests["ui gaps windows: a bigger minimap puts the button farther out"] = function(t)
    local c = boot({ size = 200 })
    local b = button(c)
    t.ok(b and near(math.sqrt(b.x * b.x + b.y * b.y), 110), "100 to the rim and 10 past it")
end

tests["ui gaps windows: a drag past a full turn is saved as the same place on the rim"] = function(t)
    local c = boot()
    button(c).drag(450)
    local b = button(c)
    t.ok(near(b.x, 0) and near(b.y, 80), "at the top: " .. tostring(b.x) .. ", " .. tostring(b.y))
    local place = (c.saved(ns.id.accountDB).layout or {}).minimapButton
    t.ok(type(place) == "table" and near(place.angle, 90), "saved as 90, not 450")
    button(c).drag(-90)
    b = button(c)
    t.ok(near(b.x, 0) and near(b.y, -80), "a drag below the middle: at the bottom")
    place = (c.saved(ns.id.accountDB).layout or {}).minimapButton
    t.ok(type(place) == "table" and near(place.angle, 270), "saved as 270")
end

-- UI/DevPanel.lua -------------------------------------------------------

local function devPanel(c)
    local found
    for _, h in ipairs(c.panels) do
        if type(h.spec) == "table" and h.spec.name == ns.id.framePrefix .. "DevPanel" then found = h end
    end
    return found
end

tests["ui gaps windows: the panel word shows the dev panel, says so, and it stays after a reload"] = function(t)
    local c = boot()
    t.eq(devPanel(c) and devPanel(c).shown, false, "not shown to a player who did not ask")
    t.eq(said(c, "panel"), ns.id.title .. ": panel shown.")
    t.eq(devPanel(c).shown, true)
    local c2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(devPanel(c2) and devPanel(c2).shown, true, "shown again after a reload")
    t.eq(said(c2, "panel"), ns.id.title .. ": panel hidden.")
    t.eq(devPanel(c2).shown, false)
end

tests["ui gaps windows: panel reset says it is back; another word says the two there are"] = function(t)
    local c, addon = boot()
    local problems = #addon.problems:list()
    said(c, "panel")
    t.eq(said(c, "panel reset"), ns.id.title .. ": panel back to its first place.")
    t.eq(devPanel(c).shown, true, "a reset does not hide it")
    t.eq(said(c, "panel sideways"),
        ns.id.title .. ": " .. ns.id.slash .. " panel, or " .. ns.id.slash .. " panel reset.")
    t.eq(#addon.problems:list(), problems, "no new problem line")
end

-- UI/Kit/Parts.lua and UI/Kit/Theme.lua ---------------------------------

tests["ui gaps windows: the login probe saves one answer for each row of the kit's parts list"] = function(t)
    local c = boot()
    local probe = (c.saved(ns.id.accountDB).diag or {}).kitProbe
    t.ok(type(probe) == "table" and type(probe.rows) == "table", "saved at login")
    local rows = type(probe) == "table" and type(probe.rows) == "table" and probe.rows or {}
    for _, row in ipairs(ns.KitParts.rows) do
        t.ok(rows[row.id] ~= nil, "an answer saved for row " .. tostring(row.id))
        t.ok(ns.KitParts.ById(row.id) == row, "and the list finds that row by its id")
    end
    t.ok(#ns.KitParts.rows > 0, "the list is not empty")
end

tests["ui gaps windows: a kit window is drawn from the one theme, and its unseen art has a plain form"] = function(t)
    local c, addon = boot()
    button(c).click("LeftButton")
    t.eq(c.kitWindows().settings and c.kitWindows().settings.shown, true, "the settings window is a kit window")
    t.ok(addon.Kit.look == addon.KitTheme, "the kit hands out the theme file, not a copy")
    local look = addon.Kit.look
    for key in pairs(look.unproven or {}) do
        t.ok(look.art[key] ~= nil, "art not yet seen in game is still a named entry: " .. tostring(key))
    end
    for _, group in ipairs({ "size", "color", "font", "art" }) do
        t.ok(type(look[group]) == "table" and next(look[group]) ~= nil, "the theme has " .. group)
    end
end

return tests
