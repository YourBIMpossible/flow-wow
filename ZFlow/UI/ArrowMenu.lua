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
    }
end

-- A style row is offered when the client can draw it: the modern arrow is
-- drawn from pictures, the others from lines.
local function styleOffered(s, key)
    return key == "modern" or s.canShapes
end

-- The menu's rows, top to bottom. A row is one of
--   { title = true, text }             a heading, cannot be chosen
--   { sep = true }                     a divider, cannot be chosen
--   { key, text, disabled?, checked?, radio? }
-- checked is true or false on a row that is ticked or not, and nil on a row
-- that is only an action. radio marks one-of-many (the styles).
function M.Items(state)
    local s = read(state)
    local rows = {
        { title = true, text = "Arrows" },
        { key = "restack", text = "Restack", disabled = s.stacked or nil },
        { key = "separate", text = "Separate", disabled = (not s.stacked) or nil },
        { key = "reset", text = "Reset" },
        { sep = true },
    }
    for _, key in ipairs(KEYS) do
        rows[#rows + 1] = { key = "text." .. key, text = NAMES[key] .. " text", checked = s.text[key] ~= false }
    end
    for _, key in ipairs(KEYS) do
        rows[#rows + 1] = { key = "show." .. key, text = "Show " .. NAMES[key]:lower(), checked = not s.hidden[key] }
    end
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
        rows[#rows + 1] = { sep = true }
        rows[#rows + 1] = { title = true, text = "Style" }
        for i = 1, #styles do rows[#rows + 1] = styles[i] end
    end
    return rows
end

-- What choosing the row `key` asks for, or nil for a row that is not there
-- or not offered:
--   a layout action for Nav.ArrowApply ({ op = ... }), or { style = key }.
function M.Action(key, state)
    if type(key) ~= "string" then return nil end
    local s = read(state)
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
