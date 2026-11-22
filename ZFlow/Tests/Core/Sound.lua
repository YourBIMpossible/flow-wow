-- S28 sound restart (Core/Sound.lua; WoW/from-plexy/RESEARCH-sound-restart.md):
-- the pure rule, the word, and the restart after the speakers change.
local _, ns = ...

local S = ns.Sound

local function start(cfg)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setSound(cfg or { ways = { "Sound_GameSystem_RestartSoundSystem" } })
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = S.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i]:sub(#ns.id.title + 3) end
    return out
end

local tests = {}

tests["sound: the rule restarts once things settle, not on its own echo, not too often"] = function(t)
    t.eq(S.ShouldAuto(true, 100, nil, {}), true)
    t.eq(select(2, S.ShouldAuto(false, 100, nil, {})), "the setting is off")
    t.eq(select(2, S.ShouldAuto(true, 100, 96, {})), "that was its own restart")
    t.eq(S.ShouldAuto(true, 100, 90, {}), true, "long enough after")
    t.eq(select(2, S.ShouldAuto(true, 100, nil, { 50, 60, 70 })), "already restarted 3 times this minute")
    t.eq(S.ShouldAuto(true, 100, nil, { 10, 60, 70 }), true, "one of them is older than a minute")
    t.eq(select(2, S.ShouldAuto(true, nil, nil, {})), "the time is not known")
end

tests["sound: /zflow audioreset restarts by hand and says how it can"] = function(t)
    local _, c = start({ ways = { "Sound_GameSystem_RestartSoundSystem", "the console's Sound_RestartSoundSystem" } })
    local lines = said(c, "audioreset")
    t.eq(lines[1], S.DONE)
    t.eq(lines[2], "ways to restart it here: Sound_GameSystem_RestartSoundSystem, the console's Sound_RestartSoundSystem")
    t.ok(lines[3]:find("by itself when your speakers change: on", 1, true) ~= nil, lines[3])
    t.eq(c.restarted()[1].byHand, true)
end

tests["sound: a restart that fails says why and what to type"] = function(t)
    local _, c = start({ fail = "blocked" })
    t.eq(said(c, "audioreset")[1], string.format(S.FAILED, "blocked"))
    local _, c2 = start({ ways = {} })
    t.eq(said(c2, "audioreset")[1], string.format(S.FAILED, "this game gives add-ons no way to restart its sound"))
end

tests["sound: speakers changing restarts it once, a few seconds after the last change"] = function(t)
    local _, c, api = start()
    c.speakersChanged()
    c.advance(1)
    c.speakersChanged()
    c.advance(2)
    t.eq(#c.restarted(), 0, "still changing")
    c.advance(2)
    t.eq(#c.restarted(), 1)
    t.eq(c.restarted()[1].byHand, false, "the console route is only for a restart by hand")
    t.eq(api.changes(), 2)
    t.eq(#api.restarts(), 1)
end

tests["sound: the change its own restart causes does not start another"] = function(t)
    local _, c = start()
    c.speakersChanged()
    c.advance(4)
    t.eq(#c.restarted(), 1)
    c.speakersChanged()
    c.advance(4)
    t.eq(#c.restarted(), 1, "within the echo time")
end

tests["sound: with the setting off nothing restarts by itself"] = function(t)
    local k, c = start()
    t.eq(k.settings:get(S.SETTING), true, "on by default")
    t.eq(k.settings:set(S.SETTING, false), true)
    c.speakersChanged()
    c.advance(4)
    t.eq(#c.restarted(), 0)
end

tests["sound: a client that does not say when speakers change still has the word"] = function(t)
    local _, c = start({ ways = { "Sound_GameSystem_RestartSoundSystem" }, noEvent = true })
    local lines = said(c, "audioreset")
    t.eq(lines[1], S.DONE)
    t.ok(lines[3]:find("but this game does not say when they change", 1, true) ~= nil, lines[3])
end

tests["sound client: the console route only by hand, and the event is taken"] = function(t)
    local calls = {}
    local frames = {}
    local env = {
        Sound_GameSystem_RestartSoundSystem = function() calls[#calls + 1] = "game" end,
        ConsoleExec = function(cmd) calls[#calls + 1] = cmd end,
    }
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        frames[#frames + 1] = f
        return f
    end
    local c = ns.make.client(env)
    t.eq(c.soundWays(false), { "Sound_GameSystem_RestartSoundSystem" })
    t.eq(#c.soundWays(true), 2)
    t.eq(c.restartSound(false), true)
    env.Sound_GameSystem_RestartSoundSystem = function() error("no") end
    local ok, how = c.restartSound(true)
    t.eq({ ok, how }, { true, "the console's Sound_RestartSoundSystem" })
    t.eq(calls, { "game", "Sound_RestartSoundSystem" })
    local heard = 0
    t.eq(c.watchSoundDevices(function() heard = heard + 1 end), true)
    for _, f in ipairs(frames) do
        if f.events.SOUND_DEVICE_UPDATE then f.scripts.OnEvent(f, "SOUND_DEVICE_UPDATE") end
    end
    t.eq(heard, 1)
end

return tests
