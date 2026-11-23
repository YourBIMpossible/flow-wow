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
--                   panel, UI/SettingsPanel.lua, is the fallback there);
--                   false and why (LOCKED, LOCK_UNKNOWN) when the game's
--                   combat lock is on or cannot be read: then the Options
--                   are not asked to open at all.
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
-- Why the game's Options were not asked to open (lead section 247): the
-- game's own windows are not opened while its lock is on, and a lock that
-- cannot be read counts as on.
O.LOCKED = "the game's Options can't be opened in combat"
O.LOCK_UNKNOWN = "the game won't say whether you are in combat, so its Options stay closed"

local DRAW = { toggle = "toggle", choice = "choice", number = "number", text = "text", place = "info" }

-- Row N57: a number row with both limits is drawn as a slider (the client
-- draws the stepper when it cannot make one); any other number row is the
-- stepper. The page's two buttons stand under this topic.
O.ACTIONS_TOPIC = "general"
local function drawKind(e)
    if e.kind == "number" and type(e.min) == "number" and type(e.max) == "number" and e.max > e.min then
        return "slider"
    end
    return DRAW[e.kind] or "info"
end

local function settingRow(e, found)
    local under = O.SAVED_FOR .. tostring(e.savedFor)
    if found then
        under = under .. " - " .. tostring(e.topicName)
        if e.sectionName then under = under .. ", " .. tostring(e.sectionName) end
    end
    if e.because then under = under .. " - " .. e.because end
    return {
        kind = drawKind(e),
        key = e.key,
        label = e.label or e.key,
        value = e.value,
        shown = e.shown,
        choices = e.choices,
        min = e.min,
        max = e.max,
        step = e.step,
        help = e.help,
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

-- keys (optional): UI/SettingsKeys.lua's rows, shown on their topic and
-- when a search finds them (N57).
function O.Rows(k, keys)
    local page = ns.SettingsPage.Page(k)
    local rows = {
        { kind = "search", label = O.SEARCH, value = page.query or "", clear = O.CLEAR },
        { kind = "topics", topics = page.topics },
    }
    local keyRows
    if type(keys) == "table" then
        local SK = ns.SettingsKeys
        local onTopic = page.mode ~= "search" and page.topic ~= nil and page.topic.id == SK.GROUP
        local found = page.mode == "search" and keys.matches(page.query)
        if onTopic or found then keyRows = keys.rows() end
    end
    if page.mode == "search" then
        local n = #page.results
        if keyRows then n = n + #ns.SettingsKeys.SLOTS end
        if n == 0 then
            rows[#rows + 1] = { kind = "note", text = page.none }
        else
            rows[#rows + 1] = { kind = "group", text = n .. O.FOUND .. '"' .. page.query .. '"' }
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
    -- The page's own buttons (SettingsPage.Actions), under one topic only.
    if page.mode == "topic" and page.topic and page.topic.id == O.ACTIONS_TOPIC
        and type(ns.SettingsPage.Actions) == "function" then
        rows[#rows + 1] = { kind = "actions", actions = ns.SettingsPage.Actions(k) }
    end
    if keyRows then
        rows[#rows + 1] = { kind = "section", text = ns.SettingsKeys.SECTION }
        for _, r in ipairs(keyRows) do rows[#rows + 1] = r end
    end
    return rows, page
end

function O.Declare(k)
    local api = {}
    local page, ctx, none
    local cancels, watched = {}, {}
    -- N57: the rotation key's rows; the text page reads them too.
    local keys
    if ns.SettingsKeys then
        keys = ns.SettingsKeys.New(k)
        k.keysPage = keys
    end

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
        local rows, view = O.Rows(k, keys)
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
        -- A number a control sent is put on its row's steps first.
        local row
        if type(key) == "string" then row = k.settings:row(key) end
        if row then value = ns.SettingsPage.Snap(row, value) end
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

    -- A press on one of the page's own buttons (row N57). It goes the way
    -- a change goes: refused in combat lockdown, done by SettingsPage.Act
    -- through the one checked set, and the page is drawn again with what it
    -- said. -> true when the button was one of the page's and ran.
    local plainNav = nav
    nav = function(kind, value)
        if kind ~= "action" then return plainNav(kind, value) end
        -- A key row's button (UI/SettingsKeys.lua): its own lock check, it
        -- says what it did and redraws.
        if type(value) == "string" and value:sub(1, 5) == "keys." then
            if not keys then return false end
            return keys.press(value)
        end
        local client = ctx and ctx.client
        if client and type(client.combatLockdown) == "function" and client.combatLockdown() == true then
            draw(O.IN_COMBAT)
            return false, O.IN_COMBAT
        end
        local n, said = ns.SettingsPage.Act(k, value)
        if n == nil then return false end
        draw(tostring(said))
        return true, said
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
        if type(to) == "table" then
            if to.topic ~= nil then ns.SettingsPage.Goto(k, to.topic) end
            if to.query ~= nil then ns.SettingsPage.Find(k, to.query) end
        end
        if none or not ctx then return false end
        -- Nothing of the game's is made or opened unless the lock is a
        -- plain false: true is a fight, anything else is not known.
        local lock
        if type(ctx.client.combatLockdown) == "function" then lock = ctx.client.combatLockdown() end
        if lock ~= false then
            if lock == true then return false, O.LOCKED end
            return false, O.LOCK_UNKNOWN
        end
        if not ensure() then return false end
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
            if keys then keys.attach(c.client, function(text) draw(text) end) end
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
