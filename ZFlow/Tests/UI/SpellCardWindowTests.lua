-- The new-spell card window (G33, lead section 402 item 5): what the card
-- says and where the spell sits. Pure parts first. The "put it on a bar"
-- line is advice: nothing here places, binds or casts a spell. Made-up
-- spells and slots. Not tested in game.
local _, ns = ...

local S = ns.SpellCard
local tests = {}

local function texts(kids)
    local out = {}
    for _, p in ipairs(kids or {}) do out[#out + 1] = ns.Kit.TextOf(p) end
    return out
end

tests["spell card where: the newest slot the game put the spell in, else nil"] = function(t)
    local placed = { { id = 8921, slot = 3 }, { id = 774, slot = 4 }, { id = 8921, slot = 15 } }
    t.eq(S.Where(8921, placed), 15, "the newest row wins")
    t.eq(S.Where(774, placed), 4)
    t.eq(S.Where(5176, placed), nil, "never placed by the game")
    t.eq(S.Where(nil, placed), nil, "no id: no claim")
    t.eq(S.Where(8921, nil), nil)
    t.eq(S.Where(8921, { "x", { id = 8921 } }), nil, "a row with no slot is no place")
end

tests["spell card where line: the bar and slot, a bare slot, or the advice"] = function(t)
    t.eq(S.WhereLine("Moonfire", 3), "On your bars: Action Bar 1, slot 3 (the game put it there).")
    t.eq(S.WhereLine("Moonfire", 14), "On your bars, slot 14 (the game put it there).", "a slot no bar is named for")
    t.eq(S.WhereLine("Moonfire", nil),
        "Put it on a bar: open your spellbook and drag Moonfire to an action bar.")
end

tests["spell card children: a header, the spell with its tip, and where it sits"] = function(t)
    local card = S.Build({ name = "Moonfire", rank = "Rank 2" })
    local kids = S.Children(card, nil)
    t.eq(texts(kids), { S.HEADER, "Moonfire (Rank 2)",
        "Put it on a bar: open your spellbook and drag Moonfire to an action bar." })
    t.eq(kids[3].key, "where")
    local tipped = S.Children({ name = "Fade", tip = "Drops your threat." }, 5)
    t.eq(tipped[2].sub, "Tip: Drops your threat.")
    t.eq(ns.Kit.TextOf(tipped[3]), "On your bars: Action Bar 1, slot 5 (the game put it there).")
    t.eq(S.Children(nil, nil), nil, "no card: no window")
end

tests["spell card children: the window the kit accepts"] = function(t)
    local tree, why = ns.Kit.Window({ id = S.ID, title = "Z-Flow: " .. S.HEADER,
        children = S.Children(S.Build({ name = "Moonfire" }), nil) })
    t.ok(tree ~= nil, tostring(why))
end

tests["spell card: show and advise only - nothing places, binds or casts"] = function(t)
    for name in pairs(S) do
        local n = tostring(name):lower()
        t.ok(not (n:find("cast") or n:find("bind") or n:find("pickup") or n:find("place") or n:find("click")),
            "no acting function: " .. n)
    end
end

return tests
