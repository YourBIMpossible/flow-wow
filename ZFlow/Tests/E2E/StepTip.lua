local _, ns = ...

-- End to end (lead section 488, parity row A1-12): the quest step's hover
-- lines say the quest level in its colour, the objectives with progress,
-- the XP and what else is here. On the whole add-on with a fake client;
-- made-up quests. Not tested in game.
-- Fails before: there is no stepTip module, so there are no such lines.

local tests = {}

local MAP = 1411
local LEVELS = { [801] = 12 }

local function boot(level)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setLevel(level or 10)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setMapSize(MAP, 1000, 1000)
    c.setQuestLog({
        { id = 801, title = "Wolves", complete = false, failed = false,
          objectives = { { text = "Grey Wolf slain: 6/6", done = true },
                         { text = "Wolf Pelt: 1/4", done = false } } },
    })
    c.setQuestieModule("QuestieDB", {
        QueryQuestSingle = function(id, field) if field == "questLevel" then return LEVELS[id] end end,
    })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function lines(addon, quest)
    local mod = addon.use("stepTip")
    return mod and mod.Lines(quest) or nil
end

tests["step tip e2e: level, objectives and XP for a quest in the log"] = function(t)
    local _, addon = boot(10)
    local ST = ns.Nav.StepTip
    t.eq(lines(addon, 801), {
        "|cffffff00Level 12|r: about your level: full XP",
        "|cff66e666  Grey Wolf slain: 6/6|r",
        "  Wolf Pelt: 1/4",
        "XP: about 820 (2 levels above you)",
    })
    t.ok(ST ~= nil)
end

-- R-07 (lead section 777): a pickup step (the quest not in the log yet) has
-- lines too, as Flow's N:FillTooltip gives every step: the level in its
-- colour from Questie, the XP, and Questie's own words for the quest
-- (Modules/Nav/Nav.lua:3279-3313, questText :3244-3249, cut at 260).
tests["step tip e2e: a pickup step has its level, XP and the quest's words"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setLevel(10)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setMapSize(MAP, 1000, 1000)
    c.setQuestLog({})
    local long = string.rep("a", 300)
    local DESC = { [802] = "Bring me 8 boar ribs.", [803] = long }
    c.setQuestieModule("QuestieDB", {
        QueryQuestSingle = function(id, field) if field == "questLevel" then return ({ [802] = 9, [803] = 9 })[id] end end,
        GetQuest = function(id) if DESC[id] then return { Description = { DESC[id] } } end end,
    })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    t.eq(lines(addon, 802), {
        "|cffffff00Level 9|r: about your level: full XP",
        "Bring me 8 boar ribs.",
        "XP: about 575 (full XP)",
    })
    local cut = lines(addon, 803)
    t.eq(cut and cut[2], long:sub(1, 257) .. "...", "long words are cut, as Flow")
end

tests["step tip e2e: a quest not in the log has no lines"] = function(t)
    local _, addon = boot(10)
    t.eq(lines(addon, 999), nil)
end

tests["step tip: the tiers and the XP notes are Flow's"] = function(t)
    local ST = ns.Nav.StepTip
    t.eq(ST.Tier(15, 10), "red")
    t.eq(ST.Tier(13, 10), "orange")
    t.eq(ST.Tier(8, 10), "yellow")
    t.eq(ST.Tier(5, 10), "green")
    t.eq(ST.Tier(1, 10), "olive")
    t.eq(ST.Tier(1, 20), "grey")
    t.eq(ST.Tier(nil, 10), nil)
    t.eq({ ST.Xp(10, 10) }, { 630, "full XP" })
    t.eq({ ST.Xp(10, 17) }, { 378, "60% XP: going grey" })
    t.eq({ ST.Xp(10, 13) }, { 630, "full XP for now; it starts to drop at level 16" })
end

tests["step tip: also here comes last, under its title"] = function(t)
    local ST = ns.Nav.StepTip
    t.eq(ST.Lines({ objectives = {}, also = { "Hand in: Boars" } }), { "Also here", "  Hand in: Boars" })
end


-- Plexy CHANGES-2 (lead section 497): through the hover, as TripTip.lua.
-- The quest arrow on quest 801 (its wolves placed by the Questie stand-in)
-- shows the lines; after the demo is switched on they are gone.
local function bootPlaced()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setLevel(10)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setQuestLog({
        { id = 801, title = "Wolves", complete = false, failed = false,
          objectives = { { text = "Wolf Pelt: 1/4", done = false } } },
    })
    local db = {}
    function db.QueryQuestSingle(id, field) if field == "questLevel" then return LEVELS[id] end end
    function db.GetQuest(id)
        if id == 801 then return { ObjectiveData = { { Type = "monster", Id = 9801 } } } end
    end
    function db.GetNPC(id)
        if id == 9801 then return { name = "Grey Wolf", spawns = { [12] = { { 60, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = MAP })[area] end
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function tipOf(c)
    local a = c.arrows[1]
    if not a then return {} end
    a.hover(false)
    a.hover(true)
    return a.tipLines or {}
end

local function has(list, text)
    for _, line in ipairs(list) do
        if type(line) == "string" and line:find(text, 1, true) then return true end
    end
    return false
end

tests["step tip e2e: hovering the quest arrow on quest 801 shows its lines"] = function(t)
    local c = bootPlaced()
    local tip = tipOf(c)
    t.ok(has(tip, "Level 12"), table.concat(tip, " | "))
    t.ok(has(tip, "  Wolf Pelt: 1/4"), table.concat(tip, " | "))
    t.ok(has(tip, "XP: about"), table.concat(tip, " | "))
end

tests["step tip e2e: after switching to the demo, quest 801's lines are gone"] = function(t)
    local c = bootPlaced()
    t.ok(has(tipOf(c), "Wolf Pelt: 1/4"), "shown first")
    c.slashes[ns.id.slash]("arrow demo")
    c.advance(2, 8)
    local tip = tipOf(c)
    t.ok(not has(tip, "Wolf Pelt"), table.concat(tip, " | "))
    t.ok(not has(tip, "Level 12"), table.concat(tip, " | "))
end

return tests
