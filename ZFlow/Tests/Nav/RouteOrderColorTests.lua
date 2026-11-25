local _, ns = ...

-- Tests for Nav/RouteOrderColor.lua (FLOW-PARITY B-17, section 844): the
-- route colour of each order mode, as Flow's Theme.lua:23 and :38. Pure.

local tests = {}

local function ROC() return ns.RouteOrderColor end

local function hex(r, g, b) return ns.RouteColor.Hex(r, g, b) end

local function settings(v)
    return { get = function(_, key)
        if key == "nav.routeSort" then return v end
        return nil
    end }
end

tests["route order colour: each mode in the standard palette, as Flow"] = function(t)
    t.eq(hex(ROC().Color("distance", "standard")), "0070DD", "shortest path: blue")
    t.eq(hex(ROC().Color("xp", "standard")), "A335EE", "most XP: purple")
    t.eq(hex(ROC().Color("custom", "standard")), "FF8000", "custom route: orange")
end

tests["route order colour: each mode in the colour-blind palette, as Flow"] = function(t)
    t.eq(hex(ROC().Color("distance", "colourBlind")), "0072B2", "shortest path")
    t.eq(hex(ROC().Color("xp", "colourBlind")), "CC79A7", "most XP")
    t.eq(hex(ROC().Color("custom", "colourBlind")), "E69F00", "custom route")
end

tests["route order colour: palette words normalise as RouteColor does"] = function(t)
    t.eq(hex(ROC().Color("xp", "colorblind")), "CC79A7", "colorblind spelling")
    t.eq(hex(ROC().Color("xp", nil)), "A335EE", "no palette: standard")
    t.eq(hex(ROC().Color("xp", "nonsense")), "A335EE", "unknown palette: standard")
end

tests["route order colour: selected is custom, unknown is shortest path"] = function(t)
    t.eq(hex(ROC().Color("selected", "standard")), "FF8000", "selected: its older name")
    t.eq(hex(ROC().Color("bogus", "standard")), "0070DD", "unknown mode: shortest path")
    t.eq(hex(ROC().Color(nil, "colourBlind")), "0072B2", "no mode: shortest path")
end

tests["route order colour: the mode comes from the route sort setting"] = function(t)
    t.eq(ROC().Mode(settings("xp")), "xp", "xp")
    t.eq(ROC().Mode(settings("distance")), "distance", "distance")
    t.eq(ROC().Mode(settings(nil)), "distance", "unset: the default")
    t.eq(ROC().Mode(nil), "distance", "no settings")
    local raising = { get = function() error("boom") end }
    t.eq(ROC().Mode(raising), "distance", "a read that raises")
end

return tests
