local _, ns = ...

-- The new-spell card (G33): when the player learns a spell, a short card
-- with its name, its rank and whether the rotation uses it.
--
-- Pure. The learned spell comes in as { name =, rank = }, exactly as the
-- client reported it; the rotation pack is read through its public
-- ns.RotationReader.SpellNames only. Nothing is guessed: no rank from the
-- client means no rank on the card, and no pack means "no rotation", never
-- "not used".
--
-- Not wired to the game yet: the client has no spell-learned event, so the
-- event and the frame that shows the card are a CLIENT NEED (see the
-- delivery note). Look-only: the card casts, buys and changes nothing.

ns.SpellCard = {}
local S = ns.SpellCard

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- { name =, rank = (nil when not known), rotation = "used" | "unused" | "none" }
-- or nil when the learned spell has no name.
function S.Build(learned, pack)
    if type(learned) ~= "table" then return nil end
    local name = text(learned.name)
    if not name then return nil end
    local rotation = "none"
    if type(pack) == "table" and type(pack.spells) == "table" then
        rotation = "unused"
        for _, n in ipairs(ns.RotationReader.SpellNames(pack)) do
            if n == name then
                rotation = "used"
                break
            end
        end
    end
    return { name = name, rank = text(learned.rank), rotation = rotation }
end

local ROTATION_LINE = {
    used = "Used by the rotation.",
    unused = "Not used by the rotation.",
    none = "No rotation is loaded for this character.",
}

-- The card's lines, plain text; {} for no card.
function S.Lines(card)
    if type(card) ~= "table" or not card.name then return {} end
    local first = "New spell: " .. card.name
    if card.rank then first = first .. " (" .. card.rank .. ")" end
    return { first, ROTATION_LINE[card.rotation] or ROTATION_LINE.none }
end
