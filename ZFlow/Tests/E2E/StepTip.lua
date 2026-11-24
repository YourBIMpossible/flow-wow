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

return tests
