-- Nearest service (G36): N.NearestOf over hand-written places, and
-- N.Nearest over the fake client. Made-up rows, test only. Not seen in game.
local _, ns = ...

local N = ns.Nav

-- The player in the middle of map 1411, 1000 by 500 yards.
local HERE = { map = 1411, x = 0.5, y = 0.5, cont = 1, size = { w = 1000, h = 500 } }

local function place(kinds, x, y, more)
    local e = { map = 1411, x = x, y = y, kinds = {} }
    for _, kind in ipairs(kinds) do e.kinds[kind] = true end
    for key, v in pairs(more or {}) do e[key] = v end
    return e
end

local T = {}

T["nearest service: the kinds and the saved path are the ones agreed"] = function(t)
    t.eq(N.SERVICE_KINDS, { "vendor", "repair", "banker", "innkeeper", "flight", "mailbox", "auction" })
    t.eq(N.SERVICES, "learned.places.services")
end

T["nearest service: nothing known, nothing given: nil"] = function(t)
    t.eq(N.NearestOf("vendor", nil, HERE), nil)
    t.eq(N.NearestOf("vendor", {}, HERE), nil)
    t.eq(N.NearestOf("vendor", { a = place({ "vendor" }, 0.5, 0.4) }, nil), nil)
end

T["nearest service: a kind that is not one of them is nil"] = function(t)
    local places = { a = place({ "vendor" }, 0.5, 0.4) }
    t.eq(N.NearestOf("trainer", places, HERE), nil)
    t.eq(N.NearestOf(nil, places, HERE), nil)
    t.eq(N.NearestOf("kinds", places, HERE), nil)
end

T["nearest service: the one known place of that kind, with its distance"] = function(t)
    local places = { ["Creature-0-1-2-3-54-0"] = place({ "vendor" }, 0.5, 0.3,
        { name = "Kaita Deepforge", guid = "Creature-0-1-2-3-54-0", seen = 7000, n = 3 }) }
    t.eq(N.NearestOf("vendor", places, HERE), {
        kind = "vendor", key = "Creature-0-1-2-3-54-0", name = "Kaita Deepforge",
        guid = "Creature-0-1-2-3-54-0", map = 1411, x = 0.5, y = 0.3, cont = 1, yards = 100, seen = 7000,
    })
end

T["nearest service: the nearest of several, in yards when the size is known"] = function(t)
    -- 0.15 of 1000 yd east is 150 yd; 0.2 of 500 yd north is 100 yd.
    local places = { east = place({ "banker" }, 0.65, 0.5), north = place({ "banker" }, 0.5, 0.3) }
    local got = N.NearestOf("banker", places, HERE)
    t.eq(got.key, "north")
    t.eq(got.yards, 100)
end

T["nearest service: with no size, by shares of the map, and no yards are said"] = function(t)
    local places = { east = place({ "banker" }, 0.65, 0.5), north = place({ "banker" }, 0.5, 0.3) }
    local got = N.NearestOf("banker", places, { map = 1411, x = 0.5, y = 0.5 })
    t.eq(got.key, "east")
    t.eq(got.yards, nil)
    t.eq(got.cont, nil)
    local bad = { map = 1411, x = 0.5, y = 0.5, size = { w = 0, h = 500 } }
    t.eq(N.NearestOf("banker", places, bad).yards, nil, "a size of 0 is no size")
end

T["nearest service: only the kind asked for"] = function(t)
    local places = {
        near = place({ "vendor" }, 0.5, 0.49),
        far = place({ "vendor", "repair" }, 0.5, 0.1),
    }
    t.eq(N.NearestOf("vendor", places, HERE).key, "near")
    t.eq(N.NearestOf("repair", places, HERE).key, "far")
    t.eq(N.NearestOf("flight", places, HERE), nil)
end

T["nearest service: a place on another map is never returned"] = function(t)
    local places = { other = place({ "flight" }, 0.5, 0.5, { map = 1412 }) }
    t.eq(N.NearestOf("flight", places, HERE), nil)
    places.here = place({ "flight" }, 0.1, 0.1)
    t.eq(N.NearestOf("flight", places, HERE).key, "here")
end

T["nearest service: where the player is not known, nil"] = function(t)
    local places = { a = place({ "mailbox" }, 0.5, 0.4) }
    t.eq(N.NearestOf("mailbox", places, { x = 0.5, y = 0.5 }), nil, "no map")
    t.eq(N.NearestOf("mailbox", places, { map = 1411 }), nil, "no position")
    t.eq(N.NearestOf("mailbox", places, { map = 1411, x = 0 / 0, y = 0.5 }), nil)
end

T["nearest service: a mailbox has no name and no guid"] = function(t)
    local got = N.NearestOf("mailbox", { ["mailbox:1411:50:25"] = place({ "mailbox" }, 0.5, 0.25) }, HERE)
    t.eq(got.name, nil)
    t.eq(got.guid, nil)
    t.eq(got.seen, nil)
    t.eq(got.yards, 125)
end

T["nearest service: a tie goes to the lower key"] = function(t)
    local places = { b = place({ "vendor" }, 0.5, 0.4), a = place({ "vendor" }, 0.5, 0.6),
                     c = place({ "vendor" }, 0.5, 0.4) }
    t.eq(N.NearestOf("vendor", places, HERE).key, "a")
end

T["nearest service: entries that are not usable are passed over"] = function(t)
    local places = {
        junk = "junk",
        noKinds = { map = 1411, x = 0.5, y = 0.5 },
        notTrue = { map = 1411, x = 0.5, y = 0.5, kinds = { vendor = "yes" } },
        noPlace = { map = 1411, kinds = { vendor = true } },
        badX = { map = 1411, x = "a", y = 0.5, kinds = { vendor = true } },
        good = place({ "vendor" }, 0.9, 0.9, { name = "" }),
    }
    local got = N.NearestOf("vendor", places, HERE)
    t.eq(got.key, "good")
    t.eq(got.name, nil, "an empty name is no name")
end

T["nearest service: nothing handed in is changed"] = function(t)
    local places = { a = place({ "vendor" }, 0.5, 0.3, { name = "A" }) }
    local got = N.NearestOf("vendor", places, HERE)
    got.x, got.name = 9, "changed"
    t.eq(places, { a = place({ "vendor" }, 0.5, 0.3, { name = "A" }) })
    t.eq(HERE, { map = 1411, x = 0.5, y = 0.5, cont = 1, size = { w = 1000, h = 500 } })
end

-- N.Nearest over the fake client and a kernel store.
local function start(char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, char or {})
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, k
end

local function saved(rows) return { learned = { places = { services = rows } } } end

T["nearest service: from the client and the store"] = function(t)
    local c, k = start(saved({
        ["Creature-0-1-2-3-54-0"] = place({ "vendor", "repair" }, 0.5, 0.3, { name = "Kaita Deepforge" }),
        ["Banker Olivia"] = place({ "banker" }, 0.75, 0.5, { name = "Banker Olivia" }),
    }))
    local got = N.Nearest("repair", c, k.store)
    t.eq(got.name, "Kaita Deepforge")
    t.eq(got.yards, 100)
    t.eq(got.cont, 1)
    t.eq(N.Nearest("banker", c, k.store).yards, 250)
    t.eq(N.Nearest("flight", c, k.store), nil)
    t.eq(k.problems:count(), 0)
end

T["nearest service: nothing saved yet is nil, and nothing is made"] = function(t)
    local c, k = start({})
    t.eq(N.Nearest("vendor", c, k.store), nil)
    t.eq(k.store:get("char", N.SERVICES), nil, "a read does not make the table")
end

T["nearest service: follows the player to another map"] = function(t)
    local c, k = start(saved({
        a = place({ "vendor" }, 0.5, 0.3),
        b = place({ "vendor" }, 0.2, 0.2, { map = 1412 }),
    }))
    t.eq(N.Nearest("vendor", c, k.store).key, "a")
    c.setPosition(1412, 0.2, 0.3)
    local got = N.Nearest("vendor", c, k.store)
    t.eq(got.key, "b")
    t.eq(got.yards, nil, "the size of map 1412 was never given")
    c.setPosition(1413, 0.5, 0.5)
    t.eq(N.Nearest("vendor", c, k.store), nil)
end

T["nearest service: a client or a store that cannot answer is nil, not an error"] = function(t)
    local c, k = start(saved({ a = place({ "vendor" }, 0.5, 0.3) }))
    t.eq(N.Nearest("vendor", {}, k.store), nil)
    t.eq(N.Nearest("vendor", { position = function() error("broken") end }, k.store), nil)
    t.eq(N.Nearest("vendor", c, {}), nil)
    t.eq(N.Nearest("vendor", c, { get = function() error("broken") end }), nil)
    t.eq(N.Nearest("vendor", c, { get = function() return "junk" end }), nil)
end

return T
