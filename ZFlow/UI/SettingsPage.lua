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
--     view.topics  { { id = , name = , rows = { entry, ... }, sections = {
--                  { id = , name = , rows = { entry, ... } }, ... } }, ... }:
--                  the topics of Settings/Topics.lua that hold a row, in
--                  the list's order; rows in the order declared. sections
--                  holds the same rows as they are shown: first the ones
--                  in no section (id and name nil), then each listed
--                  section that holds one. A row that names no listed
--                  topic stands under Topics.UNFILED, last. Nothing here
--                  is a hand-kept list: a row declared a moment ago is in
--                  the next view. view.groups is the same list.
--     entry        key, label, help (nil when the row has none), kind,
--                  value, shown (the value as text), savedFor, scope
--                  ("account" or "character"), topic, topicName, section,
--                  sectionName, min, max, step (a number row: how far one
--                  press of minus or plus moves it), choices (a copy), available,
--                  settable, why (the reason when it cannot be set, else
--                  nil), because (what an unavailable row depends on and
--                  what its `requires` said, when either is known), opens
--                  (the words of the row's own button, for a row with a
--                  window of its own: SettingsPage.Open(k, key) runs it)
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
--   SettingsPage.Step(row) -> the step of a number row: its own `step`
--     when it gives one above 0, else 0.05 for a row whose limits are 1 or
--     less apart (a share), else 1. nil for any other row.
--   SettingsPage.Snap(row, value) -> a number a control sent for a number
--     row, put on the row's steps and cleared of the stray digits adding
--     leaves (0.30000000000000004 is 0.3). Anything else is handed back
--     as it is. The row's limits are not applied here: Set refuses.
--
--   SettingsPage.Search(k, query [, view]) -> found, or nil for an empty
--     search (then the page is browsed by topic)
--     found.query    the search as typed, trimmed
--     found.results  entries from every topic, best match first: the same
--                    entries the topics hold, so a result is changed by
--                    the same Set. Matched on the label, the description,
--                    the topic's and section's names and the row's
--                    synonyms, whatever the capitals and accents.
--     found.none     the line to show when nothing matched, else nil
--
--   SettingsPage.State(k) -> { topic = id or nil, query = text or nil }
--     where the player is on the page, one for every surface of kernel k
--     (the Options page, the text panel, the slash word, a menu row). Not
--     saved: a reload starts at the first topic.
--   SettingsPage.Goto(k, topicId) -> true, or false for no such topic
--     Chooses the topic and ends a search.
--   SettingsPage.Find(k, query) -> true while a search is on
--     An empty query ends the search: the chosen topic is shown again.
--   SettingsPage.Page(k) -> page: what a surface draws now
--     page.loaded, page.count
--     page.topics  { { id, name, count, on }, ... }: the navigation; `on`
--                  marks the topic shown, none during a search
--     page.mode    "topic": page.topic is that view topic (nil: no rows)
--                  "search": page.query, page.results, page.none
--
-- There is no reset on the page (owner decision 6).
local P = {}
ns.SettingsPage = P

P.NOT_LOADED = "the saved settings are not loaded yet; try again after login"
P.NOT_NOW = "this setting does not apply right now"
P.NOT_FROM_HERE = "this is not set from the settings page"
P.SCOPES = { char = "this character", account = "account" }
P.SCOPE_WORDS = { char = "character", account = "account" }
P.DEPENDS = "depends on "
P.NO_MATCH_TAIL = "Try another word (sell, bank, arrow, food), or pick a topic."

local KINDS = { bool = "toggle", number = "number", choice = "choice", string = "text", table = "place" }

local function topics() return ns.Settings.Topics end

function P.NoMatch(query)
    return 'No setting matches "' .. tostring(query) .. '". ' .. P.NO_MATCH_TAIL
end

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

-- Why an unavailable row cannot be used: the rows it names in `needs`,
-- each with its topic, and what its `requires` gave as a second answer.
-- nil when the row says neither.
local function because(k, row)
    local parts = {}
    local needs = row.needs
    if type(needs) == "string" then needs = { needs } end
    if type(needs) == "table" then
        for i = 1, #needs do
            local other = type(needs[i]) == "string" and k.settings:row(needs[i]) or nil
            if other then
                parts[#parts + 1] = P.DEPENDS .. '"' .. tostring(other.label) .. '" ('
                    .. topics().Of(other).name .. ")"
            elseif type(needs[i]) == "string" then
                parts[#parts + 1] = P.DEPENDS .. needs[i]
            end
        end
    end
    if type(row.requires) == "function" then
        local ok, _, said = pcall(row.requires, k.settings)
        if ok and type(said) == "string" and said ~= "" then parts[#parts + 1] = said end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "; ")
end

function P.Step(row)
    if type(row) ~= "table" or row.type ~= "number" then return nil end
    if type(row.step) == "number" and row.step > 0 then return row.step end
    if type(row.min) == "number" and type(row.max) == "number" and row.max - row.min <= 1 then return 0.05 end
    return 1
end

function P.Snap(row, value)
    local step = P.Step(row)
    if step == nil or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then
        return value
    end
    local snapped = math.floor(value / step + 0.5) * step
    return math.floor(snapped * 1000000 + 0.5) / 1000000
end

local function entryOf(k, row, isLoaded)
    local kind = KINDS[row.type]
    local e = {
        key = row.key,
        label = row.label,
        help = type(row.help) == "string" and row.help ~= "" and row.help or nil,
        kind = kind,
        savedFor = P.SCOPES[row.scope] or tostring(row.scope),
        scope = P.SCOPE_WORDS[row.scope] or tostring(row.scope),
        min = row.min,
        max = row.max,
        step = P.Step(row),
        shown = "",
        settable = false,
    }
    if row.type == "choice" then
        e.choices = {}
        for i = 1, #row.choices do e.choices[i] = row.choices[i] end
    end
    -- A row with a window of its own (row.open): the words of its button.
    if type(row.open) == "table" and type(row.open.run) == "function" then
        e.opens = "Open"
        if type(row.open.text) == "string" and row.open.text ~= "" then e.opens = row.open.text end
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
        e.because = because(k, row)
    else
        e.settable = true
    end
    return e
end

-- The rows of one topic as they are shown: the ones in no section first,
-- then each listed section that holds a row, in the list's order.
local function sectionsOf(topic, rows)
    local out, plain, by = {}, { rows = {} }, {}
    for i = 1, #rows do
        local e = rows[i]
        if e.section == nil then
            plain.rows[#plain.rows + 1] = e
        else
            by[e.section] = by[e.section] or { id = e.section, name = e.sectionName, rows = {} }
            by[e.section].rows[#by[e.section].rows + 1] = e
        end
    end
    if #plain.rows > 0 then out[#out + 1] = plain end
    for i = 1, #topic.sections do
        local held = by[topic.sections[i].id]
        if held then out[#out + 1] = held end
    end
    return out
end

function P.View(k)
    local Topics = topics()
    local isLoaded = loaded(k)
    local view = { loaded = isLoaded, count = 0, topics = {} }
    local byId, listed = {}, {}
    for row in k.settings:each() do
        local topic, section = Topics.Of(row)
        local e = entryOf(k, row, isLoaded)
        view.count = view.count + 1
        e.order = view.count
        e.topic, e.topicName = topic.id, topic.name
        if section then e.section, e.sectionName = section.id, section.name end
        local held = byId[topic.id]
        if not held then
            held = { id = topic.id, name = topic.name, rows = {} }
            byId[topic.id] = held
            listed[#listed + 1] = topic
        end
        held.rows[#held.rows + 1] = e
    end
    table.sort(listed, function(a, b) return a.at < b.at end)
    for i = 1, #listed do
        local held = byId[listed[i].id]
        held.sections = sectionsOf(listed[i], held.rows)
        view.topics[i] = held
    end
    view.groups = view.topics
    return view
end

local function trim(text)
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

function P.Search(k, query, view)
    local Topics = topics()
    if type(query) ~= "string" then return nil end
    local words = Topics.Words(query)
    if #words == 0 then return nil end
    view = view or P.View(k)
    local hits = {}
    for t = 1, #view.topics do
        local rows = view.topics[t].rows
        for i = 1, #rows do
            local score = Topics.Match(k.settings:row(rows[i].key), words)
            if score then hits[#hits + 1] = { e = rows[i], score = score } end
        end
    end
    table.sort(hits, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.e.order < b.e.order
    end)
    local found = { query = trim(query), results = {} }
    for i = 1, #hits do found.results[i] = hits[i].e end
    if #hits == 0 then found.none = P.NoMatch(found.query) end
    return found
end

-- Where the player is on the page, by kernel. Kept only while the kernel is.
local states = setmetatable({}, { __mode = "k" })

function P.State(k)
    local state = states[k]
    if not state then
        state = {}
        states[k] = state
    end
    return state
end

function P.Goto(k, topicId)
    local Topics = topics()
    local topic = Topics.Find(topicId)
    if not topic and topicId ~= Topics.UNFILED.id then return false end
    local state = P.State(k)
    state.topic = topic and topic.id or topicId
    state.query = nil
    return true
end

function P.Find(k, query)
    local state = P.State(k)
    if type(query) == "string" and #topics().Words(query) > 0 then
        state.query = trim(query)
    else
        state.query = nil
    end
    return state.query ~= nil
end

function P.Page(k)
    local state = P.State(k)
    local view = P.View(k)
    local page = { loaded = view.loaded, count = view.count, topics = {} }
    local found = P.Search(k, state.query, view)
    local chosen
    if not found then
        for i = 1, #view.topics do
            if view.topics[i].id == state.topic then chosen = view.topics[i] end
        end
        chosen = chosen or view.topics[1]
    end
    for i = 1, #view.topics do
        local topic = view.topics[i]
        page.topics[i] = { id = topic.id, name = topic.name, count = #topic.rows, on = topic == chosen }
    end
    if found then
        page.mode, page.query, page.results, page.none = "search", found.query, found.results, found.none
    else
        page.mode, page.topic = "topic", chosen
    end
    return page
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

-- Runs the row's own opener (row.open.run), as the button beside it asks.
-- -> true when it ran; false for a row with none, or one that raised (kept
-- as a problem). It saves nothing by itself.
function P.Open(k, key)
    local row
    if type(key) == "string" then row = k.settings:row(key) end
    if type(row) ~= "table" or type(row.open) ~= "table" or type(row.open.run) ~= "function" then return false end
    local ok, err = pcall(row.open.run)
    if not ok then
        k.problems:add("settings", key, err)
        return false
    end
    return true
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
