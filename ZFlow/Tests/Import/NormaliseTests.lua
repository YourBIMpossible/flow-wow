-- Import.FromFlow makes safe what it stores, so the stored value is already
-- one the readers accept: sizes are held within the readers' limits, a
-- position keeps only anchors a frame has, and the companion button's
-- switches and keys are checked by type. Every table below is made up.
local _, ns = ...

local Import = ns.Import
local S = ns.Import.Stored

local ANCHORS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local SIZE_KEYS = { "buffButton.scale", "buffButton.dockScale", "rotation.scale" }
local SWITCHES = { "enabled", "dock", "always", "care", "keepOnMain" }

local function entryFor(list, key)
    for _, entry in ipairs(list) do
        if entry.key == key then return entry end
    end
    return nil
end

-- Flow data with one value at "section.key".
local function dbWith(path, value)
    local section, key = path:match("^([^.]+)%.(.+)$")
    return { [section] = { [key] = value } }
end

local function getPath(root, path)
    local at = root
    for part in path:gmatch("[^.]+") do
        if type(at) ~= "table" then return nil end
        at = at[part]
    end
    return at
end

local function rowFor(key)
    for _, row in ipairs(Import.flowMap) do
        if row[1] == key then return row end
    end
    return nil
end

-- What the import stored for a Flow key, wherever its row lands.
local function storedFor(result, key)
    local row = rowFor(key)
    return getPath(row.char and result.char or result.account, row.to)
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, one in pairs(v) do out[k] = copy(one) end
    return out
end

return {
    -- (a) sizes ---------------------------------------------------------
    ["normalise: a size above the limit is stored at the limit"] = function(t)
        for _, key in ipairs(SIZE_KEYS) do
            local result = Import.FromFlow(dbWith(key, 9), {})
            t.eq(storedFor(result, key), S.SCALE_MAX, key)
            t.eq(entryFor(result.dropped, key), nil, key .. " was left behind")
        end
    end,

    ["normalise: a size below the limit is stored at the limit"] = function(t)
        for _, key in ipairs(SIZE_KEYS) do
            local result = Import.FromFlow(dbWith(key, 0.1), {})
            t.eq(storedFor(result, key), S.SCALE_MIN, key)
            t.eq(entryFor(result.dropped, key), nil, key .. " was left behind")
        end
    end,

    ["normalise: a size within the limits is stored exactly as Flow had it"] = function(t)
        for _, key in ipairs(SIZE_KEYS) do
            for _, size in ipairs({ 0.5, 0.8, 1, 1.1, 1.23, 2 }) do
                local result = Import.FromFlow(dbWith(key, size), {})
                t.eq(storedFor(result, key), size, key)
                t.eq(#result.adjusted, 0, key .. " at " .. size .. " was reported as changed")
            end
        end
    end,

    ["normalise: every stored size reads as the reader would have read the original"] = function(t)
        for _, key in ipairs(SIZE_KEYS) do
            for _, size in ipairs({ 0.01, 0.1, 0.49, 0.5, 0.74, 1, 1.37, 2, 2.01, 9, 40, 1e9 }) do
                local stored = storedFor(Import.FromFlow(dbWith(key, size), {}), key)
                t.ok(stored >= S.SCALE_MIN and stored <= S.SCALE_MAX, key .. ": " .. size .. " was stored outside the limits")
                t.eq(S.Scale(stored), S.Scale(size), key .. " at " .. size)
            end
        end
    end,

    ["normalise: a changed size is listed with what it was and what it became"] = function(t)
        local result = Import.FromFlow({ buffButton = { scale = 9, dockScale = 0.1 }, rotation = { scale = 1.2 } }, {})
        t.eq(#result.adjusted, 2)
        local big = entryFor(result.adjusted, "buffButton.scale")
        t.ok(big ~= nil, "the size above the limit is not listed")
        t.eq(big.from, 9)
        t.eq(big.to, 2)
        t.ok(type(big.reason) == "string" and big.reason ~= "", "no reason given")
        local small = entryFor(result.adjusted, "buffButton.dockScale")
        t.ok(small ~= nil, "the size below the limit is not listed")
        t.eq(small.from, 0.1)
        t.eq(small.to, 0.5)
        t.eq(entryFor(result.adjusted, "rotation.scale"), nil, "a size within the limits is listed as changed")
        t.eq(result.record.counts.adjusted, 2)
        t.eq(result.record.counts.malformed, 0)
    end,

    ["normalise: the changed list is sorted by key"] = function(t)
        local result = Import.FromFlow({ rotation = { scale = 40 }, buffButton = { scale = 9, dockScale = 0.1 } }, {})
        local keys = {}
        for i, entry in ipairs(result.adjusted) do keys[i] = entry.key end
        t.eq(keys, { "buffButton.dockScale", "buffButton.scale", "rotation.scale" })
    end,

    ["normalise: a size that is no size is still left behind as malformed"] = function(t)
        for _, key in ipairs(SIZE_KEYS) do
            for _, bad in ipairs({ 0, -1, "big", true, {}, math.huge, -math.huge, 0 / 0 }) do
                local result = Import.FromFlow(dbWith(key, bad), {})
                local entry = entryFor(result.dropped, key)
                t.ok(entry and entry.why == "malformed", key .. " is not listed as malformed")
                t.eq(storedFor(result, key), nil, key .. " was stored")
                t.eq(#result.adjusted, 0, key .. " was reported as changed")
            end
        end
    end,

    ["normalise: nothing imported and a refused import both have an empty changed list"] = function(t)
        t.eq(Import.FromFlow(nil, nil).adjusted, {})
        local refused = Import.FromFlow("nonsense", nil)
        t.eq(refused.ok, false)
        t.eq(refused.adjusted, {})
    end,

    -- (b) anchors -------------------------------------------------------
    ["normalise: every position row leaves behind an anchor no frame has"] = function(t)
        local rows = 0
        for _, row in ipairs(Import.flowMap) do
            if row.as == "point" then
                rows = rows + 1
                local key = row[1]
                for _, point in ipairs({
                    { "MIDDLE", "TOP", 1, 2 }, { "TOP", "MIDDLE", 1, 2 }, { "center", "CENTER", 1, 2 },
                    { "", "TOP", 1, 2 }, { "TOP LEFT", "TOP", 1, 2 },
                }) do
                    local result = Import.FromFlow(dbWith(key, point), {})
                    local entry = entryFor(result.dropped, key)
                    t.ok(entry and entry.why == "malformed", key .. " with " .. point[1] .. "/" .. point[2] .. " is not listed as malformed")
                    t.eq(storedFor(result, key), nil, key .. " was stored")
                end
            end
        end
        t.eq(rows, 15, "the position rows of the mapping")
    end,

    ["normalise: every position row keeps each of the nine anchors"] = function(t)
        local rows = 0
        t.eq(#ANCHORS, 9, "the test does not hold nine anchors")
        for _, row in ipairs(Import.flowMap) do
            if row.as == "point" then
                rows = rows + 1
                local key = row[1]
                for i, anchor in ipairs(ANCHORS) do
                    local other = ANCHORS[#ANCHORS + 1 - i]
                    local result = Import.FromFlow(dbWith(key, { anchor, other, -3, 4 }), {})
                    t.eq(storedFor(result, key), { anchor, other, -3, 4 }, key .. " with " .. anchor)
                    t.eq(entryFor(result.dropped, key), nil, key .. " with " .. anchor .. " was left behind")
                end
            end
        end
        t.eq(rows, 15, "the position rows of the mapping")
    end,

    ["normalise: every kept position reads back through the reader unchanged"] = function(t)
        local rows = 0
        for _, row in ipairs(Import.flowMap) do
            if row.as == "point" then
                rows = rows + 1
                local stored = storedFor(Import.FromFlow(dbWith(row[1], { "TOPLEFT", "BOTTOMRIGHT", 12, -7 }), {}), row[1])
                t.ok(stored ~= nil, row[1] .. " was not stored, so nothing was read back")
                t.eq(S.Point(stored), stored, row[1])
            end
        end
        t.eq(rows, 15, "the position rows of the mapping")
    end,

    ["normalise: an arrow place with an anchor no frame has is left out, the others kept"] = function(t)
        -- Only the profession arrow's place is read from nav.arrows.points
        -- (the quest arrow's comes from nav.point), so the kept place is the
        -- quest arrow's, beside the refused profession place.
        local result = Import.FromFlow({ nav = {
            point = { "TOP", "TOP", 3, 4 },
            arrows = { points = { professions = { "MIDDLE", "TOP", 1, 2 } } },
        } }, {})
        t.eq(result.account.layout.arrows, { points = { quest = { "TOP", "TOP", 3, 4 } } })
        t.eq(result.record.counts.malformed, 1)
        local entry
        for _, e in ipairs(result.dropped) do
            if e.key:find("professions", 1, true) then entry = e end
        end
        t.ok(entry and entry.why == "malformed", "the profession place is listed as malformed")
    end,

    -- (c) the companion button's rows -------------------------------------
    ["normalise: the companion button's rows each have a kind"] = function(t)
        for _, name in ipairs(SWITCHES) do
            t.eq(rowFor("buffButton." .. name).as, "bool", name)
        end
        t.eq(rowFor("buffButton.key").as, "key")
        t.eq(rowFor("buffButton.key2").as, "key")
        for _, key in ipairs(SIZE_KEYS) do t.eq(rowFor(key).as, "size", key) end
    end,

    ["normalise: a companion switch that is not true or false is left behind and listed"] = function(t)
        for _, name in ipairs(SWITCHES) do
            local key = "buffButton." .. name
            for _, bad in ipairs({ "yes", 0, 1, {}, "" }) do
                local result = Import.FromFlow(dbWith(key, bad), {})
                local entry = entryFor(result.dropped, key)
                t.ok(entry and entry.why == "malformed", key .. " is not listed as malformed")
                t.ok(type(entry.reason) == "string" and entry.reason ~= "", key .. " has no reason")
                t.eq(result.account.settings, {}, key .. " was stored")
            end
        end
    end,

    ["normalise: a companion switch keeps true and keeps false"] = function(t)
        for _, name in ipairs(SWITCHES) do
            local key = "buffButton." .. name
            for _, value in ipairs({ true, false }) do
                local result = Import.FromFlow(dbWith(key, value), {})
                t.eq(result.account.settings.buffButton, { [name] = value }, key)
                t.eq(entryFor(result.dropped, key), nil, key .. " was left behind")
            end
        end
    end,

    ["normalise: a companion key that is not a key binding is left behind and listed"] = function(t)
        for _, key in ipairs({ "buffButton.key", "buffButton.key2" }) do
            for _, bad in ipairs({ 7, true, false, {}, "" }) do
                local result = Import.FromFlow(dbWith(key, bad), {})
                local entry = entryFor(result.dropped, key)
                t.ok(entry and entry.why == "malformed", key .. " is not listed as malformed")
                t.eq(result.account.settings, {}, key .. " was stored")
            end
        end
    end,

    ["normalise: a companion key binding is kept as written"] = function(t)
        local result = Import.FromFlow({ buffButton = { key = "F", key2 = "SHIFT-F" } }, {})
        t.eq(result.account.settings.buffButton, { key = "F", key2 = "SHIFT-F" })
        t.eq(result.record.counts.malformed, 0)
    end,

    ["normalise: one bad companion value does not cost the good ones beside it"] = function(t)
        local result = Import.FromFlow({ buffButton = {
            enabled = "yes", key = "F", key2 = 7, dock = false, always = 1, care = false, keepOnMain = true,
        } }, {})
        t.eq(result.account.settings.buffButton, { key = "F", dock = false, care = false, keepOnMain = true })
        t.eq(result.record.counts.malformed, 3)
        local s = S.BuffButtonSettings(result.account.settings)
        t.eq(s.enabled, false)
        t.eq(s.keys, { "F" })
        t.eq(s.dock, false)
        t.eq(s.always, false)
        t.eq(s.care, false)
        t.eq(s.keepOnMain, true)
    end,

    -- non-destructive and versioned -------------------------------------
    ["normalise: the tables handed in are left exactly as they were"] = function(t)
        local db = {
            buffButton = { scale = 9, dockScale = 0.1, point = { "MIDDLE", "TOP", 1, 2 }, enabled = "yes", key = 7, dock = false },
            rotation = { scale = 40, point = { "CENTER", "CENTER", 0, -200 } },
            ah = { chartPoint = { "TOP", "NOWHERE", 0, 0 } },
        }
        local charDb = { data = { ["prof.point"] = { "LEFT", "ELSEWHERE", 30, 0 } } }
        local dbBefore, charBefore = copy(db), copy(charDb)
        local result = Import.FromFlow(db, charDb)
        t.eq(result.ok, true)
        t.eq(db, dbBefore)
        t.eq(charDb, charBefore)
        t.eq(type(result.account.layout.rotation.frame), "table", "no position was stored")
        t.ok(result.account.layout.rotation.frame ~= db.rotation.point, "the stored position is Flow's own table")
    end,

    ["normalise: the record carries the importer version, and it moved on from 1"] = function(t)
        local result = Import.FromFlow({ rotation = { scale = 40 } }, {})
        t.ok(type(Import.flowImporterVersion) == "number" and Import.flowImporterVersion >= 2,
            "the importer version did not move on when what it stores changed")
        t.eq(result.record.importer, Import.flowImporterVersion)
        t.eq(result.account.imports[1].importer, Import.flowImporterVersion)
        t.eq(result.account.imports[1].counts.adjusted, 1)
    end,
}
