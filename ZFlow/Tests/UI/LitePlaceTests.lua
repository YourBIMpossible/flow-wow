-- Tests for F-08 in ZFlow/UI/Lite.lua: ease off by place. The row
-- perf.litePlace (on by default, as in legacy Flow Perf.lua:159-183); the
-- reason from the game's instance read; a reload inside an instance leaves
-- the extras off as manual lite does; the player's own lite stays on.
local _, ns = ...

local L = ns.Lite

local function start(account, instance)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, {})
    c.setInstance(instance)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Module({ name = "plateThreat", start = function() end })
    k:Module({ name = "core", start = function() end })
    L.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

local tests = {}

tests["lite place: the reason by the kind of instance, nothing outside or with the row off"] = function(t)
    t.eq(L.PlaceWhy({ inside = true, kind = "party" }, true), L.WHY.party)
    t.eq(L.PlaceWhy({ inside = true, kind = "raid" }, true), L.WHY.raid)
    t.eq(L.PlaceWhy({ inside = true, kind = "pvp" }, true), L.WHY.pvp)
    t.eq(L.PlaceWhy({ inside = true, kind = "arena" }, true), L.WHY.pvp)
    t.eq(L.PlaceWhy({ inside = false, kind = "none" }, true), nil)
    t.eq(L.PlaceWhy({ inside = true, kind = "party" }, false), nil, "the row off")
    t.eq(L.PlaceWhy(nil, true), nil, "the game gives no answer: nothing is assumed")
    t.eq(L.PlaceWhy({ inside = true, kind = "scenario" }, true), nil, "a kind Flow does not name")
end

tests["lite place: the row is perf.litePlace, account, on by default"] = function(t)
    local k = start()
    local row = k.settings:row(L.PLACE_SETTING)
    t.ok(row ~= nil, "declared")
    t.eq(row and row.scope, "account")
    t.eq(row and row.default, true)
    t.eq(row and row.label, "Ease off in raids, dungeons and battlegrounds")
end

tests["lite place: Place says why now, and follows the player in and out"] = function(t)
    local k, c = start()
    local lite = k.use(L.NAME)
    t.eq(lite.Place(), nil, "outside")
    c.setInstance({ inside = true, kind = "party" })
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(lite.Place(), L.WHY.party, "inside a dungeon")
    c.setInstance({ inside = false, kind = "none" })
    c.fire("ZONE_CHANGED_NEW_AREA")
    t.eq(lite.Place(), nil, "out again")
end

tests["lite place: a reload inside an instance leaves the extras off"] = function(t)
    local k = start({}, { inside = true, kind = "raid" })
    t.eq(k:ModuleState("plateThreat"), "off")
    t.eq(k:ModuleState("core"), "started")
    local k2 = start({}, { inside = false, kind = "none" })
    t.eq(k2:ModuleState("plateThreat"), "started", "outside: every module runs")
end

tests["lite place: with the row off, inside changes nothing; the player's own lite stays on"] = function(t)
    local k = start({ settings = { perf = { litePlace = false } } }, { inside = true, kind = "raid" })
    t.eq(k:ModuleState("plateThreat"), "started", "the row off")
    local k2 = start({ settings = { perf = { lite = true } } }, { inside = false, kind = "none" })
    t.eq(k2:ModuleState("plateThreat"), "off", "manual lite outside: still off")
end

return tests
