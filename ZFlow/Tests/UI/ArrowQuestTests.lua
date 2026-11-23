-- The player's own quests on the quest arrow (S43), over the fake client:
-- a hand-written quest log and a hand-written stand-in for Questie. No game
-- client and no Questie is involved. Not seen in game.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav
local Q = N.QuestSource

-- A stand-in for Questie: quest 101's boars are 50 yd east of the player,
-- quest 202 is handed in 50 yd south. Area 12 is map 1411.
local function questie(opts)
    opts = opts or {}
    local db = {}
    function db.GetQuest(id)
        if opts.fail then error("questie broke") end
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

-- The player in the middle of map 1411 (1000 by 500 yards), facing north.
local function start(log, module)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local held = { log = log }
    c.questLog = function() return held.log end
    if module ~= nil then c.questieModule = module end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, a, k, held, d
end

return {
    ["quest arrow: a step's detail is its second line"] = function(t)
        local c = start(nil)
        local step = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, label = "Boar Trouble",
                       detail = "Boars slain: 2/8" }
        local out = A.GuideSource(c, {}, { quest = step }).lines.quest
        t.eq(out[1], "Boar Trouble")
        t.eq(out[2], "Boars slain: 2/8")
        t.eq(#out, 3, "then the distance line")
    end,

    ["quest arrow: with Questie, the quest name, the objective, and the needle"] = function(t)
        local c, a, k = start({ boars() }, questie())
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(q.lines[1], "Boar Trouble")
        t.eq(q.lines[2], "Boars slain: 2/8")
        t.ok(tostring(q.lines[3]):find("^50 yd") ~= nil, "the distance: " .. tostring(q.lines[3]))
        t.ok(a.state().view.quest.mode ~= "ring", "50 yd is not there yet")
        t.eq(k.problems:count(), 0)
    end,

    ["quest arrow: without Questie, the name and the objective with location unknown"] = function(t)
        local c, _, k = start({ boars() })
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(q.lines, { "Boar Trouble", "Boars slain: 2/8", "location unknown" })
        t.eq(k.problems:count(), 0)
    end,

    ["quest arrow: a Questie error is location unknown, and no problem of ours"] = function(t)
        local c, _, k = start({ boars() }, questie({ fail = true }))
        t.eq(c.arrows[1].lines, { "Boar Trouble", "Boars slain: 2/8", Q.UNKNOWN_PLACE })
        t.eq(k.problems:count(), 0)
    end,

    ["quest arrow: an objective on another map has its place there (S44)"] = function(t)
        -- Was words only with Q.ELSEWHERE (owner session 6, Block B failed
        -- on it). Since S44 (lead section 173) the step has its place on the
        -- other map. This client gives no map corners, so the two maps
        -- cannot be related: no distance, and the direction is unknown.
        local c = start({ wolves() }, questie())
        t.eq(c.arrows[1].lines, { "Wolves", "Wolves slain: 0/4", A.UNKNOWN_TURN })
    end,

    ["quest arrow: a complete quest points at its turn-in"] = function(t)
        local log = wolves()
        log.complete, log.objectives[1].done = true, true
        local c = start({ log }, questie())
        local q = c.arrows[1]
        t.eq(q.lines[1], "Wolves")
        t.eq(q.lines[2], "Turn in: Marshal Dughan")
        t.ok(tostring(q.lines[3]):find("^50 yd") ~= nil, tostring(q.lines[3]))
    end,

    ["quest arrow: an empty log shows no quest arrow"] = function(t)
        local c = start({}, questie())
        t.eq(c.arrows[1].shown, false)
    end,

    ["quest arrow: QUEST_LOG_UPDATE reads the log again"] = function(t)
        local c, _, _, held = start({}, questie())
        t.eq(c.arrows[1].shown, false)
        held.log = { boars() }
        c.fire("QUEST_LOG_UPDATE")
        t.eq(c.arrows[1].shown, true)
        t.eq(c.arrows[1].lines[1], "Boar Trouble")
        held.log = {}
        c.fire("QUEST_LOG_UPDATE")
        t.eq(c.arrows[1].shown, false)
    end,

    ["quest arrow: a change of zone reads it again"] = function(t)
        local c, _, _, held = start({}, questie())
        held.log = { boars() }
        c.fire("ZONE_CHANGED_NEW_AREA")
        t.eq(c.arrows[1].lines[1], "Boar Trouble")
    end,

    ["quest arrow: the quest the player picks out is the one shown"] = function(t)
        local c = start({ boars(), wolves() }, questie())
        t.eq(c.arrows[1].lines[1], "Boar Trouble", "nothing picked: the one on this map")
        c.setQuestFocus(202)
        c.fire("SUPER_TRACKING_CHANGED")
        t.eq(c.arrows[1].lines[1], "Wolves")
        t.eq(c.arrows[1].lines[2], "Wolves slain: 0/4")
        c.setQuestFocus(101)
        c.fire("SUPER_TRACKING_CHANGED")
        t.eq(c.arrows[1].lines[1], "Boar Trouble")
    end,

    ["quest arrow: a change of the watch list is shown"] = function(t)
        local c = start({ boars(), wolves() }, questie())
        c.setQuestFocus(nil, { 202 })
        c.fire("QUEST_WATCH_LIST_CHANGED", 202, true)
        t.eq(c.arrows[1].lines[1], "Wolves")
        c.setQuestFocus(nil, {})
        c.fire("QUEST_WATCH_LIST_CHANGED", 202, false)
        t.eq(c.arrows[1].lines[1], "Boar Trouble")
    end,

    ["quest arrow: a quest taken, dropped or handed in reads the log again"] = function(t)
        for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED" }) do
            local c, _, _, held = start({ boars() }, questie())
            c.setQuestFocus(202)
            t.eq(c.arrows[1].lines[1], "Boar Trouble", "the picked quest is not in the log yet")
            held.log = { boars(), wolves() }
            c.fire(event, "player")
            t.eq(c.arrows[1].lines[1], "Wolves", event)
            held.log = { boars() }
            c.fire(event, "player")
            t.eq(c.arrows[1].lines[1], "Boar Trouble", event .. ", gone again")
        end
    end,

    ["quest arrow: the player's own pin wins over the quest"] = function(t)
        local c, a = start({ boars() }, questie())
        c.setWaypoint(1411, 0.5, 0.1)
        a.relayout()
        t.eq(c.arrows[1].lines[1], N.WAYPOINT_LABEL)
    end,

    ["quest arrow: a guide that was set still wins whole"] = function(t)
        local c, a = start({ boars() }, questie())
        a.setGuide(function() return nil end)
        t.eq(c.arrows[1].shown, false)
    end,

    ["quest arrow: the setting row is quest.arrow, on unless it says false"] = function(t)
        local function k(v) return { settings = { get = function(_, key) if key == "quest.arrow" then return v end end } } end
        t.eq(A.QuestArrowOn(k(nil)), true, "no such row yet: on")
        t.eq(A.QuestArrowOn(k(true)), true)
        t.eq(A.QuestArrowOn(k(false)), false)
        t.eq(A.QuestArrowOn({}), true)
    end,

    ["quest arrow why: says the source, the log, the pick, the reads and the events"] = function(t)
        local c, _, _, _, d = start({ boars(), wolves() }, questie())
        c.setQuestFocusReads({ superTrack = false, questie = 202, watched = { 101, 202 } })
        c.setQuestFocus(202, { 101, 202 })
        c.advance(1, 4)
        local n = #c.printed
        d.commands.arrow("why")
        local said = {}
        for i = n + 1, #c.printed do said[#said + 1] = c.printed[i] end
        t.eq(#said, 5)
        local title = ns.id.title .. ": "
        t.eq(said[1], title .. "quest step from your quests; quest arrow setting on.")
        t.eq(said[2], title .. "quest log: 2 read; Questie places ready; map 1411.")
        t.eq(said[3], title .. "quest 202, chosen from your focus.")
        t.eq(said[4], title .. "focus reads: super track none; Questie focus 202; watch list 2 quests.")
        t.eq(said[5], title .. "events: none refused.")
    end,

    ["quest arrow why: no focus read, no log"] = function(t)
        local c, _, _, held, d = start({ boars() }, questie())
        held.log = nil
        c.fire("QUEST_LOG_UPDATE")
        c.advance(1, 4)
        local n = #c.printed
        d.commands.arrow("why")
        t.eq(#c.printed, n + 4)
        local title = ns.id.title .. ": "
        t.eq(c.printed[n + 1], title .. "quest step from nothing; quest arrow setting on.")
        t.eq(c.printed[n + 2], title .. "quest log: not read.")
        t.eq(c.printed[n + 3], title .. "focus reads: none on this client.")
        t.eq(c.printed[n + 4], title .. "events: none refused.")
    end,

    ["quest arrow why: reads and prints only"] = function(t)
        local c, _, _, _, d = start({ boars() }, questie())
        c.advance(1, 4)
        local before = c.arrows[1].lines[1]
        d.commands.arrow("why")
        c.advance(1, 4)
        t.eq(c.arrows[1].lines[1], before)
        t.eq(c.arrows[1].lines[1], "Boar Trouble")
    end,
}
