local _, ns = ...

-- SettingsWindow: the settings as ONE window of the shared kit (lead
-- sections 285 item 3, 291, 292 and 303): the topics down the left, the
-- chosen topic's rows (or a search's hits) in one scroll at the right.
-- Kit parts only: no frame, no template, no colour and no font is named
-- here (UI/Kit.lua and UI/Kit/Theme.lua hold those).
--
-- LOOK ONLY, and no settings of its own: what stands in the window is what
-- UI/SettingsOptions.lua's Rows hands over, and a control only calls the
-- `act` and `nav` it was given (the one path every change takes). There is
-- no Save button: a change applies at once.
--
--   SettingsWindow.Tree(rows, act, nav, layout) -> tree | nil, reason
--     rows, layout   SettingsOptions.Rows(k)'s first and third answers
--     act(key, value)    a control was changed
--     nav(kind, value)   "topic" (id), "search" (text), "action" (a
--                        button's key), "open" (a row's own window)
--     The tree is Kit.Window's: client.kitWindow draws it.
--
-- The window, top to bottom:
--   header      "N topics" (during a search: how many were found), and the
--               search box at the right; every letter typed searches
--   topic list  one line a topic, the one shown marked. During a search the
--               mark stays on the topic the window goes back to.
--   the pane    the topic's name as the first heading, then its rows; a
--               search's hits stand under a heading for each topic. Nothing
--               found: a line saying what was searched and how to clear it.
-- A row: its label, one short line of description, its control in the
-- right-hand column. Who it is saved for is in the row's tooltip. A row
-- that cannot be set is greyed, with the reason.
-- Fake client only; not tested in game.
local W = {}
ns.SettingsWindow = W

W.ID = "settings"
W.WIDTH, W.HEIGHT = 760, 520
-- The names of the two parts a test (or a caller) finds by key. No setting
-- key starts with "#".
W.HEADER = "#header"
W.TOPICS = "#topics"
W.ONE_TOPIC = "1 topic"
W.MANY_TOPICS = " topics"

local function isText(v) return type(v) == "string" and v ~= "" end

local function tooltipOf(r)
    if type(r.tip) ~= "table" or #r.tip == 0 then return nil end
    local lines = {}
    for i = 1, #r.tip do lines[i] = tostring(r.tip[i]) end
    return table.concat(lines, "\n")
end

-- The control of a setting row, or nil for a row that only shows.
local function controlOf(r, act)
    if r.kind == "toggle" then
        return { kind = "checkbox", key = r.key, checked = r.value == true,
            onToggle = function(on) act(r.key, on == true) end }
    end
    if r.kind == "choice" and type(r.choices) == "table" and #r.choices > 0 then
        local items, selected = {}, nil
        for i = 1, #r.choices do
            items[i] = tostring(r.choices[i])
            if r.choices[i] == r.value then selected = i end
        end
        for i = 1, #items do
            if items[i] == "" then return nil end
        end
        return { kind = "choice", key = r.key, items = items, selected = selected,
            onSelect = function(i) act(r.key, r.choices[i]) end }
    end
    if (r.kind == "number" or r.kind == "slider") and type(r.value) == "number" then
        local step, low, high
        if type(r.step) == "number" and r.step > 0 then step = r.step end
        if type(r.min) == "number" then low = r.min end
        if type(r.max) == "number" then high = r.max end
        if low ~= nil and high ~= nil and low > high then low, high = nil, nil end
        return { kind = "number", key = r.key, value = r.value, min = low, max = high, step = step,
            onChange = function(value) act(r.key, value) end }
    end
    if r.kind == "text" then
        local text = ""
        if type(r.value) == "string" then text = r.value end
        return { kind = "text", key = r.key, text = text, onText = function(typed) act(r.key, typed) end }
    end
    return nil
end

-- A row's parts: the row itself, then a button for each thing it does
-- besides its control.
local function addRow(out, r, act, nav)
    local label = tostring(r.label or r.key)
    if label == "" then label = tostring(r.key) end
    local row = { kind = "row", label = label, tooltip = tooltipOf(r), enabled = r.settable == true }
    if isText(r.desc) then
        row.description = r.desc
    elseif isText(r.under) then
        row.description = r.under
    end
    if not row.enabled and isText(r.why) then row.reason = r.why end
    if r.kind == "bind" then
        local actions = type(r.actions) == "table" and r.actions or {}
        local set = actions[1]
        if type(set) == "table" then
            local bound
            if r.bound == true and isText(r.shown) then bound = r.shown end
            row.control = { kind = "bind", key = bound, waiting = r.waiting == true,
                onClick = function() nav("action", set.key) end }
        end
        out[#out + 1] = row
        -- What else the slot does (Clear), only while it can be done.
        for i = 2, #actions do
            local action = actions[i]
            if type(action) == "table" and action.enabled == true and isText(action.label) then
                out[#out + 1] = { kind = "button", key = action.key, text = action.label .. " " .. label,
                    onClick = function() nav("action", action.key) end }
            end
        end
        return
    end
    row.control = controlOf(r, act)
    -- A row that only shows (a place) is not greyed for having no control.
    if row.control == nil and r.kind == "info" then
        row.enabled = true
        row.reason = nil
        if isText(r.shown) then row.label = label .. ": " .. r.shown end
    end
    out[#out + 1] = row
    -- A row with a window of its own: the button that opens it.
    if r.jumpKind == "open" and isText(r.jumpText) then
        out[#out + 1] = { kind = "button", key = r.key .. ".open", text = r.jumpText,
            onClick = function() nav("open", r.jump) end }
    end
end

local function addActions(out, r, nav)
    if isText(r.label) then out[#out + 1] = { kind = "line", text = r.label } end
    for _, action in ipairs(type(r.actions) == "table" and r.actions or {}) do
        if type(action) == "table" and isText(action.label) then
            out[#out + 1] = { kind = "button", key = action.key, text = action.label,
                enabled = action.enabled ~= false, onClick = function() nav("action", action.key) end }
        end
    end
end

local function addOne(out, r, act, nav)
    if r.kind == "group" or r.kind == "section" then
        if isText(r.text) then out[#out + 1] = { kind = "section", text = r.text } end
    elseif r.kind == "note" then
        if isText(r.text) and isText(r.how) then
            out[#out + 1] = { kind = "empty", text = r.text, how = r.how }
        elseif isText(r.text) then
            out[#out + 1] = { kind = "line", text = r.text }
        end
    elseif r.kind == "actions" then
        addActions(out, r, nav)
    elseif r.key ~= nil then
        addRow(out, r, act, nav)
    end
end

function W.Tree(rows, act, nav, layout)
    local Kit = ns.Kit
    if type(Kit) ~= "table" or type(Kit.Window) ~= "function" then return nil, "the window kit is not loaded" end
    if type(act) ~= "function" or type(nav) ~= "function" then return nil, "the settings window needs act and nav" end
    rows = type(rows) == "table" and rows or {}
    layout = type(layout) == "table" and layout or {}
    local topics = type(layout.topics) == "table" and layout.topics or {}
    local search = type(layout.search) == "table" and layout.search or {}
    local searching = layout.topic == nil and isText(search.value)

    local names, selected = {}, nil
    local marked = layout.topic
    if marked == nil then marked = layout.back end
    for i = 1, #topics do
        names[i] = tostring(topics[i].name)
        if topics[i].id == marked then selected = i end
    end

    local summary = #topics .. W.MANY_TOPICS
    if #topics == 1 then summary = W.ONE_TOPIC end

    local pane = {}
    if isText(layout.notice) then pane[#pane + 1] = { kind = "line", text = layout.notice } end
    if searching then
        -- The hits under a heading for each topic, the topics in the order
        -- their best hit stands; what was found is said in the header.
        local order, by = {}, {}
        for _, r in ipairs(rows) do
            if r.kind == "group" then
                if isText(r.text) then summary = r.text end
            elseif r.topic == nil then
                addOne(pane, r, act, nav)
            else
                local name = tostring(r.topicName or r.topic)
                if by[name] == nil then
                    by[name] = {}
                    order[#order + 1] = name
                end
                by[name][#by[name] + 1] = r
            end
        end
        for _, name in ipairs(order) do
            pane[#pane + 1] = { kind = "section", text = name }
            for _, r in ipairs(by[name]) do addOne(pane, r, act, nav) end
        end
    else
        for _, r in ipairs(rows) do addOne(pane, r, act, nav) end
    end

    local typed = search.value
    if type(layout.typed) == "string" then typed = layout.typed end
    if type(typed) ~= "string" then typed = "" end
    local placeholder
    if isText(search.label) then placeholder = search.label end
    local title = layout.title
    if not isText(title) then title = tostring((ns.id or {}).title) end

    return Kit.Window({
        id = W.ID, title = title, width = W.WIDTH, height = W.HEIGHT, resizable = false,
        children = {
            { kind = "header", key = W.HEADER, title = summary,
              search = { text = typed, placeholder = placeholder, onText = function(text) nav("search", text) end } },
            { kind = "topicList", key = W.TOPICS, items = names, selected = selected,
              onSelect = function(i)
                  local topic = topics[i]
                  if topic then nav("topic", topic.id) end
              end },
            { kind = "scroll", children = pane },
        },
    })
end
