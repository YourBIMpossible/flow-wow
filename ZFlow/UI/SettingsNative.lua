-- Lead section 410: Z-Flow's settings as the game's own rows, in the game's
-- Options under AddOns. The add-on has one entry there and each topic
-- (Settings/Topics.lua) one under it; a setting is one checkbox, slider or
-- dropdown the game builds (client.optionsNative), with its short name as
-- the label and its whole description in the tooltip.
--
-- Nothing is kept here: a row reads the settings model each time the game
-- asks and a change goes through the one checked set (UI/SettingsOptions.lua
-- hands it in), so no setting's default or meaning is another's.
--
-- What the game has no row for stays reachable by a button row:
--   a setting typed as text, or a number with no limits -> "Change", which
--     opens the add-on's own window at that topic;
--   the rotation keys (UI/SettingsKeys.lua) -> the same, on their topic;
--   a setting with a window of its own (row.open) -> that window's button.
-- A place (type "table") is never set from a page and has no row.
--
--   N.Spec(k, handlers) -> the spec client.optionsNative takes, or nil while
--     the saved settings are not loaded
--   N.Attach(k, ctx, handlers) -> the client's handle, or nil when the client
--     has no such rows (the caller keeps its own window)
--   handlers = { set = fn(key, value), act = fn(action key),
--                own = fn({ topic = id }), keys = true when there are key rows }
local _, ns = ...

local N = {}
N.NAME = "settingsNative"
N.CHANGE = "Change"
N.CHOOSE = "Choose"
N.SAVED_FOR = "Saved for "
N.IN_WINDOW = "This one is changed in the add-on's own window."
N.KEYS_TIP = "The keys of the rotation are changed in the add-on's own window."

local function tipOf(e, tail)
    local parts = {}
    if e.help then parts[#parts + 1] = e.help end
    if tail then parts[#parts + 1] = tail end
    parts[#parts + 1] = N.SAVED_FOR .. tostring(e.savedFor) .. "."
    return table.concat(parts, "\n\n")
end

-- The game's row for an entry of the page: "toggle", "number", "choice", or
-- nil for none.
function N.Kind(e)
    if e.kind == "toggle" then return "toggle" end
    if e.kind == "choice" and type(e.choices) == "table" and #e.choices > 0 then return "choice" end
    if e.kind == "number" and type(e.min) == "number" and type(e.max) == "number" and e.max > e.min then
        return "number"
    end
    return nil
end

local function tagsOf(row)
    local out = {}
    if type(row.synonyms) == "table" then
        for i = 1, #row.synonyms do
            if type(row.synonyms[i]) == "string" then out[#out + 1] = row.synonyms[i] end
        end
    end
    return out
end

local function entryRows(k, handlers, rows, e, topicId)
    local row = k.settings:row(e.key)
    if type(row) ~= "table" then return end
    local label = e.label or e.key
    local kind = N.Kind(e)
    if kind then
        local key = e.key
        local default = row.default
        if kind == "toggle" then
            default = default == true
        elseif kind == "number" then
            if type(default) ~= "number" then default = e.min end
        elseif default == nil then
            default = e.choices[1]
        end
        local r = {
            kind = kind, key = key, label = label, tip = tipOf(e), default = default,
            min = e.min, max = e.max, step = e.step, tags = tagsOf(row),
            get = function()
                local v = k.settings:get(key)
                if kind == "toggle" then return v == true end
                if v == nil then return default end
                return v
            end,
            set = function(v) return handlers.set(key, v) end,
            can = function() return k.settings:available(key) == true end,
        }
        if kind == "choice" then
            r.choices = {}
            for i = 1, #e.choices do
                r.choices[i] = { value = e.choices[i], label = tostring(e.choices[i]) }
            end
        end
        rows[#rows + 1] = r
    elseif e.kind == "text" or e.kind == "number" then
        rows[#rows + 1] = {
            kind = "button", label = label, text = N.CHANGE, tip = tipOf(e, N.IN_WINDOW),
            run = function() return handlers.own({ topic = topicId }) end,
        }
    end
    if e.opens then
        local key = e.key
        rows[#rows + 1] = {
            kind = "button", label = label, text = e.opens, tip = tipOf(e),
            run = function() return ns.SettingsPage.Open(k, key) end,
        }
    end
end

function N.Spec(k, handlers)
    local P = ns.SettingsPage
    local view = P.View(k)
    if not view.loaded then return nil end
    local id = k.id or ns.id
    local spec = { title = tostring(id.title), name = tostring(id.framePrefix) .. "Options", rows = {}, topics = {} }
    -- The add-on's own entry: the page's two buttons.
    if type(P.Actions) == "function" then
        for _, action in ipairs(P.Actions(k)) do
            local key = action.key
            spec.rows[#spec.rows + 1] = {
                kind = "button", label = action.label, text = N.CHOOSE,
                run = function() return handlers.act(key) end,
            }
        end
    end
    local SK = ns.SettingsKeys
    for _, topic in ipairs(view.topics) do
        local rows = {}
        local headed = #topic.sections > 1
        for _, section in ipairs(topic.sections) do
            if section.name and headed then rows[#rows + 1] = { kind = "header", text = section.name } end
            for _, e in ipairs(section.rows) do entryRows(k, handlers, rows, e, topic.id) end
        end
        if handlers.keys and type(SK) == "table" and topic.id == SK.GROUP then
            local topicId = topic.id
            if headed then rows[#rows + 1] = { kind = "header", text = SK.SECTION } end
            rows[#rows + 1] = {
                kind = "button", label = SK.SECTION, text = N.CHANGE, tip = N.KEYS_TIP,
                run = function() return handlers.own({ topic = topicId }) end,
            }
        end
        if #rows > 0 then spec.topics[#spec.topics + 1] = { id = topic.id, name = topic.name, rows = rows } end
    end
    return spec
end

function N.Attach(k, ctx, handlers)
    if type(ctx) ~= "table" or type(ctx.client) ~= "table" or type(ctx.client.optionsNative) ~= "function" then
        return nil
    end
    local okS, spec = pcall(N.Spec, k, handlers)
    if not okS then
        k.problems:add(N.NAME, "spec", spec)
        return nil
    end
    if type(spec) ~= "table" then return nil end
    local ok, made = pcall(ctx.client.optionsNative, spec)
    if not ok then
        k.problems:add(N.NAME, "register", made)
        return nil
    end
    if type(made) ~= "table" then return nil end
    return made
end

ns.SettingsNative = N
