local _, ns = ...

-- SettingsOptions: the settings page with controls, in the game's
-- Options > AddOns (WoW/from-plexy/RESEARCH-settings-controls.md). What
-- stands on it and what a change does are UI/SettingsPage.lua's: every row
-- the kernel holds, and every change through SettingsPage.Set, so the same
-- checks, scopes and saved places apply as for /zflow setting. Nothing new
-- is stored. It makes no frame itself: the client's optionsPage does.
--
--   on / off rows     a check button
--   choice rows       a row of buttons, the one in use marked
--   number rows       minus and plus around the value, inside its limits
--   text rows         an edit box, set on Enter
--   place rows        shown as set or not set, never changed here
--   a row that cannot be set is greyed, with the reason beside it.
--
-- Changes are refused while the game is in combat lockdown, as legacy
-- Flow's page did on this client, with SettingsOptions.IN_COMBAT shown.
--
--   SettingsOptions.Rows(k) -> the rows the client's page draws
--   SettingsOptions.Declare(k) -> api
--     api.open() -> true when the game's Options was asked to open at the
--                   page; false on a client with no page (the text panel,
--                   UI/SettingsPanel.lua, is the fallback there)
--   ns.use(SettingsOptions.NAME) -> { Open = api.open }
-- Fake client only; not tested in game.
local O = {}
ns.SettingsOptions = O

O.NAME = "settingsOptions"
O.IN_COMBAT = "Settings can't change in combat."
O.SAVED = "Saved: "
O.NOT_LOADED = ns.SettingsPage and ns.SettingsPage.NOT_LOADED or "the saved settings are not loaded yet"

local DRAW = { toggle = "toggle", choice = "choice", number = "number", text = "text", place = "info" }

function O.Rows(k)
    local view = ns.SettingsPage.View(k)
    local rows = {}
    for _, group in ipairs(view.groups) do
        rows[#rows + 1] = { kind = "group", text = group.name }
        for _, e in ipairs(group.rows) do
            rows[#rows + 1] = {
                kind = DRAW[e.kind] or "info",
                key = e.key,
                label = e.label or e.key,
                value = e.value,
                shown = e.shown,
                choices = e.choices,
                min = e.min,
                max = e.max,
                settable = e.settable == true,
                why = e.why,
            }
        end
    end
    return rows, view
end

function O.Declare(k)
    local api = {}
    local page, ctx
    local cancels = {}

    local act
    local function draw(statusText)
        if not page or not ctx then return end
        local rows, view = O.Rows(k)
        page.draw(rows, act)
        if statusText then
            page.status(statusText)
        elseif not view.loaded then
            page.status(O.NOT_LOADED)
        end
    end
    act = function(key, value)
        local client = ctx and ctx.client
        if client and type(client.combatLockdown) == "function" and client.combatLockdown() == true then
            draw(O.IN_COMBAT)
            return false, O.IN_COMBAT
        end
        local ok, why = ns.SettingsPage.Set(k, key, value)
        if ok then
            draw(O.SAVED .. tostring(key))
        else
            draw(tostring(key) .. ": " .. tostring(why))
        end
        return ok, why
    end

    function api.open()
        if not page then return false end
        local ok = page.open() == true
        if ok then draw() end
        return ok
    end

    k:Module({
        name = O.NAME,
        needs = { "client", "store", "settings" },
        provides = { Open = api.open },
        start = function(c)
            ctx = c
            local id = k.id or ns.id
            if type(c.client.optionsPage) ~= "function" then return end
            page = c.client.optionsPage({ title = id.title, name = id.framePrefix .. "Options" })
            if not page then return end
            page.onShow(function() draw() end)
            -- A value changed elsewhere (/zflow setting) shows at once on an
            -- open page.
            for row in c.settings:each() do
                local path = row.path or ("settings." .. row.key)
                cancels[#cancels + 1] = c.store:watch(row.scope, path, function()
                    if page.shown() then draw() end
                end)
            end
        end,
        stop = function()
            for i = 1, #cancels do cancels[i]() end
            cancels = {}
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.settingsOptions = O.Declare(ns)
