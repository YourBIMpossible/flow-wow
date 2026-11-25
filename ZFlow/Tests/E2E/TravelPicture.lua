local _, ns = ...
-- B-28: the travel picture on the fake client. UI/TravelPicture.lua is
-- handed the quest arrow's handle and what the layout said of it, and the
-- quest step: a cast or the hearthstone puts the picture where the arrow
-- stood and the arrow at half size beside it; any other step takes the
-- picture down and leaves the arrow as the layout put it. One picture
-- frame, and never a third arrow. Nothing casts or uses an item.
-- The run through the whole add-on is in the Arrow.lua patch for lane B
-- (UI/Arrow.lua is leased). Made-up names. Offline test only: Needs game test.
local tests = {}
local N = ns.Nav

local SPELL, SPELL_ID = "Teleport: Moonglade", 18960
local CAST = { label = "Cast " .. SPELL, still = true, via = "spell",
               action = { kind = "spell", spell = SPELL, text = "Cast " .. SPELL } }
local HEARTH = { label = "Hearth to Goldshire", still = true, via = "hearth" }
local WALK = { label = "Wolves", place = { map = 1411, x = 0.5, y = 0.3 } }
local MID = { "CENTER", "CENTER", 0, -120 }

local function start()
    local c = ns.make.fakeClient()
    c.setScreen(1024, 768)
    c.setSpellId(SPELL, SPELL_ID); c.setSpellTexture(SPELL_ID, 135758)
    c.setItemTexture(N.PICTURE_HEARTH_ITEM, 134414)
    local quest = c.arrow({ name = "Q", size = N.ARROW_SIZE })
    local p = ns.TravelPicture.New(c)
    return c, quest, p
end

-- The layout's answer for the quest arrow, as UI/Arrow.lua has it.
local function ops(shown, point)
    return { shown = shown, point = point or MID, scale = 1 }
end

-- As UI/Arrow.lua's own loop: the arrow at the layout's place and scale.
local function lay(quest, o)
    quest.show(o.shown); quest.place(o.point); quest.scale(o.scale)
end

tests["travel picture: a cast step: the spell's picture where the arrow stood, the arrow half size beside it"] = function(t)
    local c, quest, p = start()
    t.ok(type(p) == "table", "the picture is made")
    t.eq(#c.pictures, 1, "one picture frame")
    t.eq(c.pictures[1].shown, false, "hidden until there is a cast")
    local o = ops(true)
    lay(quest, o)
    t.eq(p.draw(quest, o, CAST), true)
    local pic = c.pictures[1]
    t.eq(pic.shown, true, "the picture")
    t.eq(pic.point, MID, "where the arrow stood")
    t.eq(pic.texture, 135758, "the spell's own picture")
    t.eq(pic.faded, 0.85)
    t.eq(quest.scaled, 0.5, "the arrow at half size")
    t.eq(quest.point, { "CENTER", "CENTER", 39, -120 }, "beside the picture")
    t.eq(#c.arrows, 1, "no arrow frame was added")
    t.eq(#c.pictures, 1, "and no second picture")
end

tests["travel picture: the step is done: the picture goes, the arrow is full size at its place"] = function(t)
    local c, quest, p = start()
    local o = ops(true)
    lay(quest, o); p.draw(quest, o, CAST)
    lay(quest, o)
    t.eq(p.draw(quest, o, WALK), false)
    t.eq(c.pictures[1].shown, false, "no picture")
    t.eq(quest.scaled, 1, "the arrow at full size")
    t.eq(quest.point, MID, "at its own place")
    -- And up again at the next cast.
    lay(quest, o)
    t.eq(p.draw(quest, o, HEARTH), true)
    t.eq(c.pictures[1].shown, true)
    t.eq(c.pictures[1].texture, 134414, "the hearthstone's picture")
    t.eq(#c.pictures, 1, "the same frame")
end

tests["travel picture: the arrow hidden, or no step: no picture"] = function(t)
    local c, quest, p = start()
    local o = ops(true)
    lay(quest, o); p.draw(quest, o, CAST)
    local off = ops(false)
    lay(quest, off)
    t.eq(p.draw(quest, off, CAST), false, "the quest arrow is hidden")
    t.eq(c.pictures[1].shown, false)
    lay(quest, o)
    t.eq(p.draw(quest, o, nil), false, "no step")
    t.eq(c.pictures[1].shown, false)
    lay(quest, o); p.draw(quest, o, CAST)
    p.hide()
    t.eq(c.pictures[1].shown, false, "hide takes it down")
end

tests["travel picture: a spell the client gives no picture for shows the question mark; the stone its rune"] = function(t)
    local c, quest, p = start()
    c.setSpellTexture(SPELL_ID, nil)
    c.setItemTexture(N.PICTURE_HEARTH_ITEM, nil)
    local o = ops(true)
    lay(quest, o); p.draw(quest, o, CAST)
    t.eq(c.pictures[1].texture, "Interface\\Icons\\INV_Misc_QuestionMark")
    lay(quest, o); p.draw(quest, o, { label = "Cast X", still = true, via = "spell" })
    t.eq(c.pictures[1].texture, "Interface\\Icons\\INV_Misc_QuestionMark", "a step that names no spell")
    lay(quest, o); p.draw(quest, o, HEARTH)
    t.eq(c.pictures[1].texture, "Interface\\Icons\\INV_Misc_Rune_01")
end

tests["travel picture: an arrow the player holds is not moved; let go, it is saved where the picture is"] = function(t)
    local _, quest, p = start()
    local o = ops(true)
    lay(quest, o)
    quest.held = true
    quest.place({ "CENTER", "CENTER", 200, 200 })
    p.draw(quest, o, CAST)
    t.eq(quest.point, { "CENTER", "CENTER", 200, 200 }, "left in the hand")
    t.eq(quest.scaled, 0.5, "still half size")
    quest.held = nil
    -- Let go 100 px right of the middle: the picture belongs there.
    t.eq(p.unshift("quest", { "CENTER", "CENTER", 139, 20 }), { "CENTER", "CENTER", 100, 20 })
    t.eq(p.unshift("prof", { "CENTER", "CENTER", 139, 20 }), { "CENTER", "CENTER", 139, 20 }, "the echo's place is its own")
    lay(quest, o); p.draw(quest, o, WALK)
    t.eq(p.unshift("quest", { "CENTER", "CENTER", 139, 20 }), { "CENTER", "CENTER", 139, 20 }, "no picture: as let go")
end

tests["travel picture: a client that makes no frames: no picture, and nothing breaks"] = function(t)
    local c = ns.make.fakeClient()
    c.setFrames(false)
    t.eq(ns.TravelPicture.New(c), nil)
    t.eq(#(c.pictures or {}), 0)
end

return tests
