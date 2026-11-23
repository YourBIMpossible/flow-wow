-- N55 (the boss loot panel): the three reads it adds to the real client,
-- over a hand-built environment, then ClientFake's twins. Read only: no
-- unit is targeted, nothing is looted or rolled. Every answer the client
-- does not give, or gives as a secret, is nil (not known), never false, 0
-- or "". Made-up names. Not seen in game.
--   c.bossUnit()      -> { exists, guid, name } | nil     the unit "boss1"
--   c.instance()      -> { inside, kind } | nil
--   c.lootLine(line)  -> item link, count | nil           anyone's loot line; never the looter
local _, ns = ...

local tests = {}

local BOSS = "Gravelmaw the Unfed"                    -- made up
local GUID = "Creature-0-0-0-0-7001-00000A"
local LOOTER = "Bramblewick"                          -- made up
local LINK = "|cff0070dd|Hitem:4001:0:0:0:0:0:0:0|h[Thornhelm]|h|r"

local function bossEnv(extra)
    local env = { asked = {} }
    env.UnitExists = function(unit) env.asked[#env.asked + 1] = unit return unit == "boss1" end
    env.UnitGUID = function(unit) env.asked[#env.asked + 1] = unit return GUID end
    env.UnitName = function(unit) env.asked[#env.asked + 1] = unit return BOSS, nil end
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

-- Fails before: Core/Client.lua has no c.bossUnit.
tests["c.bossUnit: the boss unit as the client gave it, and only that unit is asked about"] = function(t)
    local env = bossEnv()
    local c = ns.make.client(env)
    t.ok(type(c.bossUnit) == "function", "the read is there")
    if type(c.bossUnit) ~= "function" then return end
    t.eq(c.bossUnit(), { exists = true, guid = GUID, name = BOSS })
    for _, unit in ipairs(env.asked) do t.eq(unit, "boss1", "only boss1 is asked about") end
end

tests["c.bossUnit: none is exists = false; no answer, a raise, a secret or no call is nil"] = function(t)
    local function unit(extra)
        local c = ns.make.client(bossEnv(extra))
        if type(c.bossUnit) ~= "function" then return "no read" end
        return c.bossUnit()
    end
    t.eq(unit({ UnitExists = function() return false end }), { exists = false }, "no boss unit")
    t.eq(unit({ UnitExists = function() return nil end }), nil, "no answer")
    t.eq(unit({ UnitExists = function() error("x") end }), nil, "raised")
    t.eq(unit({ UnitExists = false }), nil, "no such call")
    t.eq(unit({ issecretvalue = function() return true end }), nil, "a secret answer")
    t.eq(unit({ UnitGUID = function() error("x") end, UnitName = function() return nil end }), { exists = true },
        "the id and the name not read: left out, never made up")
end

-- Fails before: Core/Client.lua has no c.instance.
tests["c.instance: inside or not, with the kind the client names; not known is nil"] = function(t)
    local function inst(env)
        local c = ns.make.client(env)
        if type(c.instance) ~= "function" then return "no read" end
        return c.instance()
    end
    t.eq(inst({ IsInInstance = function() return true, "party" end }), { inside = true, kind = "party" })
    t.eq(inst({ IsInInstance = function() return false, "none" end }), { inside = false, kind = "none" })
    t.eq(inst({ GetInstanceInfo = function() return "Made-up Deeps", "party", 1 end }), { inside = true, kind = "party" },
        "the second read when the first is absent")
    t.eq(inst({ GetInstanceInfo = function() return "Made-up Vale", "none", 0 end }), { inside = false, kind = "none" })
    t.eq(inst({}), nil, "neither call")
    t.eq(inst({ IsInInstance = function() error("x") end }), nil, "raised")
    t.eq(inst({ IsInInstance = function() return 1 end }), nil, "not a yes or no")
end

local TEXTS = {
    LOOT_ITEM = "%s receives loot: %s.",
    LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d.",
    LOOT_ITEM_SELF = "You receive loot: %s.",
    LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.",
}

-- Fails before: Core/Client.lua has no c.lootLine.
tests["c.lootLine: the item of anyone's loot line, by the client's own texts; the looter is never given"] = function(t)
    local c = ns.make.client(TEXTS)
    t.ok(type(c.lootLine) == "function", "the read is there")
    if type(c.lootLine) ~= "function" then return end
    t.eq({ c.lootLine(LOOTER .. " receives loot: " .. LINK .. ".") }, { LINK, 1 }, "another player's")
    t.eq({ c.lootLine(LOOTER .. " receives loot: " .. LINK .. "x3.") }, { LINK, 3 }, "another player's, several")
    t.eq({ c.lootLine("You receive loot: " .. LINK .. ".") }, { LINK, 1 }, "your own")
    t.eq({ c.lootLine("You receive loot: " .. LINK .. "x2.") }, { LINK, 2 }, "your own, several")
    for _, line in ipairs({ LOOTER .. " receives loot: " .. LINK .. ".", "You receive loot: " .. LINK .. "." }) do
        for _, v in ipairs({ c.lootLine(line) }) do
            t.ok(not tostring(v):find(LOOTER, 1, true), "no looter in what is given")
        end
    end
end

tests["c.lootLine: a line that is not loot, no item in it, or a client without the texts: nil"] = function(t)
    local c = ns.make.client(TEXTS)
    if type(c.lootLine) ~= "function" then t.ok(false, "no read") return end
    t.eq(c.lootLine(LOOTER .. " creates: " .. LINK .. "."), nil, "made, not looted")
    t.eq(c.lootLine(LOOTER .. " receives loot: a thing."), nil, "no item link")
    t.eq(c.lootLine(""), nil)
    t.eq(c.lootLine(nil), nil)
    local bare = ns.make.client({})
    t.eq(bare.lootLine("You receive loot: " .. LINK .. "."), nil, "no texts on this client: not read, never guessed")
end

-- Fails before: Core/Diag.lua's NAMES lacks them.
tests["the names these reads ask are in the capture's name list"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({ "IsInInstance", "GetInstanceInfo", "LOOT_ITEM", "LOOT_ITEM_MULTIPLE",
        "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "UnitExists", "UnitGUID", "UnitName", "UnitClassification" }) do
        t.ok(listed[name], name)
    end
end

-- The fake's twins -----------------------------------------------------------

-- Fails before: Core/ClientFake.lua has none of them.
tests["fake: bossUnit, instance and lootLine are not known until set, then as set"] = function(t)
    local c = ns.make.fakeClient()
    t.ok(type(c.bossUnit) == "function" and type(c.instance) == "function" and type(c.lootLine) == "function",
        "the three reads")
    if type(c.bossUnit) ~= "function" or type(c.instance) ~= "function" or type(c.lootLine) ~= "function" then return end
    t.eq(c.bossUnit(), nil)
    t.eq(c.instance(), nil)
    t.eq(c.lootLine("anything"), nil)
    c.setBossUnit({ exists = true, guid = GUID, name = BOSS })
    t.eq(c.bossUnit(), { exists = true, guid = GUID, name = BOSS })
    c.setBossUnit({ exists = false, guid = GUID })
    t.eq(c.bossUnit(), { exists = false }, "none: nothing more is said")
    c.setInstance({ inside = true, kind = "party" })
    t.eq(c.instance(), { inside = true, kind = "party" })
    c.setLootLine(function(line) if line == "a" then return LINK, 2 end end)
    t.eq({ c.lootLine("a") }, { LINK, 2 })
    t.eq(c.lootLine("b"), nil)
end

-- Fails before: Core/ClientFake.lua has no c.setReadFails.
tests["fake: setReadFails makes one read raise until taken back"] = function(t)
    local c = ns.make.fakeClient()
    t.ok(type(c.setReadFails) == "function", "the control is there")
    if type(c.setReadFails) ~= "function" then return end
    c.setLevel(12)
    c.setReadFails("level", true)
    t.eq((pcall(c.level)), false, "raises while on")
    t.eq(c.class(), nil, "another read is untouched")
    c.setReadFails("level", false)
    t.eq(c.level(), 12, "answers again")
end

return tests
