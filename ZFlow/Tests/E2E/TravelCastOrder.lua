local _, ns = ...

-- End to end (FLOW-PARITY B-31): a druid who knows Teleport: Moonglade
-- counts a trip stop in Moonglade as one cast (N.TRAVEL_SPELL_YARDS), not
-- as the far end of the trip. "trip go" puts it before a long walk on this
-- map, and the arrow says to cast the spell; the player casts. Nothing
-- casts for them. Made-up places. Not tested in game.

local tests = {}
local N = ns.Nav

local HERE, MOONGLADE = 1411, 1450
local SPELL, SPELL_ID = "Teleport: Moonglade", 18960
local CAST = "Cast " .. SPELL

local NEAR = { kind = "here", label = "Near post", place = { map = HERE, x = 0.55, y = 0.5 } }
local FAR = { kind = "here", label = "Far post", place = { map = HERE, x = 0.9, y = 0.5 } }
local LAKE = { kind = "here", label = "Moonglade lake", place = { map = MOONGLADE, x = 0.5, y = 0.5 } }

local function boot(known)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, HERE); c.setPosition(HERE, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(HERE, 1000, 1000); c.setMapCont(HERE, 1)
    c.setMapSize(MOONGLADE, 1000, 1000); c.setMapCont(MOONGLADE, 1)
    c.setClass("DRUID"); c.setFaction("Horde"); c.setLevel(20)
    c.setSpellId(SPELL, SPELL_ID)
    c.setSpell(SPELL_ID, { known = known })
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    addon.store:set("char", N.Trip.PATH, { stops = { FAR, LAKE } })
    return c, addon
end

local function first(c)
    local a = c.arrows[1]
    if a and a.shown and a.lines then return a.lines[1] end
    return nil
end

tests["travel cast order: a known spell puts the Moonglade stop first, and the arrow says to cast it"] = function(t)
    local c = boot(true)
    c.slashes[ns.id.slash]("trip go"); c.advance(2, 20)
    t.eq(first(c), CAST, "one cast beats a 400 yd walk: the arrow says to cast")
end

tests["travel cast order: the spell not known, the walk on this map comes first"] = function(t)
    local c = boot(false)
    c.slashes[ns.id.slash]("trip go"); c.advance(2, 20)
    t.eq(first(c), "Far post")
end

tests["travel cast order: pure order, a stop nearer than the cast stays before it"] = function(t)
    local here = { map = HERE, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }
    local function labels(o)
        local out = {}
        for i, s in ipairs(o or {}) do out[i] = s.label end
        return out
    end
    t.eq(labels(N.Trip.Order({ FAR, LAKE, NEAR }, here)), { "Near post", "Far post", "Moonglade lake" },
        "no cast known: the other map comes last")
    here.casts = { [MOONGLADE] = true }
    t.eq(labels(N.Trip.Order({ FAR, LAKE, NEAR }, here)), { "Near post", "Moonglade lake", "Far post" },
        "50 yd first, then the cast (120 yd), then the 350 yd leg")
end

return tests
