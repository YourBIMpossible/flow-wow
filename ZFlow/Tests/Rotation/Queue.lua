-- Tests for ZFlow/Rotation/Queue.lua (S13, the modifier queue): the pure
-- part. Rows are hand-made; nothing here is client data.
local _, ns = ...

local Q = ns.Queue
local R = ns.Rotation
local tests = {}

local function row()
    return { key = "Wrath", shift = "Moonfire", ctrl = "Starfire", alt = "Rejuvenation", more = "Entangling Roots" }
end

tests["queue: the order, the words and the sizes are the ported ones"] = function(t)
    t.eq(Q.ORDER, { "shift", "ctrl", "alt", "more" })
    t.eq(Q.LABEL, { ctrl = "CTRL", shift = "SHIFT", alt = "ALT", more = "C+S" })
    t.eq(Q.SIZES, { 36, 30, 25, 22 })
    t.eq({ Q.GAP_FIRST, Q.GAP }, { 10, 6 })
end

tests["queue row: the row of the form you are in"] = function(t)
    local bear = { key = "Maul" }
    local plan = { states = { [0] = row(), [1] = bear } }
    t.eq(Q.Row(plan, 0), plan.states[0])
    t.eq(Q.Row(plan, 1), bear)
    t.eq(Q.Row(plan, 2), nil, "a form the plan has no row for")
    t.eq(Q.Row(plan, nil), nil, "the form is not known")
    t.eq(Q.Row(nil, 0), nil, "no plan")
    t.eq(Q.Row({}, 0), nil, "a plan with no states")
    t.eq(Q.Row({ states = { [0] = "Wrath" } }, 0), nil, "a state that is not a row")
end

tests["queue row: stealthed in the stealth form takes the stealth row"] = function(t)
    local cat, prowl = { key = "Claw" }, { key = "Pounce" }
    local plan = { states = { [0] = row(), [3] = cat, [R.STEALTH_STATE] = prowl } }
    t.eq(Q.Row(plan, 3, true, 3), prowl)
    t.eq(Q.Row(plan, 3, false, 3), cat, "not stealthed")
    t.eq(Q.Row(plan, 3, nil, 3), cat, "stealth not known is not stealthed")
    t.eq(Q.Row(plan, 0, true, 3), plan.states[0], "stealthed in another form")
    t.eq(Q.Row({ states = { [3] = cat } }, 3, true, 3), cat, "no stealth row: the form row")
end

tests["queue: nothing is drawn twice"] = function(t)
    t.eq(Q.NoRepeats(row()),
        { shift = "Moonfire", ctrl = "Starfire", alt = "Rejuvenation", more = "Entangling Roots" })
    t.eq(Q.NoRepeats({ key = "Wrath", shift = "Wrath", ctrl = "Moonfire" }), { ctrl = "Moonfire" },
        "a slot that casts what the key casts")
    t.eq(Q.NoRepeats({ key = "Wrath", shift = "Moonfire", ctrl = "Moonfire", more = "Moonfire" }),
        { shift = "Moonfire" }, "the nearer slot keeps it")
    t.eq(Q.NoRepeats({ shift = "", ctrl = 5176, alt = "Wrath" }), { alt = "Wrath" }, "only names count")
    t.eq(Q.NoRepeats(nil), {})
    t.eq(Q.NoRepeats({}), {})
end

tests["queue: which press casts the suggestion"] = function(t)
    t.eq(Q.AdviceSlot("Wrath", row()), "key")
    t.eq(Q.AdviceSlot("Moonfire", row()), "shift")
    t.eq(Q.AdviceSlot("Starfire", row()), "ctrl")
    t.eq(Q.AdviceSlot("Rejuvenation", row()), "alt")
    t.eq(Q.AdviceSlot("Entangling Roots", row()), "more")
    t.eq(Q.AdviceSlot("Hurricane", row()), nil, "on the bar, not on a press")
    t.eq(Q.AdviceSlot(nil, row()), nil)
    t.eq(Q.AdviceSlot("", row()), nil)
    t.eq(Q.AdviceSlot("Wrath", nil), nil)
    t.eq(Q.AdviceSlot("Wrath", { key = "Wrath", ctrl = "Wrath" }), "key", "the key first")
end

tests["queue: the held modifier"] = function(t)
    t.eq(Q.HeldMod(false, false, false), nil)
    t.eq(Q.HeldMod(true, false, false), "ctrl")
    t.eq(Q.HeldMod(false, true, false), "shift")
    t.eq(Q.HeldMod(false, false, true), "alt")
    t.eq(Q.HeldMod(true, true, false), "more")
    t.eq(Q.HeldMod(true, true, true), nil, "all three is no slot")
    t.eq(Q.HeldMod(true, false, true), nil)
    t.eq(Q.HeldMod(false, true, true), nil)
end

tests["queue: a modifier that is not known is never read as up"] = function(t)
    t.eq(Q.HeldMod(nil, nil, nil), nil)
    t.eq(Q.HeldMod(true, nil, false), nil, "shift not known: it could be Ctrl + Shift")
    t.eq(Q.HeldMod(true, false, nil), nil)
    t.eq(Q.HeldMod(nil, true, false), nil)
    t.eq(Q.HeldMod(1, false, false), nil, "a number is not an answer")
end

tests["queue: when it is on screen"] = function(t)
    t.eq(Q.Shows(true, false, nil), true, "in a fight")
    t.eq(Q.Shows(false, true, nil), true, "an enemy targeted")
    t.eq(Q.Shows(false, false, "shift"), true, "a modifier held")
    t.eq(Q.Shows(false, false, nil), false)
    t.eq(Q.Shows(nil, nil, nil), false, "not known is not a yes")
end

tests["queue slots: one entry per slot in order, with its word and size"] = function(t)
    local out = Q.Slots(row(), nil, nil)
    t.eq(#out, 4)
    for i, slot in ipairs(Q.ORDER) do
        t.eq(out[i].slot, slot)
        t.eq(out[i].label, Q.LABEL[slot])
        t.eq(out[i].size, Q.SIZES[i])
        t.eq(out[i].spell, row()[slot])
        t.eq(out[i].state, nil)
    end
end

tests["queue slots: the suggested press is advised, the held one is held"] = function(t)
    local out = Q.Slots(row(), "Starfire", nil)
    t.eq(out[2].state, "advised")
    t.eq(out[1].state, nil)
    out = Q.Slots(row(), "Starfire", "shift")
    t.eq(out[1].state, "held")
    t.eq(out[2].state, "advised")
    out = Q.Slots(row(), "Starfire", "ctrl")
    t.eq(out[2].state, "held", "held wins over advised")
    out = Q.Slots(row(), "Wrath", nil)
    for i = 1, 4 do t.eq(out[i].state, nil, "the key casts it: no modifier to hold") end
    out = Q.Slots(row(), "Hurricane", nil)
    for i = 1, 4 do t.eq(out[i].state, nil, "on the bar") end
end

tests["queue slots: an empty or repeated slot has no spell and no state"] = function(t)
    local out = Q.Slots({ key = "Wrath", shift = "Wrath", ctrl = "Moonfire" }, "Wrath", "shift")
    t.eq(out[1].spell, nil, "repeats the key")
    t.eq(out[1].state, nil, "nothing there to mark")
    t.eq(out[2].spell, "Moonfire")
    t.eq(out[3].spell, nil)
    t.eq(out[4].spell, nil)
    out = Q.Slots(nil, "Wrath", "ctrl")
    t.eq(#out, 4)
    for i = 1, 4 do t.eq(out[i].spell, nil) end
end

tests["queue side: by the half of the screen the big icon is in"] = function(t)
    t.eq(Q.Side({ "CENTER", "CENTER", 0, -160 }, 48, 1024), "left", "dead centre runs left")
    t.eq(Q.Side({ "CENTER", "CENTER", 100, 0 }, 48, 1024), "right")
    t.eq(Q.Side({ "CENTER", "CENTER", -100, 0 }, 48, 1024), "left")
    t.eq(Q.Side({ "BOTTOMLEFT", "BOTTOMLEFT", 900, 10 }, 48, 1024), "right")
    t.eq(Q.Side({ "TOPRIGHT", "TOPRIGHT", -900, -10 }, 48, 1024), "left")
    t.eq(Q.Side({ "CENTER", "CENTER", 100, 0 }, 48, nil), "left", "the screen is not known")
    t.eq(Q.Side(nil, 48, 1024), "left")
    t.eq(Q.Side({ "NOWHERE", "CENTER", 100, 0 }, 48, 1024), "left")
end

tests["queue place: left of a bottom-left point, bottoms level, nearest first"] = function(t)
    local out = Q.Place({ "BOTTOMLEFT", "BOTTOMLEFT", 500, 300 }, 48, "left")
    t.eq(out, {
        { "BOTTOMLEFT", "BOTTOMLEFT", 500 - 10 - 36, 300 },
        { "BOTTOMLEFT", "BOTTOMLEFT", 500 - 10 - 36 - 6 - 30, 300 },
        { "BOTTOMLEFT", "BOTTOMLEFT", 500 - 10 - 36 - 6 - 30 - 6 - 25, 300 },
        { "BOTTOMLEFT", "BOTTOMLEFT", 500 - 10 - 36 - 6 - 30 - 6 - 25 - 6 - 22, 300 },
    })
end

tests["queue place: right of a bottom-left point"] = function(t)
    local out = Q.Place({ "BOTTOMLEFT", "BOTTOMLEFT", 500, 300 }, 48, "right")
    t.eq(out, {
        { "BOTTOMLEFT", "BOTTOMLEFT", 500 + 48 + 10, 300 },
        { "BOTTOMLEFT", "BOTTOMLEFT", 500 + 48 + 10 + 36 + 6, 300 },
        { "BOTTOMLEFT", "BOTTOMLEFT", 500 + 48 + 10 + 36 + 6 + 30 + 6, 300 },
        { "BOTTOMLEFT", "BOTTOMLEFT", 500 + 48 + 10 + 36 + 6 + 30 + 6 + 25 + 6, 300 },
    })
end

-- A centred box of size s at offset (x, y) has its left edge at x - s / 2
-- and its bottom at y - s / 2 from the anchor.
tests["queue place: against a centre point the edges still meet and the bottoms are level"] = function(t)
    local main = { "CENTER", "CENTER", 0, -160 }
    local left = Q.Place(main, 48, "left")
    local mainLeft, mainBottom = 0 - 24, -160 - 24
    local edge = mainLeft - Q.GAP_FIRST
    for i, w in ipairs(Q.SIZES) do
        t.eq(left[i][1], "CENTER")
        t.eq(left[i][2], "CENTER")
        t.eq(left[i][3] + w / 2, edge, "slot " .. i .. ": its right edge")
        t.eq(left[i][4] - w / 2, mainBottom, "slot " .. i .. ": its bottom")
        edge = edge - w - Q.GAP
    end
    local right = Q.Place(main, 48, "right")
    edge = mainLeft + 48 + Q.GAP_FIRST
    for i, w in ipairs(Q.SIZES) do
        t.eq(right[i][3] - w / 2, edge, "slot " .. i .. ": its left edge")
        t.eq(right[i][4] - w / 2, mainBottom)
        edge = edge + w + Q.GAP
    end
end

tests["queue place: against a top-right point"] = function(t)
    local out = Q.Place({ "TOPRIGHT", "TOPRIGHT", -100, -50 }, 48, "left")
    -- The big icon: right edge at -100, left at -148, bottom at -98.
    t.eq(out[1], { "TOPRIGHT", "TOPRIGHT", -148 - 10, -50 - (48 - 36) })
    t.eq(out[1][4] - 36, -98, "its bottom is the big icon's bottom")
end

tests["queue place: a point that cannot be used gives nothing"] = function(t)
    t.eq(Q.Place(nil, 48, "left"), nil)
    t.eq(Q.Place({ "NOWHERE", "CENTER", 0, 0 }, 48, "left"), nil)
    t.eq(Q.Place({ "CENTER", "CENTER", 0 }, 48, "left"), nil)
    t.eq(Q.Place({ "CENTER", "CENTER", 0, 0 }, nil, "left"), nil)
end

return tests
