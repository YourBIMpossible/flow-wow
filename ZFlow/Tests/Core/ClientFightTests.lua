-- The reads of the fight log (F7) on the client: guid(), playerGUID(),
-- petGUID(), targetRank() and watchCombatLog(). First the real client over
-- a hand-built environment (env stands in for the globals of the game),
-- then the fake. Every event row is written by hand. Not tested in game.
local _, ns = ...

local EVENT = "COMBAT_LOG_EVENT_UNFILTERED"
local ME, MOB = "Player-1-0000AAAA", "Creature-0-1-0000CCCC"

local function boom() error("the client refused") end

-- An issecretvalue that refuses nil, as the one of the client does.
local function strictSecret(env, secret)
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return secret ~= nil and secret(v) or false
    end
end

-- An environment with frames that take events. env.send(name, ...) is the
-- client raising an event; env.row is what the combat-log read answers
-- (env.rowN values of it; all of it when rowN is nil). opts.refuse: an
-- event name the client will not take.
local function logEnv(opts)
    opts = opts or {}
    local env = { frames = {}, row = {}, reads = 0 }
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:RegisterEvent(name)
            if name == opts.refuse then error("no such event") end
            self.events[name] = true
        end
        function f:UnregisterEvent(name) self.events[name] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    function env.CombatLogGetCurrentEventInfo()
        env.reads = env.reads + 1
        if env.fail then error("no read") end
        return unpack(env.row, 1, env.rowN or #env.row)
    end
    function env.taken(name)
        for _, f in ipairs(env.frames) do
            if f.events[name] then return true end
        end
        return false
    end
    function env.send(name, ...)
        for _, f in ipairs(env.frames) do
            if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f, name, ...) end
        end
    end
    return env
end

local function swing(src, srcName, dst, dstName, amount)
    return { 1000, "SWING_DAMAGE", false, src, srcName, 0, 0, dst, dstName, 0, 0, amount }
end

return {
    -- ------------------------------------------------------------- guid
    ["client guid: the id of you, your pet and your target, as the client gives it"] = function(t)
        local asked = {}
        local env = { UnitGUID = function(unit)
            asked[#asked + 1] = unit
            return "id-" .. unit
        end }
        strictSecret(env)
        local c = ns.make.client(env)
        t.eq(c.guid("player"), "id-player")
        t.eq(c.guid("pet"), "id-pet")
        t.eq(c.guid("target"), "id-target")
        t.eq(asked, { "player", "pet", "target" })
    end,

    ["client guid: no other unit is asked about"] = function(t)
        local asked = 0
        local c = ns.make.client({ UnitGUID = function()
            asked = asked + 1
            return "id"
        end })
        for _, unit in ipairs({ "party1", "raid3", "focus", "mouseover", "targettarget", "nameplate1", "Player", "" }) do
            t.eq(c.guid(unit), nil, unit)
        end
        t.eq(c.guid(nil), nil)
        t.eq(c.guid(1), nil)
        t.eq(c.guid({}), nil)
        t.eq(asked, 0)
    end,

    ["client guid: not known without the call, on a failure, or on anything but text"] = function(t)
        t.eq(ns.make.client({}).guid("player"), nil, "no call")
        t.eq(ns.make.client({ UnitGUID = boom }).guid("player"), nil, "a failed call")
        t.eq(ns.make.client({ UnitGUID = function() return nil end }).guid("pet"), nil, "no pet")
        t.eq(ns.make.client({ UnitGUID = function() return "" end }).guid("player"), nil, "empty text")
        t.eq(ns.make.client({ UnitGUID = function() return 12 end }).guid("player"), nil)
        t.eq(ns.make.client({ UnitGUID = function() return true end }).guid("player"), nil)
    end,

    ["client guid: a secret id is not known"] = function(t)
        local env = { UnitGUID = function() return ME end }
        strictSecret(env, function() return true end)
        t.eq(ns.make.client(env).guid("player"), nil)
    end,

    ["client playerGUID and petGUID go through guid"] = function(t)
        local asked = {}
        local c = ns.make.client({ UnitGUID = function(unit)
            asked[#asked + 1] = unit
            return unit == "player" and ME or nil
        end })
        t.eq(c.playerGUID(), ME)
        t.eq(c.petGUID(), nil)
        t.eq(asked, { "player", "pet" })
        c.guid = function(unit) return "through-" .. unit end
        t.eq(c.playerGUID(), "through-player")
        t.eq(c.petGUID(), "through-pet")
    end,

    -- ------------------------------------------------------- targetRank
    ["client targetRank: the word the client gives, asked only about your target"] = function(t)
        local asked = {}
        local env = { UnitClassification = function(unit)
            asked[#asked + 1] = unit
            return "rareelite"
        end }
        strictSecret(env)
        t.eq(ns.make.client(env).targetRank(), "rareelite")
        t.eq(asked, { "target" })
    end,

    ["client targetRank: not known without the call, on a failure, or on anything but a word"] = function(t)
        t.eq(ns.make.client({}).targetRank(), nil, "no call")
        t.eq(ns.make.client({ UnitClassification = boom }).targetRank(), nil, "a failed call")
        t.eq(ns.make.client({ UnitClassification = function() return nil end }).targetRank(), nil)
        t.eq(ns.make.client({ UnitClassification = function() return "" end }).targetRank(), nil)
        t.eq(ns.make.client({ UnitClassification = function() return 3 end }).targetRank(), nil)
    end,

    ["client targetRank: a secret word is not known"] = function(t)
        local env = { UnitClassification = function() return "elite" end }
        strictSecret(env, function() return true end)
        t.eq(ns.make.client(env).targetRank(), nil)
    end,

    -- --------------------------------------------------- watchCombatLog
    ["client watchCombatLog: the values of each event reach the watcher, in the order of the client"] = function(t)
        local env = logEnv()
        strictSecret(env)
        local got = {}
        local c = ns.make.client(env)
        t.eq(c.watchCombatLog(function(...) got[#got + 1] = { n = select("#", ...), ... } end), true)
        t.eq(env.taken(EVENT), true)
        env.row = swing(ME, "Me", MOB, "Mob", 25)
        env.send(EVENT)
        env.row = { 1001, "SPELL_HEAL", false, ME, "Me" }
        env.send(EVENT)
        t.eq(#got, 2)
        t.eq(got[1].n, 12)
        t.eq(got[1][1], 1000)
        t.eq(got[1][2], "SWING_DAMAGE")
        t.eq(got[1][3], false, "a false stays false")
        t.eq(got[1][4], ME)
        t.eq(got[1][8], MOB)
        t.eq(got[1][12], 25)
        t.eq(got[2].n, 5, "nothing of the longer event before it is left over")
        t.eq(got[2][2], "SPELL_HEAL")
        t.eq(got[2][12], nil)
    end,

    ["client watchCombatLog: a gap in the values stays a gap"] = function(t)
        local env = logEnv()
        strictSecret(env)
        local got
        ns.make.client(env).watchCombatLog(function(...) got = { n = select("#", ...), ... } end)
        env.row = { 1000, "SPELL_DAMAGE", nil, ME, nil, 0 }
        env.rowN = 6
        env.send(EVENT)
        t.eq(got.n, 6)
        t.eq(got[3], nil)
        t.eq(got[5], nil)
        t.eq(got[4], ME)
        t.eq(got[6], 0)
    end,

    ["client watchCombatLog: a secret value is handed over as nothing"] = function(t)
        local env = logEnv()
        strictSecret(env, function(v) return v == 777 end)
        local got
        ns.make.client(env).watchCombatLog(function(...) got = { n = select("#", ...), ... } end)
        env.row = swing(ME, "Me", MOB, "Mob", 777)
        env.send(EVENT)
        t.eq(got.n, 12)
        t.eq(got[12], nil)
        t.eq(got[2], "SWING_DAMAGE")
    end,

    ["client watchCombatLog: a read that fails does not reach the watcher, and the next one does"] = function(t)
        local env = logEnv()
        local calls = 0
        ns.make.client(env).watchCombatLog(function() calls = calls + 1 end)
        env.fail = true
        env.send(EVENT)
        t.eq(calls, 0)
        t.eq(env.reads, 1)
        env.fail = false
        env.row = { 1000, "SWING_DAMAGE" }
        env.send(EVENT)
        t.eq(calls, 1)
    end,

    ["client watchCombatLog: what the event itself carries is not what is handed over"] = function(t)
        local env = logEnv()
        local got
        ns.make.client(env).watchCombatLog(function(...) got = { ... } end)
        env.row = { 1000, "SWING_DAMAGE" }
        env.send(EVENT, "not", "these")
        t.eq(got, { 1000, "SWING_DAMAGE" })
    end,

    ["client watchCombatLog: nil when the client has no combat-log read"] = function(t)
        local env = logEnv()
        env.CombatLogGetCurrentEventInfo = nil
        local calls = 0
        t.eq(ns.make.client(env).watchCombatLog(function() calls = calls + 1 end), nil)
        t.eq(env.taken(EVENT), false, "the event is not asked for")
        env.send(EVENT)
        t.eq(calls, 0)
    end,

    ["client watchCombatLog: nil when the client does not take the event"] = function(t)
        local env = logEnv({ refuse = EVENT })
        local c = ns.make.client(env)
        local calls = 0
        t.eq(c.watchCombatLog(function() calls = calls + 1 end), nil)
        t.eq(c.watchCombatLog(function() calls = calls + 1 end), nil, "and again")
        t.eq(env.taken(EVENT), false)
        t.eq(calls, 0)
    end,

    ["client watchCombatLog: nil with no frame to hear events on"] = function(t)
        local env = { CombatLogGetCurrentEventInfo = function() return 1 end }
        t.eq(ns.make.client(env).watchCombatLog(function() end), nil)
    end,

    ["client watchCombatLog: nil for a watcher that is no function, and the client is not asked"] = function(t)
        local env = logEnv()
        local c = ns.make.client(env)
        t.eq(c.watchCombatLog(nil), nil)
        t.eq(c.watchCombatLog("fn"), nil)
        t.eq(env.taken(EVENT), false)
    end,

    ["client watchCombatLog: two watchers both hear each event"] = function(t)
        local env = logEnv()
        local c = ns.make.client(env)
        local a, b = 0, 0
        t.eq(c.watchCombatLog(function() a = a + 1 end), true)
        t.eq(c.watchCombatLog(function() b = b + 1 end), true)
        env.row = { 1000, "SWING_DAMAGE" }
        env.send(EVENT)
        t.eq({ a, b }, { 1, 1 })
    end,

    -- -------------------------------------------------------------- fake
    ["fake client: ids start not known and follow setGuid, for the three units only"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.guid("player"), nil)
        t.eq(c.playerGUID(), nil)
        t.eq(c.petGUID(), nil)
        c.setGuid("player", ME)
        c.setGuid("pet", "Pet-0-1-0000BBBB")
        c.setGuid("target", MOB)
        c.setGuid("party1", "Player-1-0000DDDD")
        t.eq(c.playerGUID(), ME)
        t.eq(c.petGUID(), "Pet-0-1-0000BBBB")
        t.eq(c.guid("target"), MOB)
        t.eq(c.guid("party1"), nil)
        c.setGuid("pet", nil)
        t.eq(c.petGUID(), nil)
    end,

    ["fake client: the target rank starts not known and follows its setter"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.targetRank(), nil)
        c.setTargetRank("elite")
        t.eq(c.targetRank(), "elite")
        c.setTargetRank(nil)
        t.eq(c.targetRank(), nil)
    end,

    ["fake client: combatLog hands its values to every watcher"] = function(t)
        local c = ns.make.fakeClient()
        local got = {}
        t.eq(c.watchCombatLog(function(...) got[#got + 1] = { ... } end), true)
        t.eq(c.watchCombatLog("fn"), nil)
        c.combatLog(1000, "SWING_DAMAGE", false, "a")
        t.eq(got, { { 1000, "SWING_DAMAGE", false, "a" } })
    end,

    ["fake client: with the combat log switched off there is no feed"] = function(t)
        local c = ns.make.fakeClient()
        c.setCombatLog(false)
        local calls = 0
        t.eq(c.watchCombatLog(function() calls = calls + 1 end), nil)
        c.combatLog(1000, "SWING_DAMAGE")
        t.eq(calls, 0)
    end,

    -- ----------------------------------- the fight log on the reads of the fake
    ["fight log on the reads of the fake: a fight is recorded from fed events"] = function(t)
        local c = ns.make.fakeClient()
        c.setGuid("player", ME)
        c.setTargetRank("elite")
        local k = ns.Kernel({}, c)
        local d = ns.Diag.Start(k)
        local log = ns.FightLog.Start(k, d)
        k:Boot()
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(log.feed(), true)
        c.setCombat(true)
        c.combatLog(unpack(swing(ME, "Me", MOB, "Mob", 25), 1, 12))
        c.combatLog(unpack(swing(MOB, "Mob", ME, "Me", 7), 1, 12))
        c.setCombat(false)
        local fights = log.fights()
        t.eq(#fights, 1)
        t.eq(fights[1].dealt.total, 25)
        t.eq(fights[1].taken.total, 7)
        t.eq(fights[1].elite, true)
    end,

    ["fight log on the reads of the fake: with no feed the word says so"] = function(t)
        local c = ns.make.fakeClient()
        c.setCombatLog(false)
        local k = ns.Kernel({}, c)
        local d = ns.Diag.Start(k)
        local log = ns.FightLog.Start(k, d)
        k:Boot()
        t.eq(log.feed(), false)
        d.commands[ns.FightLog.WORD]("")
        t.ok(c.printed[#c.printed]:find(ns.FightLog.NO_FEED, 1, true) ~= nil)
    end,
}
