local _, ns = ...
-- D-14: bandage or food after a fight (legacy Flow Modules/Rotation/
-- Engine.lua E:Recover, BuffItems.lua HealKind, BandageStep, FoodStep).
-- Made-up items and tooltip lines; not tested in game.
local tests = {}

local RC = ns.Recover
local R = ns.Rotation

local LINEN, WOOL, BREAD, LOAF, WATER, STEW = 9301, 9302, 9303, 9304, 9305, 9306
local INFO = {
    [LINEN] = { name = "Linen Bandage", classID = 0, subclassID = 7, level = 1, minLevel = 0 },
    [WOOL] = { name = "Wool Bandage", classID = 0, subclassID = 7, level = 20, minLevel = 0 },
    [BREAD] = { name = "Tough Hunk of Bread", classID = 0, subclassID = 5, level = 5, minLevel = 1 },
    [LOAF] = { name = "Freshly Baked Bread", classID = 0, subclassID = 5, level = 15, minLevel = 5 },
    [WATER] = { name = "Refreshing Spring Water", classID = 0, subclassID = 5, level = 5, minLevel = 1 },
    [STEW] = { name = "Stamina Stew", classID = 0, subclassID = 5, level = 10, minLevel = 1 },
}
local LINES = {
    [BREAD] = { "Tough Hunk of Bread", "Use: Restores 61 health over 18 sec." },
    [LOAF] = { "Freshly Baked Bread", "Use: Restores 243 health over 21 sec." },
    [WATER] = { "Refreshing Spring Water", "Use: Restores 151 mana over 18 sec." },
    [STEW] = { "Stamina Stew", "Use: Restores 294 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and gain 10 Stamina for 15 min." },
}

local function client(stacks, info, lines)
    local c = ns.make.fakeClient()
    c.setBagItems(stacks)
    c.setItemInfo(info or INFO)
    for id, l in pairs(lines or LINES) do c.setItemLines(id, l) end
    c.setCombat(false)
    return c
end

tests["recover: the kinds, by Flow's name, class and tooltip rules"] = function(t)
    t.eq(RC.Kind(INFO[LINEN]), "bandage")
    t.eq(RC.Kind({ name = "Field Dressing", classID = 0, subclassID = 7 }), "bandage", "class rule")
    t.eq(RC.Kind(INFO[BREAD], LINES[BREAD]), "food")
    t.eq(RC.Kind(INFO[WATER], LINES[WATER]), "drink")
    t.eq(RC.Kind(INFO[BREAD], nil), nil, "food without its tooltip is not known")
    t.eq(RC.Kind({ name = "Minor Healthstone", classID = 0, subclassID = 0 }), nil)
    t.eq(RC.Kind(nil), nil)
end

tests["recover: the best bandage and plain food, Well Fed food only when no plain"] = function(t)
    local pick, partial = RC.Read(client({ { item = LINEN, count = 3 }, { item = WOOL, count = 1 },
        { item = BREAD, count = 4 }, { item = LOAF, count = 2 }, { item = WATER, count = 5 },
        { item = STEW, count = 1 } }))
    t.eq(partial, false)
    t.eq(pick.bandage, WOOL); t.eq(pick.bandageName, "Wool Bandage")
    t.eq(pick.food, LOAF, "plain food before the Well Fed stew")
    t.eq(pick.drink, WATER)
    pick = RC.Read(client({ { item = STEW, count = 1 } }))
    t.eq(pick.food, STEW, "no plain food: the Well Fed food heals too")
    pick, partial = RC.Read(client({ { item = BREAD, count = 1 } }, INFO, {}))
    t.eq(pick.food, nil); t.eq(partial, true, "a tooltip not read yet")
    t.eq(RC.Read({}), nil, "no bag read")
end

local function snap(fields)
    local base = { dead = false, inCombat = false, hostile = false, lowHealth = false, hurt = 10,
                   mounted = false, onTaxi = false, buffs = {}, debuffs = {},
                   recoverItem = { bandage = LINEN, bandageName = "Linen Bandage",
                                   food = BREAD, foodName = "Tough Hunk of Bread" } }
    for k, v in pairs(fields or {}) do base[k] = v end
    return (ns.SnapshotOf(base))
end

tests["recover step: hurt after a fight, the bandage on you"] = function(t)
    local s = R._steps.recover(snap())
    t.eq(type(s) == "table" and s.itemId, LINEN)
    t.eq(s.kind, "bandage"); t.eq(s.unit, "player"); t.eq(s.look, nil, "on the key")
    t.eq(R._steps.recover(snap({ inCombat = true })), nil, "in a fight")
    t.eq(R._steps.recover(snap({ hurt = 2 })), nil, "not hurt")
    t.eq(R._steps.recover(snap({ mounted = true })), nil, "mounted")
    t.eq(R._steps.recover(snap({ recoverItem = {} })), nil, "nothing in the bags")
end

tests["recover step: Recently Bandaged, then food when quite hurt"] = function(t)
    local d = { [RC.RECENTLY_BANDAGED] = true }
    t.eq(R._steps.recover(snap({ debuffs = d })), nil, "bandaged, only a little hurt: no food yet")
    local s = R._steps.recover(snap({ debuffs = d, hurt = 10, lowHealth = true }))
    t.eq(type(s) == "table" and s.itemId, BREAD, "low health: eat")
    s = R._steps.recover(snap({ debuffs = d, hurt = R.HURT.outBig }))
    t.eq(type(s) == "table" and s.itemId, BREAD, "quite hurt: eat")
    t.eq(R._steps.recover(snap({ debuffs = d, hurt = 30, hostile = true })), nil, "no food with an enemy targeted")
    local u = snap(); u.debuffs = nil
    t.eq(R._steps.recover(u), nil, "debuffs not read: no bandage")
    t.eq(R._steps.recover(snap({ buffs = { Food = true }, hurt = 30 })), nil, "eating already")
end

tests["recover step: comes before Well Fed food, except a bandage"] = function(t)
    local order = table.concat(R.STEPS, ",")
    t.ok(order:find("recover,food", 1, true), order)
    local s = snap({ foodOn = true, buffFood = { name = "Stamina Stew", item = STEW, score = 1 } })
    t.eq(R._steps.recover(s), nil, "a bandage waits for the Well Fed meal")
    s = snap({ foodOn = true, buffFood = { name = "Stamina Stew", item = STEW, score = 1 },
               debuffs = { [RC.RECENTLY_BANDAGED] = true }, lowHealth = true })
    t.eq(R._steps.recover(s).itemId, BREAD, "food to heal still first")
end

return tests
