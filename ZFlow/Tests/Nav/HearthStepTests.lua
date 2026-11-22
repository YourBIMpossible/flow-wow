-- Hearthstone step (G46): N.HearthStep over hand-written tables, and
-- N.HearthStepFrom over the fake client. The bind read and the cooldown
-- read are not in the fake yet, so they are set on it here. Made-up
-- places, test only. Not tested in game.
local _, ns = ...

local N = ns.Nav

-- Map 1411 is 1000 by 500 yards. The step the guide is on is at TARGET.
local TARGET = { map = 1411, x = 0.75, y = 0.5 }
local SIZE = { [1411] = { w = 1000, h = 500 } }

local function here(map, x, y, sizes)
    sizes = sizes or SIZE
    return { position = { map = map, x = x, y = y }, mapSize = function(m) return sizes[m] end }
end

-- The inn is 125 yards from TARGET.
local function inn(more)
    local b = { name = "Goldshire", map = 1411, x = 0.625, y = 0.5 }
    for key, v in pairs(more or {}) do b[key] = v end
    return b
end

local T = {}

T["hearth step: the saved path and the first guesses are the ones agreed"] = function(t)
    t.eq(N.HEARTH_BIND, "learned.places.bind")
    t.eq(N.HEARTH_SAVES, 300)
    t.eq(N.HEARTH_PLAIN, "Use your hearthstone")
end

T["hearth step: it saves travel on the map of the step: hearth to the place"] = function(t)
    -- The player is 500 yards from the step, the inn 125: 375 saved.
    local step, why = N.HearthStep(inn(), TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(why, nil)
    t.eq(step, { label = "Hearth to Goldshire", text = true,
                 lands = { map = 1411, x = 0.625, y = 0.5 }, saves = 375 })
end

T["hearth step: it has no place for an arrow to point at"] = function(t)
    local step = N.HearthStep(inn(), TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(step.place, nil)
    t.eq(step.radius, nil)
end

T["hearth step: too little saved is no step"] = function(t)
    -- 250 yards from the step, the inn 125: 125 saved.
    local step, why = N.HearthStep(inn(), TARGET, here(1411, 0.5, 0.5), 0)
    t.eq(step, nil)
    t.eq(why, "no saving")
    step, why = N.HearthStep(inn(), TARGET, here(1411, 0.6875, 0.5), 0)
    t.eq(step, nil, "the player is nearer than the inn")
    t.eq(why, "no saving")
end

T["hearth step: the player on another map, the inn on the map of the step"] = function(t)
    local step, why = N.HearthStep(inn(), TARGET, here(1412, 0.5, 0.5), 0)
    t.eq(why, nil)
    t.eq(step, { label = "Hearth to Goldshire", text = true, lands = { map = 1411, x = 0.625, y = 0.5 } })
    t.eq(step.saves, nil, "how much is not known, so it is not said")
end

T["hearth step: the inn on another map than the step is no step"] = function(t)
    local step, why = N.HearthStep(inn({ map = 1412 }), TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(step, nil)
    t.eq(why, "other map")
end

T["hearth step: a cooldown that is not known is never taken as ready"] = function(t)
    local step, why = N.HearthStep(inn(), TARGET, here(1411, 0.25, 0.5), nil)
    t.eq(step, nil)
    t.eq(why, "cooldown unknown")
    step, why = N.HearthStep(inn(), TARGET, here(1411, 0.25, 0.5), 0 / 0)
    t.eq(step, nil)
    t.eq(why, "cooldown unknown")
    step, why = N.HearthStep(inn(), TARGET, here(1411, 0.25, 0.5), "0")
    t.eq(step, nil)
    t.eq(why, "cooldown unknown")
end

T["hearth step: on cooldown is no step"] = function(t)
    local step, why = N.HearthStep(inn(), TARGET, here(1411, 0.25, 0.5), 120)
    t.eq(step, nil)
    t.eq(why, "on cooldown")
    step, why = N.HearthStep(inn(), TARGET, here(1411, 0.25, 0.5), 0.5)
    t.eq(step, nil)
    t.eq(why, "on cooldown")
end

T["hearth step: no step of the guide to go to is no step"] = function(t)
    local step, why = N.HearthStep(inn(), nil, here(1411, 0.25, 0.5), 0)
    t.eq(step, nil)
    t.eq(why, "no target")
    step, why = N.HearthStep(inn(), { map = 1411 }, here(1411, 0.25, 0.5), 0)
    t.eq(step, nil)
    t.eq(why, "no target")
    step, why = N.HearthStep(inn(), { x = 0.5, y = 0.5 }, here(1411, 0.25, 0.5), 0)
    t.eq(step, nil)
    t.eq(why, "no target")
end

T["hearth step: where the bind place is, is not known: text only, and it says so"] = function(t)
    local step, why = N.HearthStep({ name = "Goldshire" }, TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(step, { label = "Hearth to Goldshire", text = true })
    t.eq(why, "bind place unknown")
    step, why = N.HearthStep({ name = "Goldshire", map = 1411, x = 2, y = 0.5 }, TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(step, { label = "Hearth to Goldshire", text = true }, "a place off the map is no place")
    t.eq(why, "bind place unknown")
end

T["hearth step: no name and no place: the plain text, nothing guessed"] = function(t)
    local step, why = N.HearthStep(nil, TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(step, { label = "Use your hearthstone", text = true })
    t.eq(why, "bind place unknown")
    step, why = N.HearthStep({ name = "" }, TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(step, { label = "Use your hearthstone", text = true })
    t.eq(why, "bind place unknown")
end

T["hearth step: text only still waits for the cooldown and for a step to go to"] = function(t)
    local step, why = N.HearthStep({ name = "Goldshire" }, TARGET, here(1411, 0.25, 0.5), 30)
    t.eq(step, nil)
    t.eq(why, "on cooldown")
    step, why = N.HearthStep({ name = "Goldshire" }, nil, here(1411, 0.25, 0.5), 0)
    t.eq(step, nil)
    t.eq(why, "no target")
end

T["hearth step: a place known with no name: the plain text"] = function(t)
    local step, why = N.HearthStep({ map = 1411, x = 0.625, y = 0.5 }, TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(why, nil)
    t.eq(step.label, "Use your hearthstone")
    t.eq(step.saves, 375)
end

T["hearth step: a name too long for a label is not cut: the plain text"] = function(t)
    local long = string.rep("a", N.Waypoint.LABEL_MAX)
    local step = N.HearthStep(inn({ name = long }), TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(step.label, "Use your hearthstone")
    local fits = string.rep("a", N.Waypoint.LABEL_MAX - #"Hearth to ")
    step = N.HearthStep(inn({ name = fits }), TARGET, here(1411, 0.25, 0.5), 0)
    t.eq(step.label, "Hearth to " .. fits)
end

T["hearth step: where the player is, is not known: no step"] = function(t)
    local step, why = N.HearthStep(inn(), TARGET, {}, 0)
    t.eq(step, nil)
    t.eq(why, "position unknown")
    step, why = N.HearthStep(inn(), TARGET, nil, 0)
    t.eq(step, nil)
    t.eq(why, "position unknown")
    step, why = N.HearthStep(inn(), TARGET, { position = { map = 1411 } }, 0)
    t.eq(step, nil, "on the map, but where on it is not known")
    t.eq(why, "position unknown")
end

T["hearth step: on the same map with no size of the map: no step"] = function(t)
    local step, why = N.HearthStep(inn(), TARGET, here(1411, 0.25, 0.5, {}), 0)
    t.eq(step, nil)
    t.eq(why, "size unknown")
    step, why = N.HearthStep(inn(), TARGET, here(1411, 0.25, 0.5, { [1411] = { w = 0, h = 500 } }), 0)
    t.eq(step, nil)
    t.eq(why, "size unknown")
    step, why = N.HearthStep(inn(), TARGET,
        { position = { map = 1411, x = 0.25, y = 0.5 }, mapSize = function() error("broken") end }, 0)
    t.eq(step, nil)
    t.eq(why, "size unknown")
end

T["hearth step: nothing handed in is changed"] = function(t)
    local bind, target, h = inn(), { map = 1411, x = 0.75, y = 0.5 }, here(1411, 0.25, 0.5)
    local step = N.HearthStep(bind, target, h, 0)
    step.lands.x = 9
    t.eq(bind, inn())
    t.eq(target, { map = 1411, x = 0.75, y = 0.5 })
    t.eq(h.position, { map = 1411, x = 0.25, y = 0.5 })
end

-- N.HearthStepFrom over the fake client and a kernel store.
-- opts: char (saved table), bind (the name the client gives; false for no
-- such read), cooldown (false for no such read).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setZone(1, 1411)
    c.setPosition(1411, 0.25, 0.5)
    c.setMapSize(1411, 1000, 500)
    local held = { bind = opts.bind, cooldown = opts.cooldown }
    if opts.bind ~= false then c.bindLocation = function() return held.bind end end
    if opts.cooldown ~= false then c.hearthCooldown = function() return held.cooldown end end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, k, held
end

local function saved(row) return { learned = { places = { bind = row } } } end

T["hearth step: from the client and the store"] = function(t)
    local c, k = start({ char = saved({ name = "Goldshire", map = 1411, x = 0.625, y = 0.5, seen = 4000 }),
                         bind = "Goldshire", cooldown = 0 })
    local step, why = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(why, nil)
    t.eq(step, { label = "Hearth to Goldshire", text = true,
                 lands = { map = 1411, x = 0.625, y = 0.5 }, saves = 375 })
    t.eq(k.problems:count(), 0)
end

T["hearth step: a saved place of another bind name is not used"] = function(t)
    local c, k = start({ char = saved({ name = "Goldshire", map = 1411, x = 0.625, y = 0.5 }),
                         bind = "Lakeshire", cooldown = 0 })
    local step, why = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(step, { label = "Hearth to Lakeshire", text = true })
    t.eq(why, "bind place unknown")
end

T["hearth step: the client gives no bind name: the saved place is not trusted"] = function(t)
    local c, k = start({ char = saved({ name = "Goldshire", map = 1411, x = 0.625, y = 0.5 }), cooldown = 0 })
    local step, why = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(step, { label = "Use your hearthstone", text = true })
    t.eq(why, "bind place unknown")
    c, k = start({ char = saved({ name = "Goldshire", map = 1411, x = 0.625, y = 0.5 }), bind = false, cooldown = 0 })
    step, why = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(step, { label = "Use your hearthstone", text = true })
    t.eq(why, "bind place unknown")
end

T["hearth step: nothing saved yet: text only, and nothing is made"] = function(t)
    local c, k = start({ bind = "Goldshire", cooldown = 0 })
    local step, why = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(step, { label = "Hearth to Goldshire", text = true })
    t.eq(why, "bind place unknown")
    t.eq(k.store:get("char", N.HEARTH_BIND), nil, "a read does not make the table")
end

T["hearth step: the cooldown from the client"] = function(t)
    local c, k, held = start({ char = saved({ name = "Goldshire", map = 1411, x = 0.625, y = 0.5 }),
                               bind = "Goldshire", cooldown = 900 })
    local step, why = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(step, nil)
    t.eq(why, "on cooldown")
    held.cooldown = nil
    step, why = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(step, nil)
    t.eq(why, "cooldown unknown")
    held.cooldown = 0
    t.ok(N.HearthStepFrom(TARGET, c, k.store) ~= nil)
    c, k = start({ bind = "Goldshire", cooldown = false })
    step, why = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(step, nil, "a client with no cooldown read")
    t.eq(why, "cooldown unknown")
end

T["hearth step: follows the player"] = function(t)
    local c, k = start({ char = saved({ name = "Goldshire", map = 1411, x = 0.625, y = 0.5 }),
                         bind = "Goldshire", cooldown = 0 })
    c.setPosition(1411, 0.5, 0.5)
    local step, why = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(step, nil)
    t.eq(why, "no saving")
    c.setPosition(1412, 0.5, 0.5)
    step = N.HearthStepFrom(TARGET, c, k.store)
    t.eq(step.label, "Hearth to Goldshire")
    t.eq(step.saves, nil)
end

T["hearth step: a client or a store that cannot answer is not an error"] = function(t)
    local c, k = start({ char = saved({ name = "Goldshire", map = 1411, x = 0.625, y = 0.5 }),
                         bind = "Goldshire", cooldown = 0 })
    local step, why = N.HearthStepFrom(TARGET, {}, k.store)
    t.eq(step, nil)
    t.eq(why, "cooldown unknown")
    step, why = N.HearthStepFrom(TARGET, { hearthCooldown = function() error("broken") end }, k.store)
    t.eq(step, nil)
    t.eq(why, "cooldown unknown")
    step, why = N.HearthStepFrom(TARGET, c, {})
    t.eq(step, { label = "Hearth to Goldshire", text = true })
    t.eq(why, "bind place unknown")
    step, why = N.HearthStepFrom(TARGET, c, { get = function() error("broken") end })
    t.eq(step, { label = "Hearth to Goldshire", text = true })
    t.eq(why, "bind place unknown")
    step, why = N.HearthStepFrom(TARGET, c, { get = function() return "junk" end })
    t.eq(step, { label = "Hearth to Goldshire", text = true })
    t.eq(why, "bind place unknown")
end

return T
