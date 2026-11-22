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

-- The shipped settings model. Looked up when a test runs.
local function shipped()
    return ns.Settings.Model.Default()
end

-- A vendor automation on in Flow, one off, and two plain choices.
local function sellDb()
    return {
        sell = { autoJunk = true, autoRepair = true, autoAll = false },
        ah = { chartClick = true },
        buffButton = { enabled = true, dock = false },
    }
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

    -- ------------------------------------------------------------ adopt
    ["adopt: a value Flow held is stored as found and counts as chosen"] = function(t)
        local model = shipped()
        local out, report = S.Adopt(nil, Import.FromFlow(sellDb(), {}))
        t.eq(report.ok, true)
        t.eq(out.buffButton, { enabled = true, dock = false })
        t.eq(model:get(out, "buffButton.enabled"), true)
        t.eq(model:get(out, "buffButton.dock"), false)
        t.ok(model:explicit(out, "buffButton.enabled"), "buffButton.enabled is not chosen")
        t.ok(model:explicit(out, "buffButton.dock"), "buffButton.dock is not chosen")
    end,

    ["adopt: a value Flow held that equals the default is still stored"] = function(t)
        local model = shipped()
        t.eq(model:default("auction.chartClick"), true)
        local out = (S.Adopt(nil, Import.FromFlow(sellDb(), {})))
        t.eq(out.auction, { chartClick = true })
        t.ok(model:explicit(out, "auction.chartClick"), "auction.chartClick is not chosen")
    end,

    ["adopt: a value Flow did not hold is not stored and reads as the default"] = function(t)
        local model = shipped()
        local out, report = S.Adopt(nil, Import.FromFlow({}, {}))
        t.eq(report.ok, true)
        t.eq(out, {})
        t.eq(report.taken, {})
        for _, key in ipairs(model:keys()) do
            t.ok(not model:explicit(out, key), key .. " counts as chosen")
            t.eq((model:get(out, key)), model:default(key), key)
        end
    end,

    ["adopt: every vendor automation is off when Flow held none"] = function(t)
        local model = shipped()
        local out = (S.Adopt(nil, Import.FromFlow({ buffButton = { enabled = true } }, {})))
        t.eq(out.sell, nil)
        local seen = 0
        for _, key in ipairs(model:keys()) do
            if model:row(key).vendor then
                seen = seen + 1
                t.eq((model:get(out, key)), false, key)
            end
        end
        t.eq(seen, 5)
    end,

    ["adopt: a vendor automation Flow had on stays off until that one is confirmed"] = function(t)
        local model = shipped()
        local out, report = S.Adopt(nil, Import.FromFlow(sellDb(), {}))
        t.eq(out.sell, { autoAll = false })
        t.eq((model:get(out, "sell.autoJunk")), false)
        t.eq((model:get(out, "sell.autoRepair")), false)
        t.ok(not model:explicit(out, "sell.autoJunk"), "sell.autoJunk counts as chosen")
        t.eq(report.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" })
        t.eq(report.vendorConfirmed, {})
    end,

    ["adopt: a vendor automation Flow had off is stored off"] = function(t)
        local model = shipped()
        local out = (S.Adopt(nil, Import.FromFlow(sellDb(), {})))
        t.eq((model:get(out, "sell.autoAll")), false)
        t.ok(model:explicit(out, "sell.autoAll"), "sell.autoAll is not chosen")
    end,

    ["adopt: confirming one vendor automation switches on that one only"] = function(t)
        local model = shipped()
        local out, report = S.Adopt(nil, Import.FromFlow(sellDb(), {}), { ["sell.autoRepair"] = true })
        t.eq(out.sell, { autoAll = false, autoRepair = true })
        t.eq((model:get(out, "sell.autoJunk")), false)
        t.eq(report.vendorConfirmed, { "sell.autoRepair" })
        t.eq(report.vendorLeftOff, { "sell.autoJunk" })
    end,

    ["adopt: only a true confirms, and only what Flow had on"] = function(t)
        local result = Import.FromFlow(sellDb(), {})
        local out, report = S.Adopt(nil, result,
            { ["sell.autoJunk"] = "yes", ["sell.autoRepair"] = 1, ["sell.autoCleanup"] = true, ["sell.autoAll"] = true })
        t.eq(out.sell, { autoAll = false })
        t.eq(report.vendorConfirmed, {})
        t.eq(report.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" })
    end,

    ["adopt: a vendor automation written on in the settings is gated the same way"] = function(t)
        local result = Import.FromFlow({}, {})
        result.account.settings = { sell = { autoCleanup = true, vendorUnpriced = true } }
        local out, report = S.Adopt(nil, result, { ["sell.vendorUnpriced"] = true })
        t.eq(out.sell, { vendorUnpriced = true })
        t.eq(report.vendorLeftOff, { "sell.autoCleanup" })
        t.eq(report.vendorConfirmed, { "sell.vendorUnpriced" })
    end,

    ["adopt: a value the player already chose is kept"] = function(t)
        local mine = {
            auction = { chartClick = false },
            buffButton = { enabled = false, key = "G" },
            sell = { autoRepair = false, autoAll = true },
        }
        local out, report = S.Adopt(mine, Import.FromFlow(sellDb(), {}), { ["sell.autoRepair"] = true })
        t.eq(out.auction.chartClick, false)
        t.eq(out.buffButton.enabled, false)
        t.eq(out.buffButton.key, "G", "a setting with no row was lost")
        t.eq(out.sell.autoRepair, false)
        t.eq(out.sell.autoAll, true)
        t.eq(out.buffButton.dock, false, "an unchosen setting was not taken")
        t.eq(report.kept, { "sell.autoAll", "sell.autoRepair", "auction.chartClick", "buffButton.enabled" })
        t.eq(report.taken, { "buffButton.dock" })
    end,

    ["adopt: neither table given is changed"] = function(t)
        local mine = { auction = { chartClick = false } }
        local result = Import.FromFlow(sellDb(), {})
        local confirmed = { ["sell.autoRepair"] = true }
        local before = Import.FromFlow(sellDb(), {})
        local out = (S.Adopt(mine, result, confirmed))
        t.eq(mine, { auction = { chartClick = false } })
        t.eq(result.account.settings, before.account.settings)
        t.eq(result.vendorToConfirm, before.vendorToConfirm)
        t.eq(confirmed, { ["sell.autoRepair"] = true })
        t.ok(out ~= mine, "the settings given were handed back")
        out.auction.chartClick = true
        t.eq(mine.auction.chartClick, false)
    end,

    ["adopt: landing the same import again changes nothing"] = function(t)
        local confirmed = { ["sell.autoRepair"] = true }
        local once = (S.Adopt(nil, Import.FromFlow(sellDb(), {}), confirmed))
        local twice, report = S.Adopt(once, Import.FromFlow(sellDb(), {}), confirmed)
        t.eq(twice, once)
        t.eq(report.taken, {})
        t.eq(report.refused, {})
        local thrice = (S.Adopt(twice, Import.FromFlow(sellDb(), {})))
        t.eq(thrice, once, "a confirmed automation was switched off by a later import")
    end,

    ["adopt: an import without the confirmation, then with it, switches the one on"] = function(t)
        local first = (S.Adopt(nil, Import.FromFlow(sellDb(), {})))
        local second = (S.Adopt(first, Import.FromFlow(sellDb(), {}), { ["sell.autoJunk"] = true }))
        t.eq(second.sell, { autoAll = false, autoJunk = true })
    end,

    ["adopt: a value that does not fit its row is refused and reported"] = function(t)
        local result = Import.FromFlow({}, {})
        result.account.settings = { buffButton = { enabled = "yes", dock = false } }
        local out, report = S.Adopt(nil, result)
        t.eq(out, { buffButton = { dock = false } })
        t.eq(#report.refused, 1)
        t.eq(report.refused[1].key, "buffButton.enabled")
        t.ok(type(report.refused[1].reason) == "string", "no reason given")
    end,

    ["adopt: an import that did not succeed lands nothing"] = function(t)
        local mine = { auction = { chartClick = false } }
        local out, report = S.Adopt(mine, { ok = false, reason = "no Flow data" })
        t.eq(report.ok, false)
        t.ok(type(report.reason) == "string" and report.reason ~= "", "no reason given")
        t.eq(out, mine)
        t.ok(out ~= mine, "the settings given were handed back")
        local none, why = S.Adopt(nil, nil)
        t.eq(none, {})
        t.eq(why.ok, false)
        t.eq(why.taken, {})
    end,

    ["adopt: settings that are not a table are treated as none"] = function(t)
        local out, report = S.Adopt("broken", Import.FromFlow(sellDb(), {}))
        t.eq(report.ok, true)
        t.eq(out.buffButton, { enabled = true, dock = false })
    end,

    ["adopt: a model handed in is the one used"] = function(t)
        local model = (ns.Settings.Model.New({
            { key = "buffButton.enabled", type = "bool", default = false },
        }))
        local out, report = S.Adopt(nil, Import.FromFlow(sellDb(), {}), { ["sell.autoRepair"] = true }, model)
        t.eq(out, { buffButton = { enabled = true } })
        t.eq(report.taken, { "buffButton.enabled" })
        t.eq(report.vendorConfirmed, {})
        t.eq(report.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" })
    end,
}
