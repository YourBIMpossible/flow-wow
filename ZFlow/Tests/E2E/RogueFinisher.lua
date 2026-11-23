local _, ns = ...
-- ROGUE-2 (lead section 236, HIGH): a rogue with enough combo points is told
-- the finisher. End to end on the whole add-on loaded on a fake client: the
-- combo read (client.combo) or, when the client gives no plain number, the
-- add-on's own count of your builder casts (Rotation/Combo.lua) -> the
-- snapshot's finisherReady -> the chooser -> the icon. Offline: the reads
-- are the fake client's, not the game's. The spell ids are made up.
local tests = {}

local D = ns.RotationDriver
local IDS = {
    ["Stealth"] = 92001, ["Ambush"] = 92002, ["Garrote"] = 92003, ["Cheap Shot"] = 92004,
    ["Attack"] = 92005, ["Sinister Strike"] = 92006, ["Eviscerate"] = 92007,
    ["Slice and Dice"] = 92008, ["Kick"] = 92009,
}
local AIMED = { "Ambush", "Garrote", "Cheap Shot", "Attack", "Sinister Strike", "Eviscerate", "Kick" }
local ENEMY = { exists = true, hostile = true, dead = false }

local function need() return ns.Packs.ROGUE.options.combo.need end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setClass("ROGUE"); c.setFaction("Alliance"); c.setLevel(20); c.setDead(false)
    for name, id in pairs(IDS) do
        c.setSpellId(name, id)
        c.setSpell(id, { known = true, usable = true })
        c.setSpellCooldown(id, false)
        c.setSpellTexture(id, "tex:" .. name)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    local icon
    for _, h in ipairs(c.icons) do
        if tostring(h.spec.name):find("RotationIcon", 1, true) then icon = h end
    end
    addon.settings:set(D.SETTING, true)
    -- In the fight, out of stealth, swinging, everything in range, no buffs.
    c.setPlayerBuffs({}); c.setTarget(ENEMY); c.setStealthed(false); c.setCombat(true)
    c.setTargetDebuffs({}); c.setCurrentSpell(IDS["Attack"], true)
    for _, name in ipairs(AIMED) do c.setInRange(IDS[name], true) end
    c.advance(1, 5)
    return c, addon, icon
end

local function cast(c, name, unit)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", unit or "player", "Cast-3-0-0-0-0-0", IDS[name])
    c.advance(1, 5)
end

tests["rogue finisher: combo points read at the pack's count: the finisher is shown"] = function(t)
    local c, _, icon = start()
    t.eq(icon.texture, "tex:Sinister Strike", "no points: build")
    c.setCombo(need(), 5); c.advance(1, 5)
    t.eq(icon.texture, "tex:Slice and Dice", "enough points, Slice and Dice off: Slice and Dice")
    c.setPlayerBuffs({ ["Slice and Dice"] = 20 }); c.advance(1, 5)
    t.eq(icon.texture, "tex:Eviscerate", "enough points, Slice and Dice up: Eviscerate")
end

tests["rogue finisher: combo points read under the count: no finisher"] = function(t)
    local c, _, icon = start()
    c.setCombo(need() - 1, 5); c.advance(1, 5)
    t.eq(icon.texture, "tex:Sinister Strike")
end

tests["rogue finisher: a plain read wins over the add-on's own count"] = function(t)
    local c, _, icon = start()
    for _ = 1, need() do cast(c, "Sinister Strike") end
    c.setCombo(1, 5); c.advance(1, 5)
    t.eq(icon.texture, "tex:Sinister Strike", "the client said 1: not due, whatever was counted")
end

tests["rogue finisher: points not read: your own builder casts are counted"] = function(t)
    local c, _, icon = start()
    for i = 1, need() - 1 do
        cast(c, "Sinister Strike")
        t.eq(icon.texture, "tex:Sinister Strike", "after " .. i .. " builder(s): not due yet")
    end
    cast(c, "Sinister Strike")
    t.eq(icon.texture, "tex:Slice and Dice", "the count reached: the finisher")
end

tests["rogue finisher: a finisher cast starts the count again"] = function(t)
    local c, _, icon = start()
    for _ = 1, need() do cast(c, "Sinister Strike") end
    t.eq(icon.texture, "tex:Slice and Dice")
    cast(c, "Slice and Dice")
    t.eq(icon.texture, "tex:Sinister Strike", "spent: build again")
end

tests["rogue finisher: a new target starts the count again"] = function(t)
    local c, _, icon = start()
    for _ = 1, need() do cast(c, "Sinister Strike") end
    t.eq(icon.texture, "tex:Slice and Dice")
    c.fire("PLAYER_TARGET_CHANGED"); c.advance(1, 5)
    t.eq(icon.texture, "tex:Sinister Strike", "points stay on the old target")
end

tests["rogue finisher: the fight's end starts the count again"] = function(t)
    local c, _, icon = start()
    for _ = 1, need() do cast(c, "Sinister Strike") end
    t.eq(icon.texture, "tex:Slice and Dice")
    c.fire("PLAYER_REGEN_ENABLED"); c.advance(1, 5)
    t.eq(icon.texture, "tex:Sinister Strike")
end

tests["rogue finisher: someone else's casts and other spells are not counted"] = function(t)
    local c, _, icon = start()
    for _ = 1, need() do cast(c, "Sinister Strike", "party1") end
    for _ = 1, need() do cast(c, "Kick") end
    t.eq(icon.texture, "tex:Sinister Strike")
end

-- Pure: the count and the say-so.
tests["combo: builders add, finishers and nothing else reset, never past the most"] = function(t)
    local CB = ns.Combo
    local rules = { builders = { ["Sinister Strike"] = 1, ["Cheap Shot"] = 2 }, finishers = { Eviscerate = true }, max = 5 }
    t.eq(CB.Add(0, "Sinister Strike", rules), 1)
    t.eq(CB.Add(1, "Cheap Shot", rules), 3)
    t.eq(CB.Add(4, "Cheap Shot", rules), 5, "held at the most")
    t.eq(CB.Add(4, "Eviscerate", rules), 0)
    t.eq(CB.Add(2, "Kick", rules), 2, "not a builder or a finisher")
    t.eq(CB.Add(2, nil, rules), 2, "no name")
    t.eq(CB.Add(2, "Sinister Strike", nil), 2, "no rules")
end

tests["combo: ready from the read first, else the count, else not known"] = function(t)
    local CB = ns.Combo
    t.eq({ CB.Ready(5, 0, 5) }, { true, "read" })
    t.eq({ CB.Ready(4, 5, 5) }, { false, "read" })
    t.eq({ CB.Ready(nil, 5, 5) }, { true, "counted" })
    t.eq({ CB.Ready(nil, 4, 5) }, { false, "counted" })
    t.eq({ CB.Ready(nil, nil, 5) }, { nil, nil })
    t.eq({ CB.Ready(5, 5, nil) }, { nil, nil }, "no count asked for")
    t.eq({ CB.Ready(2.5, 5, 5) }, { true, "counted" }, "a read that is not a whole number is not a read")
end

return tests
