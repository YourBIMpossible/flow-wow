local _, ns = ...
-- Z-Flow travel icon (S33): what to show in the arrow's place when the
-- step is a cast away (Nav/TravelSpells.lua) or the hearthstone saves
-- travel (Nav/HearthStep.lua), and the per-step "walk there instead".
-- Ported from legacy Flow 0.35.377 (Modules/Nav/TravelIcon.lua): the
-- owner asked for the spell's icon in place of the arrow "making it clear
-- that is the action and the destination is next", and that it must not
-- look clickable.
--
-- SHOWS ONLY. Legacy Flow's Flow-key cast and Tracker button are not
-- ported (§143: advisory only). The action names no cast type, no item and
-- no macro. Drawing it in the arrow frame is UI/Arrow*.lua's (an ARROW
-- NEED in the delivery note). Pure. Not tested in game.
--
-- N.TravelAction(spellStep, hearthStep, skipped) -> action or nil
--   spellStep   from N.TravelSpellStep (a "learn" step is not an icon)
--   hearthStep  from N.HearthStep
--   skipped     true when the player chose to walk to this step
--   action = { kind = "spell", spell, text } or { kind = "hearth", text, saves }
--   The hearthstone shows only when its saving is a known number above 0
--   (legacy Flow's H:Saves check; review d46a60a): a "bind place unknown"
--   step, or one on another map with no saves, is no icon.
--   The spell comes first, then the hearthstone, as in legacy Flow.
--
-- N.TravelSkip(skips, key, on)  sets or clears skips[key] (this session)
--
-- B-28, the picture itself. It stands where the quest arrow stood; the
-- arrow goes to half size beside it (legacy Flow: 38 px, 0.85 alpha, the
-- arrow at 0.5). Where they stand is worked out here; UI/TravelPicture.lua
-- draws it.
--
-- N.TravelPictureIcon(step) -> { kind = "spell", spell } or { kind = "hearth" } or nil
--   step is the quest arrow's step after N.TravelVia: step.via says what
--   it is ("spell", "hearth"; a ride or a flight is no picture) and
--   step.spell names the spell when the step carries it.
-- N.TravelPicture(icon, point, screenW, screenH) -> pic or nil
--   point   the quest arrow's own point { anchor, relative anchor, x, y }
--   pic = { icon, at = that point (a copy), size, alpha,
--           arrow = { scale, point }, shift }
--   The arrow stands shift px to the right of its own point, or to the
--   left when the right would put it off the screen. A screen of unknown
--   size: to the right.
-- N.TravelPictureBack(point, shift) -> point
--   An arrow dragged while the picture is up was let go shift px from
--   where the picture belongs: this is the point to save.
ns.Nav = ns.Nav or {}
local N = ns.Nav

function N.TravelAction(spellStep, hearthStep, skipped)
    if skipped then return nil end
    if type(spellStep) == "table" and type(spellStep.spell) == "string" and not spellStep.learn
        and type(spellStep.label) == "string" then
        return { kind = "spell", spell = spellStep.spell, text = spellStep.label }
    end
    local saves = type(hearthStep) == "table" and hearthStep.saves or nil
    if type(hearthStep) == "table" and type(hearthStep.label) == "string"
        and type(saves) == "number" and saves == saves
        and saves > 0 and saves ~= math.huge then
        return { kind = "hearth", text = hearthStep.label, saves = saves }
    end
    return nil
end

function N.TravelSkip(skips, key, on)
    if type(skips) ~= "table" or key == nil then return end
    skips[key] = on and true or nil
end

-- ---------------------------------------------------------------- picture
N.PICTURE_SIZE = 38
N.PICTURE_ALPHA = 0.85
N.PICTURE_GAP = 6
N.PICTURE_ARROW_SCALE = 0.5
N.PICTURE_HEARTH_ITEM = 6948

function N.TravelPictureIcon(step)
    if type(step) ~= "table" then return nil end
    if step.via == "hearth" then return { kind = "hearth" } end
    if step.via ~= "spell" then return nil end
    return { kind = "spell", spell = type(step.spell) == "string" and step.spell or nil }
end

function N.TravelPicture(icon, point, screenW, screenH)
    if type(icon) ~= "table" or (icon.kind ~= "spell" and icon.kind ~= "hearth") then return nil end
    local size = N.ARROW_SIZE
    -- No screen: only checks the point and copies it.
    local at = N.ClampPoint(point, size)
    if not at then return nil end
    local scale = N.PICTURE_ARROW_SCALE
    local shift = N.PICTURE_SIZE / 2 + N.PICTURE_GAP + size * scale / 2
    local right = { at[1], at[2], at[3] + shift, at[4] }
    local fits = N.ClampPoint(right, size, screenW, screenH)
    if fits and fits[3] ~= right[3] then
        shift = -shift
        right[3] = at[3] + shift
    end
    return {
        icon = { kind = icon.kind, spell = icon.spell },
        at = at, size = N.PICTURE_SIZE, alpha = N.PICTURE_ALPHA,
        arrow = { scale = scale, point = right },
        shift = shift,
    }
end

function N.TravelPictureBack(point, shift)
    if type(point) ~= "table" or type(shift) ~= "number" or type(point[3]) ~= "number" then return point end
    return { point[1], point[2], point[3] - shift, point[4] }
end
