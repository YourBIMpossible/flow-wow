local _, ns = ...

-- Tests for ZFlow/Items/TooltipDisposition.lua. The decisions come from
-- Items/Disposition.lua's own Decide where a built-in rule gives the case,
-- and are written out by hand where one case is wanted exactly.

local T = ns.TooltipDisposition
local D = ns.Disposition
local tests = {}

local function texts(lines)
    local out = {}
    for i = 1, #(lines or {}) do out[i] = lines[i].text end
    return out
end

tests["disposition line: a keep says why"] = function(t)
    local lines = T.Lines({ action = "keep", reason = "quest item", basis = "fact", reasons = { "quest item" } })
    t.eq(lines, { { text = "Keep: quest item", tone = "same" } })
end

tests["disposition line: every keep reason is given, the deciding one first"] = function(t)
    local lines = T.Lines({ action = "keep", reason = "quest item", basis = "fact",
        reasons = { "quest item", "tool for Mining", "on your never-sell list" } })
    t.eq(texts(lines), { "Keep: quest item; tool for Mining; on your never-sell list" })
end

tests["disposition line: more than four keep reasons are counted, not all listed"] = function(t)
    local lines = T.Lines({ action = "keep", reason = "a", basis = "fact", reasons = { "a", "b", "c", "d", "e", "f" } })
    t.eq(texts(lines), { "Keep: a; b; c; d and 2 more" })
    t.eq(T.MAX, 4)
end

tests["disposition line: what would happen is said as would, never as done"] = function(t)
    t.eq(texts(T.Lines({ action = "sell", reason = "junk", basis = "recommendation" })),
        { "Would sell: junk (suggested)" })
    t.eq(texts(T.Lines({ action = "auction", reason = "worth more at auction", basis = "recommendation" })),
        { "Would auction: worth more at auction (suggested)" })
    t.eq(texts(T.Lines({ action = "disenchant", reason = "no use to you", basis = "recommendation" })),
        { "Would disenchant: no use to you (suggested)" })
    t.eq(texts(T.Lines({ action = "equip", reason = "better for dps", basis = "recommendation" })),
        { "Would equip: better for dps (suggested)" })
    t.eq(T.Lines({ action = "sell", reason = "junk", basis = "recommendation" })[1].tone, "none")
    t.eq(T.Lines({ action = "equip", reason = "x", basis = "recommendation" })[1].tone, "good")
end

tests["disposition line: a choice or a fact is not marked as a suggestion; a suggestion is"] = function(t)
    t.eq(texts(T.Lines({ action = "keep", reason = "you chose to keep it", basis = "choice" })),
        { "Keep: you chose to keep it" })
    t.eq(texts(T.Lines({ action = "keep", reason = "better for Balance", basis = "recommendation" })),
        { "Keep: better for Balance (suggested)" })
    t.eq(texts(T.Lines({ action = "keep", reason = "nothing is known about it", basis = "unknown" })),
        { "Keep: nothing is known about it (not known)" })
end

tests["disposition line: a split decision gives a line for each part, with its count"] = function(t)
    local lines = T.Lines({ action = "keep", count = 8, reason = "held for Mining", basis = "fact",
        reasons = { "held for Mining" },
        rest = { action = "sell", count = 4, reason = "junk", basis = "recommendation" } })
    t.eq(texts(lines), { "Keep 8: held for Mining", "Would sell 4: junk (suggested)" })
end

tests["disposition line: a count is given only where the decision is split"] = function(t)
    t.eq(texts(T.Lines({ action = "sell", count = 12, reason = "junk", basis = "recommendation" })),
        { "Would sell: junk (suggested)" })
    local lines = T.Lines({ action = "keep", reason = "held", basis = "fact",
        rest = { action = "sell", reason = "junk", basis = "recommendation" } })
    t.eq(texts(lines), { "Keep: held", "Would sell: junk (suggested)" }, "counts not known: none is made up")
end

tests["disposition line: no reason is the action alone, and odd reasons are left out"] = function(t)
    local bar = string.char(124)
    t.eq(texts(T.Lines({ action = "sell", basis = "fact" })), { "Would sell" })
    t.eq(texts(T.Lines({ action = "keep", reason = "", basis = "fact" })), { "Keep" })
    t.eq(texts(T.Lines({ action = "keep", reason = 7, basis = "fact" })), { "Keep" })
    t.eq(texts(T.Lines({ action = "keep", reason = "a" .. bar .. "b", basis = "fact" })), { "Keep" })
    t.eq(texts(T.Lines({ action = "keep", reason = "ok", basis = "fact", reasons = { "ok", bar, 3, "", "ok", "more" } })),
        { "Keep: ok; more" }, "shown once each, the unshowable ones dropped")
end

tests["disposition line: what is no decision gets no line"] = function(t)
    t.eq(T.Lines(nil), nil)
    t.eq(T.Lines("keep"), nil)
    t.eq(T.Lines({}), nil)
    t.eq(T.Lines({ action = "destroy", reason = "x" }), nil, "an action it does not know")
    t.eq(T.Lines({ action = "mail", reason = "x" }), nil)
end

tests["disposition line: a bank note is one more line, as would"] = function(t)
    local lines = T.Lines({ action = "keep", reason = "held for Mining", basis = "fact" },
        { bank = "reserved for Mining, not needed soon" })
    t.eq(texts(lines), { "Keep: held for Mining", "Would bank: reserved for Mining, not needed soon" })
    t.eq(texts(T.Lines({ action = "keep", reason = "x", basis = "fact" }, { bank = true })),
        { "Keep: x", "Would bank" })
    t.eq(texts(T.Lines({ action = "keep", reason = "x", basis = "fact" }, { bank = false })), { "Keep: x" })
    t.eq(texts(T.Lines({ action = "keep", reason = "x", basis = "fact" }, {})), { "Keep: x" })
    t.eq(T.Lines(nil, { bank = "x" }), nil, "no decision: nothing is said, the bank note neither")
end

tests["disposition line: a rest chain that loops or runs long stops"] = function(t)
    local d = { action = "keep", count = 1, reason = "a", basis = "fact" }
    d.rest = d
    local lines = T.Lines(d)
    t.ok(#lines <= T.PARTS, "no more lines than parts allowed")
    t.eq(T.PARTS, 4)
end

tests["disposition line: Disposition.Decide's own answers read as lines"] = function(t)
    local junk = D.Decide({ key = 1, name = "Broken Fang", count = 3, quality = 0, sellPrice = 5 }, {})
    local lines = T.Lines(junk)
    t.eq(type(lines), "table")
    t.ok(#lines >= 1)
    for _, line in ipairs(lines) do
        t.ok(line.text:find("^Keep") or line.text:find("^Would "), line.text)
    end
    local unreadable = D.Decide(nil, {})
    t.eq(texts(T.Lines(unreadable)), { "Keep: not a readable item (not known)" })
    local never = D.Decide({ key = 9, name = "Heirloom", count = 1, quality = 1, sellPrice = 10 },
        { choices = { never = { [9] = true } } })
    t.ok(T.Lines(never)[1].text:find("^Keep: "), T.Lines(never)[1].text)
end

tests["disposition line: nothing handed in is changed, and no line names the product"] = function(t)
    local d = { action = "keep", reason = "quest item", basis = "fact", reasons = { "quest item", "tool" } }
    local lines = T.Lines(d, { bank = "x" })
    t.eq(d, { action = "keep", reason = "quest item", basis = "fact", reasons = { "quest item", "tool" } })
    for _, line in ipairs(lines) do
        t.ok(not line.text:lower():find("flow", 1, true))
        t.ok(not line.text:find("[|%c]"))
    end
end

return tests
