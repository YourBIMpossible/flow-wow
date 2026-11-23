local _, ns = ...
-- G59 (lead sections 226 and 243): camera distance, chat timestamps and
-- the combat log file, each a setting on the whole add-on loaded on a fake
-- client. Off until the player chooses; turned on by the player (the
-- setting word of the slash command, the same Set the settings page uses),
-- the value the game had is kept; turned off, that value is put back.
-- Nothing changes at login or on any tick. Per lead section 236: a reload
-- with a setting on, a reset of all settings, a write the game refuses, a
-- read the game does not answer, and turning on twice before off.
-- Offline: the fake client, not the game. Not tested in game.
local tests = {}

local CAMERA, STAMPS = "cameraDistanceMaxZoomFactor", "showTimestamps"

-- opts: account (saved), camera, stamps, logging, limit (camera most)
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient({ env = {} })
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    c.setCombat(false)
    if type(c.putGameSetting) == "function" then
        if opts.camera ~= false then c.putGameSetting(CAMERA, opts.camera or "1.9") end
        if opts.stamps ~= false then c.putGameSetting(STAMPS, opts.stamps or "none") end
        if opts.limit then c.gameSettingLimit(CAMERA, opts.limit) end
    end
    if type(c.putCombatLogFile) == "function" and opts.logging ~= nil then c.putCombatLogFile(opts.logging) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function ready(t, c)
    local ok = type(ns.GameOptions) == "table" and type(c.putGameSetting) == "function"
        and type(c.gameSettingWrites) == "table" and type(c.logFileWrites) == "table"
    t.ok(ok, "the game options module and the fake game settings are there")
    return ok
end

-- The player types the setting word: the real slash command.
local function say(c, text)
    local from = #c.printed + 1
    c.slashes[ns.id.slash](text)
    local out = {}
    for i = from, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, "\n")
end

local function writes(c) return #c.gameSettingWrites + #c.logFileWrites end

tests["g59 e2e: all three are off at first, and nothing is written at login or on the tick"] = function(t)
    local c, addon = boot()
    if not ready(t, c) then return end
    for _, key in ipairs({ "game.cameraZoom", "game.chatTimes", "game.combatLogFile" }) do
        t.eq(addon.settings:get(key), false, key .. " is off until chosen")
    end
    c.advance(30, 60)
    t.eq(writes(c), 0, "nothing written unasked")
end

tests["g59 e2e: camera on pulls back and keeps the old distance; off puts it back"] = function(t)
    local c, addon = boot({ camera = "1.9" })
    if not ready(t, c) then return end
    local text = say(c, "setting game.cameraZoom on")
    t.eq(c.gameSetting(CAMERA), "4", "pulled back to the farthest tried")
    t.ok(text:find("1.9", 1, true) ~= nil, "the line names the old distance: " .. text)
    local body = text:gsub(ns.id.title:gsub("%p", "%%%0") .. ": ", "")
    t.ok(not body:find("Flow", 1, true), "no Flow in the line past the title: " .. body)
    t.eq(addon.GameOptions.Found(addon, "cameraZoom"), "1.9", "the old distance is kept")
    text = say(c, "setting game.cameraZoom off")
    t.eq(c.gameSetting(CAMERA), "1.9", "put back")
    t.eq(addon.GameOptions.Found(addon, "cameraZoom"), nil, "nothing kept once put back")
    t.ok(text:find("1.9", 1, true) ~= nil, text)
end

tests["g59 e2e: camera, the game keeps a lower limit: the farthest it takes"] = function(t)
    local c = boot({ camera = "1.9", limit = 3.4 })
    if not ready(t, c) then return end
    say(c, "setting game.cameraZoom on")
    t.eq(c.gameSetting(CAMERA), "3.4", "4 refused, 3.4 taken")
    t.eq(c.gameSettingWrites[#c.gameSettingWrites], { CAMERA, "3.4" }, "stops at the first one taken")
end

tests["g59 e2e: camera, the game takes none: said, and off puts the old value back"] = function(t)
    local c = boot({ camera = "1.9", limit = 1.9 })
    if not ready(t, c) then return end
    local text = say(c, "setting game.cameraZoom on")
    t.eq(c.gameSetting(CAMERA), "1.9")
    t.ok(text:find("not changed", 1, true) ~= nil, "the refusal is said: " .. text)
    say(c, "setting game.cameraZoom off")
    t.eq(c.gameSetting(CAMERA), "1.9")
end

tests["g59 e2e: chat timestamps on and off restore what was there, even a format of the player"] = function(t)
    local c = boot({ stamps = "%I:%M " })
    if not ready(t, c) then return end
    say(c, "setting game.chatTimes on")
    t.eq(c.gameSetting(STAMPS), "%H:%M:%S ")
    say(c, "setting game.chatTimes off")
    t.eq(c.gameSetting(STAMPS), "%I:%M ", "the format of the player is back")
    local c2 = boot({ stamps = "none" })
    say(c2, "setting game.chatTimes on")
    say(c2, "setting game.chatTimes off")
    t.eq(c2.gameSetting(STAMPS), "none")
end

tests["g59 e2e: combat log file on writes the file; off stops it only if it was off before"] = function(t)
    local c = boot({ logging = false })
    if not ready(t, c) then return end
    say(c, "setting game.combatLogFile on")
    t.eq(c.combatLogFile(), true)
    say(c, "setting game.combatLogFile off")
    t.eq(c.combatLogFile(), false, "it was off: stopped")
    local c2 = boot({ logging = true })
    say(c2, "setting game.combatLogFile on")
    local text = say(c2, "setting game.combatLogFile off")
    t.eq(c2.combatLogFile(), true, "it was on before: left on")
    t.ok(text:find("left on", 1, true) ~= nil, "a line says so: " .. text)
end

tests["g59 e2e: a found value of false is kept as false, not lost"] = function(t)
    local c, addon = boot({ logging = false })
    if not ready(t, c) then return end
    say(c, "setting game.combatLogFile on")
    t.eq(addon.GameOptions.Found(addon, "combatLogFile"), false)
end

tests["g59 e2e: the game does not say its value: nothing is changed, and it is said"] = function(t)
    local c = boot({ camera = false })
    if not ready(t, c) then return end
    local text = say(c, "setting game.cameraZoom on")
    t.eq(#c.gameSettingWrites, 0, "no write without the value to put back")
    t.ok(text:find("not changed", 1, true) ~= nil, text)
    say(c, "setting game.cameraZoom off")
    t.eq(#c.gameSettingWrites, 0, "nothing to put back")
    local c2 = boot({})
    say(c2, "setting game.combatLogFile on")
    t.eq(#c2.logFileWrites, 0, "logging state not known: not started")
end

tests["g59 e2e: on, a reload, then off: the old value still comes back; nothing at the reload"] = function(t)
    local c = boot({ camera = "1.9" })
    if not ready(t, c) then return end
    say(c, "setting game.cameraZoom on")
    local saved = c.saved(ns.id.accountDB)
    local c2 = boot({ account = saved, camera = c.gameSetting(CAMERA) })
    t.eq(#c2.gameSettingWrites, 0, "nothing written at the reload")
    say(c2, "setting game.cameraZoom off")
    t.eq(c2.gameSetting(CAMERA), "1.9", "the value from before the reload")
end

tests["g59 e2e: on twice before off keeps the first value found"] = function(t)
    local c = boot({ camera = "1.9" })
    if not ready(t, c) then return end
    say(c, "setting game.cameraZoom on")
    say(c, "setting game.cameraZoom on")
    say(c, "setting game.cameraZoom off")
    t.eq(c.gameSetting(CAMERA), "1.9")
end

tests["g59 e2e: a reset of all settings turns them off and puts the values back"] = function(t)
    local c, addon = boot({ camera = "1.9", stamps = "none", logging = false })
    if not ready(t, c) then return end
    say(c, "setting game.cameraZoom on")
    say(c, "setting game.chatTimes on")
    say(c, "setting game.combatLogFile on")
    addon.settings:reset("all")
    t.eq(c.gameSetting(CAMERA), "1.9")
    t.eq(c.gameSetting(STAMPS), "none")
    t.eq(c.combatLogFile(), false)
end

tests["g59 e2e: a write that raises is said, and the old value stays kept for off"] = function(t)
    local c = boot({ camera = "1.9" })
    if not ready(t, c) then return end
    c.setGameSettingFails("raised")
    local text = say(c, "setting game.cameraZoom on")
    t.ok(text:find("not changed", 1, true) ~= nil, text)
    c.setGameSettingFails(nil)
    say(c, "setting game.cameraZoom off")
    t.eq(c.gameSetting(CAMERA), "1.9")
end

tests["g59 e2e: a put-back the game refuses keeps the value for the next try"] = function(t)
    local c, addon = boot({ camera = "1.9" })
    if not ready(t, c) then return end
    say(c, "setting game.cameraZoom on")
    c.setGameSettingFails("raised")
    local text = say(c, "setting game.cameraZoom off")
    t.ok(text:find("not put back", 1, true) ~= nil, text)
    t.eq(addon.GameOptions.Found(addon, "cameraZoom"), "1.9", "kept")
    c.setGameSettingFails(nil)
    say(c, "setting game.cameraZoom on")
    say(c, "setting game.cameraZoom off")
    t.eq(c.gameSetting(CAMERA), "1.9", "the first value found, not the pulled-back one")
end

-- MyBuddy review of ec8514e9 (lead section 266), one regression test each.
-- GO-1: no write in a fight; the change is made when the fight ends.
tests["g59 go-1: turned on or off in a fight, nothing is written until the fight ends"] = function(t)
    local c, addon = boot({ camera = "1.9", logging = false })
    if not ready(t, c) then return end
    c.setCombat(true)
    local text = say(c, "setting game.cameraZoom on")
    say(c, "setting game.combatLogFile on")
    t.eq(writes(c), 0, "nothing written in the fight")
    t.ok(text:find("after the fight", 1, true) ~= nil, "a line says when: " .. text)
    t.eq(addon.GameOptions.Found(addon, "cameraZoom"), nil, "nothing read or kept in the fight")
    c.setCombat(false)
    t.eq(c.gameSetting(CAMERA), "4", "made when the fight ended")
    t.eq(c.combatLogFile(), true)
    c.setCombat(true)
    say(c, "setting game.cameraZoom off")
    t.eq(c.gameSetting(CAMERA), "4", "not put back in the fight")
    c.setCombat(false)
    t.eq(c.gameSetting(CAMERA), "1.9", "put back when the fight ended")
end

tests["g59 go-1: on and off again in the same fight writes nothing at all"] = function(t)
    local c, addon = boot({ camera = "1.9" })
    if not ready(t, c) then return end
    c.setCombat(true)
    say(c, "setting game.cameraZoom on")
    say(c, "setting game.cameraZoom off")
    c.setCombat(false)
    t.eq(writes(c), 0, "the player changed their mind: nothing to do")
    t.eq(addon.GameOptions.Found(addon, "cameraZoom"), nil, "nothing kept")
    t.eq(c.gameSetting(CAMERA), "1.9")
end

tests["g59 go-1: a write the client refuses for the fight is made when it ends"] = function(t)
    local c = boot({ camera = "1.9" })
    if not ready(t, c) then return end
    c.setGameSettingFails("combat")
    say(c, "setting game.cameraZoom on")
    c.setGameSettingFails(nil)
    c.setCombat(true)
    c.setCombat(false)
    t.eq(c.gameSetting(CAMERA), "4", "tried again when the fight ended")
end

-- GO-2: off reads the value first and writes nothing when the read fails.
tests["g59 go-2: off writes nothing when the game does not say its value; kept for the next try"] = function(t)
    local c, addon = boot({ camera = "1.9", logging = false })
    if not ready(t, c) then return end
    say(c, "setting game.cameraZoom on")
    say(c, "setting game.combatLogFile on")
    local before, beforeLog = #c.gameSettingWrites, #c.logFileWrites
    c.putGameSetting(CAMERA, nil)
    c.putCombatLogFile(nil)
    local text = say(c, "setting game.cameraZoom off")
    say(c, "setting game.combatLogFile off")
    t.eq(#c.gameSettingWrites, before, "no camera write without a read")
    t.eq(#c.logFileWrites, beforeLog, "no log file write without a read")
    t.ok(text:find("not put back", 1, true) ~= nil, text)
    t.eq(addon.GameOptions.Found(addon, "cameraZoom"), "1.9", "kept")
    t.eq(addon.GameOptions.Found(addon, "combatLogFile"), false, "kept")
    c.putGameSetting(CAMERA, "4")
    say(c, "setting game.cameraZoom on")
    say(c, "setting game.cameraZoom off")
    t.eq(c.gameSetting(CAMERA), "1.9", "put back on the next try")
end

-- GO-3: on writes nothing when the game already has the value.
tests["g59 go-3: on writes nothing when the value is already the one wanted"] = function(t)
    local c, addon = boot({ camera = "4", stamps = "%H:%M:%S ", logging = true })
    if not ready(t, c) then return end
    say(c, "setting game.cameraZoom on")
    say(c, "setting game.chatTimes on")
    say(c, "setting game.combatLogFile on")
    t.eq(writes(c), 0, "nothing written: nothing to change")
    t.eq(addon.GameOptions.Found(addon, "cameraZoom"), "4", "the value found is still kept")
    say(c, "setting game.cameraZoom off")
    say(c, "setting game.chatTimes off")
    say(c, "setting game.combatLogFile off")
    t.eq(writes(c), 0, "and nothing to put back")
end

return tests
