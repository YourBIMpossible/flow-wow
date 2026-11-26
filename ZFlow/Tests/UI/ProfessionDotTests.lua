local _, ns = ...

-- Tests for UI/ProfessionDot.lua (slice 6): the profession step's
-- destination on the minimap — one solid purple dot
-- (RC.ProfessionDot) while a profession step is live. Over the fake
-- client; a made-up profession step. Not tested in game.

local tests = {}

local function PD() return ns.ProfessionDot end
local function RC() return ns.RouteColor end

local STEP = { place = { map = 1, x = 0.53, y = 0.5 }, radius = 10 }

local function client()
    local c = ns.make.fakeClient()
    c.setPosition(1, 0.5, 0.5)
    c.setMapSize(1, 1000, 1000)
    c.setFacing(0)
    c.setMinimap({ size = 140, radius = 100, rotates = false })
    return c
end

tests["profession dot: a live step shows one purple dot"] = function(t)
    local c = client()
    local r = PD().Update(c, STEP, {}, nil)
    t.eq(r.shown, true)
    local er, eg, eb = RC().ProfessionDot(nil)
    t.eq({ r.r, r.g, r.b }, { er, eg, eb }, "the profession purple")
    t.eq(#c.minimapPins, 1)
    t.eq({ c.minimapPins[1].spec.r, c.minimapPins[1].spec.g, c.minimapPins[1].spec.b }, { er, eg, eb })
    t.eq(c.minimapPins[1].spec.size, PD().SIZE)
end

tests["profession dot: no step, no dot"] = function(t)
    local c = client()
    local state = {}
    local r = PD().Update(c, STEP, state, nil)
    t.eq(r.shown, true)
    r = PD().Update(c, nil, state, nil)
    t.eq(r.shown, false)
    t.eq(c.minimapPins[1].shown, false, "hidden again")
end

tests["profession dot: the colour-blind palette's purple"] = function(t)
    local c = client()
    local r = PD().Update(c, STEP, {}, "colourblind")
    local er, eg, eb = RC().ProfessionDot("colourblind")
    t.eq({ r.r, r.g, r.b }, { er, eg, eb })
end

tests["profession dot: the destination where you stand is told hollow"] = function(t)
    local c = client()
    PD().Update(c, { place = { map = 1, x = 0.5, y = 0.5 }, radius = 10 }, {}, nil)
    t.eq(c.minimapPins[1].hollowSet, true)
end

tests["profession dot: reached, the dot becomes the arrival ring"] = function(t)
    local c = client()
    -- 9 yards east: inside the step's own reach (radius 10), but the
    -- pin sits past the character icon (9 * 0.7 = 6.3 units > ON_ICON),
    -- so only the arrival rule can make it hollow.
    local r = PD().Update(c, { place = { map = 1, x = 0.509, y = 0.5 }, radius = 10 }, {}, nil)
    t.eq(r.shown, true)
    t.eq(r.ring, true, "reached: the report says the ring")
    t.eq(c.minimapPins[1].hollowSet, true, "and the pin is told hollow, so the marker shows through")
end

tests["profession dot: not reached, no ring; no radius reads the arrow's reach"] = function(t)
    local c = client()
    local r = PD().Update(c, STEP, {}, nil)
    t.eq(r.ring, nil, "30 yards off with a reach of 10: no ring")
    t.eq(c.minimapPins[1].hollowSet, false)
    local c2 = client()
    local r2 = PD().Update(c2, { place = { map = 1, x = 0.52, y = 0.5 } }, {}, nil)
    t.eq(r2.ring, true, "20 yards off and no radius of its own: inside the arrow's 24-yard reach")
    local c3 = client()
    local r3 = PD().Update(c3, { place = { map = 1, x = 0.53, y = 0.5 } }, {}, nil)
    t.eq(r3.ring, nil, "30 yards off, no radius: no ring")
end

tests["profession dot: the module follows the profession arrow switch"] = function(t)
    local c = client()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    k:Module({ name = "profStep", provides = { Step = function() return STEP end } })
    k:Setting({ key = "nav.profArrow", scope = "account", type = "bool", default = true,
        label = "Profession arrow", group = "travel.route" })
    local api = PD().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    api.Refresh()
    t.eq(api.Shown(), true, "the arrow is on: the dot shows")
    k.settings:set("nav.profArrow", false)
    api.Refresh()
    t.eq(api.Shown(), false, "the arrow is off: no dot")
end

return tests
