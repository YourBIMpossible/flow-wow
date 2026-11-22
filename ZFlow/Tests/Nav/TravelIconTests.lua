-- Travel icon (S33): N.TravelAction and the per-step "walk there instead".
-- Ported from legacy Flow 0.35.377 Modules/Nav/TravelIcon.lua. Shows only:
-- nothing here casts or uses an item. Not tested in game.
local _, ns = ...

local N = ns.Nav

local SPELL = { label = "Cast Teleport: Moonglade", text = true, spell = "Teleport: Moonglade" }
local LEARN = { label = "Learn Teleport: Moonglade", text = true, spell = "Teleport: Moonglade", learn = true }
local HEARTH = { label = "Hearth to Goldshire", text = true, saves = 400 }

local T = {}

T["action: a known travel spell comes first"] = function(t)
    t.eq(N.TravelAction(SPELL, HEARTH, false), { kind = "spell", spell = "Teleport: Moonglade", text = "Cast Teleport: Moonglade" })
end

T["action: the hearthstone when no spell is a cast away"] = function(t)
    t.eq(N.TravelAction(nil, HEARTH, false), { kind = "hearth", text = "Hearth to Goldshire" })
    t.eq(N.TravelAction(LEARN, HEARTH, false).kind, "hearth", "a spell to learn is not an icon")
end

T["action: nothing to show, or the player chose to walk"] = function(t)
    t.eq(N.TravelAction(nil, nil, false), nil)
    t.eq(N.TravelAction(LEARN, nil, false), nil)
    t.eq(N.TravelAction(SPELL, HEARTH, true), nil)
end

T["skip: per step, set and cleared"] = function(t)
    local skips = {}
    N.TravelSkip(skips, "step:7", true)
    t.eq(skips, { ["step:7"] = true })
    t.eq(N.TravelAction(SPELL, nil, skips["step:7"] == true), nil)
    N.TravelSkip(skips, "step:7", false)
    t.eq(skips, {})
    N.TravelSkip(skips, nil, true)
    t.eq(skips, {}, "no key: nothing")
end

T["advisory: the action names no cast and no item to use"] = function(t)
    local a = N.TravelAction(SPELL, nil, false)
    t.eq(a.type, nil); t.eq(a.item, nil); t.eq(a.macrotext, nil)
end

return T
