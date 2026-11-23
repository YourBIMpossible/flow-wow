-- F-011: after an import of an old saved-data fixture no parked legacy
-- table is kept in this add-on's saved data (only the adopted values), and
-- importing the same fixture again does not grow the import record. Through
-- the real entry: Import.FromFlow, then Import.Merge. Made-up data only.
local _, ns = ...

local Import = ns.Import
local MARK = "Parked Marker Nine"

-- An old account and character table with a parked shared table in it.
local function legacyDb()
    return {
        version = 0,
        charSplit = 3,
        migrations = { split = true },
        legacyShared = { trainer = { npc = MARK }, ["nav.hidden"] = { ["q:7"] = true }, spec = { role = MARK } },
        buffButton = { enabled = true, scale = 1.1 },
    }
end

local function legacyCharDb()
    return {
        adopted = { ["nav.hidden"] = true },
        data = { ["nav.hidden"] = { ["q:101"] = true }, spec = { role = "tank" } },
    }
end

-- Every key and string anywhere under v, as "path" -> true.
local function walk(v, path, found, seen)
    if type(v) == "string" then
        if v:find(MARK, 1, true) then found[#found + 1] = path .. " = " .. v end
        return
    end
    if type(v) ~= "table" or seen[v] then return end
    seen[v] = true
    for key, value in pairs(v) do
        local name = path .. "." .. tostring(key)
        if key == "legacyShared" or key == "charSplit" or key == "migrations" then
            found[#found + 1] = name
        end
        walk(value, name, found, seen)
    end
end

local function leftovers(account, char)
    local found = {}
    walk(account, "account", found, {})
    walk(char, "char", found, {})
    return found
end

return {
    ["legacy prune: after an import no parked legacy table or value is kept, only the adopted values"] = function(t)
        local imported = Import.FromFlow(legacyDb(), legacyCharDb())
        t.eq(imported.ok, true, "the fixture imports")
        local account, char = Import.Merge(nil, nil, imported)
        t.eq(leftovers(account, char), {}, "nothing parked remains")
        t.eq(account.settings.buffButton ~= nil, true, "an adopted value is there")
        -- The record names what was left behind, by path, and holds none of it.
        local record = account.imports[#account.imports]
        t.eq(type(record), "table")
        for _, entry in ipairs(record.dropped or {}) do
            t.eq(type(entry.key), "string")
            for _, field in pairs(entry) do
                t.ok(type(field) ~= "table", "a dropped entry holds no copied table: " .. tostring(entry.key))
            end
        end
    end,

    ["legacy prune: importing the same fixture a second time does not grow the import record"] = function(t)
        local account, char = Import.Merge(nil, nil, Import.FromFlow(legacyDb(), legacyCharDb()))
        t.eq(#account.imports, 1)
        local again, againChar = Import.Merge(account, char, Import.FromFlow(legacyDb(), legacyCharDb()))
        t.eq(#again.imports, 1, "the same import is recorded once")
        t.eq(again.imports[1].merge.added, 0, "the kept record is the newest run's")
        local third = Import.Merge(again, againChar, Import.FromFlow(legacyDb(), legacyCharDb()))
        t.eq(#third.imports, 1)
        t.eq(leftovers(third, againChar), {}, "still nothing parked")
    end,

    ["legacy prune: the import record keeps at most Import.IMPORTS_MAX records, newest last"] = function(t)
        t.ok(type(Import.IMPORTS_MAX) == "number" and Import.IMPORTS_MAX >= 1, "a bound")
        if type(Import.IMPORTS_MAX) ~= "number" then return end
        local account = { schema = 1, settings = {}, layout = {}, imports = {},
            learned = { places = {}, flights = {}, prices = {}, facts = {}, fights = {} } }
        for i = 1, Import.IMPORTS_MAX + 4 do
            account.imports[i] = { source = "Older", sourceVersion = i, importer = 1 }
        end
        local merged = Import.Merge(account, nil, Import.FromFlow(legacyDb(), legacyCharDb()))
        t.eq(#merged.imports, Import.IMPORTS_MAX)
        t.eq(merged.imports[#merged.imports].source, "Flow", "the newest is kept, last")
        t.eq(merged.imports[1].sourceVersion, 6, "the oldest went first")
    end,
}
