-- The new-spell card (G33): what it says when the player learns a spell.
-- Pure: the learned spell comes in as { name =, rank = } and the rotation
-- is read through ns.RotationReader.SpellNames only. No game client.
local _, ns = ...

local function pack(names)
    local spells = {}
    for _, n in ipairs(names) do spells[n] = { evidence = "test" } end
    return { spells = spells }
end

return {
    ["card: name, rank and 'used by the rotation' when the pack names it"] = function(t)
        local card = ns.SpellCard.Build({ name = "Moonfire", rank = "Rank 2" }, pack({ "Wrath", "Moonfire" }))
        t.eq(card, { name = "Moonfire", rank = "Rank 2", rotation = "used" })
        t.eq(ns.SpellCard.Lines(card), { "New spell: Moonfire (Rank 2)", "Used by the rotation." })
    end,

    ["card: a spell the pack does not name says so"] = function(t)
        local card = ns.SpellCard.Build({ name = "Thorns", rank = "Rank 1" }, pack({ "Wrath" }))
        t.eq(card.rotation, "unused")
        t.eq(ns.SpellCard.Lines(card)[2], "Not used by the rotation.")
    end,

    ["card: no rotation loaded is not read as 'unused'"] = function(t)
        local card = ns.SpellCard.Build({ name = "Thorns", rank = "Rank 1" }, nil)
        t.eq(card.rotation, "none")
        t.eq(ns.SpellCard.Lines(card)[2], "No rotation is loaded for this character.")
    end,

    ["card: no rank from the client means no rank shown, never a guess"] = function(t)
        local card = ns.SpellCard.Build({ name = "Attack" }, pack({ "Attack" }))
        t.eq(card.rank, nil)
        t.eq(ns.SpellCard.Lines(card)[1], "New spell: Attack")
        local blank = ns.SpellCard.Build({ name = "Attack", rank = "" }, pack({ "Attack" }))
        t.eq(blank.rank, nil, "an empty rank is no rank")
    end,

    ["card: nothing is built without a spell name"] = function(t)
        t.eq(ns.SpellCard.Build(nil, pack({ "Wrath" })), nil)
        t.eq(ns.SpellCard.Build({ rank = "Rank 1" }, pack({ "Wrath" })), nil)
        t.eq(ns.SpellCard.Build({ name = "" }, pack({ "Wrath" })), nil)
        t.eq(ns.SpellCard.Lines(nil), {})
    end,

    ["card: the rotation is read through RotationReader.SpellNames only"] = function(t)
        local real = ns.RotationReader.SpellNames
        local asked = 0
        ns.RotationReader.SpellNames = function(p) asked = asked + 1; return real(p) end
        local ok, card = pcall(ns.SpellCard.Build, { name = "Wrath" }, pack({ "Wrath" }))
        ns.RotationReader.SpellNames = real
        t.ok(ok, "built")
        t.eq(asked, 1, "asked once")
        t.eq(card and card.rotation, "used")
    end,
}
