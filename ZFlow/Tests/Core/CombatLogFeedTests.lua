-- The combat-log feed (lead section 195): which read the client gives for
-- a combat-log event. c.watchCombatLog asks C_CombatLog.GetCurrentEventInfo
-- first and the old global CombatLogGetCurrentEventInfo second. With
-- neither it answers nil and "no log", and the fight log says the client
-- gives add-ons no combat log. The diag capture asks the type of both
-- reads. Hand-built environments and the fake client; every event row is
-- made up. Not tested in game. Needs game test: which of the two reads
-- client 16001 has, and that its values come in the same order.
local _, ns = ...

local EVENT = "COMBAT_LOG_EVENT_UNFILTERED"
local NEW, OLD = "C_CombatLog.GetCurrentEventInfo", "CombatLogGetCurrentEventInfo"

-- An environment with frames that take events. opts.new: a
-- C_CombatLog.GetCurrentEventInfo; opts.old: a CombatLogGetCurrentEventInfo.
-- Each counts its calls in env.newReads and env.oldReads and answers env.row.
-- opts.logTable: what C_CombatLog is, in place of the table with the read.
local function logEnv(opts)
    opts = opts or {}
    local env = { frames = {}, row = {}, newReads = 0, oldReads = 0 }
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return false
    end
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
    if opts.new then
        env.C_CombatLog = { GetCurrentEventInfo = function()
            env.newReads = env.newReads + 1
            return unpack(env.row)
        end }
    end
    if opts.logTable ~= nil then env.C_CombatLog = opts.logTable end
    if opts.old then
        function env.CombatLogGetCurrentEventInfo()
            env.oldReads = env.oldReads + 1
            return unpack(env.row)
        end
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

local function has(list, name)
    for _, n in ipairs(list) do if n == name then return true end end
    return false
end

-- A fight log on the fake client, booted. how: what setCombatLog is given.
local function fightLog(how)
    local c = ns.make.fakeClient()
    c.setCombatLog(how)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local log = ns.FightLog.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, log
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i]:sub(#ns.id.title + 3) end
    return out
end

return {
    -- ------------------------------------------------------------ diag
    ["combat-log feed: the diag name list holds both reads"] = function(t)
        t.ok(has(ns.Diag.NAMES, "C_CombatLog"), "C_CombatLog")
        t.ok(has(ns.Diag.NAMES, NEW), NEW)
        t.ok(has(ns.Diag.NAMES, OLD), OLD)
    end,

    ["combat-log feed: the diag capture asks the type of both reads"] = function(t)
        local c = ns.make.fakeClient()
        c.setSaved(ns.id.accountDB, {})
        local k = ns.Kernel({}, c)
        ns.Diag.Start(k)
        k:Boot()
        local asked = {}
        local typeOf = c.typeOf
        c.typeOf = function(path) asked[path] = true; return typeOf(path) end
        ns.Diag.Collect(k, "feed")
        t.ok(asked[NEW] == true, "asked: " .. NEW)
        t.ok(asked[OLD] == true, "asked: " .. OLD)
    end,

    -- ------------------------------------------------- the real client
    ["combat-log feed: with both reads the C_CombatLog one is read, the old one not"] = function(t)
        local env = logEnv({ new = true, old = true })
        local got = {}
        local c = ns.make.client(env)
        t.eq(c.watchCombatLog(function(...) got[#got + 1] = { ... } end), true)
        env.row = { 1000, "SWING_DAMAGE", false, "Player-1-0000AAAA" }
        env.send(EVENT)
        t.eq(env.newReads, 1)
        t.eq(env.oldReads, 0)
        t.eq(#got, 1)
        t.eq(got[1][2], "SWING_DAMAGE")
    end,

    ["combat-log feed: with only the C_CombatLog read the feed is taken and the values reach the watcher"] = function(t)
        local env = logEnv({ new = true })
        local got = {}
        local c = ns.make.client(env)
        t.eq(c.watchCombatLog(function(...) got[#got + 1] = { n = select("#", ...), ... } end), true)
        t.eq(env.taken(EVENT), true)
        env.row = { 1001, "SPELL_HEAL", false, "Player-1-0000AAAA", "Me" }
        env.send(EVENT)
        t.eq(#got, 1)
        local row = got[1] or {}
        t.eq(row.n, 5)
        t.eq(row[1], 1001)
        t.eq(row[2], "SPELL_HEAL")
        t.eq(row[5], "Me")
    end,

    ["combat-log feed: with only the old read it is still used"] = function(t)
        local env = logEnv({ old = true })
        local got = 0
        local c = ns.make.client(env)
        t.eq(c.watchCombatLog(function() got = got + 1 end), true)
        env.row = { 1000, "SWING_DAMAGE" }
        env.send(EVENT)
        t.eq(env.oldReads, 1)
        t.eq(got, 1)
    end,

    ["combat-log feed: with neither read the answer is nil and no log, and the event is not asked for"] = function(t)
        local env = logEnv()
        local c = ns.make.client(env)
        local ok, why = c.watchCombatLog(function() end)
        t.eq(ok, nil)
        t.eq(why, "no log")
        t.eq(env.taken(EVENT), false)
    end,

    ["combat-log feed: a C_CombatLog that is no table, or has no such function, counts as no read"] = function(t)
        for _, v in ipairs({ "C_CombatLog", 7, true, {}, { GetCurrentEventInfo = "x" } }) do
            local env = logEnv({ logTable = v })
            local ok, why = ns.make.client(env).watchCombatLog(function() end)
            t.eq(ok, nil)
            t.eq(why, "no log")
        end
    end,

    ["combat-log feed: a read there but an event the client will not take is nil and not taken"] = function(t)
        local env = logEnv({ new = true, refuse = EVENT })
        local ok, why = ns.make.client(env).watchCombatLog(function() end)
        t.eq(ok, nil)
        t.eq(why, "not taken")
    end,

    ["combat-log feed: a C_CombatLog read that raises hands nothing on"] = function(t)
        local env = logEnv({ new = true })
        env.C_CombatLog.GetCurrentEventInfo = function() error("no read") end
        local got = 0
        local c = ns.make.client(env)
        t.eq(c.watchCombatLog(function() got = got + 1 end), true)
        env.send(EVENT)
        t.eq(got, 0)
    end,

    -- ------------------------------------------------------- the fake
    ["combat-log feed: the fake says no log after setCombatLog none, and plain nil after false"] = function(t)
        local c = ns.make.fakeClient()
        c.setCombatLog("none")
        local ok, why = c.watchCombatLog(function() end)
        t.eq(ok, nil)
        t.eq(why, "no log")
        c.setCombatLog(false)
        ok, why = c.watchCombatLog(function() end)
        t.eq(ok, nil)
        t.eq(why, nil)
        c.setCombatLog(true)
        t.eq(c.watchCombatLog(function() end), true)
    end,

    -- -------------------------------------------------- the fight log
    ["combat-log feed: with no log, fights says the client gives add-ons no combat log"] = function(t)
        local c, log = fightLog("none")
        t.eq(log.feed(), false)
        t.eq(said(c, "fights"), { ns.FightLog.NO_LOG })
        t.eq(said(c, "fights 2"), { ns.FightLog.NO_LOG })
    end,

    ["combat-log feed: with no log, fights death says the same"] = function(t)
        local c = fightLog("none")
        t.eq(said(c, "fights death"), { ns.FightLog.NO_LOG })
    end,

    ["combat-log feed: a feed not taken still says no read yet"] = function(t)
        local c = fightLog(false)
        t.eq(said(c, "fights"), { ns.FightLog.NO_FEED })
    end,

    ["combat-log feed: the no-log words name the add-ons and no fight, and are not the no-read words"] = function(t)
        local text = ns.FightLog.NO_LOG
        t.eq(type(text), "string")
        t.ok(text ~= ns.FightLog.NO_FEED, "not the no-read words")
        t.ok(tostring(text):find("no combat log", 1, true) ~= nil, "no combat log")
        t.ok(tostring(text):find("add-ons", 1, true) ~= nil, "add-ons")
        t.ok(tostring(text):find("Flow", 1, true) == nil, "no Flow")
    end,

    ["combat-log feed: the probe names both reads"] = function(t)
        local c = fightLog("none")
        c.setApi(NEW, true)
        t.eq(said(c, "fights probe")[1], "probe: combat-log read " .. NEW .. " present, "
            .. OLD .. " absent; feed not taken, the client gives add-ons no combat log;"
            .. " combat-log events since login: 0.")
    end,
}
