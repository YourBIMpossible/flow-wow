-- The client reads the game options need (G59, lead section 226). The real
-- client over a hand-built environment; ClientFake's own versions after.
--   c.gameSetting(name)       -> string | nil   (C_CVar.GetCVar, else GetCVar)
--   c.combatLogFile()  -> true | false | nil   (LoggingCombat with no value)
-- Unknown stays unknown: nil is never "off" or "empty".
-- Needs game test: every call here is a first guess on 16001.
local _, ns = ...

local tests = {}

local function client(env) return ns.make.client(env) end

tests["c.gameSetting: the C_CVar answer, else the old call, as a string, or not known"] = function(t)
    local asked
    local c = client({ C_CVar = { GetCVar = function(n) asked = n; return "2.6" end } })
    t.eq(c.gameSetting and c.gameSetting("cameraDistanceMaxZoomFactor"), "2.6")
    t.eq(asked, "cameraDistanceMaxZoomFactor")
    t.eq(client({ GetCVar = function() return "none" end }).gameSetting("showTimestamps"), "none")
    t.eq(client({ C_CVar = { GetCVar = function() return nil end }, GetCVar = function() return "1" end }).gameSetting("x"),
        "1", "no C_CVar answer: the old call")
    t.eq(client({ GetCVar = function() return 4 end }).gameSetting("x"), "4", "a number given: its text")
    t.eq(client({}).gameSetting("x"), nil, "neither call")
    t.eq(client({ GetCVar = function() error("no") end }).gameSetting("x"), nil, "raised")
    t.eq(client({ GetCVar = function() return {} end }).gameSetting("x"), nil, "not a value")
    t.eq(client({ GetCVar = function() return "1" end }).gameSetting(nil), nil, "no name: not asked")
end

tests["c.combatLogFile: on, off, or not known"] = function(t)
    local args
    local c = client({ LoggingCombat = function(...) args = select("#", ...); return true end })
    t.eq(c.combatLogFile and c.combatLogFile(), true)
    t.eq(args, 0, "asked with no value: a read, nothing changed")
    t.eq(client({ LoggingCombat = function() return false end }).combatLogFile(), false)
    t.eq(client({ LoggingCombat = function() return nil end }).combatLogFile(), false,
        "the game answers nil for off")
    t.eq(client({ LoggingCombat = function() return 1 end }).combatLogFile(), true)
    t.eq(client({}).combatLogFile(), nil, "no such call")
    t.eq(client({ LoggingCombat = function() error("no") end }).combatLogFile(), nil, "raised")
end

tests["diag: the game option read names are recorded at login"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({ "C_CVar.GetCVar", "GetCVar", "LoggingCombat" }) do
        t.ok(listed[name] == true, name)
    end
end

tests["fake client: a seeded game setting is read back and is not a write"] = function(t)
    local c = ns.make.fakeClient()
    if type(c.putGameSetting) ~= "function" then t.ok(false, "c.putGameSetting"); return end
    t.eq(c.gameSetting("showTimestamps"), nil, "not seeded: not known")
    c.putGameSetting("showTimestamps", "none")
    t.eq(c.gameSetting("showTimestamps"), "none")
    t.eq(#c.gameSettingWrites, 0)
end

tests["fake client: the combat log file state is seeded, not known until then"] = function(t)
    local c = ns.make.fakeClient()
    if type(c.putCombatLogFile) ~= "function" then t.ok(false, "c.putCombatLogFile"); return end
    t.eq(c.combatLogFile(), nil)
    c.putCombatLogFile(false)
    t.eq(c.combatLogFile(), false)
    t.eq(#c.logFileWrites, 0)
end

tests["fake client: a write records, a limit keeps the value, a failure says why"] = function(t)
    local c = ns.make.fakeClient()
    if type(c.setGameSetting) ~= "function" then t.ok(false, "c.setGameSetting"); return end
    c.putGameSetting("cameraDistanceMaxZoomFactor", "1.9")
    t.eq({ c.setGameSetting("cameraDistanceMaxZoomFactor", "2.6") }, { true })
    t.eq(c.gameSetting("cameraDistanceMaxZoomFactor"), "2.6")
    c.gameSettingLimit("cameraDistanceMaxZoomFactor", 3.4)
    t.eq({ c.setGameSetting("cameraDistanceMaxZoomFactor", "4") }, { true }, "the game takes the call")
    t.eq(c.gameSetting("cameraDistanceMaxZoomFactor"), "2.6", "and keeps its value")
    c.setGameSettingFails("raised")
    t.eq({ c.setGameSetting("cameraDistanceMaxZoomFactor", "3.4") }, { nil, "raised" })
    t.eq(#c.gameSettingWrites, 3, "every try is recorded")
    t.eq({ c.setCombatLogFile(true) }, { true })
    t.eq(c.combatLogFile(), true)
    t.eq(c.logFileWrites, { true })
end

return tests
