local _, ns = ...

-- Tests for ZFlow/Gear/Tooltip.lua. Pure: the scorer's answer and the
-- can-use answer are tables made here.

local T = ns.GearTooltip
local tests = {}

local YES = { can = true, why = "ok", reason = "you can use it" }

local function result(verdict, delta, slot, more)
    local r = { verdict = verdict, delta = delta, slot = slot, reason = "a reason" }
    for k, v in pairs(more or {}) do r[k] = v end
    return r
end

tests["tooltip line: an upgrade names the slot and the gain"] = function(t)
    local lines = T.Lines(result("upgrade", 6, "offHand"), YES)
    t.eq(lines, { { text = "Upgrade for your off hand (+6)", tone = "good" } })
    lines = T.Lines(result("upgrade", 2.26, "finger2"), YES)
    t.eq(lines[1].text, "Upgrade for your second ring (+2.3)", "a gain that is no whole number, to one place")
end

tests["tooltip line: the same and worse are said plainly"] = function(t)
    t.eq(T.Lines(result("same", 0, "head"), YES), { { text = "Same as your head piece", tone = "same" } })
    t.eq(T.Lines(result("worse", -8, "mainHand"), YES),
        { { text = "Not an upgrade for your main hand (-8)", tone = "bad" } })
end

tests["tooltip line: a two-hander is held up to both hands"] = function(t)
    local lines = T.Lines(result("upgrade", 1, "mainHand", { pair = true }), YES)
    t.eq(lines[1].text, "Upgrade for your main hand and off hand (+1)")
end

tests["tooltip line: the role is named when given"] = function(t)
    t.eq(T.Lines(result("upgrade", 6, "offHand"), YES, { role = "tank" })[1].text,
        "Upgrade for your off hand (+6, tank)")
    t.eq(T.Lines(result("same", 0, "head"), YES, { role = "tank" })[1].text, "Same as your head piece (tank)")
    t.eq(T.Lines(result("upgrade", 6, "offHand"), YES, { role = "" })[1].text, "Upgrade for your off hand (+6)")
    t.eq(T.Lines(result("upgrade", 6, "offHand"), YES, { role = 3 })[1].text, "Upgrade for your off hand (+6)")
end

tests["tooltip line: no recommendation says why, and never a number"] = function(t)
    local lines = T.Lines({ verdict = "none", reason = "what you wear in that slot is not known: head" }, YES)
    t.eq(lines, { { text = "No verdict: what you wear in that slot is not known: head", tone = "none" } })
    t.eq(T.Lines(nil, YES), { { text = "No verdict: " .. T.REASON.result, tone = "none" } })
    t.eq(T.Lines({ verdict = "none" }, YES)[1].text, "No verdict: " .. T.REASON.result)
    t.eq(T.Lines({ verdict = "sideways", delta = 3, slot = "head" }, YES)[1].tone, "none", "a verdict it does not know")
end

tests["G12: gear you cannot use says so, and is never an upgrade"] = function(t)
    local no = { can = false, why = "class", reason = "your class cannot use this kind of item" }
    local lines = T.Lines(result("upgrade", 50, "head"), no)
    t.eq(lines, { { text = "Can't use: your class cannot use this kind of item", tone = "bad" } })
    for _, line in ipairs(lines) do
        t.ok(not line.text:lower():find("upgrade", 1, true), "the word upgrade is not on it")
        t.ok(not line.text:find("50", 1, true), "nor the number")
    end
    lines = T.Lines(result("upgrade", 50, "head"), { can = false, why = "level", reason = "needs level 20" })
    t.eq(lines[1].text, "Can't use: needs level 20")
end

tests["G12: a can't-use that rests on a first guess says so"] = function(t)
    local no = { can = false, why = "class", reason = "your class cannot use this kind of item",
        evidence = "first guess" }
    t.eq(T.Lines(result("upgrade", 50, "head"), no)[1].text,
        "Can't use: your class cannot use this kind of item (first guess)")
    local level = { can = false, why = "level", reason = "needs level 20", evidence = "first guess" }
    t.eq(T.Lines(result("upgrade", 50, "head"), level)[1].text, "Can't use: needs level 20",
        "the level is read, not guessed")
end

tests["G12: not known whether you can use it is no verdict, never an upgrade"] = function(t)
    local unknown = { why = "unknown", reason = "the item's type is not known" }
    local lines = T.Lines(result("upgrade", 50, "head"), unknown)
    t.eq(lines, { { text = "No verdict: the item's type is not known", tone = "none" } })
    for _, use in ipairs({ false, {}, "yes" }) do
        lines = T.Lines(result("upgrade", 50, "head"), use or nil)
        t.eq(lines, { { text = "No verdict: " .. T.REASON.use, tone = "none" } })
    end
end

tests["tooltip line: the scorer's note is a second line"] = function(t)
    local note = "not known whether you can dual wield: compared with the main hand only"
    local lines = T.Lines(result("worse", -8, "mainHand", { note = note }), YES)
    t.eq(#lines, 2)
    t.eq(lines[2], { text = "Not known whether you can dual wield: compared with the main hand only", tone = "none" })
    lines = T.Lines({ verdict = "none", reason = "x", note = note }, YES)
    t.eq(#lines, 2, "also with no recommendation")
    lines = T.Lines(result("upgrade", 5, "head", { note = note }), { can = false, reason = "needs level 20" })
    t.eq(#lines, 1, "not under a can't-use")
end

tests["tooltip line: every slot the scorer names has words, and an unknown slot still reads"] = function(t)
    for _, slot in ipairs(ns.GearScore.SLOTS) do
        local text = T.Lines(result("upgrade", 1, slot), YES)[1].text
        t.ok(not text:find(slot, 1, true) or slot == "head" or slot == "neck" or slot == "back"
            or slot == "chest" or slot == "wrist" or slot == "hands" or slot == "waist" or slot == "legs"
            or slot == "feet" or slot == "shoulder" or slot == "ranged", slot .. ": " .. text)
        t.ok(text:find("^Upgrade for your %a"), text)
    end
    t.eq(T.Lines(result("upgrade", 1, "tail"), YES)[1].text, "Upgrade for what you wear (+1)")
    t.eq(T.Lines(result("upgrade", 1, nil), YES)[1].text, "Upgrade for what you wear (+1)")
end

tests["tooltip line: a gain that is no plain number is no verdict"] = function(t)
    local nan = 0 / 0
    for _, bad in ipairs({ false, "6", nan, math.huge }) do
        local lines = T.Lines(result("upgrade", bad or nil, "head"), YES)
        t.eq(lines[1].tone, "none", tostring(bad))
        t.eq(lines[1].text, "No verdict: " .. T.REASON.result)
    end
end

tests["tooltip line: no line spells the product, a bar or a line break"] = function(t)
    local all = {}
    local function keep(lines) for _, l in ipairs(lines) do all[#all + 1] = l.text end end
    keep(T.Lines(result("upgrade", 6, "offHand", { note = "a note" }), YES, { role = "dps" }))
    keep(T.Lines(result("worse", -6, "head"), YES))
    keep(T.Lines(result("same", 0, "head"), YES))
    keep(T.Lines(nil, YES))
    keep(T.Lines(result("upgrade", 6, "head"), { can = false, reason = "needs level 20" }))
    keep(T.Lines(result("upgrade", 6, "head"), nil))
    for _, text in ipairs(all) do
        t.ok(not text:lower():find("flow", 1, true), text)
        t.ok(not text:find("[|%c]"), text)
    end
    t.ok(#all >= 7)
end

tests["tooltip line P-Q: a gain or loss too small to show is the same, not an upgrade of +0.0"] = function(t)
    t.eq(T.Lines(result("upgrade", 0.04, "head"), YES), { { text = "Same as your head piece", tone = "same" } })
    t.eq(T.Lines(result("worse", -0.04, "head"), YES), { { text = "Same as your head piece", tone = "same" } })
    t.eq(T.Lines(result("upgrade", 1e-16, "head"), YES)[1].text, "Same as your head piece", "a rounding residue")
    t.eq(T.Lines(result("upgrade", 0.06, "head"), YES)[1].text, "Upgrade for your head piece (+0.1)")
    t.eq(T.Lines(result("worse", -0.06, "head"), YES)[1].text, "Not an upgrade for your head piece (-0.1)")
    t.eq(T.SAME, 0.05)
end

return tests
