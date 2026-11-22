local _, ns = ...

-- Sound restart (S28): /zflow audioreset restarts the game's sound, and it
-- happens by itself a few seconds after the game says its list of speakers
-- changed, once the changes stop. For when the game stays silent after a
-- monitor's speakers vanish and come back (a sleeping screen, Remote
-- Desktop) while every other program plays.
--
-- Ported from legacy Flow's Modules/Sound.lua (0.35.308), which ran on this
-- client; research: WoW/from-plexy/RESEARCH-sound-restart.md. The game's
-- own restart is the client's (c.restartSound); the console route is used
-- only when the player asked by hand. It changes no game setting and plays
-- nothing.
--
--   Sound.ShouldAuto(on, now, last, recent) -> true, or false and why  (pure)
--   Sound.Lines(ways, on, heard, changes) -> lines for /zflow audioreset
--   Sound.Declare(k, diag) -> api
--     api.changes()   how many speaker changes the game reported this session
--     api.restarts()  the automatic restarts this session, oldest first
--
-- Setting: sound.autoRestart (account, on by default), "Restart the game's
-- sound when your speakers change", as legacy Flow had it.
local Sound = {}
ns.Sound = Sound

Sound.NAME = "sound"
Sound.WORD = "audioreset"
Sound.SETTING = "sound.autoRestart"
Sound.SETTLE = 3      -- seconds with no more changes before the restart
Sound.ECHO = 6        -- seconds after a restart when changes are that restart's own
Sound.MAX_AUTO = 3    -- automatic restarts a minute, at most
Sound.DONE = "restarted the game's sound. Still nothing? Pick your speakers under Output Device in the game's Audio settings."
Sound.FAILED = "couldn't restart the game's sound (%s). Type /console Sound_RestartSoundSystem instead."
Sound.HELP = "restart the game's sound, for when the game is silent and everything else plays"

local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function Sound.ShouldAuto(on, now, last, recent)
    if on ~= true then return false, "the setting is off" end
    if not finite(now) then return false, "the time is not known" end
    if finite(last) and now - last < Sound.ECHO then return false, "that was its own restart" end
    local n = 0
    for _, t in ipairs(type(recent) == "table" and recent or {}) do
        if finite(t) and now - t < 60 then n = n + 1 end
    end
    if n >= Sound.MAX_AUTO then return false, string.format("already restarted %d times this minute", n) end
    return true
end

function Sound.Lines(ways, on, heard, changes)
    ways = type(ways) == "table" and ways or {}
    return {
        "ways to restart it here: " .. (#ways > 0 and table.concat(ways, ", ") or "none"),
        "by itself when your speakers change: " .. (on and "on" or "off")
            .. (heard and "" or " (but this game does not say when they change)")
            .. string.format("; changes seen this session: %d", tonumber(changes) or 0),
    }
end

function Sound.Declare(k, diag)
    local api = {}
    local ctx
    local changes, last, recent, heard = 0, nil, {}, false
    local pending
    function api.changes() return changes end
    function api.restarts()
        local out = {}
        for i = 1, #recent do out[i] = recent[i] end
        return out
    end

    local function client() return (ctx and ctx.client) or k.client end
    local function say(text) client().print(k.id.title .. ": " .. text) end
    local function now()
        local c = client()
        return type(c.uptime) == "function" and c.uptime() or nil
    end

    local function settled()
        pending = nil
        local t = now()
        local go = Sound.ShouldAuto(ctx.settings:get(Sound.SETTING) == true, t, last, recent)
        if not go then return end
        recent[#recent + 1] = t
        while #recent > Sound.MAX_AUTO do table.remove(recent, 1) end
        local c = client()
        if type(c.restartSound) ~= "function" then return end
        local ok, how = c.restartSound(false)
        if ok then last = t else k.problems:add(Sound.NAME, "restart", tostring(how)) end
    end

    local function run()
        local c = client()
        if type(c.restartSound) ~= "function" then
            say(string.format(Sound.FAILED, "this client has no restart"))
        else
            local ok, how = c.restartSound(true)
            if ok then
                last = now()
                say(Sound.DONE)
            else
                say(string.format(Sound.FAILED, tostring(how)))
            end
        end
        local on = ctx and ctx.settings:get(Sound.SETTING) == true
        local ways = type(c.soundWays) == "function" and c.soundWays(true) or {}
        for _, line in ipairs(Sound.Lines(ways, on, heard, changes)) do say(line) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[Sound.WORD] = run
        if type(diag.help) == "table" then diag.help[Sound.WORD] = Sound.HELP end
    end

    k:Module({
        name = Sound.NAME,
        needs = { "client", "store", "settings" },
        settings = { {
            key = Sound.SETTING, scope = "account", type = "bool", default = true,
            label = "Restart the game's sound when your speakers change",
            help = "When your speakers come back after a sleeping screen or Remote Desktop and the game stays silent, "
                .. "restart its sound a few seconds later. The sound may cut out for a moment. " .. k.id.slash .. " audioreset does it by hand.",
            group = "Other",
        } },
        provides = { Changes = api.changes },
        start = function(c)
            ctx = c
            if type(c.client.watchSoundDevices) ~= "function" then return end
            heard = c.client.watchSoundDevices(function()
                changes = changes + 1
                if pending then pending() end
                pending = c.sched:after(Sound.NAME, Sound.SETTLE, settled)
            end) == true
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.sound = Sound.Declare(ns, ns.diag)
