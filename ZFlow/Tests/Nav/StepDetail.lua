local _, ns = ...
-- Parity row A1-10, the data half (lead section 749): what the arrow's
-- details drawer says, as Flow's Modules/Nav/Nav.lua showPanel (:4169-
-- 4232): the step's title, "Blocked: <why>", its detail lines (not the
-- "Quest:" or "Objective:" ones), "Then (N steps)" with the next stops,
-- the 2nd to the 10th, then "..."; "Along the way" with the things to pick
-- up as you go. From Nav/TripRoute.lua View(). Made-up steps. Not tested in
-- game. Fails before: no such file.
local tests = {}

local function SD() return ns.Nav and ns.Nav.StepDetail end

local function stops(n)
    local out = {}
    for i = 1, n do out[i] = { label = "Step " .. i, place = { map = 1, x = i / 100, y = 0.5 } } end
    return out
end

local function texts(rows)
    local out = {}
    for i, r in ipairs(rows or {}) do out[i] = r.text end
    return out
end

tests["step detail: the current step, then the next ones, as Flow's drawer"] = function(t)
    t.eq(type(SD()), "table", "loaded")
    if type(SD()) ~= "table" then return end
    local view = { stops = stops(3) }
    view.stops[1].title = "Wanted: Gnolls"
    view.stops[1].detail = "Gnoll Paw: 2/8"
    t.eq(texts(SD().Rows(view)), {
        "Wanted: Gnolls", "Gnoll Paw: 2/8",
        "Then (2 steps)", "  2. Step 2", "  3. Step 3",
    })
end

tests["step detail: a held step says why, as Blocked"] = function(t)
    if type(SD()) ~= "table" then return t.ok(false, "not loaded") end
    local view = { stops = stops(1) }
    view.stops[1].held = "not complete yet"
    local rows = SD().Rows(view)
    t.eq(rows[1], { kind = "blocked", text = "Blocked: not complete yet" })
end

tests["step detail: Quest and Objective lines are left out; the title only when it differs"] = function(t)
    if type(SD()) ~= "table" then return t.ok(false, "not loaded") end
    local view = { stops = stops(1) }
    view.stops[1].title = "Step 1"
    view.stops[1].details = { "Quest: X", "Objective: Y", "Talk to the guard" }
    t.eq(texts(SD().Rows(view)), { "Talk to the guard" })
end

tests["step detail: the 2nd to the 10th step, then ..."] = function(t)
    if type(SD()) ~= "table" then return t.ok(false, "not loaded") end
    local got = texts(SD().Rows({ stops = stops(14) }))
    t.eq(got[1], "Then (13 steps)")
    t.eq(got[2], "  2. Step 2")
    t.eq(got[10], "  10. Step 10")
    t.eq(got[11], "  ...")
    t.eq(#got, 11)
end

tests["step detail: Along the way, when there is anything"] = function(t)
    if type(SD()) ~= "table" then return t.ok(false, "not loaded") end
    local got = texts(SD().Rows({ stops = stops(1) }, { along = { { text = "Stringy Wolf Meat" } } }))
    t.eq(got, { "Along the way", "  Stringy Wolf Meat" })
    t.eq(texts(SD().Rows({ stops = stops(1) }, { along = {} })), {}, "none: no heading")
end

tests["step detail: no route, nothing"] = function(t)
    if type(SD()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(SD().Rows(nil), {})
    t.eq(SD().Rows({ stops = {} }), {})
end

return tests
