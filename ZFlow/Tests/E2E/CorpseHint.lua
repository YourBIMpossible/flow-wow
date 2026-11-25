local _, ns = ...

-- End to end (lead section 485, parity row A1-14): while dead, the
-- corpse-run hint says what to do next, and a pin on the minimap marks the
-- corpse. On the whole add-on with a fake client; made-up places. Not
-- tested in game.
-- Fails before: there is no corpseHint module, so no hint and no pin.

local tests = {}

local MAP = 1411

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setLevel(10)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000)
    c.setMinimap({ size = 140, radius = 100, rotates = false })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function hint(addon)
    local mod = addon.use("corpseHint")
    return mod and mod.Hint() or nil
end

local function pinOf(c)
    local want = tostring(ns.id.addon) .. ns.Nav.CorpseHint.PIN_NAME
    for _, h in ipairs(c.minimapPins) do
        if type(h.spec) == "table" and h.spec.name == want then return h end
    end
    return nil
end

tests["corpse hint e2e: dead, not released, says release first"] = function(t)
    local c, addon = boot()
    c.setDead(true); c.setGhost(false); c.setCorpse(MAP, 0.5, 0.5); c.advance(1, 4)
    t.eq(hint(addon), "Release your spirit, then follow the red arrow")
    local p = pinOf(c)
    t.ok(p == nil or not p.shown, "no corpse pin before release")
end

tests["corpse hint e2e: a ghost gets a corpse pin, and at the corpse the words"] = function(t)
    local c, addon = boot()
    c.setDead(true); c.setGhost(true); c.setCorpse(MAP, 0.55, 0.5); c.advance(1, 4)
    t.eq(hint(addon), nil, "on the way: no hint line")
    local p = pinOf(c)
    t.ok(p ~= nil and p.shown, "the corpse is pinned")
    if p then t.ok(p.x > 0, "east of the middle") end
    c.setPosition(MAP, 0.552, 0.5); c.advance(1, 4)
    t.eq(hint(addon), "Here: resurrect")
end

tests["corpse hint e2e: a corpse on another map says the graveyard path"] = function(t)
    local c, addon = boot()
    c.setDead(true); c.setGhost(true); c.setCorpse(false); c.advance(1, 4)
    t.eq(hint(addon), "On another map: follow the graveyard path")
    local p = pinOf(c)
    t.ok(p == nil or not p.shown, "no pin without a place")
end

tests["corpse hint e2e: alive, or not known, there is no hint"] = function(t)
    local _, addon = boot()
    t.eq(hint(addon), nil, "alive")
    local CH = ns.Nav.CorpseHint
    t.eq(CH.Words(nil, false, nil), nil, "ghost not known")
    t.eq(CH.Words(true, { map = 1, x = 0.5, y = 0.5 }, nil), nil, "distance not known")
end

return tests
