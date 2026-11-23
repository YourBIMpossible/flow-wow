local _, ns = ...
-- SG-R2 (MyBuddy, lead section 249): the import of legacy Flow settings is
-- unchanged by the settings regrouping (N56). On the whole add-on: a
-- made-up legacy saved table holding a value for every legacy key that
-- lands on a settings row of the add-on is imported (Import.FromFlow, then
-- Import.Merge with every vendor automation confirmed) and saved; a second
-- add-on loads those saved tables, and every such row reads the legacy
-- value back, at the scope the mapping names. The regrouping moved rows
-- between topics only: a key, a scope or a value that moved fails here.
-- Every name and value is made up.
local tests = {}

local function boot(account, char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, char or {})
    c.setVersion("0.1.0")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function put(into, dotted, value)
    local at = into
    local parts = {}
    for part in dotted:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        if type(at[parts[i]]) ~= "table" then at[parts[i]] = {} end
        at = at[parts[i]]
    end
    at[parts[#parts]] = value
end

-- A value of the row's own kind that is not its default.
local function other(row)
    if row.type == "bool" then return not row.default end
    if row.type == "number" then
        if row.max ~= nil and row.max ~= row.default then return row.max end
        if row.min ~= nil and row.min ~= row.default then return row.min end
        return (row.default or 0) + 1
    end
    if row.type == "choice" then
        for _, v in ipairs(row.choices) do
            if v ~= row.default then return v end
        end
    end
    return nil
end

-- Guards behaviour that holds today: green before and after, by design.
tests["SG-R2: after the settings regrouping every legacy settings key lands on the same key, scope and value (whole add-on)"] = function(t)
    local _, first = boot()
    local map
    if type(first.Import) == "table" then map = first.Import.flowMap end
    t.ok(type(map) == "table", "the add-on has the import mapping")
    if type(map) ~= "table" then return end

    local flowDb, want, confirmed = {}, {}, {}
    for _, entry in ipairs(map) do
        local to, row
        if type(entry.to) == "string" then to = entry.to:match("^settings%.(.+)$") end
        if to then row = first.settings:row(to) end
        local plain = entry.as == nil or entry.as == "bool"
        if row and plain and not entry.drop and not entry.yield
            and (row.type == "bool" or row.type == "number" or row.type == "choice") then
            local value = other(row)
            if value ~= nil then
                put(flowDb, entry[1], value)
                want[#want + 1] = { flow = entry[1], key = to, scope = entry.char and "char" or "account", value = value }
                if entry.vendor then confirmed[entry[1]] = true end
            end
        end
    end
    t.ok(#want >= 2, "legacy keys that land on a settings row: " .. #want)

    local result = first.Import.FromFlow(flowDb, {})
    t.eq(result.ok, true, "the legacy table is read")
    local account, char = first.Import.Merge({}, {}, result, nil, confirmed, first.Settings.Model.Default())
    t.ok(type(account) == "table" and type(char) == "table", "and merged")
    if type(account) ~= "table" or type(char) ~= "table" then return end

    local _, second = boot(account, char)
    for _, w in ipairs(want) do
        local row = second.settings:row(w.key)
        t.eq(row and row.scope, w.scope, w.flow .. " lands at the scope the mapping names")
        t.eq(second.settings:get(w.key), w.value, w.flow .. " reads back as " .. w.key .. " with its value")
    end

    -- Two pinned by name, so a renamed key fails even if the loop finds less.
    local pinned = { ["nav.crossings"] = "account", ["nav.zoneFirst"] = "account" }
    for key, scope in pairs(pinned) do
        local found
        for _, w in ipairs(want) do
            if w.key == key then found = w end
        end
        t.ok(found ~= nil and found.scope == scope, key .. " is still mapped, " .. scope)
    end
end

return tests
