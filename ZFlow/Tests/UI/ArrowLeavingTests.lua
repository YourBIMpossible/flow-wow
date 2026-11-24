-- R7 (section 387): the leaving-zone chat line through the real entry, over the
-- fake client: Arrow.Start with the quest log and a stand-in for Questie,
-- then ZONE_CHANGED_NEW_AREA. No game client and no Questie is involved.
-- Not seen in game.
local _, ns = ...

local A = ns.Arrow

-- Quest 101's boars are on map 1411 (area 12); quest 202's wolves on map
-- 1412 (area 40).
local function questie()
    local db = {}
    function db.GetQuest(id)
        return ({
            [101] = { ObjectiveData = { { Type = "monster", Id = 9001 } }, Finisher = { NPC = { 9100 } } },
            [202] = { ObjectiveData = { { Type = "monster", Id = 9002 } }, Finisher = { NPC = { 9100 } } },
        })[id]
    end
    function db:GetNPC(id)
        return ({
            [9001] = { name = "Young Boar", spawns = { [12] = { { 55, 50 } } } },
            [9002] = { name = "Far Wolf", spawns = { [40] = { { 50, 50 } } } },
            [9100] = { name = "Marshal Dughan", spawns = { [12] = { { 50, 60 } } } },
        })[id]
    end
    local zones = {}
    function zones:GetUiMapIdByAreaId(area) return ({ [12] = 1411, [40] = 1412 })[area] end
    return function(name) return ({ QuestieDB = db, ZoneDB = zones })[name] end
end

local function boars() return { id = 101, title = "Boar Trouble", objectives = { { text = "Boars slain: 2/8" } } } end
local function wolves() return { id = 202, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } end

local function start(log)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapSize(1412, 1000, 500)
    c.setMapName(1411, "Elwynn Forest")
    c.setMapName(1412, "Westfall")
    c.questLog = function() return log end
    c.questieModule = questie()
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    A.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, k
end

local function leave(c)
    c.setZone(1, 1412)
    c.setPosition(1412, 0.5, 0.5)
    c.fire("ZONE_CHANGED_NEW_AREA")
end

local function leavingLines(c)
    local out = {}
    for _, line in ipairs(c.printed) do
        if line:find("Still to do before you leave", 1, true) then out[#out + 1] = line end
    end
    return out
end

return {
    ["leaving a zone with a step still open there: one line, with the title"] = function(t)
        local c, k = start({ boars(), wolves() })
        leave(c)
        t.eq(leavingLines(c), { ns.id.title .. ": Your next step is in Westfall. Still to do before you leave: Boar Trouble" })
        t.eq(k.problems:count(), 0)
    end,

    ["the same zone change again says nothing more"] = function(t)
        local c = start({ boars(), wolves() })
        leave(c)
        c.fire("ZONE_CHANGED_NEW_AREA")
        leave(c)
        t.eq(#leavingLines(c), 1, "once per leaving")
    end,

    ["nothing open in the zone left: no line"] = function(t)
        local c = start({ wolves() })
        leave(c)
        t.eq(#leavingLines(c), 0)
    end,

    ["the setting off: no line"] = function(t)
        local c, k = start({ boars(), wolves() })
        k:Setting({ key = ns.Nav.LEAVING_SETTING, scope = "account", type = "bool", default = true,
            group = "travel.route", label = "Finish quests in this zone first" })
        t.eq(k.settings:set(ns.Nav.LEAVING_SETTING, false), true)
        leave(c)
        t.eq(#leavingLines(c), 0)
    end,

    ["the fake client's map names"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.mapName(1411), nil, "not set: not known")
        c.setMapName(1411, "Elwynn Forest")
        t.eq(c.mapName(1411), "Elwynn Forest")
    end,
}
