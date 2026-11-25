-- The two client writes behind the game options (G59, lead section 226,
-- ACTS). The real client over a hand-built environment.
--   c.setGameSetting(name, text) -> true | nil, why
--       only cameraDistanceMaxZoomFactor and showTimestamps; any other
--       name is refused before the game is asked. C_CVar.SetCVar, else
--       SetCVar. why: "notAllowed", "bad", "noCall", "raised".
--   c.setCombatLogFile(on)       -> true | nil, why
--       on is true or false only; LoggingCombat(on). why: "bad",
--       "noCall", "raised".
-- Called only by UI/GameOptions.lua on the player own choice.
-- Needs game test: every call here is a first guess on 16001.
local _, ns = ...

local tests = {}

-- Out of a fight unless a test says otherwise (lead section 266 GO-1: the
-- writes are refused when the combat state is not known).
local function client(env)
    if env.InCombatLockdown == nil then env.InCombatLockdown = function() return false end end
    return ns.make.client(env)
end

local function recorder(answer)
    local calls = {}
    local fn = function(...)
        calls[#calls + 1] = { ... }
        if answer == "raise" then error("no") end
        return answer
    end
    return fn, calls
end

tests["c.setGameSetting: an allowed name goes to C_CVar.SetCVar"] = function(t)
    local fn, calls = recorder(true)
    local old, oldCalls = recorder(true)
    local c = client({ C_CVar = { SetCVar = fn }, SetCVar = old })
    if type(c.setGameSetting) ~= "function" then t.ok(false, "c.setGameSetting"); return end
    t.eq({ c.setGameSetting("cameraDistanceMaxZoomFactor", "4") }, { true })
    t.eq({ c.setGameSetting("showTimestamps", "%H:%M:%S ") }, { true })
    t.eq(calls, { { "cameraDistanceMaxZoomFactor", "4" }, { "showTimestamps", "%H:%M:%S " } })
    t.eq(#oldCalls, 0, "the old call is not asked as well")
end

tests["c.setGameSetting: no C_CVar, the old SetCVar"] = function(t)
    local fn, calls = recorder(nil)
    local c = client({ SetCVar = fn })
    if type(c.setGameSetting) ~= "function" then t.ok(false, "c.setGameSetting"); return end
    t.eq({ c.setGameSetting("showTimestamps", "none") }, { true }, "an old call that answers nothing ran")
    t.eq(calls, { { "showTimestamps", "none" } })
end

tests["c.setGameSetting: any other name is refused and the game is not asked"] = function(t)
    local fn, calls = recorder(true)
    local c = client({ C_CVar = { SetCVar = fn }, SetCVar = fn })
    if type(c.setGameSetting) ~= "function" then t.ok(false, "c.setGameSetting"); return end
    for _, name in ipairs({ "gxApi", "Sound_EnableAllSound", "", "CAMERADISTANCEMAXZOOMFACTOR", "AUTOLOOTDEFAULT" }) do
        t.eq({ c.setGameSetting(name, "1") }, { nil, "notAllowed" }, name)
    end
    t.eq({ c.setGameSetting(nil, "1") }, { nil, "notAllowed" }, "no name")
    t.eq(#calls, 0, "nothing asked")
end

tests["c.setGameSetting: only text is written"] = function(t)
    local fn, calls = recorder(true)
    local c = client({ C_CVar = { SetCVar = fn } })
    if type(c.setGameSetting) ~= "function" then t.ok(false, "c.setGameSetting"); return end
    t.eq({ c.setGameSetting("showTimestamps", nil) }, { nil, "bad" })
    t.eq({ c.setGameSetting("cameraDistanceMaxZoomFactor", 4) }, { nil, "bad" })
    t.eq({ c.setGameSetting("showTimestamps", false) }, { nil, "bad" })
    t.eq(#calls, 0, "nothing asked")
end

tests["c.setGameSetting: no call, a call that raises, a call that says no"] = function(t)
    local probe = client({})
    if type(probe.setGameSetting) ~= "function" then t.ok(false, "c.setGameSetting"); return end
    t.eq({ probe.setGameSetting("showTimestamps", "none") }, { nil, "noCall" })
    local raise = recorder("raise")
    t.eq({ client({ C_CVar = { SetCVar = raise } }).setGameSetting("showTimestamps", "none") }, { nil, "raised" })
    local no = recorder(false)
    t.eq({ client({ C_CVar = { SetCVar = no } }).setGameSetting("showTimestamps", "none") }, { nil, "bad" })
end

tests["c.setCombatLogFile: true or false to LoggingCombat"] = function(t)
    local fn, calls = recorder(true)
    local c = client({ LoggingCombat = fn })
    if type(c.setCombatLogFile) ~= "function" then t.ok(false, "c.setCombatLogFile"); return end
    t.eq({ c.setCombatLogFile(true) }, { true })
    t.eq({ c.setCombatLogFile(false) }, { true })
    t.eq(calls, { { true }, { false } })
end

tests["c.setCombatLogFile: anything but true or false is refused and not asked"] = function(t)
    local fn, calls = recorder(true)
    local c = client({ LoggingCombat = fn })
    if type(c.setCombatLogFile) ~= "function" then t.ok(false, "c.setCombatLogFile"); return end
    t.eq({ c.setCombatLogFile(nil) }, { nil, "bad" }, "nil would be a read")
    t.eq({ c.setCombatLogFile(1) }, { nil, "bad" })
    t.eq({ c.setCombatLogFile("1") }, { nil, "bad" })
    t.eq(#calls, 0, "nothing asked")
    t.eq({ client({}).setCombatLogFile(true) }, { nil, "noCall" })
    local raise = recorder("raise")
    t.eq({ client({ LoggingCombat = raise }).setCombatLogFile(true) }, { nil, "raised" })
end

tests["diag: the game option write names are recorded at login"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({ "C_CVar.SetCVar", "SetCVar" }) do
        t.ok(listed[name] == true, name)
    end
end

tests["the module asks the two writes by these names"] = function(t)
    local spec
    ns.GameOptions.Declare({ Module = function(_, m) spec = m end })
    t.ok(type(spec) == "table", "declared")
    local c = ns.make.fakeClient({ env = {} })
    t.ok(type(c.setGameSetting) == "function" and type(c.setCombatLogFile) == "function",
        "the fake has the same two names")
end

-- GO-1 (lead section 266): no write in a fight. A combat state the game
-- does not give counts as a fight.
tests["c.setGameSetting and c.setCombatLogFile: refused in a fight, the game is not asked"] = function(t)
    local fn, calls = recorder(true)
    local log, logCalls = recorder(true)
    local fight = true
    local c = ns.make.client({ C_CVar = { SetCVar = fn }, LoggingCombat = log,
        InCombatLockdown = function() return fight end })
    if type(c.setGameSetting) ~= "function" then t.ok(false, "c.setGameSetting"); return end
    t.eq({ c.setGameSetting("showTimestamps", "none") }, { nil, "combat" })
    t.eq({ c.setCombatLogFile(true) }, { nil, "combat" })
    t.eq(#calls + #logCalls, 0, "nothing asked in the fight")
    fight = false
    t.eq({ c.setGameSetting("showTimestamps", "none") }, { true })
    t.eq({ c.setCombatLogFile(true) }, { true })
    local unknown = ns.make.client({ C_CVar = { SetCVar = fn }, LoggingCombat = log })
    t.eq({ unknown.setGameSetting("showTimestamps", "none") }, { nil, "combat" }, "not known: refused")
    t.eq({ unknown.setCombatLogFile(true) }, { nil, "combat" }, "not known: refused")
end

tests["c.setGameSetting: the F-14 suggested settings go to C_CVar.SetCVar, else SetCVar"] = function(t)
    local names = { "autoLootDefault", "nameplateShowEnemies", "instantQuestText", "autoSelfCast", "statusText" }
    local fn, calls = recorder(true)
    local c = client({ C_CVar = { SetCVar = fn } })
    if type(c.setGameSetting) ~= "function" then t.ok(false, "c.setGameSetting"); return end
    for _, name in ipairs(names) do t.eq({ c.setGameSetting(name, "1") }, { true }, name) end
    t.eq(#calls, #names, "each asked once")
    local old, oldCalls = recorder(nil)
    local c2 = client({ SetCVar = old })
    t.eq({ c2.setGameSetting("autoLootDefault", "1") }, { true }, "the older call")
    t.eq(oldCalls, { { "autoLootDefault", "1" } })
    local c3 = client({ InCombatLockdown = function() return true end, C_CVar = { SetCVar = fn } })
    t.eq({ c3.setGameSetting("autoLootDefault", "1") }, { nil, "combat" }, "not in a fight")
end

return tests
