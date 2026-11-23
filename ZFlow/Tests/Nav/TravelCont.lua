local _, ns = ...

-- Tests for lead section 184 G1: a step place with no continent (a quest
-- place on another map, Nav/QuestSource.lua) gets its continent from its
-- own map before the travel providers are asked, with the same number
-- client.zone gives (C_Map.GetWorldPosFromMapPos). A continent the client
-- does not give stays nil; one already on the place is kept. Made-up maps;
-- fake client. Not tested in game. Look only.

local N = ns.Nav
local T = N.Travel
local tests = {}

-- A travel module with a stand-in flight provider that keeps every place it
-- is handed, and the crossings module with one Horde zeppelin saved.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { crossings = { {
        key = "zep", how = "zeppelin", faction = "Horde",
        a = { cont = 1, map = 1411, x = 0.5, y = 0.1, name = "Durotar tower" },
        b = { cont = 0, map = 1420, x = 0.6, y = 0.6, name = "Tirisfal tower" },
    } } } } })
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapSize(1420, 1000, 1000)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    if opts.cont ~= nil then c.setMapCont(1420, opts.cont) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local handed = {}
    k:Module({
        name = "flights",
        needs = {},
        provides = { Way = function(place) handed[#handed + 1] = place return nil end },
        start = function() end,
    })
    N.Crossings.Declare(k)
    local travel = T.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, travel, handed
end

tests["travel cont: a place with no continent is filled from its map"] = function(t)
    local k, _, travel, handed = start({ cont = 0 })
    local s = { label = "Kill bats", place = { map = 1420, x = 0.6, y = 0.7 } }
    local out, how = travel.via(s)
    t.eq(how, "crossing")
    t.eq(out.label, "Zeppelin to Tirisfal tower")
    t.eq(#handed, 1)
    t.eq(handed[1], { cont = 0, map = 1420, x = 0.6, y = 0.7 }, "the flight provider is handed the filled place too")
    t.eq(k.problems:count(), 0)
end

tests["travel cont: a continent the client does not give stays nil"] = function(t)
    local k, _, travel, handed = start()
    local s = { label = "Kill bats", place = { map = 1420, x = 0.6, y = 0.7 } }
    local out, how = travel.via(s)
    t.eq(how, nil)
    t.ok(out == s)
    t.eq(handed[1], { map = 1420, x = 0.6, y = 0.7 })
    t.eq(k.problems:count(), 0)
end

tests["travel cont: a continent already on the place is kept"] = function(t)
    local _, _, travel, handed = start({ cont = 5 })
    travel.via({ label = "Kill bats", place = { cont = 0, map = 1420, x = 0.6, y = 0.7 } })
    t.eq(handed[1], { cont = 0, map = 1420, x = 0.6, y = 0.7 })
end

tests["travel cont: the step place handed in is not changed"] = function(t)
    local _, _, travel = start({ cont = 0 })
    local place = { map = 1420, x = 0.6, y = 0.7 }
    travel.via({ label = "Kill bats", place = place })
    t.eq(place, { map = 1420, x = 0.6, y = 0.7 })
end

tests["map cont: the fake gives what the test set"] = function(t)
    local f = ns.make.fakeClient()
    t.eq(f.mapCont(1420), nil)
    f.setMapCont(1420, 0)
    t.eq(f.mapCont(1420), 0)
    f.setMapCont(1420, nil)
    t.eq(f.mapCont(1420), nil)
end

tests["map cont: the client reads the first number of the world place"] = function(t)
    local asked
    local env = {
        CreateVector2D = function(x, y) return { x = x, y = y } end,
        C_Map = { GetWorldPosFromMapPos = function(map, pos)
            asked = { map = map, x = pos.x, y = pos.y }
            if map == 1420 then return 0, { x = 1, y = 2 } end
            return nil
        end },
    }
    local c = ns.make.client(env)
    t.eq(c.mapCont(1420), 0)
    t.eq(asked, { map = 1420, x = 0.5, y = 0.5 })
    t.eq(c.mapCont(9), nil, "a map the client gives nothing for")
    t.eq(c.mapCont("1420"), nil)
    t.eq(c.mapCont(nil), nil)
end

tests["map cont: unknown rather than guessed"] = function(t)
    local env = {
        CreateVector2D = function(x, y) return { x = x, y = y } end,
        C_Map = { GetWorldPosFromMapPos = function() return "one", {} end },
    }
    local c = ns.make.client(env)
    t.eq(c.mapCont(1420), nil, "not a number")
    env.C_Map.GetWorldPosFromMapPos = function() error("boom") end
    t.eq(c.mapCont(1420), nil, "the call fails")
    env.C_Map.GetWorldPosFromMapPos = function() return 0, {} end
    env.issecretvalue = function() return true end
    t.eq(c.mapCont(1420), nil, "hidden")
    env.issecretvalue = nil
    env.CreateVector2D = nil
    t.eq(c.mapCont(1420), nil, "no way to name a spot")
    t.eq(ns.make.client({}).mapCont(1420), nil)
end

return tests
