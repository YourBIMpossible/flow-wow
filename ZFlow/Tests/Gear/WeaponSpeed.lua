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

-- G15 (lead section 275 item 3): the class data's reason goes after the
-- role, as words in brackets; a reason that is not words is left out.
tests["weapon speed: a preference's reason is said after it"] = function(t)
    local prefs = { dps = { prefer = "slow", why = "big hits" }, tank = { prefer = "medium", why = "steady threat" } }
    t.eq(W.Line(weapon(3.6, nil), prefs).text,
        "Speed 3.60 (slow); good for dps (big hits); tank prefers medium (steady threat)")
    for _, bad in ipairs({ "", false, 7 }) do
        t.eq(W.Line(weapon(3.6, nil), { dps = { prefer = "slow", why = bad } }).text,
            "Speed 3.60 (slow); good for dps", tostring(bad))
    end
end

-- Lead section 280: a role speed does not matter for says so ("any"), with
-- the class data's reason; never "prefers any", never left out.
tests["weapon speed: a role that speed does not matter for says so, with the reason"] = function(t)
    local prefs = { dps = { prefer = "any", why = "spells do the damage" } }
    t.eq(W.Line(weapon(3.0, nil, "INVTYPE_2HWEAPON"), prefs).text,
        "Speed 3.00 (medium); speed does not matter for dps (stats do): spells do the damage")
    t.eq(W.Line(weapon(3.6, 50), { heal = { prefer = "any" } }).text,
        "Speed 3.60 (slow), 50.0 damage per second; speed does not matter for heal (stats do)", "no reason given")
    local both = { dps = { prefer = "fast", why = "more swings" }, heal = { prefer = "any", why = "no swings" } }
    t.eq(W.Line(weapon(1.8, nil), both).text,
        "Speed 1.80 (fast); good for dps (more swings); speed does not matter for heal (stats do): no swings")
    t.eq(W.ANY, "any")
end

-- A hunter: a slow bow or gun matters, the melee weapon's speed does not.
-- The role's `ranged` part speaks for a weapon of the ranged slot.
tests["weapon speed: a role's ranged part speaks for a bow, a gun and a thrown weapon only"] = function(t)
    local prefs = { dps = { prefer = "any", why = "shots do the damage",
                            ranged = { prefer = "slow", why = "shots hit for weapon damage" } } }
    for _, kind in ipairs({ "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" }) do
        t.eq(W.Line(weapon(3.4, nil, kind), prefs).text,
            "Speed 3.40 (slow); good for dps (shots hit for weapon damage)", kind)
        t.eq(W.Line(weapon(2.2, nil, kind), prefs).text,
            "Speed 2.20 (medium); dps prefers slow (shots hit for weapon damage)", kind .. ", not slow")
    end
    for _, kind in ipairs({ "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" }) do
        t.eq(W.Line(weapon(3.4, nil, kind), prefs).text,
            "Speed 3.40 (slow); speed does not matter for dps (stats do): shots do the damage", kind)
    end
    t.eq(W.Line(weapon(3.4, nil, "INVTYPE_RANGED"), { dps = { prefer = "slow", why = "big hits" } }).text,
        "Speed 3.40 (slow); good for dps (big hits)", "no ranged part: the role's own")
    t.eq(W.Line(weapon(3.4, nil, "INVTYPE_RANGED"), { dps = { prefer = "fast", ranged = "slow" } }).text,
        "Speed 3.40 (slow); dps prefers fast", "a ranged part that is no table: the role's own")
end

-- A rogue: a slow main hand, a fast off hand. The role's `offhand` part
-- speaks for a weapon that only goes in the off hand.
tests["weapon speed: a role's off hand part speaks for an off hand weapon only"] = function(t)
    local prefs = { dps = { prefer = "slow", why = "big strikes",
                            offhand = { prefer = "fast", why = "more poison" } } }
    t.eq(W.Line(weapon(1.5, nil, "INVTYPE_WEAPONOFFHAND"), prefs).text, "Speed 1.50 (fast); good for dps (more poison)")
    t.eq(W.Line(weapon(3.4, nil, "INVTYPE_WEAPONOFFHAND"), prefs).text, "Speed 3.40 (slow); dps prefers fast (more poison)")
    for _, kind in ipairs({ "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON", "INVTYPE_RANGED" }) do
        t.eq(W.Line(weapon(1.5, nil, kind), prefs).text, "Speed 1.50 (fast); dps prefers slow (big strikes)", kind)
    end
end

tests["weapon speed: a part with no speed of its own is not said"] = function(t)
    local prefs = { dps = { prefer = "slow", ranged = { why = "no speed here" } } }
    t.eq(W.Line(weapon(3.4, nil, "INVTYPE_RANGED"), prefs).text, "Speed 3.40 (slow)")
    t.eq(W.Line(weapon(3.4, nil, "INVTYPE_WEAPON"), prefs).text, "Speed 3.40 (slow); good for dps")
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
