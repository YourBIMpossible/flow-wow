-- FightLog: feeds the fight reader (Rotation/Fights.lua) from the client and
-- shows the last fights as text (G29). No frame, no panel. Look-only: it
-- reads the combat log and prints; it changes nothing in the game.
--
--   <slash> fights            the fights of this session, newest first
--   <slash> fights <number>   that fight, with its spells
--   <slash> fights death      what hit you before your last death (G30)
--   <slash> fights probe      what this client gives the fight log: the combat-log
--                             read, the game's damage meter and death recap, hits
--                             on you (RESEARCH-fight-log.md; reads nothing as a number)
--
-- At your death (PLAYER_DEAD) the damage you took in the seconds before is
-- printed, as text. Each fight row also says its type (G28): solo, elite,
-- group, or "type unknown" when it was not read. The elite read is
--   client.targetRank() -> text | nil   the rank word of your target
--
-- A fight is the time between the combat start and the combat end events.
-- The fights are kept in memory only: a fixed number of them (Fights.KEEP),
-- gone at a reload or logout. Nothing of a fight is saved.
--
-- It needs three client reads (Core/Client.lua, the F7 block; the ids go
-- through client.guid). Where the client has no combat-log read the word
-- says that no fight can be recorded:
--   client.watchCombatLog(fn) -> true | nil
--       calls fn with the values of each combat-log event, in the client's
--       own order. nil when the client has no such read.
--   client.playerGUID() -> text | nil    your id, nil when it will not say
--   client.petGUID() -> text | nil       your pet's id, nil with no pet
--
-- Your id and your pet's are read when a fight starts. A pet called or
-- changed in the middle of a fight is counted from the next fight on.
--
--   FightLog.Start(k, diag) -> { fights = fn, feed = fn, death = fn, recorder = rec }
--     fights()  the kept fights, newest first, as fresh copies
--     death()   the last death, nil before any
--     feed()    true when the client's combat-log read was taken
local _, ns = ...

local L = {}
ns.FightLog = L

L.WORD = "fights"
L.HELP = "show the last fights of this session: what you dealt, took and healed;"
    .. " fights <number> lists that fight's spells; fights death shows what hit you before your last death"
L.NO_FEED = "this client build has no combat-log read yet, so no fight can be recorded."
L.PROBE = "probe"
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
    -- For "fights probe" (RESEARCH-fight-log.md): counts since login only.
    local cleuSeen, hitsOnYou, hitsReadable, hitsFollowed = 0, 0, 0, false

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

    local function say(text) client.print(k.id.title .. ": " .. text) end

    -- The rank word of the target you have now, for the fight type. The
    -- reader takes it only while a fight is open.
    local function rank()
        if type(client.targetRank) == "function" then rec:sawRank(client.targetRank()) end
    end

    if type(client.watchCombatLog) == "function" then
        feed = client.watchCombatLog(function(...)
            -- A hit outside a fight is kept for the death report, so your
            -- id is asked for here too until it is known.
            cleuSeen = cleuSeen + 1
            if not rec:knowsMe() then who() end
            rec:event(now(), ...)
        end) == true
    end
    if feed then
        client.listen("PLAYER_REGEN_DISABLED", function()
            who()
            rec:enter(now())
            rank()
        end)
        client.listen("PLAYER_REGEN_ENABLED", function()
            rec:leave(now())
        end)
        client.listen("PLAYER_TARGET_CHANGED", rank)
        client.listen("PLAYER_DEAD", function()
            local lines = ns.Fights.DeathLines(rec:died(now()))
            for i = 1, #lines do say(lines[i]) end
        end)
    end

    if type(client.watchUnitCombat) == "function" then
        hitsFollowed = client.watchUnitCombat(function(unit, readable)
            if unit ~= "player" then return end
            hitsOnYou = hitsOnYou + 1
            if readable then hitsReadable = hitsReadable + 1 end
        end) ~= nil
    end

    -- One line per open question of RESEARCH-fight-log.md. It reads no
    -- game value as a number; it only says what is there.
    local function present(path)
        if type(client.apiPresent) ~= "function" then return "not known" end
        return client.apiPresent(path) and "present" or "absent"
    end
    local function probe()
        say("probe: combat-log read " .. present("CombatLogGetCurrentEventInfo")
            .. "; feed " .. (feed and "taken" or "not taken")
            .. "; combat-log events since login: " .. cleuSeen .. ".")
        say("probe: game damage meter (C_DamageMeter) " .. present("C_DamageMeter")
            .. "; death recap (C_DeathRecap.GetRecapEvents) " .. present("C_DeathRecap.GetRecapEvents") .. ".")
        if hitsFollowed then
            say("probe: hits on you since login (UNIT_COMBAT): " .. hitsOnYou
                .. ", with a readable amount: " .. hitsReadable .. ".")
        else
            say("probe: hits on you (UNIT_COMBAT) are not followed: this client has no such read.")
        end
    end

    local function run(rest)
        if tostring(rest):lower():find(L.PROBE, 1, true) then
            probe()
            return
        end
        if not feed then
            say(L.NO_FEED)
            return
        end
        if tostring(rest):lower():find("death", 1, true) then
            local lines = ns.Fights.DeathLines(rec:death())
            for i = 1, #lines do say(lines[i]) end
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
        death = function() return rec:death() end,
        recorder = rec,
    }
end

-- The addon's own: the word is added when this file loads.
ns.fightLog = L.Start(ns, ns.diag)
