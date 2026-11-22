-- The client reads of the quest arrow (F1): questLog, questieModule,
-- minimap and minimapPin, on the real boundary with a stand-in for the
-- globals of the client, and on the fake. No game client is involved, and
-- every call named here is a first guess not seen in game.
local _, ns = ...

-- A quest log as C_QuestLog would give it. entries: a list of
-- { title, questID, isHeader }; objectives, complete, failed: by quest id.
local function newLog(entries, extra)
    extra = extra or {}
    local group = {}
    function group.GetNumQuestLogEntries() return #entries end
    function group.GetInfo(i) return entries[i] end
    function group.GetQuestObjectives(id) return (extra.objectives or {})[id] end
    function group.IsComplete(id) return (extra.complete or {})[id] end
    function group.IsFailed(id) return (extra.failed or {})[id] end
    return group
end

-- A minimap frame, and every frame made on it in env.frames.
local function mapEnv(opts)
    opts = opts or {}
    local env = { frames = {} }
    env.Minimap = {}
    function env.Minimap:GetWidth() return opts.width or 140 end
    function env.CreateFrame(kind, name, parent)
        if opts.noFrames then error("no frames") end
        local f = { kind = kind, name = name, parent = parent, shown = true, calls = {} }
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:SetSize(w, h) self.w, self.h = w, h end
        function f:EnableMouse(on) self.mouse = on end
        function f:ClearAllPoints() self.point = nil end
        function f:SetPoint(...) self.point = { ... } end
        function f:SetAlpha(a) self.alpha = a end
        env.frames[#env.frames + 1] = f
        return f
    end
    return env
end

return {
    ["client quest log: rows from C_QuestLog, headers left out"] = function(t)
        local env = {
            C_QuestLog = newLog({
                { title = "Zone", questID = 0, isHeader = true },
                { title = "First", questID = 11, isHeader = false },
                { title = "Second", questID = 12, isHeader = false },
            }, {
                objectives = { [11] = { { text = "Wolves: 2/8", finished = false }, { text = "Bears: 4/4", finished = true } } },
                complete = { [11] = false, [12] = true },
                failed = { [11] = false, [12] = false },
            }),
        }
        local rows = ns.make.client(env).questLog()
        t.eq(rows, {
            {
                id = 11, title = "First", complete = false, failed = false,
                objectives = { { text = "Wolves: 2/8", done = false }, { text = "Bears: 4/4", done = true } },
            },
            { id = 12, title = "Second", complete = true, failed = false, objectives = {} },
        })
    end,

    ["client quest log: what the client did not say stays unknown"] = function(t)
        local group = newLog({ { title = "Only", questID = 5 } }, { objectives = { [5] = { { finished = true }, "junk" } } })
        group.IsComplete = nil
        local rows = ns.make.client({ C_QuestLog = group }).questLog()
        t.eq(#rows, 1)
        t.eq(rows[1].complete, nil, "no IsComplete: not known, not false")
        t.eq(rows[1].failed, nil, "IsFailed gave nothing")
        t.eq(rows[1].objectives, { { done = true }, { done = false } }, "no text is nil text")
    end,

    ["client quest log: an empty log is an empty list, not nil"] = function(t)
        t.eq(ns.make.client({ C_QuestLog = newLog({}) }).questLog(), {})
    end,

    ["client quest log: no quest log calls at all is nil"] = function(t)
        t.eq(ns.make.client({}).questLog(), nil)
    end,

    ["client quest log: a count that fails or is not a number is nil"] = function(t)
        local group = newLog({})
        group.GetNumQuestLogEntries = function() error("boom") end
        t.eq(ns.make.client({ C_QuestLog = group }).questLog(), nil)
        group.GetNumQuestLogEntries = function() return "many" end
        t.eq(ns.make.client({ C_QuestLog = group }).questLog(), nil)
    end,

    ["client quest log: a row that fails or has no id or title is skipped"] = function(t)
        local group = newLog({
            { title = "No id" },
            { questID = 7 },
            { title = "Good", questID = 8 },
            { title = "Also good", questID = 9 },
        })
        local real = group.GetInfo
        group.GetInfo = function(i)
            if i == 4 then error("boom") end
            return real(i)
        end
        local rows = ns.make.client({ C_QuestLog = group }).questLog()
        t.eq(#rows, 1)
        t.eq(rows[1].id, 8)
    end,

    ["client quest log: hidden values are not read"] = function(t)
        local env = { C_QuestLog = newLog({ { title = "Secret", questID = 3 } }) }
        env.issecretvalue = function() return true end
        t.eq(ns.make.client(env).questLog(), nil, "the count itself is hidden")
    end,

    ["client quest log: the older calls, when there is no C_QuestLog"] = function(t)
        local env = {}
        function env.GetNumQuestLogEntries() return 3 end
        function env.GetQuestLogTitle(i)
            if i == 1 then return "Zone", 0, nil, true, false, nil, 0, 0 end
            if i == 2 then return "Old one", 10, nil, false, false, 1, 0, 21 end
            return "Old two", 10, nil, false, false, -1, 0, 22
        end
        function env.GetNumQuestLeaderBoards(i) return i == 2 and 1 or 0 end
        function env.GetQuestLogLeaderBoard() return "Boars: 3/3", "monster", true end
        t.eq(ns.make.client(env).questLog(), {
            { id = 21, title = "Old one", complete = true, failed = false, objectives = { { text = "Boars: 3/3", done = true } } },
            { id = 22, title = "Old two", complete = false, failed = true, objectives = {} },
        })
    end,

    ["client quest focus: no such read at all is nil"] = function(t)
        t.eq(ns.make.client({}).questFocus(), nil)
        t.eq(ns.make.client({ C_SuperTrack = "x", C_QuestLog = 7, Questie = "y" }).questFocus(), nil)
    end,

    ["client quest focus: the grouped call first, the bare name second"] = function(t)
        local asked = {}
        local env = {
            C_SuperTrack = { GetSuperTrackedQuestID = function() asked[#asked + 1] = "group" return 101 end },
            GetSuperTrackedQuestID = function() asked[#asked + 1] = "bare" return 202 end,
        }
        local c = ns.make.client(env)
        t.eq(c.questFocus(), { quest = 101 })
        t.eq(asked, { "group" })
        env.C_SuperTrack.GetSuperTrackedQuestID = function() error("no") end
        t.eq(c.questFocus(), { quest = 202 }, "a failed grouped call: the bare name")
        env.C_SuperTrack = nil
        t.eq(c.questFocus(), { quest = 202 }, "no group: the bare name")
    end,

    ["client quest focus: none picked is a read with no quest"] = function(t)
        local env = { C_SuperTrack = { GetSuperTrackedQuestID = function() return nil end } }
        local c = ns.make.client(env)
        t.eq(c.questFocus(), {})
        env.C_SuperTrack.GetSuperTrackedQuestID = function() return 0 end
        t.eq(c.questFocus(), {}, "0 is no quest")
        env.C_SuperTrack.GetSuperTrackedQuestID = function() return true end
        t.eq(c.questFocus(), {}, "not a number")
    end,

    ["client quest focus: the quest Questie is set on, when the client names none"] = function(t)
        local env = { Questie = { db = { char = { TrackerFocus = 303 } } } }
        local c = ns.make.client(env)
        t.eq(c.questFocus(), { quest = 303 })
        env.Questie.db.char.TrackerFocus = "303 2"
        t.eq(c.questFocus(), { quest = 303 }, "a text that starts with the id")
        env.Questie.db.char.TrackerFocus = nil
        t.eq(c.questFocus(), {}, "Questie is there and set on none")
        env.Questie.db.char.TrackerFocus = "none"
        t.eq(c.questFocus(), {})
        env.Questie.db = nil
        t.eq(c.questFocus(), nil, "a Questie with no such place: no read")
        env.Questie = { db = { char = { TrackerFocus = 303 } } }
        env.C_SuperTrack = { GetSuperTrackedQuestID = function() return 101 end }
        t.eq(c.questFocus(), { quest = 101 }, "the client is asked first")
        env.C_SuperTrack.GetSuperTrackedQuestID = function() return 0 end
        t.eq(c.questFocus(), { quest = 303 }, "the client names none: Questie")
    end,

    ["client quest focus: the watch list from C_QuestLog"] = function(t)
        local ids = { 101, 0, 202, "x" }
        local env = { C_QuestLog = {
            GetNumQuestWatches = function() return 5 end,
            GetQuestIDForQuestWatchIndex = function(i)
                if i == 5 then error("no") end
                return ids[i]
            end,
        } }
        local c = ns.make.client(env)
        t.eq(c.questFocus(), { watched = { 101, 202 } })
        env.C_QuestLog.GetNumQuestWatches = function() return 0 end
        t.eq(c.questFocus(), { watched = {} }, "nothing watched is an empty list")
        env.C_QuestLog.GetNumQuestWatches = function() return "many" end
        t.eq(c.questFocus(), nil, "a count that is no number: no read")
        env.C_QuestLog.GetNumQuestWatches = function() return 100000 end
        env.C_QuestLog.GetQuestIDForQuestWatchIndex = function(i) return i end
        t.eq(#c.questFocus().watched, 100, "never read past 100 rows")
    end,

    ["client quest focus: the older watch calls, when C_QuestLog has none"] = function(t)
        local env = {
            GetNumQuestWatches = function() return 3 end,
            GetQuestIndexForWatch = function(i) return ({ 4, nil, 9 })[i] end,
            GetQuestLogTitle = function(index)
                if index == 4 then return "Boar Trouble", 5, nil, nil, nil, nil, nil, 101 end
                return "No id", 5
            end,
        }
        local c = ns.make.client(env)
        t.eq(c.questFocus(), { watched = { 101 } })
        env.C_QuestLog = { GetNumQuestWatches = function() return 1 end,
                           GetQuestIDForQuestWatchIndex = function() return 202 end }
        t.eq(c.questFocus(), { watched = { 202 } }, "the grouped calls are asked first")
    end,

    ["client quest focus: hidden values are not read"] = function(t)
        local env = {
            issecretvalue = function() return true end,
            C_SuperTrack = { GetSuperTrackedQuestID = function() return 101 end },
            C_QuestLog = { GetNumQuestWatches = function() return 1 end,
                           GetQuestIDForQuestWatchIndex = function() return 202 end },
            Questie = { db = { char = { TrackerFocus = 303 } } },
        }
        t.eq(ns.make.client(env).questFocus(), {})
    end,

    ["fake quest focus: nothing set is no read, and it answers a copy"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.questFocus(), nil)
        local list = { 101, 202 }
        c.setQuestFocus(101, list)
        local got = c.questFocus()
        t.eq(got, { quest = 101, watched = { 101, 202 } })
        got.watched[1] = 9
        t.eq(c.questFocus().watched, { 101, 202 })
        c.setQuestFocus(nil, {})
        t.eq(c.questFocus(), { watched = {} })
        c.setQuestFocus(nil)
        t.eq(c.questFocus(), nil)
    end,

    ["client questie module: asked of the loader of Questie by name"] = function(t)
        local db, asked = { GetQuest = function() end }, {}
        local env = { QuestieLoader = {} }
        function env.QuestieLoader:ImportModule(name)
            asked[#asked + 1] = name
            if name == "QuestieDB" then return db end
            return nil
        end
        local c = ns.make.client(env)
        t.ok(c.questieModule("QuestieDB") == db, "the module itself")
        t.eq(c.questieModule("ZoneDB"), nil)
        t.eq(asked, { "QuestieDB", "ZoneDB" })
    end,

    ["client questie module: no Questie, a failing loader or a bad name is nil"] = function(t)
        t.eq(ns.make.client({}).questieModule("QuestieDB"), nil)
        local env = { QuestieLoader = {} }
        function env.QuestieLoader:ImportModule() error("boom") end
        local c = ns.make.client(env)
        t.eq(c.questieModule("QuestieDB"), nil)
        t.eq(c.questieModule(""), nil)
        t.eq(c.questieModule(nil), nil)
        function env.QuestieLoader:ImportModule() return "not a table" end
        t.eq(c.questieModule("QuestieDB"), nil)
    end,

    ["client minimap: no minimap frame is nil"] = function(t)
        t.eq(ns.make.client({}).minimap(), nil)
    end,

    ["client minimap: size alone when the client says nothing else"] = function(t)
        local r = ns.make.client(mapEnv()).minimap()
        t.eq(r, { size = 140 }, "radius, rotates and square stay unknown")
    end,

    ["client minimap: radius only from the client, rotates from the setting, square from the shape"] = function(t)
        local env = mapEnv({ width = 160 })
        env.C_Minimap = { GetViewRadius = function() return 233 end }
        env.GetCVar = function(name) return name == "rotateMinimap" and "1" or nil end
        env.GetMinimapShape = function() return "SQUARE" end
        t.eq(ns.make.client(env).minimap(), { size = 160, radius = 233, rotates = true, square = true })
        env.GetCVar = function() return "0" end
        env.GetMinimapShape = function() return "ROUND" end
        t.eq(ns.make.client(env).minimap(), { size = 160, radius = 233, rotates = false })
    end,

    ["client minimap: a radius that is not a positive number is not a radius"] = function(t)
        local env = mapEnv()
        env.C_Minimap = { GetViewRadius = function() return 0 end }
        t.eq(ns.make.client(env).minimap().radius, nil)
        env.C_Minimap.GetViewRadius = function() error("boom") end
        t.eq(ns.make.client(env).minimap().radius, nil)
        env.GetCVar = function() return "sometimes" end
        t.eq(ns.make.client(env).minimap().rotates, nil, "a setting it cannot read is not false")
    end,

    ["client minimap pin: hidden when made, on the minimap, with no mouse"] = function(t)
        local env = mapEnv()
        local h = ns.make.client(env).minimapPin({ size = 10 })
        t.ok(h ~= nil)
        local f = env.frames[1]
        t.ok(f.parent == env.Minimap)
        t.eq({ f.shown, f.mouse, f.w, f.h }, { false, false, 10, 10 })
    end,

    ["client minimap pin: place shows it at the offset, hide hides it"] = function(t)
        local env = mapEnv()
        local h = ns.make.client(env).minimapPin({})
        local f = env.frames[1]
        h.place(12, -30, false)
        t.eq(f.shown, true)
        t.eq({ f.point[1], f.point[3], f.point[4], f.point[5] }, { "CENTER", "CENTER", 12, -30 })
        t.ok(f.point[2] == env.Minimap)
        t.eq(f.alpha, 1)
        h.place(5, 5, true)
        t.ok(f.alpha < 1, "at the edge it is fainter")
        h.hide()
        t.eq(f.shown, false)
    end,

    ["client minimap pin: a place that is not two numbers changes nothing"] = function(t)
        local env = mapEnv()
        local h = ns.make.client(env).minimapPin({})
        local f = env.frames[1]
        h.place(nil, 3)
        h.place(0 / 0, 3)
        t.eq(f.shown, false)
        t.eq(f.point, nil)
    end,

    ["client minimap pin: no minimap or no frames is nil"] = function(t)
        t.eq(ns.make.client({}).minimapPin({}), nil)
        t.eq(ns.make.client(mapEnv({ noFrames = true })).minimapPin({}), nil)
    end,

    ["fake quest reads: nothing set is unknown"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.questLog(), nil)
        t.eq(c.questieModule("QuestieDB"), nil)
        t.eq(c.minimap(), nil)
    end,

    ["fake quest reads: questLog answers a copy of what was set"] = function(t)
        local c = ns.make.fakeClient()
        c.setQuestLog({ { id = 1, title = "A", complete = false, objectives = { { text = "x", done = false } } } })
        local rows = c.questLog()
        t.eq(rows, { { id = 1, title = "A", complete = false, objectives = { { text = "x", done = false } } } })
        rows[1].objectives[1].done = true
        t.eq(c.questLog()[1].objectives[1].done, false, "a caller cannot change the log")
    end,

    ["fake quest reads: a Questie module can be set and taken away"] = function(t)
        local c = ns.make.fakeClient()
        local db = {}
        c.setQuestieModule("QuestieDB", db)
        t.ok(c.questieModule("QuestieDB") == db)
        t.eq(c.questieModule("ZoneDB"), nil)
        c.setQuestieModule("QuestieDB", nil)
        t.eq(c.questieModule("QuestieDB"), nil)
    end,

    ["fake minimap: as set, and pins are kept in order"] = function(t)
        local c = ns.make.fakeClient()
        c.setMinimap({ size = 140, rotates = false })
        t.eq(c.minimap(), { size = 140, rotates = false })
        local h = c.minimapPin({ name = "P", size = 12 })
        t.ok(c.minimapPins[1] == h)
        t.eq(h.shown, false, "hidden when made")
        h.place(3, 4, true)
        t.eq({ h.x, h.y, h.edge, h.shown, h.places }, { 3, 4, true, true, 1 })
        h.hide()
        t.eq({ h.shown, h.hides }, { false, 1 })
    end,

    ["fake minimap: a client that cannot make frames gives no pin"] = function(t)
        local c = ns.make.fakeClient()
        c.setFrames(false)
        t.eq(c.minimapPin({}), nil)
        t.eq(#c.minimapPins, 0)
    end,

    ["client questFocusReads: each read on its own"] = function(t)
        t.eq(ns.make.client({}).questFocusReads(), {}, "no read at all")
        local env = {
            C_SuperTrack = { GetSuperTrackedQuestID = function() return 0 end },
            Questie = { db = { char = { TrackerFocus = 404 } } },
            C_QuestLog = {
                GetNumQuestWatches = function() return 2 end,
                GetQuestIDForQuestWatchIndex = function(i) return ({ 101, 404 })[i] end,
            },
        }
        local c = ns.make.client(env)
        t.eq(c.questFocusReads(), { superTrack = false, questie = 404, watched = { 101, 404 } })
        t.eq(c.questFocus(), { quest = 404, watched = { 101, 404 } }, "the same reads, as one answer")
        env.C_SuperTrack.GetSuperTrackedQuestID = function() return 101 end
        t.eq(c.questFocusReads().superTrack, 101)
        t.eq(c.questFocusReads().questie, 404, "both are said, though the first one wins")
        t.eq(c.questFocus().quest, 101)
        env.C_SuperTrack.GetSuperTrackedQuestID = function() error("no") end
        env.Questie.db.char.TrackerFocus = nil
        local r = c.questFocusReads()
        t.eq(r.superTrack, nil, "a failed call is no read")
        t.eq(r.questie, false, "Questie is there and has no focus")
    end,
}
