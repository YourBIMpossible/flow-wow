-- The arrows' right-click menu and hover tooltip as plain tables (inventory
-- rows 42, 45 to 50; LEDGER 65 AM5). Nothing here draws, clicks or reads the
-- client: UI/Arrow.lua asks for the rows and the lines and hands them to the
-- client's arrow frame, and turns a chosen row into a layout action.
--
-- The wording is authored here. The predecessor's menu was not copied.
local _, ns = ...

local M = {}
ns.ArrowMenu = M

local NAMES = { quest = "Quest arrow", prof = "Profession arrow" }
local KEYS = { "quest", "prof" }

-- s as UI/Arrow.lua gives it, or nothing at all:
--   { stacked, hidden = { quest, prof }, text = { quest, prof },
--     styles = { { key, label, on } }, canShapes }
local function read(s)
    s = type(s) == "table" and s or {}
    return {
        stacked = s.stacked ~= false,
        hidden = type(s.hidden) == "table" and s.hidden or {},
        text = type(s.text) == "table" and s.text or {},
        styles = type(s.styles) == "table" and s.styles or {},
        canShapes = s.canShapes == true,
        feedback = s.feedback == true,
    }
end

-- A style row is offered when the client can draw it: the modern arrow is
-- drawn from pictures, the others from lines.
local function styleOffered(s, key)
    return key == "modern" or s.canShapes
end

-- The headings, the settings topic the arrows belong to, and the most rows
-- a level may hold: all from the one list (Settings/Topics.lua).
local function topics() return ns.Settings.Topics end
M.TOPIC = "travel"

-- The whole menu as a tree (lead section 239, row N57). The top level is a
-- few headings, each with its own short list in `children`, and the rows
-- that open the settings. A row is one of
--   { title = true, text }             a heading, cannot be chosen
--   { sep = true }                     a divider, cannot be chosen
--   { key, text, disabled?, checked?, radio? }
--   { key, text, children = { row, ... } }   opens its children as a level
-- checked is true or false on a row that is ticked or not, and nil on a row
-- that is only an action. radio marks one-of-many (the styles).
-- What is on the screen at one time is M.Level's, never the whole tree.
function M.Items(state)
    local s = read(state)
    local T = topics()
    local layout = {
        { key = "restack", text = "Restack", disabled = s.stacked or nil },
        { key = "separate", text = "Separate", disabled = (not s.stacked) or nil },
        { key = "reset", text = "Reset" },
    }
    local show = {}
    for _, key in ipairs(KEYS) do
        show[#show + 1] = { key = "text." .. key, text = NAMES[key] .. " text", checked = s.text[key] ~= false }
    end
    for _, key in ipairs(KEYS) do
        show[#show + 1] = { key = "show." .. key, text = "Show " .. NAMES[key]:lower(), checked = not s.hidden[key] }
    end
    local rows = {
        { key = "layout", text = T.MENU.layout, children = layout },
        { key = "show", text = T.MENU.show, children = show },
    }
    local styles = {}
    for i = 1, #s.styles do
        local style = s.styles[i]
        if type(style) == "table" and type(style.key) == "string" then
            styles[#styles + 1] = {
                key = "style." .. style.key,
                text = type(style.label) == "string" and style.label or style.key,
                radio = true,
                checked = style.on == true,
                disabled = (not styleOffered(s, style.key)) or nil,
            }
        end
    end
    if #styles > 0 then
        rows[#rows + 1] = { key = "style", text = T.MENU.style, children = styles }
    end
    local topic = T.Find(M.TOPIC)
    rows[#rows + 1] = { sep = true }
    rows[#rows + 1] = { key = "settings." .. topic.id, text = topic.name .. T.MENU.topicSettings }
    rows[#rows + 1] = { key = "settings", text = T.MENU.settings }
    -- Row N73: the feedback window (UI/Feedback.lua), only while it is
    -- reachable (state.feedback; paused by lead section 284).
    if s.feedback then rows[#rows + 1] = { key = M.FEEDBACK, text = T.MENU.feedback } end
    return rows
end

M.BACK = "back"
M.FEEDBACK = "feedback"
M.MORE = "  >"

local function childrenOf(items, key)
    for i = 1, #items do
        local row = items[i]
        if type(row) == "table" and row.key == key and type(row.children) == "table" then return row end
    end
    return nil
end

-- The rows on the screen for one level of the tree: the top level (no
-- path), or the children of the row named by path ({ "layout" }) under its
-- heading, with the way back last. A row that opens a level is marked
-- more = true and its words end in M.MORE; it keeps its children, so what
-- lies under a level can still be read. A path that leads nowhere gives
-- the top level.
function M.Level(items, path)
    items = type(items) == "table" and items or {}
    local at, parent = items, nil
    for i = 1, #(type(path) == "table" and path or {}) do
        local row = childrenOf(at, path[i])
        if not row then
            at, parent = items, nil
            break
        end
        at, parent = row.children, row
    end
    local out = {}
    if parent then out[#out + 1] = { title = true, text = parent.text } end
    for i = 1, #at do
        local row = at[i]
        if type(row) == "table" and type(row.children) == "table" then
            local copy = {}
            for field, value in pairs(row) do copy[field] = value end
            copy.text, copy.more = tostring(row.text) .. M.MORE, true
            out[#out + 1] = copy
        else
            out[#out + 1] = row
        end
    end
    if parent then out[#out + 1] = { key = M.BACK, text = topics().MENU.back } end
    return out
end

-- Every level of the tree with its row count as M.Level shows it:
-- { { path = "top" | "layout" | ..., rows = n }, ... }, the top first.
function M.Counts(items)
    local out = {}
    local function walk(at, path, name)
        out[#out + 1] = { path = name, rows = #M.Level(items, path) }
        for i = 1, #at do
            local row = at[i]
            if type(row) == "table" and type(row.children) == "table" and type(row.key) == "string" then
                local deeper = {}
                for p = 1, #path do deeper[p] = path[p] end
                deeper[#deeper + 1] = row.key
                walk(row.children, deeper, row.key)
            end
        end
    end
    walk(type(items) == "table" and items or {}, {}, "top")
    return out
end

-- What choosing the row `key` asks for, or nil for a row that is not there
-- or not offered:
--   a layout action for Nav.ArrowApply ({ op = ... }), { style = key },
--   { open = key } for a row that opens its level ({ open = false }: back
--   to the top), { settings = topic id } / { settings = true } for a
--   row that opens the settings page (at that topic, or where it was), or
--   { feedback = true } for the row that opens the feedback window (only
--   with state.feedback true).
-- Opening a level or the settings changes nothing that is saved.
function M.Action(key, state)
    if type(key) ~= "string" then return nil end
    local s = read(state)
    if key == M.BACK then return { open = false } end
    if key == "layout" or key == "show" then return { open = key } end
    if key == "style" then
        for i = 1, #s.styles do
            if type(s.styles[i]) == "table" and type(s.styles[i].key) == "string" then return { open = key } end
        end
        return nil
    end
    if key == "settings" then return { settings = true } end
    if key == "feedback" then
        if s.feedback then return { feedback = true } end
        return nil
    end
    local topicId = key:match("^settings%.(.+)$")
    if topicId then
        local topic = topics().Find(topicId)
        if topic and topic.id == topicId then return { settings = topic.id } end
        return nil
    end
    if key == "reset" then return { op = "reset" } end
    if key == "restack" then
        if s.stacked then return nil end
        return { op = "restack" }
    end
    if key == "separate" then
        if not s.stacked then return nil end
        return { op = "mode", mode = "separate" }
    end
    local kind, which = key:match("^(%a+)%.(.+)$")
    if kind == "text" and NAMES[which] then
        return { op = "text", key = which, on = s.text[which] == false }
    end
    if kind == "show" and NAMES[which] then
        return { op = "hide", key = which, on = not s.hidden[which] }
    end
    if kind == "style" then
        for i = 1, #s.styles do
            local style = s.styles[i]
            if type(style) == "table" and style.key == which then
                if not styleOffered(s, which) then return nil end
                return { style = which }
            end
        end
    end
    return nil
end

-- Escape (owner default N1): Escape closes an open menu and does nothing
-- else. With no menu open the key is not taken, so the game's own Escape
-- (its windows, its game menu) goes on as before.
--
-- Only the decision and the close are here. No key reaches this yet:
--   the client's menu (Core/Client.lua) is an unnamed full-screen catcher
--     with a panel on it. It listens to no key, and without a name it
--     cannot be listed in the game's UISpecialFrames, which is how the
--     game closes a window at Escape and leaves the key alone otherwise.
--   an arrow handle has no way to be told of a key and does not say
--     whether its menu is open.
--   the fake client (Core/ClientFake.lua) has no key press for a handle.
-- Whoever hears the key (the catcher is shown only while a menu is open)
-- hands it to OnKey with the handle the menu is open for.
M.ESCAPE = "ESCAPE"

-- What the key asks of the menu: { close = true }, or nil for a key that
-- is not the menu's. open is true only while a menu is open.
function M.Key(key, open)
    if key == M.ESCAPE and open == true then return { close = true } end
    return nil
end

-- A key was pressed. h is the arrow handle the menu is open for; open as
-- for Key. -> true when the key was the menu's and the menu was closed
-- (the key is taken: the game must not see it), false otherwise (the key
-- is the game's). Closing chooses no row and changes nothing else.
function M.OnKey(h, key, open)
    if M.Key(key, open) == nil then return false end
    if type(h) ~= "table" or type(h.menu) ~= "function" then return false end
    return (pcall(h.menu, nil))
end

local function add(out, lines)
    if type(lines) ~= "table" then return end
    for i = 1, #lines do out[#out + 1] = tostring(lines[i]) end
end

-- The tooltip's lines for the arrow under the pointer, or nil for no arrow:
--   { key = "quest" | "prof", stacked, both, drawer,
--     lines = { quest = { ... }, prof = { ... } } }
-- The arrow's name, its step's lines, and last how to use it. Stacked with
-- both showing, the needle is under the quest arrow and takes no mouse, so
-- the quest arrow's tooltip carries the needle's lines too. A click is
-- promised only when there is a drawer to open.
function M.Tip(state)
    if type(state) ~= "table" or NAMES[state.key] == nil then return nil end
    local lines = type(state.lines) == "table" and state.lines or {}
    local out = { NAMES[state.key] }
    add(out, lines[state.key])
    if state.key == "quest" and state.stacked and state.both then
        out[#out + 1] = NAMES.prof
        add(out, lines.prof)
    end
    out[#out + 1] = (state.drawer and "Click: details. " or "") .. "Right-click: menu. Ctrl-drag: move."
    return out
end
