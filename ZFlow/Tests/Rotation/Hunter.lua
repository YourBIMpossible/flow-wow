local _, ns = ...

-- Tests for ZFlow/Classes/Hunter.lua: the pack's shape (Rotation/Pack.lua
-- and ns.PackCheck), its evidence labels, and the chooser over it with
-- made-up snapshots. Offline only; nothing here was seen in the game.

local tests = {}

local function hunter() return ns.Packs and ns.Packs.HUNTER end

local ALL = {
    "Aspect of the Hawk", "Aspect of the Monkey", "Call Pet", "Revive Pet", "Feed Pet", "Hunter's Mark",
    "Serpent Sting", "Auto Shot", "Arcane Shot", "Multi-Shot", "Raptor Strike", "Mongoose Bite", "Wing Clip",
}

-- Alive, out of a fight, the hawk up, a happy pet, every read given; `over`
-- replaces fields ("nil" takes one away); known: the spells known (all by default), each ready and
-- in range.
local function snap(over, known)
    local s = {
        dead = false, inCombat = false, hostile = false, buffs = { ["Aspect of the Hawk"] = true },
        targetDebuffs = {}, current = { ["Auto Shot"] = false },
        pet = { exists = true, dead = false, happiness = "happy" }, spells = {},
    }
    for _, name in ipairs(known or ALL) do
        s.spells[name] = { known = true, usable = true, onCooldown = false, inRange = true }
    end
    for k, v in pairs(over or {}) do
        if v == "nil" then s[k] = nil else s[k] = v end
    end
    return ns.SnapshotOf(s)
end

local function pick(over, known, fightType)
    local s = snap(over, known)
    s.fightType = fightType
    local got = ns.Choose(s, hunter())
    return got and got.spell or nil, got
end

tests["hunter pack: registered, and passes the pack check"] = function(t)
    t.ok(type(hunter()) == "table", "ns.Packs.HUNTER")
    if type(hunter()) ~= "table" then return end
    local ok, problems = ns.PackCheck(hunter())
    t.ok(ok, table.concat(problems or {}, "; "))
    for _, key in ipairs(ns.Pack.KEYS) do t.ok(hunter()[key] ~= nil, "row " .. key) end
end

tests["hunter pack: every data row is a first guess but the authored weights"] = function(t)
    local p = hunter()
    if type(p) ~= "table" then t.ok(false, "no pack") return end
    for name, row in pairs(p.spells) do t.eq(row.evidence, "first guess", name) end
    for list, rules in pairs(p.lists) do
        for i, rule in ipairs(rules) do t.eq(rule.evidence, "first guess", list .. "[" .. i .. "]") end
    end
    for _, row in ipairs(p.resources) do t.eq(row.evidence, "first guess", "resource " .. row.name) end
    t.eq(p.roles.dps, { name = "Marksmanship", evidence = "first guess" }, "D2")
    t.eq(p.roles.heal, nil)
    t.eq(p.roles.tank, nil)
    t.eq(p.proficiency.evidence, "first guess")
    t.eq(p.weights.dps.evidence, "authored")
    t.eq(type(p.weights.dps.provenance), "string", "an authored row says who and how")
    t.eq(p.weights.heal, nil)
    t.eq(p.weights.tank, nil)
    t.eq(p.talentBuilds, {}, "not authored yet")
end

tests["hunter pack: no swing row, so going into melee is never suggested to start"] = function(t)
    local p = hunter()
    if type(p) ~= "table" then t.ok(false, "no pack") return end
    t.eq(p.spells["Attack"], nil)
    t.eq(p.spells["Auto Attack"], nil)
end

tests["hunter pack: mail from level 40, plate never, bows and guns always (D3)"] = function(t)
    local p = hunter()
    if type(p) ~= "table" then t.ok(false, "no pack") return end
    t.eq(p.proficiency[4][3], 40)
    t.eq(p.proficiency[4][4], nil)
    t.eq(p.proficiency[2][2], true)
    t.eq(p.proficiency[2][3], true)
    t.eq(p.proficiency[2][18], true)
end

tests["hunter pack: names the reads it leans on, and its minimum range"] = function(t)
    local p = hunter()
    if type(p) ~= "table" then t.ok(false, "no pack") return end
    t.eq(p.options.reads, { "buffs", "targetDebuffs", "pet" })
    t.eq(p.options.minRange, true)
end

tests["hunter chooser: aspect, then mark, sting, auto shot and arcane shot"] = function(t)
    if type(hunter()) ~= "table" then t.ok(false, "no pack") return end
    t.eq(pick({ buffs = {} }), "Aspect of the Hawk", "no aspect on")
    t.eq(pick({ buffs = {} }, { "Aspect of the Monkey" }), "Aspect of the Monkey", "no hawk learned yet")
    t.eq(pick({ buffs = { ["Aspect of the Cheetah"] = true } }), nil, "any aspect counts: left alone")
    t.eq(pick({ buffs = "nil" }), nil, "buffs not read: no aspect asked for")
    local enemy = { hostile = true, inCombat = true }
    t.eq(pick(enemy), "Hunter's Mark")
    enemy.targetDebuffs = { ["Hunter's Mark"] = true }
    t.eq(pick(enemy), "Serpent Sting")
    enemy.targetDebuffs = { ["Hunter's Mark"] = true, ["Serpent Sting"] = true }
    t.eq(pick(enemy), "Auto Shot")
    enemy.current = { ["Auto Shot"] = true }
    t.eq(pick(enemy), "Arcane Shot")
    t.eq(pick(enemy, nil, "aoe"), "Multi-Shot", "several enemies: Multi-Shot before Arcane Shot")
    enemy.current = "nil"   -- (the file's sentinel: a plain nil would leave the default)
    t.eq(pick(enemy), "Arcane Shot", "auto shot not read: not asked for")
end

tests["hunter chooser: the pet, only out of a fight and only when read"] = function(t)
    if type(hunter()) ~= "table" then t.ok(false, "no pack") return end
    t.eq(pick({ pet = { exists = false } }), "Call Pet")
    t.eq(pick({ pet = { exists = true, dead = true } }), "Revive Pet")
    t.eq(pick({ pet = { exists = true, dead = false, happiness = "unhappy" } }), "Feed Pet")
    t.eq(pick({ pet = { exists = true, dead = false } }), nil, "happiness not read: no food")
    t.eq(pick({ pet = { exists = true, happiness = "unhappy" } }), nil, "alive not read: no food")
    t.eq(pick({ pet = "nil" }), nil, "the pet not read: nothing")
    t.eq(pick({ pet = { exists = false }, inCombat = true }), nil, "in a fight: no pet call")
    t.eq(pick({ pet = { exists = false }, inCombat = "nil" }), nil, "fight not known: no pet call")
end

tests["hunter chooser: melee only in melee reach; ranged first"] = function(t)
    if type(hunter()) ~= "table" then t.ok(false, "no pack") return end
    local s = snap({ hostile = true, inCombat = true, current = { ["Auto Shot"] = true, ["Raptor Strike"] = false },
        targetDebuffs = { ["Hunter's Mark"] = true, ["Serpent Sting"] = true } })
    for _, name in ipairs({ "Hunter's Mark", "Serpent Sting", "Auto Shot", "Arcane Shot", "Multi-Shot" }) do
        s.spells[name].inRange = false
    end
    local got = ns.Choose(s, hunter())
    t.eq(got and got.spell, "Raptor Strike", "the ranged shots out of range, melee in reach")
    for _, name in ipairs({ "Raptor Strike", "Mongoose Bite", "Wing Clip" }) do s.spells[name].inRange = false end
    got = ns.Choose(s, hunter())
    t.eq(got and got.spell, "Arcane Shot", "nothing in reach: the shot to get to")
    t.eq(got and got.step, "farOpener")
    t.eq(got and got.minRange, true, "too far or too close: not only move closer")
end

-- HU1 (review): the hawk is in `maintain`, while the aspect rule takes any
-- aspect as on. An aspect the player chose is never swapped for the hawk:
-- not out of a fight, not at any step of a fight, in either list.
tests["hunter chooser: the cheetah or the pack on is never swapped for the hawk (HU1)"] = function(t)
    if type(hunter()) ~= "table" then t.ok(false, "no pack") return end
    for _, aspect in ipairs({ "Aspect of the Cheetah", "Aspect of the Pack" }) do
        local buffs = { [aspect] = true }
        t.eq(pick({ buffs = buffs }), nil, aspect .. ", out of a fight: nothing asked for")
        local enemy = { buffs = buffs, hostile = true, inCombat = true }
        t.eq(pick(enemy), "Hunter's Mark", aspect .. ", in a fight: the mark, not an aspect")
        t.eq(pick(enemy, nil, "aoe"), "Hunter's Mark", aspect .. ", several enemies: the mark, not an aspect")
        enemy.targetDebuffs = { ["Hunter's Mark"] = true, ["Serpent Sting"] = true }
        enemy.current = { ["Auto Shot"] = true }
        t.eq(pick(enemy), "Arcane Shot", aspect .. ", shooting: arcane shot, not an aspect")
    end
    t.eq(pick({ buffs = { ["Aspect of the Cheetah"] = true } }, { "Aspect of the Monkey" }), nil,
        "the monkey is not asked for over the cheetah either")
end

-- HU3 (review): Raptor Strike is asked for only when the queued read was
-- given and says it is not queued, as Auto Shot is. In a fight, too close for
-- the shots (and Arcane Shot on cooldown), Mongoose Bite on cooldown, Wing
-- Clip on: Raptor Strike is the only melee rule left.
local function tooClose(current)
    local s = snap({ hostile = true, inCombat = true, current = current,
        targetDebuffs = { ["Hunter's Mark"] = true, ["Serpent Sting"] = true, ["Wing Clip"] = true } })
    for _, name in ipairs({ "Hunter's Mark", "Serpent Sting", "Auto Shot", "Arcane Shot", "Multi-Shot" }) do
        s.spells[name].inRange = false
    end
    s.spells["Arcane Shot"].onCooldown = true
    s.spells["Multi-Shot"].onCooldown = true
    s.spells["Mongoose Bite"].onCooldown = true
    local got = ns.Choose(s, hunter())
    return got and got.spell or nil
end

tests["hunter chooser: raptor strike only on a queued read that says no (HU3)"] = function(t)
    if type(hunter()) ~= "table" then t.ok(false, "no pack") return end
    t.eq(tooClose("nil"), nil, "nothing queued was read: raptor strike not asked for")
    t.eq(tooClose({ ["Auto Shot"] = true }), nil, "raptor strike left out of the read: not asked for")
    t.eq(tooClose({ ["Auto Shot"] = true, ["Raptor Strike"] = false }), "Raptor Strike", "read, not queued: asked for")
    t.eq(tooClose({ ["Auto Shot"] = true, ["Raptor Strike"] = true }), nil, "read, already queued: not again")
end

tests["hunter chooser: the engage step never asks for a swing"] = function(t)
    if type(hunter()) ~= "table" then t.ok(false, "no pack") return end
    local _, got = pick({ hostile = true, canStartAttack = true, stealthed = false, buffs = {} })
    t.ok(got == nil or got.engage ~= true, "no engage suggestion")
end

return tests
