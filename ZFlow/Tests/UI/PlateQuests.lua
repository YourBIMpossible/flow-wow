-- Tests for ZFlow/UI/PlateQuests.lua (G51, lead sections 226 and 227): a
-- small quest mark over an enemy nameplate whose creature counts toward an
-- unfinished objective of a quest in your log. Which creatures count comes
-- from the installed Questie's objective data at runtime, and from your
-- own learned drops for an item objective; never from a name. Look only.
-- Over the fake client; every name, id and number is made up. Not tested
-- in game.
local _, ns = ...

local PQ = ns.PlateQuests
local tests = {}

local VERMIN, GNOLL, STRANGER, LEARNED = 2001, 2002, 2003, 2004
local PAW, FANG = 3001, 3002

-- Questie's QuestieDB as its loader would hand it out: GetQuest, GetItem.
local function questie(opts)
    opts = opts or {}
    local quests = {
        [101] = { ObjectiveData = { { Type = "monster", Id = VERMIN }, { Type = "item", Id = PAW } } },
        [102] = { ObjectiveData = { { Type = "item", Id = FANG } } },
    }
    local items = { [PAW] = { npcDrops = { GNOLL } }, [FANG] = { npcDrops = {} } }
    return {
        GetQuest = function(id)
            if opts.raise then error("questie failed (test)") end
            return quests[id]
        end,
        GetItem = function(id) return items[id] end,
    }
end

local function log(opts)
    opts = opts or {}
    return {
        { id = 101, title = "Camp", complete = false, failed = false, objectives = {
            { text = "Kobold Vermin slain: " .. (opts.kills or "3/8"), done = opts.killsDone == true },
            { text = "Gnoll Paw: 0/5", done = false },
        } },
        { id = 102, title = "Fangs", complete = false, failed = false, objectives = {
            { text = "Fang: 1/4", done = false },
        } },
    }
end

-- ---------------------------------------------------------------- pure

tests["plate quests: the names, words and numbers agreed"] = function(t)
    t.ok(type(PQ) == "table", "the module table is there")
    if type(PQ) ~= "table" then return end
    t.eq({ PQ.NAME, PQ.WORD, PQ.OFF, PQ.WAIT, PQ.MARK, PQ.DROPS },
        { "plateQuests", "questmarks", "plateQuests.off", 0.5, "!", "learned.drops" })
    t.eq(PQ.COLOR, { 1, 0.82, 0 })
end

tests["plate quests progress: the count of an objective's text, or nil"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    t.eq(PQ.Progress("Kobold Vermin slain: 3/8"), "3/8")
    t.eq(PQ.Progress("3 / 8 Kobold Vermin slain"), "3/8")
    t.eq(PQ.Progress("Speak with the guard"), nil)
    t.eq(PQ.Progress(nil), nil)
end

tests["plate quests index: Questie's kill and drop creatures, unfinished only"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local rows = log()
    local index = PQ.Index(rows, questie(), nil)
    t.eq(index[VERMIN] and index[VERMIN][1].label, "3/8", "the kill objective's creature")
    t.eq(index[VERMIN] and index[VERMIN][1].kind, "kill")
    t.eq(index[GNOLL] and index[GNOLL][1].label, "0/5", "the creature that drops the item")
    t.eq(index[GNOLL] and index[GNOLL][1].kind, "drop")
    t.eq(index[STRANGER], nil, "a creature of no objective")
    rows[1].objectives[1].done = true
    t.eq(PQ.Index(rows, questie(), nil)[VERMIN], nil, "a finished objective counts no more")
    rows = log()
    rows[1].complete = true
    t.eq(PQ.Index(rows, questie(), nil)[GNOLL], nil, "a quest ready to hand in marks nothing")
end

tests["plate quests index: your own learned drops add an item's creature; no Questie, nothing"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local book = { [LEARNED] = { looted = 2, items = { [FANG] = { count = 1, times = 1 } } } }
    local index = PQ.Index(log(), questie(), book)
    t.eq(index[LEARNED] and index[LEARNED][1].label, "1/4", "learned from your own loot")
    t.eq(index[LEARNED] and index[LEARNED][1].from, "learned")
    t.eq(PQ.Index(log(), nil, book), {}, "no Questie: no objective data, no guess by name")
    t.eq(PQ.Index(nil, questie(), book), {}, "no log")
end

tests["plate quests label: each count once, at most two"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    t.eq(PQ.Label({ { label = "3/8" } }), "3/8")
    t.eq(PQ.Label({ { label = "3/8" }, { label = "3/8" }, { label = "0/5" }, { label = "!" } }), "3/8 0/5")
    t.eq(PQ.Label({}), nil)
    t.eq(PQ.Label(nil), nil)
end

-- ---------------------------------------------------------------- module

-- Every read the mark needs is set: the log, Questie, the creature on the
-- plate, the plate on screen and whether it can be attacked.
local function start()
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = PQ.Declare(k, d)
    c.setQuestLog(log())
    c.setQuestieModule("QuestieDB", questie())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(1, 2)
    return k, c, api
end

local function markOf(c, unit)
    for i = #c.plateQuestMarks, 1, -1 do
        if c.plateQuestMarks[i].unit == unit then return c.plateQuestMarks[i] end
    end
    return nil
end

local function mob(c, unit, id)
    c.setCanAttack(unit, true)
    c.setPlateCreature(unit, id)
    c.addPlate(unit)
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return table.concat(out, "\n")
end

tests["plate quests module: started, its setting on by default, filed under nameplates"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local k = start()
    t.eq((k:ModuleState(PQ.NAME)), "started")
    t.eq(k.problems:count(), 0)
    t.eq(k.settings:get(PQ.OFF), false)
    local row = k.settings:row(PQ.OFF)
    t.eq(row and { row.scope, row.group }, { "account", "combat.plates" })
    local model = ns.Settings.Model.Default():row(PQ.OFF)
    t.eq(model and { model.type, model.default }, { "bool", false }, "a row of the settings model")
end

tests["plate quests module: a quest mob's plate gets its count, yellow; another gets nothing"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local k, c, api = start()
    mob(c, "nameplate1", VERMIN)
    mob(c, "nameplate2", STRANGER)
    local m = markOf(c, "nameplate1")
    t.ok(m ~= nil and m.shown, "a mark on the quest mob")
    t.eq(m and m.says, "3/8")
    t.eq(m and m.rgb, PQ.COLOR)
    local other = markOf(c, "nameplate2")
    t.ok(other == nil or other.shown == false, "no mark on a creature of no objective")
    t.eq(api.status().shown, 1)
    t.eq(k.problems:count(), 0)
end

tests["plate quests module: a plate you cannot attack gets no mark"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local _, c = start()
    c.setCanAttack("nameplate1", false)
    c.setPlateCreature("nameplate1", VERMIN)
    c.addPlate("nameplate1")
    local m = markOf(c, "nameplate1")
    t.ok(m == nil or m.shown == false)
end

tests["plate quests module: the log changes, read again once after a short wait"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local _, c = start()
    mob(c, "nameplate1", VERMIN)
    local m = markOf(c, "nameplate1")
    c.setQuestLog(log({ kills = "4/8" }))
    c.fire("QUEST_LOG_UPDATE")
    c.fire("UNIT_QUEST_LOG_CHANGED", "player")
    t.eq(m.says, "3/8", "not at once")
    c.advance(0.5, 1)
    t.eq(m.says, "4/8", "half a second on")
end

tests["plate quests module: off hides the marks; the word says the state"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local k, c = start()
    mob(c, "nameplate1", VERMIN)
    local text = said(c, PQ.WORD)
    t.ok(text:find(ns.id.title .. ": quest marks on nameplates: on; 1 nameplate(s) in view, 1 marked", 1, true) ~= nil, text)
    text = said(c, PQ.WORD .. " off")
    t.eq(k.settings:get(PQ.OFF), true)
    t.eq(markOf(c, "nameplate1").shown, false)
    t.ok(text:find("quest marks on nameplates: off", 1, true) ~= nil, text)
    said(c, PQ.WORD .. " on")
    c.advance(0.5, 1)
    t.eq(markOf(c, "nameplate1").shown, true, "on again")
end

tests["plate quests: only nameplate units are asked about"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local _, c = start()
    local seen = {}
    for _, name in ipairs({ "canAttack", "plateCreature", "plateQuestMark", "guid", "unitInfo" }) do
        local real = c[name]
        c[name] = function(unit, ...)
            seen[#seen + 1] = tostring(unit)
            return real(unit, ...)
        end
    end
    mob(c, "nameplate1", VERMIN)
    c.fire("QUEST_LOG_UPDATE")
    c.advance(1, 2)
    t.ok(#seen > 0, "something was asked")
    for _, unit in ipairs(seen) do
        t.ok(unit:find("^nameplate%d+$") ~= nil, "asked about " .. unit)
    end
end

tests["plate quests: look only - nothing casts, clicks, targets or writes a CVar"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local _, c, api = start()
    for _, tbl in ipairs({ PQ, api }) do
        for name in pairs(tbl) do
            local n = tostring(name):lower()
            for _, bad in ipairs({ "cast", "click", "target", "press", "secure", "cvar" }) do
                t.ok(not n:find(bad, 1, true), "an acting name: " .. n)
            end
        end
    end
    mob(c, "nameplate1", VERMIN)
    t.eq(#c.secureButtons, 0, "no secure button made")
end

-- ---------------------------------------------------------------- lead section 274

-- PM-1: Questie with names, its ObjectiveData in another order than the log.
local function namedQuestie(data)
    local npcs = { [VERMIN] = { name = "Kobold Vermin" }, [GNOLL] = { name = "Gnoll" } }
    local items = { [PAW] = { name = "Gnoll Paw", npcDrops = { GNOLL } } }
    return {
        GetQuest = function(id) if id == 101 then return { ObjectiveData = data } end return nil end,
        GetNPC = function(id) return npcs[id] end,
        GetItem = function(id) return items[id] end,
    }
end

tests["plate quests index (PM-1): a log objective is matched to Questie's by its name, not its place"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local reordered = { { Type = "item", Id = PAW }, { Type = "monster", Id = VERMIN } }
    local index = PQ.Index({ log()[1] }, namedQuestie(reordered), nil)
    t.eq(index[VERMIN] and index[VERMIN][1].label, "3/8", "the kill count on the kill creature")
    t.eq(index[GNOLL] and index[GNOLL][1].label, "0/5", "the item count on the creature that drops it")
end

tests["plate quests index (PM-1): names that match no objective give no mark, never a guess"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local other = { { Type = "monster", Id = GNOLL }, { Type = "monster", Id = GNOLL } }
    local index = PQ.Index({ log()[1] }, namedQuestie(other), nil)
    t.eq(index[GNOLL], nil, "Questie names a Gnoll; the log speaks of Kobold Vermin and Gnoll Paw")
end

tests["plate quests index (PM-2): a '.' call answering no table is no answer; the ':' form is asked"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local db = {
        GetQuest = function(a, b)
            if type(a) == "table" then
                return { ObjectiveData = { { Type = "monster", Id = VERMIN } } }
            end
            return "not a quest"
        end,
    }
    local index = PQ.Index({ log()[1] }, db, nil)
    t.eq(index[VERMIN] and index[VERMIN][1].label, "3/8", "the ':' form's table is taken")
    db.GetQuest = function() return 7 end
    t.eq(PQ.Index({ log()[1] }, db, nil), {}, "neither form a table: nothing")
end

tests["plate quests module (PM-3): switching off by the setting hides the marks on the next look"] = function(t)
    if type(PQ) ~= "table" then return t.ok(false, "no module") end
    local k, c, api = start()
    mob(c, "nameplate1", VERMIN)
    local m = markOf(c, "nameplate1")
    t.eq(m and m.shown, true)
    k.settings:set(PQ.OFF, true)
    c.advance(PQ.LOOK or 0.5, 1)
    t.eq(m and m.shown, false, "hidden with no quest event and no plate change")
    t.eq(api.status().shown, 0)
    k.settings:set(PQ.OFF, false)
    c.advance(1, 2)
    t.eq(m and m.shown, true, "on again: back")
end

return tests
