local _, ns = ...

-- Tests for ZFlow/Gear/WeaponSpeed.lua. Pure: the weapon is a table made
-- here.

local W = ns.GearWeaponSpeed
local tests = {}

local DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"

local function weapon(speed, dps, kind)
    return { kind = kind or "INVTYPE_WEAPON", speed = speed, dps = dps }
end

tests["weapon speed: slow, medium and fast by the two marks"] = function(t)
    t.eq(W.Feel(3.3), "slow")
    t.eq(W.Feel(3.8), "slow")
    t.eq(W.Feel(3.29), "medium")
    t.eq(W.Feel(2.6), "medium")
    t.eq(W.Feel(2.01), "medium")
    t.eq(W.Feel(2.0), "fast")
    t.eq(W.Feel(1.5), "fast")
    t.eq({ W.SLOW, W.FAST }, { 3.3, 2.0 })
end

tests["weapon speed: a speed that is no number above zero has no feel"] = function(t)
    local nan = 0 / 0
    for _, bad in ipairs({ false, "2.6", 0, -1, nan, math.huge }) do
        t.eq(W.Feel(bad or nil), nil, tostring(bad))
    end
end

tests["weapon speed: the line gives the speed, its feel and the damage per second"] = function(t)
    t.eq(W.Line(weapon(2.6, 41.5)), { text = "Speed 2.60 (medium), 41.5 damage per second", tone = "none" })
    t.eq(W.Line(weapon(3.4, 60)).text, "Speed 3.40 (slow), 60.0 damage per second")
    t.eq(W.Line(weapon(1.8, 22.26)).text, "Speed 1.80 (fast), 22.3 damage per second")
end

tests["weapon speed: damage per second not read is left out, never shown as 0"] = function(t)
    local nan = 0 / 0
    for _, bad in ipairs({ false, "41", nan, math.huge, -3 }) do
        local line = W.Line(weapon(2.6, bad or nil))
        t.eq(line.text, "Speed 2.60 (medium)", tostring(bad))
    end
    t.eq(W.Line(weapon(2.6, 0)).text, "Speed 2.60 (medium), 0.0 damage per second", "a read 0 is a 0")
end

tests["weapon speed: no speed read is no line"] = function(t)
    t.eq(W.Line(weapon(nil, 41.5)), nil)
    t.eq(W.Line(weapon("2.6", 41.5)), nil)
    t.eq(W.Line(weapon(0, 41.5)), nil)
end

tests["weapon speed: only weapons get a line"] = function(t)
    for _, kind in ipairs({ "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND",
        "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" }) do
        t.ok(W.Line(weapon(2.6, 10, kind)) ~= nil, kind)
    end
    for _, kind in ipairs({ "INVTYPE_HEAD", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RELIC", "INVTYPE_BAG", "" }) do
        t.eq(W.Line(weapon(2.6, 10, kind)), nil, kind)
    end
    t.eq(W.Line({ speed = 2.6, dps = 10 }), nil, "no kind read")
    t.eq(W.Line(nil), nil)
    t.eq(W.Line("a sword"), nil)
end

tests["weapon speed: a role's preference is said when the class data has one"] = function(t)
    local prefs = { dps = { prefer = "slow" }, tank = { prefer = "fast" } }
    t.eq(W.Line(weapon(3.4, 60), prefs).text,
        "Speed 3.40 (slow), 60.0 damage per second; good for dps; tank prefers fast")
    t.eq(W.Line(weapon(1.8, nil), prefs).text, "Speed 1.80 (fast); dps prefers slow; good for tank")
    t.eq(W.Line(weapon(2.6, nil), prefs).text, "Speed 2.60 (medium); dps prefers slow; tank prefers fast")
end

tests["weapon speed: a preference that is not one of the three feels is not said"] = function(t)
    local prefs = { dps = { prefer = "heavy" }, tank = "fast", heal = {}, [1] = { prefer = "slow" } }
    t.eq(W.Line(weapon(3.4, nil), prefs).text, "Speed 3.40 (slow)")
    t.eq(W.Line(weapon(3.4, nil), "slow").text, "Speed 3.40 (slow)")
    t.eq(W.Line(weapon(3.4, nil), nil).text, "Speed 3.40 (slow)")
end

tests["weapon speed: From takes the weapon out of the client's gear answer"] = function(t)
    local gear = { kind = "INVTYPE_2HWEAPON", speed = 3.6, stats = { [DPS] = 55.5, ITEM_MOD_STRENGTH_SHORT = 9 } }
    t.eq(W.From(gear), { kind = "INVTYPE_2HWEAPON", speed = 3.6, dps = 55.5 })
    t.eq(W.Line(W.From(gear)).text, "Speed 3.60 (slow), 55.5 damage per second")
    t.eq(W.From({ kind = "INVTYPE_WEAPON", speed = 2.6 }), { kind = "INVTYPE_WEAPON", speed = 2.6 }, "no stats read")
    t.eq(W.From({ kind = "INVTYPE_WEAPON", speed = 2.6, stats = { [DPS] = false } }).dps, nil,
        "a damage figure that was not read stays out")
    t.eq(W.From({ kind = "INVTYPE_WEAPON", stats = { [DPS] = 10 } }).speed, nil, "today's client: no speed")
    t.eq(W.Line(W.From({ kind = "INVTYPE_WEAPON", stats = { [DPS] = 10 } })), nil, "so no line today")
    t.eq(W.From(nil), {})
end

tests["weapon speed: nothing handed in is changed, and the text has no product name or bar"] = function(t)
    local w, prefs = weapon(3.4, 60), { dps = { prefer = "slow" } }
    local line = W.Line(w, prefs)
    t.eq(w, { kind = "INVTYPE_WEAPON", speed = 3.4, dps = 60 })
    t.eq(prefs, { dps = { prefer = "slow" } })
    t.ok(not line.text:lower():find("flow", 1, true))
    t.ok(not line.text:find("[|%c]"))
end

return tests
