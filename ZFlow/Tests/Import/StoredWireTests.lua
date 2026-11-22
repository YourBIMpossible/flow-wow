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
        t.eq(#FLOW_KEYS, 14, "the list of reader paths changed size")
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
        t.eq(type(frame), "table", "no frame point was read")
        t.eq(type(chart), "table", "no chart point was read")
        t.eq(type(layout.buffButton.frame), "table", "no frame point was imported")
        t.eq(type(layout.auction.chart), "table", "no chart point was imported")
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
        -- 12 since L6-A added vendor.list (lead); 16 with the fork rows and T-E spec.role.
        t.eq(#model:keys(), 16, "the shipped model changed its number of rows")
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

    -- ------------------------------------------------- adopt beside merge
    ["adopt and merge: the same input gives the same settings"] = function(t)
        local model = shipped()
        local function mine()
            return {
                auction = { chartClick = true },
                buffButton = { enabled = "yes", care = false },
                sell = { autoJunk = false },
            }
        end
        local function flow()
            local db = sellDb()
            db.ah.chartClick = false
            db.buffButton.care = true
            return db
        end
        local confirmed = { ["sell.autoJunk"] = true, ["sell.autoRepair"] = true }
        local adopted = (S.Adopt(mine(), Import.FromFlow(flow(), {}), confirmed))
        local merged = (Import.Merge({ settings = mine() }, nil, Import.FromFlow(flow(), {}),
            { account = { settings = model:defaults() } }, confirmed)).settings
        local keys = model:keys()
        t.ok(type(keys) == "table" and #keys > 0, "the shipped model names no setting, so nothing was compared")
        for _, key in ipairs(keys) do
            t.eq((model:get(merged, key)), (model:get(adopted, key)), key)
            t.eq(model:explicit(merged, key), model:explicit(adopted, key), key .. " chosen")
        end
        t.eq((model:get(merged, "auction.chartClick")), true, "a stored value equal to the default was overwritten")
        t.eq((model:get(merged, "sell.autoJunk")), false, "a stored off was switched on by a confirmation")
        t.eq((model:get(merged, "sell.autoRepair")), true, "a confirmed automation with nothing stored is off")
        t.eq((model:get(merged, "buffButton.enabled")), true, "a stored value of the wrong type was kept")
        t.eq((model:get(merged, "buffButton.care")), false, "a stored choice was overwritten")
        t.eq((model:get(merged, "buffButton.dock")), false, "a value with nothing stored was not taken")

        -- The same with a model of the test's own that bounds a number: a
        -- stored number outside the bounds is the right type and still no
        -- choice, for the adopt and for the merge alike.
        local custom, problems = ns.Settings.Model.New({
            { key = "nav.pathAlpha", type = "number", default = 1, bounds = { min = 0, max = 1 } },
            { key = "nav.pathMotion", type = "number", default = 1, bounds = { min = 0, max = 4 } },
            { key = "nav.mapLines", type = "bool", default = true },
            { key = "buffButton.enabled", type = "bool", default = false },
        })
        t.eq(problems, {})
        local function mineToo()
            return {
                nav = { pathAlpha = 7, pathMotion = 3, mapLines = "yes" },
                buffButton = { enabled = false },
            }
        end
        local function flowToo()
            return { nav = { pathAlpha = 0.5, pathMotion = 2, mapLines = false }, buffButton = { enabled = true } }
        end
        local adoptedToo = (S.Adopt(mineToo(), Import.FromFlow(flowToo(), {}), nil, custom))
        local mergedToo = (Import.Merge({ settings = mineToo() }, nil, Import.FromFlow(flowToo(), {}),
            { account = { settings = custom:defaults() } }, nil, custom)).settings
        for _, key in ipairs(custom:keys()) do
            t.eq((custom:get(mergedToo, key)), (custom:get(adoptedToo, key)), key)
            t.eq(custom:explicit(mergedToo, key), custom:explicit(adoptedToo, key), key .. " chosen")
        end
        t.eq((custom:get(mergedToo, "nav.pathAlpha")), 0.5, "a stored number outside the bounds was kept")
        t.eq((custom:get(mergedToo, "nav.pathMotion")), 3, "a stored number inside the bounds was overwritten")
        t.eq((custom:get(mergedToo, "nav.mapLines")), false, "a stored value of the wrong type was kept")
        t.eq((custom:get(mergedToo, "buffButton.enabled")), false, "a stored choice was overwritten")
    end,

    -- ------------------------------------------------------- import gate
    ["gate: the merge and the adopt go through the one gate"] = function(t)
        t.eq(type(Import.VendorGate), "function")
        local result = Import.FromFlow(sellDb(), {})
        local before = Import.FromFlow(sellDb(), {})
        local confirmed = { ["sell.autoRepair"] = true }
        local account, on, off = Import.VendorGate(result.account, result.vendorToConfirm, confirmed)
        t.eq(on, { { key = "sell.autoRepair", to = "settings.sell.autoRepair" } })
        t.eq(off, { { key = "sell.autoJunk", to = "settings.sell.autoJunk" } })
        t.eq(account.settings.sell.autoRepair, true)
        t.eq(account.settings.sell.autoJunk, nil)
        t.eq(result.account, before.account, "the import was changed")
        t.eq(result.vendorToConfirm, before.vendorToConfirm)
        t.eq(confirmed, { ["sell.autoRepair"] = true })

        local _, _, merged = Import.Merge({}, {}, result, nil, confirmed)
        local _, adopted = S.Adopt(nil, result, confirmed)
        t.eq(merged.vendorConfirmed, { "sell.autoRepair" })
        t.eq(merged.vendorLeftOff, { "sell.autoJunk" })
        t.eq(adopted.vendorConfirmed, merged.vendorConfirmed)
        t.eq(adopted.vendorLeftOff, merged.vendorLeftOff)
    end,

    ["gate: the gate takes no account data and no list without raising"] = function(t)
        local account, on, off = Import.VendorGate(nil, nil, nil)
        t.eq(account, {})
        t.eq(on, {})
        t.eq(off, {})
        local written = { settings = { sell = { autoCleanup = true } } }
        account, on, off = Import.VendorGate(written, "broken", { ["sell.autoCleanup"] = "yes" })
        t.eq(account, { settings = {} })
        t.eq(on, {})
        t.eq(off, { { key = "sell.autoCleanup", to = "settings.sell.autoCleanup" } })
        t.eq(written, { settings = { sell = { autoCleanup = true } } })
    end,

    ["gate: the adopt asks the shared gate and keeps none of its own"] = function(t)
        local result = Import.FromFlow(sellDb(), {})
        local real = Import.VendorGate
        local calls = 0
        Import.VendorGate = function(account, listed)
            calls = calls + 1
            return real(account, listed, nil)
        end
        local ok, out, report = pcall(S.Adopt, nil, result, { ["sell.autoRepair"] = true })
        Import.VendorGate = real
        t.ok(ok, tostring(out))
        t.eq(calls, 1)
        t.eq(out.sell, { autoAll = false })
        t.eq(report.vendorConfirmed, {})
        t.eq(report.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" })
    end,

    ["gate: an on with no confirmation never lands, however it reached the settings"] = function(t)
        local result = Import.FromFlow({}, {})
        result.account.settings = { sell = {
            autoJunk = true, autoAll = true, autoRepair = true, autoCleanup = true, vendorUnpriced = true,
        } }
        result.vendorToConfirm = nil
        local tries = { {}, { ["sell.autoJunk"] = "yes" }, { ["settings.sell.autoJunk"] = true }, { sell = { autoJunk = true } } }
        for i = 0, #tries do
            local out, report = S.Adopt(nil, result, tries[i])
            t.eq(out, {}, "try " .. i)
            t.eq(report.taken, {}, "try " .. i)
            t.eq(report.vendorConfirmed, {}, "try " .. i)
            t.eq(report.vendorLeftOff,
                { "sell.autoAll", "sell.autoCleanup", "sell.autoJunk", "sell.autoRepair", "sell.vendorUnpriced" },
                "try " .. i)
        end
    end,

    ["gate: a vendor row Flow has no key for is held off by the model"] = function(t)
        local model = (ns.Settings.Model.New({
            { key = "extra.autoBuy", type = "bool", default = false, vendor = true },
        }))
        local result = Import.FromFlow({}, {})
        result.account.settings = { extra = { autoBuy = true } }
        local out, report = S.Adopt(nil, result, { ["extra.autoBuy"] = true }, model)
        t.eq(out, {})
        t.eq(report.taken, {})
        t.eq(report.vendorConfirmed, {})
        t.eq(report.vendorLeftOff, { "extra.autoBuy" })
    end,

    ["gate: a confirmed automation the player had already chosen is not listed as confirmed"] = function(t)
        local mine = { sell = { autoRepair = false } }
        local out, report = S.Adopt(mine, Import.FromFlow(sellDb(), {}),
            { ["sell.autoRepair"] = true, ["sell.autoJunk"] = true })
        t.eq(out.sell, { autoAll = false, autoJunk = true, autoRepair = false })
        t.eq(report.vendorConfirmed, { "sell.autoJunk" })
        t.eq(report.vendorLeftOff, {})
        t.eq(report.kept, { "sell.autoRepair" })
    end,

    ["gate: a confirmed automation already on is kept and not listed again"] = function(t)
        local confirmed = { ["sell.autoRepair"] = true }
        local once, first = S.Adopt(nil, Import.FromFlow(sellDb(), {}), confirmed)
        t.eq(first.vendorConfirmed, { "sell.autoRepair" })
        local twice, second = S.Adopt(once, Import.FromFlow(sellDb(), {}), confirmed)
        t.eq(twice, once)
        t.eq(second.vendorConfirmed, {})
        t.ok(second.kept[1] ~= nil, "nothing was kept")
    end,

    ["gate: every setting the model has no row for is reported as dropped"] = function(t)
        local model = (ns.Settings.Model.New({
            { key = "buffButton.enabled", type = "bool", default = false },
        }))
        local out, report = S.Adopt(nil, Import.FromFlow(sellDb(), {}), { ["sell.autoRepair"] = true }, model)
        t.eq(out, { buffButton = { enabled = true } })
        t.ok(#report.dropped >= 3, "too little is reported as dropped")
        local seen = {}
        for i, entry in ipairs(report.dropped) do
            t.eq(entry.reason, "no model row", tostring(entry.key))
            t.ok(not seen[entry.key], tostring(entry.key) .. " is listed twice")
            seen[entry.key] = true
            if i > 1 then t.ok(report.dropped[i - 1].key < entry.key, "the list is not sorted") end
        end
        for _, key in ipairs({ "auction.chartClick", "buffButton.dock", "sell.autoAll" }) do
            t.ok(seen[key], key .. " is not reported")
        end
        t.ok(not seen["buffButton.enabled"], "a landed setting is reported as dropped")
        t.ok(not seen["sell.autoJunk"], "an automation left off is reported as dropped")
        t.ok(not seen["sell.autoRepair"], "a confirmed automation with no row is reported twice: left off and dropped")
        t.eq(report.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" })
    end,

    ["gate: nothing the shipped model lands is reported as dropped"] = function(t)
        local model = shipped()
        local out, report = S.Adopt(nil, Import.FromFlow(sellDb(), {}), { ["sell.autoRepair"] = true })
        t.eq(type(report.dropped), "table")
        local dropped = {}
        for _, entry in ipairs(report.dropped) do
            dropped[entry.key] = true
            t.ok(model:row(entry.key) == nil, tostring(entry.key) .. " has a row and is reported as dropped")
            t.eq(entry.reason, "no model row")
        end
        t.ok(#report.taken >= 4, "too little landed to say anything")
        for _, key in ipairs(report.taken) do
            t.ok(model:row(key) ~= nil, tostring(key) .. " was taken and has no row")
            t.ok(model:explicit(out, key), tostring(key) .. " is reported as taken and is not stored")
            t.ok(not dropped[key], tostring(key) .. " landed and is reported as dropped")
        end
        local landed = 0
        for _, key in ipairs(model:keys()) do
            if model:explicit(out, key) then
                landed = landed + 1
                t.ok(not dropped[key], key .. " is stored and is reported as dropped")
            end
        end
        t.eq(landed, #report.taken, "what is stored is not what is reported as taken")
        t.eq((model:get(out, "sell.autoRepair")), true, "the confirmed automation did not land")
        t.eq(report.vendorConfirmed, { "sell.autoRepair" })
    end,

    ["gate: a mapped setting is dropped whole, any other table value by value"] = function(t)
        local model = (ns.Settings.Model.New({
            { key = "buffButton.enabled", type = "bool", default = false },
        }))
        local result = Import.FromFlow({}, {})
        result.account.settings = {
            auction = { chartClick = { a = 1, b = 2 } },
            buffButton = { enabled = true },
            stray = { deep = { one = 1, two = 2 }, flat = "x", none = {} },
        }
        local out, report = S.Adopt(nil, result, nil, model)
        t.eq(out, { buffButton = { enabled = true } })
        t.eq(report.dropped, {
            { key = "auction.chartClick", reason = "no model row" },
            { key = "stray.deep.one", reason = "no model row" },
            { key = "stray.deep.two", reason = "no model row" },
            { key = "stray.flat", reason = "no model row" },
        })
    end,

    ["gate: an import that did not succeed reports nothing dropped"] = function(t)
        local _, report = S.Adopt(nil, { ok = false, reason = "no Flow data" })
        t.eq(report.ok, false)
        t.eq(report.dropped, {})
    end,
    -- ------------------------------------------------------ gate honesty
    ["honesty G1: the merge lists as confirmed only an on that landed"] = function(t)
        local confirmed = { ["sell.autoRepair"] = true, ["sell.autoJunk"] = true }
        local mine = { settings = { sell = { autoRepair = false } } }
        local account, _, report = Import.Merge(mine, nil, Import.FromFlow(sellDb(), {}), nil, confirmed)
        t.eq(account.settings.sell.autoRepair, false, "the player's own off was overwritten")
        t.eq(account.settings.sell.autoJunk, true)
        t.eq(report.vendorConfirmed, { "sell.autoJunk" })
        t.eq(account.imports[#account.imports].vendorConfirmed, { ["sell.autoJunk"] = true })

        local again, _, second = Import.Merge(account, nil, Import.FromFlow(sellDb(), {}), nil, confirmed)
        t.eq(again.settings.sell.autoJunk, true)
        t.eq(second.vendorConfirmed, {}, "an on already stored is listed as confirmed again")
        t.eq(again.imports[#again.imports].vendorConfirmed, {})
    end,

    ["honesty G2: the merge never lists as left off an automation the player has on"] = function(t)
        local mine = { settings = { sell = { autoJunk = true } } }
        local account, _, report = Import.Merge(mine, nil, Import.FromFlow(sellDb(), {}))
        t.eq(account.settings.sell.autoJunk, true, "the player's own on was lost")
        t.eq(account.settings.sell.autoRepair, nil)
        t.eq(report.vendorLeftOff, { "sell.autoRepair" })
        t.eq(report.vendorAlreadyOn, { "sell.autoJunk" })
        t.eq(report.vendorConfirmed, {})
        local reason = {}
        for _, entry in ipairs(report.skipped) do reason[entry.path] = entry.reason end
        local own, off = reason["account.settings.sell.autoJunk"], reason["account.settings.sell.autoRepair"]
        t.ok(type(own) == "string" and not own:find("stays off", 1, true), "an automation that is on is said to stay off")
        t.ok(type(off) == "string" and off:find("stays off", 1, true) ~= nil, "the one left off is not said to stay off")
    end,

    ["honesty G2: the adopt never lists as left off an automation the player has on"] = function(t)
        local mine = { sell = { autoJunk = true } }
        local out, report = S.Adopt(mine, Import.FromFlow(sellDb(), {}))
        t.eq(out.sell, { autoAll = false, autoJunk = true })
        t.eq(report.vendorLeftOff, { "sell.autoRepair" })
        t.eq(report.vendorAlreadyOn, { "sell.autoJunk" })
        t.eq(report.vendorConfirmed, {})
    end,

    ["honesty G3: the character's settings are gated like the account's"] = function(t)
        local result = Import.FromFlow({}, {})
        result.char.settings = { sell = { autoJunk = true, autoAll = false } }
        local _, char, report = Import.Merge(nil, nil, result)
        t.eq(char.settings.sell, { autoAll = false }, "an unconfirmed on reached the character's settings")
        t.eq(report.vendorLeftOff, { "sell.autoJunk" })
        t.eq(report.vendorConfirmed, {})
        local listed = false
        for _, entry in ipairs(report.skipped) do
            if entry.path == "char.settings.sell.autoJunk" then listed = true end
        end
        t.ok(listed, "the automation held back is not listed as skipped")

        local account, yes, agreed = Import.Merge(nil, nil, result, nil, { ["sell.autoJunk"] = true })
        t.eq(yes.settings.sell, { autoAll = false, autoJunk = true })
        t.eq(agreed.vendorConfirmed, { "sell.autoJunk" })
        t.eq(agreed.vendorLeftOff, {})
        t.eq(account.imports[1].vendorConfirmed, { ["sell.autoJunk"] = true })
        t.eq(result.char.settings, { sell = { autoJunk = true, autoAll = false } }, "the import was changed")
    end,

    ["honesty G4: any value but an off at a vendor path is gated"] = function(t)
        local written = { settings = { sell = { autoJunk = "yes", autoAll = 1, autoRepair = {}, autoCleanup = false } } }
        local account, on, off = Import.VendorGate(written, nil, { ["sell.autoAll"] = true })
        t.eq(account, { settings = { sell = { autoAll = true, autoCleanup = false } } })
        t.eq(on, { { key = "sell.autoAll", to = "settings.sell.autoAll" } })
        t.eq(off, {
            { key = "sell.autoJunk", to = "settings.sell.autoJunk" },
            { key = "sell.autoRepair", to = "settings.sell.autoRepair" },
        })
        t.eq(written, { settings = { sell = { autoJunk = "yes", autoAll = 1, autoRepair = {}, autoCleanup = false } } })

        local result = Import.FromFlow({}, {})
        result.account.settings = { sell = { autoJunk = "yes", autoAll = 1 } }
        local out, report = S.Adopt(nil, result)
        t.eq(out, {})
        t.eq(report.vendorLeftOff, { "sell.autoAll", "sell.autoJunk" })
        t.eq(report.refused, {})
        local merged, _, mergeReport = Import.Merge(nil, nil, result)
        t.eq(merged.settings.sell, nil, "a value that is not an off was merged at a vendor path")
        t.eq(mergeReport.vendorLeftOff, { "sell.autoAll", "sell.autoJunk" })
    end,

    ["honesty G6: an automation left off is named by its model key, never a Flow key"] = function(t)
        local result = Import.FromFlow(sellDb(), {})
        local real = Import.VendorGate
        Import.VendorGate = function(account, listed)
            local data, _, off = real(account, listed, nil)
            for i = 1, #off do off[i] = { key = "flow name " .. i, to = off[i].to } end
            return data, {}, off
        end
        local okAdopt, a1, adopted = pcall(S.Adopt, nil, result)
        local okMerge, m1, _, merged = pcall(Import.Merge, nil, nil, result)
        Import.VendorGate = real
        t.ok(okAdopt, tostring(a1))
        t.ok(okMerge, tostring(m1))
        if okAdopt then t.eq(adopted.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" }) end
        if okMerge then t.eq(merged.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" }) end
    end,

    ["honesty: the merge asks the model before adding a setting where nothing is stored"] = function(t)
        local model = (ns.Settings.Model.New({
            { key = "buffButton.enabled", type = "bool", default = false },
            { key = "auction.chartClick", type = "bool", default = true },
        }))
        local result = Import.FromFlow({}, {})
        result.account.settings = {
            auction = { chartClick = "sometimes" },
            buffButton = { enabled = "sometimes", dock = false },
            stray = { flat = "x" },
        }
        local account, _, report = Import.Merge(nil, nil, result, nil, nil, model)
        t.eq(account.settings, { buffButton = { dock = false }, stray = { flat = "x" } })
        local skipped, added = {}, {}
        for _, entry in ipairs(report.skipped) do skipped[entry.path] = entry.reason end
        for _, at in ipairs(report.added) do added[at] = true end
        t.ok(skipped["account.settings.buffButton.enabled"] ~= nil, "the refused value is not listed as skipped")
        t.ok(skipped["account.settings.auction.chartClick"] ~= nil, "the refused value is not listed as skipped")
        t.eq(added["account.settings.buffButton"], true)
        t.eq(added["account.settings.stray"], true)
        t.eq(added["account.settings.auction"], nil, "a section with nothing left in it is reported as added")

        local good = Import.FromFlow({}, {})
        good.account.settings = { buffButton = { enabled = true } }
        local fits = Import.Merge(nil, nil, good, nil, nil, model)
        t.eq(fits.settings, { buffButton = { enabled = true } }, "a value the model accepts was not added")
    end,

    ["honesty T2: the merge asks the shared gate and keeps none of its own"] = function(t)
        local result = Import.FromFlow(sellDb(), {})
        local real = Import.VendorGate
        local calls = 0
        Import.VendorGate = function(account, listed)
            calls = calls + 1
            return real(account, listed, nil)
        end
        local ok, account, _, report = pcall(Import.Merge, nil, nil, result, nil, { ["sell.autoRepair"] = true })
        Import.VendorGate = real
        t.ok(ok, tostring(account))
        t.eq(calls, 2, "the gate is asked once for the account and once for the character")
        if ok then
            t.eq(account.settings.sell, { autoAll = false })
            t.eq(report.vendorConfirmed, {})
            t.eq(report.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" })
        end
    end,

    ["honesty T2: with no gate loaded the merge lands nothing"] = function(t)
        local result = Import.FromFlow(sellDb(), {})
        local mine = { settings = { sell = { autoAll = true } } }
        local real = Import.VendorGate
        Import.VendorGate = nil
        local ok, account, _, report = pcall(Import.Merge, mine, nil, result, nil, { ["sell.autoRepair"] = true })
        Import.VendorGate = real
        t.ok(ok, tostring(account))
        t.eq(type(Import.VendorGate), "function")
        if ok then
            t.eq(report.ok, false)
            t.ok(type(report.reason) == "string" and report.reason:find("nothing was merged", 1, true) ~= nil,
                "does not say nothing was merged")
            t.eq(account, { settings = { sell = { autoAll = true } } })
        end
    end,
    ["guards P2: the merge and the adopt agree on a stored on that is no true"] = function(t)
        local model = shipped()
        local adopted, adopt = S.Adopt({ sell = { autoJunk = "yes" } }, Import.FromFlow(sellDb(), {}), nil, model)
        local account, _, merge = Import.Merge({ settings = { sell = { autoJunk = "yes" } } }, nil,
            Import.FromFlow(sellDb(), {}), nil, nil, model)
        t.eq(merge.ok, true, tostring(merge.reason))
        t.eq(adopt.ok, true, tostring(adopt.reason))
        t.eq(merge.vendorAlreadyOn, adopt.vendorAlreadyOn, "already on differs")
        t.eq(merge.vendorLeftOff, adopt.vendorLeftOff, "left off differs")
        t.eq(merge.vendorConfirmed, adopt.vendorConfirmed, "confirmed differs")
        t.eq(merge.vendorAlreadyOn, {}, "a stored value that is no true is reported as on")
        t.eq(merge.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" })
        t.eq((model:get(account.settings, "sell.autoJunk")), (model:get(adopted, "sell.autoJunk")))
        t.ok((model:get(account.settings, "sell.autoJunk")) ~= true, "the model reads the stored value as on")
    end,

    ["guards P2: a stored true is already on for the merge and the adopt alike"] = function(t)
        local model = shipped()
        local _, adopt = S.Adopt({ sell = { autoJunk = true } }, Import.FromFlow(sellDb(), {}), nil, model)
        local _, _, merge = Import.Merge({ settings = { sell = { autoJunk = true } } }, nil,
            Import.FromFlow(sellDb(), {}), nil, nil, model)
        t.eq(merge.vendorAlreadyOn, { "sell.autoJunk" })
        t.eq(merge.vendorAlreadyOn, adopt.vendorAlreadyOn)
        t.eq(merge.vendorLeftOff, adopt.vendorLeftOff)
    end,
    -- ------------------------------------------------------------ guards TG1
    ["guards TG1: with no model row a stored value that is no plain on or off is not said to stay off"] = function(t)
        local model = (ns.Settings.Model.New({ { key = "buffButton.enabled", type = "bool", default = false } }))
        local want = "a vendor automation Flow had on; the player did not confirm it."
            .. " The stored value is not a plain on or off; it is left as stored"
        local mine = { settings = { sell = { autoJunk = "yes", autoRepair = 1 } } }
        local account, _, report = Import.Merge(mine, nil, Import.FromFlow(sellDb(), {}), nil, nil, model)
        t.eq(report.ok, true, tostring(report.reason))
        t.eq(account.settings.sell.autoJunk, "yes", "the stored text was changed")
        t.eq(account.settings.sell.autoRepair, 1, "the stored number was changed")
        local reason = {}
        for _, entry in ipairs(report.skipped) do reason[entry.path] = entry.reason end
        t.eq(reason["account.settings.sell.autoJunk"], want)
        t.eq(reason["account.settings.sell.autoRepair"], want)
        t.eq(report.vendorNotPlain, { "sell.autoJunk", "sell.autoRepair" })
        t.eq(report.vendorLeftOff, {}, "a value left as stored is listed as off")
        t.eq(report.vendorAlreadyOn, {}, "a value that is no true is listed as on")
        t.eq(report.vendorConfirmed, {})
    end,

    ["guards TG1: a character's stored value that is no plain on or off is not said to stay off"] = function(t)
        local want = "a vendor automation Flow had on; the player did not confirm it."
            .. " The stored value is not a plain on or off; it is left as stored"
        local mine = { settings = { sell = { autoJunk = "yes", autoRepair = 1 } } }
        local _, char, report = Import.Merge(nil, mine, Import.FromFlow(sellDb(), {}), nil, nil, shipped())
        t.eq(report.ok, true, tostring(report.reason))
        t.eq(char.settings.sell.autoJunk, "yes", "the stored text was changed")
        t.eq(char.settings.sell.autoRepair, 1, "the stored number was changed")
        local reason = {}
        for _, entry in ipairs(report.skipped) do reason[entry.path] = entry.reason end
        t.eq(reason["account.settings.sell.autoJunk"], want)
        t.eq(reason["account.settings.sell.autoRepair"], want)
        t.eq(report.vendorNotPlain, { "sell.autoJunk", "sell.autoRepair" })
        t.eq(report.vendorLeftOff, {})
        t.eq(report.vendorAlreadyOn, {})
    end,

    ["guards TG1: a plain off, an absent value and a true keep the reasons they had"] = function(t)
        local model = (ns.Settings.Model.New({ { key = "buffButton.enabled", type = "bool", default = false } }))
        local mine = { settings = { sell = { autoJunk = false } } }
        local _, _, report = Import.Merge(mine, { settings = { sell = { autoRepair = true } } },
            Import.FromFlow(sellDb(), {}), nil, nil, model)
        t.eq(report.ok, true, tostring(report.reason))
        t.eq(report.vendorNotPlain, {})
        t.eq(report.vendorLeftOff, { "sell.autoJunk" })
        t.eq(report.vendorAlreadyOn, { "sell.autoRepair" })
        local reason = {}
        for _, entry in ipairs(report.skipped) do reason[entry.path] = entry.reason end
        local off = reason["account.settings.sell.autoJunk"]
        t.ok(type(off) == "string" and off:find("stays off", 1, true) ~= nil, "a plain off is not said to stay off")
        local _, _, empty = Import.Merge(nil, nil, Import.FromFlow(sellDb(), {}), nil, nil, model)
        t.eq(empty.vendorNotPlain, {})
        t.eq(empty.vendorLeftOff, { "sell.autoJunk", "sell.autoRepair" })
    end,

    ["guards TG1: a merge that is refused still has the list"] = function(t)
        local _, _, report = Import.Merge(nil, nil, nil)
        t.eq(report.ok, false)
        t.eq(report.vendorNotPlain, {})
    end,
}
