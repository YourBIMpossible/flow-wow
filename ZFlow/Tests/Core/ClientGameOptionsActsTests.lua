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

local function client(env) return ns.make.client(env) end

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
    for _, name in ipairs({ "autoLootDefault", "Sound_EnableAllSound", "", "CAMERADISTANCEMAXZOOMFACTOR" }) do
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

return tests
