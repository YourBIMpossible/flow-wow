-- The new-spell card (G33): what it says when the player learns a spell.
-- Pure: the learned spell comes in as { name =, rank = }. The card makes no
-- claim about the rotation: the only public rotation read today
-- (RotationReader.SpellNames) is the pack's whole spell catalogue, not
-- what the rotation casts (review zflow-aps-a-a-c2dcbd6, finding 1; the
-- needed function is posted as a ROTATION NEED). No game client.
local _, ns = ...

local function pack(names)
    local spells = {}
    for _, n in ipairs(names) do spells[n] = { evidence = "test" } end
    return { spells = spells }
end

local function says(lines, word)
    for _, l in ipairs(lines) do
        if l:lower():find(word, 1, true) then return true end
    end
    return false
end

return {
    ["card: name and rank, one line"] = function(t)
        local card = ns.SpellCard.Build({ name = "Moonfire", rank = "Rank 2" })
        t.eq(card, { name = "Moonfire", rank = "Rank 2" })
        t.eq(ns.SpellCard.Lines(card), { "New spell: Moonfire (Rank 2)" })
    end,

    ["card: a spell in the pack catalogue is not called 'used by the rotation'"] = function(t)
        -- Hibernate is in the Druid catalogue but no rotation rule casts it.
        local card = ns.SpellCard.Build({ name = "Hibernate", rank = "Rank 1" }, pack({ "Hibernate", "Wrath" }))
        t.eq(card.rotation, nil, "no rotation field")
        t.ok(not says(ns.SpellCard.Lines(card), "rotation"), "no rotation claim in the text")
    end,

    ["card: no rank from the client means no rank shown, never a guess"] = function(t)
        local card = ns.SpellCard.Build({ name = "Attack" })
        t.eq(card.rank, nil)
        t.eq(ns.SpellCard.Lines(card), { "New spell: Attack" })
        local blank = ns.SpellCard.Build({ name = "Attack", rank = "" })
        t.eq(blank.rank, nil, "an empty rank is no rank")
    end,

    ["card: nothing is built without a spell name"] = function(t)
        t.eq(ns.SpellCard.Build(nil), nil)
        t.eq(ns.SpellCard.Build({ rank = "Rank 1" }), nil)
        t.eq(ns.SpellCard.Build({ name = "" }), nil)
        t.eq(ns.SpellCard.Lines(nil), {})
    end,
}
