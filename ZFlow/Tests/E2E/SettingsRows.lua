local _, ns = ...
-- Lead section 187. Every setting a feature reads must be a kernel row in
-- the loaded add-on: with no row the settings page and the set command
-- refuse the key and the feature cannot be switched. Eleven features had
-- left their row "the lead's to add" and it never was (Settings/Rows.lua).
local tests = {}

-- The feedback (row N73) is paused by lead section 284 and declares no row
-- while paused (Tests/E2E/FeedbackOff.lua); here it is on through the fake
-- client internal switch, so its row is checked like every other.
local function boot()
    local c = ns.make.fakeClient({ internal = { feedback = true } })
    c.setSaved(ns.id.accountDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    return addon
end

-- Named by a file of plain helpers that nothing reads yet: no feature asks
-- for the setting, so a switch would do nothing and none is shown. The day
-- a feature reads one, it declares the row and the name leaves this list
-- (the last test fails until it does).
-- (Section 187 section 7: nav.mapFlights and nav.taxiMark left it; their
-- modules now read them.)
local UNREAD = {
}

-- Every string held in a field named SETTING (or ending _SETTING) anywhere
-- in the add-on's tables, three levels down.
local function settingNames(addon)
    local found, seen = {}, {}
    local function walk(tbl, depth, path)
        if seen[tbl] or depth > 3 then return end
        seen[tbl] = true
        for key, v in pairs(tbl) do
            if type(key) == "string" then
                if type(v) == "string" and (key == "SETTING" or key:sub(-8) == "_SETTING") then
                    found[v] = path .. "." .. key
                elseif type(v) == "table" then
                    walk(v, depth + 1, path .. "." .. key)
                end
            end
        end
    end
    walk(addon, 0, "ns")
    return found
end

tests["every setting a feature names is a row the player can switch"] = function(t)
    local addon = boot()
    local names = settingNames(addon)
    local count, missing = 0, {}
    for key, where in pairs(names) do
        count = count + 1
        if not UNREAD[key] and addon.settings:row(key) == nil then missing[#missing + 1] = key .. " (" .. where .. ")" end
    end
    table.sort(missing)
    t.ok(count >= 20, "the walk found the features' settings: " .. count)
    t.eq(table.concat(missing, ", "), "", "settings with no row")
end

tests["the rows the features left to the lead can be set and read back"] = function(t)
    local addon = boot()
    for _, row in ipairs(addon.Settings.Rows.ROWS) do
        t.ok(addon.settings:row(row.key) ~= nil, row.key .. " is a row")
        t.eq(addon.settings:get(row.key), row.default, row.key .. " starts at its default")
        local to = row.default
        if row.type == "bool" then to = not row.default elseif row.type == "number" then to = 0.5 end
        local ok, why = addon.settings:set(row.key, to)
        t.ok(ok, row.key .. " can be set: " .. tostring(why))
        t.eq(addon.settings:get(row.key), to, row.key .. " reads back")
    end
end

tests["the window buttons' settings are rows; the world map one starts on, the merchant one off"] = function(t)
    local addon = boot()
    for key, start in pairs({ ["buttons.worldMap"] = true, ["buttons.merchant"] = false }) do
        t.ok(addon.settings:row(key) ~= nil, key .. " is a row")
        t.eq(addon.settings:get(key), start, key .. " starts " .. (start and "on" or "off"))
    end
end

tests["a setting no feature reads yet has no switch"] = function(t)
    local addon = boot()
    local names = settingNames(addon)
    for key in pairs(UNREAD) do
        t.ok(names[key] ~= nil, key .. " is still named by its file")
        t.eq(addon.settings:row(key), nil, key .. " has no row until a feature reads it")
    end
    -- With the list empty, the check is that nothing is left waiting: every
    -- named setting has its row.
    if next(UNREAD) == nil then
        for key in pairs(names) do t.ok(addon.settings:row(key) ~= nil, key .. " has a row") end
    end
end

return tests
