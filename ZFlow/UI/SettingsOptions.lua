local _, ns = ...

-- SettingsOptions: the settings with controls, in ONE window of the
-- add-on's own (lead sections 285 item 3, 291, 292 and 303). What stands in
-- it and what a change does are UI/SettingsPage.lua's: every row the kernel
-- holds, and every change through SettingsPage.Set, so the same checks,
-- scopes and saved places apply as for the setting word. Nothing new is
-- stored but where the player was (the last topic, SettingsPage.TOPIC_PATH)
-- and where the window stands (SettingsOptions.PLACE_PATH). It makes no
-- frame itself: UI/SettingsWindow.lua turns the rows into a tree of the
-- shared window kit and the client's settingsWindow draws it.
--
-- The window (the look spec, section 4.1):
--   the topics      down the left, the one shown marked
--   the search      at the top right; it searches every topic, and clearing
--                   it shows the last topic again
--   the pane        one topic's rows (its name first, a heading above each
--                   section only in a topic of more than SECTIONS_OVER
--                   rows), or the search's hits, each naming its topic
-- A row: its label, one short line of description (the whole of it is in
-- the tooltip) and its control. Who it is saved for is in the tooltip.
--
--   on / off rows     a check box
--   choice rows       the choices, the one in use marked
--   number rows       minus and plus around the value, inside its limits
--   text rows         an edit box, set on Enter
--   key rows          a bind button; with no key it reads Not Bound
--   place rows        shown as set or not set, never changed here
--   a row that cannot be set is greyed, with the reason. It is never left
--   out.
--
-- A result is changed by the same control and the same act as a row of a
-- topic: there is one path for a change. There is no Save button.
--
-- Changes are refused while the game is in combat lockdown, as legacy
-- Flow's page did on this client, with SettingsOptions.IN_COMBAT shown.
--
-- The add-on's entry in the game's Options > AddOns holds one line and one
-- button, "Open <title> settings", which opens the same window.
--
--   SettingsOptions.Rows(k) -> rows, page, layout
--     rows     what the pane holds, top to bottom
--     page     SettingsPage.Page(k)
--     layout   what stands beside the pane: title, topics ({ id, name,
--              count, on }), topic (the id shown; nil during a search),
--              back (the topic a cleared search goes back to), search
--              ({ label, value, clear }), count
--   SettingsOptions.Short(help) -> a description as one short line
--   SettingsOptions.Declare(k) -> api
--     api.open([to]) -> true when the window was drawn and shown; false on
--                   a client that cannot make it or when its draw failed
--                   (the text panel, UI/SettingsPanel.lua, is the fallback
--                   there); false and why (LOCKED, LOCK_UNKNOWN) when the
--                   game's combat lock is on or cannot be read: then
--                   nothing is opened at all.
--                   to = { topic = id } or { query = text } goes there first.
--   ns.use(SettingsOptions.NAME) -> { Open = api.open }
--
-- The client's window is asked for at login. A client with none answers nil
-- and is not asked again; an ask or a draw that raises is listed as a
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
O.NONE_HOW = "They are listed here once the add-on has loaded them."
O.NO_MATCH_HOW = "Clear the search box to see the topics again, or try another word."
-- What follows the add-on's title in the window's title: nothing.
O.WINDOW = ""
-- The longest description line a row shows; the whole is in its tooltip.
O.DESC_MAX = 56
-- A topic of more rows than this is headed by section.
O.SECTIONS_OVER = 10
-- The entry in the game's Options > AddOns: one line and one button.
O.ENTRY_LINE = "The game's Options has no setting rows for add-ons here, so the settings are in a window of their own. Nothing else changed."
-- The first thing that window says when it is the fallback (lead section
-- 410): why it is not the game's Options, and that nothing else changed.
O.FALLBACK = "The game's Options has no setting rows for add-ons here, so the settings are in this window. Nothing else changed."
O.ENTRY_OPEN = "open"
O.ENTRY_FAILED = "the settings window could not be shown"
-- Where the window's place is saved, for the account:
-- { point = { anchor, screen anchor, x, y } }.
O.PLACE_PATH = "layout.settingsWindow"
-- Why the window was not opened (lead section 247): nothing is opened while
-- the game's lock is on, and a lock that cannot be read counts as on.
O.LOCKED = "the game's Options can't be opened in combat"
O.LOCK_UNKNOWN = "the game won't say whether you are in combat, so its Options stay closed"

local DRAW = { toggle = "toggle", choice = "choice", number = "number", text = "text", place = "info" }

-- Row N57: a number row with both limits is kind "slider", any other
-- number row "number"; the window draws both as minus and plus around the
-- value. The page's two buttons stand under this topic.
O.ACTIONS_TOPIC = "general"
local function drawKind(e)
    if e.kind == "number" and type(e.min) == "number" and type(e.max) == "number" and e.max > e.min then
        return "slider"
    end
    return DRAW[e.kind] or "info"
end

-- The words of the button on the add-on's entry in the game's Options.
function O.OpenLabel(id)
    return "Open " .. tostring(id.title) .. " settings"
end

-- A description as one short line: its first line, cut at the end of a
-- word and ended with three dots when it is longer than O.DESC_MAX. nil
-- for no description.
function O.Short(help)
    if type(help) ~= "string" or help == "" then return nil end
    local first = help:match("^[^\r\n]*")
    if first == help and #help <= O.DESC_MAX then return help end
    local room = O.DESC_MAX - 3
    if #first <= room then return first .. "..." end
    local at = room
    while at > 0 and first:sub(at + 1, at + 1) ~= " " do at = at - 1 end
    if at < room / 2 then at = room end
    return first:sub(1, at) .. "..."
end

local function settingRow(e, found)
    -- Under a hit: its topic and section. Under any row: what it waits on.
    local under
    if found then
        under = tostring(e.topicName)
        if e.sectionName then under = under .. ", " .. tostring(e.sectionName) end
    end
    if e.because then
        if under then under = under .. " - " .. e.because else under = e.because end
    end
    -- The tooltip: the whole description, why it cannot be set, who it is
    -- saved for.
    local tip = {}
    if e.help then tip[#tip + 1] = e.help end
    if e.why then tip[#tip + 1] = e.why end
    if e.because then tip[#tip + 1] = e.because end
    tip[#tip + 1] = O.SAVED_FOR .. tostring(e.savedFor)
    local row = {
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
        desc = O.Short(e.help),
        tip = tip,
        settable = e.settable == true,
        why = e.why,
        scope = e.scope,
        topic = e.topic,
        topicName = e.topicName,
        under = under,
    }
    if found then row.jump, row.jumpText = e.topic, O.JUMP end
    return row
end

-- A row with a window of its own gets that button in place of Open topic.
local function withOpener(row, e)
    if e.opens then row.jump, row.jumpText, row.jumpKind = e.key, e.opens, "open" end
    return row
end

-- keys (optional): UI/SettingsKeys.lua's rows, shown on their topic and
-- when a search finds them (N57).
function O.Rows(k, keys)
    local page = ns.SettingsPage.Page(k)
    local id = k.id or ns.id
    local rows = {}
    local layout = {
        title = tostring(id.title) .. O.WINDOW,
        topics = {},
        back = page.back,
        search = { label = O.SEARCH, value = page.query or "", clear = O.CLEAR },
        count = page.count,
    }
    for i = 1, #page.topics do
        local topic = page.topics[i]
        layout.topics[i] = { id = topic.id, name = topic.name, count = topic.count, on = topic.on }
        if topic.on then layout.topic = topic.id end
    end
    local keyRows
    if type(keys) == "table" then
        local SK = ns.SettingsKeys
        local onTopic = page.mode ~= "search" and page.topic ~= nil and page.topic.id == SK.GROUP
        local found = page.mode == "search" and keys.matches(page.query)
        if onTopic or found then
            keyRows = keys.rows()
            -- A key row names its topic as a setting row does.
            local topic = ns.Settings.Topics.Find(SK.GROUP)
            for _, r in ipairs(keyRows) do
                if topic and r.topicName == nil then r.topicName = topic.name end
            end
        end
    end
    if page.mode == "search" then
        local n = #page.results
        if keyRows then n = n + #ns.SettingsKeys.SLOTS end
        if n == 0 then
            rows[#rows + 1] = { kind = "note", text = page.none, how = O.NO_MATCH_HOW }
        else
            rows[#rows + 1] = { kind = "group", text = n .. O.FOUND .. '"' .. page.query .. '"' }
            for _, e in ipairs(page.results) do rows[#rows + 1] = withOpener(settingRow(e, true), e) end
        end
    elseif page.topic then
        -- A small topic is one plain list; a large one is headed by section.
        local n = #page.topic.rows
        if keyRows then n = n + #ns.SettingsKeys.SLOTS end
        local headed = n > O.SECTIONS_OVER
        rows[#rows + 1] = { kind = "group", text = page.topic.name }
        for _, section in ipairs(page.topic.sections) do
            if section.name and headed then rows[#rows + 1] = { kind = "section", text = section.name } end
            for _, e in ipairs(section.rows) do rows[#rows + 1] = withOpener(settingRow(e, false), e) end
        end
        -- The page's own buttons (SettingsPage.Actions), under one topic only.
        if page.topic.id == O.ACTIONS_TOPIC and type(ns.SettingsPage.Actions) == "function" then
            rows[#rows + 1] = { kind = "actions", actions = ns.SettingsPage.Actions(k) }
        end
        if keyRows and headed then rows[#rows + 1] = { kind = "section", text = ns.SettingsKeys.SECTION } end
    else
        rows[#rows + 1] = { kind = "note", text = O.NONE, how = O.NONE_HOW }
    end
    if keyRows then
        for _, r in ipairs(keyRows) do rows[#rows + 1] = r end
    end
    return rows, page, layout
end

local function trim(text)
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

function O.Declare(k)
    local api = {}
    local page, entry, ctx, none
    -- Lead section 410: the settings as the game's own rows, when the
    -- client has them; this window is then only for what has no such row.
    local native, toldFallback
    local cancels, watched = {}, {}
    -- status: the last thing said about a change (for a reader and a test);
    -- notice: what of it the window shows above the rows (a plain "Saved"
    -- is not shown). typed: the search box's own text, as it was typed.
    local status, notice, typed
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
    -- -> true when the window was drawn. A draw that raises is listed as a
    -- problem; nothing goes up to whoever asked.
    draw = function(statusText, quiet)
        if not page or not ctx then return false end
        watch()
        local rows, view, layout = O.Rows(k, keys)
        if statusText then
            status, notice = statusText, statusText
            if quiet then notice = "" end
        elseif not native and not toldFallback and status == nil and view.loaded then
            toldFallback = true
            status, notice = O.FALLBACK, O.FALLBACK
        elseif not view.loaded then
            status, notice = O.NOT_LOADED, O.NOT_LOADED
        end
        -- The box keeps what was typed (a space at the end too) while the
        -- search is still the one it made.
        if typed ~= nil and trim(typed) ~= layout.search.value then typed = nil end
        layout.status, layout.notice, layout.typed = status, notice, typed
        local ok, done, why = pcall(page.draw, rows, act, nav, layout)
        if not ok then
            k.problems:add(O.NAME, "draw", done)
            return false
        end
        if done ~= true then
            if why ~= nil then k.problems:add(O.NAME, "draw", why) end
            return false
        end
        return true
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
            draw(O.SAVED .. tostring(key), true)
        else
            draw(tostring(key) .. ": " .. tostring(why))
        end
        return ok, why
    end
    -- The player chose a topic or searched. A topic chosen is saved as the
    -- last one (SettingsPage.Goto); a search is not.
    nav = function(kind, value)
        local P = ns.SettingsPage
        if kind == "topic" then
            if not P.Goto(k, value) then return false end
            typed = nil
        elseif kind == "search" then
            P.Find(k, value)
            typed = nil
            if type(value) == "string" then typed = value end
        elseif kind == "open" then
            -- The button of a row with a window of its own.
            return P.Open(k, value)
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

    -- The window's place, kept for the account when the player moves it.
    local function moved(point)
        if type(point) ~= "table" or not ctx then return end
        local ok, why = ctx.store:set("account", O.PLACE_PATH,
            { point = { point[1], point[2], point[3], point[4] } })
        if not ok then k.problems:add(O.NAME, "place", why) end
    end

    -- The client's window, asked for once it can be; nil when there is none
    -- (yet).
    local function ensure()
        if page or none or not ctx then return page end
        if type(ctx.client.settingsWindow) ~= "function" or type(ns.SettingsWindow) ~= "table" then
            none = true
            return nil
        end
        local id = k.id or ns.id
        local W = ns.SettingsWindow
        local point
        local saved = ctx.store:get("account", O.PLACE_PATH)
        if type(saved) == "table" and type(ns.Kit) == "table" then point = ns.Kit.Place(saved, nil) end
        local ok, made = pcall(ctx.client.settingsWindow, {
            id = W.ID, title = tostring(id.title) .. O.WINDOW, name = id.framePrefix .. "SettingsWindow",
            build = W.Tree, point = point, onMoved = moved,
            failed = function(err) k.problems:add(O.NAME, "window", err) end,
        })
        if not ok then
            k.problems:add(O.NAME, "page", made)
            return nil
        end
        if not made then
            none = true
            return nil
        end
        page = made
        return page
    end

    local function ownOpen(to)
        if type(to) == "table" then
            if to.topic ~= nil then ns.SettingsPage.Goto(k, to.topic) end
            if to.query ~= nil then ns.SettingsPage.Find(k, to.query) end
        end
        if none or not ctx then return false end
        -- Nothing is made or opened unless the lock is a plain false: true
        -- is a fight, anything else is not known.
        local lock
        if type(ctx.client.combatLockdown) == "function" then lock = ctx.client.combatLockdown() end
        if lock ~= false then
            if lock == true then return false, O.LOCKED end
            return false, O.LOCK_UNKNOWN
        end
        if not ensure() then return false end
        -- Drawn first: an empty window is never left on the screen.
        if not draw() then
            pcall(page.hide)
            return false
        end
        local ok, opened = pcall(page.open)
        if not ok then
            k.problems:add(O.NAME, "open", opened)
            return false
        end
        if opened ~= true then return false end
        return true
    end

    -- Lead section 410: the minimap button and the slash word come here.
    -- With the game's own rows the game's Options opens at the add-on's
    -- entry (at a topic's, when one was asked for); a search, and a client
    -- without those rows, get the window above.
    function api.open(to)
        if not native or not ctx or (type(to) == "table" and to.query ~= nil) then return ownOpen(to) end
        -- A search already on (the slash word's "settings <words>") is
        -- shown in the window too: the game's Options has its own search.
        if type(to) ~= "table" and ns.SettingsPage.State(k).query ~= nil then return ownOpen(to) end
        local lock
        if type(ctx.client.combatLockdown) == "function" then lock = ctx.client.combatLockdown() end
        if lock ~= false then
            if lock == true then return false, O.LOCKED end
            return false, O.LOCK_UNKNOWN
        end
        local topic
        if type(to) == "table" and to.topic ~= nil then
            topic = to.topic
            ns.SettingsPage.Goto(k, topic)
        end
        local ok, opened = pcall(native.open, topic)
        if not ok then k.problems:add(O.NAME, "open", opened) end
        if ok and opened == true then return true end
        return ownOpen(to)
    end
    -- A row of the game's Options was changed: the one checked set, and
    -- a refusal said in chat (the game's row has no line for it).
    local function nativeSet(key, value)
        local ok, why = act(key, value)
        if not ok and ctx and type(ctx.client.print) == "function" then
            local id = k.id or ns.id
            local row = type(key) == "string" and k.settings:row(key) or nil
            local name = row and row.label or key
            pcall(ctx.client.print, tostring(id.title) .. ": " .. tostring(name) .. " - " .. tostring(why))
        end
        return ok, why
    end
    local function nativeAct(key)
        local ok, said = nav("action", key)
        if said ~= nil and ctx and type(ctx.client.print) == "function" then
            local id = k.id or ns.id
            pcall(ctx.client.print, tostring(id.title) .. ": " .. tostring(said))
        end
        return ok, said
    end

    -- The add-on's entry in the game's Options > AddOns: one line and the
    -- button that opens the window. No setting stands there.
    local function entryRows()
        local id = k.id or ns.id
        return {
            { kind = "note", text = O.ENTRY_LINE },
            { kind = "actions", actions = { { key = O.ENTRY_OPEN, label = O.OpenLabel(id) } } },
        }
    end
    local function entryNav(kind, value)
        if kind ~= "action" or value ~= O.ENTRY_OPEN or not entry then return false end
        local opened, why = api.open()
        if opened == true then
            entry.status("")
            return true
        end
        entry.status(why or O.ENTRY_FAILED)
        return false, why
    end
    local function drawEntry()
        if not entry then return end
        local ok, err = pcall(entry.draw, entryRows(), function() return false end, entryNav)
        if not ok then k.problems:add(O.NAME, "entry", err) end
    end
    local function ensureEntry()
        if entry or type(ctx.client.optionsPage) ~= "function" then return end
        local id = k.id or ns.id
        local ok, made = pcall(ctx.client.optionsPage,
            { title = id.title, name = id.framePrefix .. "Options", entry = true })
        if not ok then
            k.problems:add(O.NAME, "entry", made)
            return
        end
        if type(made) ~= "table" then return end
        entry = made
        if type(entry.onShow) == "function" then entry.onShow(drawEntry) end
        drawEntry()
    end

    k:Module({
        name = O.NAME,
        needs = { "client", "store", "settings" },
        provides = { Open = api.open },
        start = function(c)
            ctx = c
            if keys then keys.attach(c.client, function(text) draw(text) end) end
            if type(ns.SettingsNative) == "table" then
                native = ns.SettingsNative.Attach(k, c, {
                    set = nativeSet, act = nativeAct, own = ownOpen, keys = keys ~= nil,
                })
            end
            -- The one-button entry only where the game has no rows for us.
            if not native then ensureEntry() end
            -- A value changed elsewhere (the setting word) shows at once in
            -- an open window: draw() follows every row it has drawn.
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
