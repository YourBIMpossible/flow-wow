local _, ns = ...

-- SettingsPanel: the settings page on the shared panel (G52 part 2, F9),
-- and the word that shows the settings. UI/SettingsPage.lua says what
-- stands on the page; this file puts it on client.panel. It makes no frame
-- itself.
--
--   <slash> settings                 show or hide the page
--   <slash> settings topic <name>    show one topic ("topic gear", "topic
--                                    bags"); topic alone ends a search
--   <slash> settings <words>         search every topic for the words
--   <slash> settings <key> <value>   change one, as <slash> setting does,
--                                    and the open page shows the new value
-- A first word that is a setting's key is that setting; anything else is
-- searched for.
--
-- The page is the one with controls in the game's Options when the client
-- has it (UI/SettingsOptions.lua), and this text page otherwise. Both show
-- the same place: the topic chosen or the search made (SettingsPage.State).
--
-- The shared panel shows text only, so the page lists the topics, then the
-- rows of the chosen topic under its sections (or the search's results,
-- each with its topic), each with its value, who it is saved for and its
-- key, and a change is typed. A change goes the one way every change goes:
-- UI/SettingsSlash.lua, the kernel's settings and the store, so it is kept
-- across a reload like any other.
-- The player closes the page with its close button or Escape, when the
-- client gives the panel those; the word hides it on every client. A client
-- that cannot make the panel gets the same lines in the chat window.
--
-- An open page is drawn again when a row's saved value changes. A row
-- declared after login is on the page the next time it is drawn.
--
--   SettingsPanel.Lines(k) -> the page as lines of text
--   SettingsPanel.Declare(k, diag) -> api
--     api.open()    true while the page is on the screen
--     api.toggle()  shows or hides it; answers api.open()
--     api.show([topic [, query]])   shows the settings at that topic, or
--                   with that search, on the Options page or else here;
--                   -> "options", "panel" or "chat"; nil before login
--   ns.use(SettingsPanel.NAME) -> { Open, Toggle, Show }
-- Fake client only; not tested in game.
local SP = {}
ns.SettingsPanel = SP

SP.NAME = "settingsPanel"
SP.WORD = "settings"
SP.TOPIC_WORD = "topic"
SP.HELP = "show the settings; settings <words> searches them; settings topic <name> shows one topic; "
    .. "settings <key> <value> changes one"
SP.TITLE = "Settings" -- authored
SP.NONE = "There are no settings yet."
SP.NOT_NOW = "does not apply right now"
SP.NOT_READY = "the settings page is not ready until login."
SP.TOPICS = "Topics"
SP.SEARCH = "Search: "
SP.NO_TOPIC = "no topic is called "
SP.TEXT_INSTEAD = "; the text page is shown instead."
SP.MAX_RESULTS = 16
SP.MORE = " more: add a word to narrow the search."
SP.WIDTH = 460
SP.LINE_HEIGHT = 12
SP.SPARE_LINES = 6
SP.MIN_HEIGHT = 80
SP.DEFAULT_POINT = { "CENTER", "CENTER", 0, 40 }

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One row as a line. found: it is a search result, so its topic is said.
local function rowLine(e, isLoaded, found)
    local line = "  " .. tostring(e.label or e.key)
    if isLoaded then
        line = line .. ": " .. tostring(e.shown)
        if e.available == false then
            line = line .. " (" .. SP.NOT_NOW
            if e.because then line = line .. ": " .. e.because end
            line = line .. ")"
        end
    end
    line = line .. "  (" .. tostring(e.scope)
    if found then line = line .. "; " .. tostring(e.topicName) end
    return line .. ")  [" .. tostring(e.key) .. "]"
end

function SP.Lines(k)
    local P = ns.SettingsPage
    local id = k.id or ns.id
    local page = P.Page(k)
    local lines = { SP.TITLE }
    if page.count == 0 then
        lines[#lines + 1] = SP.NONE
        return lines
    end
    if not page.loaded then lines[#lines + 1] = P.NOT_LOADED end
    lines[#lines + 1] = ""
    lines[#lines + 1] = SP.TOPICS
    for i = 1, #page.topics do
        local topic = page.topics[i]
        lines[#lines + 1] = (topic.on and "> " or "  ") .. topic.name .. " (" .. topic.count .. ")"
    end
    lines[#lines + 1] = ""
    if page.mode == "search" then
        lines[#lines + 1] = SP.SEARCH .. page.query
        if #page.results == 0 then lines[#lines + 1] = page.none end
        local shown = math.min(#page.results, SP.MAX_RESULTS)
        for i = 1, shown do lines[#lines + 1] = rowLine(page.results[i], page.loaded, true) end
        if #page.results > shown then lines[#lines + 1] = "  " .. (#page.results - shown) .. SP.MORE end
    elseif page.topic then
        lines[#lines + 1] = tostring(page.topic.name)
        for s = 1, #page.topic.sections do
            local section = page.topic.sections[s]
            if section.name then lines[#lines + 1] = " " .. section.name end
            for i = 1, #section.rows do lines[#lines + 1] = rowLine(section.rows[i], page.loaded, false) end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "To see a topic, type " .. tostring(id.slash) .. " " .. SP.WORD .. " " .. SP.TOPIC_WORD
        .. " <name>. To search them all, type " .. tostring(id.slash) .. " " .. SP.WORD .. " <words>."
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

-- The most lines the page has with any one topic chosen, as things stand.
function SP.Tallest(k)
    local P = ns.SettingsPage
    local view = P.View(k)
    local most = 0
    for i = 1, #view.topics do
        local n = #view.topics[i].rows + #view.topics[i].sections
        if n > most then most = n end
    end
    if most < SP.MAX_RESULTS + 1 then most = SP.MAX_RESULTS + 1 end
    return most + #view.topics + 9
end

function SP.Declare(k, diag)
    local api = {}
    local panel, ctx
    local open = false
    local cancels, watched = {}, {}

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

    local refresh
    -- A row declared after login is followed too, from the next draw on.
    local function watch()
        if not ctx then return end
        for row in ctx.settings:each() do
            if not watched[row.key] then
                watched[row.key] = true
                local path = row.path or ("settings." .. row.key)
                cancels[#cancels + 1] = ctx.store:watch(row.scope, path, function() refresh() end)
            end
        end
    end
    refresh = function()
        if not panel or not open then return end
        watch()
        local out = lines()
        if out then panel.setLines(out) end
    end

    function api.open() return open end

    -- The text page: on the panel, or in the chat window on a client that
    -- cannot make one. -> "panel" or "chat"; nil before login.
    local function show()
        if not ctx then
            say(SP.NOT_READY)
            return nil
        end
        watch()
        local out = lines()
        if not out then return nil end
        if not panel then
            for i = 1, #out do
                if out[i] ~= "" then say(out[i]) end
            end
            return "chat"
        end
        open = true
        panel.setLines(out)
        panel.show(true)
        return "panel"
    end

    local function hide()
        open = false
        if panel then panel.show(false) end
    end

    function api.toggle()
        if open then hide() else show() end
        return open
    end

    -- The page with controls in the game's Options when the client has it
    -- (UI/SettingsOptions.lua); this text page otherwise.
    local function options()
        local name = ns.SettingsOptions and ns.SettingsOptions.NAME or "settingsOptions"
        local found = k.use and k.use(name) or nil
        if found and type(found.Open) == "function" then return found end
        return nil
    end

    -- Asks the Options page to open. -> true when it did; false, and true
    -- when it was refused for the game's combat lock (said in chat: the
    -- text page is what the player gets).
    local function openOptions()
        local page = options()
        if not page then return false, false end
        local opened, why = page.Open()
        if opened == true then return true, false end
        if type(why) == "string" then
            say(why .. SP.TEXT_INSTEAD)
            return false, true
        end
        return false, false
    end

    function api.show(topic, query)
        local P = ns.SettingsPage
        if topic ~= nil and not P.Goto(k, topic) then return nil end
        if query ~= nil then P.Find(k, query) end
        if openOptions() then return "options" end
        return show()
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[SP.WORD] = function(rest)
            rest = trim(rest)
            if rest == "" then
                local opened, locked = openOptions()
                if opened then return end
                -- Locked: the text page is shown, never hidden by the word.
                if locked then show() else api.toggle() end
                return
            end
            local first, tail = rest:match("^(%S+)%s*(.-)$")
            if first:lower() == SP.TOPIC_WORD then
                if tail == "" then
                    ns.SettingsPage.Find(k, "")
                    api.show()
                    return
                end
                local rows = {}
                for row in k.settings:each() do rows[#rows + 1] = row end
                local topic = ns.Settings.Topics.Pick(tail, rows)
                if not topic then
                    local names = {}
                    for _, one in ipairs(ns.Settings.Topics.LIST) do names[#names + 1] = one.name end
                    say(SP.NO_TOPIC .. tail .. ". " .. SP.TOPICS .. ": " .. table.concat(names, "; ") .. ".")
                    return
                end
                api.show(topic.id)
                return
            end
            if ns.SettingsSlash.Row(k, first) == nil then
                -- Not a key: the words are searched for in every topic.
                api.show(nil, rest)
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
        provides = { Open = api.open, Toggle = api.toggle, Show = api.show },
        start = function(c)
            ctx = c
            local id = k.id or ns.id
            panel = c.client.panel({ name = id.framePrefix .. "Settings",
                width = SP.WIDTH, height = SP.Height(SP.Tallest(k)), closable = true })
            if panel then
                panel.show(false)
                panel.place(SP.DEFAULT_POINT)
                if type(panel.onClose) == "function" then
                    panel.onClose(function() open = false end,
                        function(err) k.problems:add(SP.NAME, "close", err) end)
                end
            end
            watch()
        end,
        stop = function()
            for i = 1, #cancels do cancels[i]() end
            cancels, watched = {}, {}
            hide()
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.settingsPanel = SP.Declare(ns, ns.diag)
