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
