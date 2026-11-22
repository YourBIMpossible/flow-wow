local _, ns = ...

-- SettingsPanel: the settings page on the shared panel (G52 part 2, F9).
-- UI/SettingsPage.lua says what stands on the page; this file puts it on
-- client.panel and adds the word that shows it. It makes no frame itself.
--
--   <slash> settings                 show or hide the page
--   <slash> settings <key> <value>   change one, as <slash> setting does,
--                                    and the open page shows the new value
--
-- The shared panel shows text only, so the page lists every row (its
-- group, label, value and key) and a change is typed. A change goes the
-- one way every change goes: UI/SettingsSlash.lua, the kernel's settings
-- and the store, so it is kept across a reload like any other.
-- The player closes the page with its close button or Escape, when the
-- client gives the panel those; the word hides it on every client. A client
-- that cannot make the panel gets the same lines in the chat window.
--
-- An open page is drawn again when a row's saved value changes. A row
-- declared after login is on the page the next time it is shown.
--
--   SettingsPanel.Lines(k) -> the page as lines of text
--   SettingsPanel.Declare(k, diag) -> api
--     api.open()    true while the page is on the screen
--     api.toggle()  shows or hides it; answers api.open()
-- Fake client only; not tested in game.
local SP = {}
ns.SettingsPanel = SP

SP.NAME = "settingsPanel"
SP.WORD = "settings"
SP.HELP = "show or hide the settings page; settings <key> <value> changes one"
SP.TITLE = "Settings" -- authored
SP.NONE = "There are no settings yet."
SP.NOT_NOW = "does not apply right now"
SP.NOT_READY = "the settings page is not ready until login."
SP.WIDTH = 460
SP.LINE_HEIGHT = 12
SP.SPARE_LINES = 6
SP.MIN_HEIGHT = 80
SP.DEFAULT_POINT = { "CENTER", "CENTER", 0, 40 }

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function SP.Lines(k)
    local P = ns.SettingsPage
    local id = k.id or ns.id
    local view = P.View(k)
    local lines = { SP.TITLE }
    if view.count == 0 then
        lines[#lines + 1] = SP.NONE
        return lines
    end
    if not view.loaded then lines[#lines + 1] = P.NOT_LOADED end
    for g = 1, #view.groups do
        local group = view.groups[g]
        lines[#lines + 1] = ""
        lines[#lines + 1] = tostring(group.name)
        for i = 1, #group.rows do
            local e = group.rows[i]
            local line = "  " .. tostring(e.label or e.key)
            if view.loaded then
                line = line .. ": " .. tostring(e.shown)
                if e.available == false then line = line .. " (" .. SP.NOT_NOW .. ")" end
            end
            lines[#lines + 1] = line .. "  [" .. tostring(e.key) .. "]"
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "To change one, type " .. tostring(id.slash) .. " setting <key> <value>."
    lines[#lines + 1] = "A yes-or-no setting takes on or off."
    return lines
end

-- How tall the panel is made for that many lines.
function SP.Height(count)
    local h = ((tonumber(count) or 0) + SP.SPARE_LINES) * SP.LINE_HEIGHT + 12
    if h < SP.MIN_HEIGHT then h = SP.MIN_HEIGHT end
    return h
end

function SP.Declare(k, diag)
    local api = {}
    local panel, ctx
    local open = false
    local cancels = {}

    local function say(line)
        local id = k.id or ns.id
        k.client.print(tostring(id.title) .. ": " .. line)
    end

    local function lines()
        local ok, out = pcall(SP.Lines, k)
        if ok then return out end
        k.problems:add(SP.NAME, "lines", out)
        return nil
    end

    local function refresh()
        if not panel or not open then return end
        local out = lines()
        if out then panel.setLines(out) end
    end

    function api.open() return open end

    local function show()
        if not ctx then
            say(SP.NOT_READY)
            return
        end
        local out = lines()
        if not out then return end
        if not panel then
            for i = 1, #out do
                if out[i] ~= "" then say(out[i]) end
            end
            return
        end
        open = true
        panel.setLines(out)
        panel.show(true)
    end

    local function hide()
        open = false
        if panel then panel.show(false) end
    end

    function api.toggle()
        if open then hide() else show() end
        return open
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[SP.WORD] = function(rest)
            rest = trim(rest)
            if rest == "" then
                -- The page with controls in the game's Options when the
                -- client has it (UI/SettingsOptions.lua); this text page
                -- otherwise.
                local options = k.use and k.use("settingsOptions") or nil
                if options and type(options.Open) == "function" and options.Open() == true then return end
                api.toggle()
                return
            end
            -- A change typed here goes the way the setting word goes.
            local out = ns.SettingsSlash.Run(k, rest)
            for i = 1, #out do say(out[i]) end
            refresh()
        end
        if type(diag.help) == "table" then diag.help[SP.WORD] = SP.HELP end
    end

    k:Module({
        name = SP.NAME,
        needs = { "client", "store", "settings" },
        provides = { Open = api.open, Toggle = api.toggle },
        start = function(c)
            ctx = c
            local id = k.id or ns.id
            local first = lines() or {}
            panel = c.client.panel({ name = id.framePrefix .. "Settings",
                width = SP.WIDTH, height = SP.Height(#first), closable = true })
            if panel then
                panel.show(false)
                panel.place(SP.DEFAULT_POINT)
                if type(panel.onClose) == "function" then
                    panel.onClose(function() open = false end,
                        function(err) k.problems:add(SP.NAME, "close", err) end)
                end
            end
            for row in c.settings:each() do
                local path = row.path or ("settings." .. row.key)
                cancels[#cancels + 1] = c.store:watch(row.scope, path, refresh)
            end
        end,
        stop = function()
            for i = 1, #cancels do cancels[i]() end
            cancels = {}
            hide()
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.settingsPanel = SP.Declare(ns, ns.diag)
