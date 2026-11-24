local _, ns = ...

-- End to end (lead section 481, parity row A1-17): when a creature the
-- quest step needs has a nameplate in view, the arrow's words say
-- "There: <name>". On the whole add-on with a fake client; made-up quests
-- and creatures. Not tested in game.
-- Fails before: there is no plateTarget module, so nothing names the plate.

local tests = {}

local WOLF, BOAR, OTHER = 5001, 5002, 5003
local QUESTS = {
    [701] = { ObjectiveData = { { Type = "monster", Id = WOLF } } },
    [702] = { ObjectiveData = { { Type = "monster", Id = BOAR } } },
}
local NPCS = { [WOLF] = { name = "Grey Wolf" }, [BOAR] = { name = "Bristle Boar" } }

local function boot(noQuestie)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setLevel(10); c.setPosition(1454, 0.5, 0.5)
    c.setQuestLog({
        { id = 701, title = "Wolves", complete = false, failed = false,
          objectives = { { text = "Grey Wolf slain: 1/6", done = false } } },
        { id = 702, title = "Boars", complete = false, failed = false,
          objectives = { { text = "Bristle Boar slain: 0/4", done = false } } },
    })
    if not noQuestie then
        c.setQuestieModule("QuestieDB", {
            GetQuest = function(id) return QUESTS[id] end,
            GetNPC = function(id) return NPCS[id] end,
        })
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function mob(c, unit, id)
    c.setCanAttack(unit, true)
    c.setPlateCreature(unit, id)
    c.addPlate(unit)
end

local function there(addon, quest)
    local mod = addon.use("plateTarget")
    return mod and mod.There(quest) or nil
end

tests["plate target e2e: the step's creature in view is named"] = function(t)
    local c, addon = boot()
    mob(c, "nameplate1", OTHER)
    mob(c, "nameplate2", WOLF)
    t.eq(there(addon, 701), "There: Grey Wolf")
    t.eq(there(addon, 702), nil, "no boar in view")
end

tests["plate target e2e: the words go when the plate goes"] = function(t)
    local c, addon = boot()
    mob(c, "nameplate3", BOAR)
    t.eq(there(addon, 702), "There: Bristle Boar")
    c.removePlate("nameplate3")
    t.eq(there(addon, 702), nil)
end

tests["plate target e2e: without Questie nothing is named"] = function(t)
    local c, addon = boot(true)
    mob(c, "nameplate1", WOLF)
    t.eq(there(addon, 701), nil)
end

tests["plate target e2e: the first plate by unit wins"] = function(t)
    local PT = ns.Nav.PlateTarget
    local units = { nameplate10 = true, nameplate2 = true }
    local ids = { nameplate10 = WOLF, nameplate2 = WOLF }
    local unit = PT.Pick(units, function(u) return ids[u] end, { [WOLF] = true })
    t.eq(unit, "nameplate2")
    t.eq(PT.Words(""), nil)
end

return tests
