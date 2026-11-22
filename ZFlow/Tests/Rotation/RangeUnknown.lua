local _, ns = ...

-- A range nobody read is not "in range": a rule that needs range is not
-- suggested, and the step that passed it by names it. Rows here carry no
-- inRange unless the test gives one.

local R = ns.Rotation

local RANGE = "not known whether it is in range"
local COOLDOWN = "not known whether it is ready"
local TARGET = "not known whether you have a target"

local function rule(spell, extra)
    local r = { spell = spell, evidence = "first guess" }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

local function pack(list)
    return {
        lists = { default = list or { rule("Bolt", { target = true }) } },
        interrupts = { rule("Kick", { near = true }), rule("Silence") },
    }
end

-- In a fight, an enemy targeted, every named spell known and off cooldown,
-- its range not read.
local function snap(known, over)
    local s = { dead = false, inCombat = true, hostile = true, spells = {} }
    for _, name in ipairs(known or {}) do s.spells[name] = { known = true, onCooldown = false } end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function rowOf(trace, step)
    for _, row in ipairs(trace) do
        if row.step == step then return row end
    end
    return nil
end

return {
    ["the reason has its own words"] = function(t)
        t.eq(R.RANGE_UNKNOWN, RANGE, "the words")
        t.ok(R.RANGE_UNKNOWN ~= R.COOLDOWN_UNKNOWN, "not the cooldown reason")
        t.ok(R.RANGE_UNKNOWN ~= R.TARGET_UNKNOWN, "not the target reason")
    end,

    ["Ready: a range not read is a no with the reason, only when range is needed"] = function(t)
        local s = snap({ "Bolt" })
        local ok, why = R.Ready(s, "Bolt", true)
        t.eq(ok, false, "range needed, not read: not ready")
        t.eq(why, RANGE, "and the reason says so")
        ok, why = R.Ready(s, "Bolt")
        t.eq(ok, true, "range not needed: ready")
        t.eq(why, nil, "no reason")
        s.spells.Bolt.inRange = true
        ok, why = R.Ready(s, "Bolt", true)
        t.eq(ok, true, "read as in range: ready")
        t.eq(why, nil, "no reason")
        s.spells.Bolt.inRange = false
        ok, why = R.Ready(s, "Bolt", true)
        t.eq(ok, false, "read as out of range: not ready")
        t.eq(why, nil, "a known no carries no reason")
    end,

    ["Ready: the cooldown is asked before the range"] = function(t)
        local s = snap({ "Bolt" })
        s.spells.Bolt.onCooldown = nil
        local ok, why = R.Ready(s, "Bolt", true)
        t.eq(ok, false, "not ready")
        t.eq(why, COOLDOWN, "named for the cooldown")
        s.spells.Bolt.onCooldown = true
        ok, why = R.Ready(s, "Bolt", true)
        t.eq(ok, false, "on cooldown: not ready")
        t.eq(why, nil, "a known no carries no reason")
    end,

    ["Castable does not ask about range"] = function(t)
        local ok, why = R.Castable(snap({ "Bolt" }), "Bolt")
        t.eq(ok, true, "castable")
        t.eq(why, nil, "no reason")
    end,

    ["an enemy targeted, range not read: nothing is suggested and the list names the spell"] = function(t)
        local s, trace = ns.Choose(snap({ "Bolt" }), pack())
        t.eq(s, nil, "nothing suggested")
        local list = rowOf(trace, "list")
        t.eq(list.result, "skip", "the list step answered nothing")
        t.eq(list.note, "no rule ready; " .. RANGE .. ": Bolt", "and says why")
        t.eq(list.passed, nil, "passed is for a cooldown not read only")
        t.eq(rowOf(trace, "farOpener").note, "nothing out of range", "not read is not out of range either")
    end,

    ["range read as in range: the rule is suggested"] = function(t)
        local snapshot = snap({ "Bolt" })
        snapshot.spells.Bolt.inRange = true
        local s = ns.Choose(snapshot, pack())
        t.eq(s and s.spell, "Bolt", "suggested")
        t.eq(s and s.step, "list", "by the list")
    end,

    ["range read as out of range: a plain no in the list, and the far opener answers"] = function(t)
        local snapshot = snap({ "Bolt" })
        snapshot.spells.Bolt.inRange = false
        local s, trace = ns.Choose(snapshot, pack())
        t.eq(rowOf(trace, "list").note, "no rule ready", "no reason named for a known no")
        t.eq(s and s.spell, "Bolt", "the far opener")
        t.eq(s and s.step, "farOpener", "its step")
    end,

    ["a rule that needs no target does not need range"] = function(t)
        local p = pack({ rule("Bolt", { target = true }), rule("Shield", { kind = "buff" }) })
        local s, trace = ns.Choose(snap({ "Bolt", "Shield" }), p)
        t.eq(s and s.spell, "Shield", "the rule after it is suggested")
        t.eq(rowOf(trace, "list").result, "pick", "by the list")
    end,

    ["each spell is named once, sorted"] = function(t)
        local p = pack({ rule("Zap", { target = true }), rule("Bolt", { target = true }), rule("Zap", { target = true }) })
        local _, trace = ns.Choose(snap({ "Bolt", "Zap" }), p)
        t.eq(rowOf(trace, "list").note, "no rule ready; " .. RANGE .. ": Bolt, Zap", "once each, sorted")
    end,

    ["only a spell that the range alone stops is named"] = function(t)
        local p = pack({
            rule("Unknown", { target = true }),
            rule("Skipped", { target = true }),
            rule("Unusable", { target = true }),
            rule("Cooling", { target = true }),
            rule("Unwanted", { target = true, when = function() return false end }),
            rule("Far", { target = true }),
        })
        local snapshot = snap({ "Skipped", "Unusable", "Cooling", "Unwanted", "Far" })
        snapshot.spells.Unusable.usable = false
        snapshot.spells.Cooling.onCooldown = true
        snapshot.spells.Far.inRange = false
        local _, trace = ns.Choose(snapshot, p, { skip = { Skipped = true } })
        t.eq(rowOf(trace, "list").note, "no rule ready", "none of them is named for range")
    end,

    ["the cooldown reason comes before the range reason"] = function(t)
        local p = pack({ rule("Slow", { target = true }), rule("Bolt", { target = true }) })
        local snapshot = snap({ "Slow", "Bolt" })
        snapshot.spells.Slow.onCooldown = nil
        local _, trace = ns.Choose(snapshot, p)
        local list = rowOf(trace, "list")
        t.eq(list.note, "no rule ready; " .. COOLDOWN .. ": Slow; " .. RANGE .. ": Bolt", "cooldown, then range")
        t.eq(list.passed, { "Slow" }, "passed holds the cooldown one only")
    end,

    ["a target not read is asked before the range"] = function(t)
        local snapshot = snap({ "Bolt" })
        snapshot.hostile = nil
        local _, trace = ns.Choose(snapshot, pack())
        t.eq(rowOf(trace, "list").note, "no rule ready; " .. TARGET .. ": Bolt", "named for the target, not for range")
    end,

    ["in a group of adaptive rules the one whose range is not read is not chosen"] = function(t)
        local p = pack({ rule("Bolt", { target = true, adaptive = true }), rule("Zap", { target = true, adaptive = true }) })
        local snapshot = snap({ "Bolt", "Zap" })
        snapshot.spells.Zap.inRange = true
        local s = ns.Choose(snapshot, p, nil, { Bolt = 1 })
        t.eq(s and s.spell, "Zap", "the one read as in range")
        snapshot.spells.Zap.inRange = nil
        local none, trace = ns.Choose(snapshot, p, nil, { Bolt = 1 })
        t.eq(none, nil, "neither")
        t.eq(rowOf(trace, "list").note, "no rule ready; " .. RANGE .. ": Bolt, Zap", "both named")
    end,

    ["an interrupt that needs range is not suggested while its range is not read"] = function(t)
        local s, trace = ns.Choose(snap({ "Silence" }, { targetCasting = "Fireball" }), pack({}))
        t.eq(s, nil, "nothing suggested")
        t.eq(rowOf(trace, "interrupt").note, "no interrupt ready; " .. RANGE .. ": Silence", "and the step says why")
        t.eq(rowOf(trace, "interrupt").passed, nil, "passed is for a cooldown not read only")
    end,

    ["an interrupt read as in range is suggested; a near one does not ask for range"] = function(t)
        local snapshot = snap({ "Silence" }, { targetCasting = "Fireball" })
        snapshot.spells.Silence.inRange = true
        local s = ns.Choose(snapshot, pack({}))
        t.eq(s and s.spell, "Silence", "read as in range")
        s = ns.Choose(snap({ "Kick" }, { targetCasting = "Fireball", targetNear = true }), pack({}))
        t.eq(s and s.spell, "Kick", "near is its own read")
    end,

    ["target not read: the list says so once, whatever the rules own conditions answered"] = function(t)
        local p = pack({
            rule("Bolt", { target = true, when = function(s) return s.hostile == true end }),
            rule("Zap", { target = true, when = function(s) return s.hostile == true end }),
        })
        local snapshot = snap({ "Bolt", "Zap" })
        snapshot.hostile = nil
        local s, trace = ns.Choose(snapshot, p)
        t.eq(s, nil, "nothing suggested")
        t.eq(rowOf(trace, "list").note, "no rule ready; " .. TARGET, "said once, no spell named")
        p.lists.default[3] = rule("Storm", { target = true })
        snapshot.spells.Storm = { known = true, onCooldown = false }
        _, trace = ns.Choose(snapshot, p)
        t.eq(rowOf(trace, "list").note, "no rule ready; " .. TARGET .. ": Storm", "still once when a spell is named")
    end,
}
