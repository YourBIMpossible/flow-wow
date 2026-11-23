local _, ns = ...

-- Minimum range (lead section 197, the Hunter plan's shared gap). The
-- client's range read answers "not in range" both too far away and inside a
-- ranged spell's dead zone, so for a pack that says its spells have a
-- minimum range (options.minRange = true) the out-of-range step and the
-- diag line must not tell the player only to move closer. Offline: made-up
-- snapshots and views.

local D = ns.RotationDriver
local tests = {}

local function pack(minRange)
    return {
        spells = { Shot = { evidence = "first guess" } },
        lists = { default = { { spell = "Shot", target = true, reason = "Shoot it", evidence = "first guess" } } },
        options = { minRange = minRange },
    }
end

local function snap()
    return ns.SnapshotOf({ dead = false, inCombat = true, hostile = true,
        spells = { Shot = { known = true, usable = true, onCooldown = false, inRange = false } } })
end

tests["min range: the out-of-range step says too far or too close for a pack with a minimum range"] = function(t)
    local s = ns.Choose(snap(), pack(true))
    t.eq(s and s.step, "farOpener")
    t.eq(s and s.minRange, true, "marked as a spell with a minimum range")
    t.eq(s and s.reason, "Shoot it (out of range: too far or too close)")
    t.eq(s and s.label, "Out of range", "the icon's label is unchanged")
end

tests["min range: a pack without it keeps the plain out-of-range step"] = function(t)
    for _, minRange in ipairs({ false, "yes" }) do
        local s = ns.Choose(snap(), pack(minRange))
        t.eq(s and s.step, "farOpener", tostring(minRange))
        t.eq(s and s.minRange, nil, tostring(minRange))
        t.eq(s and s.reason, "Shoot it (out of range)", tostring(minRange))
    end
    local s = ns.Choose(snap(), pack(nil))
    t.eq(s and s.reason, "Shoot it (out of range)", "no option")
end

local function view(suggestion)
    local v = {
        pack = true,
        snapshot = { dead = false, inCombat = false, stealthed = false, spells = {} },
        suggestion = suggestion,
        trace = { { step = "farOpener", result = "pick", spell = suggestion.spell, note = suggestion.reason } },
        lockdown = false, keys = { ok = true, ops = {} },
        unread = {}, missing = {}, passed = {}, notRead = {},
    }
    v.why = D.Why(v.snapshot, v.trace, v.keys, v.lockdown)
    return v
end

tests["min range: the diag line does not say move closer inside a dead zone"] = function(t)
    local line = ns.Diag.RotationLine("started",
        view({ spell = "Arcane Shot", reason = "x", step = "farOpener", minRange = true }), true)
    t.eq(line, "rotation: Arcane Shot is next, but out of range: too far away or too close (farOpener).")
    t.ok(not line:find("move closer", 1, true), line)
end

tests["min range: without it the diag line still says move closer"] = function(t)
    local line = ns.Diag.RotationLine("started", view({ spell = "Judgement", reason = "x", step = "farOpener" }), true)
    t.eq(line, "rotation: Judgement is next, but out of range: move closer (farOpener).")
end

return tests
