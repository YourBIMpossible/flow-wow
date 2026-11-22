-- Import.Stored: the readers for the stored paths nothing else reads yet.
-- Every table below is made up; no real saved data is read anywhere.
local _, ns = ...

local S = ns.Import.Stored
local NAN = 0 / 0
local HUGE = math.huge

local function near(t, got, want)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9,
        "expected " .. tostring(want) .. ", got " .. tostring(got))
end

local function samePoint(t, got, want)
    t.ok(type(got) == "table", "expected a point")
    if type(got) ~= "table" then return end
    t.eq(got[1], want[1])
    t.eq(got[2], want[2])
    t.eq(got[3], want[3])
    t.eq(got[4], want[4])
    t.eq(got[5], nil)
end

-- Things a half-written or damaged store could hold in place of a table.
local JUNK = { false, true, 0, 7, "text", NAN }

return {
    -- ------------------------------------------------------------ nothing stored
    ["stored: nil layout gives the buff button defaults"] = function(t)
        local b = S.BuffButtonLayout(nil)
        t.eq(b.frame, nil)
        t.eq(b.scale, 1)
        t.eq(b.dockScale, nil)
    end,
    ["stored: nil input gives every other default"] = function(t)
        t.eq(S.RotationScale(nil), 1)
        t.eq(S.AuctionChart(nil), nil)
        t.eq(S.ProfFrame(nil), nil)
        t.eq(S.AuctionChartClick(nil), true)
        t.eq(S.DockScale(nil, nil), 1)
        local b = S.BuffButtonSettings(nil)
        t.eq(b.enabled, false)
        t.eq(b.key, nil)
        t.eq(b.key2, nil)
        t.eq(#b.keys, 0)
        t.eq(b.dock, true)
        t.eq(b.always, false)
        t.eq(b.care, true)
        t.eq(b.keepOnMain, false)
    end,
    ["stored: empty tables read like nil"] = function(t)
        t.eq(S.BuffButtonLayout({}).scale, 1)
        t.eq(S.BuffButtonLayout({ buffButton = {} }).scale, 1)
        t.eq(S.RotationScale({ rotation = {} }), 1)
        t.eq(S.AuctionChart({ auction = {} }), nil)
        t.eq(S.ProfFrame({ prof = {} }), nil)
        t.eq(S.AuctionChartClick({ auction = {} }), true)
        t.eq(S.BuffButtonSettings({ buffButton = {} }).dock, true)
    end,
    ["stored: a non-table where a table belongs never raises and reads as defaults"] = function(t)
        for _, junk in ipairs(JUNK) do
            local holders = { junk, { buffButton = junk, rotation = junk, auction = junk, prof = junk } }
            for i = 1, 2 do
                local holder = holders[i]
                local b = S.BuffButtonLayout(holder)
                t.eq(b.frame, nil)
                t.eq(b.scale, 1)
                t.eq(b.dockScale, nil)
                t.eq(S.RotationScale(holder), 1)
                t.eq(S.AuctionChart(holder), nil)
                t.eq(S.ProfFrame(holder), nil)
                t.eq(S.AuctionChartClick(holder), true)
                t.eq(S.DockScale(holder, nil), 1)
                local s = S.BuffButtonSettings(holder)
                t.eq(s.enabled, false)
                t.eq(s.dock, true)
                t.eq(s.care, true)
                t.eq(#s.keys, 0)
            end
        end
    end,

    -- ------------------------------------------------------------ points
    ["stored: a good point is read from each of the three point paths"] = function(t)
        local layout = {
            buffButton = { frame = { "CENTER", "BOTTOM", 12.5, -40 } },
            auction = { chart = { "TOPLEFT", "TOPLEFT", 300, -200 } },
        }
        local charLayout = { prof = { frame = { "RIGHT", "CENTER", -8, 0 } } }
        samePoint(t, S.BuffButtonLayout(layout).frame, { "CENTER", "BOTTOM", 12.5, -40 })
        samePoint(t, S.AuctionChart(layout), { "TOPLEFT", "TOPLEFT", 300, -200 })
        samePoint(t, S.ProfFrame(charLayout), { "RIGHT", "CENTER", -8, 0 })
    end,
    ["stored: a point with only an anchor fills in the rest"] = function(t)
        samePoint(t, S.Point({ "TOP" }), { "TOP", "TOP", 0, 0 })
        samePoint(t, S.Point({ "LEFT", nil, 5 }), { "LEFT", "LEFT", 5, 0 })
    end,
    ["stored: every one of the nine anchors is accepted"] = function(t)
        for _, a in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
                             "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
            samePoint(t, S.Point({ a, a, 1, 2 }), { a, a, 1, 2 })
        end
    end,
    ["stored: a point that cannot be used reads as nil"] = function(t)
        local bad = {
            {}, { "MIDDLE", "TOP", 0, 0 }, { "top", "TOP", 0, 0 }, { 1, "TOP", 0, 0 },
            { "TOP", "NOWHERE", 0, 0 }, { "TOP", 4, 0, 0 }, { "TOP", false, 0, 0 },
            { "TOP", "TOP", "3", 0 }, { "TOP", "TOP", 0, "3" },
            { "TOP", "TOP", NAN, 0 }, { "TOP", "TOP", 0, NAN },
            { "TOP", "TOP", HUGE, 0 }, { "TOP", "TOP", 0, -HUGE },
            { "TOP", "TOP", {}, 0 },
        }
        for _, p in ipairs(bad) do
            t.eq(S.Point(p), nil)
            t.eq(S.BuffButtonLayout({ buffButton = { frame = p } }).frame, nil)
            t.eq(S.AuctionChart({ auction = { chart = p } }), nil)
            t.eq(S.ProfFrame({ prof = { frame = p } }), nil)
        end
        for _, junk in ipairs(JUNK) do t.eq(S.Point(junk), nil) end
        t.eq(S.Point(nil), nil)
    end,
    ["stored: a point comes back as a new table and extra entries are dropped"] = function(t)
        local saved = { "TOP", "TOP", 1, 2, "extra", name = "x" }
        local layout = { auction = { chart = saved } }
        local got = S.AuctionChart(layout)
        t.ok(got ~= saved, "the stored table itself was returned")
        samePoint(t, got, { "TOP", "TOP", 1, 2 })
        t.eq(got.name, nil)
        got[3] = 99
        t.eq(saved[3], 1)
        t.eq(saved[5], "extra")
        t.ok(S.AuctionChart(layout) ~= S.AuctionChart(layout), "two reads shared one table")
    end,
    ["stored: the profession point is read from the layout it is given only"] = function(t)
        local account = { prof = { frame = { "TOP", "TOP", 1, 1 } } }
        local char = {}
        samePoint(t, S.ProfFrame(account), { "TOP", "TOP", 1, 1 })
        t.eq(S.ProfFrame(char), nil)
    end,

    -- ------------------------------------------------------------ sizes
    ["stored: a good size is read from each of the three size paths"] = function(t)
        local layout = { buffButton = { scale = 1.5, dockScale = 0.75 }, rotation = { scale = 1.25 } }
        local b = S.BuffButtonLayout(layout)
        near(t, b.scale, 1.5)
        near(t, b.dockScale, 0.75)
        near(t, S.RotationScale(layout), 1.25)
    end,
    ["stored: sizes are held within the limits carried over from Flow"] = function(t)
        near(t, S.SCALE_MIN, 0.5)
        near(t, S.SCALE_MAX, 2)
        near(t, S.Scale(0.01), 0.5)
        near(t, S.Scale(0.5), 0.5)
        near(t, S.Scale(2), 2)
        near(t, S.Scale(40), 2)
        near(t, S.RotationScale({ rotation = { scale = 9 } }), 2)
        local b = S.BuffButtonLayout({ buffButton = { scale = 0.1, dockScale = 3 } })
        near(t, b.scale, 0.5)
        near(t, b.dockScale, 2)
    end,
    ["stored: sizes are rounded to the nearest twentieth"] = function(t)
        near(t, S.Scale(1.23), 1.25)
        near(t, S.Scale(1.22), 1.2)
        near(t, S.Scale(0.874), 0.85)
        near(t, S.Scale(1), 1)
    end,
    ["stored: a size that cannot be used reads as the default"] = function(t)
        for _, v in ipairs({ 0, -1, -0.5, NAN, HUGE, -HUGE, "1.5", true, false, {} }) do
            t.eq(S.Scale(v), nil)
            t.eq(S.RotationScale({ rotation = { scale = v } }), 1)
            local b = S.BuffButtonLayout({ buffButton = { scale = v, dockScale = v } })
            t.eq(b.scale, 1)
            t.eq(b.dockScale, nil)
        end
        t.eq(S.Scale(nil), nil)
    end,
    ["stored: the docked size is the saved one, else the main size, else 1"] = function(t)
        near(t, S.DockScale({ buffButton = { dockScale = 0.8 } }, 1.5), 0.8)
        near(t, S.DockScale({ buffButton = {} }, 1.5), 1.5)
        near(t, S.DockScale({}, 1.5), 1.5)
        near(t, S.DockScale({ buffButton = { dockScale = NAN } }, 1.5), 1.5)
        near(t, S.DockScale({ buffButton = { dockScale = -2 } }, 7), 2)
        near(t, S.DockScale({}, nil), 1)
        near(t, S.DockScale({}, "big"), 1)
        near(t, S.DockScale({}, 0), 1)
        near(t, S.DockScale({}, NAN), 1)
    end,
    ["stored: the docked size does not follow the undocked size"] = function(t)
        near(t, S.DockScale({ buffButton = { scale = 1.8 } }, 1.1), 1.1)
    end,

    -- ------------------------------------------------------------ settings
    ["stored: chart click is on unless it is stored as false"] = function(t)
        t.eq(S.AuctionChartClick({ auction = { chartClick = false } }), false)
        t.eq(S.AuctionChartClick({ auction = { chartClick = true } }), true)
        t.eq(S.AuctionChartClick({ auction = { chartClick = 0 } }), true)
        t.eq(S.AuctionChartClick({ auction = { chartClick = "no" } }), true)
        t.eq(S.AuctionChartClick({ auction = { chart = { "TOP" } } }), true)
    end,
    ["stored: buff button settings read back as stored"] = function(t)
        local b = S.BuffButtonSettings({ buffButton = {
            enabled = true, key = "SHIFT-F", key2 = "BUTTON4", dock = false,
            always = true, care = false, keepOnMain = true,
        } })
        t.eq(b.enabled, true)
        t.eq(b.key, "SHIFT-F")
        t.eq(b.key2, "BUTTON4")
        t.eq(#b.keys, 2)
        t.eq(b.keys[1], "SHIFT-F")
        t.eq(b.keys[2], "BUTTON4")
        t.eq(b.dock, false)
        t.eq(b.always, true)
        t.eq(b.care, false)
        t.eq(b.keepOnMain, true)
    end,
    ["stored: buff button switches of the wrong type read as their defaults"] = function(t)
        for _, v in ipairs({ 0, 1, "true", "false", {}, NAN }) do
            local b = S.BuffButtonSettings({ buffButton = {
                enabled = v, dock = v, always = v, care = v, keepOnMain = v,
            } })
            t.eq(b.enabled, false)
            t.eq(b.dock, true)
            t.eq(b.always, false)
            t.eq(b.care, true)
            t.eq(b.keepOnMain, false)
        end
    end,
    ["stored: every buff button switch comes back as a boolean"] = function(t)
        for _, store in ipairs({ {}, { buffButton = { enabled = "x", dock = "x" } } }) do
            local b = S.BuffButtonSettings(store)
            for _, name in ipairs({ "enabled", "dock", "always", "care", "keepOnMain" }) do
                t.eq(type(b[name]), "boolean")
            end
        end
    end,
    ["stored: a key that is not a string with something in it reads as nil"] = function(t)
        for _, v in ipairs({ "", 0, 5, true, false, {}, NAN }) do
            local b = S.BuffButtonSettings({ buffButton = { key = v, key2 = v } })
            t.eq(b.key, nil)
            t.eq(b.key2, nil)
            t.eq(#b.keys, 0)
        end
    end,
    ["stored: the second key alone is kept as the second key"] = function(t)
        local b = S.BuffButtonSettings({ buffButton = { key2 = "G" } })
        t.eq(b.key, nil)
        t.eq(b.key2, "G")
        t.eq(#b.keys, 1)
        t.eq(b.keys[1], "G")
    end,
    ["stored: a second key that repeats the first is dropped"] = function(t)
        local b = S.BuffButtonSettings({ buffButton = { key = "G", key2 = "G" } })
        t.eq(b.key, "G")
        t.eq(b.key2, nil)
        t.eq(#b.keys, 1)
    end,
    ["stored: a key does not switch the button on by itself"] = function(t)
        t.eq(S.BuffButtonSettings({ buffButton = { key = "G" } }).enabled, false)
    end,
    ["stored: unknown buff button keys are not passed through"] = function(t)
        local b = S.BuffButtonSettings({ buffButton = { enabled = true, extra = "x", point = { "TOP" } } })
        t.eq(b.extra, nil)
        t.eq(b.point, nil)
    end,

    -- ------------------------------------------------------------ purity
    ["stored: no reader changes what it is given"] = function(t)
        local layout = {
            buffButton = { frame = { "TOP" }, scale = 9, dockScale = "bad" },
            rotation = { scale = 1.23 }, auction = { chart = { "LEFT", nil, 4 } },
            prof = { frame = { "TOP", "NOWHERE" } }, arrows = { mode = "separate" },
        }
        local settings = {
            buffButton = { enabled = 1, key = "", key2 = "G", dock = "x" },
            auction = { chartClick = "x" },
        }
        S.BuffButtonLayout(layout)
        S.DockScale(layout, 1.5)
        S.RotationScale(layout)
        S.AuctionChart(layout)
        S.ProfFrame(layout)
        S.AuctionChartClick(settings)
        S.BuffButtonSettings(settings)
        t.eq(layout.buffButton.frame[1], "TOP")
        t.eq(layout.buffButton.frame[2], nil)
        t.eq(layout.buffButton.frame[3], nil)
        t.eq(layout.buffButton.scale, 9)
        t.eq(layout.buffButton.dockScale, "bad")
        t.eq(layout.rotation.scale, 1.23)
        t.eq(layout.auction.chart[2], nil)
        t.eq(layout.auction.chart[3], 4)
        t.eq(layout.auction.chart[4], nil)
        t.eq(layout.prof.frame[2], "NOWHERE")
        t.eq(layout.arrows.mode, "separate")
        t.eq(settings.buffButton.enabled, 1)
        t.eq(settings.buffButton.key, "")
        t.eq(settings.buffButton.key2, "G")
        t.eq(settings.buffButton.dock, "x")
        t.eq(settings.buffButton.keys, nil)
        t.eq(settings.auction.chartClick, "x")
    end,
    ["stored: two reads of the settings share no table"] = function(t)
        local settings = { buffButton = { key = "G" } }
        local a, b = S.BuffButtonSettings(settings), S.BuffButtonSettings(settings)
        t.ok(a ~= b and a.keys ~= b.keys, "two reads shared a table")
        a.keys[1] = "changed"
        t.eq(b.keys[1], "G")
        t.eq(settings.buffButton.key, "G")
    end,
    ["stored: what the import writes is what the readers read"] = function(t)
        local result = ns.Import.FromFlow({
            buffButton = { enabled = true, key = "SHIFT-F", dock = false, point = { "CENTER", "CENTER", 10, 20 },
                           scale = 1.5, dockScale = 0.75 },
            rotation = { scale = 1.25 },
            ah = { chartPoint = { "TOP", "TOP", 0, -50 }, chartClick = false },
            prof = { point = { "LEFT", "LEFT", 30, 0 } },
        }, {})
        t.eq(result.ok, true)
        local layout, settings = result.account.layout, result.account.settings
        local b = S.BuffButtonLayout(layout)
        samePoint(t, b.frame, { "CENTER", "CENTER", 10, 20 })
        near(t, b.scale, 1.5)
        near(t, b.dockScale, 0.75)
        near(t, S.RotationScale(layout), 1.25)
        samePoint(t, S.AuctionChart(layout), { "TOP", "TOP", 0, -50 })
        t.eq(S.AuctionChartClick(settings), false)
        local s = S.BuffButtonSettings(settings)
        t.eq(s.enabled, true)
        t.eq(s.key, "SHIFT-F")
        t.eq(s.dock, false)
        samePoint(t, S.ProfFrame(result.char.layout), { "LEFT", "LEFT", 30, 0 })
        t.eq(S.ProfFrame(layout), nil)
    end,
}
