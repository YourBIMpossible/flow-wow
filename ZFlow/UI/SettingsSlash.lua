-- SettingsSlash: the settings from the chat line. No panel, no frames.
--
--   <slash> setting                 every setting row: key, value, scope, label,
--                                   under its topic's name
--   <slash> setting <key>           that one row, and what it takes
--   <slash> setting <key> on|off    a yes-or-no row
--   <slash> setting <key> <value>   a number row or a choice row
--
-- The rows are the kernel's (ns:Setting and a module's settings). Nothing
-- is listed here that is not a row, and no row is made here.
--
-- A change goes through the kernel's settings (so it is checked against the
-- row's type and limits and saved at the row's own scope and place) and,
-- for a key the settings model (Settings/Model.lua) also holds, through the
-- model's check for that key. A refusal says why and changes nothing:
--   an unknown key
--   a yes-or-no row given anything but on or off
--   a number row given something that is not a plain number (digits, with
--     an optional sign and fraction), or one outside the row's limits
--   a choice row given something that is not one of its choices
--   a text row or a table row: listed, but not set from here. The slash
--     command hands every word over lower-cased, so text would not arrive
--     as typed.
--   saved data that is not loaded yet, or a write the store refuses
--
-- The key is matched whatever its capitals (the slash command lower-cases
-- it); a choice is matched the same way and saved in the row's own spelling.
--
--   SettingsSlash.Run(k, rest) -> lines, changed
--     rest     what follows the word, as typed
--     lines    what to say, without the title
--     changed  true only when a value was saved
--   SettingsSlash.Start(k, diag) -> { run = fn }
--     adds the word "setting" to diag.commands when diag has them, and
--     its line for the help word to diag.help.
local _, ns = ...

local S = {}
ns.SettingsSlash = S

S.WORD = "setting"
S.HELP = "list the settings, show one, or change one: setting <key> <value>"
S.NOT_LOADED = "the saved settings are not loaded yet; try again after login."
S.NONE = "there are no settings yet."
S.SCOPES = { char = "this character", account = "account" }

local function trim(text)
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A value as it is said. A table is never spelled out; one that is not
-- stored is "not set", never off and never 0.
local function say(row, value)
    if row.type == "table" then return type(value) == "table" and "set" or "not set" end
    if value == nil then return "not set" end
    if row.type == "bool" then return value and "on" or "off" end
    if row.type == "string" then return '"' .. tostring(value) .. '"' end
    return tostring(value)
end

local function choicesText(row)
    local out = {}
    for i = 1, #row.choices do out[i] = tostring(row.choices[i]) end
    return table.concat(out, ", ")
end

-- What a row takes, for the line that explains it.
local function takes(row)
    if row.type == "bool" then return "on or off" end
    if row.type == "number" then
        if row.min ~= nil and row.max ~= nil then return "a number from " .. row.min .. " to " .. row.max end
        if row.min ~= nil then return "a number, " .. row.min .. " or more" end
        if row.max ~= nil then return "a number, " .. row.max .. " or less" end
        return "a number"
    end
    if row.type == "choice" then return "one of: " .. choicesText(row) end
    return nil
end

local function rowLine(k, row)
    return row.key .. " = " .. say(row, k.settings:get(row.key))
        .. " (" .. (S.SCOPES[row.scope] or tostring(row.scope)) .. ") - " .. tostring(row.label)
end

-- The row for a typed key: its own spelling first, then whatever the
-- capitals. -> row, or nil and why.
local function find(k, typed)
    local row = k.settings:row(typed)
    if row then return row end
    local lower, found, many = typed:lower(), nil, false
    for one in k.settings:each() do
        if one.key:lower() == lower then
            if found then many = true end
            found = found or one
        end
    end
    if many then return nil, "more than one setting is called " .. typed .. " apart from capitals" end
    if found then return found end
    return nil, "no setting is called " .. typed
end

-- The row a typed key means, as the word finds it; nil when no row has that
-- key. (UI/SettingsPanel.lua asks, to tell a key from words to search for.)
function S.Row(k, typed)
    if type(typed) ~= "string" or typed == "" then return nil end
    return (find(k, typed))
end

-- The typed text as a value for the row. -> value, or nil and why.
local function parse(row, text)
    if row.type == "bool" then
        local word = text:lower()
        if word == "on" then return true end
        if word == "off" then return false end
        return nil, "it takes on or off"
    end
    if row.type == "number" then
        -- Plain digits only: no hex, no exponent, no "inf", no "nan".
        local plain = text:find("^[+-]?%d+%.?%d*$") or text:find("^[+-]?%.%d+$")
        local n = plain and tonumber(text) or nil
        if n == nil or n ~= n or n == math.huge or n == -math.huge then
            return nil, '"' .. text .. '" is not a number'
        end
        if row.min ~= nil and n < row.min then return nil, "below the lowest value allowed (" .. row.min .. ")" end
        if row.max ~= nil and n > row.max then return nil, "above the highest value allowed (" .. row.max .. ")" end
        return n
    end
    if row.type == "choice" then
        for i = 1, #row.choices do
            if tostring(row.choices[i]) == text then return row.choices[i] end
        end
        local lower = text:lower()
        for i = 1, #row.choices do
            if tostring(row.choices[i]):lower() == lower then return row.choices[i] end
        end
        return nil, '"' .. text .. '" is not one of: ' .. choicesText(row)
    end
    return nil, "a " .. (row.type == "string" and "text" or tostring(row.type))
        .. " setting cannot be set from this command"
end

-- The settings model's word on a key it also holds. true when the model
-- does not hold the key or is not loaded: then the row alone decides.
local function modelAllows(key, value)
    local Model = ns.Settings and ns.Settings.Model
    if type(Model) ~= "table" or type(Model.Default) ~= "function" then return true end
    local model = Model.Default()
    if type(model) ~= "table" or model:row(key) == nil then return true end
    return model:check(key, value)
end

local function refused(row, why)
    return { row.key .. " not changed: " .. tostring(why) .. "." }, false
end

function S.Run(k, rest)
    local id = k.id
    if not (type(k.store) == "table" and k.store.opened) then return { S.NOT_LOADED }, false end
    local text = trim(rest == nil and "" or rest)

    if text == "" then
        -- Under their topics (row N57), in the topics' order, as the
        -- settings page has them; a row is one line, as it always was.
        local lines = {}
        local Page = ns.SettingsPage
        local view
        if type(Page) == "table" and type(Page.View) == "function" then view = Page.View(k) end
        if type(view) == "table" and type(view.topics) == "table" then
            for _, topic in ipairs(view.topics) do
                lines[#lines + 1] = tostring(topic.name) .. ":"
                for _, e in ipairs(topic.rows) do
                    local row = k.settings:row(e.key)
                    if row then lines[#lines + 1] = rowLine(k, row) end
                end
            end
        else
            for row in k.settings:each() do lines[#lines + 1] = rowLine(k, row) end
        end
        if #lines == 0 then return { S.NONE }, false end
        table.insert(lines, 1, "settings, as key = value (saved for) - what it is. Change one with: "
            .. id.slash .. " " .. S.WORD .. " <key> <value>")
        return lines, false
    end

    local typedKey, typedValue = text:match("^(%S+)%s*(.-)$")
    local row, why = find(k, typedKey)
    if not row then return { why .. "; nothing changed. " .. id.slash .. " " .. S.WORD .. " lists them." }, false end

    if typedValue == "" then
        local lines = { rowLine(k, row) }
        if type(row.help) == "string" and row.help ~= "" then lines[#lines + 1] = row.help end
        local what = takes(row)
        if what then
            lines[#lines + 1] = "Takes " .. what .. ". Change it with: "
                .. id.slash .. " " .. S.WORD .. " " .. row.key .. " <value>"
        else
            lines[#lines + 1] = "It cannot be set from this command."
        end
        return lines, false
    end

    local value, bad = parse(row, typedValue)
    if value == nil then return refused(row, bad) end
    local allowed, modelWhy = modelAllows(row.key, value)
    if not allowed then return refused(row, modelWhy) end

    local was = k.settings:get(row.key)
    local ok, reason = k.settings:set(row.key, value)
    if not ok then return refused(row, reason or "the store refused it") end
    if k.settings:get(row.key) ~= value then return refused(row, "it did not read back as saved") end
    return { row.key .. " is now " .. say(row, value) .. " (was " .. say(row, was) .. "); saved for "
        .. (S.SCOPES[row.scope] or tostring(row.scope)) .. "." }, true
end

-- Adds the word to the slash command of kernel k. diag (optional) is what
-- Diag.Start returned; without its commands nothing is added.
function S.Start(k, diag)
    local function run(rest)
        local lines, changed = S.Run(k, rest)
        for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
        return changed
    end
    if diag and type(diag.commands) == "table" then
        diag.commands[S.WORD] = run
        if type(diag.help) == "table" then diag.help[S.WORD] = S.HELP end
    end
    return { run = run }
end

-- The addon's own: the word is added when this file loads.
ns.settingsSlash = S.Start(ns, ns.diag)
