local _, ns = ...
-- N8 (lead section 238): healthstone, then healing potion, in a fight.
-- Made-up items; not tested in game.
local tests = {}

local HI = ns.HealItems
local D = ns.RotationDriver
local R = ns.Rotation

local STONE, STONE2, POT, POT2, BREAD = 9101, 9102, 9103, 9104, 9105
local INFO = {
    [STONE] = { name = "Minor Healthstone", classID = 0, subclassID = 0, level = 10, minLevel = 0 },
    [STONE2] = { name = "Lesser Healthstone", classID = 0, subclassID = 0, level = 22, minLevel = 12 },
    [POT] = { name = "Minor Healing Potion", classID = 0, subclassID = 1, level = 5, minLevel = 1 },
    [POT2] = { name = "Lesser Healing Potion", classID = 0, subclassID = 1, level = 13, minLevel = 3 },
    [BREAD] = { name = "Tough Hunk of Bread", classID = 0, subclassID = 5, level = 5, minLevel = 1 },
}

local function client(stacks, info)
    local c = ns.make.fakeClient()
    c.setBagItems(stacks)
    c.setItemInfo(info or INFO)
    c.setCombat(false)
    return c
end

tests["heal items: the kinds, by the Flow name and class rules"] = function(t)
    t.eq(HI.Kind(INFO[STONE]), "healthstone")
    t.eq(HI.Kind(INFO[POT]), "potion")
    t.eq(HI.Kind({ name = "Healing Draught", classID = 0, subclassID = 1 }), "potion", "class rule")
    t.eq(HI.Kind({ name = "Healing Draught", classID = 0, subclassID = 5 }), nil, "not a potion class")
    t.eq(HI.Kind(INFO[BREAD]), nil, "food")
    t.eq(HI.Kind({}), nil, "no name")
    t.eq(HI.Kind(nil), nil)
end

tests["heal items: the best of each by item level, then required level"] = function(t)
    local pick, partial = HI.Read(client({ { item = STONE, count = 1 }, { item = POT, count = 2 },
        { item = STONE2, count = 1 }, { item = POT2, count = 1 }, { item = BREAD, count = 4 } }))
    t.eq(partial, false)
    t.eq(pick.stone, STONE2); t.eq(pick.stoneName, "Lesser Healthstone")
    t.eq(pick.potion, POT2); t.eq(pick.potionName, "Lesser Healing Potion")
    t.ok(HI.Rank({ level = 10, minLevel = 5 }) > HI.Rank({ level = 10, minLevel = 1 }), "required level breaks a tie")
end

tests["heal items: none in the bags, an empty stack, an item not read"] = function(t)
    local pick, partial = HI.Read(client({ { item = BREAD, count = 1 } }))
    t.eq(next(pick), nil, "neither: an empty pick"); t.eq(partial, false)
    pick = HI.Read(client({ { item = STONE, count = 0 } }))
    t.eq(next(pick), nil, "an empty stack is not there")
    pick, partial = HI.Read(client({ { item = STONE, count = 1 }, { item = POT, count = 1 } }, { [POT] = INFO[POT] }))
    t.eq(pick.potion, POT, "the one read"); t.eq(pick.stone, nil)
    t.eq(partial, true, "the stone not read yet")
    local c = client({ { item = STONE, count = 1 } })
    c.bagItems = function() error("bags failed") end
    t.eq(HI.Read(c), nil, "the bags not read: nil")
end

-- The choice ------------------------------------------------------------

local function item(fields)
    local h = { stone = STONE, stoneName = "Minor Healthstone", stoneWait = 0,
                potion = POT, potionName = "Minor Healing Potion", potionWait = 0 }
    for k, v in pairs(fields or {}) do h[k] = v end
    return h
end

local function snap(fields)
    local base = { dead = false, inCombat = true, lowHealth = true, healItem = item() }
    for k, v in pairs(fields or {}) do base[k] = v end
    return (ns.SnapshotOf(base))
end

tests["heal items: the healthstone first, then the potion"] = function(t)
    local s = R._healItem(snap())
    t.eq(s.itemId, STONE); t.eq(s.kind, "emergency"); t.eq(s.item, "Minor Healthstone")
    s = R._healItem(snap({ healItem = item({ stoneWait = 90 }) }))
    t.eq(s.itemId, POT, "the stone not ready: the potion")
    t.eq(R._healItem(snap({ healItem = item({ stoneWait = 90, potionWait = false }) })), nil,
        "a cooldown not read is not ready")
    t.eq(R._healItem(snap({ healItem = { potion = POT, potionWait = 0 } })).itemId, POT, "no stone")
end

tests["heal items: only in a fight, only with the warning on"] = function(t)
    t.eq(R._healItem(snap({ inCombat = false })), nil, "out of a fight")
    t.eq(R._healItem(snap({ lowHealth = false })), nil, "no warning")
    local s = snap(); s.lowHealth = nil
    t.eq(R._healItem(s), nil, "the warning not read")
    s = snap(); s.inCombat = nil
    t.eq(R._healItem(s), nil, "the fight not known")
    s = snap(); s.healItem = nil
    t.eq(R._healItem(s), nil, "not read")
end

tests["heal items: the words say Alt only for the item on Alt"] = function(t)
    local s = R._healItem(snap({ healItem = item({ alt = STONE }) }))
    t.eq(s.reason, "Low health: use your Minor Healthstone now (press Alt + your rotation key)")
    s = R._healItem(snap({ healItem = item({ alt = POT }) }))
    t.eq(s.reason, "Low health: use your Minor Healthstone now (press it on your bar or in your bag: the key is locked in a fight)")
end

tests["heal items: the heal step offers the item before any heal spell"] = function(t)
    local pick, trace = ns.Choose(snap(), { heals = { self = { "Holy Light" } } }, nil, nil)
    t.eq(pick and pick.itemId, STONE, "the stone")
    t.eq(pick and pick.step, "heal")
    t.eq(trace[#trace].item, "Minor Healthstone", "the trace names the item")
end

-- The driver read -------------------------------------------------------

local function read(c, heal) return D.Read(c, {}, {}, nil, { heal = heal })("healItem") end

tests["heal items: the driver keeps a whole read, not a partial one"] = function(t)
    local c = client({ { item = STONE, count = 1 }, { item = POT, count = 1 } }, { [POT] = INFO[POT] })
    c.setItemCooldown(POT, 0)
    local heal = { on = true }
    local got = read(c, heal)
    t.eq(got.potion, POT); t.eq(got.potionWait, 0); t.eq(got.stone, nil)
    t.eq(heal.kept, false, "a stone not read: not kept")
    c.setItemInfo(INFO); c.setItemCooldown(STONE, 30)
    got = read(c, heal)
    t.eq(got.stone, STONE); t.eq(got.stoneWait, 30)
    t.eq(heal.kept, true, "all read: kept")
    c.setBagItems({})
    t.eq(read(c, heal).stone, STONE, "kept until the module clears it")
    c.setItemCooldown(STONE, 0)
    t.eq(read(c, heal).stoneWait, 0, "the cooldown is read each time")
end

tests["heal items: the setting off reads nothing"] = function(t)
    local c = client({ { item = STONE, count = 1 } })
    local asked = 0
    local bags = c.bagItems
    c.bagItems = function() asked = asked + 1; return bags() end
    t.eq(read(c, { on = false }), nil)
    t.eq(asked, 0, "the bags were not read")
end

tests["heal items: Alt is set out of a fight only, with the key frame on"] = function(t)
    local c = client({ { item = STONE, count = 1 }, { item = POT, count = 1 } })
    local heal = { on = true, keys = false }
    t.eq(read(c, heal).alt, nil, "the key frame off: no Alt")
    heal.keys = true
    t.eq(read(c, heal).alt, STONE, "out of a fight: the stone")
    c.setCombat(true)
    heal.kept, heal.value = true, { potion = POT, potionName = "Minor Healing Potion" }
    t.eq(read(c, heal).alt, STONE, "in a fight: what is on the key stays")
    c.setCombat(false)
    t.eq(read(c, heal).alt, POT, "out again: the new pick")
end

tests["heal items: the low-health read is a boolean or nil"] = function(t)
    local c = client({})
    local r = D.Read(c, {}, {}, nil, {})
    t.eq(r("lowHealth"), nil, "not set: not known")
    c.setLowHealth(true); t.eq(r("lowHealth"), true)
    c.setLowHealth(false); t.eq(r("lowHealth"), false)
    c.lowHealth = function() error("read failed") end
    t.eq(r("lowHealth"), nil, "a failed read: not known")
    c.lowHealth = function() return 1 end
    t.eq(r("lowHealth"), nil, "not a boolean: not known")
end

return tests
