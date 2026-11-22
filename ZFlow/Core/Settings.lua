-- Settings: one declared row per setting. The row is the only source of the
-- default, the scope, the type and the text the panel and setup will show.
--
--   ns:Setting{ key = "sell.autoJunk", scope = "char", type = "bool",
--               default = false, label = "Sell junk", help = "...",
--               group = "Vendor", requires = function(settings) ... end }
--   settings:get(key) / :set(key, value) / :reset(key | group | "all")
--   settings:each([group]) / :row(key) / :available(key)
--
-- Types: "bool", "number" (optional min, max), "string", "choice" (needs
-- choices = { ... }), "table". A bad or duplicate row is recorded as a
-- problem and skipped; the file declaring it keeps loading.
--
-- Where a row is stored: in its scope, at "settings." .. key. A row may name
-- its own place instead, for a value that is already kept somewhere else:
--   ns:Setting{ key = "arrow.layout", scope = "account", type = "table",
--               path = "layout.arrows", label = "Arrow positions" }
-- Reads, writes and resets of that row go to scope + path; nothing is moved
-- and nothing is kept under "settings." for it. Two rows cannot have one
-- place in one scope.
--
-- A "table" row holds the table as it is stored: the same table is given
-- back, not a copy, and what is in it is not checked. It is the one type
-- that may go without a default: such a row reads nil while nothing (or
-- something that is no table) is stored, and set(key, nil) clears it.
local _, ns = ...
ns.make = ns.make or {}

local TYPES = {
    bool = function(_, v) return type(v) == "boolean" end,
    number = function(row, v)
        return type(v) == "number" and v == v
            and (row.min == nil or v >= row.min) and (row.max == nil or v <= row.max)
    end,
    string = function(_, v) return type(v) == "string" end,
    choice = function(row, v)
        for i = 1, #row.choices do
            if row.choices[i] == v then return true end
        end
        return false
    end,
    table = function(_, v) return type(v) == "table" end,
}

-- Where the row is stored, within its scope.
local function place(row)
    return row.path or ("settings." .. row.key)
end

local function rowProblem(row)
    if type(row) ~= "table" then return "the row is not a table" end
    if type(row.key) ~= "string" or row.key == "" then return "no key" end
    if row.key:find("^%.") or row.key:find("%.$") or row.key:find("%.%.") then return "bad key" end
    if row.scope ~= "account" and row.scope ~= "char" then return "scope must be account or char" end
    if not TYPES[row.type] then return "unknown type " .. tostring(row.type) end
    if row.type == "choice" and (type(row.choices) ~= "table" or #row.choices == 0) then return "a choice needs choices" end
    if type(row.label) ~= "string" or row.label == "" then return "no label" end
    if row.help ~= nil and type(row.help) ~= "string" then return "help must be text" end
    if row.group ~= nil and type(row.group) ~= "string" then return "group must be text" end
    if row.requires ~= nil and type(row.requires) ~= "function" then return "requires must be a function" end
    if row.path ~= nil then
        local path = row.path
        if type(path) ~= "string" or path == "" or path:find("^%.") or path:find("%.$") or path:find("%.%.") then
            return "bad path"
        end
    end
    if row.default == nil then
        if row.type ~= "table" then return "no default" end
        return nil
    end
    if not TYPES[row.type](row, row.default) then return "the default does not fit the type" end
    return nil
end

function ns.make.settings(k)
    local settings = {}
    local rows, order = {}, {}
    local places = {}   -- scope .. ":" .. place -> true, for the rows taken

    function k:Setting(row)
        local problem = rowProblem(row)
        if not problem and rows[row.key] then problem = "duplicate key" end
        local at = not problem and (row.scope .. ":" .. place(row)) or nil
        if at and places[at] then problem = "duplicate path" end
        if problem then
            local key = type(row) == "table" and row.key or nil
            k.problems:add("setting", tostring(key), problem)
            return nil
        end
        places[at] = true
        rows[row.key] = row
        order[#order + 1] = row
        return row
    end

    function settings:row(key)
        return rows[key]
    end

    -- The stored value when it fits the row, else the row's default.
    function settings:get(key)
        local row = rows[key]
        if not row then return nil end
        local v = k.store:get(row.scope, place(row))
        if v ~= nil and TYPES[row.type](row, v) then return v end
        return row.default
    end

    function settings:set(key, value)
        local row = rows[key]
        if not row then return false, "unknown setting " .. tostring(key) end
        -- nil is a value only for a row without a default: it clears it.
        if not (value == nil and row.default == nil) and not TYPES[row.type](row, value) then
            return false, "not a valid " .. row.type
        end
        return k.store:set(row.scope, place(row), value)
    end

    -- Back to the default: one key, every key of a group, or "all".
    function settings:reset(what)
        local n = 0
        for i = 1, #order do
            local row = order[i]
            if what == "all" or row.key == what or (not rows[what] and row.group == what) then
                if k.store:set(row.scope, place(row), nil) then n = n + 1 end
            end
        end
        return n
    end

    -- Rows in the order they were declared; all of them, or one group's.
    function settings:each(group)
        local i = 0
        return function()
            repeat i = i + 1 until not order[i] or group == nil or order[i].group == group
            return order[i]
        end
    end

    -- False when the row's `requires` says the setting does not apply now.
    function settings:available(key)
        local row = rows[key]
        if not row then return false end
        if not row.requires then return true end
        local ok, yes = pcall(row.requires, self)
        if not ok then
            k.problems:add("setting", key, "requires failed: " .. tostring(yes))
            return false
        end
        return yes and true or false
    end

    return settings
end
