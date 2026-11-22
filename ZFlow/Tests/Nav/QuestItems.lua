-- Tests for ZFlow/Nav/QuestItems.lua (S42, lead sections 169 and 172):
-- the quest's own item named on the quest arrow, "Use <item> (in your
-- bags)". LOOK ONLY: no click, no secure button, nothing is used for the
-- player (the click is parked behind G23). The game's own quest item only:
-- no Questie fallback. Over the fake client, with a hand-written stand-in
-- for Questie for the arrow. Research: WoW/from-zen/RESEARCH-S42.md.
-- Every name and number is made up. Not tested in game.
local _, ns = ...

local N, A = ns.Nav, ns.Arrow
local QI = N.QuestItems
local tests = {}

local TOTEM = 12345

-- ---------------------------------------------------------------- pure

tests["quest items: the names and words are the ones agreed"] = function(t)
    t.eq({ QI.NAME, QI.WORD, QI.KEEP }, { "questItems", "questitems", 2 })
    t.eq(QI.PLAIN, "Use the quest's item (in your bags)")
    t.eq(N.QuestItemLine("Totem of Ner"), "Use Totem of Ner (in your bags)")
end

tests["quest item of: in the bags and with a use, else why not"] = function(t)
    t.eq({ N.QuestItemOf(TOTEM, 1, true) }, { TOTEM })
    t.eq({ N.QuestItemOf(nil, 1, true) }, { nil, "no quest item" })
    t.eq({ N.QuestItemOf(TOTEM, nil, true) }, { nil, "count unknown" })
    t.eq({ N.QuestItemOf(TOTEM, 0, true) }, { nil, "not in your bags" })
    t.eq({ N.QuestItemOf(TOTEM, 1, nil) }, { nil, "use unknown" })
    t.eq({ N.QuestItemOf(TOTEM, 1, false) }, { nil, "no use" }, "used on something else: as legacy Flow, not shown")
end

tests["quest item line: the name when known, never a number in its place"] = function(t)
    t.eq(N.QuestItemLine(nil), QI.PLAIN)
    t.eq(N.QuestItemLine(""), QI.PLAIN)
    t.eq(N.QuestItemLine(12345), QI.PLAIN)
    t.eq(N.QuestItemLine("Bad|cff name"), QI.PLAIN, "a name that cannot be shown as it is")
end

tests["quest item with: a copy of the step with the line, the step itself not changed"] = function(t)
    local step = { quest = 101, label = "Boar Trouble", detail = "Boars slain: 2/8",
                   place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } }
    local out = N.QuestItemWith(step, "Use Totem of Ner (in your bags)")
    t.ok(out ~= step)
    t.eq(out.use, "Use Totem of Ner (in your bags)")
    t.ok(out.place == step.place and out.label == step.label)
    t.eq(step.use, nil)
    t.ok(N.QuestItemWith(step, nil) == step, "no line: the step itself")
    t.eq(N.QuestItemWith(nil, "x"), nil)
end

-- ---------------------------------------------------------------- module

-- opts: item (false: the quest has none), count, use, name (false: not loaded),
-- arrow (true: the arrows run too, with a stand-in Questie), log.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    if opts.item ~= false then c.setQuestItem(101, TOTEM) end
    c.setItemCount(TOTEM, opts.count == nil and 1 or opts.count)
    if opts.use ~= "unknown" then c.setItemUse(TOTEM, opts.use ~= false) end
    if opts.name ~= false then c.setItemInfo({ [TOTEM] = { name = "Totem of Ner" } }) end
    local log = opts.log or { { id = 101, title = "Boar Trouble", objectives = { { text = "Boars slain: 2/8" } } } }
    c.questLog = function() return log end
    if opts.questie then
        local db = {}
        function db.GetQuest(id)
            if id == 101 then return { ObjectiveData = { { Type = "monster", Id = 9001 } } } end
            return nil
        end
        function db.GetNPC(id)
            if id == 9001 then return { name = "Young Boar", spawns = { [12] = { { 55, 50 } } } } end
            return nil
        end
        local zones = {}
        function zones.GetUiMapIdByAreaId(area) return area == 12 and 1411 or nil end
        c.questieModule = function(name) return ({ QuestieDB = db, ZoneDB = zones })[name] end
    end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    if opts.arrow then A.Start(k, d) end
    local api = QI.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function step()
    return { quest = 101, label = "Boar Trouble", detail = "Boars slain: 2/8",
             place = { cont = 1, map = 1411, x = 0.55, y = 0.5 } }
end

tests["quest items module: started, and it provides With and For"] = function(t)
    local k = start()
    t.eq((k:ModuleState(QI.NAME)), "started")
    local provided = k.use(QI.NAME)
    t.ok(type(provided.With) == "function" and type(provided.For) == "function")
    t.eq(k.problems:count(), 0)
end

tests["quest items module: a quest with its own item gets the line"] = function(t)
    local k, _, api = start()
    local item = api.forQuest(101)
    t.eq(item, { id = TOTEM, name = "Totem of Ner", count = 1, line = "Use Totem of Ner (in your bags)" })
    local out = k.use(QI.NAME).With(step())
    t.eq(out.use, "Use Totem of Ner (in your bags)")
    t.eq(out.label, "Boar Trouble")
end

tests["quest items module: no item, none in the bags, no use, or not known: the step as it is"] = function(t)
    for _, opts in ipairs({ { item = false }, { count = 0 }, { use = false }, { use = "unknown" } }) do
        local _, _, api = start(opts)
        local s = step()
        t.ok(api.with(s) == s, "the same step")
        t.eq(api.forQuest(101), nil)
    end
end

tests["quest items module: only a quest step gets a line"] = function(t)
    local _, _, api = start()
    local pin = { label = "Waypoint", place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } }
    t.ok(api.with(pin) == pin)
    t.eq(api.with(nil), nil)
end

tests["quest items module: a name not loaded yet is the plain line"] = function(t)
    local _, _, api = start({ name = false })
    t.eq(api.with(step()).use, QI.PLAIN)
end

tests["quest items module: kept a moment, read again after a bag change or the moment"] = function(t)
    local _, c, api = start()
    t.eq(api.with(step()).use, "Use Totem of Ner (in your bags)")
    c.setItemCount(TOTEM, 0)
    t.eq(api.with(step()).use, "Use Totem of Ner (in your bags)", "kept for QI.KEEP seconds")
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(api.with(step()).use, nil, "the bags changed: read again, used up")
    c.setItemCount(TOTEM, 1)
    t.eq(api.with(step()).use, nil, "kept again")
    c.advance(QI.KEEP + 0.5, 1)
    t.eq(api.with(step()).use, "Use Totem of Ner (in your bags)", "the moment passed: read again")
end

tests["quest items module: the word lists the quests with an item"] = function(t)
    local log = { { id = 101, title = "Boar Trouble", objectives = {} },
                  { id = 202, title = "Wolves", objectives = {} } }
    local _, c = start({ log = log })
    c.setQuestItem(202, 777)
    c.setItemCount(777, 0)
    c.setItemUse(777, true)
    c.slashes[ns.id.slash](QI.WORD)
    local said = table.concat(c.printed, "\n")
    t.ok(said:find(ns.id.title .. ": ", 1, true) ~= nil, said)
    t.ok(said:find("Boar Trouble: Totem of Ner (1 in your bags)", 1, true) ~= nil, said)
    t.ok(said:find("Wolves: not shown (not in your bags)", 1, true) ~= nil, said)
end

tests["quest items module: the word with no quest log read says so"] = function(t)
    local _, c = start()
    c.questLog = function() return nil end
    c.slashes[ns.id.slash](QI.WORD)
    t.ok(c.printed[#c.printed]:find("could not be read", 1, true) ~= nil, c.printed[#c.printed])
end

-- ---------------------------------------------------------------- arrow

tests["quest items on the arrow: the line under the objective, then the distance"] = function(t)
    local k, c = start({ arrow = true, questie = true })
    local q = c.arrows[1]
    t.eq(q.shown, true)
    t.eq(q.lines[1], "Boar Trouble")
    t.eq(q.lines[2], "Boars slain: 2/8")
    t.eq(q.lines[3], "Use Totem of Ner (in your bags)")
    t.ok(tostring(q.lines[4]):find("^50 yd") ~= nil, "the distance: " .. tostring(q.lines[4]))
    t.eq(k.problems:count(), 0)
end

tests["quest items on the arrow: no item, the lines as before"] = function(t)
    local _, c = start({ arrow = true, questie = true, item = false })
    local q = c.arrows[1]
    t.eq(q.lines[2], "Boars slain: 2/8")
    t.ok(tostring(q.lines[3]):find("^50 yd") ~= nil, tostring(q.lines[3]))
end

tests["quest items on the arrow: a step in words only gets the line last"] = function(t)
    local _, c = start({ arrow = true })
    t.eq(c.arrows[1].lines, { "Boar Trouble", "Boars slain: 2/8", "location unknown",
                              "Use Totem of Ner (in your bags)" })
end

tests["quest items: look only - nothing uses, clicks or casts for you"] = function(t)
    for name in pairs(QI) do
        local n = tostring(name):lower()
        t.ok(not (n:find("click") or n:find("cast") or n:find("press") or n:find("secure") or n:find("bind")),
            "no acting function: " .. n)
    end
    local _, c = start({ arrow = true, questie = true })
    for _, h in ipairs(c.arrows) do
        t.ok(h.secure == nil and h.attributes == nil, "the arrow holds no secure action")
    end
end

return tests
