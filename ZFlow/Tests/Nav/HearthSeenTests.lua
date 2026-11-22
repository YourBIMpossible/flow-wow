-- Tests for ZFlow/Nav/HearthSeen.lua (G46): the recorder of where the
-- player made a home, over the fake client. The bind read is not in the
-- fake yet, so it is set on it here. Made-up places, test only. Not tested
-- in game.
local _, ns = ...

local S = ns.HearthSeen
local N = ns.Nav
local tests = {}

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

-- opts: char (saved table), date (false: the client will not say), bind
-- (the name the client gives; false for no such read).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    if opts.date ~= false then c.setClock(opts.date or 5000) end
    c.setZone(1, 1411)
    c.setPosition(1411, 0.625, 0.5)
    local held = { bind = opts.bind }
    if opts.bind ~= false then c.bindLocation = function() return held.bind end end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local w = S.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, w, held
end

local function bind(c)
    local root = c.saved(ns.id.charDB)
    root = type(root) == "table" and root.learned or nil
    root = type(root) == "table" and root.places or nil
    return type(root) == "table" and root.bind or nil
end

local function char(c)
    local out = copy(c.saved(ns.id.charDB))
    if type(out) == "table" then out.diag = nil end
    return out
end

tests["hearth seen: the names are the ones agreed"] = function(t)
    t.eq(S.NAME, "hearthSeen")
    t.eq(S.EVENT, "HEARTHSTONE_BOUND")
    t.eq(S.PLACE, "learned.places.bind")
    t.eq(S.PLACE, N.HEARTH_BIND, "the recorder writes where the reader reads")
end

tests["hearth seen: nothing is saved before the player makes a home"] = function(t)
    local k, c, w = start({ bind = "Goldshire" })
    t.eq(bind(c), nil)
    t.eq(w.last(), nil)
    t.eq(k.problems:count(), 0)
end

tests["hearth seen: a new home is saved with where the player stood"] = function(t)
    local k, c, w = start({ bind = "Goldshire" })
    c.fire("HEARTHSTONE_BOUND")
    t.eq(bind(c), { name = "Goldshire", map = 1411, x = 0.625, y = 0.5, seen = 5000 })
    t.eq(w.last(), { kind = "bind", ok = true, name = "Goldshire" })
    t.eq(k.problems:count(), 0)
end

tests["hearth seen: the next home takes the place of the last"] = function(t)
    local _, c, _, held = start({ bind = "Goldshire",
        char = { learned = { places = { bind = { name = "Old", map = 1, x = 0.1, y = 0.1, seen = 10, more = true } } } } })
    held.bind = "Lakeshire"
    c.setPosition(1433, 0.25, 0.75)
    c.fire("HEARTHSTONE_BOUND")
    t.eq(bind(c), { name = "Lakeshire", map = 1433, x = 0.25, y = 0.75, seen = 5000 })
end

tests["hearth seen: with no date the place is saved without one"] = function(t)
    local _, c = start({ bind = "Goldshire", date = false })
    c.fire("HEARTHSTONE_BOUND")
    t.eq(bind(c), { name = "Goldshire", map = 1411, x = 0.625, y = 0.5 })
end

tests["hearth seen: the name of the home is not known: nothing is written"] = function(t)
    local old = { name = "Old", map = 1, x = 0.1, y = 0.1 }
    local _, c, w = start({ char = { learned = { places = { bind = copy(old) } } } })
    c.fire("HEARTHSTONE_BOUND")
    t.eq(bind(c), old)
    t.eq(w.last(), { kind = "bind", ok = false, reason = "the bind place is not known" })
    _, c, w = start({ bind = false })
    c.fire("HEARTHSTONE_BOUND")
    t.eq(bind(c), nil)
    t.eq(w.last().ok, false)
    _, c, w = start({ bind = "" })
    c.fire("HEARTHSTONE_BOUND")
    t.eq(bind(c), nil)
    t.eq(w.last().reason, "the bind place is not known")
end

tests["hearth seen: the position is not known: nothing is written"] = function(t)
    local _, c, w = start({ bind = "Goldshire" })
    c.setPosition(nil)
    c.fire("HEARTHSTONE_BOUND")
    t.eq(bind(c), nil)
    t.eq(w.last(), { kind = "bind", ok = false, reason = "the position is not known", name = "Goldshire" })
end

tests["hearth seen: a store that refuses is left as it was"] = function(t)
    local k, c, w = start({ bind = "Goldshire" })
    local before = char(c)
    k.store.blocked.char = "refused in a test"
    c.fire("HEARTHSTONE_BOUND")
    t.eq(char(c), before)
    t.eq(w.last(), { kind = "bind", ok = false, reason = "the bind place cannot be saved", name = "Goldshire" })
    k.store.blocked.char = nil
    c.fire("HEARTHSTONE_BOUND")
    t.eq(bind(c).name, "Goldshire")
    t.eq(w.last().ok, true)
end

tests["hearth seen: what is saved is what the step reads"] = function(t)
    local k, c = start({ bind = "Goldshire" })
    c.fire("HEARTHSTONE_BOUND")
    c.hearthCooldown = function() return 0 end
    c.setMapSize(1411, 1000, 500)
    c.setPosition(1411, 0.25, 0.5)
    local step, why = N.HearthStepFrom({ map = 1411, x = 0.75, y = 0.5 }, c, k.store)
    t.eq(why, nil)
    t.eq(step.label, "Hearth to Goldshire")
    t.eq(step.saves, 375)
end

tests["hearth seen: one sighting read by hand"] = function(t)
    local k, c = start({ bind = "Goldshire" })
    t.eq(S.Seen(c, k.store), { kind = "bind", ok = true, name = "Goldshire" })
    t.eq(S.Seen(c, {}), { kind = "bind", ok = false, reason = "the bind place cannot be saved", name = "Goldshire" })
    t.eq(S.Seen({}, k.store), { kind = "bind", ok = false, reason = "the bind place is not known" })
end

return tests
