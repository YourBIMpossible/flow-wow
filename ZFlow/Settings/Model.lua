local _, ns = ...
-- The settings model: what settings there are, what each may hold and what
-- each is when the player has chosen nothing. Pure Lua 5.1: no frames, no
-- client calls, no saved variable, no clock. Every function takes the
-- settings table as stored ({ sell = { autoJunk = false }, ... }), tolerates
-- a missing or half-written one, never raises and never changes what it is
-- given; a function that changes a setting returns a new table.
--
--   Model.New(rows) -> model, problems
--     rows      list of { key, type, default [, bounds] [, vendor] }
--       key      "section.name": where the value sits in the settings table
--       type     "bool", "number" or "string"
--       default  the value when nothing is stored; must fit type and bounds
--       bounds   numbers only: { min = n, max = n }, either end optional
--       vendor   true marks a vendor automation: a "bool" whose default is
--                false. Each one is its own row and its own switch.
--     problems  list of { key, problem }: rows left out, and why
--   Model.Default() -> model      the rows in Model.ROWS
--
--   model:keys()                  every key, in the order of the rows
--   model:row(key)                a copy of the row, or nil
--   model:default(key)            the default, or nil for an unknown key
--   model:defaults()              every default, as a settings table
--   model:check(key, value)       true, or false and why
--   model:get(values, key)        the stored value when it fits, else the default
--   model:explicit(values, key)   true when a fitting value is stored
--   model:set(values, key, value) a new settings table, or nil and why
--   model:reset(values, key)      a new settings table without the key, or nil and why
--   model:adopt(values, imported) a new settings table, and a report
--
-- A choice the player made is kept apart from a default: get() reads a
-- default without storing it, so a later change of a default never passes
-- for a choice, and adopt() takes only what the import holds.
ns.Settings = ns.Settings or {}
local M = {}
ns.Settings.Model = M

-- The shipped rows. Only settings whose type and default are known are
-- listed; a setting with no row here is not the model's to read or write.
--   sell.*        the vendor automations the import carries
--                 (Import/FromFlow.lua). Each is off until the player turns
--                 that one on.
--   auction.*, buffButton.*   defaults as Import/Stored.lua reads them.
M.ROWS = {
    { key = "sell.autoJunk", type = "bool", default = false, vendor = true },
    { key = "sell.autoAll", type = "bool", default = false, vendor = true },
    { key = "sell.autoRepair", type = "bool", default = false, vendor = true },
    { key = "sell.autoCleanup", type = "bool", default = false, vendor = true },
    { key = "sell.vendorUnpriced", type = "bool", default = false, vendor = true },
    { key = "auction.chartClick", type = "bool", default = true },
    { key = "buffButton.enabled", type = "bool", default = false },
    { key = "buffButton.dock", type = "bool", default = true },
    { key = "buffButton.always", type = "bool", default = false },
    { key = "buffButton.care", type = "bool", default = true },
    { key = "buffButton.keepOnMain", type = "bool", default = false },
}

-- ---------------------------------------------------------------- helpers
local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, one in pairs(v) do out[k] = copy(one) end
    return out
end

local function parts(key)
    local list = {}
    for part in key:gmatch("[^.]+") do list[#list + 1] = part end
    return list
end

local function getPath(root, path)
    local at = root
    for i = 1, #path do
        if type(at) ~= "table" then return nil end
        at = at[path[i]]
    end
    return at
end

-- Writes value at path in root (a table this module owns). Anything that is
-- not a table on the way is replaced by one. A nil value removes the key and
-- every table left empty by that.
local function putPath(root, path, value)
    local trail, at = {}, root
    for i = 1, #path - 1 do
        local nextAt = at[path[i]]
        if type(nextAt) ~= "table" then
            if value == nil then return end
            nextAt = {}
            at[path[i]] = nextAt
        end
        trail[i] = at
        at = nextAt
    end
    at[path[#path]] = value
    if value ~= nil then return end
    for i = #path - 1, 1, -1 do
        if next(at) ~= nil then return end
        trail[i][path[i]] = nil
        at = trail[i]
    end
end

local function asTable(values)
    if type(values) == "table" then return copy(values) end
    return {}
end

-- ---------------------------------------------------------------- types
-- Each: fn(row, value) -> true, or false and why.
local TYPES = {}

function TYPES.bool(_, v)
    if type(v) == "boolean" then return true end
    return false, "expected true or false, found a " .. type(v)
end

function TYPES.number(row, v)
    if type(v) ~= "number" then return false, "expected a number, found a " .. type(v) end
    if not finite(v) then return false, "not a finite number" end
    local b = row.bounds
    if b and b.min ~= nil and v < b.min then return false, "below the lowest value allowed (" .. b.min .. ")" end
    if b and b.max ~= nil and v > b.max then return false, "above the highest value allowed (" .. b.max .. ")" end
    return true
end

function TYPES.string(_, v)
    if type(v) == "string" then return true end
    return false, "expected text, found a " .. type(v)
end

local function boundsProblem(row)
    local b = row.bounds
    if b == nil then return nil end
    if row.type ~= "number" then return "only a number has bounds" end
    if type(b) ~= "table" then return "bounds must be a table" end
    for k in pairs(b) do
        if k ~= "min" and k ~= "max" then return "bounds holds something other than min and max" end
    end
    if b.min ~= nil and not finite(b.min) then return "the lowest value is not a finite number" end
    if b.max ~= nil and not finite(b.max) then return "the highest value is not a finite number" end
    if b.min ~= nil and b.max ~= nil and b.min > b.max then return "the lowest value is above the highest" end
    return nil
end

local function rowProblem(row)
    if type(row) ~= "table" then return "the row is not a table" end
    local key = row.key
    if type(key) ~= "string" or key == "" then return "no key" end
    if key:find("^%.") or key:find("%.$") or key:find("%.%.") then return "bad key" end
    if not TYPES[row.type] then return "unknown type " .. tostring(row.type) end
    local problem = boundsProblem(row)
    if problem then return problem end
    if row.default == nil then return "no default" end
    local fits, why = TYPES[row.type](row, row.default)
    if not fits then return "the default does not fit: " .. why end
    if row.vendor ~= nil and row.vendor ~= true then return "vendor must be true or absent" end
    if row.vendor and row.type ~= "bool" then return "a vendor automation is a yes-or-no choice" end
    if row.vendor and row.default ~= false then return "a vendor automation must default to off" end
    return nil
end

-- ---------------------------------------------------------------- model
function M.New(rows)
    local model, problems = {}, {}
    local byKey, order, paths = {}, {}, {}

    if type(rows) ~= "table" then
        problems[1] = { key = "?", problem = "the rows are not a table" }
        rows = {}
    end
    for i = 1, #rows do
        local row = rows[i]
        local problem = rowProblem(row)
        if not problem and byKey[row.key] then problem = "duplicate key" end
        if not problem then
            -- A key may not sit inside another: "a.b" beside "a.b.c".
            local path = parts(row.key)
            for j = 1, #order do
                local other = paths[order[j]]
                local short, long = path, other
                if #short > #long then short, long = long, short end
                local inside = true
                for n = 1, #short do
                    if short[n] ~= long[n] then inside = false break end
                end
                if inside then problem = "the key sits inside or around " .. order[j] break end
            end
            if not problem then
                byKey[row.key] = {
                    key = row.key, type = row.type, default = row.default,
                    bounds = copy(row.bounds), vendor = row.vendor,
                }
                paths[row.key] = path
                order[#order + 1] = row.key
            end
        end
        if problem then
            local key = type(row) == "table" and type(row.key) == "string" and row.key or "?"
            problems[#problems + 1] = { key = key, problem = problem }
        end
    end

    local function fits(key, value)
        local row = byKey[key]
        if not row then return false, "unknown setting " .. tostring(key) end
        return TYPES[row.type](row, value)
    end

    function model:keys()
        return copy(order)
    end

    function model:row(key)
        return copy(byKey[key])
    end

    function model:default(key)
        local row = byKey[key]
        if not row then return nil end
        return row.default
    end

    -- Every default as a settings table. This is what a new install reads,
    -- and what an import merge may be given as the defaults of the settings.
    function model:defaults()
        local out = {}
        for i = 1, #order do putPath(out, paths[order[i]], byKey[order[i]].default) end
        return out
    end

    function model:check(key, value)
        return fits(key, value)
    end

    -- True when a value that fits is stored: the player (or an import the
    -- player ran) chose it. A default that was never stored is not explicit.
    function model:explicit(values, key)
        if not byKey[key] then return false end
        local stored = getPath(values, paths[key])
        return stored ~= nil and fits(key, stored) == true
    end

    function model:get(values, key)
        local row = byKey[key]
        if not row then return nil, "unknown setting " .. tostring(key) end
        local stored = getPath(values, paths[key])
        if stored ~= nil and fits(key, stored) then return stored end
        return row.default
    end

    function model:set(values, key, value)
        local ok, why = fits(key, value)
        if not ok then return nil, why end
        local out = asTable(values)
        putPath(out, paths[key], value)
        return out
    end

    -- Back to the default: the stored value is removed, so the key reads as
    -- its default and no longer counts as chosen. Other keys are untouched.
    function model:reset(values, key)
        if not byKey[key] then return nil, "unknown setting " .. tostring(key) end
        local out = asTable(values)
        putPath(out, paths[key], nil)
        return out
    end

    -- Takes an import's settings into the player's.
    --   A value the player already chose is kept; the import never replaces it.
    --   A value the import holds for a key the player has not chosen is
    --   stored as found, also when it equals the default: it was chosen.
    --   A key the import does not hold stays unchosen and reads as its
    --   default, so a vendor automation the import does not carry stays off.
    --   A value that does not fit its row is refused and reported.
    -- report = { taken = { key, ... }, kept = { key, ... },
    --            refused = { { key, reason }, ... } }, each in row order.
    -- Only the model's own keys are read from the import.
    function model:adopt(values, imported)
        local out = asTable(values)
        local report = { taken = {}, kept = {}, refused = {} }
        for i = 1, #order do
            local key = order[i]
            local found = getPath(imported, paths[key])
            if found ~= nil then
                local ok, why = fits(key, found)
                if not ok then
                    report.refused[#report.refused + 1] = { key = key, reason = why }
                elseif model:explicit(out, key) then
                    report.kept[#report.kept + 1] = key
                else
                    putPath(out, paths[key], found)
                    report.taken[#report.taken + 1] = key
                end
            end
        end
        return out, report
    end

    return model, problems
end

function M.Default()
    return (M.New(M.ROWS))
end
