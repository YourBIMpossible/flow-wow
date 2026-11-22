local _, ns = ...

-- SettingsPage: the settings as a page a panel can draw (G52). No frames
-- here: this is what stands on the page and what a change does. The panel
-- that draws it asks View for the rows and hands a change to Set.
--
-- The rows are the kernel's (ns:Setting and a module's settings). Nothing
-- stands on the page that is not a row, and no row is made here.
--
--   SettingsPage.View(k) -> view
--     view.loaded  false until the saved settings are loaded. Until then
--                  the rows are listed without values and none can be set.
--     view.count   how many rows
--     view.groups  { { name = , rows = { entry, ... } }, ... }: groups in
--                  the order first declared, rows in the order declared. A
--                  row without a group stands under GROUP_OTHER.
--     entry        key, label, help (nil when the row has none), kind,
--                  value, shown (the value as text), savedFor, min, max,
--                  choices (a copy), available, settable, why (the reason
--                  when it cannot be set, else nil)
--     kind         "toggle" (bool), "number", "choice", "text" (string) or
--                  "place" (table). A place is never handed out or spelled
--                  out: it reads "set" or "not set", and is not set here.
--
--   SettingsPage.Set(k, key, value) -> true, or false and why
--     value is the value itself, not typed text: true or false for a
--     toggle, a number, one of the row's choices as the row spells it, or
--     text. It goes through the kernel's settings (checked against the
--     row's type and limits, saved at the row's own scope and place) and,
--     for a key the settings model (Settings/Model.lua) also holds, through
--     the model's check for that key. A refusal changes nothing.
--
-- There is no reset on the page (owner decision 6).
local P = {}
ns.SettingsPage = P

P.GROUP_OTHER = "Other" -- authored
P.NOT_LOADED = "the saved settings are not loaded yet; try again after login"
P.NOT_NOW = "this setting does not apply right now"
P.NOT_FROM_HERE = "this is not set from the settings page"
P.SCOPES = { char = "this character", account = "account" }

local KINDS = { bool = "toggle", number = "number", choice = "choice", string = "text", table = "place" }

local function loaded(k)
    return type(k.store) == "table" and k.store.opened == true
end

local function choicesText(row)
    local out = {}
    for i = 1, #row.choices do out[i] = tostring(row.choices[i]) end
    return table.concat(out, ", ")
end

-- A value as it is shown. A place is never spelled out; one that is not
-- stored is "not set", never off and never 0.
local function show(row, value)
    if row.type == "table" then return type(value) == "table" and "set" or "not set" end
    if value == nil then return "not set" end
    if row.type == "bool" then return value and "on" or "off" end
    return tostring(value)
end

local function entryOf(k, row, isLoaded)
    local kind = KINDS[row.type]
    local e = {
        key = row.key,
        label = row.label,
        help = type(row.help) == "string" and row.help ~= "" and row.help or nil,
        kind = kind,
        savedFor = P.SCOPES[row.scope] or tostring(row.scope),
        min = row.min,
        max = row.max,
        shown = "",
        settable = false,
    }
    if row.type == "choice" then
        e.choices = {}
        for i = 1, #row.choices do e.choices[i] = row.choices[i] end
    end
    if not isLoaded then
        e.why = P.NOT_LOADED
        return e
    end
    local value = k.settings:get(row.key)
    if kind ~= "place" then e.value = value end
    e.shown = show(row, value)
    e.available = k.settings:available(row.key)
    if kind == "place" then
        e.why = P.NOT_FROM_HERE
    elseif not e.available then
        e.why = P.NOT_NOW
    else
        e.settable = true
    end
    return e
end

function P.View(k)
    local isLoaded = loaded(k)
    local view = { loaded = isLoaded, count = 0, groups = {} }
    local byName = {}
    for row in k.settings:each() do
        local name = type(row.group) == "string" and row.group ~= "" and row.group or P.GROUP_OTHER
        local group = byName[name]
        if not group then
            group = { name = name, rows = {} }
            byName[name] = group
            view.groups[#view.groups + 1] = group
        end
        group.rows[#group.rows + 1] = entryOf(k, row, isLoaded)
        view.count = view.count + 1
    end
    return view
end

-- Why the value does not fit the row, or nil when it does.
local function misfit(row, value)
    if row.type == "bool" then
        if type(value) ~= "boolean" then return "it takes on or off" end
    elseif row.type == "number" then
        if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
            return "it takes a number"
        end
        if row.min ~= nil and value < row.min then return "below the lowest value allowed (" .. row.min .. ")" end
        if row.max ~= nil and value > row.max then return "above the highest value allowed (" .. row.max .. ")" end
    elseif row.type == "choice" then
        for i = 1, #row.choices do
            if row.choices[i] == value then return nil end
        end
        return "it takes one of: " .. choicesText(row)
    elseif row.type == "string" then
        if type(value) ~= "string" then return "it takes text" end
    end
    return nil
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

function P.Set(k, key, value)
    if not loaded(k) then return false, P.NOT_LOADED end
    local row = type(key) == "string" and k.settings:row(key) or nil
    if not row then return false, "no setting is called " .. tostring(key) end
    if KINDS[row.type] == "place" then return false, P.NOT_FROM_HERE end
    if not k.settings:available(row.key) then return false, P.NOT_NOW end
    local bad = misfit(row, value)
    if bad then return false, bad end
    local allowed, modelWhy = modelAllows(row.key, value)
    if not allowed then return false, tostring(modelWhy) end
    local ok, reason = k.settings:set(row.key, value)
    if not ok then return false, tostring(reason or "the store refused it") end
    if k.settings:get(row.key) ~= value then return false, "it did not read back as saved" end
    return true
end
