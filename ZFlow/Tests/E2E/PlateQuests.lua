local _, ns = ...
-- Nameplate quest marks end to end (G51), on the whole add-on loaded on a
-- fake client. Per lead section 236: a plate added for a quest mob; the
-- objective completing; a plate added before the quest log is read;
-- Questie absent; a read raising, then recovering; a reload. Every read
-- the mark needs is set in each fixture (the log, Questie, the creature on
-- the plate, the plate on screen, whether it can be attacked). Look only.
-- Made-up quests, creatures and items. Not tested in game.
local tests = {}

local VERMIN, GNOLL, LEARNED = 2001, 2002, 2004
local PAW, FANG = 3001, 3002
local QUESTS = {
    [101] = { ObjectiveData = { { Type = "monster", Id = VERMIN }, { Type = "item", Id = PAW } } },
    [102] = { ObjectiveData = { { Type = "item", Id = FANG } } },
}
local ITEMS = { [PAW] = { npcDrops = { GNOLL } }, [FANG] = { npcDrops = {} } }

-- fails.quest: GetQuest raises while true.
local function questie(fails)
    return {
        GetQuest = function(id)
            if fails and fails.quest then error("questie failed (test)") end
            return QUESTS[id]
        end,
        GetItem = function(id) return ITEMS[id] end,
    }
end

local function log(kills, done)
    return {
        { id = 101, title = "Camp", complete = false, failed = false, objectives = {
            { text = "Kobold Vermin slain: " .. kills, done = done == true },
            { text = "Gnoll Paw: 0/5", done = false },
        } },
        { id = 102, title = "Fangs", complete = false, failed = false, objectives = {
            { text = "Fang: 1/4", done = false },
        } },
    }
end

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

-- opts: account, char (saved tables), noLog, noQuestie, fails, before(c).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setPosition(1454, 0.5, 0.5)
    if not opts.noLog then c.setQuestLog(log("3/8")) end
    if not opts.noQuestie then c.setQuestieModule("QuestieDB", questie(opts.fails)) end
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    -- Lead (section 271): the fake has no cast read and no spell tooltip hook,
    -- so a whole-addon boot already lists problems. Count from here.
    atBoot[addon] = addon.problems:count()
    return c, addon
end

local function mob(c, unit, id)
    c.setCanAttack(unit, true)
    c.setPlateCreature(unit, id)
    c.addPlate(unit)
end

local function markOf(c, unit)
    for i = #c.plateQuestMarks, 1, -1 do
        if c.plateQuestMarks[i].unit == unit then return c.plateQuestMarks[i] end
    end
    return nil
end

local function shows(c, unit)
    local m = markOf(c, unit)
    if m == nil or not m.shown then return nil end
    return m.says
end

local function logChanged(c)
    c.fire("QUEST_LOG_UPDATE")
    c.advance(0.5, 1)
end

-- Lead section 271: the boot baseline above cannot see a problem this module
-- lists during boot itself. The whole list, filtered by owner, can.
local function ownProblems(addon)
    local out = {}
    for _, p in ipairs(addon.problems:list()) do
        if p.owner == ns.PlateQuests.NAME then out[#out + 1] = p.kind .. ": " .. p.text end
    end
    return out
end

tests["plate quests: the module lists no problem of its own during boot"] = function(t)
    for _, opts in ipairs({ {}, { noQuestie = true }, { noLog = true } }) do
        local _, addon = boot(opts)
        t.eq(ownProblems(addon), {}, "no plateQuests problem at boot")
    end
end

tests["plate quests: a plate added for a quest mob gets its mark"] = function(t)
    local c, addon = boot()
    mob(c, "nameplate1", VERMIN)
    mob(c, "nameplate2", GNOLL)
    t.eq(shows(c, "nameplate1"), "3/8", "the kill objective's count")
    t.eq(shows(c, "nameplate2"), "0/5", "the mob that drops the quest item")
    t.eq(newProblems(addon), 0, "no problem listed after boot")
end

tests["plate quests: the objective completes - the mark goes"] = function(t)
    local c = boot()
    mob(c, "nameplate1", VERMIN)
    t.eq(shows(c, "nameplate1"), "3/8")
    c.setQuestLog(log("8/8", true))
    logChanged(c)
    t.eq(shows(c, "nameplate1"), nil, "a finished objective: no mark")
end

tests["plate quests: the plate goes - its mark hides"] = function(t)
    local c = boot()
    mob(c, "nameplate1", VERMIN)
    local m = markOf(c, "nameplate1")
    c.removePlate("nameplate1")
    t.eq(m and m.shown, false)
end

tests["plate quests: a plate added before the quest log is read - the mark comes when it is"] = function(t)
    local c = boot({ noLog = true })
    mob(c, "nameplate1", VERMIN)
    t.eq(shows(c, "nameplate1"), nil, "the log not read: no mark, no guess")
    c.setQuestLog(log("3/8"))
    logChanged(c)
    t.eq(shows(c, "nameplate1"), "3/8", "read: the mark")
end

tests["plate quests: Questie absent - no mark, never a guess by name"] = function(t)
    local c, addon = boot({ noQuestie = true })
    mob(c, "nameplate1", VERMIN)
    t.eq(shows(c, "nameplate1"), nil)
    local api = addon.use("plateQuests")
    local s = type(api) == "table" and type(api.Status) == "function" and api.Status() or {}
    t.eq(s.source, "no questie")
    c.setQuestieModule("QuestieDB", questie())
    logChanged(c)
    t.eq(shows(c, "nameplate1"), "3/8", "Questie loaded later: the mark on the next log change")
end

tests["plate quests: your own learned drops mark the creature Questie does not name"] = function(t)
    local book = { [LEARNED] = { looted = 1, items = { [FANG] = { count = 1, times = 1 } } } }
    local c = boot({ char = { learned = { drops = book } } })
    mob(c, "nameplate1", LEARNED)
    t.eq(shows(c, "nameplate1"), "1/4")
end

tests["plate quests: a read raising, then recovering"] = function(t)
    local fails = { quest = true }
    local c, addon = boot({ fails = fails })
    mob(c, "nameplate1", VERMIN)
    t.eq(shows(c, "nameplate1"), nil, "Questie raised: no mark")
    fails.quest = false
    logChanged(c)
    t.eq(shows(c, "nameplate1"), "3/8", "Questie recovered")
    c.setPlateCreatureFails(true)
    mob(c, "nameplate2", VERMIN)
    t.eq(shows(c, "nameplate2"), nil, "the creature read raised: no mark")
    c.setPlateCreatureFails(false)
    logChanged(c)
    t.eq(shows(c, "nameplate2"), "3/8", "the creature read recovered")
    t.eq(newProblems(addon), 0, "no problem listed after boot")
end

tests["plate quests: a reload - the marks come back, the switch is kept"] = function(t)
    local c, addon = boot()
    mob(c, "nameplate1", VERMIN)
    addon.settings:set("plateQuests.off", true)
    local c2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    mob(c2, "nameplate1", VERMIN)
    t.eq(shows(c2, "nameplate1"), nil, "off is kept over the reload")
    local c3, addon3 = boot()
    mob(c3, "nameplate1", VERMIN)
    t.eq(shows(c3, "nameplate1"), "3/8", "on: the mark after a reload")
    t.eq(newProblems(addon3), 0, "no problem listed after boot")
end

tests["plate quests: the setting row is on by default and filed under nameplates"] = function(t)
    local _, addon = boot()
    local row = addon.settings:row("plateQuests.off")
    t.eq(row and row.type, "bool")
    t.eq(row and row.group, "combat.plates")
    t.eq(addon.settings:get("plateQuests.off"), false)
    local words = " " .. table.concat(row and row.synonyms or {}, " ") .. " "
    for _, w in ipairs({ "quest", "nameplate", "objective", "mark", "kill" }) do
        t.ok(words:find(" " .. w .. " ", 1, true) ~= nil, "synonym " .. w .. ": " .. words)
    end
end

-- Parity row C-21 (lead section 603): hovering a quest mob, the game's
-- tooltip gets a line naming the quest and the count left (Flow
-- Modules/QuestMarks.lua TipLine, there for profession drops), from the
-- same data the plate mark uses. The hovered creature comes from
-- client.unitCreature (a CLIENT NEED; the fake has it).
-- Fails before: nothing listens to the unit tooltip.
local function tipLines(c, unit)
    local out = {}
    for _, l in ipairs(c.showUnitTooltip(unit)) do out[#out + 1] = l.text end
    return out
end

tests["plate quests: hovering a quest mob - the tooltip names the quest and the count"] = function(t)
    local c = boot()
    c.setUnitCreature("mouseover", VERMIN)
    t.eq(tipLines(c, "mouseover"), { ns.id.title .. ": Camp 3/8" })
    c.setUnitCreature("mouseover", GNOLL)
    t.eq(tipLines(c, "mouseover"), { ns.id.title .. ": Camp 0/5" }, "the mob that drops the item")
end

tests["plate quests: hovering - no line for other mobs, finished objectives or marks off"] = function(t)
    local c, addon = boot()
    c.setUnitCreature("mouseover", 9999)
    t.eq(tipLines(c, "mouseover"), {}, "not a quest mob")
    c.setUnitCreature("mouseover", nil)
    t.eq(tipLines(c, "mouseover"), {}, "creature not known")
    c.setUnitCreature("mouseover", VERMIN)
    c.setQuestLog(log("8/8", true))
    logChanged(c)
    t.eq(tipLines(c, "mouseover"), {}, "objective done")
    c.setQuestLog(log("3/8"))
    logChanged(c)
    addon.settings:set(ns.PlateQuests.OFF, true)
    t.eq(tipLines(c, "mouseover"), {}, "quest marks switched off")
end

tests["plate quests: hovering a plate unit uses the plate's creature"] = function(t)
    local c = boot()
    mob(c, "nameplate1", VERMIN)
    t.eq(tipLines(c, "nameplate1"), { ns.id.title .. ": Camp 3/8" })
end

return tests
