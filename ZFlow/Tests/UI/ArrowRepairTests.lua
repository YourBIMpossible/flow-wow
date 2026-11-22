-- The repair step (S6, Nav/RepairStep.lua) on the quest arrow: after the
-- player's own pin and the errand stop, before the player's quests (lead
-- section 162). Over the fake client, with made-up places and readings.
-- Nothing here repairs, buys or clicks. Not seen in game.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav
local RS, R = ns.RepairStep, ns.Repair
local W = N.Waypoint

local WORN = { [5] = { cur = 10, max = 100 } }
local FINE = { [5] = { cur = 90, max = 100 } }
local SMITH = { a = { map = 1411, x = 0.5, y = 0.3, name = "Kaita Deepforge", kinds = { vendor = true, repair = true } } }

-- A stand-in for Questie: quest 101's boars are 50 yd east of the player.
local function questie()
    local db = {}
    function db.GetQuest(id)
        return ({ [101] = { ObjectiveData = { { Type = "monster", Id = 9001 } }, Finisher = { NPC = { 9100 } } } })[id]
    end
    function db:GetNPC(id)
        return ({
            [9001] = { name = "Young Boar", spawns = { [12] = { { 55, 50 } } } },
            [9100] = { name = "Marshal Dughan", spawns = { [12] = { { 50, 60 } } } },
        })[id]
    end
    local zones = {}
    function zones:GetUiMapIdByAreaId(area) return ({ [12] = 1411 })[area] end
    return function(name) return ({ QuestieDB = db, ZoneDB = zones })[name] end
end
local function boars() return { id = 101, title = "Boar Trouble", objectives = { { text = "Boars slain: 2/8" } } } end

-- The player in the middle of map 1411 (1000 by 500 yards), facing north.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { places = { services = opts.services } } })
    c.setDurability(opts.durability)
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setFaction("Horde")
    if opts.log then
        c.questLog = function() return opts.log end
        c.questieModule = questie()
    end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    if not opts.bare then
        R.Declare(k)
        RS.Declare(k)
    end
    A.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    -- A few frames, so the arrow has asked again after the durability reading.
    c.advance(1, 4)
    return c, k, d
end

local function why(c, d)
    local n = #c.printed
    d.commands.arrow("why")
    return c.printed[n + 1]
end
local function from(text) return ns.id.title .. ": quest step from " .. text .. "; quest arrow setting on." end

return {
    ["arrow repair: low gear and a seen vendor put the repair step on the arrow"] = function(t)
        local c, k, d = start({ durability = WORN, services = SMITH })
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(q.lines[1], "Repair: Kaita Deepforge")
        t.ok(tostring(q.lines[#q.lines]):find("^100 yd") ~= nil, "the distance: " .. tostring(q.lines[#q.lines]))
        t.eq(why(c, d), from("a repair stop"))
        t.eq(k.problems:count(), 0)
    end,

    ["arrow repair: it comes before the player's quests"] = function(t)
        local c, _, d = start({ durability = WORN, services = SMITH, log = { boars() } })
        t.eq(c.arrows[1].lines[1], "Repair: Kaita Deepforge")
        t.eq(why(c, d), from("a repair stop"))
    end,

    ["arrow repair: gear that is fine leaves the quests on the arrow"] = function(t)
        local c, _, d = start({ durability = FINE, services = SMITH, log = { boars() } })
        t.eq(c.arrows[1].lines[1], "Boar Trouble")
        t.eq(why(c, d), from("your quests"))
    end,

    ["arrow repair: the player's own waypoint wins over it"] = function(t)
        local c, k, d = start({ durability = WORN, services = SMITH })
        k.store:set(W.SCOPE, W.PATH, { waypoint = { map = 1411, x = 0.9, y = 0.5 } })
        c.advance(1, 4)
        t.eq(why(c, d), from("your own waypoint"))
        t.ok(c.arrows[1].lines[1] ~= "Repair: Kaita Deepforge", "the pin, not the vendor")
    end,

    ["arrow repair: the step goes once the gear is repaired, and the quests come back"] = function(t)
        local c, _, d = start({ durability = WORN, services = SMITH, log = { boars() } })
        t.eq(why(c, d), from("a repair stop"))
        c.setDurability(FINE)
        c.fire(R.EVENT)
        c.advance(1, 4)
        t.eq(why(c, d), from("your quests"))
        t.eq(c.arrows[1].lines[1], "Boar Trouble")
    end,

    ["arrow repair: the setting off keeps it off the arrow"] = function(t)
        local c, k, d = start({ durability = WORN, services = SMITH, log = { boars() } })
        k.settings:set(RS.SETTING, false)
        c.advance(1, 4)
        t.eq(why(c, d), from("your quests"))
        t.eq(c.arrows[1].lines[1], "Boar Trouble")
    end,

    ["arrow repair: low gear and no vendor known is no step, never a guess"] = function(t)
        local c, k, d = start({ durability = WORN })
        t.eq(why(c, d), from("nothing"))
        t.eq(k.problems:count(), 0)
    end,

    ["arrow repair: without the repair step module the arrow is as before"] = function(t)
        local c, k, d = start({ durability = WORN, services = SMITH, log = { boars() }, bare = true })
        t.eq(why(c, d), from("your quests"))
        t.eq(k.problems:count(), 0)
    end,
}
