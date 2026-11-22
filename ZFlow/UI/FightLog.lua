-- FightLog: feeds the fight reader (Rotation/Fights.lua) from the client and
-- shows the last fights as text (G29). No frame, no panel. Look-only: it
-- reads the combat log and prints; it changes nothing in the game.
--
--   <slash> fights            the fights of this session, newest first
--   <slash> fights <number>   that fight, with its spells
--
-- A fight is the time between the combat start and the combat end events.
-- The fights are kept in memory only: a fixed number of them (Fights.KEEP),
-- gone at a reload or logout. Nothing of a fight is saved.
--
-- It needs three client reads that Core/Client.lua does not have yet
-- (CLIENT NEED, posted with this file); until they are there the word says
-- that no fight can be recorded:
--   client.watchCombatLog(fn) -> true | nil
--       calls fn with the values of each combat-log event, in the client's
--       own order. nil when the client has no such read.
--   client.playerGUID() -> text | nil    your id, nil when it will not say
--   client.petGUID() -> text | nil       your pet's id, nil with no pet
--
-- Your id and your pet's are read when a fight starts. A pet called or
-- changed in the middle of a fight is counted from the next fight on.
--
--   FightLog.Start(k, diag) -> { fights = fn, feed = fn, recorder = rec }
--     fights()  the kept fights, newest first, as fresh copies
--     feed()    true when the client's combat-log read was taken
local _, ns = ...

local L = {}
ns.FightLog = L

L.WORD = "fights"
L.HELP = "show the last fights of this session: what you dealt, took and healed;"
    .. " fights <number> lists that fight's spells"
L.NO_FEED = "this client build has no combat-log read yet, so no fight can be recorded."
L.NO_ME = "the client did not say who you are, so nothing in these fights could be counted as yours."

local function read(fn)
    if type(fn) ~= "function" then return nil end
    local value = fn()
    return (type(value) == "string" and value ~= "") and value or nil
end

-- Starts the recording on kernel k and adds the word to the slash command.
-- diag (optional) is what Diag.Start returned.
function L.Start(k, diag)
    local client = k.client
    local rec = ns.Fights.New()
    local feed = false
    local me

    local function now()
        if type(client.uptime) ~= "function" then return nil end
        return client.uptime()
    end

    -- Your own id does not change in a session, so one that was read is
    -- kept when a later read fails. The pet's is whatever is read now.
    local function who()
        me = read(client.playerGUID) or me
        rec:setMe(me, read(client.petGUID))
    end

    if type(client.watchCombatLog) == "function" then
        feed = client.watchCombatLog(function(...)
            rec:event(now(), ...)
        end) == true
    end
    if feed then
        client.listen("PLAYER_REGEN_DISABLED", function()
            who()
            rec:enter(now())
        end)
        client.listen("PLAYER_REGEN_ENABLED", function()
            rec:leave(now())
        end)
    end

    local function run(rest)
        local function say(text) client.print(k.id.title .. ": " .. text) end
        if not feed then
            say(L.NO_FEED)
            return
        end
        local list = rec:list()
        local lines = ns.Fights.Lines(list, now(), tonumber(tostring(rest):match("%d+")))
        for i = 1, #lines do say(lines[i]) end
        if #list > 0 and not rec:knowsMe() then say(L.NO_ME) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[L.WORD] = run
        if type(diag.help) == "table" then diag.help[L.WORD] = L.HELP end
    end

    return {
        fights = function() return rec:list() end,
        feed = function() return feed end,
        recorder = rec,
    }
end

-- The addon's own: the word is added when this file loads.
ns.fightLog = L.Start(ns, ns.diag)
