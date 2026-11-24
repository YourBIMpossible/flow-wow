local _, ns = ...
-- Tests for ZFlow/Nav/TravelAdvice.lua (S33, lead dispatch section 395
-- item 4): the pure parts, when a travel spell or a ride is advised and
-- the words. Advice only: nothing here casts or summons. Made-up maps.
local tests = {}
local function T() return ns.TravelAdvice or {} end

-- Two maps on continent 0, one on continent 1; shares * 3000 yards.
local A, B, FAR = 9001, 9002, 9003
local CORNERS = {
    [A] = { cont = 0, ox = 0, oy = 0, ex = 3000, ey = 0, sx = 0, sy = 3000 },
    [B] = { cont = 0, ox = 3000, oy = 0, ex = 6000, ey = 0, sx = 3000, sy = 3000 },
    [FAR] = { cont = 1, ox = 0, oy = 0, ex = 3000, ey = 0, sx = 0, sy = 3000 },
}
local function cornersOf(map) return CORNERS[map] end

-- A table cannot hold "set this to nil", so a helper given NONE for a
-- field takes the field away (a value the game did not say).
local NONE = {}
local function put(o, over)
    for key, v in pairs(over or {}) do
        if v == NONE then o[key] = nil else o[key] = v end
    end
    return o
end

-- here to target: 2400 yards on map A, about 343 seconds on foot.
local function base(over)
    local o = {
        here = { map = A, x = 0.9, y = 0.5 }, target = { map = A, x = 0.1, y = 0.5 },
        cornersOf = cornersOf, spells = {}, mount = {},
    }
    return put(o, over)
end

local function recall(over)
    local s = { kind = "recall", name = "Astral Recall", known = true, cooldown = false,
                dest = { map = A, x = 0.15, y = 0.5 } }
    return put(s, over)
end

local function advice(o)
    local f = T().Advice
    if type(f) ~= "function" then return nil, "missing" end
    return f(o)
end

tests["travel advice: yards across two maps of one continent, none across a sea"] = function(t)
    local yards = T().Yards or function() return nil end
    t.eq(yards({ map = A, x = 0.5, y = 0.5 }, { map = B, x = 0.5, y = 0.5 }, cornersOf), 3000)
    t.eq(yards({ map = A, x = 0.5, y = 0.5 }, { map = FAR, x = 0.5, y = 0.5 }, cornersOf), nil, "other continent")
    t.eq(yards({ map = A, x = 0.5, y = 0.5 }, { map = 1, x = 0.5, y = 0.5 }, cornersOf), nil, "corners unknown")
end

tests["travel advice: a ready recall that saves the walk says the minutes"] = function(t)
    local line, why = advice(base({ spells = { recall() } }))
    t.eq(line, "Your Astral Recall is ready: it saves about 5 minutes.")
    t.eq(why, "spell")
end

tests["travel advice: a teleport is named as it would save"] = function(t)
    local tp = recall({ kind = "teleport", name = "Teleport: Darnassus", dest = { map = A, x = 0.12, y = 0.5 } })
    local line = advice(base({ spells = { tp } }))
    t.eq(line, "Teleport: Darnassus would save about 5 minutes.")
end

tests["travel advice: a spell on cooldown, or its cooldown not known, gives no line"] = function(t)
    t.eq({ advice(base({ spells = { recall({ cooldown = true }) } })) }, { nil, "no saving" })
    t.eq({ advice(base({ spells = { recall({ cooldown = NONE }) } })) }, { nil, "no saving" })
end

tests["travel advice: a spell not known, or not said, gives no line"] = function(t)
    t.eq({ advice(base({ spells = { recall({ known = false }) } })) }, { nil, "no saving" })
    t.eq({ advice(base({ spells = { recall({ known = NONE }) } })) }, { nil, "no saving" })
    t.eq({ advice(base({ spells = { recall({ name = NONE }) } })) }, { nil, "no saving" }, "no name read")
end

tests["travel advice: a saving under two minutes gives no line"] = function(t)
    -- The recall lands 1800 yards from the stop: 343 - (10 + 257) is 76 seconds.
    t.eq({ advice(base({ spells = { recall({ dest = { map = A, x = 0.7, y = 0.5 } }) } })) }, { nil, "no saving" })
    -- A walk of 600 yards (86 seconds) is near: nothing is weighed.
    t.eq({ advice(base({ here = { map = A, x = 0.3, y = 0.5 }, spells = { recall() } })) }, { nil, "near" })
end

tests["travel advice: no stop, or a position not known, gives no line"] = function(t)
    t.eq({ advice(base({ target = NONE, spells = { recall() } })) }, { nil, "no target" })
    t.eq({ advice(base({ here = NONE, spells = { recall() } })) }, { nil, "far unknown" })
    t.eq({ advice(base({ here = { map = FAR, x = 0.5, y = 0.5 }, spells = { recall() } })) }, { nil, "far unknown" },
        "across a sea")
    t.eq({ advice(base({ spells = { recall({ dest = { map = 1, x = 0.5, y = 0.5 } }) } })) }, { nil, "no saving" },
        "where the spell lands is not known")
end

tests["travel advice: the spell that saves the most is named"] = function(t)
    local near = recall({ kind = "teleport", name = "Teleport: Near", dest = { map = A, x = 0.1, y = 0.5 } })
    local line = advice(base({ spells = { recall(), near } }))
    t.eq(line, "Teleport: Near would save about 6 minutes.")
end

tests["travel advice: a known mount not summoned halves the walk"] = function(t)
    local long = { here = { map = B, x = 0.9, y = 0.5 } }  -- 5400 yards: 771 seconds
    local o = base(long)
    o.mount = { known = true, mounted = false, indoors = false }
    t.eq({ advice(o) }, { "Ride your mount: it halves this walk.", "mount" })
    o.mount = { known = true, mounted = true }
    t.eq({ advice(o) }, { nil, "no saving" }, "already mounted")
    o.mount = { known = true, mounted = false, indoors = true }
    t.eq({ advice(o) }, { nil, "no saving" }, "indoors")
    o.mount = { known = false, mounted = false }
    t.eq({ advice(o) }, { nil, "no saving" }, "no mount")
    o.mount = { known = true, mounted = nil }
    t.eq({ advice(o) }, { nil, "no saving" }, "mounted not known")
    local short = base()  -- 343 seconds: half is 171, a ride is advised
    short.mount = { known = true, mounted = false }
    t.eq(advice(short), "Ride your mount: it halves this walk.")
end

tests["travel advice: spells read from the client, by id, named by the client"] = function(t)
    local spells = T().Spells
    t.ok(type(spells) == "function", "Spells is there")
    if type(spells) ~= "function" then return end
    local c = ns.make.fakeClient()
    c.setSpellId("Astral Recall", 556); c.setSpell(556, { known = true }); c.setSpellCooldown(556, false)
    local rows = spells(c, { map = A, x = 0.1, y = 0.5 })
    t.eq(#rows, 1)
    t.eq(rows[1] and { rows[1].kind, rows[1].name, rows[1].known, rows[1].cooldown },
        { "recall", "Astral Recall", true, false })
    t.eq(#spells(c, nil), 0, "no home: no recall")
end

tests["travel advice: a mount known from a class spell or a riding skill"] = function(t)
    local known = T().MountKnown
    t.ok(type(known) == "function", "MountKnown is there")
    if type(known) ~= "function" then return end
    local c = ns.make.fakeClient()
    t.eq(known(c), nil, "skills not read")
    c.setSkillRanks({ ["Horse Riding"] = { rank = 75, max = 75 } })
    t.eq(known(c), true)
    c.setSkillRanks({ ["Cooking"] = { rank = 75, max = 75 } })
    t.eq(known(c), false)
    c.setSpell(13819, { known = true })
    t.eq(known(c), true, "Summon Warhorse")
end

return tests
