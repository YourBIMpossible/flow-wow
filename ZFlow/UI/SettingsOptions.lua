local _, ns = ...

-- SettingsOptions: the settings page with controls, in the game's
-- Options > AddOns (WoW/from-plexy/RESEARCH-settings-controls.md). What
-- stands on it and what a change does are UI/SettingsPage.lua's: every row
-- the kernel holds, and every change through SettingsPage.Set, so the same
-- checks, scopes and saved places apply as for /zflow setting. Nothing new
-- is stored. It makes no frame itself: the client's optionsPage does.
--
-- The page, top to bottom (lead sections 238 and 239):
--   a search box        Enter searches every topic; Clear ends the search
--   the topics          one button each, the one shown marked; choosing a
--                       topic shows that topic's settings only
--   the chosen topic    its name, then its settings, a small heading above
--                       each section; or the search results, each with its
--                       topic and a button that opens that topic
-- Under each setting stands who it is saved for (account or this
-- character) and, in results, its topic.
--
--   on / off rows     a check button
--   choice rows       a row of buttons, the one in use marked
--   number rows       minus and plus around the value, inside its limits
--   text rows         an edit box, set on Enter
--   place rows        shown as set or not set, never changed here
--   a row that cannot be set is greyed, with the reason beside it and what
--   it depends on under it. It is never left out.
--
-- A result is changed by the same control and the same act as a row of a
-- topic: there is one path for a change.
--
-- Changes are refused while the game is in combat lockdown, as legacy
-- Flow's page did on this client, with SettingsOptions.IN_COMBAT shown.
--
--   SettingsOptions.Rows(k) -> the rows the client's page draws, and the page
--   SettingsOptions.Declare(k) -> api
--     api.open([to]) -> true when the game's Options was asked to open at
--                   the page; false on a client with no page (the text
--                   panel, UI/SettingsPanel.lua, is the fallback there).
--                   to = { topic = id } or { query = text } goes there first.
--   ns.use(SettingsOptions.NAME) -> { Open = api.open }
--
-- The client's page is asked for at login. A client with no Options route
-- answers nil and is not asked again; an ask that raises is listed as a
-- problem and tried again at the next open.
-- Fake client only; not tested in game.
local O = {}
ns.SettingsOptions = O

O.NAME = "settingsOptions"
O.IN_COMBAT = "Settings can't change in combat."
O.SAVED = "Saved: "
O.NOT_LOADED = ns.SettingsPage and ns.SettingsPage.NOT_LOADED or "the saved settings are not loaded yet"
O.SEARCH = "Search"
O.CLEAR = "Clear"
O.JUMP = "Open topic"
O.SAVED_FOR = "Saved for "
O.FOUND = " found for "
O.NONE = "There are no settings yet."

local DRAW = { toggle = "toggle", choice = "choice", number = "number", text = "text", place = "info" }

local function settingRow(e, found)
    local under = O.SAVED_FOR .. tostring(e.savedFor)
    if found then
        under = under .. " - " .. tostring(e.topicName)
        if e.sectionName then under = under .. ", " .. tostring(e.sectionName) end
    end
    if e.because then under = under .. " - " .. e.because end
    return {
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
        scope = e.scope,
        topic = e.topic,
        topicName = e.topicName,
        under = under,
        jump = found and e.topic or nil,
        jumpText = found and O.JUMP or nil,
    }
end

function O.Rows(k)
    local page = ns.SettingsPage.Page(k)
    local rows = {
        { kind = "search", label = O.SEARCH, value = page.query or "", clear = O.CLEAR },
        { kind = "topics", topics = page.topics },
    }
    if page.mode == "search" then
        if #page.results == 0 then
            rows[#rows + 1] = { kind = "note", text = page.none }
        else
            rows[#rows + 1] = { kind = "group", text = #page.results .. O.FOUND .. '"' .. page.query .. '"' }
            for _, e in ipairs(page.results) do rows[#rows + 1] = settingRow(e, true) end
        end
    elseif page.topic then
        rows[#rows + 1] = { kind = "group", text = page.topic.name }
        for _, section in ipairs(page.topic.sections) do
            if section.name then rows[#rows + 1] = { kind = "section", text = section.name } end
            for _, e in ipairs(section.rows) do rows[#rows + 1] = settingRow(e, false) end
        end
    else
        rows[#rows + 1] = { kind = "note", text = O.NONE }
    end
    return rows, page
end

function O.Declare(k)
    local api = {}
    local page, ctx, none
    local cancels, watched = {}, {}

    local act, nav, draw
    -- A row declared after login is followed too, from the next draw on.
    local function watch()
        for row in ctx.settings:each() do
            if not watched[row.key] then
                watched[row.key] = true
                local path = row.path or ("settings." .. row.key)
                cancels[#cancels + 1] = ctx.store:watch(row.scope, path, function()
                    if page and page.shown() then draw() end
                end)
            end
        end
    end
    draw = function(statusText)
        if not page or not ctx then return end
        watch()
        local rows, view = O.Rows(k)
        page.draw(rows, act, nav)
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
    -- The player chose a topic or searched. Nothing is saved by either.
    nav = function(kind, value)
        local P = ns.SettingsPage
        if kind == "topic" then
            if not P.Goto(k, value) then return false end
        elseif kind == "search" then
            P.Find(k, value)
        else
            return false
        end
        draw("")
        return true
    end

    -- The client's page, asked for once it can be; nil when there is none
    -- (yet).
    local function ensure()
        if page or none or not ctx then return page end
        if type(ctx.client.optionsPage) ~= "function" then
            none = true
            return nil
        end
        local id = k.id or ns.id
        local ok, made = pcall(ctx.client.optionsPage, { title = id.title, name = id.framePrefix .. "Options" })
        if not ok then
            k.problems:add(O.NAME, "page", made)
            return nil
        end
        if not made then
            none = true
            return nil
        end
        page = made
        page.onShow(function() draw() end)
        return page
    end

    function api.open(to)
        if not ensure() then return false end
        if type(to) == "table" then
            if to.topic ~= nil then ns.SettingsPage.Goto(k, to.topic) end
            if to.query ~= nil then ns.SettingsPage.Find(k, to.query) end
        end
        local ok, opened = pcall(page.open)
        if not ok then
            k.problems:add(O.NAME, "open", opened)
            return false
        end
        if opened ~= true then return false end
        draw()
        return true
    end

    k:Module({
        name = O.NAME,
        needs = { "client", "store", "settings" },
        provides = { Open = api.open },
        start = function(c)
            ctx = c
            -- A value changed elsewhere (/zflow setting) shows at once on an
            -- open page: draw() follows every row it has drawn.
            if ensure() then watch() end
        end,
        stop = function()
            for i = 1, #cancels do cancels[i]() end
            cancels, watched = {}, {}
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.settingsOptions = O.Declare(ns)
