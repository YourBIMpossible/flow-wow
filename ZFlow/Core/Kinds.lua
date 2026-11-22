-- Kinds: declared extension points. A kind names what a row must look like;
-- a row that does not fit, or reuses a key, is recorded as a problem and
-- skipped. The file registering it keeps loading.
--
--   ns:Kind{ name = "activity", row = { order = "number", plan = "function", note = "string?" } }
--   ns:Kind{ name = "slash", row = function(row, key) return ok, reason end }
--   ns:Register("activity", "profession:mining", { ... }) -> row or nil
--   ns:Get(kind, key) -> row or nil
--   ns:Each(kind) -> iterator of key, row in registration order
local _, ns = ...
ns.make = ns.make or {}

local function fits(spec, row, key)
    if type(row) ~= "table" then return false, "the row is not a table" end
    if type(spec) == "function" then
        local ok, good, reason = pcall(spec, row, key)
        if not ok then return false, "the row check failed: " .. tostring(good) end
        if not good then return false, reason or "the row was refused" end
        return true
    end
    for field, want in pairs(spec or {}) do
        local optional = want:sub(-1) == "?"
        local kind = optional and want:sub(1, -2) or want
        local v = row[field]
        if v == nil then
            if not optional then return false, "missing " .. field end
        elseif kind ~= "any" and type(v) ~= kind then
            return false, field .. " must be a " .. kind
        end
    end
    return true
end

function ns.make.kinds(k)
    local kinds = {}

    function k:Kind(def)
        local name = type(def) == "table" and def.name or nil
        local problem
        if type(name) ~= "string" or name == "" then problem = "a kind needs a name"
        elseif kinds[name] then problem = "duplicate kind"
        elseif def.row ~= nil and type(def.row) ~= "function" and type(def.row) ~= "table" then problem = "row must be a function or a field table"
        elseif type(def.row) == "table" then
            for field, want in pairs(def.row) do
                if type(field) ~= "string" or type(want) ~= "string" then problem = "a field table maps names to type names" end
            end
        end
        if problem then
            k.problems:add("kind", tostring(name), problem)
            return nil
        end
        kinds[name] = { spec = def.row, rows = {}, order = {} }
        return name
    end

    function k:Register(kind, key, row)
        local def = kinds[kind]
        local problem
        if not def then problem = "unknown kind"
        elseif type(key) ~= "string" and type(key) ~= "number" then problem = "a key must be text or a number"
        elseif def.rows[key] ~= nil then problem = "duplicate key"
        else
            local ok, reason = fits(def.spec, row, key)
            if not ok then problem = reason end
        end
        if problem then
            k.problems:add("register", tostring(kind) .. ":" .. tostring(key), problem)
            return nil
        end
        def.rows[key] = row
        def.order[#def.order + 1] = key
        return row
    end

    function k:Get(kind, key)
        local def = kinds[kind]
        return def and def.rows[key] or nil
    end

    function k:Each(kind)
        local def = kinds[kind]
        local i = 0
        return function()
            i = i + 1
            local key = def and def.order[i]
            if key == nil then return nil end
            return key, def.rows[key]
        end
    end
end
