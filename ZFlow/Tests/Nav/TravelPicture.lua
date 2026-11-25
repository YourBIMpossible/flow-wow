-- B-28: the travel spell's or the hearthstone's picture in the quest
-- arrow's place, with the arrow at half size beside it (legacy Flow 0.35.377
-- Modules/Nav/TravelIcon.lua). Pure: where the picture and the arrow stand.
-- Shows only: nothing here casts or uses an item. Not tested in game.
local _, ns = ...

local N = ns.Nav

local T = {}

local SPELL_STEP = { label = "Cast Teleport: Moonglade", still = true, via = "spell",
                     action = { kind = "spell", spell = "Teleport: Moonglade", text = "Cast Teleport: Moonglade" } }
local HEARTH_STEP = { label = "Hearth to Goldshire", still = true, via = "hearth" }
local MID = { "CENTER", "CENTER", 0, -120 }

T["picture: which step gets one: a cast or the hearthstone, nothing else"] = function(t)
    t.eq(N.TravelPictureIcon(SPELL_STEP), { kind = "spell", spell = "Teleport: Moonglade" })
    t.eq(N.TravelPictureIcon(HEARTH_STEP), { kind = "hearth" })
    -- The step does not name its spell: still a picture (the client shows
    -- the question mark), never a made-up spell.
    t.eq(N.TravelPictureIcon({ label = "Cast X", via = "spell" }), { kind = "spell" })
    t.eq(N.TravelPictureIcon({ label = "Fly to X", via = "flight" }), nil, "a flight")
    t.eq(N.TravelPictureIcon({ label = "Ride", via = "ride" }), nil, "a ride")
    t.eq(N.TravelPictureIcon({ label = "Wolves" }), nil, "a plain step")
    t.eq(N.TravelPictureIcon(nil), nil)
    t.eq(N.TravelPictureIcon("spell"), nil)
end

T["picture: it stands where the arrow stood; the arrow is half size to its right"] = function(t)
    local pic = N.TravelPicture({ kind = "spell", spell = "Teleport: Moonglade" }, MID, 1024, 768)
    t.eq(pic.icon, { kind = "spell", spell = "Teleport: Moonglade" })
    t.eq(pic.at, MID, "the picture at the arrow's place")
    t.ok(pic.at ~= MID, "a table of its own")
    t.eq(pic.size, 38)
    t.eq(pic.alpha, 0.85)
    t.eq(pic.arrow.scale, 0.5)
    -- Half the picture, the gap, half the half-size arrow: 19 + 6 + 14.
    t.eq(pic.shift, 39)
    t.eq(pic.arrow.point, { "CENTER", "CENTER", 39, -120 })
    t.eq(MID, { "CENTER", "CENTER", 0, -120 }, "the point handed in is not changed")
end

T["picture: no room on the right: the arrow stands on its left"] = function(t)
    -- The arrow's box ends 10 px from the right edge.
    local pic = N.TravelPicture({ kind = "hearth" }, { "RIGHT", "RIGHT", -10, 0 }, 1024, 768)
    t.eq(pic.shift, -39)
    t.eq(pic.arrow.point, { "RIGHT", "RIGHT", -49, 0 })
    t.eq(pic.at, { "RIGHT", "RIGHT", -10, 0 })
end

T["picture: the screen size unknown: the arrow on the right, nothing clamped"] = function(t)
    local pic = N.TravelPicture({ kind = "hearth" }, MID, nil, nil)
    t.eq(pic.shift, 39)
    t.eq(pic.arrow.point, { "CENTER", "CENTER", 39, -120 })
end

T["picture: nothing to show"] = function(t)
    t.eq(N.TravelPicture(nil, MID, 1024, 768), nil, "no icon")
    t.eq(N.TravelPicture({ kind = "flight" }, MID, 1024, 768), nil, "not a cast or the stone")
    t.eq(N.TravelPicture({ kind = "spell" }, nil, 1024, 768), nil, "no place")
    t.eq(N.TravelPicture({ kind = "spell" }, { "CENTER", "CENTER", "x", 0 }, 1024, 768), nil, "a bad place")
end

T["picture: an arrow let go while the picture is up is saved where the picture is"] = function(t)
    t.eq(N.TravelPictureBack({ "CENTER", "CENTER", 139, 20 }, 39), { "CENTER", "CENTER", 100, 20 })
    t.eq(N.TravelPictureBack({ "RIGHT", "RIGHT", -49, 0 }, -39), { "RIGHT", "RIGHT", -10, 0 })
    local p = { "CENTER", "CENTER", 5, 5 }
    t.eq(N.TravelPictureBack(p, nil), p, "no picture: the point as it is")
    t.eq(N.TravelPictureBack(nil, 39), nil)
end

return T
