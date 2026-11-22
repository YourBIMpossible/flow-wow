-- /zflow fights probe (F7, LEDGER 134; WoW/from-plexy/RESEARCH-fight-log.md):
-- one line per open question about what this client gives the fight log.
-- Hand-made fakes only; nothing here is from a real fight.
local _, ns = ...

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local watchers = {}
    c.watchCombatLog = nil
    if opts.feed then
        function c.watchCombatLog(fn)
            watchers[#watchers + 1] = fn
            return true
        end
    end
    function c.combatLog() for i = 1, #watchers do watchers[i](1000, "SWING_DAMAGE") end end
    if opts.noUnitCombat then c.watchUnitCombat = nil end
    if opts.noApiRead then c.apiPresent = nil end
    for _, path in ipairs(opts.apis or {}) do c.setApi(path, true) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    ns.FightLog.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i]:sub(#ns.id.title + 3) end
    return out
end

return {
    ["fights probe: a client with none of the reads says each one is absent"] = function(t)
        local c = start()
        t.eq(said(c, "fights probe"), {
            "probe: combat-log read absent; feed not taken; combat-log events since login: 0.",
            "probe: game damage meter (C_DamageMeter) absent; death recap (C_DeathRecap.GetRecapEvents) absent.",
            "probe: hits on you since login (UNIT_COMBAT): 0, with a readable amount: 0.",
        })
    end,

    ["fights probe: present reads, the feed taken and its events counted"] = function(t)
        local c = start({ feed = true, apis = { "CombatLogGetCurrentEventInfo", "C_DamageMeter", "C_DeathRecap.GetRecapEvents" } })
        c.combatLog()
        c.combatLog()
        local lines = said(c, "fights probe")
        t.eq(lines[1], "probe: combat-log read present; feed taken; combat-log events since login: 2.")
        t.eq(lines[2], "probe: game damage meter (C_DamageMeter) present; death recap (C_DeathRecap.GetRecapEvents) present.")
    end,

    ["fights probe: hits on you are counted, readable or not; others' are not"] = function(t)
        local c = start()
        c.unitCombat("player", true)
        c.unitCombat("player", false)
        c.unitCombat("player", false)
        c.unitCombat("target", true)
        c.unitCombat(nil, true)
        t.eq(said(c, "fights probe")[3], "probe: hits on you since login (UNIT_COMBAT): 3, with a readable amount: 1.")
    end,

    ["fights probe: a client without the reads says so, not absent"] = function(t)
        local c = start({ noUnitCombat = true, noApiRead = true })
        local lines = said(c, "fights probe")
        t.eq(lines[1], "probe: combat-log read not known; feed not taken; combat-log events since login: 0.")
        t.eq(lines[3], "probe: hits on you (UNIT_COMBAT) are not followed: this client has no such read.")
    end,

    ["fights probe: with no feed, plain fights still says there is no read"] = function(t)
        local c = start()
        t.eq(said(c, "fights"), { ns.FightLog.NO_FEED })
    end,

    ["client probe reads: apiPresent looks without calling; watchUnitCombat hands on no amount"] = function(t)
        local called = 0
        local env = { C_DeathRecap = { GetRecapEvents = function() called = called + 1 end }, C_DamageMeter = {} }
        local frames = {}
        function env.CreateFrame()
            local f = { scripts = {}, events = {} }
            function f:SetScript(name, fn) self.scripts[name] = fn end
            function f:RegisterEvent(e) self.events[e] = true end
            function f:UnregisterEvent(e) self.events[e] = nil end
            frames[#frames + 1] = f
            return f
        end
        local c = ns.make.client(env)
        t.eq(c.apiPresent("C_DeathRecap.GetRecapEvents"), true)
        t.eq(c.apiPresent("C_DamageMeter"), true)
        t.eq(c.apiPresent("CombatLogGetCurrentEventInfo"), false)
        t.eq(c.apiPresent("C_DamageMeter.Nope.Deeper"), false)
        t.eq(c.apiPresent(""), false)
        t.eq(called, 0, "nothing was called")
        local got = {}
        c.watchUnitCombat(function(...) got[#got + 1] = { ... } end)
        local secret = {}
        env.issecretvalue = function(v) return secret[v] == true end
        for _, f in ipairs(frames) do
            if f.events.UNIT_COMBAT then
                f.scripts.OnEvent(f, "UNIT_COMBAT", "player", "WOUND", "", 12, 1)
                secret[30] = true
                f.scripts.OnEvent(f, "UNIT_COMBAT", "player", "WOUND", "", 30, 1)
                f.scripts.OnEvent(f, "UNIT_COMBAT", "player", "MISS", "", nil, 1)
            end
        end
        t.eq(got, { { "player", true }, { "player", false }, { "player", false } })
    end,
}
