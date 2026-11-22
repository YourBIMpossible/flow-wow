-- Import.FromFlow and Import.Stored together: what the import keeps for the
-- stored paths is what the readers read, and what the import leaves behind
-- reads as the default. Every table below is made up.
--
-- The import drops none of these paths (each has a keeping row in the map).
-- These tests hold that fact in place: if a row for one of these paths is
-- ever turned into a drop, the first test fails. The import also makes each
-- value safe on the way in, so what is stored is what the reader hands out.
local _, ns = ...

local Import = ns.Import
local S = ns.Import.Stored

local function near(t, got, want)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9,
        "expected " .. tostring(want) .. ", got " .. tostring(got))
end

local function droppedFor(result, key)
    for _, entry in ipairs(result.dropped) do
        if entry.key == key then return entry end
    end
    return nil
end

-- Flow data holding a good value at every path the readers cover.
local function goodDb()
    return {
        buffButton = {
            enabled = true, key = "F", key2 = "SHIFT-F", dock = false,
            always = true, care = false, keepOnMain = true,
            point = { "CENTER", "BOTTOMLEFT", 640, 220 }, scale = 1.1, dockScale = 0.8,
        },
        rotation = { scale = 1.2 },
        ah = { chartPoint = { "TOP", "TOP", 0, -50 }, chartClick = false },
        prof = { point = { "LEFT", "LEFT", 30, 0 } },
    }
end

-- The Flow key of every path the readers cover.
local FLOW_KEYS = {
    "buffButton.enabled", "buffButton.key", "buffButton.key2", "buffButton.dock",
    "buffButton.always", "buffButton.care", "buffButton.keepOnMain",
    "buffButton.point", "buffButton.scale", "buffButton.dockScale",
    "rotation.scale", "ah.chartPoint", "ah.chartClick", "prof.point",
}

return {
    ["stored wire: the import leaves none of the readers' paths behind"] = function(t)
        local result = Import.FromFlow(goodDb(), {})
        t.eq(result.ok, true)
        for _, key in ipairs(FLOW_KEYS) do
            t.eq(droppedFor(result, key), nil, key .. " was left behind")
        end
        for _, section in ipairs({ "buffButton", "rotation", "ah", "prof" }) do
            t.eq(droppedFor(result, section), nil, section .. " was left behind whole")
        end
    end,

    ["stored wire: every kept value reads back through its reader"] = function(t)
        local result = Import.FromFlow(goodDb(), {})
        local layout, settings = result.account.layout, result.account.settings

        local b = S.BuffButtonLayout(layout)
        t.eq(b.frame, { "CENTER", "BOTTOMLEFT", 640, 220 })
        near(t, b.scale, 1.1)
        near(t, b.dockScale, 0.8)
        near(t, S.DockScale(layout, 1.5), 0.8)
        near(t, S.RotationScale(layout), 1.2)
        t.eq(S.AuctionChart(layout), { "TOP", "TOP", 0, -50 })
        t.eq(S.AuctionChartClick(settings), false)

        local s = S.BuffButtonSettings(settings)
        t.eq(s.enabled, true)
        t.eq(s.key, "F")
        t.eq(s.key2, "SHIFT-F")
        t.eq(s.keys, { "F", "SHIFT-F" })
        t.eq(s.dock, false)
        t.eq(s.always, true)
        t.eq(s.care, false)
        t.eq(s.keepOnMain, true)
    end,

    ["stored wire: the profession point reads from the character, not the account"] = function(t)
        local result = Import.FromFlow(goodDb(), {})
        t.eq(S.ProfFrame(result.char.layout), { "LEFT", "LEFT", 30, 0 })
        t.eq(S.ProfFrame(result.account.layout), nil)
    end,

    ["stored wire: the readers hand out copies, never the imported tables"] = function(t)
        local result = Import.FromFlow(goodDb(), {})
        local layout = result.account.layout
        local frame = S.BuffButtonLayout(layout).frame
        local chart = S.AuctionChart(layout)
        t.ok(frame ~= layout.buffButton.frame, "the imported frame point itself was returned")
        t.ok(chart ~= layout.auction.chart, "the imported chart point itself was returned")
        frame[3], chart[3] = -1, -1
        t.eq(layout.buffButton.frame[3], 640)
        t.eq(layout.auction.chart[3], 0)
    end,

    ["stored wire: a value the import leaves behind as malformed reads as its default"] = function(t)
        local result = Import.FromFlow({
            buffButton = { point = "middle", scale = "big", dockScale = -1 },
            rotation = { scale = 0 },
            ah = { chartPoint = { "TOP" }, chartClick = "yes" },
            prof = { point = { "LEFT", "LEFT", "far", 0 } },
        }, {})
        t.eq(result.ok, true)
        for _, key in ipairs({ "buffButton.point", "buffButton.scale", "buffButton.dockScale",
                               "rotation.scale", "ah.chartPoint", "ah.chartClick", "prof.point" }) do
            local entry = droppedFor(result, key)
            t.ok(entry and entry.why == "malformed", key .. " is not listed as malformed")
        end
        local layout, settings = result.account.layout, result.account.settings
        local b = S.BuffButtonLayout(layout)
        t.eq(b.frame, nil)
        t.eq(b.scale, 1)
        t.eq(b.dockScale, nil)
        t.eq(S.DockScale(layout, nil), 1)
        t.eq(S.RotationScale(layout), 1)
        t.eq(S.AuctionChart(layout), nil)
        t.eq(S.AuctionChartClick(settings), true)
        t.eq(S.ProfFrame(result.char.layout), nil)
    end,

    ["stored wire: nothing imported reads as every default"] = function(t)
        local result = Import.FromFlow(nil, nil)
        local layout, settings = result.account.layout, result.account.settings
        local b = S.BuffButtonLayout(layout)
        t.eq(b.frame, nil)
        t.eq(b.scale, 1)
        t.eq(b.dockScale, nil)
        t.eq(S.RotationScale(layout), 1)
        t.eq(S.AuctionChart(layout), nil)
        t.eq(S.AuctionChartClick(settings), true)
        t.eq(S.ProfFrame(result.char.layout), nil)
        local s = S.BuffButtonSettings(settings)
        t.eq(s.enabled, false)
        t.eq(s.keys, {})
        t.eq(s.dock, true)
        t.eq(s.always, false)
        t.eq(s.care, true)
        t.eq(s.keepOnMain, false)
    end,

    -- The import stores nothing the readers would refuse or change, apart
    -- from the rounding of a size, which stays with the reader.
    ["stored wire: a size outside the limits is stored within them and reads the same"] = function(t)
        local result = Import.FromFlow({ buffButton = { scale = 9, dockScale = 0.1 }, rotation = { scale = 40 } }, {})
        local layout = result.account.layout
        t.eq(layout.buffButton.scale, 2)
        t.eq(layout.buffButton.dockScale, 0.5)
        t.eq(layout.rotation.scale, 2)
        local b = S.BuffButtonLayout(layout)
        near(t, b.scale, 2)
        near(t, b.dockScale, 0.5)
        near(t, S.RotationScale(layout), 2)
    end,

    ["stored wire: a point with an anchor no frame has is left behind and reads as no point"] = function(t)
        local result = Import.FromFlow({ ah = { chartPoint = { "MIDDLE", "TOP", 1, 2 } } }, {})
        t.eq(result.account.layout, {})
        local entry = droppedFor(result, "ah.chartPoint")
        t.ok(entry and entry.why == "malformed", "ah.chartPoint is not listed as malformed")
        t.eq(S.AuctionChart(result.account.layout), nil)
    end,

    ["stored wire: a companion switch of the wrong type is left behind and reads as its default"] = function(t)
        local result = Import.FromFlow({ buffButton = { enabled = "yes", dock = 0, key = 7 } }, {})
        t.eq(result.account.settings, {})
        for _, key in ipairs({ "buffButton.enabled", "buffButton.dock", "buffButton.key" }) do
            local entry = droppedFor(result, key)
            t.ok(entry and entry.why == "malformed", key .. " is not listed as malformed")
        end
        local s = S.BuffButtonSettings(result.account.settings)
        t.eq(s.enabled, false)
        t.eq(s.dock, true)
        t.eq(s.key, nil)
        t.eq(s.keys, {})
    end,
}
