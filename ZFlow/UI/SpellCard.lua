local _, ns = ...

-- The new-spell card (G33): when the player learns a spell, a short card
-- with its name and its rank.
--
-- Pure. The learned spell comes in as { name =, rank = }, exactly as the
-- client reported it. Nothing is guessed: no rank from the client means no
-- rank on the card.
--
-- No rotation claim. G33 also asks whether the rotation uses the spell, but
-- the only public rotation read today, ns.RotationReader.SpellNames, is the
-- pack's whole spell catalogue (Hibernate, Aquatic Form, ...), not what the
-- rotation's rules cast. Until Rotation offers that (ROTATION NEED posted
-- with this fix), the card says nothing about the rotation rather than
-- something untrue.
--
-- Lead section 242: the second argument, the class pack, gives a tip line
-- when its spell row has a `tip` (help for a spell that is no rule: Mind
-- Soothe, Mind Control, Levitate). No pack or no tip: no tip line.
--
-- Not wired to the game yet: the client has no spell-learned event, so the
-- event and the frame that shows the card are a CLIENT NEED. Look-only: the
-- card casts, buys and changes nothing.

ns.SpellCard = {}
local S = ns.SpellCard

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- { name =, rank = (nil when not known), tip = (nil when none) }, or nil
-- when the learned spell has no name.
function S.Build(learned, pack)
    if type(learned) ~= "table" then return nil end
    local name = text(learned.name)
    if not name then return nil end
    local tip
    local spells = type(pack) == "table" and pack.spells or nil
    local row = type(spells) == "table" and spells[name] or nil
    if type(row) == "table" then tip = text(row.tip) end
    return { name = name, rank = text(learned.rank), tip = tip }
end

-- The card's lines, plain text; {} for no card.
function S.Lines(card)
    if type(card) ~= "table" or not card.name then return {} end
    local first = "New spell: " .. card.name
    if card.rank then first = first .. " (" .. card.rank .. ")" end
    if type(card.tip) == "string" then return { first, "Tip: " .. card.tip } end
    return { first }
end
